import CoreGraphics

enum BezelFinish: String, Sendable {
    case black, white, silver, gold, graphite, blue, green, pink, purple, yellow
    case burgundy, glacier, lavender, sage, teal, ultramarine, starlight, midnight
    case spaceBlack = "space-black"
    case spaceGray = "space-gray"
    case roseGold = "rose-gold"
    case cosmicOrange = "cosmic-orange"
    case deepBlue = "deep-blue"
    case skyBlue = "sky-blue"
    case cloudWhite = "cloud-white"
    case lightGold = "light-gold"
    case softPink = "soft-pink"
    case mistBlue = "mist-blue"
    case naturalTitanium = "natural-titanium"
    case blackTitanium = "black-titanium"
    case whiteTitanium = "white-titanium"
    case blueTitanium = "blue-titanium"
    case desertTitanium = "desert-titanium"
    case deepPurple = "deep-purple"
    case alpineGreen = "alpine-green"
    case sierraBlue = "sierra-blue"
    case pacificBlue = "pacific-blue"
    case productRed = "product-red"

    var displayName: String {
        self == .productRed ? "(PRODUCT)RED" : rawValue.replacingOccurrences(of: "-", with: " ").capitalized
    }

    /// Approximate material colors for our original artwork, not Apple color specifications.
    var railColor: UInt32 {
        switch self {
        case .black: return 0x242526
        case .white: return 0xE4E5E1
        case .silver: return 0xC9C9C7
        case .gold: return 0xDBC8AD
        case .graphite: return 0x4A4947
        case .blue: return 0x90AABB
        case .green: return 0x9EBEA8
        case .pink: return 0xD8A8B5
        case .purple: return 0xB2A7C2
        case .yellow: return 0xE6CD87
        case .burgundy: return 0x643840
        case .glacier: return 0xC0D0DB
        case .lavender: return 0xB8B2CD
        case .sage: return 0xABB9A3
        case .teal: return 0x86A8A4
        case .ultramarine: return 0x737CB8
        case .starlight: return 0xE9DFD0
        case .midnight: return 0x303840
        case .spaceBlack: return 0x353534
        case .spaceGray: return 0x77787C
        case .roseGold: return 0xD6AAA1
        case .cosmicOrange: return 0xC77643
        case .deepBlue: return 0x384451
        case .skyBlue: return 0xB3CADC
        case .cloudWhite: return 0xE6E5DF
        case .lightGold: return 0xDED4B8
        case .softPink: return 0xEBCED1
        case .mistBlue: return 0xA8B7C8
        case .naturalTitanium: return 0xACA69A
        case .blackTitanium: return 0x454647
        case .whiteTitanium: return 0xD6D4CF
        case .blueTitanium: return 0x414A57
        case .desertTitanium: return 0xC3AD96
        case .deepPurple: return 0x60576B
        case .alpineGreen: return 0x556454
        case .sierraBlue: return 0x9FB4C6
        case .pacificBlue: return 0x41616E
        case .productRed: return 0xB82735
        }
    }
}

struct BezelPalette {
    /// The first finish is the model's default. Only released finishes belong here.
    let finishes: [BezelFinish]
    let sources: [String]
    var railColors: [BezelFinish: UInt32] = [:]
    /// Older silver/gold iPads have light front glass; Space Gray has dark glass.
    var lightFront = false

    func components(for finish: BezelFinish) -> (CGFloat, CGFloat, CGFloat) {
        let rgb = railColors[finish] ?? finish.railColor
        return (CGFloat((rgb >> 16) & 255) / 255,
                CGFloat((rgb >> 8) & 255) / 255,
                CGFloat(rgb & 255) / 255)
    }
}

enum BezelFinishCatalog {
    static func palette(for profileID: String) -> BezelPalette? {
        currentIPhonePalettes[profileID] ?? legacyIPhonePalettes[profileID] ?? iPadPalettes[profileID]
    }

    // Verified against the linked Apple specifications, September 25, 2026.
    private static let currentIPhonePalettes: [String: BezelPalette] = {
        var result: [String: BezelPalette] = [:]
        func add(_ ids: [String], _ finishes: [BezelFinish], _ sources: [String]) {
            for id in ids { result[id] = BezelPalette(finishes: finishes, sources: sources) }
        }
        add(["iphone-18-pro", "iphone-18-pro-max"], [.black, .silver, .glacier, .burgundy],
            ["https://www.apple.com/iphone-18-pro/specs/"])
        add(["iphone-17-pro", "iphone-17-pro-max"], [.silver, .cosmicOrange, .deepBlue],
            ["https://support.apple.com/en-us/125090", "https://support.apple.com/en-us/125091"])
        add(["iphone-17"], [.black, .white, .mistBlue, .sage, .lavender],
            ["https://www.apple.com/iphone-17/specs/"])
        add(["iphone-air"], [.spaceBlack, .cloudWhite, .lightGold, .skyBlue],
            ["https://www.apple.com/iphone-air/specs/"])
        add(["iphone-17e"], [.black, .white, .softPink],
            ["https://www.apple.com/iphone-17e/specs/"])
        add(["iphone-16-pro", "iphone-16-pro-max"],
            [.blackTitanium, .whiteTitanium, .naturalTitanium, .desertTitanium],
            ["https://support.apple.com/en-us/121031", "https://support.apple.com/en-us/121032"])
        add(["iphone-16", "iphone-16-plus"], [.black, .white, .pink, .teal, .ultramarine],
            ["https://support.apple.com/en-us/121029", "https://support.apple.com/en-us/121030"])
        add(["iphone-16e"], [.black, .white], ["https://support.apple.com/en-us/122208"])
        return result
    }()
}
