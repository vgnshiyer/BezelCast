import SwiftUI
import AVFoundation

struct BezelView: View {
    let session: AVCaptureSession
    let profile: DeviceProfile
    let customFrame: NSImage?

    var body: some View {
        GeometryReader { geo in
            let hasCustomFrame = customFrame != nil
            let reference = hasCustomFrame ? DeviceProfile.largestFrameSize : DeviceProfile.largestScreenSize
            let outputSize = hasCustomFrame ? profile.frameSize : profile.screenSize
            let scale = min(geo.size.width / reference.width,
                            geo.size.height / reference.height)

            LayeredCapturePreview(session: session, profile: profile, customFrame: customFrame)
                .frame(width: outputSize.width * scale, height: outputSize.height * scale)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}
