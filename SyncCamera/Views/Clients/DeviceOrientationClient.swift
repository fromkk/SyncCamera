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

          // Yield the current orientation immediately
          continuation.yield(device.orientation)

          for await _ in NotificationCenter.default.notifications(
            named: UIDevice.orientationDidChangeNotification
          ).map({ _ in () }) {
            let currentOrientation = UIDevice.current.orientation
            // Only yield valid orientations
            if currentOrientation != .unknown && currentOrientation != .faceUp
              && currentOrientation != .faceDown
            {
              continuation.yield(currentOrientation)
            }
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
