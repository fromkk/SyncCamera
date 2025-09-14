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

@Observable
final class ExternalStorageDevicesStore: NSObject, Identifiable {
  let id = UUID()

  init(selectedDevice: AVExternalStorageDevice? = nil) {
    super.init()
    self.selectedDevice = selectedDevice
  }
  var devices: [AVExternalStorageDevice] = []
  var selectedDevice: AVExternalStorageDevice?

  private var cancellables: Set<AnyCancellable> = .init()

  func startSubscribe() {
    self.devices =
      AVExternalStorageDeviceDiscoverySession.shared?.externalStorageDevices
      ?? []
    AVExternalStorageDeviceDiscoverySession.shared?.publisher(
      for: \.externalStorageDevices
    ).sink { [weak self] devices in
      self?.devices = devices
    }
    .store(in: &cancellables)
  }

  func stopSubscribe() {
    cancellables.removeAll()
  }
}

struct ExternalStorageDevicesView: View {
  @Bindable var store: ExternalStorageDevicesStore

  var body: some View {
    Group {
      if store.devices.isEmpty {
        Text("No Devices")
      } else {
        List(store.devices, id: \.uuid) { device in
          Button {
            if store.selectedDevice?.isEqual(device) ?? false {
              store.selectedDevice = nil
            } else {
              store.selectedDevice = device
            }
          } label: {
            HStack(spacing: 8) {
              if store.selectedDevice?.isEqual(device) ?? false {
                Image(systemName: "checkmark")
              }

              Text(device.displayName ?? "Unknown")
            }
            .font(.system(size: 18))
          }
        }
      }
    }
    .tint(Color(uiColor: .label))
    .onAppear {
      store.startSubscribe()
    }
    .onDisappear {
      store.stopSubscribe()
    }
  }
}
