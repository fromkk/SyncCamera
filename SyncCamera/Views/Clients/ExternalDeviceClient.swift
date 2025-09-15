import Foundation
import ImageCaptureCore
import OSLog

struct ExternalDeviceClient: Sendable {
  var mediaFiles: @Sendable (ICCameraDevice) async throws -> [ICCameraFile]
}

extension ExternalDeviceClient {
  static let liveValue: ExternalDeviceClient = {
    var lastDevice: ICCameraDevice?
    return Self(
      mediaFiles: { device in
        let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "\(Self.self)")
        guard !device.hasOpenSession else {
          logger.info("device hasOpenSession")
          return device.mediaFiles?.compactMap { $0 as? ICCameraFile } ?? []
        }
        try await device.requestOpenSession()
        logger.info("device mediaFiles \(String(describing: device.mediaFiles))")
        logger.info("device hasOpenSession \(device.hasOpenSession)")
        logger.info(
          "device contentCatalogPercentCompleted \(device.contentCatalogPercentCompleted)")
        while device.contentCatalogPercentCompleted < 100 {
          try await Task.sleep(for: .seconds(0.1))
          logger.info(
            "device contentCatalogPercentCompleted \(device.contentCatalogPercentCompleted)")
        }
        logger.info("device mediaFiles \(String(describing: device.mediaFiles))")
        return device.mediaFiles?.compactMap { $0 as? ICCameraFile } ?? []
      }
    )
  }()
}
