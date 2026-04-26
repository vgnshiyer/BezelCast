import SwiftUI
import AVFoundation

struct BezelView: View {
    let session: AVCaptureSession

    private let screenAspect: CGFloat = 9.0 / 19.5

    var body: some View {
        GeometryReader { geo in
            let width = min(geo.size.width, geo.size.height * screenAspect)
            let height = width / screenAspect
            let cornerRadius = width * 0.16
            let frame = width * 0.025
            let islandWidth = width * 0.32
            let islandHeight = islandWidth * 0.30

            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.black)

                CapturePreview(session: session)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius - frame))
                    .padding(frame)

                Capsule()
                    .fill(.black)
                    .frame(width: islandWidth, height: islandHeight)
                    .padding(.top, frame + width * 0.025)
            }
            .frame(width: width, height: height)
            .shadow(color: .black.opacity(0.25), radius: 24, y: 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
