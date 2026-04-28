import SwiftUI
import AVFoundation

struct BezelView: View {
    let session: AVCaptureSession
    let profile: DeviceProfile
    let customFrame: NSImage?

    var body: some View {
        GeometryReader { geo in
            // Scale relative to the catalog's largest frame so smaller devices
            // render visibly smaller in the same window.
            let reference = DeviceProfile.largestFrameSize
            let scale = min(geo.size.width / reference.width,
                            geo.size.height / reference.height)
            let availableW = profile.frameSize.width * scale
            let availableH = profile.frameSize.height * scale

            let screenW = profile.screenSize.width * scale
            let screenH = profile.screenSize.height * scale
            let offsetX = profile.screenOffset.x * scale
            let offsetY = profile.screenOffset.y * scale
            let screenCorner = profile.screenCornerRadius * scale

            ZStack(alignment: .topLeading) {
                CapturePreview(session: session)
                    .frame(width: screenW, height: screenH)
                    .clipShape(RoundedRectangle(cornerRadius: screenCorner, style: .continuous))
                    .offset(x: offsetX, y: offsetY)

                if let customFrame {
                    Image(nsImage: customFrame)
                        .resizable()
                        .frame(width: availableW, height: availableH)
                } else {
                    ProgrammaticBezel(profile: profile, scale: scale)
                        .frame(width: availableW, height: availableH)
                }
            }
            .frame(width: availableW, height: availableH)
            .shadow(color: .black.opacity(0.25), radius: 24, y: 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

/// Plain black ring around the screen + Dynamic Island, drawn on top of the
/// CapturePreview. Thin, no gradient.
private struct ProgrammaticBezel: View {
    let profile: DeviceProfile
    let scale: CGFloat

    var body: some View {
        let screenRect = CGRect(x: profile.screenOffset.x * scale,
                                y: profile.screenOffset.y * scale,
                                width: profile.screenSize.width * scale,
                                height: profile.screenSize.height * scale)
        let thickness = DefaultBezelArt.thickness * scale
        let overlap = DefaultBezelArt.edgeOverlap * scale
        let bezelInner = screenRect.insetBy(dx: overlap, dy: overlap)
        let bezelOuter = screenRect.insetBy(dx: -thickness, dy: -thickness)
        let outerCorner = (profile.screenCornerRadius + DefaultBezelArt.thickness) * scale
        let innerCorner = max(profile.screenCornerRadius - DefaultBezelArt.edgeOverlap, 0) * scale

        ZStack(alignment: .topLeading) {
            BezelRingShape(outer: bezelOuter, outerCorner: outerCorner,
                           inner: bezelInner, innerCorner: innerCorner)
                .fill(Color(nsColor: DefaultBezelArt.color), style: FillStyle(eoFill: true))

            if let island = profile.island {
                Capsule()
                    .fill(.black)
                    .frame(width: island.width * scale, height: island.height * scale)
                    .offset(x: screenRect.minX + island.origin.x * scale,
                            y: screenRect.minY + island.origin.y * scale)
            }

            if let notch = profile.notch {
                let notchW = notch.width * scale
                let notchH = notch.height * scale
                let notchX = screenRect.minX + (profile.screenSize.width - notch.width) / 2 * scale
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: notchH / 2,
                    bottomTrailingRadius: notchH / 2,
                    topTrailingRadius: 0,
                    style: .continuous
                )
                .fill(.black)
                .frame(width: notchW, height: notchH)
                .offset(x: notchX, y: screenRect.minY)
            }
        }
    }
}

private struct BezelRingShape: Shape {
    let outer: CGRect
    let outerCorner: CGFloat
    let inner: CGRect
    let innerCorner: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRoundedRect(in: outer,
                            cornerSize: CGSize(width: outerCorner, height: outerCorner),
                            style: .continuous)
        path.addRoundedRect(in: inner,
                            cornerSize: CGSize(width: innerCorner, height: innerCorner),
                            style: .continuous)
        return path
    }
}
