import AVFoundation
import Observation
import SwiftUI

protocol PermissionStoreDelegate: AnyObject {
  func permissionUpdated()
}

@Observable
final class PermissionStore {
  weak var delegate: PermissionStoreDelegate?

  var permissionClient: PermissionClient
  var cameraPermission: Permission?
  var addLibraryPermission: Permission?

  init(permissionClient: PermissionClient = .liveValue) {
    self.permissionClient = permissionClient
    checkPermissions()
  }

  func checkPermissions() {
    cameraPermission = permissionClient.cameraPermission()
    addLibraryPermission = permissionClient.addLibraryPermission()
  }

  func requestCameraPermission() {
    Task {
      self.cameraPermission = await permissionClient.requestCameraPermission()
      self.delegate?.permissionUpdated()
    }
  }

  func requestAddLibraryPermission() {
    Task {
      self.addLibraryPermission =
        await permissionClient.requestAddLibraryPermission()
      self.delegate?.permissionUpdated()
    }
  }
}

struct PermissionView: View {
  @Bindable var store: PermissionStore

  var body: some View {
    VStack(spacing: 32) {
      VStack(spacing: 16) {
        if let cameraPermission = store.cameraPermission {
          switch cameraPermission {
          case .notDetermined:
            Image(systemName: "camera")
              .resizable()
              .aspectRatio(contentMode: .fit)
              .frame(width: 64, height: 64)
            Text("カメラを利用するためにアクセス権限を許可してください")
            Button {
              store.requestCameraPermission()
            } label: {
              Text("カメラへのアクセスを許可する")
            }
            .buttonStyle(.borderedProminent)
          case .authorized:
            Text("\(Image(systemName: "checkmark")) カメラは利用可能です")
          case .denied:
            Text("カメラへのアクセスが拒否されました")
            Button {
              if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
              }
            } label: {
              Text("設定アプリを開く")
            }
            .buttonStyle(.bordered)
          }
        }
      }

      VStack(spacing: 16) {
        if let addLibraryPermission = store.addLibraryPermission {
          switch addLibraryPermission {
          case .notDetermined:
            Image(systemName: "photo")
              .resizable()
              .aspectRatio(contentMode: .fit)
              .frame(width: 64, height: 64)
            Text("写真を保存するためにアクセス権限を許可してください")
            Button {
              store.requestAddLibraryPermission()
            } label: {
              Text("カメラへのアクセスを許可する")
            }
            .buttonStyle(.borderedProminent)
          case .authorized:
            Text("\(Image(systemName: "checkmark")) ライブラリはアクセス可能です")
          case .denied:
            Text("ライブラリへのアクセスが拒否されました")
            Button {
              if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
              }
            } label: {
              Text("設定アプリを開く")
            }
            .buttonStyle(.bordered)
          }
        }
      }
    }
    .onAppear {
      store.checkPermissions()
    }
    .padding()
  }
}

#Preview {
  PermissionView(
    store: PermissionStore(
      permissionClient: PermissionClient(
        cameraPermission: {
          .notDetermined
        },
        requestCameraPermission: {
          .denied
        },
        addLibraryPermission: {
          .notDetermined
        },
        requestAddLibraryPermission: {
          .authorized
        }
      )
    )
  )
}
