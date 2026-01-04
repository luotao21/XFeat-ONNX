import UIKit
import onnxruntime_objc

/// XFeat 特征匹配器，封装 ONNX Runtime 推理逻辑
class XFeatMatcher {

  // ONNX Runtime sessions
  private var extractorSession: ORTSession?
  private var matcherSession: ORTSession?
  private let env: ORTEnv

  // Model configuration
  private let isDense: Bool = true

  /// Whether CoreML execution provider is enabled
  public private(set) var isUsingCoreML: Bool = false

  /// 匹配结果
  struct MatchResult {
    let refKeypoints: [[Float]]
    let tgtKeypoints: [[Float]]
    let matchCount: Int
    let visualizedImage: UIImage?
  }

  enum XFeatError: Error, LocalizedError {
    case modelNotFound(String)
    case sessionCreationFailed(String)
    case inferenceError(String)
    case imagePreprocessingFailed

    var errorDescription: String? {
      switch self {
      case .modelNotFound(let name):
        return "Model not found: \(name)"
      case .sessionCreationFailed(let msg):
        return "Session creation failed: \(msg)"
      case .inferenceError(let msg):
        return "Inference error: \(msg)"
      case .imagePreprocessingFailed:
        return "Image preprocessing failed"
      }
    }
  }

  init() throws {
    // Create ONNX Runtime environment
    env = try ORTEnv(loggingLevel: .warning)

    // Load models
    try loadModels()
  }

  private func loadModels() throws {
    // Get model paths from bundle
    let extractorModelName = isDense ? "xfeat_dense_600x800" : "xfeat_600x800"
    let matcherModelName = isDense ? "matching_dense" : "matching"

    guard let extractorPath = Bundle.main.path(forResource: extractorModelName, ofType: "onnx")
    else {
      throw XFeatError.modelNotFound(extractorModelName)
    }

    guard let matcherPath = Bundle.main.path(forResource: matcherModelName, ofType: "onnx") else {
      throw XFeatError.modelNotFound(matcherModelName)
    }

    // Create session options
    let sessionOptions = try ORTSessionOptions()
    try sessionOptions.setGraphOptimizationLevel(.all)
    // Try to enable CoreML
    do {
      let coreMLOptions = try ORTCoreMLExecutionProviderOptions()
      try sessionOptions.appendCoreMLExecutionProvider(with: coreMLOptions)
      print("CoreML Execution Provider enabled")
      isUsingCoreML = true
    } catch {
      print("Failed to enable CoreML Execution Provider: \(error)")
      isUsingCoreML = false
    }

    // Create sessions
    extractorSession = try ORTSession(
      env: env, modelPath: extractorPath, sessionOptions: sessionOptions)
    matcherSession = try ORTSession(
      env: env, modelPath: matcherPath, sessionOptions: sessionOptions)
  }

  // Cache
  private var cachedRefImage: UIImage?
  private var cachedRefFeatures: ExtractorOutput?

  // MARK: - Public Methods

  /// 预计算并缓存参考图像特征
  func preloadReference(image: UIImage) throws {
    guard let extractorSession = extractorSession else {
      throw XFeatError.sessionCreationFailed("Session not initialized")
    }

    guard let tensor = preprocessImage(image) else {
      throw XFeatError.imagePreprocessingFailed
    }

    let features = try runExtractor(session: extractorSession, inputTensor: tensor)

    self.cachedRefImage = image
    self.cachedRefFeatures = features
  }

  /// 使用缓存的参考图像进行匹配
  func matchWithReference(target: UIImage) async throws -> MatchResult? {
    guard let refImage = cachedRefImage,
      let refFeatures = cachedRefFeatures,
      let matcherSession = matcherSession,
      let extractorSession = extractorSession
    else {
      return nil
    }

    // Preprocess target
    guard let tgtTensor = preprocessImage(target) else {
      throw XFeatError.imagePreprocessingFailed
    }

    // Extract target features
    let tgtFeatures = try runExtractor(session: extractorSession, inputTensor: tgtTensor)

    // Run matching
    let matchResult = try runMatcher(
      session: matcherSession,
      refKeypoints: refFeatures.keypoints,
      refDescriptors: refFeatures.descriptors,
      tgtKeypoints: tgtFeatures.keypoints,
      tgtDescriptors: tgtFeatures.descriptors,
      refScales: refFeatures.scales
    )

    // Visualize
    let visualized = visualizeMatches(
      refImage: refImage,
      tgtImage: target,
      refPoints: matchResult.0,
      tgtPoints: matchResult.1
    )

    return MatchResult(
      refKeypoints: matchResult.0,
      tgtKeypoints: matchResult.1,
      matchCount: matchResult.0.count,
      visualizedImage: visualized
    )
  }

  /// 对两张图像进行特征匹配 (Legacy)
  func matchImages(reference: UIImage, target: UIImage) async throws -> MatchResult {
    guard let extractorSession = extractorSession,
      let matcherSession = matcherSession
    else {
      throw XFeatError.sessionCreationFailed("Sessions not initialized")
    }

    // Preprocess images
    guard let refTensor = preprocessImage(reference),
      let tgtTensor = preprocessImage(target)
    else {
      throw XFeatError.imagePreprocessingFailed
    }

    // Extract features from reference image
    let refFeatures = try runExtractor(session: extractorSession, inputTensor: refTensor)

    // Extract features from target image
    let tgtFeatures = try runExtractor(session: extractorSession, inputTensor: tgtTensor)

    // Run matching
    let matchResult = try runMatcher(
      session: matcherSession,
      refKeypoints: refFeatures.keypoints,
      refDescriptors: refFeatures.descriptors,
      tgtKeypoints: tgtFeatures.keypoints,
      tgtDescriptors: tgtFeatures.descriptors,
      refScales: refFeatures.scales
    )

    // Visualize matches
    let visualized = visualizeMatches(
      refImage: reference,
      tgtImage: target,
      refPoints: matchResult.0,
      tgtPoints: matchResult.1
    )

    return MatchResult(
      refKeypoints: matchResult.0,
      tgtKeypoints: matchResult.1,
      matchCount: matchResult.0.count,
      visualizedImage: visualized
    )
  }

  // MARK: - Private Methods

  private struct ExtractorOutput {
    let keypoints: ORTValue
    let descriptors: ORTValue
    let scales: ORTValue?
  }

  private func preprocessImage(_ image: UIImage) -> ORTValue? {
    // Target size matches the exported model
    let targetWidth = 800
    let targetHeight = 600

    // Resize image
    guard let resizedImage = image.resized(to: CGSize(width: targetWidth, height: targetHeight)),
      let cgImage = resizedImage.cgImage
    else {
      return nil
    }

    let width = cgImage.width
    let height = cgImage.height
    let bytesPerPixel = 4
    let bytesPerRow = bytesPerPixel * width
    let bitsPerComponent = 8

    var pixelData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

    guard
      let context = CGContext(
        data: &pixelData,
        width: width,
        height: height,
        bitsPerComponent: bitsPerComponent,
        bytesPerRow: bytesPerRow,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else {
      return nil
    }

    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

    // Convert to CHW format and normalize
    var floatData = [Float](repeating: 0, count: 3 * height * width)

    for y in 0..<height {
      for x in 0..<width {
        let pixelIndex = (y * width + x) * bytesPerPixel
        let r = Float(pixelData[pixelIndex]) / 255.0
        let g = Float(pixelData[pixelIndex + 1]) / 255.0
        let b = Float(pixelData[pixelIndex + 2]) / 255.0

        // CHW format: [C, H, W]
        floatData[0 * height * width + y * width + x] = r
        floatData[1 * height * width + y * width + x] = g
        floatData[2 * height * width + y * width + x] = b
      }
    }

    // Create ONNX tensor
    let shape: [NSNumber] = [1, 3, NSNumber(value: height), NSNumber(value: width)]

    do {
      let data = Data(bytes: floatData, count: floatData.count * MemoryLayout<Float>.size)
      let tensor = try ORTValue(
        tensorData: NSMutableData(data: data),
        elementType: .float,
        shape: shape
      )
      return tensor
    } catch {
      print("Error creating tensor: \(error)")
      return nil
    }
  }

  private func runExtractor(session: ORTSession, inputTensor: ORTValue) throws -> ExtractorOutput {
    let inputs: [String: ORTValue] = ["images": inputTensor]

    let outputNames: Set<String> =
      isDense
      ? ["keypoints", "descriptors", "scales"]
      : ["keypoints", "descriptors", "scores"]

    let outputs = try session.run(
      withInputs: inputs,
      outputNames: outputNames,
      runOptions: nil
    )

    guard let keypoints = outputs["keypoints"],
      let descriptors = outputs["descriptors"]
    else {
      throw XFeatError.inferenceError("Missing extractor outputs")
    }

    let scales = outputs["scales"]

    return ExtractorOutput(keypoints: keypoints, descriptors: descriptors, scales: scales)
  }

  private func runMatcher(
    session: ORTSession,
    refKeypoints: ORTValue,
    refDescriptors: ORTValue,
    tgtKeypoints: ORTValue,
    tgtDescriptors: ORTValue,
    refScales: ORTValue?
  ) throws -> ([[Float]], [[Float]]) {

    var inputs: [String: ORTValue] = [
      "kpts0": refKeypoints,
      "feats0": refDescriptors,
      "kpts1": tgtKeypoints,
      "feats1": tgtDescriptors,
    ]

    if isDense, let scales = refScales {
      inputs["scales0"] = scales
    }

    let outputNames: Set<String> = ["mkpts0", "mkpts1"]

    let outputs = try session.run(
      withInputs: inputs,
      outputNames: outputNames,
      runOptions: nil
    )

    guard let mkpts0 = outputs["mkpts0"],
      let mkpts1 = outputs["mkpts1"]
    else {
      throw XFeatError.inferenceError("Missing matcher outputs")
    }

    // Extract keypoint data
    let refPointsFull = try extractKeypoints(from: mkpts0)
    let tgtPointsFull = try extractKeypoints(from: mkpts1)

    // Check if we have enough points for RANSAC
    guard refPointsFull.count >= 4 else {
      // Return raw matches if not enough points (fallback)
      return (refPointsFull, tgtPointsFull)
    }

    // Apply RANSAC to filter outliers
    let inliersMask = RANSAC.findHomography(
      srcPoints: refPointsFull,
      dstPoints: tgtPointsFull
    )

    // Filter points based on mask
    var refPointsFiltered: [[Float]] = []
    var tgtPointsFiltered: [[Float]] = []

    for i in 0..<refPointsFull.count {
      if inliersMask[i] {
        refPointsFiltered.append(refPointsFull[i])
        tgtPointsFiltered.append(tgtPointsFull[i])
      }
    }

    return (refPointsFiltered, tgtPointsFiltered)
  }

  private func extractKeypoints(from tensor: ORTValue) throws -> [[Float]] {
    let tensorData = try tensor.tensorData() as Data
    let shape = try tensor.tensorTypeAndShapeInfo().shape

    guard shape.count == 2 else {
      return []
    }

    let numPoints = shape[0].intValue
    let dims = shape[1].intValue

    var points: [[Float]] = []

    tensorData.withUnsafeBytes { buffer in
      let floatBuffer = buffer.bindMemory(to: Float.self)
      for i in 0..<numPoints {
        var point: [Float] = []
        for j in 0..<dims {
          point.append(floatBuffer[i * dims + j])
        }
        points.append(point)
      }
    }

    return points
  }

  private func visualizeMatches(
    refImage: UIImage,
    tgtImage: UIImage,
    refPoints: [[Float]],
    tgtPoints: [[Float]]
  ) -> UIImage? {
    // Create combined image
    let combinedWidth = refImage.size.width + tgtImage.size.width
    let combinedHeight = max(refImage.size.height, tgtImage.size.height)

    UIGraphicsBeginImageContextWithOptions(
      CGSize(width: combinedWidth, height: combinedHeight), false, 1.0)

    guard let context = UIGraphicsGetCurrentContext() else {
      UIGraphicsEndImageContext()
      return nil
    }

    // Draw images
    refImage.draw(at: .zero)
    tgtImage.draw(at: CGPoint(x: refImage.size.width, y: 0))

    // Draw matches
    let colors: [UIColor] = [.green, .cyan, .yellow, .orange, .magenta]

    // Calculate scale factors
    let modelWidth: CGFloat = 800.0
    let modelHeight: CGFloat = 600.0

    let scaleRefX = refImage.size.width / modelWidth
    let scaleRefY = refImage.size.height / modelHeight
    let scaleTgtX = tgtImage.size.width / modelWidth
    let scaleTgtY = tgtImage.size.height / modelHeight

    // Limit number of lines to draw for performance
    let maxDrawCount = 200
    let pointsToDraw: [(Int, ([Float], [Float]))]

    if refPoints.count > maxDrawCount {
      // Sample random points
      var indicies = Array(0..<refPoints.count)
      indicies.shuffle()
      let sampleIndices = indicies.prefix(maxDrawCount)
      pointsToDraw = sampleIndices.map { ($0, (refPoints[$0], tgtPoints[$0])) }
    } else {
      pointsToDraw = Array(zip(refPoints, tgtPoints).enumerated())
    }

    // for (index, (refPt, tgtPt)) in zip(refPoints, tgtPoints).enumerated() {
    for (index, (refPt, tgtPt)) in pointsToDraw {
      guard refPt.count >= 2, tgtPt.count >= 2 else { continue }

      let color = colors[index % colors.count]
      context.setStrokeColor(color.cgColor)
      context.setLineWidth(1.0)  // Thicker line for visibility on high res images? Maybe 2.0? Let's stick to 1.0 but scaled maybe? No, 2.0 is safer.
      context.setLineWidth(2.0)

      // Scale points to original image size
      let startX = CGFloat(refPt[0]) * scaleRefX
      let startY = CGFloat(refPt[1]) * scaleRefY
      let endX = CGFloat(tgtPt[0]) * scaleTgtX + refImage.size.width
      let endY = CGFloat(tgtPt[1]) * scaleTgtY

      let start = CGPoint(x: startX, y: startY)
      let end = CGPoint(x: endX, y: endY)

      context.move(to: start)
      context.addLine(to: end)
      context.strokePath()

      // Draw circles at keypoints
      context.setFillColor(color.cgColor)
      let radius: CGFloat = 4.0
      context.fillEllipse(
        in: CGRect(x: start.x - radius, y: start.y - radius, width: radius * 2, height: radius * 2))
      context.fillEllipse(
        in: CGRect(x: end.x - radius, y: end.y - radius, width: radius * 2, height: radius * 2))
    }

    let result = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()

    return result
  }
}

// MARK: - UIImage Extension

extension UIImage {
  func resized(to size: CGSize) -> UIImage? {
    UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
    draw(in: CGRect(origin: .zero, size: size))
    let resized = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()
    return resized
  }
}
