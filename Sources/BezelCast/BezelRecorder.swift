@preconcurrency import AVFoundation
import CoreVideo
import CoreImage

final class BezelRecorder: @unchecked Sendable {
    private let outputURL: URL
    private let renderer: BezelRenderer

    private let lock = NSLock()
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var backplate: CIImage?
    private var mask: CIImage?
    private var geometry: BezelGeometry?
    private var started = false
    private var stopped = false

    init(url: URL, renderer: BezelRenderer) {
        self.outputURL = url
        self.renderer = renderer
    }

    func receive(buffer: CVPixelBuffer, presentationTime: CMTime) {
        lock.lock()
        defer { lock.unlock() }
        guard !stopped else { return }

        if !started {
            startWriting(firstBuffer: buffer, time: presentationTime)
        }

        guard started, let adaptor, let pool = adaptor.pixelBufferPool,
              let backplate, let mask, let geometry, let input, input.isReadyForMoreMediaData else { return }

        var outputBuffer: CVPixelBuffer?
        let result = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &outputBuffer)
        guard result == kCVReturnSuccess, let output = outputBuffer else { return }

        renderer.composite(video: buffer, backplate: backplate, mask: mask, geometry: geometry, into: output)
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

    private func startWriting(firstBuffer: CVPixelBuffer, time: CMTime) {
        let videoSize = CGSize(width: CVPixelBufferGetWidth(firstBuffer),
                               height: CVPixelBufferGetHeight(firstBuffer))
        let g = BezelGeometry(videoSize: videoSize)
        guard let backplateCG = renderer.backplateImage(for: videoSize),
              let maskCG = renderer.screenMaskImage(for: videoSize) else { return }

        do {
            let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)

            let compression: [String: Any] = [
                AVVideoAverageBitRateKey: 12_000_000,
            ]
            let settings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.hevcWithAlpha,
                AVVideoWidthKey: Int(g.outerWidth),
                AVVideoHeightKey: Int(g.outerHeight),
                AVVideoCompressionPropertiesKey: compression,
            ]

            let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
            input.expectsMediaDataInRealTime = true

            let pbAttrs: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(g.outerWidth),
                kCVPixelBufferHeightKey as String: Int(g.outerHeight),
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
            self.backplate = CIImage(cgImage: backplateCG)
            self.mask = CIImage(cgImage: maskCG)
            self.geometry = g
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
