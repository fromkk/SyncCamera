import UIKit

struct DeviceOrientationClient: Sendable {
  var subscribe: @Sendable () -> AsyncStream<UIDeviceOrientation>
}

extension DeviceOrientationClient {
  static let liveValue: DeviceOrientationClient = Self(
    subscribe: {
      return AsyncStream { continuation in
        let task = Task { @MainActor in
          let device = UIDevice.current
          device.beginGeneratingDeviceOrientationNotifications()
          for await _ in NotificationCenter.default.notifications(
            named: UIDevice.orientationDidChangeNotification
          ).map({ _ in () }) {
            continuation.yield(UIDevice.current.orientation)
          }
        }
        continuation.onTermination = { _ in
          Task { @MainActor in
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
          }
          task.cancel()
        }
      }
    }
  )
}
