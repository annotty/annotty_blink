import AVFoundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Service for extracting frames from video files
class VideoFrameExtractor {

    enum ExtractionError: Error, LocalizedError {
        case cannotLoadAsset
        case cannotCreateImageGenerator
        case invalidVideoDuration
        case extractionFailed(String)

        var errorDescription: String? {
            switch self {
            case .cannotLoadAsset:
                return "Cannot load video asset"
            case .cannotCreateImageGenerator:
                return "Cannot create image generator"
            case .invalidVideoDuration:
                return "Invalid video duration"
            case .extractionFailed(let message):
                return "Frame extraction failed: \(message)"
            }
        }
    }

    /// Extract frames from a video at a specified frame rate
    /// - Parameters:
    ///   - videoURL: URL of the video file
    ///   - fps: Frames per second to extract
    ///   - progress: Progress callback (0.0 - 1.0)
    /// - Returns: Array of URLs to extracted frame images
    func extractFrames(
        from videoURL: URL,
        fps: Double,
        progress: @escaping (Double) -> Void
    ) async throws -> [URL] {
        let asset = AVAsset(url: videoURL)

        // Load duration
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)

        guard durationSeconds > 0 else {
            throw ExtractionError.invalidVideoDuration
        }

        // Create image generator
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceBefore = CMTime(seconds: 0.01, preferredTimescale: 600)
        imageGenerator.requestedTimeToleranceAfter = CMTime(seconds: 0.01, preferredTimescale: 600)

        // Calculate frame times
        let frameInterval = 1.0 / fps
        var frameTimes: [CMTime] = []
        var currentTime = 0.0

        while currentTime < durationSeconds {
            let cmTime = CMTime(seconds: currentTime, preferredTimescale: 600)
            frameTimes.append(cmTime)
            currentTime += frameInterval
        }

        let totalFrames = frameTimes.count
        print("[VideoFrameExtractor] Extracting \(totalFrames) frames at \(fps) FPS from \(String(format: "%.1f", durationSeconds))s video")

        // Get video basename for frame naming
        let videoBasename = videoURL.deletingPathExtension().lastPathComponent

        // Create output directory
        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("extracted_frames_\(UUID().uuidString)")

        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        // Extract frames
        var extractedURLs: [URL] = []

        for (index, time) in frameTimes.enumerated() {
            do {
                let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)

                // Save as PNG with format: {videoBasename}_frame{number}.png
                let frameNumber = String(format: "%05d", index)
                let frameURL = outputDir.appendingPathComponent("\(videoBasename)_frame\(frameNumber).png")

                if saveCGImageAsPNG(cgImage, to: frameURL) {
                    extractedURLs.append(frameURL)
                }

                // Report progress
                let currentProgress = Double(index + 1) / Double(totalFrames)
                progress(currentProgress)

            } catch {
                print("[VideoFrameExtractor] Failed to extract frame \(index): \(error)")
                // Continue with next frame instead of failing completely
            }
        }

        print("[VideoFrameExtractor] Successfully extracted \(extractedURLs.count) frames")
        return extractedURLs
    }

    /// Extract frames at specific time points
    /// - Parameters:
    ///   - videoURL: URL of the video file
    ///   - times: Array of time points in seconds
    ///   - progress: Progress callback
    /// - Returns: Array of URLs to extracted frame images
    func extractFrames(
        from videoURL: URL,
        atTimes times: [Double],
        progress: @escaping (Double) -> Void
    ) async throws -> [URL] {
        let asset = AVAsset(url: videoURL)

        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceBefore = CMTime(seconds: 0.01, preferredTimescale: 600)
        imageGenerator.requestedTimeToleranceAfter = CMTime(seconds: 0.01, preferredTimescale: 600)

        // Get video basename for frame naming
        let videoBasename = videoURL.deletingPathExtension().lastPathComponent

        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("extracted_frames_\(UUID().uuidString)")

        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        var extractedURLs: [URL] = []
        let totalFrames = times.count

        for (index, timeSeconds) in times.enumerated() {
            let cmTime = CMTime(seconds: timeSeconds, preferredTimescale: 600)

            do {
                let cgImage = try imageGenerator.copyCGImage(at: cmTime, actualTime: nil)

                // Save as PNG with format: {videoBasename}_frame{number}.png
                let frameNumber = String(format: "%05d", index)
                let frameURL = outputDir.appendingPathComponent("\(videoBasename)_frame\(frameNumber).png")

                if saveCGImageAsPNG(cgImage, to: frameURL) {
                    extractedURLs.append(frameURL)
                }

                let currentProgress = Double(index + 1) / Double(totalFrames)
                progress(currentProgress)

            } catch {
                print("[VideoFrameExtractor] Failed to extract frame at \(timeSeconds)s: \(error)")
            }
        }

        return extractedURLs
    }

    /// Get video information
    func getVideoInfo(from videoURL: URL) async throws -> VideoInfo {
        let asset = AVAsset(url: videoURL)

        let duration = try await asset.load(.duration)
        let tracks = try await asset.load(.tracks)

        var width: Int = 0
        var height: Int = 0
        var frameRate: Float = 0

        if let videoTrack = tracks.first(where: { $0.mediaType == .video }) {
            let naturalSize = try await videoTrack.load(.naturalSize)
            let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)

            width = Int(naturalSize.width)
            height = Int(naturalSize.height)
            frameRate = nominalFrameRate
        }

        return VideoInfo(
            duration: CMTimeGetSeconds(duration),
            width: width,
            height: height,
            frameRate: frameRate
        )
    }

    // MARK: - Private Helpers

    /// Save CGImage as PNG file (cross-platform)
    private func saveCGImageAsPNG(_ image: CGImage, to url: URL) -> Bool {
        #if os(iOS)
        let uiImage = UIImage(cgImage: image)
        guard let pngData = uiImage.pngData() else { return false }
        do {
            try pngData.write(to: url)
            return true
        } catch {
            return false
        }
        #elseif os(macOS)
        let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        guard let tiffData = nsImage.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            return false
        }
        do {
            try pngData.write(to: url)
            return true
        } catch {
            return false
        }
        #endif
    }
}

/// Video metadata
struct VideoInfo {
    let duration: Double
    let width: Int
    let height: Int
    let frameRate: Float

    var estimatedFrameCount: Int {
        return Int(duration * Double(frameRate))
    }
}
