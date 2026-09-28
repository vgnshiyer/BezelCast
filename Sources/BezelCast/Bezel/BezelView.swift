import SwiftUI

struct BezelView: View {
    let profile: DeviceProfile
    let customFrame: CustomFrame?
    let previewFrames: PreviewFrameStore
    var presentation: CapturePresentation = .init()

    var body: some View {
        GeometryReader { geo in
            let displaySize = DeviceDisplayLayout.previewSize(for: profile,
                                                              customFrame: customFrame,
                                                              presentation: presentation,
                                                              fitting: geo.size)
            let deviceSize = customFrame?.geometry.frameSize ?? profile.screenSize

            LayeredCapturePreview(profile: profile,
                                  customFrame: customFrame,
                                  previewFrames: previewFrames,
                                  hasCanvas: !presentation.background.isNone || presentation.fixedCanvasSize != nil,
                                  canvasCornerRadius: presentation.background.isNone ? 0 : 14)
                .frame(width: displaySize.width, height: displaySize.height)
                .overlay {
                    PreviewResizeHandle(canvasSize: presentation.outputSize(for: deviceSize),
                                        deviceRect: presentation.deviceRect(for: deviceSize),
                                        viewportSize: geo.size)
                        .padding(-PreviewResizeView.edgeInset)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}
