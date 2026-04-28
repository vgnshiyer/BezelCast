@preconcurrency import AVFoundation
import CoreVideo

/// AVCaptureVideoDataOutput sample-buffer delegate. Per Apple TN2445, holding
/// onto a CMSampleBuffer for too long causes AVFoundation to stop delivering
/// frames *to all outputs of the session*, including the preview layer. So:
///
/// 1. As soon as a sample arrives, copy its pixel buffer into a private pool
///    we own. The capture sample's IOSurface is released the moment the
///    delegate returns, freeing the upstream pipeline.
/// 2. Hand the copy off to a dedicated recorder queue (with a 1-frame in-
///    flight cap) so a slow CIImage composite + HEVC-with-alpha encode can't
///    push back on the video-data queue.
final class FrameTap: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var recorder: BezelRecorder?
    private var hasFiredFirstFrame = false
    private var firstFrameCallback: (@Sendable (CGSize) -> Void)?
    private var nextFrameCallback: (@Sendable (CVPixelBuffer) -> Void)?

    /// Private CVPixelBufferPool. Inputs get copied here in their source pixel
    /// format so the upstream AVCapture pool is never held by CI/VT work.
    private var copyPool: CVPixelBufferPool?
    private var copyPoolWidth: Int = 0
    private var copyPoolHeight: Int = 0
    private var copyPoolPixelFormat: OSType = 0

    private let recorderQueue = DispatchQueue(label: "BezelCast.recorder", qos: .userInitiated)
    private var inFlightCount = 0  // guarded by lock

    func setRecorder(_ recorder: BezelRecorder?) {
        lock.lock(); defer { lock.unlock() }
        self.recorder = recorder
    }

    func setOnFirstFrame(_ callback: (@Sendable (CGSize) -> Void)?) {
        lock.lock(); defer { lock.unlock() }
        firstFrameCallback = callback
        hasFiredFirstFrame = false
    }

    func setOnNextFrame(_ callback: (@Sendable (CVPixelBuffer) -> Void)?) {
        lock.lock(); defer { lock.unlock() }
        nextFrameCallback = callback
    }

    func cancelNextFrame() -> Bool {
        lock.lock(); defer { lock.unlock() }
        let hadCallback = nextFrameCallback != nil
        nextFrameCallback = nil
        return hadCallback
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let sourceBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let width = CVPixelBufferGetWidth(sourceBuffer)
        let height = CVPixelBufferGetHeight(sourceBuffer)
        let size = CGSize(width: width, height: height)

        // Copy out of the shared capture pool ASAP. After this returns, the
        // sample's IOSurface goes back to AVFoundation for the preview layer
        // and the next frame.
        guard let copy = copyOutOfCapturePool(source: sourceBuffer, width: width, height: height) else { return }

        lock.lock()
        let recorder = self.recorder
        let nextFrameCB = nextFrameCallback
        nextFrameCallback = nil
        var firstCB: (@Sendable (CGSize) -> Void)?
        if !hasFiredFirstFrame, let cb = firstFrameCallback {
            hasFiredFirstFrame = true
            firstCB = cb
            firstFrameCallback = nil
        }
        // Cap recorder backlog at 1 frame in flight. If the recorder is
        // behind, drop the new frame — AVAssetWriter handles timestamp gaps
        // gracefully, and dropping is far better than holding pool buffers
        // and freezing the preview.
        let shouldSubmit = recorder != nil && inFlightCount < 1
        if shouldSubmit { inFlightCount += 1 }
        lock.unlock()

        if shouldSubmit, let recorder {
            recorderQueue.async { [weak self] in
                recorder.receive(buffer: copy, presentationTime: pts)
                guard let self else { return }
                self.lock.lock()
                self.inFlightCount -= 1
                self.lock.unlock()
            }
        }
        nextFrameCB?(copy)
        firstCB?(size)
    }

    /// Returns a freshly-allocated CVPixelBuffer (from our private pool) with
    /// the same pixel data as `source`. The caller can hold the result
    /// indefinitely without affecting AVCapture's frame delivery.
    private func copyOutOfCapturePool(source: CVPixelBuffer, width: Int, height: Int) -> CVPixelBuffer? {
        let pixelFormat = CVPixelBufferGetPixelFormatType(source)
        if copyPool == nil || copyPoolWidth != width || copyPoolHeight != height || copyPoolPixelFormat != pixelFormat {
            let pixelAttrs: [CFString: Any] = [
                kCVPixelBufferPixelFormatTypeKey: pixelFormat,
                kCVPixelBufferWidthKey: width,
                kCVPixelBufferHeightKey: height,
                kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
                kCVPixelBufferMetalCompatibilityKey: true,
            ]
            let poolAttrs: [CFString: Any] = [
                kCVPixelBufferPoolMinimumBufferCountKey: 4,
            ]
            var pool: CVPixelBufferPool?
            let status = CVPixelBufferPoolCreate(nil,
                                                 poolAttrs as CFDictionary,
                                                 pixelAttrs as CFDictionary,
                                                 &pool)
            guard status == kCVReturnSuccess, let pool else { return nil }
            copyPool = pool
            copyPoolWidth = width
            copyPoolHeight = height
            copyPoolPixelFormat = pixelFormat
        }

        var dest: CVPixelBuffer?
        let result = CVPixelBufferPoolCreatePixelBuffer(nil, copyPool!, &dest)
        guard result == kCVReturnSuccess, let dest else { return nil }

        guard CVPixelBufferLockBaseAddress(source, .readOnly) == kCVReturnSuccess else { return nil }
        guard CVPixelBufferLockBaseAddress(dest, []) == kCVReturnSuccess else {
            CVPixelBufferUnlockBaseAddress(source, .readOnly)
            return nil
        }
        defer {
            CVPixelBufferUnlockBaseAddress(dest, [])
            CVPixelBufferUnlockBaseAddress(source, .readOnly)
        }

        if CVPixelBufferIsPlanar(source) {
            let planeCount = CVPixelBufferGetPlaneCount(source)
            guard CVPixelBufferGetPlaneCount(dest) == planeCount else { return nil }

            for plane in 0..<planeCount {
                guard let srcPtr = CVPixelBufferGetBaseAddressOfPlane(source, plane),
                      let dstPtr = CVPixelBufferGetBaseAddressOfPlane(dest, plane) else { return nil }

                let srcRowBytes = CVPixelBufferGetBytesPerRowOfPlane(source, plane)
                let dstRowBytes = CVPixelBufferGetBytesPerRowOfPlane(dest, plane)
                let rows = min(CVPixelBufferGetHeightOfPlane(source, plane),
                               CVPixelBufferGetHeightOfPlane(dest, plane))
                let bytesPerRow = min(srcRowBytes, dstRowBytes)

                for row in 0..<rows {
                    let s = srcPtr.advanced(by: row * srcRowBytes)
                    let d = dstPtr.advanced(by: row * dstRowBytes)
                    memcpy(d, s, bytesPerRow)
                }
            }
            return dest
        }

        guard let srcPtr = CVPixelBufferGetBaseAddress(source),
              let dstPtr = CVPixelBufferGetBaseAddress(dest) else { return nil }

        let srcRowBytes = CVPixelBufferGetBytesPerRow(source)
        let dstRowBytes = CVPixelBufferGetBytesPerRow(dest)

        if srcRowBytes == dstRowBytes {
            memcpy(dstPtr, srcPtr, srcRowBytes * height)
        } else {
            // Strides differ — copy row by row using the smaller stride.
            let bytesPerRow = min(srcRowBytes, dstRowBytes)
            for row in 0..<height {
                let s = srcPtr.advanced(by: row * srcRowBytes)
                let d = dstPtr.advanced(by: row * dstRowBytes)
                memcpy(d, s, bytesPerRow)
            }
        }
        return dest
    }
}
