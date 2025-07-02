import CoreImage
import Photos
import SwiftUI

@Observable
final class SpatialPhotoStore: Identifiable {
  let id = UUID()

  let leftImageData: Data
  let rightImageData: Data

  var leftImage: CGImage
  var rightImage: CGImage

  var leftImageOrientation: Image.Orientation = .up
  var rightImageOrientation: Image.Orientation = .up

  var error: (any Error)?
  var isSaveSuccessAlertPresented: Bool = false

  init?(leftImageData: Data, rightImageData: Data) {
    guard
      let leftImage = Self.createCGImage(from: leftImageData),
      let rightImage = Self.createCGImage(from: rightImageData)
    else {
      return nil
    }

    self.leftImageData = leftImageData
    self.rightImageData = rightImageData

    self.leftImage = leftImage
    self.rightImage = rightImage

    self.leftImageOrientation = translateImageOrientation(leftImageData.orientation ?? .up)
    self.rightImageOrientation = translateImageOrientation(rightImageData.orientation ?? .up)
  }

  static func createCGImage(from data: Data) -> CGImage? {
    guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil)
    else {
      return nil
    }
    return CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
  }

  private func translateImageOrientation(
    _ imageOrientation: CGImagePropertyOrientation
  ) -> Image.Orientation {
    switch imageOrientation {
    case .up:
      return .up
    case .upMirrored:
      return .upMirrored
    case .left:
      return .left
    case .leftMirrored:
      return .leftMirrored
    case .right:
      return .right
    case .rightMirrored:
      return .rightMirrored
    case .down:
      return .down
    case .downMirrored:
      return .downMirrored
    }
  }

  func generateSpatialPhoto() {
    let leftImageURL = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("left.jpg")
    let rightImageURL = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("right.jpg")
    do {
      try self.leftImageData.write(to: leftImageURL)
      try self.rightImageData.write(to: rightImageURL)

      try generateSpatialPhoto(
        leftImageURL: leftImageURL,
        rightImageURL: rightImageURL
      )
    } catch {
      self.error = error
    }
  }

  private func generateSpatialPhoto(leftImageURL: URL, rightImageURL: URL) throws {
    let outputImageURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(
      "output.heic")
    let converter = SpatialPhotoConverter(
      leftImageURL: leftImageURL,
      rightImageURL: rightImageURL,
      outputImageURL: outputImageURL,
      baselineInMillimeters: 1,
      horizontalFOV: 42,
      disparityAdjustment: 0
    )
    try converter.convert()

    PHPhotoLibrary.shared().performChanges {
      PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: outputImageURL)
    } completionHandler: { [self] success, error in
      Task { @MainActor in
        if success {
          try? FileManager.default.removeItem(at: leftImageURL)
          try? FileManager.default.removeItem(at: rightImageURL)
          try? FileManager.default.removeItem(at: outputImageURL)

          self.isSaveSuccessAlertPresented = true
        } else if let error = error {
          self.error = error
        }
      }
    }
  }
}

struct SpatialPhotoView: View {
  @Bindable var store: SpatialPhotoStore
  var body: some View {
    VStack(spacing: 16) {
      HStack(spacing: 16) {
        Image(
          decorative: store.leftImage,
          scale: 1,
          orientation: store.leftImageOrientation
        )
        .resizable()
        .aspectRatio(contentMode: .fit)
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.accentColor.opacity(0.1))
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 16))

        Image(
          decorative: store.rightImage,
          scale: 1,
          orientation: store.rightImageOrientation
        )
        .resizable()
        .aspectRatio(contentMode: .fit)
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.accentColor.opacity(0.1))
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 16))

      }
      .padding(16)

      Button {
        store.generateSpatialPhoto()
      } label: {
        Text("空間写真を生成する")
          .padding(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
          .foregroundStyle(.background)
          .background(Color.accentColor)
          .clipShape(RoundedRectangle(cornerRadius: 8))
      }
    }
    .alert(
      "エラー",
      isPresented: Binding(
        get: { store.error != nil },
        set: { _ in store.error = nil }
      )
    ) {
      Button("OK") {
        store.error = nil
      }
    } message: {
      Text(store.error?.localizedDescription ?? "")
    }
    .alert(
      "保存完了",
      isPresented: $store.isSaveSuccessAlertPresented
    ) {
      Button("OK") {
        store.isSaveSuccessAlertPresented = false
      }
    } message: {
      Text("空間写真の保存が完了しました")
    }
  }
}
