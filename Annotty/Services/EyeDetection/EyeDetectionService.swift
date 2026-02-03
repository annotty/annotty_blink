import CoreML
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// MARK: - Result Types

struct EyeDetectionResult {
    let leftEye: EyeAnnotation?
    let rightEye: EyeAnnotation?
}

struct EyeAnnotation {
    let pupilCenterX: CGFloat?  // nil = iris not found, inherit from previous frame
    let pupilCenterY: CGFloat?  // nil = iris not found, inherit from previous frame
    let upperLidY: CGFloat
    let lowerLidY: CGFloat
}

// MARK: - Service

final class EyeDetectionService {
    static let shared = EyeDetectionService()

    private var yoloModel: MLModel?
    private var segformerModel: MLModel?
    private var isLoaded = false

    /// YOLO class indices: 0 = Right_eye, 1 = Left_eye
    private let rightEyeClassIndex = 0
    private let leftEyeClassIndex = 1

    private init() {}

    // MARK: - Model Loading

    func loadModels() throws {
        guard !isLoaded else { return }

        let config = MLModelConfiguration()
        config.computeUnits = .all

        yoloModel = try loadMLModel(named: "detect_yolo11n", configuration: config)
        segformerModel = try loadMLModel(named: "seg_segformer_b3", configuration: config)

        isLoaded = true
        print("[EyeDetection] Models loaded")
    }

    private func loadMLModel(named name: String, configuration: MLModelConfiguration) throws -> MLModel {
        if let compiledURL = Bundle.main.url(forResource: name, withExtension: "mlmodelc") {
            return try MLModel(contentsOf: compiledURL, configuration: configuration)
        }
        if let packageURL = Bundle.main.url(forResource: name, withExtension: "mlpackage") {
            let compiledURL = try MLModel.compileModel(at: packageURL)
            return try MLModel(contentsOf: compiledURL, configuration: configuration)
        }
        throw EyeDetectionError.modelNotFound(name)
    }

    // MARK: - Full Pipeline

    func detect(imageURL: URL) async throws -> EyeDetectionResult {
        try loadModels()

        guard let cgImage = loadCGImage(from: imageURL) else {
            throw EyeDetectionError.imageLoadFailed
        }

        let imageW = CGFloat(cgImage.width)
        let imageH = CGFloat(cgImage.height)

        // Step 1: YOLO detection -- outputs normalized cx, cy, w, h
        let detections = try runYOLO(on: cgImage)

        var leftEyeBox: (cx: CGFloat, cy: CGFloat, w: CGFloat, h: CGFloat)?
        var rightEyeBox: (cx: CGFloat, cy: CGFloat, w: CGFloat, h: CGFloat)?
        var leftConf: Float = 0
        var rightConf: Float = 0

        for det in detections {
            if det.classIndex == leftEyeClassIndex && det.confidence > leftConf {
                leftEyeBox = det.box
                leftConf = det.confidence
            } else if det.classIndex == rightEyeClassIndex && det.confidence > rightConf {
                rightEyeBox = det.box
                rightConf = det.confidence
            }
        }

        print("[EyeDetection] YOLO: L=\(String(format:"%.2f",leftConf)) R=\(String(format:"%.2f",rightConf)) total=\(detections.count)")

        // Step 2: SegFormer for each detected eye
        let leftResult = try processEye(cgImage: cgImage, normalizedBox: leftEyeBox, imageW: imageW, imageH: imageH, eyeLabel: "L")
        let rightResult = try processEye(cgImage: cgImage, normalizedBox: rightEyeBox, imageW: imageW, imageH: imageH, eyeLabel: "R")

        if leftResult == nil && rightResult == nil {
            let hasBoxes = leftEyeBox != nil || rightEyeBox != nil
            throw EyeDetectionError.inferenceError(
                hasBoxes ? "SegFormer post-processing returned nil for both eyes" : "No eye bboxes detected"
            )
        }

        return EyeDetectionResult(leftEye: leftResult, rightEye: rightResult)
    }

    // MARK: - YOLO (MLModel direct)

    private struct YOLODetection {
        let classIndex: Int
        let confidence: Float
        /// Normalized 0-1: (center_x, center_y, width, height)
        let box: (cx: CGFloat, cy: CGFloat, w: CGFloat, h: CGFloat)
    }

    private func runYOLO(on cgImage: CGImage) throws -> [YOLODetection] {
        guard let model = yoloModel else {
            throw EyeDetectionError.modelNotLoaded
        }

        let inputDesc = model.modelDescription.inputDescriptionsByName
        let imageFeature: MLFeatureValue
        if let imageDesc = inputDesc["image"], imageDesc.type == .image,
           let constraint = imageDesc.imageConstraint {
            imageFeature = try MLFeatureValue(cgImage: cgImage, constraint: constraint, options: [:])
        } else {
            let pixelBuffer = try createPixelBuffer(from: cgImage, width: 640, height: 640)
            imageFeature = MLFeatureValue(pixelBuffer: pixelBuffer)
        }

        let input = try MLDictionaryFeatureProvider(dictionary: [
            "image": imageFeature,
            "iouThreshold": MLFeatureValue(double: 0.45),
            "confidenceThreshold": MLFeatureValue(double: 0.25)
        ])

        let output = try model.prediction(from: input)

        guard let confidence = output.featureValue(for: "confidence")?.multiArrayValue,
              let coordinates = output.featureValue(for: "coordinates")?.multiArrayValue else {
            throw EyeDetectionError.inferenceError("YOLO missing confidence/coordinates outputs")
        }

        // confidence: (N, numClasses), coordinates: (N, 4) where 4 = cx, cy, w, h normalized
        let n = confidence.shape[0].intValue
        let numClasses = confidence.shape.count > 1 ? confidence.shape[1].intValue : 2
        var detections: [YOLODetection] = []

        for i in 0..<n {
            var maxConf: Float = 0
            var maxClass = 0
            for c in 0..<numClasses {
                let val = confidence[[i, c] as [NSNumber]].floatValue
                if val > maxConf {
                    maxConf = val
                    maxClass = c
                }
            }

            guard maxConf > 0.25 else { continue }

            let cx = CGFloat(coordinates[[i, 0] as [NSNumber]].floatValue)
            let cy = CGFloat(coordinates[[i, 1] as [NSNumber]].floatValue)
            let w  = CGFloat(coordinates[[i, 2] as [NSNumber]].floatValue)
            let h  = CGFloat(coordinates[[i, 3] as [NSNumber]].floatValue)

            detections.append(YOLODetection(
                classIndex: maxClass,
                confidence: maxConf,
                box: (cx: cx, cy: cy, w: w, h: h)
            ))
        }

        return detections
    }

    // MARK: - SegFormer per Eye

    private func processEye(
        cgImage: CGImage,
        normalizedBox: (cx: CGFloat, cy: CGFloat, w: CGFloat, h: CGFloat)?,
        imageW: CGFloat, imageH: CGFloat,
        eyeLabel: String
    ) throws -> EyeAnnotation? {
        guard let box = normalizedBox else { return nil }

        // Convert normalized coords to pixel coords (top-left origin)
        let pixCx = box.cx * imageW
        let pixCy = box.cy * imageH
        let pixW  = box.w * imageW
        let pixH  = box.h * imageH

        // Expand ROI by 50% and make it square
        let halfSide = max(pixW, pixH) * 1.5 / 2.0

        let roiX1 = max(0, pixCx - halfSide)
        let roiY1 = max(0, pixCy - halfSide)
        let roiX2 = min(imageW, pixCx + halfSide)
        let roiY2 = min(imageH, pixCy + halfSide)

        let roiRect = CGRect(x: roiX1, y: roiY1, width: roiX2 - roiX1, height: roiY2 - roiY1)
        guard roiRect.width > 0 && roiRect.height > 0 else {
            throw EyeDetectionError.inferenceError("ROI empty for eye \(eyeLabel)")
        }

        guard let croppedImage = cgImage.cropping(to: roiRect) else {
            throw EyeDetectionError.inferenceError("Crop failed for eye \(eyeLabel)")
        }

        let mask = try runSegFormer(on: croppedImage)

        return try extractAnnotation(
            from: mask,
            roiRect: roiRect,
            imageW: imageW,
            imageH: imageH,
            debugLabel: eyeLabel,
            roiImage: croppedImage
        )
    }

    // MARK: - SegFormer Inference

    private func runSegFormer(on cgImage: CGImage) throws -> MLMultiArray {
        guard let model = segformerModel else {
            throw EyeDetectionError.modelNotLoaded
        }

        let pixelBuffer = try createPixelBuffer(from: cgImage, width: 512, height: 512, flipY: false)
        let input = try MLDictionaryFeatureProvider(dictionary: [
            "image": MLFeatureValue(pixelBuffer: pixelBuffer)
        ])

        let output = try model.prediction(from: input)

        guard let logits = output.featureValue(for: "logits")?.multiArrayValue else {
            throw EyeDetectionError.inferenceError("No 'logits' output")
        }

        return logits
    }

    // MARK: - Post-processing

    /// Minimum iris pixel count to consider a valid detection
    private let minIrisPixels = 100

    /// Extract pupil center and eyelid Y from segmentation logits using sigmoid multi-label.
    /// Logits shape: (1, 3, 512, 512) -- channels: 0=eyelid, 1=iris, 2=pupil
    private func extractAnnotation(
        from logits: MLMultiArray,
        roiRect: CGRect,
        imageW: CGFloat,
        imageH: CGFloat,
        debugLabel: String = "",
        roiImage: CGImage? = nil
    ) throws -> EyeAnnotation? {
        let shape = logits.shape.map { $0.intValue }
        guard shape.count >= 4, shape[1] >= 3, shape[2] > 0, shape[3] > 0 else {
            throw EyeDetectionError.inferenceError("Unexpected logits shape: \(shape)")
        }
        let maskH = shape[2]
        let maskW = shape[3]

        // Sigmoid per-channel -> binary masks at threshold 0.5
        // Channel mapping: 0=eyelid, 1=iris, 2=pupil
        let threshold: Float = 0.5
        let totalPixels = maskH * maskW
        var irisMask = [Bool](repeating: false, count: totalPixels)
        var eyelidMask = [Bool](repeating: false, count: totalPixels)
        var pupilMask = [Bool](repeating: false, count: totalPixels)

        var irisSumX: CGFloat = 0
        var irisSumY: CGFloat = 0
        var irisCount = 0

        for y in 0..<maskH {
            for x in 0..<maskW {
                let eyelidLogit = logits[[0, 0, y, x] as [NSNumber]].floatValue
                let irisLogit = logits[[0, 1, y, x] as [NSNumber]].floatValue
                let pupilLogit = logits[[0, 2, y, x] as [NSNumber]].floatValue

                let idx = y * maskW + x
                if 1.0 / (1.0 + exp(-eyelidLogit)) > threshold {
                    eyelidMask[idx] = true
                }
                if 1.0 / (1.0 + exp(-irisLogit)) > threshold {
                    irisMask[idx] = true
                    irisSumX += CGFloat(x)
                    irisSumY += CGFloat(y)
                    irisCount += 1
                }
                if 1.0 / (1.0 + exp(-pupilLogit)) > threshold {
                    pupilMask[idx] = true
                }
            }
        }

        // Iris centroid -> pupil center (nil if iris too small)
        let pupilCenterMaskX: CGFloat? = irisCount >= minIrisPixels ? irisSumX / CGFloat(irisCount) : nil
        let pupilCenterMaskY: CGFloat? = irisCount >= minIrisPixels ? irisSumY / CGFloat(irisCount) : nil

        // Eyelid boundary from eyelid mask at iris center X column (fallback: center of mask)
        let colX: Int
        if let pcx = pupilCenterMaskX {
            colX = max(0, min(maskW - 1, Int(pcx.rounded())))
        } else {
            colX = maskW / 2
        }

        // Scan the eyelid mask column to find topmost and bottommost eyelid pixels
        var topY: Int? = nil
        var botY: Int? = nil
        for y in 0..<maskH {
            if eyelidMask[y * maskW + colX] {
                if topY == nil { topY = y }
                botY = y
            }
        }

        guard let upperY = topY, let lowerY = botY, upperY < lowerY else {
            let eyelidCount = eyelidMask.filter { $0 }.count
            if eyelidCount == 0 {
                throw EyeDetectionError.inferenceError("[\(debugLabel)] No eyelid pixels detected")
            }
            throw EyeDetectionError.inferenceError("[\(debugLabel)] No eyelid span at col \(colX)")
        }

        saveSegmentationDebugImages(
            eyelidMask: eyelidMask,
            irisMask: irisMask,
            pupilMask: pupilMask,
            maskW: maskW,
            maskH: maskH,
            roiImage: roiImage,
            pupilCenterMaskX: pupilCenterMaskX,
            pupilCenterMaskY: pupilCenterMaskY,
            upperY: upperY,
            lowerY: lowerY,
            colX: colX,
            debugLabel: debugLabel
        )

        // Convert mask coords -> ROI pixel -> original image -> normalized 0-1
        let roiW = roiRect.width
        let roiH = roiRect.height

        let normPupilX: CGFloat? = pupilCenterMaskX.map { clamp01((roiRect.origin.x + $0 * roiW / CGFloat(maskW)) / imageW) }
        let normPupilY: CGFloat? = pupilCenterMaskY.map { clamp01((roiRect.origin.y + $0 * roiH / CGFloat(maskH)) / imageH) }
        let normUpperY = clamp01((roiRect.origin.y + CGFloat(upperY) * roiH / CGFloat(maskH)) / imageH)
        let normLowerY = clamp01((roiRect.origin.y + CGFloat(lowerY) * roiH / CGFloat(maskH)) / imageH)

        print("[EyeDetection] [\(debugLabel)] pupil=(\(normPupilX as Any), \(normPupilY as Any)) upper=\(String(format:"%.4f",normUpperY)) lower=\(String(format:"%.4f",normLowerY))")

        return EyeAnnotation(
            pupilCenterX: normPupilX,
            pupilCenterY: normPupilY,
            upperLidY: normUpperY,
            lowerLidY: normLowerY
        )
    }

    // MARK: - Helpers

    private func loadCGImage(from url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        return cgImage
    }

    private func createPixelBuffer(from cgImage: CGImage, width: Int, height: Int, flipY: Bool = true) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, width, height,
            kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pixelBuffer
        )
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            throw EyeDetectionError.inferenceError("Failed to create pixel buffer")
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let ctx = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width, height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            throw EyeDetectionError.inferenceError("Failed to create CGContext")
        }

        if flipY {
            ctx.translateBy(x: 0, y: CGFloat(height))
            ctx.scaleBy(x: 1.0, y: -1.0)
        }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }

    private func clamp01(_ v: CGFloat) -> CGFloat {
        max(0, min(1, v))
    }

    // MARK: - Debug Image Saving (gated by ANNOTTY_SAVE_SEG_MASKS=1)

    private func saveSegmentationDebugImages(
        eyelidMask: [Bool], irisMask: [Bool], pupilMask: [Bool],
        maskW: Int, maskH: Int,
        roiImage: CGImage?,
        pupilCenterMaskX: CGFloat?, pupilCenterMaskY: CGFloat?,
        upperY: Int, lowerY: Int, colX: Int,
        debugLabel: String
    ) {
        guard ProcessInfo.processInfo.environment["ANNOTTY_SAVE_SEG_MASKS"] == "1",
              let dir = debugOutputDirectory() else { return }

        let ts = Self.debugTimestamp()

        if let merged = makeMergedMaskImage(eyelidMask: eyelidMask, irisMask: irisMask, pupilMask: pupilMask, width: maskW, height: maskH) {
            saveCGImageAsPNG(merged, to: dir.appendingPathComponent("\(ts)_\(debugLabel)_mask.png"))
        }

        if let roiImage,
           let overlay = makeOverlayImage(
               baseImage: roiImage, eyelidMask: eyelidMask, irisMask: irisMask, pupilMask: pupilMask,
               maskW: maskW, maskH: maskH,
               pupilCenterMaskX: pupilCenterMaskX, pupilCenterMaskY: pupilCenterMaskY,
               upperY: upperY, lowerY: lowerY, colX: colX
           ) {
            saveCGImageAsPNG(overlay, to: dir.appendingPathComponent("\(ts)_\(debugLabel)_overlay.png"))
        }

        if let roiImage {
            saveCGImageAsPNG(roiImage, to: dir.appendingPathComponent("\(ts)_\(debugLabel)_roi.png"))
        }
    }

    private func debugOutputDirectory() -> URL? {
        guard let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("AnnottySegFormerDebug", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func saveCGImageAsPNG(_ image: CGImage, to url: URL) {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, image, nil)
        if CGImageDestinationFinalize(dest) {
            print("[EyeDetection] Saved debug image: \(url.lastPathComponent)")
        }
    }

    private static func debugTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss_SSS"
        return formatter.string(from: Date())
    }

    private func makeMergedMaskImage(
        eyelidMask: [Bool], irisMask: [Bool], pupilMask: [Bool],
        width: Int, height: Int
    ) -> CGImage? {
        let count = width * height
        var rgba = [UInt8](repeating: 0, count: count * 4)
        for i in 0..<count {
            let base = i * 4
            rgba[base]     = eyelidMask[i] ? 255 : 0  // R = eyelid
            rgba[base + 1] = irisMask[i] ? 255 : 0    // G = iris
            rgba[base + 2] = pupilMask[i] ? 255 : 0   // B = pupil
            rgba[base + 3] = 255
        }
        return cgImageFromRGBA(rgba, width: width, height: height)
    }

    private func makeOverlayImage(
        baseImage: CGImage,
        eyelidMask: [Bool], irisMask: [Bool], pupilMask: [Bool],
        maskW: Int, maskH: Int,
        pupilCenterMaskX: CGFloat?, pupilCenterMaskY: CGFloat?,
        upperY: Int, lowerY: Int, colX: Int,
        alpha: Float = 0.35
    ) -> CGImage? {
        guard var baseRGBA = renderRGBA(from: baseImage, width: maskW, height: maskH) else { return nil }
        let count = maskW * maskH
        let blend = 1 - alpha

        for i in 0..<count {
            let idx = i * 4
            var r = Float(baseRGBA[idx])
            var g = Float(baseRGBA[idx + 1])
            var b = Float(baseRGBA[idx + 2])

            if eyelidMask[i] { r = r * blend + 255 * alpha }
            if irisMask[i]   { g = g * blend + 255 * alpha }
            if pupilMask[i]  { b = b * blend + 255 * alpha }

            baseRGBA[idx]     = UInt8(max(0, min(255, Int(r))))
            baseRGBA[idx + 1] = UInt8(max(0, min(255, Int(g))))
            baseRGBA[idx + 2] = UInt8(max(0, min(255, Int(b))))
            baseRGBA[idx + 3] = 255
        }

        drawAnnotationLines(
            on: &baseRGBA, width: maskW, height: maskH,
            pupilCenterX: pupilCenterMaskX, pupilCenterY: pupilCenterMaskY,
            upperY: upperY, lowerY: lowerY, colX: colX
        )

        return cgImageFromRGBA(baseRGBA, width: maskW, height: maskH)
    }

    private func drawAnnotationLines(
        on rgba: inout [UInt8], width: Int, height: Int,
        pupilCenterX: CGFloat?, pupilCenterY: CGFloat?,
        upperY: Int, lowerY: Int, colX: Int
    ) {
        func setPixel(x: Int, y: Int, r: UInt8, g: UInt8, b: UInt8) {
            guard x >= 0, x < width, y >= 0, y < height else { return }
            let idx = (y * width + x) * 4
            rgba[idx] = r; rgba[idx + 1] = g; rgba[idx + 2] = b; rgba[idx + 3] = 255
        }

        let lineHalfWidth = 40
        let lineThickness = 2
        let centerX = max(0, min(width - 1, colX))

        // Vertical red line at pupil column
        for t in 0..<lineThickness {
            for y in 0..<height {
                setPixel(x: centerX + t, y: y, r: 255, g: 0, b: 0)
            }
        }

        // Horizontal orange line at pupil center Y
        if let cy = pupilCenterY {
            let y = max(0, min(height - 1, Int(cy.rounded())))
            for t in 0..<lineThickness {
                for x in (centerX - lineHalfWidth)...(centerX + lineHalfWidth) {
                    setPixel(x: x, y: y + t, r: 255, g: 165, b: 0)
                }
            }
        }

        // Upper (cyan) and lower (blue) eyelid lines
        let upper = max(0, min(height - 1, upperY))
        let lower = max(0, min(height - 1, lowerY))
        for t in 0..<lineThickness {
            for x in (centerX - lineHalfWidth)...(centerX + lineHalfWidth) {
                setPixel(x: x, y: upper + t, r: 0, g: 255, b: 255)
                setPixel(x: x, y: lower + t, r: 0, g: 100, b: 255)
            }
        }

        // Crosshair at pupil center
        if let cx = pupilCenterX, let cy = pupilCenterY {
            let x = max(0, min(width - 1, Int(cx.rounded())))
            let y = max(0, min(height - 1, Int(cy.rounded())))
            for d in -8...8 {
                setPixel(x: x, y: y + d, r: 255, g: 255, b: 0)
                setPixel(x: x + d, y: y, r: 255, g: 255, b: 0)
            }
        }
    }

    private func renderRGBA(from image: CGImage, width: Int, height: Int) -> [UInt8]? {
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        guard let ctx = CGContext(
            data: &rgba, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return rgba
    }

    private func cgImageFromRGBA(_ rgba: [UInt8], width: Int, height: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
        return CGImage(
            width: width, height: height,
            bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Big.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )
    }
}

// MARK: - Errors

enum EyeDetectionError: LocalizedError {
    case modelNotFound(String)
    case modelNotLoaded
    case imageLoadFailed
    case inferenceError(String)
    case noEyesDetected

    var errorDescription: String? {
        switch self {
        case .modelNotFound(let name): return "Model not found: \(name)"
        case .modelNotLoaded: return "Models not loaded"
        case .imageLoadFailed: return "Failed to load image"
        case .inferenceError(let msg): return "Inference error: \(msg)"
        case .noEyesDetected: return "No eyes detected in image"
        }
    }
}
