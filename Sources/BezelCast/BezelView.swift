import SwiftUI
import AVFoundation

struct BezelView: View {
    let session: AVCaptureSession

    private let screenAspect: CGFloat = 9.0 / 19.5

    var body: some View {
        GeometryReader { geo in
            let width = min(geo.size.width, geo.size.height * screenAspect)
            let height = width / screenAspect
            let cornerRadius = width * BezelGeometry.cornerRatio
            let frame = width * BezelGeometry.frameRatio

            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.black)

                CapturePreview(session: session)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius - frame))
                    .padding(frame)
            }
            .frame(width: width, height: height)
            .shadow(color: .black.opacity(0.25), radius: 24, y: 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
