import ImageCaptureCore
import SwiftUI

@Observable
public final class ExternalStorageIconStore {
  let deviceBrowwser: ICDeviceBrowser = ICDeviceBrowser()

  var isAuthorized: Bool = false
  var selectedDevice: ICCameraDevice?
  var isDeviceListShown: Bool = false

  func task() async {
    switch deviceBrowwser.contentsAuthorizationStatus {
    case .authorized:
      isAuthorized = true
    case .notDetermined:
      let status = await withCheckedContinuation { continuation in
        deviceBrowwser.requestContentsAuthorization { status in
          continuation.resume(returning: status)
        }
      }
      isAuthorized = status == .authorized
    case .denied, .restricted:
      isAuthorized = false
    default:
      isAuthorized = false
    }
  }
}

struct ExternalStorageIcon: View {
  @Bindable var store: ExternalStorageIconStore
  @Environment(\.openURL) var openURL

  init(store: ExternalStorageIconStore) {
    self.store = store
  }

  var body: some View {
    Group {
      if store.isAuthorized {
        Button {
          store.isDeviceListShown = true
        } label: {
          if let device = store.selectedDevice {
            Text("\(device.name ?? "Unknown")")
          } else {
            Label("Devices", systemImage: "list.bullet")
              .labelStyle(.iconOnly)
          }
        }
      } else {
        Button {
          openURL(URL(string: UIApplication.openSettingsURLString)!)
        } label: {
          Label("Settings", systemImage: "gear")
        }
        .labelStyle(.iconOnly)
      }
    }
    .task {
      await store.task()
    }
  }
}

#Preview {
  ExternalStorageIcon(store: ExternalStorageIconStore())
}
