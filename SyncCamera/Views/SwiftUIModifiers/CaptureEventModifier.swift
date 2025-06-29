import AVKit
import SwiftUI
import UIKit

private struct iOS17CaptureView: UIViewRepresentable {
  let capture: () -> Void
  
  typealias UIViewType = UIView
  
  func makeUIView(context: Context) -> UIViewType {
    let view = UIView()
    view.backgroundColor = .clear
    if #available(iOS 17.2, *) {
      view.addInteraction(
        AVCaptureEventInteraction(handler: { event in
          if event.phase == .ended {
            capture()
          }
        })
      )
    }
    return view
  }
  
  func updateUIView(_ uiView: UIViewType, context: Context) {
    // nop
  }
}

struct CaptureEventModifier: ViewModifier {
  let capture: () -> Void
  
  func body(content: Content) -> some View {
    if #available(iOS 18.0, *) {
      content
        .onCameraCaptureEvent { event in
          if event.phase == .ended {
            capture()
          }
        }
    } else {
      content
        .background(iOS17CaptureView(capture: capture))
    }
  }
}

extension View {
  func captureEvent(_ capture: @escaping () -> Void) -> some View {
    modifier(CaptureEventModifier(capture: capture))
  }
}
