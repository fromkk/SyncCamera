//
//  SyncCameraApp.swift
//  SyncCamera
//
//  Created by Kazuya Ueoka on 2025/06/22.
//

import SwiftUI

@main
struct SyncCameraApp: App {
  let contentStore: ContentStore = .init(permissionStore: .init())

  var body: some Scene {
    WindowGroup {
      ContentView(store: contentStore)
    }
  }
}
