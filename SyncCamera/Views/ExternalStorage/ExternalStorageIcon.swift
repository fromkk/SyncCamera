import Combine
import ImageCaptureCore
import SwiftUI

@Observable
final class ExternalStorageIconStore: Identifiable {
  let id = UUID()
  let deviceBrowwser: ICDeviceBrowser = ICDeviceBrowser()

  var isAuthorized: Bool = false
  var selectedDevice: ICCameraDevice?
  var deviceListStore: ExternalStorageDevicesStore?

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

  func showDeviceList() {
    let deviceListStore = ExternalStorageDevicesStore(
      deviceBrowser: deviceBrowwser,
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
    .sheet(item: $store.deviceListStore) { store in
      ExternalStorageDevicesView(store: store)
    }
  }
}

#Preview {
  ExternalStorageIcon(store: ExternalStorageIconStore())
}

@Observable
final class ExternalStorageDevicesStore: NSObject, Identifiable,
  ICDeviceBrowserDelegate
{
  let id = UUID()

  init(deviceBrowser: ICDeviceBrowser, selectedDevice: ICCameraDevice? = nil) {
    self.deviceBrowser = deviceBrowser
    super.init()
    self.deviceBrowser.delegate = self
    self.selectedDevice = selectedDevice
  }

  let deviceBrowser: ICDeviceBrowser
  var devices: [ICCameraDevice] = []
  var selectedDevice: ICCameraDevice?

  private var cancellables: Set<AnyCancellable> = .init()

  func startSubscribe() {
    deviceBrowser.start()

    deviceBrowser.publisher(for: \.devices).sink { [weak self] in
      self?.devices = $0?.compactMap { $0 as? ICCameraDevice } ?? []
    }
    .store(in: &cancellables)
  }

  func stopSubscribe() {
    deviceBrowser.stop()
    cancellables.removeAll()
  }

  func deviceBrowser(
    _ browser: ICDeviceBrowser,
    didAdd device: ICDevice,
    moreComing: Bool
  ) {
    updateDevices()
  }

  func deviceBrowser(
    _ browser: ICDeviceBrowser,
    didRemove device: ICDevice,
    moreGoing: Bool
  ) {
    updateDevices()
  }

  private func updateDevices() {
    self.devices =
      deviceBrowser.devices?.compactMap { $0 as? ICCameraDevice } ?? []
  }
}

struct ExternalStorageDevicesView: View {
  @Bindable var store: ExternalStorageDevicesStore

  var body: some View {
    Group {
      if store.devices.isEmpty {
        Text("No Devices")
      } else {
        List(store.devices, id: \.self) { device in
          Button {
            if store.selectedDevice == device {
              store.selectedDevice = nil
            } else {
              store.selectedDevice = device
            }
          } label: {
            HStack(spacing: 8) {
              if store.selectedDevice == device {
                Image(systemName: "checkmark")
              }
              Text(device.name ?? "Unknown")
            }
          }
        }
      }
    }
    .onAppear {
      subscribeDeviceList()
    }
    .onDisappear {
      unsubscribeDeviceList()
    }
  }

  private func subscribeDeviceList() {
    store.startSubscribe()
  }

  private func unsubscribeDeviceList() {
    store.stopSubscribe()
  }
}
