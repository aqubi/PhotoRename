//
//  RenameItem.swift
//  PhotoDateRenamer
//
//  Created by Hideko Ogawa on 2026/07/15.
//

import Foundation

struct RenameItem: Identifiable, Sendable {
  enum DateSource: Sendable {
    case exif
    case fileCreationDate
    case unavailable

    var label: String {
      switch self {
      case .exif:
        return String(
          localized: "dateSource.exif",
          defaultValue: "Capture date"
        )

      case .fileCreationDate:
        return String(
          localized: "dateSource.fileCreationDate",
          defaultValue: "File creation date"
        )

      case .unavailable:
        return String(
          localized: "dateSource.unavailable",
          defaultValue: "No date"
        )
      }
    }
  }

  enum State: Equatable, Sendable {
    case ready
    case skipped(String)
    case alreadyRenamed
    case completed
    case failed(String)

    var label: String {
      switch self {
      case .ready:
        return String(
          localized: "renameState.ready",
          defaultValue: "Ready"
        )

      case .skipped(let reason):
        return reason

      case .alreadyRenamed:
        return String(
          localized: "renameState.skipped.alreadyRenamed",
          defaultValue: "Already renamed"
        )

      case .completed:
        return String(
          localized: "renameState.completed",
          defaultValue: "Done"
        )

      case .failed(let reason):
        let summary = reason.components(separatedBy: .newlines).first ?? reason
        let format = String(
          localized: "renameState.failed.format",
          defaultValue: "Failed: %@"
        )
        return String(format: format, summary)
      }
    }

    var detail: String? {
      switch self {
      case .failed(let reason):
        return reason

      default:
        return nil
      }
    }

    nonisolated static func == (
      lhs: State,
      rhs: State
    ) -> Bool {
      switch (lhs, rhs) {
      case (.ready, .ready),
        (.alreadyRenamed, .alreadyRenamed),
        (.completed, .completed):
        return true

      case (.skipped(let lhsReason), .skipped(let rhsReason)),
        (.failed(let lhsReason), .failed(let rhsReason)):
        return lhsReason == rhsReason

      default:
        return false
      }
    }
  }

  let id: UUID
  let sourceURL: URL
  let captureDate: Date?
  let captureTimeZone: TimeZone?
  let dateSource: DateSource

  var destinationURL: URL?
  var duplicateOfURL: URL?
  var state: State

  nonisolated init(
    id: UUID = UUID(),
    sourceURL: URL,
    captureDate: Date?,
    captureTimeZone: TimeZone? = nil,
    dateSource: DateSource,
    destinationURL: URL? = nil,
    duplicateOfURL: URL? = nil,
    state: State = .ready
  ) {
    self.id = id
    self.sourceURL = sourceURL
    self.captureDate = captureDate
    self.captureTimeZone = captureTimeZone
    self.dateSource = dateSource
    self.destinationURL = destinationURL
    self.duplicateOfURL = duplicateOfURL
    self.state = state
  }

  var originalName: String {
    sourceURL.lastPathComponent
  }

  var renamedName: String {
    destinationURL?.lastPathComponent ?? "—"
  }

  var duplicateOfName: String {
    duplicateOfURL?.lastPathComponent ?? "—"
  }

  var dateSourceSortValue: String {
    dateSource.label
  }

  var stateSortValue: String {
    state.label
  }

  var duplicateSortValue: String {
    duplicateOfURL?.lastPathComponent ?? ""
  }
}
