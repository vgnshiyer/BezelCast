extension BezelFinishCatalog {
    /// Released finishes, including Apple's later green, purple, and yellow additions.
    /// Rail colors are artwork approximations; Apple does not publish material RGB values.
    static let legacyIPhonePalettes: [String: BezelPalette] = {
        var result: [String: BezelPalette] = [:]

        let iPhone15Pro = BezelPalette(
            finishes: [.blackTitanium, .whiteTitanium, .blueTitanium, .naturalTitanium],
            sources: [
                "https://support.apple.com/en-us/111829",
                "https://support.apple.com/en-us/111828",
            ]
        )
        result["iphone-15-pro"] = iPhone15Pro
        result["iphone-15-pro-max"] = iPhone15Pro

        let iPhone15 = BezelPalette(
            finishes: [.black, .blue, .green, .yellow, .pink],
            sources: [
                "https://support.apple.com/en-us/111831",
                "https://support.apple.com/en-us/111830",
            ],
            railColors: [
                .black: 0x3C4142, .blue: 0xA5BFCC, .green: 0xA7BFA7,
                .yellow: 0xD3C985, .pink: 0xD7A6AC,
            ]
        )
        result["iphone-15"] = iPhone15
        result["iphone-15-plus"] = iPhone15

        let iPhone14Pro = BezelPalette(
            finishes: [.spaceBlack, .silver, .gold, .deepPurple],
            sources: [
                "https://support.apple.com/en-us/111849",
                "https://support.apple.com/en-us/111846",
            ]
        )
        result["iphone-14-pro"] = iPhone14Pro
        result["iphone-14-pro-max"] = iPhone14Pro

        let iPhone14 = BezelPalette(
            finishes: [.midnight, .purple, .starlight, .productRed, .blue, .yellow],
            sources: [
                "https://support.apple.com/en-us/111850",
                "https://support.apple.com/en-us/111854",
            ],
            railColors: [.blue: 0x6586A5, .purple: 0xABA3C2, .yellow: 0xD8B92C]
        )
        result["iphone-14"] = iPhone14
        result["iphone-14-plus"] = iPhone14

        let iPhone13Pro = BezelPalette(
            finishes: [.graphite, .gold, .silver, .sierraBlue, .alpineGreen],
            sources: [
                "https://support.apple.com/en-us/111871",
                "https://support.apple.com/en-us/111870",
            ]
        )
        result["iphone-13-pro"] = iPhone13Pro
        result["iphone-13-pro-max"] = iPhone13Pro

        let iPhone13 = BezelPalette(
            finishes: [.midnight, .starlight, .productRed, .blue, .pink, .green],
            sources: [
                "https://support.apple.com/en-us/111872",
                "https://support.apple.com/en-us/111873",
            ],
            railColors: [.blue: 0x2E667F, .pink: 0xDFC2BE, .green: 0x3A5745]
        )
        result["iphone-13"] = iPhone13
        result["iphone-13-mini"] = iPhone13

        let iPhone12Pro = BezelPalette(
            finishes: [.graphite, .silver, .gold, .pacificBlue],
            sources: [
                "https://support.apple.com/en-us/111875",
                "https://support.apple.com/en-us/111874",
            ]
        )
        result["iphone-12-pro"] = iPhone12Pro
        result["iphone-12-pro-max"] = iPhone12Pro

        let iPhone12 = BezelPalette(
            finishes: [.black, .white, .productRed, .green, .blue, .purple],
            sources: [
                "https://support.apple.com/en-us/111876",
                "https://support.apple.com/en-us/111877",
            ],
            railColors: [
                .blue: 0x245D7A, .green: 0xA8CFC2, .purple: 0xA49BCC,
                .productRed: 0xD94148,
            ]
        )
        result["iphone-12"] = iPhone12
        result["iphone-12-mini"] = iPhone12

        result["iphone-se"] = BezelPalette(
            finishes: [.midnight, .starlight, .productRed],
            sources: ["https://support.apple.com/en-us/111866"]
        )

        return result
    }()
}
