//
//  Data+Spatial.swift
//  SpatialPhoto
//
//  Created by Kazuya Ueoka on 2025/05/10.
//

import CoreImage
import Foundation
import UniformTypeIdentifiers

extension Data {
  var isSpatialPhoto: Bool {
    // Image I/O でコンテナを開く
    guard let src = CGImageSourceCreateWithData(self as CFData, nil) else {
      return false
    }

    // HEIC/HEIF であることを確認
    guard
      let utiString = CGImageSourceGetType(src) as? String,
      let uti = UTType(utiString),
      UTType.heic.conforms(to: uti)
    else {
      return false
    }

    // マルチイメージ HEIC で、「少なくとも左右 2 枚」を持っていること
    guard
      CGImageSourceGetCount(src) >= 2,
      let properties = CGImageSourceCopyProperties(src, nil)
        as? [CFString: Any],
      let groups = properties[kCGImagePropertyGroups] as? [[CFString: Any]]
    else {
      return false
    }

    // GroupTypeStereoPairであること
    return groups.contains { dict in
      (dict[kCGImagePropertyGroupType] as? String)
        == (kCGImagePropertyGroupTypeStereoPair as String)
    }
  }

  var splitImages: (CGImage, CGImage)? {
    guard let src = CGImageSourceCreateWithData(self as CFData, nil) else {
      return nil
    }

    guard
      let properties = CGImageSourceCopyProperties(src, nil)
        as? [CFString: Any],
      let groups = properties[kCGImagePropertyGroups] as? [[CFString: Any]],
      let stereoPairGroup = groups.first(where: {
        $0[kCGImagePropertyGroupType] as? String
          == (kCGImagePropertyGroupTypeStereoPair as String)
      }),
      let leftIndex = stereoPairGroup[kCGImagePropertyGroupImageIndexLeft]
        as? Int,
      let rightIndex = stereoPairGroup[kCGImagePropertyGroupImageIndexRight]
        as? Int,
      let left = CGImageSourceCreateImageAtIndex(src, leftIndex, nil),
      let right = CGImageSourceCreateImageAtIndex(src, rightIndex, nil)
    else {
      return nil
    }
    return (left, right)
  }

  var orientation: CGImagePropertyOrientation? {
    guard
      let src = CGImageSourceCreateWithData(self as CFData, nil),
      let property = CGImageSourceCopyProperties(src, nil) as? [CFString: Any],
      let rawValue = property[kCGImagePropertyOrientation] as? UInt32
    else {
      return nil
    }
    return CGImagePropertyOrientation(rawValue: rawValue)
  }
}

extension URL {
  var isSpatialPhoto: Bool {
    guard let data = try? Data(contentsOf: self) else {
      return false
    }
    return data.isSpatialPhoto
  }
}
