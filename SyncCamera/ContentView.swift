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
          Text("Show Camera")
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
