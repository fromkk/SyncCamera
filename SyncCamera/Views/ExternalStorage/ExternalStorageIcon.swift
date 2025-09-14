import AVKit
import Combine
import SwiftUI

@Observable
final class ExternalStorageIconStore: Identifiable {
  let id = UUID()

  var isAuthorized: Bool = false
  var selectedDevice: AVExternalStorageDevice?
  var deviceListStore: ExternalStorageDevicesStore?

  func task() async {
    switch AVExternalStorageDevice.authorizationStatus {
    case .authorized:
      isAuthorized = true
    case .notDetermined:
      isAuthorized = await AVExternalStorageDevice.requestAccess()
    case .denied, .restricted:
      isAuthorized = false
    default:
      isAuthorized = false
    }
  }

  func showDeviceList() {
    let deviceListStore = ExternalStorageDevicesStore(
      selectedDevice: selectedDevice
    )
    trackSelectedDevice(deviceListStore)
    self.deviceListStore = deviceListStore
  }

  private func trackSelectedDevice(
    _ deviceListStore: ExternalStorageDevicesStore
  ) {
    self.selectedDevice = withObservationTracking({
      deviceListStore.selectedDevice
    }) { [weak self, weak deviceListStore] in
      Task { @MainActor in
        guard let self, let deviceListStore else { return }
        self.trackSelectedDevice(deviceListStore)
      }
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
          store.showDeviceList()
        } label: {
          if let device = store.selectedDevice {
            Text("\(device.displayName ?? "Unknown")")
              .font(.system(size: 18))
          } else {
            Label("Devices", systemImage: "list.bullet")
              .labelStyle(.iconOnly)
              .font(.system(size: 24))
          }
        }
      } else {
        Button {
          openURL(URL(string: UIApplication.openSettingsURLString)!)
        } label: {
          Label("Settings", systemImage: "gear")
        }
        .labelStyle(.iconOnly)
        .font(.system(size: 24))
      }
    }
    .tint(Color.white)
    .task {
      await store.task()
    }
    .sheet(item: $store.deviceListStore) { store in
      ExternalStorageDevicesView(store: store)
    }
  }
}

#Preview {
  ExternalStorageIcon(store: ExternalStorageIconStore())
}
