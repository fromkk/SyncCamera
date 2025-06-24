import AVFoundation
import OSLog
import Observation
import Photos
import SwiftUI
import UIKit

/// カメラの操作や設定、撮影、同期処理などを管理するクラス
@Observable
final class CameraStore: NSObject, AVCapturePhotoCaptureDelegate, SyncDelegate {
  /// ログ出力用のLogger（デバッグやエラー記録用）
  private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier!,
    category: "CameraStore"
  )

  /// カメラのキャプチャセッションを管理
  let session = AVCaptureSession()
  /// 現在使用中のビデオ入力デバイス
  var currentVideoInput: AVCaptureDeviceInput?
  /// 写真撮影用の出力
  private let photoOutput = AVCapturePhotoOutput()
  /// エラー情報を保持
  var error: (any Error)?
  /// 現在のキャプチャモード（写真/動画）
  private(set) var captureMode: CaptureMode = .photo
  /// カメラ処理用のシリアルキュー
  private let queue = DispatchQueue(label: "me.fromkk.SyncCamera.CameraStore")

  /// 同期画面の表示状態
  var isSyncViewPresented: Bool = false
  /// 同期処理を管理するストア
  let syncStore: SyncStore = .init()

  /// プレビュー表示用のレイヤー
  var previewLayer: AVCaptureVideoPreviewLayer?

  /// 設定項目などの表示・非表示
  var isConfigurationsVisible: Bool = false {
    didSet {
      if !isConfigurationsVisible {
        configurationMode = nil
      }
    }
  }

  /// キャプチャモード（写真/動画）の定義
  enum CaptureMode {
    case photo
    /// 写真撮影モード
    case video/// 動画撮影モード
  }

  /// カメラ関連のエラー定義
  enum CameraError: Error {
    case inputDeviceNotFound
    /// 入力デバイスが見つからない
    case couldntAddVideoDataOutput
    /// ビデオ出力の追加に失敗
    case couldntAddPhotoOutput
    /// 写真出力の追加に失敗
    case couldntSetPreset/// プリセット設定に失敗
  }

  var configurationMode: ConfigurationMode?

  enum ConfigurationMode {
    case iso
    case shutterSpeed
  }

  enum ISO: Hashable, CustomStringConvertible {
    case auto
    case value(Int)

    var description: String {
      switch self {
      case .auto:
        return "AUTO"
      case let .value(value):
        return "\(value)"
      }
    }
  }

  var currentISO: ISO? = .auto

  var isoValues: [ISO] {
    // TODO: 正しい値に変更
    return [
      .auto, .value(100), .value(200), .value(400), .value(800), .value(1600), .value(3200),
      .value(6400), .value(12800),
    ]
  }

  func updateISO(_ iso: ISO) {
    guard let currentISO, let device = currentVideoInput?.device else { return }

    do {
      switch currentISO {
      case .auto:
        try device.lockForConfiguration()
        device.exposureMode = .autoExpose
        device.unlockForConfiguration()
      case let .value(iso):
        let duration = device.exposureDuration
        try device.lockForConfiguration()
        device.setExposureModeCustom(duration: duration, iso: Float(iso))
        device.unlockForConfiguration()
      }
    } catch {
      logger.error("error \(error.localizedDescription)")
    }
  }

  /// CameraStoreの初期化処理。SyncDelegateの設定とカメラ利用可の場合の構成処理
  override init() {
    super.init()
    syncStore.delegate = self
    if isCameraAvailable {
      configuration()
    }
  }

  /// カメラセッションの構成を行う（入力・出力の追加、プリセット設定など）
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

  /// 入力デバイス（カメラ）を切り替える
  func changeDeviceInput(_ device: AVCaptureDevice) {
    logger.info("\(#function)")
    guard isCameraAvailable else { return }

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

  /// カメラが利用可能かどうかを判定
  var isCameraAvailable: Bool {
    #if targetEnvironment(simulator)
      return false
    #else
      if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
        return false
      } else {
        return AVCaptureDevice.default(
          .builtInWideAngleCamera,
          for: .video,
          position: .back
        ) != nil
      }
    #endif
  }

  // MARK: - Device Sessions
  /// 背面カメラのデバイス探索セッション
  let backVideoDeviceDiscoverySession = AVCaptureDevice.DiscoverySession(
    deviceTypes: [
      .builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera,
      .builtInWideAngleCamera,
    ],
    mediaType: .video,
    position: .back
  )

  /// 前面カメラのデバイス探索セッション
  let frontVideoDeviceDiscoverySession = AVCaptureDevice.DiscoverySession(
    deviceTypes: [.builtInWideAngleCamera],
    mediaType: .video,
    position: .front
  )

  /// カメラセッションの再開処理（同期広告も開始）
  func resume() {
    logger.info("\(#function)")
    guard isCameraAvailable else { return }

    if !syncStore.isAdvertising {
      syncStore.startAdvertising()
    }

    queue.async { [weak self] in
      guard let self, !self.session.isRunning else {
        self?.logger.info("already running")
        return
      }
      self.session.startRunning()
    }
  }

  /// カメラセッションの一時停止処理（同期広告も停止）
  func pause() {
    logger.info("\(#function)")
    guard isCameraAvailable else { return }
    if syncStore.isAdvertising {
      syncStore.stopAdvertising()
    }

    queue.async { [weak self] in
      guard let self, self.session.isRunning else {
        self?.logger.info("already stopping")
        return
      }
      self.session.stopRunning()
    }
  }

  /// 写真を撮影する（同期イベント発火時にも利用）
  private func takePhoto() {
    guard isCameraAvailable else { return }
    queue.async { [weak self] in
      guard let self else { return }
      let settings = AVCapturePhotoSettings()
      self.photoOutput.capturePhoto(with: settings, delegate: self)
    }
  }

  /// ユーザー操作で写真撮影を行う（同期イベントも送信）
  func takePhotoFromUser() {
    logger.info("\(#function)")
    guard isCameraAvailable else { return }
    syncStore.sendEvent(.takePhoto)
    takePhoto()
  }

  // MARK: - AVCapturePhotoCaptureDelegate

  /// 撮影した写真データを一時的に保持
  var photoData: Data?

  /// 写真撮影完了時のデリゲートメソッド。写真データをフォトライブラリに保存
  func photoOutput(
    _ output: AVCapturePhotoOutput,
    didFinishProcessingPhoto photo: AVCapturePhoto,
    error: (any Error)?
  ) {
    logger.info("\(#function)")
    if let error {
      self.error = error
    } else {
      guard let data = photo.fileDataRepresentation() else {
        return
      }
      PHPhotoLibrary.shared().performChanges {
        let request = PHAssetCreationRequest.forAsset()
        request.addResource(with: .photo, data: data, options: nil)
      }
    }
  }

  // MARK: - SyncDelegate

  /// 同期イベント受信時の処理（例：写真撮影イベント）
  func receivedEvent(_ event: SyncStore.Event) {
    switch event {
    case .takePhoto:
      takePhoto()
    }
  }
}

/// AVCaptureVideoPreviewLayerをSwiftUIで表示するためのビュー
struct CameraPreview: UIViewControllerRepresentable {
  /// プレビュー表示用のレイヤー
  let previewLayer: AVCaptureVideoPreviewLayer

  typealias UIViewControllerType = UIViewController
  /// UIViewControllerの生成とプレビューレイヤー追加
  func makeUIViewController(context: Context) -> UIViewController {
    let vc = UIViewController()
    vc.view.layer.addSublayer(previewLayer)
    return vc
  }

  /// UIViewControllerの更新時にプレビューレイヤーのフレームを更新
  func updateUIViewController(
    _ uiViewController: UIViewController,
    context: Context
  ) {
    previewLayer.frame = uiViewController.view.bounds
  }
}

/// カメラのプレビューや各種操作UIを提供するSwiftUIビュー
struct CameraView: View {
  /// カメラストア（状態管理と操作用）
  @Bindable var store: CameraStore
  /// 現在のシーンのフェーズ（アクティブ/非アクティブ等）
  @Environment(\.scenePhase) var scenePhase

  /// ビューの本体。カメラプレビューやボタンなどのUIを構築
  var body: some View {
    NavigationStack {
      ZStack(alignment: .bottom) {
        Color.black.ignoresSafeArea()

        if let previewLayer = store.previewLayer {
          CameraPreview(previewLayer: previewLayer)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }

        VStack(spacing: 16) {
          Button {
            store.isConfigurationsVisible.toggle()
          } label: {
            Capsule()
              .frame(width: 100, height: 6)
              .padding(.vertical, 8)
          }
          .tint(.white.opacity(0.5))
          .contentShape(.rect)

          if store.isConfigurationsVisible {
            HStack(spacing: 32) {
              Button {
                store.configurationMode = .iso
              } label: {
                Text("ISO")
              }

              Button {
                // TODO: Shutter speed
              } label: {
                Text("SS")
              }
            }
            .tint(.white)
            .transition(.move(edge: .bottom).combined(with: .opacity))
          }

          if let configurationMode = store.configurationMode {
            switch configurationMode {
            case .iso:
              SlideDialView(allValues: store.isoValues, selection: $store.currentISO)
              DialView(allValue: store.isoValues, selection: $store.currentISO) {
                Text("\($0.description)")
              }
            case .shutterSpeed:
              EmptyView()
            }
          } else {
            Button {
              store.takePhotoFromUser()
            } label: {
              Circle()
                .frame(width: 80, height: 80)
            }
            .accessibilityLabel(Text("シャッター"))
            .tint(.white)
            .padding(.bottom, 16)
          }

        }
        .animation(.default, value: store.isConfigurationsVisible)
      }
      .gesture(
        DragGesture().onEnded { value in
          if value.translation.height < -50 {
            store.isConfigurationsVisible = true
          } else if value.translation.height > 50 {
            store.isConfigurationsVisible = false
          }
        }
      )
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button {
            store.isSyncViewPresented.toggle()
          } label: {
            Label(
              "Sync",
              systemImage: "arrow.trianglehead.2.clockwise.rotate.90"
            )
            .labelStyle(.iconOnly)
          }
        }
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
    .sheet(isPresented: $store.isSyncViewPresented) {
      MultipeerBrowserView(store: store.syncStore)
    }
  }
}

#Preview {
  CameraView(store: CameraStore())
}
