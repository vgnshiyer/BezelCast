# BezelCast

Mirror your iPhone screen on macOS with a beautiful device bezel — open-source alternative to [Bezel](https://nonstrict.eu/bezel).

Plug an iPhone in via USB, accept the **Trust** prompt, and BezelCast renders the live screen inside a programmatic device frame on a chromeless transparent window. Snap a screenshot or record a video — both export at the iPhone's native resolution with transparent corners outside the rounded device shape.

![Floating pill toolbar with traffic lights and capture controls](https://via.placeholder.com/900x80?text=screenshot+TBD)

## Features

- **USB iPhone mirroring** via the [`kCMIOHardwarePropertyAllowScreenCaptureDevices`](https://developer.apple.com/documentation/coremediaio) trick — same path QuickTime Player uses.
- **Auto-detected device** — connect any iPhone 12-17 (and SE), the app matches it against a catalog of 24 profiles by screen resolution.
- **Programmatic default bezel** — thin black ring + Dynamic Island drawn via SwiftUI / `CGPath`. No bundled assets, fully legal.
- **BYOB (Bring Your Own Bezel)** — upload a PNG that matches your iPhone's expected frame dimensions to override the default with photoreal Apple bezel art. In-memory only, no disk writes.
- **Screenshot** → PNG with transparent corners.
- **Recording** → HEVC-with-alpha `.mov` (Apple's native alpha-preserving codec). Transparent corners survive into Final Cut, iMovie, Keynote, etc.
- **Chromeless transparent window** with a floating pill toolbar (close/min/zoom traffic lights + device label + capture/record/upload controls). Same look as Apple's iPhone Mirroring app.

## Requirements

- macOS 14+ (Sonoma or later, Apple Silicon recommended)
- Swift 6.0+ (ships with Xcode 16+)
- An iPhone running iOS 14 or later, USB cable, and a Lightning/USB-C port

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

A first launch will trigger a macOS Camera permission prompt — grant it. Plug in an iPhone, tap **Trust** on the device, and the live screen appears inside the bezel.

## Usage

| Pill button         | Action                                                    |
| ------------------- | --------------------------------------------------------- |
| 📷 (camera)          | Save a screenshot — file picker, exports PNG.             |
| ⏺ → 🟥 (record)      | Start / stop recording — file picker on stop, exports `.mov`. |
| 📱 (iPhone, gray pill) | Upload a custom bezel PNG. Must match the detected device's `frameSize` exactly; mismatch shows a red error banner. |
| ✕ (clear, gray pill) | Remove the uploaded bezel and revert to programmatic default. |

The pill's two-line title shows your iPhone's user-set name (e.g. *Vignesh's iPhone*) on top and the matched profile model + status (`Connected` / `Recording` / uploaded filename) underneath.

## BYOB — where to get high-quality bezel PNGs

The repo intentionally ships **zero Apple-derived art** for legal cleanliness. The default programmatic bezel works out of the box. For pixel-perfect Apple-style frames, source PNGs yourself:

### Apple Design Resources

[developer.apple.com/design/resources](https://developer.apple.com/design/resources/) — free with an Apple Developer Program membership (free or paid tier). Download the iOS design kit (Sketch, Photoshop, or Figma) and export the device frame at the dimensions BezelCast asks for.

License: limited to displaying *your* app on Apple devices in marketing materials. No tilting, no animating the bezel itself, no 3D rendering. See [Apple's marketing guidelines](https://developer.apple.com/app-store/marketing/guidelines/).

### Required dimensions per profile

When you click the iPhone (BYOB) button, BezelCast tells you the required size in the file picker — for example, *"Pick a PNG sized 1350×2760 for iPhone 17 Pro"*. Reference table:

| Profile             | `frameSize`  |
| ------------------- | ------------ |
| iPhone 17 / 16 Pro Max          | 1470 × 3000 |
| iPhone 14 / 15 Pro Max + Plus   | 1440 × 2940 |
| iPhone 12 / 13 Pro Max          | 1410 × 2904 |
| iPhone 16 / 17 Pro              | 1350 × 2760 |
| iPhone 14 Pro / 15 / 15 Pro / 16 / 17 | 1359 × 2736 |
| iPhone 12 / 13 / 14 + 12 / 13 Pro | 1290 × 2652 |
| iPhone 12 / 13 mini             | 1190 × 2450 |

The PNG must have transparent pixels everywhere except the bezel material itself, with the screen area transparent at exactly the offset specified in `Bezel/DeviceProfile.swift`.

## Known limitations

- **No audio.** HEVC-with-alpha + audio in the same `.mov` track is doable but not implemented. Recordings are silent.
- **Portrait only.** Rotating the iPhone mid-session does not rotate the bezel.
- **Locked iPhone shows the last frame.** When the screen locks, iOS keeps emitting the last frame; the preview freezes there. Same as QuickTime Player.
- **Notched devices (iPhone 12-14, 12/13 Pro Max)** get a generic programmatic ring without an actual notch shape — only Dynamic Island devices have an island overlay.
- **iPhone Mirroring (macOS Sequoia 15+)** must not be running on the same iPhone — Apple's screen capture is exclusive.
- **iOS apps with screen-recording protection** (banking, Netflix, etc.) will black out their UI via the iOS `isCaptured` flag. There is no workaround.

## License

MIT. See `LICENSE`. The repository contains no Apple-derived assets.
