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
final class ContentStore: PermissionStoreDelegate {
  let permissionStore: PermissionStore
  private(set) var cameraStore: CameraStore?

  init(permissionStore: PermissionStore, cameraStore: CameraStore? = nil) {
    self.permissionStore = permissionStore
    self.cameraStore = cameraStore

    self.permissionStore.delegate = self
  }

  func checkPermission() {
    if permissionStore.cameraPermission == .authorized,
      permissionStore.addLibraryPermission == .authorized
    {
      if cameraStore == nil {
        self.cameraStore = .init()
      }
    } else {
      self.cameraStore = nil
    }
  }

  func permissionUpdated() {
    checkPermission()
  }
}

struct ContentView: View {
  @Bindable var store: ContentStore
  init(store: ContentStore) {
    self.store = store
  }

  var body: some View {
    Group {
      if let cameraStore = store.cameraStore {
        CameraView(store: cameraStore)
      } else {
        PermissionView(store: store.permissionStore)
      }
    }
    .onAppear {
      store.checkPermission()
    }
  }
}

#Preview {
  ContentView(store: ContentStore(permissionStore: PermissionStore()))
}
