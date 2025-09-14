import AVKit
import Combine
import SwiftUI

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
