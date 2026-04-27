import SwiftUI
import AVFoundation

struct BezelView: View {
    let session: AVCaptureSession

    private let innerAspect: CGFloat = 9.0 / 19.5

    var body: some View {
        GeometryReader { geo in
            let frameRatio = BezelGeometry.frameRatio
            let cornerRatio = BezelGeometry.cornerRatio

            let outerHWRatio = (1 - 2 * frameRatio) / innerAspect + 2 * frameRatio
            let width = min(geo.size.width, geo.size.height / outerHWRatio)
            let height = width * outerHWRatio
            let frame = width * frameRatio
            let cornerRadius = width * cornerRatio

            let innerWidth = width * (1 - 2 * frameRatio)
            let islandWidth = innerWidth * BezelGeometry.islandWidthRatio
            let islandHeight = innerWidth * BezelGeometry.islandHeightRatio
            let islandTop = frame + innerWidth * BezelGeometry.islandTopRatio

            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.black)

                CapturePreview(session: session)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius - frame))
                    .padding(frame)

                Capsule()
                    .fill(.black)
                    .frame(width: islandWidth, height: islandHeight)
                    .padding(.top, islandTop)
            }
            .frame(width: width, height: height)
            .shadow(color: .black.opacity(0.25), radius: 24, y: 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
