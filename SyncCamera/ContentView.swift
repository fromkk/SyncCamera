//
//  ContentView.swift
//  SyncCamera
//
//  Created by Kazuya Ueoka on 2025/06/22.
//

import AVFoundation
import Observation
import SwiftUI

@Observable
final class ContentStore {
  func checkPermission() {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .notDetermined:
      cameraPermission = .notDetermined
    case .authorized:
      cameraPermission = .authorized
      cameraStore = CameraStore()
    case .denied, .restricted:
      cameraPermission = .denied
    @unknown default:
      cameraPermission = nil
    }
  }

  func requestPermission() {
    Task {
      if await AVCaptureDevice.requestAccess(for: .video) {
        cameraPermission = .authorized
        cameraStore = CameraStore()
      } else {
        cameraPermission = .denied
      }
    }
  }

  enum CameraPermission {
    case notDetermined
    case authorized
    case denied
  }

  private(set) var cameraPermission: CameraPermission?
  private(set) var cameraStore: CameraStore?
}

struct ContentView: View {
  @Bindable var store: ContentStore
  init(store: ContentStore) {
    self.store = store
  }

  var body: some View {
    Group {
      if let permission = store.cameraPermission {
        switch permission {
        case .notDetermined:
          CameraPermissionNotDetermined {
            store.requestPermission()
          }
        case .authorized:
          if let cameraStore = store.cameraStore {
            CameraView(store: cameraStore)
          } else {
            Text("Unexpected...")
          }
        case .denied:
          CameraPermissionDenied()
        }
      }
    }
    .onAppear {
      store.checkPermission()
    }
  }
}

#Preview {
  ContentView(store: ContentStore())
}
