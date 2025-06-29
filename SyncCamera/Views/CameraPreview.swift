import AVFoundation
import SwiftUI
import UIKit

/// AVCaptureVideoPreviewLayerをSwiftUIで表示するためのビュー
struct CameraPreview: UIViewControllerRepresentable {
  /// プレビュー表示用のレイヤー
  let previewLayer: AVCaptureVideoPreviewLayer

  var orientation: UIDeviceOrientation?

  typealias UIViewControllerType = UIViewController

  class Coordinator: NSObject {
    let previewLayer: AVCaptureVideoPreviewLayer
    let device: AVCaptureDevice?

    init(previewLayer: AVCaptureVideoPreviewLayer) {
      self.previewLayer = previewLayer
      self.device =
        previewLayer.session?.inputs.compactMap { $0 as? AVCaptureDeviceInput }
        .first?.device
    }

    @objc func handleTap(_ gesture: UITapGestureRecognizer) {
      let point = gesture.location(in: gesture.view)
      let focusPoint = previewLayer.captureDevicePointConverted(
        fromLayerPoint: point
      )
      guard let device else { return }
      do {
        try device.lockForConfiguration()
        if device.isFocusPointOfInterestSupported {
          device.focusPointOfInterest = focusPoint
          device.focusMode = .autoFocus
        }
        device.unlockForConfiguration()
      } catch {}
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(previewLayer: previewLayer)
  }

  /// UIViewControllerの生成とプレビューレイヤー追加
  func makeUIViewController(context: Context) -> UIViewController {
    let vc = UIViewController()
    vc.view.layer.addSublayer(previewLayer)
    previewLayer.frame = vc.view.frame
    vc.view.addGestureRecognizer(
      UITapGestureRecognizer(
        target: context.coordinator,
        action: #selector(context.coordinator.handleTap(_:))
      )
    )
    return vc
  }

  /// UIViewControllerの更新時にプレビューレイヤーのフレームを更新
  func updateUIViewController(
    _ uiViewController: UIViewController,
    context: Context
  ) {
    previewLayer.frame = uiViewController.view.frame

    if let connection = previewLayer.connection {
      let rotationAngle: CGFloat
      switch orientation {
      case .portrait:
        rotationAngle = 90
      case .landscapeLeft:
        rotationAngle = 0
      case .landscapeRight:
        rotationAngle = 180
      case .portraitUpsideDown:
        rotationAngle = 270
      default:
        rotationAngle = 90
      }

      if connection.isVideoRotationAngleSupported(rotationAngle) {
        connection.videoRotationAngle = rotationAngle
      }
    }
  }
}
