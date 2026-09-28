# Changelog

## 0.3.0

- Added capture backgrounds: colors, gradients, locally installed macOS wallpapers, and imported images, with landscape, portrait, and square canvases, padding, and optional shadows.
- Applied backgrounds consistently to previews, PNG screenshots, and recordings. Backgrounds can change during recording while the movie's canvas stays fixed; choices and imported images are remembered.
- Kept the preview window's size and position stable when switching bezels. Added proportional resizing by dragging phone or background canvas edges and corners.
- Rounded background preview corners without changing the rectangular corners of exported screenshots and movies.
- Excluded TopNotch-processed wallpapers with black strips from the wallpaper picker and fixed initial restoration of saved backgrounds.
- Closed translucent screen-to-bezel edge seams in screenshots and recordings while preserving the captured screen's proportions and original status bar.
- Added regression coverage for backgrounds, preview layout, resizing, screen preservation, and bezel-edge alignment in both orientations.

## 0.2.1

- Fixed rejection of iPhone XR and iPhone 11 feeds at 828×1792, including landscape capture. Added their built-in bezels, released finishes, and 2× notch geometry.

## 0.2.0

- Added a searchable built-in bezel library with instant model and finish switching, automatic selection, and a no-bezel option. Custom PNG imports remain available.
- Matched available finishes and their names to Apple's released models. Added distinct wide notches, smaller notches, and Dynamic Islands for the appropriate devices.
- Applied bezel changes consistently to the preview, screenshots, and recordings, including rotation and rapid switching. Recordings retain their starting canvas size.
- Remembered selections separately for iPhone and iPad and migrated obsolete saved finishes to valid choices.
- Simplified the toolbar to a single bezel picker with an adjacent arrow.
- Fixed Terminal launches that did not bring up the app, removed the unintended extra window, and restored standard app and editing keyboard shortcuts.
- Added regression coverage for rendering, selection, recording, device finishes, and display cutouts.

The built-in artwork is original and approximates physical dimensions and materials; it does not include Apple's licensed design resources. Selecting a frame preserves the connected device's captured iOS interface.
