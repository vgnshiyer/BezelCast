import SwiftUI

struct BezelView: View {
    let profile: DeviceProfile
    let customFrame: CustomFrame?
    let previewFrames: PreviewFrameStore

    var body: some View {
        GeometryReader { geo in
            let targetSize = DeviceDisplayLayout.previewSize(for: profile,
                                                             customFrame: customFrame)
            let fit = min(1,
                          geo.size.width / targetSize.width,
                          geo.size.height / targetSize.height)

            LayeredCapturePreview(profile: profile,
                                  customFrame: customFrame,
                                  previewFrames: previewFrames)
                .frame(width: targetSize.width * fit, height: targetSize.height * fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}
