# SeatingChart

A lightweight, fully offline macOS app for generating random seating charts for school classes. It includes a visual room editor, per-class constraints, fullscreen presentation mode, PDF export, a random name picker with an always-on-top overlay, and a team-grouping tool.

The UI is available in English and German and follows the system language automatically.

## Features

- **Class management**: add classes and students, attach photos, set gender for grouping.
- **Constraints**: keep students apart, pin a student to a row, or pin a student to a specific seat.
- **Room editor**: click-and-drag grid canvas with blackboard orientation, quick-setup sheet, and disabled seats.
- **Seating generation**: true random or constraint-aware randomized backtracking.
- **Presentation mode**: fullscreen window for projectors / AirPlay.
- **Export**: PDF printout, plus import/export of `.seatingchart` bundles that include classes, rooms, charts, and student photos.
- **Name picker**: draw names without replacement, with an overlay window for slideshows.
- **Group builder**: split a class into balanced teams by group size or max per group, with optional gender quotas.

## Download

The easiest way to install SeatingChart is from the [latest GitHub release](https://github.com/ningunoclub/SeatingChart/releases/latest):

1. Download the release zip (for example `SeatingChart.zip`).
2. Double-click the zip to extract `Seating Chart.app`.
3. Drag `Seating Chart.app` into your `/Applications` folder.
4. Open it from Launchpad or Finder.

> The app is ad-hoc signed, so macOS may show a Gatekeeper warning the first time you open it. If that happens, right-click the app and choose **Open**, or go to **System Settings → Privacy & Security** and click **Open Anyway**.

## Requirements

- macOS 14.0 (Sonoma) or later
- Swift 6.0 / Xcode 16 or the Swift 6 command line tools (only if you want to build from source)

## Build & run

```bash
swift build
swift run SeatingChart
```

Run the test suite:

```bash
scripts/test.sh
```

> Without a full Xcode installation, `swift test` alone may run zero tests because the swift-testing framework lives in the Command Line Tools. `scripts/test.sh` adds the correct search path.

## Package the app

```bash
scripts/make-icon.sh   # icon/AppIcon.png → icon/AppIcon.icns
scripts/make-app.sh    # release build → ./Seating Chart.app
```

The resulting `Seating Chart.app` is ad-hoc signed for local use.

## Create a GitHub release

1. Build the release app:

   ```bash
   scripts/make-app.sh
   ```

2. Zip the app bundle (macOS app bundles must be zipped before uploading):

   ```bash
   ditto -c -k --sequesterRsrc --keepParent "Seating Chart.app" "SeatingChart.zip"
   ```

   > Use the same filename (for example `SeatingChart.zip`) for every release. GitHub provides a stable `releases/latest/download/SeatingChart.zip` URL only when the asset name does not change between releases.

3. Go to the repo on GitHub: `https://github.com/ningunoclub/SeatingChart/releases`
4. Click **Draft a new release**.
5. Click **Choose a tag**, type a version like `v1.0.0`, and select **Create new tag**.
6. Set **Release title** (e.g., `SeatingChart 1.0.0`).
7. Add release notes describing what’s new.
8. Drag `SeatingChart.zip` into the assets area.
9. Click **Publish release**.

Users can then download the zip, extract it, and drag `Seating Chart.app` to `/Applications`.

## Data & privacy

All data is stored locally in `~/Library/Application Support/SeatingChart/`. There is no network, iCloud, or analytics traffic. Student photos are kept in a local `Images/` folder and are never transmitted.

## License

This project is provided as-is for personal or classroom use.
