@preconcurrency import AVFoundation
import CoreVideo
import CoreImage

final class BezelRecorder: @unchecked Sendable {
    private let outputURL: URL
    private let renderer: BezelRenderer
    private let profile: DeviceProfile
    private let customFrame: CIImage?

    private let lock = NSLock()
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var started = false
    private var stopped = false

    init(url: URL, renderer: BezelRenderer, profile: DeviceProfile, customFrame: CIImage?) {
        self.outputURL = url
        self.renderer = renderer
        self.profile = profile
        self.customFrame = customFrame
    }

    func receive(buffer: CVPixelBuffer, presentationTime: CMTime) {
        lock.lock()
        defer { lock.unlock() }
        guard !stopped else { return }

        if !started {
            startWriting(time: presentationTime)
        }

        guard started, let adaptor, let pool = adaptor.pixelBufferPool,
              let input, input.isReadyForMoreMediaData else { return }

        var outputBuffer: CVPixelBuffer?
        let result = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &outputBuffer)
        guard result == kCVReturnSuccess, let output = outputBuffer else { return }

        renderer.composite(video: buffer, profile: profile, customFrame: customFrame, into: output)
        adaptor.append(output, withPresentationTime: presentationTime)
    }

    func stop(completion: @escaping @Sendable (URL?) -> Void) {
        lock.lock()
        let wasStarted = started
        let writer = self.writer
        let input = self.input
        stopped = true
        lock.unlock()

        guard wasStarted, let writer, let input else {
            completion(nil)
            return
        }

        input.markAsFinished()
        let url = outputURL
        let box = WriterBox(writer)
        writer.finishWriting {
            completion(box.writer.status == .completed ? url : nil)
        }
    }

    private func startWriting(time: CMTime) {
        let outputWidth = Int(profile.frameSize.width)
        let outputHeight = Int(profile.frameSize.height)

        do {
            let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)

            let compression: [String: Any] = [
                AVVideoAverageBitRateKey: 12_000_000,
            ]
            let settings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.hevcWithAlpha,
                AVVideoWidthKey: outputWidth,
                AVVideoHeightKey: outputHeight,
                AVVideoCompressionPropertiesKey: compression,
            ]

            let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
            input.expectsMediaDataInRealTime = true

            let pbAttrs: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: outputWidth,
                kCVPixelBufferHeightKey as String: outputHeight,
            ]
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: input,
                sourcePixelBufferAttributes: pbAttrs)

            guard writer.canAdd(input) else { return }
            writer.add(input)
            guard writer.startWriting() else {
                print("startWriting failed: \(String(describing: writer.error))")
                return
            }
            writer.startSession(atSourceTime: time)

            self.writer = writer
            self.input = input
            self.adaptor = adaptor
            self.started = true
        } catch {
            print("AVAssetWriter init failed: \(error)")
        }
    }

    private final class WriterBox: @unchecked Sendable {
        let writer: AVAssetWriter
        init(_ writer: AVAssetWriter) { self.writer = writer }
    }
}
