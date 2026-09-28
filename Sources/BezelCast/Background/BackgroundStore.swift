import AppKit
import Combine
import UniformTypeIdentifiers

@MainActor
final class BackgroundStore: ObservableObject {
    @Published private(set) var options = BackgroundLibrary.builtIns
    @Published private(set) var selectedID = "none"
    @Published private(set) var background = CaptureBackground.none
    @Published private(set) var canvas: BackgroundCanvas
    @Published private(set) var padding: CGFloat
    @Published private(set) var shadow: Bool
    @Published private(set) var isLoading = false
    @Published private(set) var isDiscovering = false
    @Published private(set) var error: String?
    var didChange: (() -> Void)?

    private let preferences: UserDefaults
    private let importDirectory: URL
    private var loadTask: Task<Void, Never>?
    private var discoveryTask: Task<Void, Never>?
    private var transitionTask: Task<Void, Never>?
    private var previousBackground: CaptureBackground?
    private var transitionStartTime: TimeInterval?

    var presentation: CapturePresentation {
        CapturePresentation(background: background, canvas: canvas, padding: padding, shadow: shadow,
                            previousBackground: previousBackground, transitionStartTime: transitionStartTime)
    }

    init(preferences: UserDefaults = .standard, importDirectory: URL? = nil) {
        self.preferences = preferences
        self.importDirectory = importDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory,
                                                                           in: .userDomainMask)[0]
            .appendingPathComponent("BezelCast/Backgrounds", isDirectory: true)
        canvas = BackgroundCanvas(rawValue: preferences.string(forKey: "BezelCast.background.canvas") ?? "") ?? .landscape
        let savedPadding = preferences.object(forKey: "BezelCast.background.padding") as? Double ?? 0.12
        padding = savedPadding.isFinite ? min(0.3, max(0, savedPadding)) : 0.12
        shadow = preferences.object(forKey: "BezelCast.background.shadow") as? Bool ?? true

        var importedPaths = preferences.stringArray(forKey: "BezelCast.background.customPaths") ?? []
        if let lastPath = preferences.string(forKey: "BezelCast.background.customPath"), !importedPaths.contains(lastPath) {
            importedPaths.append(lastPath)
        }
        for path in importedPaths {
            options.append(BackgroundLibrary.customOption(url: URL(fileURLWithPath: path)))
        }
        let savedID = preferences.string(forKey: "BezelCast.background.id") ?? "none"
        if !options.contains(where: { $0.id == savedID }),
           let path = preferences.string(forKey: "BezelCast.background.wallpaperPath") {
            let option = BackgroundLibrary.wallpaperOption(url: URL(fileURLWithPath: path))
            if option.id == savedID {
                if BackgroundLibrary.isProcessedDesktopWallpaper(url: URL(fileURLWithPath: path)) {
                    // The processed image can outlive or differ from its original.
                    // Let the user choose the clean artwork instead of substituting it.
                    preferences.set("none", forKey: "BezelCast.background.id")
                    preferences.removeObject(forKey: "BezelCast.background.wallpaperPath")
                    error = "The saved desktop image includes a notch-hiding strip. Choose an original image from macOS Wallpapers."
                } else {
                    options.append(option)
                }
            }
        }
        if savedID != "none" { select(savedID) }
    }

    deinit {
        loadTask?.cancel()
        discoveryTask?.cancel()
        transitionTask?.cancel()
    }

    func refreshWallpapers() {
        guard discoveryTask == nil else { return }
        isDiscovering = true
        let current = NSScreen.screens.compactMap { NSWorkspace.shared.desktopImageURL(for: $0) }
        discoveryTask = Task { [weak self] in
            let wallpapers = await Task.detached(priority: .utility) {
                BackgroundLibrary.wallpapers(currentWallpaperURLs: current)
            }.value
            guard !Task.isCancelled, let self else { return }
            var next = BackgroundLibrary.builtIns + wallpapers
            // Retain imported images and a selected file outside standard wallpaper folders.
            for option in self.options where option.kind == .custom || option.id == self.selectedID {
                if !next.contains(where: { $0.id == option.id }) { next.append(option) }
            }
            self.options = next
            self.isDiscovering = false
            self.discoveryTask = nil
        }
    }

    func select(_ id: String) {
        guard let option = options.first(where: { $0.id == id }) else { return }
        loadTask?.cancel()
        error = nil
        if option.fileURL == nil {
            // Built-in colors and gradients require no image decoding.
            if let background = try? BackgroundLibrary.load(option) { apply(background, option: option) }
            return
        }
        isLoading = true
        loadTask = Task { [weak self] in
            do {
                let loaded = try await Task.detached(priority: .userInitiated) {
                    try BackgroundLibrary.load(option)
                }.value
                guard !Task.isCancelled, let self else { return }
                self.apply(loaded, option: option)
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.isLoading = false
                self.error = error.localizedDescription
            }
        }
    }

    func setCanvas(_ value: BackgroundCanvas) {
        canvas = value
        preferences.set(value.rawValue, forKey: "BezelCast.background.canvas")
        didChange?()
    }

    func setPadding(_ value: CGFloat) {
        padding = value.isFinite ? min(0.3, max(0, value)) : 0.12
        preferences.set(Double(padding), forKey: "BezelCast.background.padding")
        didChange?()
    }

    func setShadow(_ value: Bool) {
        shadow = value
        preferences.set(value, forKey: "BezelCast.background.shadow")
        didChange?()
    }

    func dismissError() {
        error = nil
    }

    func importImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = "Choose Background"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importImage(from: url)
    }

    func importImage(from url: URL) {
        loadTask?.cancel()
        isLoading = true
        error = nil
        let directory = importDirectory
        loadTask = Task { [weak self] in
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    let source = BackgroundLibrary.customOption(url: url)
                    // Validate before copying so an unreadable import leaves the current selection alone.
                    _ = try BackgroundLibrary.load(source)
                    let folder = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    do {
                        let savedURL = folder.appendingPathComponent(url.lastPathComponent)
                        try FileManager.default.copyItem(at: url, to: savedURL)
                        let option = BackgroundLibrary.customOption(url: savedURL)
                        return (option, try BackgroundLibrary.load(option))
                    } catch {
                        try? FileManager.default.removeItem(at: folder)
                        throw error
                    }
                }.value
                guard !Task.isCancelled, let self else {
                    if let folder = result.0.fileURL?.deletingLastPathComponent() {
                        try? FileManager.default.removeItem(at: folder)
                    }
                    return
                }
                self.options.append(result.0)
                self.preferences.set(result.0.fileURL?.path, forKey: "BezelCast.background.customPath")
                self.preferences.set(self.options.filter { $0.kind == .custom }.compactMap { $0.fileURL?.path },
                                     forKey: "BezelCast.background.customPaths")
                self.apply(result.1, option: result.0)
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.isLoading = false
                self.error = "Couldn't import \(url.lastPathComponent). Choose a readable image."
            }
        }
    }

    private func apply(_ value: CaptureBackground, option: BackgroundOption) {
        if !options.contains(where: { $0.id == option.id }) { options.append(option) }
        transitionTask?.cancel()
        previousBackground = !background.isNone && !value.isNone && background.id != value.id ? background : nil
        transitionStartTime = previousBackground == nil ? nil : ProcessInfo.processInfo.systemUptime
        background = value
        selectedID = option.id
        isLoading = false
        preferences.set(option.id, forKey: "BezelCast.background.id")
        if option.kind == .wallpaper {
            preferences.set(option.fileURL?.path, forKey: "BezelCast.background.wallpaperPath")
        } else if option.kind == .custom {
            preferences.set(option.fileURL?.path, forKey: "BezelCast.background.customPath")
        }
        didChange?()
        if previousBackground != nil {
            transitionTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled, let self else { return }
                self.previousBackground = nil
                self.transitionStartTime = nil
                self.didChange?()
            }
        }
    }
}
