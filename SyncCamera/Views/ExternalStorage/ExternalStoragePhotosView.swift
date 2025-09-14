import ImageCaptureCore
import OSLog
import SwiftUI

@Observable
final class ExternalStoragePhotosStore: NSObject, ICDeviceBrowserDelegate,
  ICDeviceDelegate, Identifiable
{
  private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier!,
    category: "ExternalStoragePhotosStore"
  )
  var deviceBrowser: ICDeviceBrowser

  var id: String { selectedUUID }
  var selectedDevice: ICCameraDevice?
  var mediaFiles: [ICCameraFile] = []

  let selectedUUID: String
  init(deviceBrowser: ICDeviceBrowser, selectedUUID: String) {
    self.deviceBrowser = deviceBrowser
    self.selectedUUID = selectedUUID
  }

  func startSubscribe() async {
    logger.info("\(#function)")
    deviceBrowser.delegate = self
    deviceBrowser.start()
    Task {
      await updateDevices()
    }
  }

  func stopSubscribe() {
    logger.info("\(#function)")
    selectedDevice?.requestCloseSession()
    deviceBrowser.stop()
  }

  // MARK: - ICDeviceBrowserDelegate

  func deviceBrowser(
    _ browser: ICDeviceBrowser,
    didAdd device: ICDevice,
    moreComing: Bool
  ) {
    logger.info("\(#function)")
    Task {
      await updateDevices()
    }
  }

  func deviceBrowser(
    _ browser: ICDeviceBrowser,
    didRemove device: ICDevice,
    moreGoing: Bool
  ) {
    logger.info("\(#function)")
    Task {
      await updateDevices()
    }
  }

  private func updateDevices() async {
    guard
      selectedDevice == nil,
      let device = deviceBrowser.devices?.first(where: {
        $0.uuidString == selectedUUID
      }) as? ICCameraDevice
    else {
      logger.info("device not found")
      return
    }
    logger.info(
      "selectedDevice \(device.name ?? "") hasOpenSession \(device.hasOpenSession)"
    )
    self.selectedDevice = device
    device.delegate = self
    if device.hasOpenSession {
      mediaFiles = device.mediaFiles?.compactMap { $0 as? ICCameraFile } ?? []
    } else {
      do {
        try await device.requestOpenSession()
        while device.contentCatalogPercentCompleted < 100 {
          try await Task.sleep(for: .seconds(0.1))
          logger.info(
            "device.contentCatalogPercentCompleted \(device.contentCatalogPercentCompleted)"
          )
        }
        mediaFiles = device.mediaFiles?.compactMap { $0 as? ICCameraFile } ?? []
      } catch {
        logger.error("error \(error.localizedDescription)")
      }
    }
  }

  // MARK: - ICDeviceDelegate

  func device(_ device: ICDevice, didCloseSessionWithError error: (any Error)?)
  {
    logger.error(
      "\(#function) device \(device.name ?? "") error \(error?.localizedDescription ?? "")"
    )
  }

  func didRemove(_ device: ICDevice) {
    logger.info("\(#function) device \(device.name ?? "")")
  }

  func device(_ device: ICDevice, didOpenSessionWithError error: (any Error)?) {
    logger.error(
      "\(#function) device \(device.name ?? "") error \(error?.localizedDescription ?? "")"
    )
  }
}

struct ExternalStoragePhotosView: View {
  @Bindable var store: ExternalStoragePhotosStore

  var body: some View {
    Group {
      if store.selectedDevice != nil {
        ScrollView {
          LazyVGrid(columns: Array(repeating: GridItem(), count: 3)) {
            ForEach(store.mediaFiles, id: \.name) { mediaFile in
              ExternalStoragePhotoView(mediaFile: mediaFile)
            }
          }
        }
      } else {
        ProgressView()
      }
    }
    .task {
      await store.startSubscribe()
    }
    .onDisappear {
      store.stopSubscribe()
    }
  }
}

struct ExternalStoragePhotoView: View {
  @State var mediaFile: ICCameraFile
  @State var thumbnailData: Data?

  var body: some View {
    Group {
      if let thumbnailData {
        Image(uiImage: UIImage(data: thumbnailData)!)
          .resizable()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .aspectRatio(1, contentMode: .fill)
      } else {
        ProgressView()
      }
    }
    .task {
      self.thumbnailData = try? await mediaFile.requestThumbnailData()
    }
  }
}
