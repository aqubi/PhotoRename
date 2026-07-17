//
//  FilenameFormat.swift
//  PhotoDateRenamer
//
//  Created by Hideko Ogawa on 2026/07/15.
//

import Foundation

enum FilenameFormat: String, CaseIterable, Identifiable, Sendable {
  case compact
  case readableDate
  case readableDateAndTime

  var id: Self {
    self
  }

  var title: String {
    exampleTitle(for: Date())
  }

  func exampleTitle(for date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = .current
    formatter.dateFormat = dateFormat

    return formatter.string(from: date)
  }

  nonisolated var dateFormat: String {
    switch self {
    case .compact:
      return "yyyyMMdd_HHmmss"

    case .readableDate:
      return "yyyy-MM-dd_HHmmss"

    case .readableDateAndTime:
      return "yyyy-MM-dd_HH-mm-ss"
    }
  }
}

enum FilenameExtensionStyle: String, CaseIterable, Identifiable, Sendable {
  case keepOriginal
  case lowercase
  case uppercase

  var id: Self {
    self
  }

  var title: String {
    switch self {
    case .keepOriginal:
      return String(
        localized: "filenameExtensionStyle.keepOriginal",
        defaultValue: "Keep Original"
      )

    case .lowercase:
      return String(
        localized: "filenameExtensionStyle.lowercase",
        defaultValue: "Lowercase"
      )

    case .uppercase:
      return String(
        localized: "filenameExtensionStyle.uppercase",
        defaultValue: "Uppercase"
      )
    }
  }

  var exampleExtension: String {
    formattedExtension(for: "HEIC")
  }

  nonisolated func formattedExtension(for originalExtension: String) -> String {
    switch self {
    case .keepOriginal:
      return originalExtension

    case .lowercase:
      return originalExtension.lowercased()

    case .uppercase:
      return originalExtension.uppercased()
    }
  }
}

enum FilenameTimeZoneStyle: String, CaseIterable, Identifiable, Sendable {
  case localTime
  case localTimeWithOffset
  case utc

  var id: Self {
    self
  }

  var title: String {
    switch self {
    case .localTime:
      return String(
        localized: "filenameTimeZoneStyle.localTime",
        defaultValue: "Capture location time"
      )

    case .localTimeWithOffset:
      return String(
        localized: "filenameTimeZoneStyle.localTimeWithOffset",
        defaultValue: "Capture location time with UTC offset"
      )

    case .utc:
      return String(
        localized: "filenameTimeZoneStyle.utc",
        defaultValue: "Convert to UTC"
      )
    }
  }

  func exampleDatePart(
    for filenameFormat: FilenameFormat
  ) -> String {
    switch self {
    case .localTime:
      return filenameFormat.title

    case .localTimeWithOffset:
      return "\(filenameFormat.title)_-1000"

    case .utc:
      switch filenameFormat {
      case .compact:
        return "20260716_002356Z"

      case .readableDate:
        return "2026-07-16_002356Z"

      case .readableDateAndTime:
        return "2026-07-16_00-23-56Z"
      }
    }
  }
}

enum ImageFileSelection: String, CaseIterable, Identifiable, Sendable {
  case photos
  case photosAndCommonImages
  case allSupportedImages

  var id: Self {
    self
  }

  var title: String {
    switch self {
    case .photos:
      return String(
        localized: "imageFileSelection.photos",
        defaultValue: "Photos only (HEIC, HEIF, JPEG)"
      )

    case .photosAndCommonImages:
      return String(
        localized: "imageFileSelection.photosAndCommonImages",
        defaultValue: "Photos + PNG/TIFF"
      )

    case .allSupportedImages:
      return String(
        localized: "imageFileSelection.allSupportedImages",
        defaultValue: "All supported images"
      )
    }
  }

  nonisolated var extensions: Set<String> {
    switch self {
    case .photos:
      return [
        "heic",
        "heif",
        "jpg",
        "jpeg",
      ]

    case .photosAndCommonImages:
      return [
        "heic",
        "heif",
        "jpg",
        "jpeg",
        "png",
        "tif",
        "tiff",
      ]

    case .allSupportedImages:
      return [
        "heic",
        "heif",
        "jpg",
        "jpeg",
        "png",
        "tif",
        "tiff",
        "gif",
        "webp",
      ]
    }
  }
}
