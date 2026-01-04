import SwiftUI
import UIKit

@MainActor
class MatcherViewModel: ObservableObject {
  @Published var referenceImage: UIImage?
  @Published var targetImage: UIImage?
  @Published var resultImage: UIImage?
  @Published var statusMessage: String = ""
  @Published var isReadyToMatch: Bool = false

  private var matcher: XFeatMatcher?

  @Published var isProcessing: Bool = false

  init() {
    initializeMatcher()
  }

  private func initializeMatcher() {
    statusMessage = "正在初始化模型..."

    Task {
      do {
        matcher = try XFeatMatcher()
        statusMessage = "模型初始化成功"
        loadBuiltInReference()
      } catch {
        statusMessage = "模型初始化失败: \(error.localizedDescription)"
      }
    }
  }

  private func loadBuiltInReference() {
    // Load reference_page.jpg
    if let refURL = Bundle.main.url(forResource: "reference_page", withExtension: "jpg"),
      let refData = try? Data(contentsOf: refURL),
      let refImg = UIImage(data: refData)
    {

      referenceImage = refImg

      // Pre-compute features
      do {
        try matcher?.preloadReference(image: refImg)
        statusMessage = "参考图像特征已提取 (缓存完毕)"
      } catch {
        statusMessage = "特征提取失败: \(error.localizedDescription)"
      }
    } else {
      statusMessage = "未找到内置参考图像 reference_page.jpg"
    }

    checkReadyStatus()
  }

  func setTargetImage(image: UIImage) {
    targetImage = image
    checkReadyStatus()
    resultImage = nil
    statusMessage = "目标图像已设置"
  }

  private func checkReadyStatus() {
    // Just check if we calculate features for ref and have a target
    isReadyToMatch = referenceImage != nil && targetImage != nil
  }

  func runMatching() {
    guard let tgtImage = targetImage,
      let matcher = matcher
    else {
      statusMessage = "请先设置目标图像"
      return
    }

    statusMessage = "正在匹配..."
    isProcessing = true

    Task {
      defer { isProcessing = false }
      do {
        let startTime = CFAbsoluteTimeGetCurrent()

        // Use cached matching if available
        let result: XFeatMatcher.MatchResult
        if let cachedResult = try await matcher.matchWithReference(target: tgtImage) {
          result = cachedResult
        } else {
          // Fallback (should normally use cache)
          guard let refImage = referenceImage else { return }
          result = try await matcher.matchImages(reference: refImage, target: tgtImage)
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        resultImage = result.visualizedImage
        statusMessage = String(format: "匹配完成！找到 %d 个匹配点，耗时 %.3f 秒", result.matchCount, elapsed)
      } catch {
        statusMessage = "匹配失败: \(error.localizedDescription)"
      }
    }
  }
}
