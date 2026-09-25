# BezelCast

I Built this because I didn't want to pay $99 for getbezel.app.

Mirror your iPhone or iPad screen on macOS.

[Download the latest release for Apple Silicon Macs](https://github.com/vgnshiyer/BezelCast/releases/latest/download/BezelCast.dmg) · [Release notes](https://github.com/vgnshiyer/BezelCast/releases/latest)

## Features

- **USB iPhone and iPad mirroring** via the [`kCMIOHardwarePropertyAllowScreenCaptureDevices`](https://developer.apple.com/documentation/coremediaio) trick — same path QuickTime Player uses.
- **Auto-detected devices** — connect a supported iPhone or iPad, and the app matches it against a catalog of screen-resolution profiles.
- **Built-in bezel library** — switch instantly between original, code-drawn frames with only the finishes Apple released for each model, using Apple's finish names. Search by model or finish; no downloads needed.
- **Automatic or no bezel** — start with a frame matching the detected screen, or export the screen alone. Your choice is remembered separately for iPhone and iPad.
- **Optional custom PNGs** — import your own device frame with a transparent screen cutout.
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
| bezel + chevron      | Choose a model and finish, select Automatic or No Bezel, or import a custom PNG. |

The pill's two-line title shows your device's user-set name on top and the selected bezel, matched profile model, or recording timer underneath.

Click the bezel icon or its adjacent chevron to open the picker, then search by model or finish. Choose a thumbnail to apply it immediately; the picker stays open so you can compare frames. It shows models compatible with the connected screen, and you can also browse before connecting a device. **Automatic**, the default, uses the first released finish listed for the current profile. **No Bezel** removes the frame.

A saved finish that is no longer offered migrates to a valid default for the same model.

Bezel changes apply to the live preview, screenshots, and active recordings. A recording keeps its initial canvas size and fits subsequent frames inside it.

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

Run the test suite with:

```bash
swift test
```

## Built-in and custom bezels

The built-in library uses original CoreGraphics artwork. Available finishes and their names match Apple's released models, including colors added after launch. The rendered shades approximate physical materials and are not official Apple artwork. Apple source links are stored alongside each palette; see the [complete model and finish reference](Documentation/DeviceFinishes.md).

Camera cutouts follow the selected model: the wider iPhone 12 notch, the smaller notch on iPhone 13/14 (excluding 14 Pro) and 16e/17e, or the appropriate Dynamic Island. iPhone SE and iPads have no display cutout. These original shapes use approximate dimensions; see the [model and cutout reference](Documentation/DeviceCutouts.md). Changing a bezel preserves the connected device's captured content, including any live activities it sends.

For your own artwork, choose **Import custom PNG…** in the bezel picker. The PNG must have a transparent screen cutout and match the selected profile's geometry; an invalid file shows an error banner. You can switch away from your imported frame and select **Custom PNG** to return to it during the same app launch. Imported files are not restored after quitting; the last built-in, Automatic, or No Bezel preference is retained.

### Why official Apple PNGs are not bundled

The License Agreement included in Apple's [iPhone 18 bezel download](https://devimages-cdn.apple.com/design/resources/download/Bezel-iPhone-18.dmg), Apple Design Resources §2.B, states: “You may not embed the Apple Design Resources in any software programs or other products.” BezelCast therefore includes its own code-drawn artwork. If you obtain artwork from [Apple Design Resources](https://developer.apple.com/design/resources/) for your own use, follow its license terms.

### Supported profiles

| Device | Profiles |
| ------ | -------- |
| iPhone | iPhone 18 Pro Max, iPhone 18 Pro |
| iPhone | iPhone 17 Pro Max, iPhone 17 Pro, iPhone Air, iPhone 17, iPhone 17e |
| iPhone | iPhone 16 Pro Max, iPhone 16 Pro, iPhone 16 Plus, iPhone 16, iPhone 16e |
| iPhone | iPhone 15 Pro Max, iPhone 15 Pro, iPhone 15 Plus, iPhone 15 |
| iPhone | iPhone 14 Pro Max, iPhone 14 Pro, iPhone 14 Plus, iPhone 14 |
| iPhone | iPhone 13 Pro Max, iPhone 13 Pro, iPhone 13, iPhone 13 mini |
| iPhone | iPhone 12 Pro Max, iPhone 12 Pro, iPhone 12, iPhone 12 mini |
| iPhone | iPhone SE (3rd gen) |
| iPad | iPad Pro 13-inch (M4/M5) |
| iPad | iPad Pro 12.9-inch (2018-2022) |
| iPad | iPad Pro 12.9-inch (1st/2nd gen) |
| iPad | iPad Pro 11-inch (M4/M5) |
| iPad | iPad Pro 11-inch (2018-2022) |
| iPad | iPad Air 13-inch (M2/M3/M4), iPad Air 11-inch (M2/M3/M4) |
| iPad | iPad Air 10.9-inch (5th gen), iPad Air 10.9-inch (4th gen) |
| iPad | iPad (A16 / 10th gen) |
| iPad | iPad mini (A17 Pro), iPad mini 8.3-inch (6th gen) |
| iPad | iPad 10.2-inch (9th gen), iPad 10.2-inch (7th/8th gen) |
| iPad | iPad Air 10.5-inch (3rd gen), iPad Pro 10.5-inch |
| iPad | iPad 9.7-inch (5th/6th gen), iPad Pro 9.7-inch, iPad Air 2 |
| iPad | iPad mini 7.9-inch (4th/5th gen) |

## Known limitations

- **No audio.** HEVC-with-alpha + audio in the same `.mov` track is doable but not implemented. Recordings are silent.
- **Recordings use a fixed canvas.** Rotation and bezel changes during recording fit inside the movie's starting canvas size, which can leave transparent margins. New screenshots and recordings use the current orientation and bezel dimensions.
- **Locked device shows the last frame.** When the device screen locks, iOS/iPadOS keeps emitting the last frame; the preview freezes there. Same as QuickTime Player.
- **iPhone Mirroring (macOS Sequoia 15+)** must not be running on the same iPhone — Apple's iPhone screen capture is exclusive.
- **iOS apps with screen-recording protection** (banking, Netflix, etc.) will black out their UI via the iOS `isCaptured` flag. There is no workaround.

## License

MIT. See `LICENSE`. The built-in code-drawn frames are original artwork covered by the same license. The repository contains no Apple-derived assets.
