import SwiftUI

struct CameraPermissionDenied: View {
  var body: some View {
    VStack(spacing: 24) {
      Image(systemName: "camera.slash")
        .resizable()
        .scaledToFit()
        .frame(width: 64, height: 64)
        .foregroundColor(.red)
      Text("カメラへのアクセスが許可されていません")
        .font(.headline)
        .multilineTextAlignment(.center)
      Text("写真を撮影するには、カメラへのアクセス権限が必要です。設定アプリからカメラのアクセスを許可してください。")
        .font(.subheadline)
        .multilineTextAlignment(.center)
      Button(action: {
        if let url = URL(string: UIApplication.openSettingsURLString) {
          UIApplication.shared.open(url)
        }
      }) {
        Text("設定を開く")
          .fontWeight(.bold)
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
    }
    .padding()
  }
}

#Preview {
  CameraPermissionDenied()
}
