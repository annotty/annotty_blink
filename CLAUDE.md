# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Annotty is a professional iPad segmentation annotation app designed for machine learning data preparation. It provides an intuitive drawing experience using Apple Pencil for creating pixel-perfect segmentation masks.

**Target Platform:** iPadOS 17+ (Apple Pencil required)
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
User Input (Apple Pencil / Gestures)
    ↓
GestureCoordinator (filters pencil vs finger, 32ms finger delay)
    ↓
CanvasViewModel (state orchestration, tool logic, undo/redo)
    ↓
MetalRenderer + TextureManager (GPU pipelines, texture management)
    ↓
Shaders.metal (brush stamp compute, mask compositing fragment)
    ↓
Display (MTKView + SwiftUI overlays)
```

### Key Components

| File | Responsibility |
|------|----------------|
| `CanvasViewModel.swift` | Central state coordinator. Manages drawing, fill, smooth, SAM modes. Handles undo/redo stack, image navigation, mask save/load. ~1900 lines. |
| `MetalRenderer.swift` | Metal pipeline setup. Render pipeline for canvas display, compute pipelines for brush stamps and mask clearing. |
| `TextureManager.swift` | GPU texture lifecycle. Manages image texture loading, mask texture creation at 2x resolution (max 4096px). |
| `GestureCoordinator.swift` | Input classification (pencil vs finger). Implements 32ms delay for finger drawing to allow 2-finger gesture detection. |
| `CanvasTransform.swift` | Coordinate transform matrix. Handles pan/zoom/rotate with screen-to-mask coordinate conversion. |
| `SAM2Service.swift` | SAM 2.1 CoreML inference. Supports Tiny (~11M params) and Small (~38M params) models with image embedding caching. |

### Mask System

- **Internal Format:** `UInt8` buffer with `MTLPixelFormat.r8Uint`
- **Value Range:** 0 = background, 1-8 = class IDs
- **Resolution:** 2x source image (clamped to 4096px max)
- **Persistence:** Color PNG in `annotations/` folder (class colors mapped to RGB)

### Class Colors (Must Match Exactly)

Class colors are defined in both `CanvasViewModel.classRGBColors` (for PNG save/load) and `MetalRenderer.classColors` (for GPU rendering):

| ClassID | Color | RGB |
|---------|-------|-----|
| 1 | Red | (255, 0, 0) |
| 2 | Orange | (255, 128, 0) |
| 3 | Yellow | (255, 255, 0) |
| 4 | Green | (0, 255, 0) |
| 5 | Cyan | (0, 255, 255) |
| 6 | Blue | (0, 0, 255) |
| 7 | Purple | (128, 0, 255) |
| 8 | Pink | (255, 102, 178) |

### Coordinate Spaces

1. **Touch coordinates:** UIKit points (logical pixels)
2. **Screen coordinates:** Physical pixels (`touch × contentScaleFactor`)
3. **Image coordinates:** Original image pixels
4. **Mask coordinates:** Mask texture pixels (`image × maskScaleFactor`)

Conversions flow through `CanvasTransform`:
- `screenToMask()` for drawing operations
- `screenToImage()` for SAM predictions
- Transform matrix applies pan, zoom, rotation

### Gesture System

The `GestureCoordinator` implements a critical 32ms delay for finger input:
- **Pencil:** Draws immediately (no delay)
- **Finger:** Waits 32ms before starting stroke
- **2+ fingers within 32ms:** Cancels pending stroke, enables navigation
- **2-finger tap:** Undo (with 300ms cooldown after navigation)
- **3-finger tap:** Redo

Tool modes (`isFillMode`, `isSAMMode`, `isSmoothMode`) are mutually exclusive.

### Undo System

Undo patches capture mask regions before modification:
- Large initial bbox (2000×2000 or texture size) to minimize expansion
- `UndoAction` stores: classID, bbox, previousPatch (Data)
- Expansion uses compositing to merge original + new regions

### SAM Integration

SAM 2.1 runs three CoreML models in sequence:
1. **ImageEncoder:** 1024×1024 input → image embedding (cached)
2. **PromptEncoder:** Points/labels → sparse/dense embeddings
3. **MaskDecoder:** Embeddings → 256×256 low-res masks (3 candidates)

Point labels: 1=foreground, 0=background, 2=bbox top-left, 3=bbox bottom-right

### QuickLine Feature

Hold pencil stationary for 1 second to convert freehand stroke to straight line:
- Detects movement < 5pt threshold
- Restores original patch, redraws as interpolated line

## Runtime Folder Structure

```
Documents/
├── images/          # Source images (PNG, JPG)
├── annotations/     # Color mask PNGs (auto-saved)
└── labels/          # Exported ML labels (COCO/YOLO)
```

## Critical Implementation Notes

### Metal Struct Alignment

`CanvasUniforms` must match Metal shader exactly. Use `MemoryLayout<T>.stride` not `.size` for buffer allocation.

### Thread Safety

- GPU texture reads (`getBytes`) block until complete
- Background saves capture mask data on main thread, write on background
- SAM predictions use `@MainActor` for UI state updates

### Auto-Save Triggers

- Image navigation (immediate, blocking)
- App backgrounding (`saveBeforeBackground()`)
- NOT on stroke end (performance)

## Export Formats

| Format | Service | Output |
|--------|---------|--------|
| PNG | `PNGExporter` | Color masks at mask resolution |
| COCO JSON | `COCOExporter` | Instance polygons via `ContourExtractor` |
| YOLO-seg | `YOLOExporter` | Normalized polygon coordinates |

## Development Notes

- Simulator testing: Finger input works for all tools (no pencil required)
- SAM models: Included in `Services/SAM/Models/` (~80MB total)
- No unit tests currently configured
