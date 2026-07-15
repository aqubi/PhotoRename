//
//  PhotoRenameViewModel.swift
//  PhotoDateRenamer
//
//  Created by Hideko Ogawa on 2026/07/15.
//

import Foundation
import Observation

@MainActor
@Observable
final class PhotoRenameViewModel {
  var selectedFolderURL: URL?
  var items: [RenameItem] = []

  var isLoading = false
  var isCheckingDuplicates = false
  var isRenaming = false
  var scannedFileCount = 0
  var totalScanFileCount: Int?

  private var previewTask: Task<Void, Never>?
  private var duplicateCheckTask: Task<Void, Never>?
  fileprivate var previewRequestID = UUID()

  var useFileCreationDateAsFallback = SettingsStore.useFileCreationDateAsFallback {
    didSet {
      SettingsStore.useFileCreationDateAsFallback = useFileCreationDateAsFallback
    }
  }

  var includeSubfolders = SettingsStore.includeSubfolders {
    didSet {
      SettingsStore.includeSubfolders = includeSubfolders
    }
  }

  var imageFileSelection: ImageFileSelection = SettingsStore.imageFileSelection {
    didSet {
      SettingsStore.imageFileSelection = imageFileSelection
    }
  }

  var errorMessage: String?
  var completionMessage: String?

  var filenameFormat: FilenameFormat = SettingsStore.filenameFormat {
    didSet {
      SettingsStore.filenameFormat = filenameFormat
    }
  }

  var timeZoneStyle: FilenameTimeZoneStyle = SettingsStore.timeZoneStyle {
    didSet {
      SettingsStore.timeZoneStyle = timeZoneStyle
    }
  }

  var extensionStyle: FilenameExtensionStyle = SettingsStore.extensionStyle {
    didSet {
      SettingsStore.extensionStyle = extensionStyle
    }
  }

  var folderName: String {
    selectedFolderURL?.lastPathComponent
      ?? String(
        localized: "folder.notSelected",
        defaultValue: "No folder selected"
      )
  }

  var readyCount: Int {
    items.filter { $0.state == .ready }.count
  }

  var completedCount: Int {
    items.filter { $0.state == .completed }.count
  }

  var scanProgressFraction: Double? {
    guard let totalScanFileCount, totalScanFileCount > 0 else {
      return nil
    }

    return Double(scannedFileCount) / Double(totalScanFileCount)
  }

  var scanProgressText: String {
    if let totalScanFileCount {
      if isCheckingDuplicates {
        let format = String(
          localized: "scanProgress.checkingDuplicates.format",
          defaultValue: "Checking duplicates: %lld of %lld"
        )
        return String(format: format, scannedFileCount, totalScanFileCount)
      }

      let format = String(
        localized: "scanProgress.reading.format",
        defaultValue: "Reading capture dates: %lld of %lld"
      )
      return String(format: format, scannedFileCount, totalScanFileCount)
    }

    return String(
      localized: "scanProgress.findingFiles",
      defaultValue: "Finding image files..."
    )
  }

  var hasDuplicateItems: Bool {
    items.contains { $0.duplicateOfURL != nil }
  }

  func selectFolder(_ url: URL) {
    selectedFolderURL = url
    loadPreview()
  }

  func loadPreview(preservesCompletionMessage: Bool = false) {
    previewTask?.cancel()
    duplicateCheckTask?.cancel()
    duplicateCheckTask = nil
    isCheckingDuplicates = false

    guard let folderURL = selectedFolderURL else {
      items = []
      isLoading = false
      resetScanProgress()
      return
    }

    isLoading = true
    isCheckingDuplicates = false
    scannedFileCount = 0
    totalScanFileCount = nil
    errorMessage = nil
    if !preservesCompletionMessage {
      completionMessage = nil
    }

    let requestID = UUID()
    previewRequestID = requestID

    let useFallback =
      useFileCreationDateAsFallback

    let shouldIncludeSubfolders =
      includeSubfolders

    let selectedImageFileSelection =
      imageFileSelection

    let selectedFormat =
      filenameFormat

    let selectedTimeZoneStyle =
      timeZoneStyle

    let selectedExtensionStyle =
      extensionStyle

    previewTask = Task { [weak self] in
      guard let self else {
        return
      }

      let progressUpdater = ScanProgressUpdater(
        viewModel: self,
        requestID: requestID
      )

      let accessed =
        folderURL.startAccessingSecurityScopedResource()

      defer {
        if accessed {
          folderURL.stopAccessingSecurityScopedResource()
        }
      }

      do {
        let loadedItems = try await Task.detached(
          priority: .userInitiated
        ) {
          try Task.checkCancellation()

          let items = try RenameEngine.scan(
            folderURL: folderURL,
            filenameFormat: selectedFormat,
            timeZoneStyle: selectedTimeZoneStyle,
            extensionStyle: selectedExtensionStyle,
            includeSubfolders: shouldIncludeSubfolders,
            supportedExtensions:
              selectedImageFileSelection.extensions,
            useFileCreationDateAsFallback:
              useFallback
          ) { progress in
            progressUpdater.update(progress)
          }

          try Task.checkCancellation()
          return items
        }.value

        guard !Task.isCancelled else {
          return
        }

        guard previewRequestID == requestID else {
          return
        }

        items = loadedItems
        isLoading = false
        previewTask = nil
        resetScanProgress()
      } catch is CancellationError {
        guard previewRequestID == requestID else {
          return
        }

        isLoading = false
        previewTask = nil
        resetScanProgress()
      } catch {
        guard previewRequestID == requestID else {
          return
        }

        items = []
        errorMessage = error.localizedDescription
        isLoading = false
        previewTask = nil
        resetScanProgress()
      }
    }
  }

  func cancelPreviewLoading() {
    previewTask?.cancel()
    duplicateCheckTask?.cancel()
    previewTask = nil
    duplicateCheckTask = nil
    previewRequestID = UUID()
    isLoading = false
    isCheckingDuplicates = false
    resetScanProgress()
  }

  func isManuallySkipped(itemID: RenameItem.ID) -> Bool {
    guard let item = items.first(where: { $0.id == itemID }),
      case .skipped(let reason) = item.state
    else {
      return false
    }

    return reason == manualSkipReason
  }

  func markItemsAsReady(_ itemIDs: Set<RenameItem.ID>) {
    for index in items.indices where itemIDs.contains(items[index].id) {
      guard isManuallySkipped(itemID: items[index].id),
        items[index].captureDate != nil
      else {
        continue
      }

      items[index].state = .ready
    }

    items = RenameEngine.assignDestinationURLs(
      to: items,
      filenameFormat: filenameFormat,
      timeZoneStyle: timeZoneStyle,
      extensionStyle: extensionStyle
    )
  }

  private var manualSkipReason: String {
    String(
      localized: "renameState.skipped.manual",
      defaultValue: "No change"
    )
  }

  func markItemsAsSkipped(_ itemIDs: Set<RenameItem.ID>) {
    let reason = manualSkipReason

    for index in items.indices where itemIDs.contains(items[index].id) {
      guard items[index].state == .ready else {
        continue
      }

      items[index].state = .skipped(reason)
      items[index].destinationURL = nil
    }
  }

  func deleteItems(_ itemIDs: Set<RenameItem.ID>) {
    guard !itemIDs.isEmpty else {
      return
    }

    let accessURL = selectedFolderURL
    let accessed = accessURL?.startAccessingSecurityScopedResource() ?? false
    defer {
      if accessed {
        accessURL?.stopAccessingSecurityScopedResource()
      }
    }

    var deletedIDs = Set<RenameItem.ID>()

    for item in items where itemIDs.contains(item.id) {
      let url = currentFileURL(for: item)

      do {
        var resultingURL: NSURL?
        try FileManager.default.trashItem(
          at: url,
          resultingItemURL: &resultingURL
        )
        deletedIDs.insert(item.id)
      } catch {
        errorMessage = error.localizedDescription
      }
    }

    if !deletedIDs.isEmpty {
      items.removeAll { deletedIDs.contains($0.id) }
    }
  }

  private func currentFileURL(for item: RenameItem) -> URL {
    if item.state == .completed,
      let destinationURL = item.destinationURL
    {
      return destinationURL
    }

    return item.sourceURL
  }

  func checkDuplicates() {
    guard let folderURL = selectedFolderURL,
      !items.isEmpty
    else {
      return
    }

    previewTask?.cancel()
    duplicateCheckTask?.cancel()

    isLoading = true
    isCheckingDuplicates = true
    scannedFileCount = 0
    totalScanFileCount = items.count
    errorMessage = nil
    completionMessage = nil

    let requestID = UUID()
    previewRequestID = requestID
    let currentItems = items

    duplicateCheckTask = Task { [weak self] in
      guard let self else {
        return
      }

      let progressUpdater = ScanProgressUpdater(
        viewModel: self,
        requestID: requestID
      )

      let accessed = folderURL.startAccessingSecurityScopedResource()
      defer {
        if accessed {
          folderURL.stopAccessingSecurityScopedResource()
        }
      }

      do {
        let checkedItems = try await Task.detached(priority: .userInitiated) {
          try RenameEngine.markDuplicates(in: currentItems) { progress in
            progressUpdater.update(progress)
          }
        }.value

        guard previewRequestID == requestID else {
          return
        }

        items = checkedItems
        let duplicateCount = checkedItems.filter { $0.duplicateOfURL != nil }.count
        if duplicateCount == 0 {
          completionMessage = String(
            localized: "duplicateCheck.noDuplicatesFound",
            defaultValue: "No duplicate files were found."
          )
        } else {
          let format = String(
            localized: "duplicateCheck.duplicatesFound.format",
            defaultValue: "%lld duplicate files were found."
          )
          completionMessage = String(format: format, duplicateCount)
        }
        isLoading = false
        isCheckingDuplicates = false
        duplicateCheckTask = nil
        resetScanProgress()
      } catch is CancellationError {
        guard previewRequestID == requestID else {
          return
        }

        isLoading = false
        isCheckingDuplicates = false
        duplicateCheckTask = nil
        resetScanProgress()
      } catch {
        guard previewRequestID == requestID else {
          return
        }

        errorMessage = error.localizedDescription
        isLoading = false
        isCheckingDuplicates = false
        duplicateCheckTask = nil
        resetScanProgress()
      }
    }
  }

  private func resetScanProgress() {
    scannedFileCount = 0
    totalScanFileCount = nil
  }

  func rename() {
    guard let folderURL = selectedFolderURL else {
      return
    }

    previewTask?.cancel()
    duplicateCheckTask?.cancel()
    previewTask = nil
    duplicateCheckTask = nil
    previewRequestID = UUID()

    let currentItems = items

    isRenaming = true
    errorMessage = nil
    completionMessage = nil

    Task {
      let accessed =
        folderURL.startAccessingSecurityScopedResource()

      defer {
        if accessed {
          folderURL.stopAccessingSecurityScopedResource()
        }
      }

      let renamedItems = await Task.detached(
        priority: .userInitiated
      ) {
        RenameEngine.execute(items: currentItems)
      }.value

      items = renamedItems
      isRenaming = false

      let successCount = renamedItems.filter {
        $0.state == .completed
      }.count

      let failedCount = renamedItems.filter {
        if case .failed = $0.state {
          return true
        }

        return false
      }.count

      if failedCount == 0 {
        let format = String(
          localized: "renameCompletion.success.format",
          defaultValue: "Renamed %lld files."
        )
        completionMessage = String(format: format, successCount)
        loadPreview(preservesCompletionMessage: true)
      } else {
        let format = String(
          localized: "renameCompletion.partialFailure.format",
          defaultValue: "Renamed %lld files. %lld failed."
        )
        completionMessage = String(
          format: format,
          successCount,
          failedCount
        )
      }
    }
  }
}

private enum SettingsStore {
  private enum Key {
    static let useFileCreationDateAsFallback = "useFileCreationDateAsFallback"
    static let includeSubfolders = "includeSubfolders"
    static let imageFileSelection = "imageFileSelection"
    static let filenameFormat = "filenameFormat"
    static let timeZoneStyle = "timeZoneStyle"
    static let extensionStyle = "extensionStyle"
  }

  private static let defaults = UserDefaults.standard

  static var useFileCreationDateAsFallback: Bool {
    get {
      defaults.object(forKey: Key.useFileCreationDateAsFallback) as? Bool ?? true
    }
    set {
      defaults.set(newValue, forKey: Key.useFileCreationDateAsFallback)
    }
  }

  static var includeSubfolders: Bool {
    get {
      defaults.object(forKey: Key.includeSubfolders) as? Bool ?? false
    }
    set {
      defaults.set(newValue, forKey: Key.includeSubfolders)
    }
  }

  static var imageFileSelection: ImageFileSelection {
    get {
      guard let rawValue = defaults.string(forKey: Key.imageFileSelection) else {
        return .photos
      }

      return ImageFileSelection(rawValue: rawValue) ?? .photos
    }
    set {
      defaults.set(newValue.rawValue, forKey: Key.imageFileSelection)
    }
  }

  static var filenameFormat: FilenameFormat {
    get {
      guard let rawValue = defaults.string(forKey: Key.filenameFormat) else {
        return .readableDateAndTime
      }

      return FilenameFormat(rawValue: rawValue) ?? .readableDateAndTime
    }
    set {
      defaults.set(newValue.rawValue, forKey: Key.filenameFormat)
    }
  }

  static var timeZoneStyle: FilenameTimeZoneStyle {
    get {
      guard let rawValue = defaults.string(forKey: Key.timeZoneStyle) else {
        return .localTime
      }

      return FilenameTimeZoneStyle(rawValue: rawValue) ?? .localTime
    }
    set {
      defaults.set(newValue.rawValue, forKey: Key.timeZoneStyle)
    }
  }

  static var extensionStyle: FilenameExtensionStyle {
    get {
      guard let rawValue = defaults.string(forKey: Key.extensionStyle) else {
        return .keepOriginal
      }

      return FilenameExtensionStyle(rawValue: rawValue) ?? .keepOriginal
    }
    set {
      defaults.set(newValue.rawValue, forKey: Key.extensionStyle)
    }
  }
}

private final class ScanProgressUpdater: @unchecked Sendable {
  nonisolated(unsafe) weak var viewModel: PhotoRenameViewModel?
  let requestID: UUID

  init(viewModel: PhotoRenameViewModel, requestID: UUID) {
    self.viewModel = viewModel
    self.requestID = requestID
  }

  nonisolated func update(_ progress: RenameEngine.ScanProgress) {
    Task { @MainActor [weak viewModel] in
      guard let viewModel,
        viewModel.previewRequestID == requestID,
        viewModel.isLoading
      else {
        return
      }

      viewModel.scannedFileCount = progress.scannedCount
      viewModel.totalScanFileCount = progress.totalCount
    }
  }
}
