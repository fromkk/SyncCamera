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

  let deviceOrientationClient: DeviceOrientationClient = .liveValue

  var currentOrientation: UIDeviceOrientation?

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
    case focus
  }
  // MARK: - Focus

  enum FocusMode: Hashable, CustomStringConvertible {
    case auto
    case value(Float)

    var description: String {
      switch self {
      case .auto:
        return "AUTO"
      case let .value(value):
        return String(format: "%.2f", value)
      }
    }
  }

  var currentFocus: FocusMode? = .auto

  func updateFocus(_ focus: FocusMode) {
    guard let device = currentVideoInput?.device else { return }
    do {
      try device.lockForConfiguration()
      defer { device.unlockForConfiguration() }

      switch focus {
      case .auto:
        guard device.isFocusModeSupported(.continuousAutoFocus) else {
          logger.warning("!device.isFocusModeSupported(.continuousAutoFocus)")
          return
        }
        device.focusMode = .continuousAutoFocus
      case let .value(value):
        guard device.isFocusModeSupported(.locked) else {
          logger.warning("!device.isFocusModeSupported(.locked)")
          return
        }
        device.focusMode = .locked
        device.setFocusModeLocked(lensPosition: value)
      }
    } catch {
      logger.error("error \(error.localizedDescription)")
    }
  }

  // MARK: - ISO

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
    guard let device = currentVideoInput?.device else {
      return [.auto]
    }

    let minISO = Int(device.activeFormat.minISO)
    let maxISO = Int(device.activeFormat.maxISO)

    let availableISO: [Int] = [
      64, 100, 200, 400, 800, 1600, 3200, 6400, 12800, 25600,
    ]
    let result: [Int] = availableISO.filter { minISO <= $0 && $0 <= maxISO }
    return [
      .auto
    ] + result.map { .value($0) }
  }

  func updateISO(_ iso: ISO) {
    guard let device = currentVideoInput?.device else { return }
    do {
      try device.lockForConfiguration()
      defer {
        device.unlockForConfiguration()
      }
      switch iso {
      case .auto:
        guard device.isExposureModeSupported(.autoExpose) else {
          logger.warning("!device.isExposureModeSupported(.autoExpose)")
          return
        }
        device.exposureMode = .autoExpose
      case let .value(iso):
        let duration = device.exposureDuration
        guard device.isExposureModeSupported(.custom) else {
          logger.warning("!device.isExposureModeSupported(.custom)")
          return
        }
        device.exposureMode = .custom
        device.setExposureModeCustom(duration: duration, iso: Float(iso))
      }
    } catch {
      logger.error("error \(error.localizedDescription)")
    }
  }

  // MARK: - Shutter Speed

  enum ShutterSpeed: Hashable, CustomStringConvertible {
    case auto
    case value(TimeInterval)  // 秒単位

    var description: String {
      switch self {
      case .auto:
        return "AUTO"
      case let .value(seconds):
        if seconds >= 1.0 {
          return String(format: "%.0f\"", seconds)
        } else {
          return "1/\(Int(round(1.0 / seconds)))"
        }
      }
    }
  }

  var currentShutterSpeed: ShutterSpeed? = .auto

  var shutterSpeedValues: [ShutterSpeed] {
    guard let device = currentVideoInput?.device else {
      return [.auto]
    }

    let minDuration = device.activeFormat.minExposureDuration
    let maxDuration = device.activeFormat.maxExposureDuration

    let availableSeconds: [Double] = [
      1.0, 1.0 / 2.0, 1.0 / 4.0, 1.0 / 8.0, 1.0 / 15.0, 1.0 / 30.0, 1.0 / 60.0,
      1.0 / 100.0, 1.0 / 200.0, 1.0 / 400.0, 1.0 / 800.0, 1.0 / 1600.0,
      1.0 / 3200.0, 1.0 / 6400.0, 1.0 / 12800.0, 1.0 / 25600.0,
    ]

    let result = availableSeconds.filter {
      minDuration.seconds <= $0 && $0 <= maxDuration.seconds
    }

    return [.auto] + result.map { .value($0) }
  }

  // MARK: - リアルタイム値
  /// デバイスから取得したリアルタイムのISO値
  var realTimeISO: Float = 0
  /// デバイスから取得したリアルタイムのシャッタースピード値（秒）
  var realTimeShutterSpeed: Double = 0

  func updateShutterSpeed(_ shutterSpeed: ShutterSpeed) {
    guard let device = currentVideoInput?.device else { return }
    do {
      try device.lockForConfiguration()
      defer { device.unlockForConfiguration() }

      switch shutterSpeed {
      case .auto:
        guard device.isExposureModeSupported(.autoExpose) else {
          logger.warning("!device.isExposureModeSupported(.autoExpose)")
          return
        }
        device.exposureMode = .autoExpose
      case let .value(seconds):
        let iso = device.iso
        guard device.isExposureModeSupported(.custom) else {
          logger.warning("!device.isExposureModeSupported(.custom)")
          return
        }
        device.exposureMode = .custom
        device.setExposureModeCustom(
          duration: CMTimeMakeWithSeconds(
            seconds,
            preferredTimescale: 1_000_000
          ),
          iso: iso
        )
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
      subscribeDeviceValues()
      subscribeDeviceOrientation()
    }
  }

  private var timer: Timer?

  private func subscribeDeviceValues() {
    timer?.invalidate()
    timer = Timer.scheduledTimer(
      withTimeInterval: 1.0 / 30.0,
      repeats: true,
      block: { [weak self] _ in
        guard let self, let device = self.currentVideoInput?.device else {
          return
        }

        self.realTimeISO = device.iso
        self.realTimeShutterSpeed = device.exposureDuration.seconds
      }
    )
  }

  private var deviceOrientationTask: Task<Void, Never>?

  private func subscribeDeviceOrientation() {
    deviceOrientationTask = Task {
      for await orientation in deviceOrientationClient.subscribe() {
        currentOrientation = orientation
      }
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
      if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"]
        == "1"
      {
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
      .builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera,
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
      if !(self.timer?.isValid ?? false) {
        self.subscribeDeviceValues()
      }
      deviceOrientationTask?.cancel()
      subscribeDeviceOrientation()
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
      if self.timer?.isValid ?? false {
        self.timer?.invalidate()
      }
      deviceOrientationTask?.cancel()
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

/// カメラのプレビューや各種操作UIを提供するSwiftUIビュー
struct CameraView: View {
  /// カメラストア（状態管理と操作用）
  @Bindable var store: CameraStore
  /// 現在のシーンのフェーズ（アクティブ/非アクティブ等）
  @Environment(\.scenePhase) var scenePhase

  /// ビューの本体。カメラプレビューやボタンなどのUIを構築
  var body: some View {
    ZStack(alignment: .center) {
      if let previewLayer = store.previewLayer {
        GeometryReader { proxy in
          if store.currentOrientation?.isPortrait ?? true {
            VStack {
              cameraPreview(proxy: proxy, layer: previewLayer)
            }
          } else {
            HStack {
              cameraPreview(proxy: proxy, layer: previewLayer)
            }
          }
        }
      }

      // リアルタイム情報表示
      VStack {
        HStack(spacing: 20) {
          Text("ISO: \(Int(store.realTimeISO))")
            .font(.system(size: 14, weight: .medium, design: .monospaced))
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.6))
            .cornerRadius(8)

          Text("SS: \(shutterSpeedString(from: store.realTimeShutterSpeed))")
            .font(.system(size: 14, weight: .medium, design: .monospaced))
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.6))
            .cornerRadius(8)
        }
        .padding(.top, 44)

        Spacer()
      }

      VStack(spacing: 16) {
        Spacer()
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
              if store.configurationMode != .iso {
                store.configurationMode = .iso
              } else {
                store.configurationMode = nil
              }
            } label: {
              Text("ISO")
                .padding(8)
                .frame(minWidth: 80)
                .background(
                  store.configurationMode == .iso
                    ? Color.accentColor : Color.clear
                )
                .foregroundColor(
                  store.configurationMode == .iso
                    ? .white : .white.opacity(0.7)
                )
                .cornerRadius(8)
                .overlay(
                  RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.5), lineWidth: 1)
                )
            }

            Button {
              if store.configurationMode != .shutterSpeed {
                store.configurationMode = .shutterSpeed
              } else {
                store.configurationMode = nil
              }
            } label: {
              Text("SS")
                .padding(8)
                .frame(minWidth: 80)
                .background(
                  store.configurationMode == .shutterSpeed
                    ? Color.accentColor : Color.clear
                )
                .foregroundColor(
                  store.configurationMode == .shutterSpeed
                    ? .white : .white.opacity(0.7)
                )
                .cornerRadius(8)
                .overlay(
                  RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.5), lineWidth: 1)
                )
            }

            Button {
              if store.configurationMode != .focus {
                store.configurationMode = .focus
              } else {
                store.configurationMode = nil
              }
            } label: {
              Text("Focus")
                .padding(8)
                .frame(minWidth: 80)
                .background(
                  store.configurationMode == .focus
                    ? Color.accentColor : Color.clear
                )
                .foregroundColor(
                  store.configurationMode == .focus
                    ? .white : .white.opacity(0.7)
                )
                .cornerRadius(8)
                .overlay(
                  RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.5), lineWidth: 1)
                )
            }
          }
          .tint(.white)
          .transition(.move(edge: .bottom).combined(with: .opacity))
        }

        if let configurationMode = store.configurationMode {
          switch configurationMode {
          case .iso:
            SlideDialView(
              allValues: store.isoValues,
              selection: Binding(
                get: {
                  store.currentISO
                },
                set: {
                  store.currentISO = $0
                  guard let iso = $0 else { return }
                  store.updateISO(iso)
                }
              )
            )
          case .shutterSpeed:
            SlideDialView(
              allValues: store.shutterSpeedValues,
              selection: Binding(
                get: {
                  store.currentShutterSpeed
                },
                set: {
                  store.currentShutterSpeed = $0
                  guard let ss = $0 else { return }
                  store.updateShutterSpeed(ss)
                }
              )
            )
          case .focus:
            HStack(spacing: 16) {
              Button {
                if store.currentFocus == .auto {
                  let focus: CameraStore.FocusMode = .value(0)
                  store.currentFocus = focus
                  store.updateFocus(focus)
                } else {
                  store.currentFocus = .auto
                }
              } label: {
                Text("AUTO")
              }
              .padding(8)
              .frame(minWidth: 80)
              .background(
                store.currentFocus == .auto ? Color.accentColor : Color.clear
              )
              .foregroundColor(
                store.currentFocus == .auto ? .white : .white.opacity(0.7)
              )
              .cornerRadius(8)
              .overlay(
                RoundedRectangle(cornerRadius: 8)
                  .stroke(Color.white.opacity(0.5), lineWidth: 1)
              )

              if store.currentFocus != .auto {
                Slider(
                  value: Binding<Float>(
                    get: {
                      switch store.currentFocus {
                      case .value(let float):
                        return float
                      case .auto, .none:
                        return 0
                      }
                    },
                    set: { float in
                      let value: CameraStore.FocusMode = .value(float)
                      store.currentFocus = value
                      store.updateFocus(value)
                    }
                  )
                )
              }
            }
            .padding(.horizontal)
          }
        } else {
          HStack {
            // Left placeholder to balance the sync button
            Spacer()
              .frame(width: 80)

            Spacer()

            // Shutter button in the middle
            Button {
              store.takePhotoFromUser()
            } label: {
              Circle()
                .frame(width: 80, height: 80)
            }
            .accessibilityLabel(Text("シャッター"))
            .tint(.white)
            .padding(.bottom, 16)

            Spacer()

            // Sync button on the right
            Button {
              store.isSyncViewPresented.toggle()
            } label: {
              HStack {
                Image(systemName: "arrow.triangle.2.circlepath.camera")
                  .resizable()
                  .aspectRatio(contentMode: .fit)
                  .frame(width: 44, height: 44)
                if store.syncStore.mcSession.connectedPeers.count > 0 {
                  Text("\(store.syncStore.mcSession.connectedPeers.count)")
                    .font(.footnote)
                    .padding(4)
                }
              }
            }
            .tint(Color.white)
            .frame(width: 80, height: 80)
          }
          .padding()
        }

      }
      .animation(.default, value: store.isConfigurationsVisible)
    }
    .background(Color.black)
    .ignoresSafeArea(edges: [.top, .horizontal])
    .gesture(
      DragGesture().onEnded { value in
        if value.translation.height < -50 {
          store.isConfigurationsVisible = true
        } else if value.translation.height > 50 {
          store.isConfigurationsVisible = false
        }
      }
    )
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
    .sheet(isPresented: $store.isSyncViewPresented) {
      MultipeerBrowserView(store: store.syncStore)
    }
    .alert(
      "\(store.syncStore.pendingInvitation?.peerID.displayName ?? "")からペアリングが届いています",
      isPresented: Binding(
        get: { store.syncStore.pendingInvitation != nil },
        set: { _ in store.syncStore.pendingInvitation = nil }
      ),
      presenting: store.syncStore.pendingInvitation
    ) { _ in
      Button("OK") {
        store.syncStore.acceptInvitation()
      }
      Button("キャンセル", role: .cancel) {
        store.syncStore.declineInvitation()
      }
    } message: { _ in
      Text("接続しますか？")
    }
  }

  @ViewBuilder
  private func cameraPreview(
    proxy: GeometryProxy,
    layer: AVCaptureVideoPreviewLayer
  ) -> some View {
    Spacer()
    CameraPreview(
      previewLayer: layer,
      orientation: store.currentOrientation
    )
    .id("preview")
    .frame(
      width: frameWidth(for: proxy.size, orientation: store.currentOrientation),
      height: frameHeight(
        for: proxy.size,
        orientation: store.currentOrientation
      )
    )
    Spacer()
  }

  /// デバイスの向きに応じてフレームの幅を計算
  private func frameWidth(for size: CGSize, orientation: UIDeviceOrientation?)
    -> CGFloat
  {
    guard let orientation = orientation else { return size.width }

    if orientation.isPortrait {
      // 縦向きの場合は 3/4 の比率で縦長に
      return size.width * 0.75
    } else if orientation.isLandscape {
      // 横向きの場合は 4/3 の比率で横長に
      return size.width
    } else {
      return size.width
    }
  }

  /// デバイスの向きに応じてフレームの高さを計算
  private func frameHeight(for size: CGSize, orientation: UIDeviceOrientation?)
    -> CGFloat
  {
    guard let orientation = orientation else { return size.height }

    if orientation.isPortrait {
      // 縦向きの場合は 3/4 の比率で縦長に
      return size.height
    } else if orientation.isLandscape {
      // 横向きの場合は 4/3 の比率で横長に
      return size.height * 0.75
    } else {
      return size.height
    }
  }

  /// TimeInterval（秒）を写真用シャッタースピード表記に変換する。
  /// 例: 0.008 → "1/125", 0.5 → "1/2", 2.0 → "2″"
  func shutterSpeedString(
    from interval: TimeInterval,
    precisionForLong: Int = 2,
    usePrimeSymbol: Bool = true
  ) -> String {
    // 1 秒以上なら「秒」表記
    if interval >= 1.0 {
      // 端数がほぼ 0 なら整数だけを表示
      if abs(interval.rounded() - interval) < 0.01 {
        let seconds = Int(interval.rounded())
        return usePrimeSymbol ? "\(seconds)″" : "\(seconds)s"
      } else {
        // 小数部も残っていれば指定桁で丸める
        let fmt = "%.\(precisionForLong)f"
        return
          (usePrimeSymbol
          ? String(format: fmt + "″", interval)
          : String(format: fmt + "s", interval))
      }
    }

    // 1 秒未満なら「1/分母」表記
    // ── 定番ストップ（1/60, 1/125 など）に丸めることで見栄えを整える
    let commonStops: [Double] = [
      1.0 / 2.0, 1.0 / 4.0, 1.0 / 8.0, 1.0 / 15.0, 1.0 / 30.0, 1.0 / 60.0,
      1.0 / 100.0, 1.0 / 200.0, 1.0 / 400.0, 1.0 / 800.0, 1.0 / 1600.0,
      1.0 / 3200.0, 1.0 / 6400.0, 1.0 / 12800.0, 1.0 / 25600.0,
    ]

    // 最も近いストップを採用
    let nearest = commonStops.min(by: { abs($0 - interval) < abs($1 - interval) }) ?? interval
    let denominator = Int(round(1.0 / nearest))
    return "1/\(denominator)"
  }
}

#Preview {
  CameraView(store: CameraStore())
}
