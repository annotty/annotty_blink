# Repository Guidelines

## Project Structure & Module Organization
Runtime code lives in `Annotty/`, grouped by responsibility: `App/` configures the SwiftUI entry point, `Views/` and `ViewModels/` drive the UI, `Services/` handles persistence + exports, `Metal/` contains GPU pipeline helpers, and `Gestures/` plus `Utils/` provide shared abstractions. Platform-specific shims sit under `Platform/`, and app assets belong in `Assets.xcassets/` with supporting screenshots under `assets/`.

## Build, Test, and Development Commands
Open the project with `open Annotty.xcodeproj` for day-to-day development. For CI-friendly builds, run `xcodebuild -scheme Annotty -destination 'platform=iOS Simulator,name=iPad Pro (11-inch) (4th generation)' build` to verify compilation on the default iPadOS target. Execute the same command with `test` instead of `build` to run XCTest suites once they exist.

## Coding Style & Naming Conventions
Follow the existing Swift 5.9 style: four-space indentation, `CamelCase` for types, and `lowerCamelCase` for properties and functions. Prefer structs + value semantics for view models, keep view-specific modifiers in extensions, and align property wrappers (`@State`, `@EnvironmentObject`) vertically for readability. SwiftUI previews should match the directory of the component they document, and file names must match the primary type (e.g., `MainView.swift`).

## Testing Guidelines
New tests should live in an `AnnottyTests/` target created alongside the app target and should import `@testable Annotty`. Use XCTest naming such as `testFeature_StateUnderTest_ExpectedResult`. Target at least smoke coverage for gesture flows, view-model logic, and service serialization before merging feature branches. Until automated UI tests are added, include screen recordings for risky interaction changes.

## Commit & Pull Request Guidelines
Commits follow the short, imperative pattern already in history (`Update CLAUDE.md for blink annotation architecture`, `Transform app from brush-based segmentation to blink annotation`). Keep subjects under ~70 characters and describe why in the body when the diff is non-trivial. Pull requests must summarize scope, list test commands, attach relevant screenshots or exports, and reference linked issues. Draft PRs are encouraged for early feedback but should still include a checklist of pending items.

## Security & Configuration Tips
Do not commit proprietary datasets or Core ML weights; reference their local path in documentation instead. Store API keys or experiment toggles in user-specific `.xcconfig` files ignored by git, and load them via `ProcessInfo.processInfo.environment`. Review third-party notices before adding dependencies, and confirm any new binary resources are cleared for redistribution.
