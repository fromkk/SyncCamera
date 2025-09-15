import ImageCaptureCore
import OSLog
import SwiftUI

@Observable
final class ExternalStoragePhotosStore: NSObject, ICDeviceBrowserDelegate,
  ICDeviceDelegate, Identifiable
{
  enum Errors: Error {
    case noSession
  }

  private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier!,
    category: "ExternalStoragePhotosStore"
  )

  var id: String { selectedUUID }
  var selectedDevice: ICCameraDevice?
  var mediaFiles: [ICCameraFile] = []
  var externalDevicesClient: ExternalDevicesClient

  let selectedUUID: String
  init(selectedUUID: String, externalDevicesClient: ExternalDevicesClient) {
    self.selectedUUID = selectedUUID
    self.externalDevicesClient = externalDevicesClient
  }

  func startSubscribe() async {
    logger.info("\(#function) \(String(describing: self.selectedUUID))")
    guard await externalDevicesClient.requestPermission() else {
      logger.info("no permission")
      return
    }
    for await devices in externalDevicesClient.devices() {
      logger.info("devices \(devices)")
      if let device = devices.first(where: { $0.uuidString == selectedUUID }) {
        self.selectedDevice = device
        self.selectedDevice?.delegate = self
        await updateDevices()
      }
    }
  }

  func stopSubscribe() {
    logger.info("\(#function)")
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
    guard let selectedDevice else {
      logger.info("no selectedDevice")
      return
    }
    let client = ExternalDeviceClient.liveValue
    mediaFiles = (try? await client.mediaFiles(selectedDevice)) ?? []
  }

  // MARK: - ICDeviceDelegate

  func device(_ device: ICDevice, didCloseSessionWithError error: (any Error)?) {
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
    NavigationStack {
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
      .navigationBarTitleDisplayMode(.inline)
      .navigationTitle("Media files")
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
