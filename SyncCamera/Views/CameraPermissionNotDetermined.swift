import SwiftUI

struct CameraPermissionNotDetermined: View {
  // 権限リクエストのクロージャを外部から渡す方式
  let onRequestPermission: () -> Void

  var body: some View {
    VStack(spacing: 24) {
      Image(systemName: "camera.viewfinder")
        .resizable()
        .scaledToFit()
        .frame(width: 64, height: 64)
        .foregroundColor(.accentColor)
      Text("カメラへのアクセスが必要です")
        .font(.headline)
      Text("写真を撮影するにはカメラの権限が必要です。")
        .font(.subheadline)
        .multilineTextAlignment(.center)
      Button(action: onRequestPermission) {
        Text("カメラを許可する")
          .fontWeight(.bold)
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
    }
    .padding()
  }
}

#Preview {
  CameraPermissionNotDetermined {}
}
