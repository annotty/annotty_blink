# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Annotty Blink is an iPad app for annotating blink (eye) data in images/video frames. It uses a 12-line annotation system to mark eye landmarks for machine learning training data preparation.

**Target Platform:** iPadOS 17+ (Apple Pencil + finger supported), Mac (Designed for iPad)
**Tech Stack:** SwiftUI + Metal (no external dependencies)

## Build Commands

```bash
# Open in Xcode
open Annotty.xcodeproj

# Build from command line
xcodebuild -scheme Annotty -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)'

# Run tests
xcodebuild test -scheme Annotty -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)'
```

## Architecture

### Data Flow

```
User Input (Apple Pencil / Finger)
    ↓
GestureCoordinator (filters input, cooldown after navigation)
    ↓
CanvasViewModel (line selection, position management, annotation persistence)
    ↓
MetalRenderer (image display) + LineOverlayView (SwiftUI line rendering)
    ↓
Display (MTKView + SwiftUI overlays)
```

### Key Components

| File | Responsibility |
|------|----------------|
| `CanvasViewModel.swift` | Central state coordinator. Manages line selection, drag operations, image navigation, annotation save/load. |
| `BlinkAnnotation.swift` | Data model for 12-line annotation (6 per eye) with normalized coordinates (0-1). |
| `BlinkAnnotationLoader.swift` | JSON persistence for annotations, keyed by image filename. |
| `LineOverlayView.swift` | SwiftUI Canvas view for rendering annotation lines over the image. |
| `GestureCoordinator.swift` | Input handling with cooldown after pan/zoom to prevent accidental line moves. |
| `MetalRenderer.swift` | Metal pipeline for image display with brightness/contrast adjustments. |
| `CanvasTransform.swift` | Coordinate transform matrix for pan/zoom/rotate operations. |

### Platform Abstraction Layer (`Platform/`)

Cross-platform input handling for iOS and Mac (Designed for iPad):

| File | Responsibility |
|------|----------------|
| `PlatformTypes.swift` | Type aliases (`PlatformColor`, `PlatformImage`) and platform-specific extensions. |
| `InputCoordinatorProtocol.swift` | Protocol defining keyboard event handling interface. |
| `iOSInputCoordinator.swift` | iOS implementation (hardware keyboard via pressesBegan). |
| `macOSInputCoordinator.swift` | Mac implementation using NSEvent keyboard monitor for arrow key navigation. |

**Arrow key navigation:** On Mac, arrow keys (↑↓) cycle through line types. This uses `NSEvent.addLocalMonitorForEvents` to intercept keys before they trigger system beeps.

### 12-Line Annotation System

Each eye has 6 lines (12 total):

| # | Eye | Line Type | Direction | Color |
|---|-----|-----------|-----------|-------|
| 0 | Right | Pupil Center Vertical | Vertical (full height) | Red |
| 1 | Right | Pupil Center Horizontal | Horizontal (short) | Orange |
| 2 | Right | Upper Brow | Horizontal (short) | Yellow |
| 3 | Right | Lower Brow | Horizontal (short) | Green |
| 4 | Right | Upper Eyelid | Horizontal (short) | Cyan |
| 5 | Right | Lower Eyelid | Horizontal (short) | Blue |
| 6 | Left | Pupil Center Vertical | Vertical (full height) | Magenta |
| 7 | Left | Pupil Center Horizontal | Horizontal (short) | Purple |
| 8 | Left | Upper Brow | Horizontal (short) | Pink |
| 9 | Left | Lower Brow | Horizontal (short) | Olive |
| 10 | Left | Upper Eyelid | Horizontal (short) | Teal |
| 11 | Left | Lower Eyelid | Horizontal (short) | Brown |

**Horizontal line behavior:**
- Short lines (~20px total width centered on vertical line)
- Moving vertical line also moves associated horizontal lines

### Coordinate System

- **Annotation coordinates:** Normalized 0-1 range (resolution-independent)
- **Touch coordinates:** UIKit points converted via `CanvasTransform`
- **Display:** `LineOverlayView` converts normalized → screen coordinates

Conversions use `CanvasTransform`:
- `screenToImage()` for touch → normalized coordinate conversion
- Transform matrix applies pan, zoom, rotation

### Gesture System

The `GestureCoordinator` handles input with navigation protection:

- **Line dragging:** Touch near selected line, drag to move
- **Relative dragging:** Movement is delta-based, not absolute positioning
- **Cooldown:** 0.2s delay after pan/zoom/rotate before allowing line drag
- **2-finger:** Pan and zoom navigation
- **Rotation:** Two-finger rotate gesture

### Annotation Persistence

- **Format:** JSON file `annotations/blink_annotations.json`
- **Key:** Image filename (e.g., `frame_001.png`)
- **Auto-save:** On image navigation and app backgrounding
- **Inheritance:** New images inherit line positions from previous frame

## Runtime Folder Structure

```
Documents/
├── images/              # Source images (PNG, JPG)
├── annotations/
│   └── blink_annotations.json  # Line position data
└── exports/             # Exported mask images
```

## Export Format

Export creates a timestamped folder with the following structure:

```
Annotty_export_YYYYMMDD_HHMMSS/
├── images/                    # Original images (optional)
├── labels/                    # Mask images
│   └── {basename}_label.png   # Black background + colored lines
└── blink_annotations.json     # All annotations in JSON
```

| Option | Description |
|--------|-------------|
| Original Images | Copy source images to `images/` folder |
| Label Masks | Black background with colored lines (1px width) |
| JSON Coordinates | Normalized 0-1 line positions |

**Mac export:** Folder picker available to choose export destination.

## UI Layout

```
┌─────────────────────────────────────────────────────────┐
│ [Load] [↻]          ◀ 12/128 ▶ 🗑      [Fit] [Clear] [Export] │  ← Top Bar
├───────────────────────────────────────────┬─────────────┤
│                                           │ Right Eye   │
│                                           │ ● Pupil V   │
│            Canvas (Metal + Overlay)       │ ○ Pupil H   │
│                                           │ ○ Upper Brow│
│                                           │ ...         │
│                                           ├─────────────┤
│                                           │ Left Eye    │
│                                           │ ○ Pupil V   │
│                                           │ ...         │
│                                           ├─────────────┤
│                                           │ [Settings]  │
└───────────────────────────────────────────┴─────────────┘
```

- **Right Panel:** Line selection (tap to select, 👁 to toggle visibility)
- **Canvas:** Image display with line overlay
- **Settings:** Image brightness/contrast adjustment

## Critical Implementation Notes

### Transform Version Counter

`CanvasViewModel.transformVersion` increments on pan/zoom/rotate to trigger `LineOverlayView` re-render for proper line positioning.

### Relative Dragging

Line positions update using delta from drag start, not absolute touch position:
```swift
let delta = currentNormalizedPoint - dragStartNormalizedPoint
newPosition = dragStartLinePosition + delta
```

### Image-Based Annotation Keys

Annotations use image filename as key (not index) to preserve data when images are added/removed:
```swift
var annotations: [String: BlinkAnnotation]  // key = "frame_001.png"
```

### Auto-Save Triggers

- Image navigation (before switching)
- App backgrounding (`saveBeforeBackground()`)
- Image deletion (removes annotation data too)

## Development Notes

- Simulator testing: Finger input works for all operations
- New images are appended to end of list (not sorted alphabetically)
- Delete button in navigator removes image + annotation data
- Video frame extraction via `VideoFrameExtractor` (for future use)

### Mac Compatibility (Designed for iPad)

The app runs on Mac via "Designed for iPad". Key considerations:

- **Platform detection:** Use `ProcessInfo.processInfo.isiOSAppOnMac` to detect Mac at runtime
- **`#if os(macOS)` blocks are NOT compiled** - iOS code paths are used
- **File dialogs:** Use SwiftUI `.fileImporter()` modifier (works on iOS-on-Mac), never `NSOpenPanel.runModal()` (causes freeze)
- **Heavy operations:** Use `Task.detached` to avoid blocking MainActor
- **Keyboard events:** Use `NSEvent.addLocalMonitorForEvents` for arrow keys (not `keyDown` override)
- **Share button:** Hidden on Mac (uses folder picker for export instead)

### PlatformColor Extension Warning

**NEVER add extension properties to `PlatformColor` (UIColor/NSColor) with names that already exist in the base class.**

Bad example (causes infinite recursion crash):
```swift
extension PlatformColor {
    static var secondarySystemBackground: PlatformColor {
        return UIColor.secondarySystemBackground  // Calls itself!
    }
}
```

iOS already has `UIColor.secondarySystemBackground`. Adding an extension with the same name shadows it and causes infinite recursion → stack overflow → `EXC_BAD_ACCESS`.

Solution: Only add these properties for macOS where they don't exist:
```swift
#if os(macOS)
extension PlatformColor {
    static var secondarySystemBackground: PlatformColor {
        return NSColor.controlBackgroundColor
    }
}
#endif
```

## Pre-Commit Checklist

**Before completing work, verify:**

### 1. Remove duplicate CLAUDE.md files
Xcode includes subdirectory CLAUDE.md files in builds, causing errors. Only the root CLAUDE.md should exist.

```bash
# Find and delete duplicates
find . -name "CLAUDE.md" ! -path "./CLAUDE.md" -print -delete

# Clear DerivedData if cached errors persist
rm -rf ~/Library/Developer/Xcode/DerivedData/Annotty-*
```

### 2. Verify build succeeds
```bash
xcodebuild -scheme Annotty -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' build 2>&1 | grep -E "(BUILD SUCCEEDED|BUILD FAILED|error:)"
```
