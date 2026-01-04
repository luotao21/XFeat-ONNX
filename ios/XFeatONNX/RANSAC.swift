import Accelerate
import Foundation

class RANSAC {
  /// RANSAC 配置
  struct Config {
    let maxIterations: Int
    let confidence: Float
    let threshold: Float
  }

  /// 执行 RANSAC 寻找单应性矩阵并返回内点掩码
  static func findHomography(
    srcPoints: [[Float]],
    dstPoints: [[Float]],
    config: Config = Config(maxIterations: 2000, confidence: 0.995, threshold: 5.0)  // Relaxed threshold
  ) -> [Bool] {
    guard srcPoints.count == dstPoints.count, srcPoints.count >= 4 else {
      return Array(repeating: false, count: srcPoints.count)
    }

    let count = srcPoints.count
    var bestInliersCount = 0
    var bestMask = Array(repeating: false, count: count)

    // 预先分配索引数组
    let indices = Array(0..<count)

    for _ in 0..<config.maxIterations {
      // 1. 随机选择4个点
      var sampleIndices: [Int] = []
      var availableIndices = indices
      for _ in 0..<4 {
        if availableIndices.isEmpty { break }
        let randIdx = Int.random(in: 0..<availableIndices.count)
        sampleIndices.append(availableIndices.remove(at: randIdx))
      }

      if sampleIndices.count < 4 { break }

      // 2. 根据4个点计算单应性矩阵 H (使用归一化 DLT)
      guard
        let H = computeHomographyNormalized(
          src: sampleIndices.map { srcPoints[$0] },
          dst: sampleIndices.map { dstPoints[$0] }
        )
      else {
        continue
      }

      // 3. 计算内点
      var currentInliersCount = 0
      var currentMask = Array(repeating: false, count: count)

      for i in 0..<count {
        let src = srcPoints[i]
        let dst = dstPoints[i]

        let error = computeReprojectionError(H: H, src: src, dst: dst)
        if error < config.threshold {
          currentInliersCount += 1
          currentMask[i] = true
        }
      }

      // 4. 更新最佳模型
      if currentInliersCount > bestInliersCount {
        bestInliersCount = currentInliersCount
        bestMask = currentMask

        // 简单的提前退出条件（如果内点比例足够高）
        let inlierRatio = Float(bestInliersCount) / Float(count)
        if inlierRatio > 0.7 {  // Slightly lower ratio for early exit
          break
        }
      }
    }

    return bestMask
  }

  // MARK: - Private Helpers

  /// 计算单应性矩阵 (Normalized DLT 算法)
  private static func computeHomographyNormalized(src: [[Float]], dst: [[Float]]) -> [Float]? {
    // 1. Normalize points
    let (normSrc, T1) = normalizePoints(src)
    let (normDst, T2) = normalizePoints(dst)

    // 2. Compute Homography with normalized points
    guard let H_prime = computeHomographyDLT(src: normSrc, dst: normDst) else {
      return nil
    }

    // 3. Denormalize: H = inv(T2) * H_prime * T1
    // inv(T2)
    // T2 is [s 0 tx; 0 s ty; 0 0 1]
    // inv(T2) is [1/s 0 -tx/s; 0 1/s -ty/s; 0 0 1]

    let s2 = T2[0]
    let tx2 = T2[2]
    let ty2 = T2[5]
    let invScale2 = 1.0 / s2

    let invT2: [Float] = [
      invScale2, 0, -tx2 * invScale2,
      0, invScale2, -ty2 * invScale2,
      0, 0, 1,
    ]

    // MatMul: Temp = invT2 * H_prime
    let temp = matMul3x3(invT2, H_prime)

    // MatMul: H = Temp * T1
    let H = matMul3x3(temp, T1)

    return H
  }

  private static func normalizePoints(_ points: [[Float]]) -> ([[Float]], [Float]) {
    var cx: Float = 0
    var cy: Float = 0
    for p in points {
      cx += p[0]
      cy += p[1]
    }
    cx /= Float(points.count)
    cy /= Float(points.count)

    var meanDist: Float = 0
    for p in points {
      let dx = p[0] - cx
      let dy = p[1] - cy
      meanDist += sqrt(dx * dx + dy * dy)
    }
    meanDist /= Float(points.count)

    let scale = sqrt(2.0) / meanDist

    var normalizedPoints: [[Float]] = []
    for p in points {
      let nx = (p[0] - cx) * scale
      let ny = (p[1] - cy) * scale
      normalizedPoints.append([nx, ny])
    }

    // T matrix:
    // [scale, 0, -scale*cx]
    // [0, scale, -scale*cy]
    // [0, 0, 1]
    let T: [Float] = [
      scale, 0, -scale * cx,
      0, scale, -scale * cy,
      0, 0, 1,
    ]

    return (normalizedPoints, T)
  }

  private static func matMul3x3(_ A: [Float], _ B: [Float]) -> [Float] {
    var C = [Float](repeating: 0, count: 9)
    for i in 0..<3 {
      for j in 0..<3 {
        var sum: Float = 0
        for k in 0..<3 {
          sum += A[i * 3 + k] * B[k * 3 + j]
        }
        C[i * 3 + j] = sum
      }
    }
    return C
  }

  /// 基础 DLT 实现
  private static func computeHomographyDLT(src: [[Float]], dst: [[Float]]) -> [Float]? {
    // 构建 8x9 矩阵 A 的系统 (Ax = 0)
    // 实际上我们构建 8x8 系统 Ax = B
    // 使用 Gaussian Elimination 求解

    var A: [Double] = []  // Row-major
    var B: [Double] = []

    for i in 0..<4 {
      let x = Double(src[i][0])
      let y = Double(src[i][1])
      let u = Double(dst[i][0])
      let v = Double(dst[i][1])

      // Equation 1: -x*h1 - y*h2 - h3 + u*x*h7 + u*y*h8 = -u
      // Equation 2: -x*h4 - y*h5 - h6 + v*x*h7 + v*y*h8 = -v

      // Row 1
      A.append(contentsOf: [-x, -y, -1, 0, 0, 0, u * x, u * y])
      B.append(-u)

      // Row 2
      A.append(contentsOf: [0, 0, 0, -x, -y, -1, v * x, v * y])
      B.append(-v)
    }

    // Solve linear system
    guard let hParams = solveLinearSystem8x8(A: A, B: B) else {
      return nil
    }

    // H = [h1, h2, h3, h4, h5, h6, h7, h8, 1]
    var H = hParams.map { Float($0) }
    H.append(1.0)

    return H
  }

  /// 求解 8x8 线性方程组 (Gaussian elimination)
  private static func solveLinearSystem8x8(A: [Double], B: [Double]) -> [Double]? {
    let n = 8
    var mat = A
    var rhs = B
    var x = Array(repeating: 0.0, count: n)

    // Forward elimination
    for i in 0..<n {
      var pivot = mat[i * n + i]
      var pivotRow = i

      // Find pivot
      for k in (i + 1)..<n {
        if abs(mat[k * n + i]) > abs(pivot) {
          pivot = mat[k * n + i]
          pivotRow = k
        }
      }

      if abs(pivot) < 1e-8 { return nil }  // Singular

      // Swap rows
      if pivotRow != i {
        for j in i..<n {
          let temp = mat[i * n + j]
          mat[i * n + j] = mat[pivotRow * n + j]
          mat[pivotRow * n + j] = temp
        }
        let tempB = rhs[i]
        rhs[i] = rhs[pivotRow]
        rhs[pivotRow] = tempB
      }

      // Eliminate
      for k in (i + 1)..<n {
        let factor = mat[k * n + i] / pivot
        for j in i..<n {
          mat[k * n + j] -= factor * mat[i * n + j]
        }
        rhs[k] -= factor * rhs[i]
      }
    }

    // Back substitution
    for i in (0..<n).reversed() {
      var sum = 0.0
      for j in (i + 1)..<n {
        sum += mat[i * n + j] * x[j]
      }
      x[i] = (rhs[i] - sum) / mat[i * n + i]
    }

    return x
  }

  /// 计算重投影误差
  private static func computeReprojectionError(H: [Float], src: [Float], dst: [Float]) -> Float {
    let x = src[0]
    let y = src[1]

    // Project source point
    let w = H[6] * x + H[7] * y + H[8]
    if abs(w) < 1e-8 { return Float.infinity }

    let projX = (H[0] * x + H[1] * y + H[2]) / w
    let projY = (H[3] * x + H[4] * y + H[5]) / w

    let dx = projX - dst[0]
    let dy = projY - dst[1]

    return sqrt(dx * dx + dy * dy)
  }
}
