import AVFoundation
import OSLog
import Observation
import Photos
import SwiftUI
import UIKit

@Observable
final class CameraStore: NSObject, AVCapturePhotoCaptureDelegate {
  private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "CameraStore")

  let session = AVCaptureSession()
  var currentVideoInput: AVCaptureDeviceInput?
  private let photoOutput = AVCapturePhotoOutput()
  var error: (any Error)?
  private(set) var captureMode: CaptureMode = .photo
  private let queue = DispatchQueue(label: "me.fromkk.SyncCamera.CameraStore")

  var previewLayer: AVCaptureVideoPreviewLayer?

  enum CaptureMode {
    case photo
    case video
  }

  enum CameraError: Error {
    case inputDeviceNotFound
    case couldntAddVideoDataOutput
    case couldntAddPhotoOutput
    case couldntSetPreset
  }

  override init() {
    super.init()
    configuration()
  }

  private func configuration() {
    logger.info("\(#function)")
    queue.async { [weak self] in
      guard let self else { return }
      do {
        self.session.beginConfiguration()

        if let device = self.backVideoDeviceDiscoverySession.devices.first {
          let videoInput = try AVCaptureDeviceInput(device: device)
          if self.session.canAddInput(videoInput) {
            self.session.addInput(videoInput)
            self.currentVideoInput = videoInput
          }
        } else {
          throw CameraError.inputDeviceNotFound
        }

        if self.session.canAddOutput(self.photoOutput) {
          self.session.addOutput(self.photoOutput)
        } else {
          throw CameraError.couldntAddPhotoOutput
        }

        switch self.captureMode {
        case .photo:
          if self.session.canSetSessionPreset(.photo) {
            self.session.sessionPreset = .photo
          } else {
            throw CameraError.couldntSetPreset
          }
        case .video:
          if self.session.canSetSessionPreset(.high) {
            self.session.sessionPreset = .high
          } else {
            throw CameraError.couldntSetPreset
          }
        }

        self.session.commitConfiguration()

        self.previewLayer = AVCaptureVideoPreviewLayer(session: self.session)
        self.previewLayer?.videoGravity = .resizeAspect

        self.session.startRunning()
      } catch {
        self.error = error
        logger.info("\(#function) error \(String(describing: error))")
      }
    }
  }

  func changeDeviceInput(_ device: AVCaptureDevice) {
    logger.info("\(#function)")
    queue.async { [weak self] in
      guard let self else { return }
      self.session.stopRunning()
      self.session.beginConfiguration()

      if let currentVideoInput = self.currentVideoInput,
        self.session.inputs.contains(currentVideoInput)
      {
        self.session.removeInput(currentVideoInput)
      }

      do {
        let inputDevice = try AVCaptureDeviceInput(device: device)
        if self.session.canAddInput(inputDevice) {
          self.session.addInput(inputDevice)
        }
      } catch {
        self.error = error
      }

      self.session.commitConfiguration()
      self.session.startRunning()
    }
  }

  // MARK: - Device Sessions
  let backVideoDeviceDiscoverySession = AVCaptureDevice.DiscoverySession(
    deviceTypes: [
      .builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera,
      .builtInWideAngleCamera,
    ],
    mediaType: .video,
    position: .back
  )

  let frontVideoDeviceDiscoverySession = AVCaptureDevice.DiscoverySession(
    deviceTypes: [.builtInWideAngleCamera],
    mediaType: .video,
    position: .front
  )

  func resume() {
    logger.info("\(#function)")
    queue.async { [weak self] in
      guard let self, !self.session.isRunning else {
        self?.logger.info("already running")
        return
      }
      self.session.startRunning()
    }
  }

  func pause() {
    logger.info("\(#function)")
    queue.async { [weak self] in
      guard let self, self.session.isRunning else {
        self?.logger.info("already stopping")
        return
      }
      self.session.stopRunning()
    }
  }

  func takePhoto() {
    logger.info("\(#function)")
    queue.async { [weak self] in
      guard let self else { return }
      let settings = AVCapturePhotoSettings()
      self.photoOutput.capturePhoto(with: settings, delegate: self)
    }
  }

  // MARK: - AVCapturePhotoCaptureDelegate

  var photoData: Data?

  func photoOutput(
    _ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto,
    error: (any Error)?
  ) {
    logger.info("\(#function)")
    if let error {
      self.error = error
    } else {
      photoData = photo.fileDataRepresentation()
    }
  }
}

struct CameraPreview: UIViewControllerRepresentable {
  let previewLayer: AVCaptureVideoPreviewLayer

  typealias UIViewControllerType = UIViewController
  func makeUIViewController(context: Context) -> UIViewController {
    let vc = UIViewController()
    vc.view.layer.addSublayer(previewLayer)
    return vc
  }

  func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
    previewLayer.frame = uiViewController.view.bounds
  }
}

struct CameraView: View {
  @Bindable var store: CameraStore
  @Environment(\.scenePhase) var scenePhase

  var body: some View {
    ZStack(alignment: .bottom) {
      if let previewLayer = store.previewLayer {
        CameraPreview(previewLayer: previewLayer)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }

      Button {
        store.takePhoto()
      } label: {
        Label("Shutter", systemImage: "camera.fill")
          .labelStyle(.iconOnly)
      }
      .frame(width: 80, height: 80)
      .padding(.bottom, 16)
    }
    .onAppear {
      store.resume()
    }
    .onDisappear {
      store.pause()
    }
    .onChange(of: scenePhase) { oldValue, newValue in
      switch newValue {
      case .active:
        store.resume()
      default:
        store.pause()
      }
    }
    .alert(
      isPresented: Binding(
        get: { store.error != nil },
        set: {
          if !$0 {
            store.error = nil
          }
        }
      )
    ) {
      Alert(
        title: Text("エラー"),
        message: store.error.flatMap {
          Text(
            $0.localizedDescription
          )
        }
      )
    }
  }
}
