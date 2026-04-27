import SwiftUI
import AVFoundation

struct BezelView: View {
    let session: AVCaptureSession
    let profile: DeviceProfile
    let customFrame: NSImage?

    var body: some View {
        GeometryReader { geo in
            let aspect = profile.frameSize.width / profile.frameSize.height
            let availableW = min(geo.size.width, geo.size.height * aspect)
            let availableH = availableW / aspect
            let scale = availableW / profile.frameSize.width

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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
