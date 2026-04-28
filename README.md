# BezelCast

Mirror your iPhone or iPad screen on macOS with optional custom device bezel art.

Plug an iPhone or iPad in via USB, accept the **Trust** prompt, and BezelCast renders the live screen in a chromeless transparent window. Without a custom bezel, exports are the rounded screen itself. With a BYOB PNG, exports use the full bezel canvas with transparent corners.

## Features

- **USB iPhone and iPad mirroring** via the [`kCMIOHardwarePropertyAllowScreenCaptureDevices`](https://developer.apple.com/documentation/coremediaio) trick — same path QuickTime Player uses.
- **Auto-detected devices** — connect a supported iPhone or iPad, and the app matches it against a catalog of screen-resolution profiles.
- **BYOB (Bring Your Own Bezel)** — upload a PNG device frame with a transparent screen cutout. In-memory only, no disk writes.
- **Screenshot** → PNG with transparent corners.
- **Recording** → HEVC-with-alpha `.mov` (Apple's native alpha-preserving codec). Transparent corners survive into Final Cut, iMovie, Keynote, etc.
- **Chromeless transparent window** with a floating pill toolbar (close/min/zoom traffic lights + device label + capture/record/profile/bezel controls). Same look as Apple's iPhone Mirroring app.

## Requirements

- macOS 14+ (Sonoma or later, Apple Silicon recommended)
- Swift 6.0+ (ships with Xcode 16+)
- An iPhone running iOS 14 or later, or an iPad running iPadOS 14 or later
- USB cable and a Lightning/USB-C port

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

## Usage

| Pill button         | Action                                                    |
| ------------------- | --------------------------------------------------------- |
| 📷 (camera)          | Save a screenshot — file picker, exports PNG.             |
| ⏺ → 🟥 (record)      | Start / stop recording — file picker on stop, exports `.mov`. |
| device + chevron     | Pick a compatible device profile.                         |
| bezel icon           | Add or remove a custom bezel PNG. The PNG must have a transparent screen cutout; mismatch shows a red error banner. |

The pill's two-line title shows your device's user-set name on top and the matched profile model, recording timer, or uploaded filename underneath.

## BYOB — where to get high-quality bezel PNGs

BezelCast does not ship bezel artwork. For pixel-perfect Apple-style frames, source PNGs yourself.

### Apple Design Resources

Official product bezel artwork lives at [developer.apple.com/design/resources](https://developer.apple.com/design/resources/). Export each device frame and upload it from the bezel button.

### Why we don't bundle the artwork

Apple's bezel artwork is proprietary intellectual property, distributed under terms that don't permit redistribution by third parties. Including those PNGs in this repository would fall outside that license. To keep BezelCast legally clean for everyone who clones it, the project ships **zero Apple-derived assets**. Any photoreal frames must be supplied by you from your own copy of Apple's design resources. Your licensing arrangement with Apple is between you and Apple — BezelCast is just the renderer.

### Required dimensions per profile

For iPhones, BezelCast uses fixed Apple-frame geometry. When you choose Add Bezel, the file picker tells you the required PNG size — for example, *"Pick a PNG sized 1350×2760 for iPhone 17 Pro"*. Reference table:

| Profile             | `frameSize`  |
| ------------------- | ------------ |
| iPhone 17 / 16 Pro Max          | 1470 × 3000 |
| iPhone 14 / 15 Pro Max + 15 / 16 Plus | 1440 × 2940 |
| iPhone 12 / 13 Pro Max          | 1410 × 2904 |
| iPhone 16 / 17 Pro + iPhone 17  | 1350 × 2760 |
| iPhone 14 Pro / 15 / 15 Pro / 16 | 1359 × 2736 |
| iPhone 12 / 13 / 14 + 12 / 13 Pro | 1290 × 2652 |
| iPhone 12 / 13 mini             | 1190 × 2450 |

For iPads, BezelCast detects the transparent screen cutout from the PNG and uses that frame geometry for live preview, screenshots, and recordings. The cutout must match the selected iPad profile's aspect and orientation.

## Known limitations

- **No audio.** HEVC-with-alpha + audio in the same `.mov` track is doable but not implemented. Recordings are silent.
- **Recording rotation uses a fixed canvas.** If the device rotates during an active recording, BezelCast keeps the movie's starting canvas size and fits the rotated frame inside it. New screenshots and recordings use the current orientation.
- **Locked device shows the last frame.** When the device screen locks, iOS/iPadOS keeps emitting the last frame; the preview freezes there. Same as QuickTime Player.
- **iPhone Mirroring (macOS Sequoia 15+)** must not be running on the same iPhone — Apple's iPhone screen capture is exclusive.
- **iOS apps with screen-recording protection** (banking, Netflix, etc.) will black out their UI via the iOS `isCaptured` flag. There is no workaround.

## License

MIT. See `LICENSE`. The repository contains no Apple-derived assets.
