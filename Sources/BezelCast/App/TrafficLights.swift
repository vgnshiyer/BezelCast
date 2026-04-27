import SwiftUI
import AppKit

/// macOS-style traffic-light controls drawn in SwiftUI. Used with
/// NSWindow.styleMask = .borderless so the system buttons don't exist.
struct TrafficLights: View {
    @EnvironmentObject var windowAccess: WindowAccess
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            TrafficLightButton(
                fill: Color(red: 1.0, green: 0.37, blue: 0.36),
                hoverGlyph: "xmark",
                showGlyph: hovering,
                action: { windowAccess.window?.close() }
            )
            TrafficLightButton(
                fill: Color(red: 1.0, green: 0.74, blue: 0.18),
                hoverGlyph: "minus",
                showGlyph: hovering,
                action: { windowAccess.window?.miniaturize(nil) }
            )
            TrafficLightButton(
                fill: Color(red: 0.16, green: 0.79, blue: 0.25),
                hoverGlyph: "plus",
                showGlyph: hovering,
                action: { windowAccess.window?.zoom(nil) }
            )
        }
        .onHover { hovering = $0 }
    }
}

private struct TrafficLightButton: View {
    let fill: Color
    let hoverGlyph: String
    let showGlyph: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(fill)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().strokeBorder(.black.opacity(0.18), lineWidth: 0.5))
                if showGlyph {
                    Image(systemName: hoverGlyph)
                        .font(.system(size: 7, weight: .heavy))
                        .foregroundStyle(.black.opacity(0.55))
                }
            }
        }
        .buttonStyle(.plain)
    }
}
