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
    previewLayer.frame = uiViewController.view.bounds

    switch orientation {
    case .portrait:
      previewLayer.connection?.videoRotationAngle = 90
    case .landscapeLeft:
      previewLayer.connection?.videoRotationAngle = 0
    case .landscapeRight:
      previewLayer.connection?.videoRotationAngle = 180
    case .portraitUpsideDown:
      previewLayer.connection?.videoRotationAngle = 270
    default:
      previewLayer.connection?.videoRotationAngle = 90
    }
  }
}
