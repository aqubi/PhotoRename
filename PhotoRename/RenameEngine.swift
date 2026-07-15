//
//  RenameEngine.swift
//  PhotoDateRenamer
//
//  Created by Hideko Ogawa on 2026/07/15.
//

import CryptoKit
import Foundation

enum RenameEngine {
  enum EngineError: LocalizedError {
    case sourceFolderUnavailable
    case destinationAlreadyExists(String)

    var errorDescription: String? {
      switch self {
      case .sourceFolderUnavailable:
        return String(
          localized: "error.sourceFolderUnavailable",
          defaultValue: "Cannot access the selected folder."
        )

      case .destinationAlreadyExists(let name):
        let format = String(
          localized: "error.destinationAlreadyExists.format",
          defaultValue: "A file with the same name already exists: %@"
        )
        return String(format: format, name)
      }
    }
  }

  struct ScanProgress: Sendable {
    let scannedCount: Int
    let totalCount: Int?
  }

  nonisolated static func scan(
    folderURL: URL,
    filenameFormat: FilenameFormat,
    timeZoneStyle: FilenameTimeZoneStyle,
    extensionStyle: FilenameExtensionStyle,
    includeSubfolders: Bool,
    supportedExtensions: Set<String>,
    useFileCreationDateAsFallback: Bool,
    progressHandler: (@Sendable (ScanProgress) -> Void)? = nil
  ) throws -> [RenameItem] {
    progressHandler?(ScanProgress(scannedCount: 0, totalCount: nil))

    let imageURLs = try imageFileURLs(
      in: folderURL,
      includeSubfolders: includeSubfolders,
      supportedExtensions: supportedExtensions
    )

    progressHandler?(ScanProgress(scannedCount: 0, totalCount: imageURLs.count))

    var items: [RenameItem] = []
    items.reserveCapacity(imageURLs.count)

    for (index, url) in imageURLs.enumerated() {
      try Task.checkCancellation()

      let metadata = PhotoMetadataReader.captureDate(
        for: url,
        useFileCreationDateAsFallback:
          useFileCreationDateAsFallback
      )

      if metadata.date == nil {
        items.append(
          RenameItem(
            sourceURL: url,
            captureDate: nil,
            dateSource: metadata.source,
            state: .skipped(
              String(
                localized: "renameState.skipped.noCaptureDate",
                defaultValue: "No capture date"
              )
            )
          )
        )
      } else {
        items.append(
          RenameItem(
            sourceURL: url,
            captureDate: metadata.date,
            captureTimeZone: metadata.timeZone,
            dateSource: metadata.source
          )
        )
      }

      progressHandler?(ScanProgress(scannedCount: index + 1, totalCount: imageURLs.count))
    }

    try Task.checkCancellation()

    assignDestinationURLs(
      to: &items,
      filenameFormat: filenameFormat,
      timeZoneStyle: timeZoneStyle,
      extensionStyle: extensionStyle
    )

    return items
  }

  nonisolated private static func imageFileURLs(
    in folderURL: URL,
    includeSubfolders: Bool,
    supportedExtensions: Set<String>
  ) throws -> [URL] {
    let fileManager = FileManager.default
    let resourceKeys: [URLResourceKey] = [
      .isRegularFileKey,
      .creationDateKey,
      .contentModificationDateKey,
    ]

    var urls: [URL] = []

    if includeSubfolders {
      guard
        let enumerator = fileManager.enumerator(
          at: folderURL,
          includingPropertiesForKeys: resourceKeys,
          options: [
            .skipsHiddenFiles,
            .skipsPackageDescendants,
          ]
        )
      else {
        throw EngineError.sourceFolderUnavailable
      }

      for case let url as URL in enumerator {
        try Task.checkCancellation()

        if isSupportedImageFile(url, supportedExtensions: supportedExtensions) {
          urls.append(url)
        }
      }
    } else {
      for url in try fileManager.contentsOfDirectory(
        at: folderURL,
        includingPropertiesForKeys: resourceKeys,
        options: [
          .skipsHiddenFiles,
          .skipsPackageDescendants,
        ]
      ) {
        try Task.checkCancellation()

        if isSupportedImageFile(url, supportedExtensions: supportedExtensions) {
          urls.append(url)
        }
      }
    }

    return urls.sorted {
      $0.path.localizedStandardCompare($1.path) == .orderedAscending
    }
  }

  nonisolated private static func isSupportedImageFile(
    _ url: URL,
    supportedExtensions: Set<String>
  ) -> Bool {
    guard supportedExtensions.contains(url.pathExtension.lowercased()) else {
      return false
    }

    let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
    return values?.isRegularFile == true
  }

  nonisolated private static func contentHash(for url: URL) throws -> String {
    let fileHandle = try FileHandle(forReadingFrom: url)
    defer {
      try? fileHandle.close()
    }

    var hasher = SHA256()
    while true {
      try Task.checkCancellation()

      let data = fileHandle.readData(ofLength: 1024 * 1024)
      if data.isEmpty {
        break
      }

      hasher.update(data: data)
    }

    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
  }

  nonisolated static func assignDestinationURLs(
    to items: [RenameItem],
    filenameFormat: FilenameFormat,
    timeZoneStyle: FilenameTimeZoneStyle,
    extensionStyle: FilenameExtensionStyle
  ) -> [RenameItem] {
    var results = items
    assignDestinationURLs(
      to: &results,
      filenameFormat: filenameFormat,
      timeZoneStyle: timeZoneStyle,
      extensionStyle: extensionStyle
    )
    return results
  }

  nonisolated private static func assignDestinationURLs(
    to items: inout [RenameItem],
    filenameFormat: FilenameFormat,
    timeZoneStyle: FilenameTimeZoneStyle,
    extensionStyle: FilenameExtensionStyle
  ) {
    struct AssignmentGroup {
      let datePart: String
      let formattedExtension: String
      var indices: [Array<RenameItem>.Index]
    }

    var groups: [String: AssignmentGroup] = [:]

    for index in items.indices {
      guard items[index].state == .ready,
        let captureDate = items[index].captureDate
      else {
        continue
      }

      let timeZone = items[index].captureTimeZone ?? .current
      let datePart = formattedDatePart(
        captureDate,
        filenameFormat: filenameFormat,
        timeZoneStyle: timeZoneStyle,
        timeZone: timeZone
      )

      let formattedExtension = extensionStyle.formattedExtension(
        for: items[index].sourceURL.pathExtension
      )
      let groupKey = "\(datePart).\(formattedExtension.lowercased())"

      if groups[groupKey] == nil {
        groups[groupKey] = AssignmentGroup(
          datePart: datePart,
          formattedExtension: formattedExtension,
          indices: []
        )
      }

      groups[groupKey]?.indices.append(index)
    }

    for group in groups.values {
      let candidateNames = (0..<group.indices.count).map { count in
        let suffix = count == 0 ? "" : String(format: "_%02d", count)
        return "\(group.datePart)\(suffix).\(group.formattedExtension)"
      }
      var unusedCandidateNames = Set(candidateNames)

      for index in group.indices {
        let currentName = items[index].sourceURL.lastPathComponent
        guard unusedCandidateNames.contains(currentName) else {
          continue
        }

        items[index].destinationURL = items[index].sourceURL
        items[index].state = .alreadyRenamed
        unusedCandidateNames.remove(currentName)
      }

      for index in group.indices where items[index].state == .ready {
        guard let newName = candidateNames.first(where: { unusedCandidateNames.contains($0) }) else {
          continue
        }

        items[index].destinationURL = items[index].sourceURL
          .deletingLastPathComponent()
          .appendingPathComponent(newName)
        unusedCandidateNames.remove(newName)
      }
    }
  }

  nonisolated private static func formattedDatePart(
    _ date: Date,
    filenameFormat: FilenameFormat,
    timeZoneStyle: FilenameTimeZoneStyle,
    timeZone: TimeZone
  ) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)

    switch timeZoneStyle {
    case .localTime:
      formatter.timeZone = timeZone
      formatter.dateFormat = filenameFormat.dateFormat
      return formatter.string(from: date)

    case .localTimeWithOffset:
      formatter.timeZone = timeZone
      formatter.dateFormat = "\(filenameFormat.dateFormat)_Z"
      return formatter.string(from: date)

    case .utc:
      formatter.timeZone = TimeZone(secondsFromGMT: 0)
      formatter.dateFormat = "\(filenameFormat.dateFormat)'Z'"
      return formatter.string(from: date)
    }
  }

  nonisolated static func markDuplicates(
    in items: [RenameItem],
    progressHandler: (@Sendable (ScanProgress) -> Void)? = nil
  ) throws -> [RenameItem] {
    var results = items
    var firstURLByContentHash: [String: URL] = [:]

    progressHandler?(ScanProgress(scannedCount: 0, totalCount: results.count))

    for index in results.indices {
      try Task.checkCancellation()

      if results[index].duplicateOfURL != nil {
        results[index].duplicateOfURL = nil
        if results[index].captureDate != nil {
          results[index].state = .ready
        }
      }

      let fileURL = currentFileURL(for: results[index])
      let contentHash = try contentHash(for: fileURL)
      if let firstURL = firstURLByContentHash[contentHash] {
        results[index].duplicateOfURL = firstURL
      } else {
        firstURLByContentHash[contentHash] = fileURL
      }

      progressHandler?(ScanProgress(scannedCount: index + 1, totalCount: results.count))
    }

    return results
  }

  nonisolated private static func currentFileURL(for item: RenameItem) -> URL {
    if item.state == .completed,
      let destinationURL = item.destinationURL
    {
      return destinationURL
    }

    return item.sourceURL
  }

  private enum RenameOperation {
    case moveToTemporaryName
    case moveToFinalName

    nonisolated var title: String {
      switch self {
      case .moveToTemporaryName:
        return String(
          localized: "renameFailure.operation.moveToTemporaryName",
          defaultValue: "Move original file to a temporary name"
        )

      case .moveToFinalName:
        return String(
          localized: "renameFailure.operation.moveToFinalName",
          defaultValue: "Move temporary file to the final name"
        )
      }
    }
  }

  nonisolated private static func fileResourceIdentifier(for url: URL) -> NSObject? {
    guard let identifier = try? url.resourceValues(
      forKeys: [.fileResourceIdentifierKey]
    ).fileResourceIdentifier as? NSObject else {
      return nil
    }

    return identifier
  }

  nonisolated private static func renameFailureDetails(
    operation: RenameOperation,
    sourceURL: URL,
    destinationURL: URL,
    originalURL: URL? = nil,
    error: Error
  ) -> String {
    let nsError = error as NSError
    var lines = [
      error.localizedDescription,
      "",
      "\(String(localized: "renameFailure.operation", defaultValue: "Operation")): \(operation.title)",
      "\(String(localized: "renameFailure.source", defaultValue: "Source")): \(sourceURL.path)",
      "\(String(localized: "renameFailure.destination", defaultValue: "Destination")): \(destinationURL.path)",
    ]

    if let originalURL {
      lines.append("\(String(localized: "renameFailure.original", defaultValue: "Original")): \(originalURL.path)")
    }

    lines.append("\(String(localized: "renameFailure.errorDomain", defaultValue: "Error Domain")): \(nsError.domain)")
    lines.append("\(String(localized: "renameFailure.errorCode", defaultValue: "Error Code")): \(nsError.code)")

    if let reason = nsError.localizedFailureReason, !reason.isEmpty {
      lines.append("\(String(localized: "renameFailure.reason", defaultValue: "Reason")): \(reason)")
    }

    if let suggestion = nsError.localizedRecoverySuggestion, !suggestion.isEmpty {
      lines.append("\(String(localized: "renameFailure.recoverySuggestion", defaultValue: "Suggestion")): \(suggestion)")
    }

    return lines.joined(separator: "\n")
  }

  nonisolated static func execute(
    items: [RenameItem]
  ) -> [RenameItem] {
    let fileManager = FileManager.default
    var results = items

    let readyIndices = results.indices.filter {
      results[$0].state == .ready
        && results[$0].destinationURL != nil
    }

    let sourceFileIdentifiers = Set(
      readyIndices.compactMap {
        fileResourceIdentifier(for: results[$0].sourceURL)
      }
    )

    for index in readyIndices {
      guard let destinationURL = results[index].destinationURL,
        fileManager.fileExists(atPath: destinationURL.path)
      else {
        continue
      }

      if let destinationIdentifier = fileResourceIdentifier(for: destinationURL),
        sourceFileIdentifiers.contains(destinationIdentifier)
      {
        continue
      }

      results[index].state = .failed(
        String(
          localized: "renameState.failed.duplicateFilename",
          defaultValue: "A file with the same name already exists"
        )
      )
    }

    let executableIndices = readyIndices.filter {
      results[$0].state == .ready
    }

    /*
     元URL → 仮URL
     */
    var temporaryURLs: [UUID: URL] = [:]

    for index in executableIndices {
      let sourceURL = results[index].sourceURL

      let temporaryName =
        ".PhotoDateRenamer-\(UUID().uuidString).tmp"

      let temporaryURL =
        sourceURL
        .deletingLastPathComponent()
        .appendingPathComponent(temporaryName)

      do {
        try fileManager.moveItem(
          at: sourceURL,
          to: temporaryURL
        )

        temporaryURLs[results[index].id] =
          temporaryURL
      } catch {
        results[index].state = .failed(
          renameFailureDetails(
            operation: .moveToTemporaryName,
            sourceURL: sourceURL,
            destinationURL: temporaryURL,
            error: error
          )
        )
      }
    }

    /*
     仮URL → 最終URL
     */
    for index in executableIndices {
      guard results[index].state == .ready,
        let temporaryURL =
          temporaryURLs[results[index].id],
        let destinationURL =
          results[index].destinationURL
      else {
        continue
      }

      do {
        try fileManager.moveItem(
          at: temporaryURL,
          to: destinationURL
        )

        results[index].state = .completed
      } catch {
        /*
         最終名への変更に失敗したら、可能な限り
         元の名前へ戻す。
         */
        try? fileManager.moveItem(
          at: temporaryURL,
          to: results[index].sourceURL
        )

        results[index].state = .failed(
          renameFailureDetails(
            operation: .moveToFinalName,
            sourceURL: temporaryURL,
            destinationURL: destinationURL,
            originalURL: results[index].sourceURL,
            error: error
          )
        )
      }
    }

    return results
  }
}
