import SwiftUI

struct BackgroundPicker: View {
    @ObservedObject var store: BackgroundStore
    let isRecording: Bool
    var recordingSize: CGSize? = nil
    var importImage: () -> Void
    @State private var search = ""
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Backgrounds").font(.system(size: 18, weight: .semibold))
                    Text("For your preview, screenshots, and recordings.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                if store.isLoading || store.isDiscovering { ProgressView().controlSize(.small) }
            }

            Button { store.select("none") } label: {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.slash")
                    Text("None").font(.system(size: 12, weight: .medium))
                    Text("Transparent").font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    if store.selectedID == "none" { Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint) }
                }
                .padding(10)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("No background")
            .accessibilityAddTraits(store.selectedID == "none" ? .isSelected : [])

            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search backgrounds", text: $search).textFieldStyle(.plain)
            }
            .padding(9)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    group("Colors", kinds: [.solid])
                    group("Gradients", kinds: [.gradient])
                    group("macOS Wallpapers", kinds: [.wallpaper])
                    if !store.isDiscovering && !store.options.contains(where: { $0.kind == .wallpaper }) && search.isEmpty {
                        Text("No wallpaper images are available locally. Download one in System Settings → Wallpaper, then refresh, or import an image.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    group("Your Images", kinds: [.custom])
                    if filteredOptions.isEmpty {
                        Text("No matching backgrounds.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity).padding(.vertical, 24)
                    }
                }
                .padding(.trailing, 2)
            }
            .frame(height: 290)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                if isRecording, let recordingSize {
                    HStack {
                        Text("Canvas")
                        Spacer()
                        Label("\(Int(recordingSize.width)) × \(Int(recordingSize.height))", systemImage: "lock")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Picker("Canvas", selection: Binding(get: { store.canvas }, set: store.setCanvas)) {
                        ForEach(BackgroundCanvas.allCases) { canvas in Text(canvas.name).tag(canvas) }
                    }
                    .pickerStyle(.segmented)
                    .disabled(isRecording || store.selectedID == "none")
                    .accessibilityLabel("Background canvas")
                }

                HStack {
                    Text("Padding").frame(width: 50, alignment: .leading)
                    Slider(value: Binding(get: { store.padding }, set: store.setPadding), in: 0...0.3, step: 0.01)
                        .accessibilityLabel("Background padding")
                    Text("\(Int((store.padding * 100).rounded()))%")
                        .monospacedDigit().frame(width: 34, alignment: .trailing)
                }
                .disabled(store.selectedID == "none")
                Toggle("Shadow", isOn: Binding(get: { store.shadow }, set: store.setShadow))
                    .toggleStyle(.switch).controlSize(.small)
                    .disabled(store.selectedID == "none")
                Text(isRecording ? "Canvas stays fixed while recording."
                     : store.selectedID == "none" ? "Transparent captures keep their original size."
                     : "\(Int(store.canvas.size.width)) × \(Int(store.canvas.size.height)) pixels")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .font(.system(size: 12))

            if let error = store.error {
                Text(error).font(.system(size: 11)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button(action: importImage) {
                    Label("Import image…", systemImage: "square.and.arrow.down")
                }
                Spacer()
                Button { store.refreshWallpapers() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh macOS wallpapers")
                .accessibilityLabel("Refresh macOS wallpapers")
                .disabled(store.isDiscovering)
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(width: 390)
        .preferredColorScheme(.dark)
        .task { store.refreshWallpapers() }
    }

    private var filteredOptions: [BackgroundOption] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.options.filter { $0.kind != .none && (query.isEmpty || $0.name.localizedStandardContains(query)) }
    }

    @ViewBuilder
    private func group(_ title: String, kinds: [BackgroundOption.Kind]) -> some View {
        let options = filteredOptions.filter { kinds.contains($0.kind) }
        if !options.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(options) { option in
                        Button { store.select(option.id) } label: {
                            VStack(spacing: 6) {
                                BackgroundThumbnail(option: option)
                                    .frame(height: 62)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                Text(option.name)
                                    .font(.system(size: 11))
                                    .lineLimit(1).truncationMode(.middle)
                            }
                            .padding(6)
                            .background(store.selectedID == option.id ? Color.accentColor.opacity(0.15) : .white.opacity(0.04),
                                        in: RoundedRectangle(cornerRadius: 9))
                            .overlay {
                                RoundedRectangle(cornerRadius: 9)
                                    .strokeBorder(store.selectedID == option.id ? Color.accentColor : .white.opacity(0.08),
                                                  lineWidth: store.selectedID == option.id ? 2 : 1)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(option.name)
                        .accessibilityLabel(option.name)
                        .accessibilityAddTraits(store.selectedID == option.id ? .isSelected : [])
                    }
                }
            }
        }
    }
}

private struct BackgroundThumbnail: View {
    let option: BackgroundOption
    @State private var image: CGImage?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.white.opacity(0.05)
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                } else {
                    Image(systemName: "photo").foregroundStyle(.secondary)
                }
            }
        }
        .task(id: option.id) {
            let thumbnail = await BackgroundThumbnailLoader.shared.thumbnail(for: option)
            if !Task.isCancelled { image = thumbnail }
        }
    }
}

private actor BackgroundThumbnailLoader {
    static let shared = BackgroundThumbnailLoader()

    func thumbnail(for option: BackgroundOption) -> CGImage? {
        BackgroundLibrary.thumbnail(for: option, maxPixelSize: 256)
    }
}
