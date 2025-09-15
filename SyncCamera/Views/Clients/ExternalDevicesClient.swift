import Foundation
@preconcurrency import ImageCaptureCore

struct ExternalDevicesClient: Sendable {
  var requestPermission: @Sendable () async -> Bool
  var devices: @Sendable () -> AsyncStream<[ICCameraDevice]>
}

extension ExternalDevicesClient {
  static let liveValue: ExternalDevicesClient = {
    let service = ExternalDevicesService(deviceBrowser: ICDeviceBrowser())
    return Self(
      requestPermission: {
        await service.requestPermission()
      },
      devices: {
        service.subscribeDevices()
      }
    )
  }()
}

private final class ExternalDevicesService: NSObject, ICDeviceBrowserDelegate {
  private let deviceBrowser: ICDeviceBrowser
  init(deviceBrowser: ICDeviceBrowser) {
    self.deviceBrowser = deviceBrowser
    super.init()
    self.deviceBrowser.delegate = self
    self.deviceBrowser.start()
  }

  private var continuation: AsyncStream<[ICCameraDevice]>.Continuation? = nil

  func requestPermission() async -> Bool {
    switch deviceBrowser.contentsAuthorizationStatus {
    case .authorized:
      return true
    case .notDetermined:
      switch await deviceBrowser.requestContentsAuthorization() {
      case .authorized:
        return true
      default:
        return false
      }
    default:
      return false
    }
  }

  func subscribeDevices() -> AsyncStream<[ICCameraDevice]> {
    return AsyncStream<[ICCameraDevice]> { [weak self] continuation in
      guard let self else { return }
      self.continuation = continuation
      continuation.yield(self.devices)
      continuation.onTermination = { [weak self] _ in
        self?.continuation = nil
        self?.deviceBrowser.stop()
      }
    }
  }

  var devices: [ICCameraDevice] {
    deviceBrowser.devices?.compactMap { $0 as? ICCameraDevice } ?? []
  }

  func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
    continuation?.yield(devices)
  }

  func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {
    continuation?.yield(devices)
  }
}
