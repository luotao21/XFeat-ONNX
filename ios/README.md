# XFeat-ONNX iOS 演示应用

这是一个使用 ONNX Runtime 在 iOS 上运行 XFeat 特征匹配的演示应用。

## 项目结构

```
ios/
├── XFeatONNX.xcodeproj/     # Xcode 项目文件
├── XFeatONNX/               # 源代码目录
│   ├── XFeatONNXApp.swift   # App 入口
│   ├── ContentView.swift    # SwiftUI 主界面
│   ├── MatcherViewModel.swift # 视图模型
│   ├── XFeatMatcher.swift   # ONNX Runtime 推理封装
│   ├── ref.png              # 测试参考图像
│   ├── tgt.png              # 测试目标图像
│   ├── xfeat_dense_600x800.onnx   # 特征提取模型
│   └── matching_dense.onnx        # 匹配模型
└── Podfile                  # CocoaPods 配置
```

## 配置步骤

### 方法 1：使用 CocoaPods（推荐）

1. 确保已安装 CocoaPods：

   ```bash
   sudo gem install cocoapods
   ```

2. 进入 ios 目录并安装依赖：

   ```bash
   cd ios
   pod install
   ```

3. 打开生成的 workspace：

   ```bash
   open XFeatONNX.xcworkspace
   ```

### 方法 2：使用 Swift Package Manager

1. 打开 `XFeatONNX.xcodeproj`
2. 选择项目 -> Package Dependencies
3. 点击 "+" 添加包
4. 输入 ONNX Runtime 的 GitHub URL：

   ```
   https://github.com/niclaswue/onnxruntime-swift-package-manager
   ```

5. 选择版本并添加到项目

### 方法 3：手动下载 XCFramework

1. 从 [ONNX Runtime Releases](https://github.com/microsoft/onnxruntime/releases) 下载 iOS XCFramework
2. 将 `onnxruntime.xcframework` 拖入 Xcode 项目
3. 在 Build Settings 中配置 Framework Search Paths

## 运行

1. 选择目标设备（真机或模拟器）
2. 点击运行 (⌘R)
3. 在应用中点击"加载图像"加载测试图片
4. 点击"开始匹配"进行特征匹配

## 注意事项

- 模型输入尺寸固定为 600x800，输入图像会自动缩放
- 首次运行时模型初始化可能需要几秒钟
- 建议在真机上测试以获得最佳性能

## 故障排除

如果 `pod install` 下载失败，可以尝试：

1. 更新 CocoaPods 仓库：

   ```bash
   pod repo update
   ```

2. 使用代理或 VPN

3. 手动下载 ONNX Runtime 并按方法 3 配置
