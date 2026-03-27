# Delayed Mirror — iOS App

A live camera feed that plays back what the camera captured **N seconds ago**
(1 – 30 s, adjustable in real time). Supports pinch-to-zoom and a zoom slider.
No video is saved to disk.

---

## Files

| File | Purpose |
|------|---------|
| `DelayedMirrorApp.swift` | `@main` entry point |
| `CameraManager.swift` | AVFoundation capture, JPEG ring buffer, zoom control |
| `CameraPreviewView.swift` | `UIViewRepresentable` + `CADisplayLink` renderer |
| `ContentView.swift` | SwiftUI UI — delay slider, zoom panel, buffering indicator |
| `InfoPlist.snippet.xml` | Camera permission key to paste into `Info.plist` |

---

## Create the Xcode Project (step by step)

### 1  New project

1. Open **Xcode** (16.x recommended; minimum 15.x).
2. **File → New → Project…**
3. Choose **iOS → App** and click **Next**.
4. Fill in:
   - **Product Name**: `DelayedMirror`
   - **Team**: your Apple Developer team (free or paid)
   - **Bundle Identifier**: e.g. `com.yourname.DelayedMirror`
   - **Interface**: **SwiftUI**
   - **Language**: **Swift**
   - Uncheck *Include Tests* (optional)
5. Click **Next**, choose a save location, **Create**.

### 2  Replace / add source files

Xcode creates a default `ContentView.swift` and an app file.

1. **Delete** the default `ContentView.swift` and the default app entry file
   (e.g. `DelayedMirrorApp.swift` or whatever Xcode named it).
2. Drag the four Swift files from this folder into the **project navigator**
   under the `DelayedMirror` group:
   - `DelayedMirrorApp.swift`
   - `CameraManager.swift`
   - `CameraPreviewView.swift`
   - `ContentView.swift`
3. In the sheet that appears, make sure **"Copy items if needed"** is checked
   and the app target is selected. Click **Finish**.

### 3  Add the camera permission key

1. In the project navigator, click **Info.plist** (or select your app target →
   **Info** tab).
2. Add a new row:
   - **Key**: `Privacy - Camera Usage Description`
   - **Value**: `Delayed Mirror uses the camera to display a live delayed preview.`

   Alternatively, open `Info.plist` as source and paste the contents of
   `InfoPlist.snippet.xml` inside the root `<dict>`.

### 4  Deployment target

1. Select the project in the navigator → your app **Target** → **General**.
2. Set **Minimum Deployments** to **iOS 16.0** (or higher).

### 5  Capabilities (no extras needed)

The app uses only the camera. No special capabilities (HealthKit, Push, etc.)
are required beyond the `NSCameraUsageDescription` key.

### 6  Run on a real device

> **The camera does not work in the iOS Simulator.**
> You must run on a physical iPhone or iPad.

1. Connect your device via USB (or use wireless pairing).
2. Select your device in the Xcode toolbar.
3. Press **⌘R** (or the ▶ button).
4. On first run, trust the developer profile on the device:
   **Settings → General → VPN & Device Management → your team → Trust**.

---

## How it works

```
AVCaptureVideoDataOutput  (30 fps, 720p, BGRA)
        │
        ▼
   captureQueue (serial)
        │
   CIContext (Metal)         ← GPU-accelerated pixel-buffer → CGImage
        │
   UIImage.jpegData(0.75)    ← ~60–120 KB per frame
        │
   ringBuffer [(timestamp, Data)]
        │   ← pruned to last 33 s (~1000 frames ≈ 60–120 MB peak)
        │
   CADisplayLink (30 fps, main thread)
        │
   decodeQueue (concurrent)  ← UIImage(data:) off the main thread
        │
   UIImageView.image          ← CATransaction with animations disabled
```

**Delay logic**: on each display-link tick, the manager binary-searches the
ring buffer for the entry whose timestamp is closest to
`CACurrentMediaTime() - delay`. This gives sub-frame accuracy with O(log n)
lookup.

**Memory**: at 30 fps × 30 s × ~90 KB/frame ≈ **81 MB** worst-case. The ring
is capped at 33 s and frames older than that are pruned on every capture.

---

## Customisation

| What | Where | How |
|------|-------|-----|
| Capture resolution | `CameraManager.setupCaptureSession()` | Change `sessionPreset` (e.g. `.vga640x480` saves more RAM) |
| JPEG quality | `CameraManager.jpegQuality` | 0.6 – 0.9 trades quality for memory |
| Max delay | `ContentView` Slider range + `CameraManager.maxBufferDuration` | Increase both; watch RAM usage |
| Front camera | `setupCaptureSession()` | Change `position: .back` to `.front` |
| Landscape support | `CameraPreviewViewController.viewDidLoad` + `CameraManager.setupCaptureSession` | Observe `UIDevice.orientationDidChangeNotification` and update `connection.videoOrientation` |

---

## Requirements

- iOS 16.0+
- iPhone or iPad with a rear camera
- Xcode 15+ / Swift 5.9+
