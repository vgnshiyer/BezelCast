import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation

@MainActor
final class PreviewFrameStore {
    var imageHandler: ((CGImage?) -> Void)?

    func display(_ image: CGImage?) {
        imageHandler?(image)
    }
}

final class PreviewCompositor: @unchecked Sendable {
    private let renderer: BezelRenderer
    private let frameStore: PreviewFrameStore
    private let queue = DispatchQueue(label: "BezelCast.preview-compositor", qos: .userInteractive)
    private let lock = NSLock()
    private var configuration: PreviewConfiguration?

    init(renderer: BezelRenderer, frameStore: PreviewFrameStore) {
        self.renderer = renderer
        self.frameStore = frameStore
    }

    func setConfiguration(_ configuration: PreviewConfiguration?) {
        lock.lock()
        self.configuration = configuration
        lock.unlock()
    }

    func receive(buffer: CVPixelBuffer,
                 presentationTime _: CMTime,
                 completion: @escaping @Sendable () -> Void) {
        lock.lock()
        let configuration = self.configuration
        lock.unlock()

        guard let configuration else {
            completion()
            return
        }

        queue.async { [renderer, frameStore] in
            let currentSize = CGSize(width: CVPixelBufferGetWidth(buffer),
                                     height: CVPixelBufferGetHeight(buffer))
            let currentProfile = configuration.profile.oriented(matching: currentSize)
            let currentFrame = configuration.customFrame?.oriented(to: currentProfile)?.renderFrame
            let image = renderer.previewImage(from: buffer,
                                              profile: currentProfile,
                                              customFrame: currentFrame)
            Task { @MainActor in
                frameStore.display(image)
                completion()
            }
        }
    }
}
