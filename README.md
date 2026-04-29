# BezelCast

Mirror your iPhone or iPad screen on macOS with optional custom device bezel art.

## Features

- **USB iPhone and iPad mirroring** via the [`kCMIOHardwarePropertyAllowScreenCaptureDevices`](https://developer.apple.com/documentation/coremediaio) trick — same path QuickTime Player uses.
- **Auto-detected devices** — connect a supported iPhone or iPad, and the app matches it against a catalog of screen-resolution profiles.
- **BYOB (Bring Your Own Bezel)** — upload a PNG device frame with a transparent screen cutout; you can find them on [Apple's Design Resources website](https://developer.apple.com/design/resources/).
- **Screenshot** → PNG.
- **Recording** → HEVC-with-alpha `.mov` (Apple's native alpha-preserving codec).

## Requirements

- macOS 14+ (Sonoma or later, Apple Silicon recommended)
- Swift 6.0+ (ships with Xcode 16+)
- An iPhone running iOS 14 or later, or an iPad running iPadOS 14 or later
- Lightning/USB-C port

## Usage

| Pill button         | Action                                                    |
| ------------------- | --------------------------------------------------------- |
| 📷 (camera)          | Save a screenshot — file picker, exports PNG.             |
| ⏺ → 🟥 (record)      | Start / stop recording — file picker on stop, exports `.mov`. |
| device + chevron     | Pick a compatible device profile.                         |
| bezel icon           | Add or remove a custom bezel PNG. The PNG must have a transparent screen cutout; mismatch shows a red error banner. |

The pill's two-line title shows your device's user-set name on top and the matched profile model, recording timer, or uploaded filename underneath.

## Build & run

The fastest path:

```bash
git clone https://github.com/vgnshiyer/BezelCast.git
cd BezelCast
open Package.swift          # opens in Xcode, hit ⌘R
```

Or from the terminal (camera permission attaches to Terminal in this mode):

```bash
swift run BezelCast
```

A first launch will trigger a macOS Camera permission prompt — grant it. Plug in an iPhone or iPad, tap **Trust** on the device, and the live screen appears in the window.

## BYOB — where to get high-quality bezel PNGs

BezelCast does not ship bezel artwork. For pixel-perfect Apple-style frames, source PNGs yourself.

### Apple Design Resources

Official product bezel artwork lives at [developer.apple.com/design/resources](https://developer.apple.com/design/resources/). Export each device frame and upload it from the bezel button.

### Why we don't bundle the artwork

Apple's bezel artwork is proprietary intellectual property, distributed under terms that don't permit redistribution by third parties. Including those PNGs in this repository would fall outside that license. To keep BezelCast legally clean for everyone who clones it, the project ships **zero Apple-derived assets**. Any photoreal frames must be supplied by you from your own copy of Apple's design resources. Your licensing arrangement with Apple is between you and Apple — BezelCast is just the renderer.

### Supported profiles

| Device | Profiles |
| ------ | -------- |
| iPhone | iPhone 17 Pro Max, iPhone 17 Pro, iPhone 17 |
| iPhone | iPhone 16 Pro Max, iPhone 16 Pro, iPhone 16 Plus, iPhone 16 |
| iPhone | iPhone 15 Pro Max, iPhone 15 Pro, iPhone 15 Plus, iPhone 15 |
| iPhone | iPhone 14 Pro Max, iPhone 14 Pro, iPhone 14 Plus, iPhone 14 |
| iPhone | iPhone 13 Pro Max, iPhone 13 Pro, iPhone 13, iPhone 13 mini |
| iPhone | iPhone 12 Pro Max, iPhone 12 Pro, iPhone 12, iPhone 12 mini |
| iPhone | iPhone SE |
| iPad | iPad Pro 13-inch |
| iPad | iPad Pro 12.9-inch / iPad Air 13-inch |
| iPad | iPad Pro 12.9-inch (1st/2nd gen) |
| iPad | iPad Pro 11-inch (M4/M5) |
| iPad | iPad Pro 11-inch (2018-2022) |
| iPad | iPad 10.9/11-inch / iPad Air |
| iPad | iPad mini 8.3-inch |
| iPad | iPad 10.2-inch |
| iPad | iPad Air 10.5-inch / iPad Pro 10.5-inch |
| iPad | iPad 9.7-inch / iPad mini 7.9-inch |

## Known limitations

- **No audio.** HEVC-with-alpha + audio in the same `.mov` track is doable but not implemented. Recordings are silent.
- **Recording rotation uses a fixed canvas.** If the device rotates during an active recording, BezelCast keeps the movie's starting canvas size and fits the rotated frame inside it. New screenshots and recordings use the current orientation.
- **Locked device shows the last frame.** When the device screen locks, iOS/iPadOS keeps emitting the last frame; the preview freezes there. Same as QuickTime Player.
- **iPhone Mirroring (macOS Sequoia 15+)** must not be running on the same iPhone — Apple's iPhone screen capture is exclusive.
- **iOS apps with screen-recording protection** (banking, Netflix, etc.) will black out their UI via the iOS `isCaptured` flag. There is no workaround.

## License

MIT. See `LICENSE`. The repository contains no Apple-derived assets.
