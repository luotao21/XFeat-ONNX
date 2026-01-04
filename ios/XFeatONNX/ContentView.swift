import SwiftUI
import UIKit

struct ContentView: View {
  @StateObject private var viewModel = MatcherViewModel()
  @State private var showingImagePicker = false
  @State private var showingCamera = false

  var body: some View {
    NavigationView {
      VStack(spacing: 20) {

        // Input Images Area (Left - Right)
        HStack(spacing: 20) {
          // Reference Image (Left - Fixed)
          VStack {
            Text("参考图像")
              .font(.headline)
            if let refImage = viewModel.referenceImage {
              Image(uiImage: refImage)
                .resizable()
                .scaledToFit()
                .cornerRadius(8)
                .overlay(
                  RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.green, lineWidth: 2)
                )
            } else {
              RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.3))
                .overlay(Text("加载中..."))
            }
          }

          // Target Image (Right - Capture)
          VStack {
            Text("目标图像")
              .font(.headline)

            ZStack {
              RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.1))
                .overlay(
                  RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )

              if let image = viewModel.targetImage {
                Image(uiImage: image)
                  .resizable()
                  .scaledToFit()
                  .cornerRadius(8)
              } else {
                VStack {
                  Image(systemName: "camera.fill")
                    .font(.largeTitle)
                    .foregroundColor(.blue)
                  Text("拍照或选择")
                    .font(.caption)
                    .foregroundColor(.gray)
                }
              }
            }
            .onTapGesture {
              // Show source selection action sheet
              // For simplicity in this demo, default to camera if available, else picker
              // Ideally we show an action sheet.
              // Let's toggle a simple choice via logic or Alert
              self.showingCamera = true
            }
          }
        }
        .frame(height: 200)

        // Action Button
        if viewModel.isProcessing {
          ProgressView("正在匹配...")
        } else {
          Button("开始匹配") {
            viewModel.runMatching()
          }
          .buttonStyle(.borderedProminent)
          .disabled(!viewModel.isReadyToMatch)
          .frame(maxWidth: .infinity)
        }

        // Status
        if !viewModel.statusMessage.isEmpty {
          Text(viewModel.statusMessage)
            .font(.caption)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
        }

        // Match Result (Bottom)
        if let resultImage = viewModel.resultImage {
          VStack {
            Text("匹配结果")
              .font(.headline)
            Image(uiImage: resultImage)
              .resizable()
              .scaledToFit()
              .frame(maxHeight: .infinity)
              .cornerRadius(8)
          }
        } else {
          Spacer()
        }
      }
      .padding()
      .navigationTitle("XFeat ONNX")
      .actionSheet(isPresented: $showingCamera) {
        ActionSheet(
          title: Text("获取目标图像"),
          buttons: [
            .default(Text("拍照")) {
              self.showingImagePicker = true
              self.showingCamera = true  // Use this flag to indicate camera source in sheets? No, need a cleaner way.
            },
            .default(Text("从相册选择")) {
              self.showingImagePicker = true
              self.showingCamera = false
            },
            .cancel(),
          ])
      }
      .sheet(isPresented: $showingImagePicker) {
        ImagePicker(
          sourceType: showingCamera ? .camera : .photoLibrary,
          image: Binding(
            get: { nil },
            set: { img in
              if let img = img {
                viewModel.setTargetImage(image: img)
              }
            }
          ))
      }
    }
  }
}

// Image Picker
struct ImagePicker: UIViewControllerRepresentable {
  @Environment(\.presentationMode) var presentationMode
  var sourceType: UIImagePickerController.SourceType
  @Binding var image: UIImage?

  func makeUIViewController(context: UIViewControllerRepresentableContext<ImagePicker>)
    -> UIImagePickerController
  {
    let picker = UIImagePickerController()
    picker.delegate = context.coordinator
    picker.sourceType = sourceType
    return picker
  }

  func updateUIViewController(
    _ uiViewController: UIImagePickerController,
    context: UIViewControllerRepresentableContext<ImagePicker>
  ) {}

  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }

  class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
    let parent: ImagePicker

    init(_ parent: ImagePicker) {
      self.parent = parent
    }

    func imagePickerController(
      _ picker: UIImagePickerController,
      didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
      if let uiImage = info[.originalImage] as? UIImage {
        parent.image = uiImage
      }
      parent.presentationMode.wrappedValue.dismiss()
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
      parent.presentationMode.wrappedValue.dismiss()
    }
  }
}
