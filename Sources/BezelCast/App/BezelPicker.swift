import SwiftUI

/// Keeps the library open while switching frames so choices can be compared live.
struct BezelPicker: View {
    @ObservedObject var capture: DeviceCapture
    var importFrame: () -> Void
    @State private var search = ""

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Bezels")
                    .font(.system(size: 18, weight: .semibold))
                Text("Choose a frame for your preview and exports.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                preset("Automatic", icon: "sparkles", id: "automatic")
                preset("No Bezel", icon: "rectangle.portrait.slash", id: "none")
            }

            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search model or finish", text: $search)
                    .textFieldStyle(.plain)
                    .accessibilityLabel("Search bezels")
                if !search.isEmpty {
                    Button {
                        search = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(9)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: 9) {
                            Text(group.name)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                            LazyVGrid(columns: columns, spacing: 10) {
                                ForEach(group.options) { option in
                                    bezelTile(option)
                                }
                            }
                        }
                    }

                    if groups.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: search.isEmpty ? "iphone" : "magnifyingglass")
                                .font(.system(size: 25, weight: .light))
                            Text(search.isEmpty ? "No built-in bezels for this screen" : "No matching bezels")
                                .font(.system(size: 12, weight: .medium))
                            Text(search.isEmpty ? "You can import a custom PNG below." : "Try another model or finish.")
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    }
                }
                .padding(.trailing, 2)
                .padding(.bottom, 4)
            }
            .frame(height: 310)

            if capture.session != nil {
                Text("Showing bezels that fit your connected screen.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Divider()

            if capture.hasImportedFrame {
                Button {
                    capture.selectBezel("custom")
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "photo")
                        Text(importedFrameLabel)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        if capture.selectedBezelID == "custom" {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                    .font(.system(size: 12))
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Use imported bezel")
            }

            Button(action: importFrame) {
                Label("Import custom PNG…", systemImage: "square.and.arrow.down")
                    .font(.system(size: 12))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(width: 380)
        .preferredColorScheme(.dark)
    }

    private var importedFrameLabel: String {
        capture.selectedBezelID == "custom" ? (capture.customFrameName ?? "Custom PNG") : "Custom PNG"
    }

    private var groups: [BezelGroup] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let options = capture.availableBezels.filter {
            query.isEmpty || $0.name.localizedStandardContains(query)
        }
        var result: [BezelGroup] = []
        for option in options {
            if let index = result.firstIndex(where: { $0.id == option.profileID }) {
                result[index].options.append(option)
            } else {
                result.append(BezelGroup(id: option.profileID,
                                         name: option.profile.displayName,
                                         options: [option]))
            }
        }
        return result
    }

    private func preset(_ title: String, icon: String, id: String) -> some View {
        let selected = capture.selectedBezelID == id
        return Button {
            capture.selectBezel(id)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: icon)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(selected ? Color.accentColor.opacity(0.15) : .white.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 9))
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(selected ? Color.accentColor : .white.opacity(0.1), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func bezelTile(_ option: BezelOption) -> some View {
        let selected = capture.selectedBezelID == option.id
        return Button {
            capture.selectBezel(option.id)
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    if let thumbnail = option.thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                    } else {
                        Image(systemName: option.profile.family == .iPad ? "ipad" : "iphone")
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 94)
                .padding(.top, 4)
                Text(option.finishName)
                    .font(.system(size: 11, weight: selected ? .semibold : .regular))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.center)
                    .frame(height: 28, alignment: .top)
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(selected ? Color.accentColor.opacity(0.15) : .white.opacity(0.04),
                        in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(selected ? Color.accentColor : .white.opacity(0.08),
                                  lineWidth: selected ? 2 : 1)
            }
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.white, Color.accentColor)
                        .padding(6)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .help(option.name)
        .accessibilityLabel(option.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct BezelGroup: Identifiable {
    var id: String
    var name: String
    var options: [BezelOption]
}
