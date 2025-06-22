import AVFoundation
import Foundation
import Photos

enum Permission {
  case notDetermined
  case authorized
  case denied
}

struct PermissionClient: Sendable {
  var cameraPermission: @Sendable () -> Permission?
  var requestCameraPermission: @Sendable () async -> Permission
  var addLibraryPermission: @Sendable () -> Permission?
  var requestAddLibraryPermission: @Sendable () async -> Permission?
}

extension PermissionClient {
  static let liveValue: PermissionClient = Self(
    cameraPermission: {
      switch AVCaptureDevice.authorizationStatus(for: .video) {
      case .notDetermined:
        return .notDetermined
      case .authorized:
        return .authorized
      case .denied, .restricted:
        return .denied
      @unknown default:
        return nil
      }
    },
    requestCameraPermission: {
      let result = await AVCaptureDevice.requestAccess(for: .video)
      if result {
        return .authorized
      } else {
        return .denied
      }
    },
    addLibraryPermission: {
      let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
      switch status {
      case .notDetermined:
        return .notDetermined
      case .authorized, .limited:
        return .authorized
      case .denied, .restricted:
        return .denied
      @unknown default:
        return nil
      }
    },
    requestAddLibraryPermission: {
      let result = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
      switch result {
      case .notDetermined:
        return .notDetermined
      case .authorized, .limited:
        return .authorized
      case .denied, .restricted:
        return .denied
      @unknown default:
        return nil
      }
    }
  )
}
