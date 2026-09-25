extension BezelFinishCatalog {
    /// Released finish names from Apple's technical specifications. A profile
    /// groups generations only when their available finishes and front glass
    /// colors agree. RGB rail approximations are artwork, not Apple color data.
    static let iPadPalettes: [String: BezelPalette] = [
        "ipad-pro-13": BezelPalette(
            finishes: [.spaceBlack, .silver],
            sources: ["https://support.apple.com/en-us/119891",
                      "https://support.apple.com/en-us/125407"]),
        "ipad-pro-12-9-air-13": BezelPalette(
            finishes: [.spaceGray, .silver],
            sources: ["https://support.apple.com/en-us/111979",
                      "https://support.apple.com/en-us/111977",
                      "https://support.apple.com/en-us/111896",
                      "https://support.apple.com/en-us/111841"]),
        "ipad-air-13": BezelPalette(
            finishes: [.spaceGray, .starlight, .blue, .purple],
            sources: ["https://support.apple.com/en-us/119893",
                      "https://support.apple.com/en-us/122242",
                      "https://support.apple.com/en-us/126472"],
            railColors: [.blue: 0xABBAC8, .purple: 0xC3BDD3]),
        "ipad-pro-12-9-home-button": BezelPalette(
            finishes: [.spaceGray, .silver, .gold],
            sources: ["https://support.apple.com/en-us/112024",
                      "https://support.apple.com/en-us/111964"],
            lightFront: true),
        "ipad-pro-11-m4": BezelPalette(
            finishes: [.spaceBlack, .silver],
            sources: ["https://support.apple.com/en-us/119892",
                      "https://support.apple.com/en-us/125406"]),
        "ipad-pro-11": BezelPalette(
            finishes: [.spaceGray, .silver],
            sources: ["https://support.apple.com/en-us/111974",
                      "https://support.apple.com/en-us/118452",
                      "https://support.apple.com/en-us/111897",
                      "https://support.apple.com/en-us/111842"]),
        "ipad-11-air-11": BezelPalette(
            finishes: [.silver, .blue, .pink, .yellow],
            sources: ["https://support.apple.com/en-us/122240",
                      "https://support.apple.com/en-us/111840"],
            railColors: [.blue: 0x7BA7BF, .pink: 0xDE93AC, .yellow: 0xE7CE64]),
        "ipad-air-11": BezelPalette(
            finishes: [.spaceGray, .starlight, .blue, .purple],
            sources: ["https://support.apple.com/en-us/119894",
                      "https://support.apple.com/en-us/122241",
                      "https://support.apple.com/en-us/126471"],
            railColors: [.blue: 0xABBAC8, .purple: 0xC3BDD3]),
        "ipad-air-10-9-5": BezelPalette(
            finishes: [.spaceGray, .starlight, .pink, .purple, .blue],
            sources: ["https://support.apple.com/en-us/111887"],
            railColors: [.blue: 0x91B3C7, .purple: 0xB5ADD0, .pink: 0xE7CDD0]),
        "ipad-air-10-9-4": BezelPalette(
            finishes: [.spaceGray, .silver, .roseGold, .green, .skyBlue],
            sources: ["https://support.apple.com/en-us/111905"],
            railColors: [.green: 0xC6D6CC, .skyBlue: 0xB8CEDB]),
        "ipad-mini-8-3": BezelPalette(
            finishes: [.spaceGray, .starlight, .blue, .purple],
            sources: ["https://support.apple.com/en-us/121456"],
            railColors: [.blue: 0xB7C9D3, .purple: 0xC9C4DB]),
        "ipad-mini-8-3-6": BezelPalette(
            finishes: [.spaceGray, .starlight, .pink, .purple],
            sources: ["https://support.apple.com/en-us/111886"],
            railColors: [.pink: 0xE7D2CE, .purple: 0xBEBACD]),
        "ipad-10-2": BezelPalette(
            finishes: [.spaceGray, .silver],
            sources: ["https://support.apple.com/en-us/111898",
                      "https://support.apple.com/en-us/108043"]),
        "ipad-10-2-7-8": BezelPalette(
            finishes: [.spaceGray, .silver, .gold],
            sources: ["https://support.apple.com/en-us/111911",
                      "https://support.apple.com/en-us/118451"],
            lightFront: true),
        "ipad-air-10-5-pro-10-5": BezelPalette(
            finishes: [.spaceGray, .silver, .gold],
            sources: ["https://support.apple.com/en-us/111939"],
            lightFront: true),
        "ipad-pro-10-5": BezelPalette(
            finishes: [.spaceGray, .silver, .gold, .roseGold],
            sources: ["https://support.apple.com/en-us/111927"],
            lightFront: true),
        "ipad-9-7-mini-retina": BezelPalette(
            finishes: [.spaceGray, .silver, .gold],
            sources: ["https://support.apple.com/en-us/111960",
                      "https://support.apple.com/en-us/111957"],
            lightFront: true),
        "ipad-pro-9-7": BezelPalette(
            finishes: [.spaceGray, .silver, .gold, .roseGold],
            sources: ["https://support.apple.com/en-us/111965"],
            lightFront: true),
        "ipad-air-2": BezelPalette(
            finishes: [.spaceGray, .silver, .gold],
            sources: ["https://support.apple.com/en-us/112017"],
            lightFront: true),
        "ipad-mini-7-9": BezelPalette(
            finishes: [.spaceGray, .silver, .gold],
            sources: ["https://support.apple.com/en-us/112002",
                      "https://support.apple.com/en-us/111904"],
            lightFront: true),
    ]
}
