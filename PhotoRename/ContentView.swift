//
//  ContentView.swift
//  PhotoDateRenamer
//
//  Created by Hideko Ogawa on 2026/07/15.
//

import Quartz
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var viewModel = PhotoRenameViewModel()
    @State private var isFolderImporterPresented = false
    @State private var isConfirmationPresented = false
    @State private var isSettingsPresented = false
    @State private var selectedPreviewItemID: RenameItem.ID?
    @State private var pendingDeleteItemIDs = Set<RenameItem.ID>()
    @State private var isDeleteConfirmationPresented = false
    @State private var errorDetailsMessage: String?
    @State private var sortOrder = [KeyPathComparator(\RenameItem.originalName)]
    @State private var quickLookPresenter: QuickLookPreviewPresenter?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header

                Divider()

                if viewModel.isLoading {
                    loadingView
                } else if viewModel.items.isEmpty {
                    emptyView
                } else {
                    previewTable
                }

                Divider()

                footer
            }
            .navigationTitle("PhotoRename")
            .toolbar {
                ToolbarItemGroup {
                    Button {
                        isFolderImporterPresented = true
                    } label: {
                        Label("Select Folder", systemImage: "folder")
                    }
                    .keyboardShortcut("o")

                    Button {
                        viewModel.loadPreview()
                    } label: {
                        Label("Reload", systemImage: "arrow.clockwise")
                    }
                    .keyboardShortcut("r")
                    .disabled(viewModel.selectedFolderURL == nil || viewModel.isLoading || viewModel.isRenaming)

                    Button {
                        viewModel.checkDuplicates()
                    } label: {
                        Label("Find Duplicates", systemImage: "exclamationmark.magnifyingglass")
                    }
                    .disabled(viewModel.items.isEmpty || viewModel.isLoading || viewModel.isRenaming)

                    Button {
                        isSettingsPresented = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .keyboardShortcut(",", modifiers: .command)
                    .disabled(viewModel.isLoading || viewModel.isRenaming)
                }
            }
        }
        .fileImporter(isPresented: $isFolderImporterPresented, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let folderURL = urls.first else {
                    return
                }

                viewModel.selectFolder(folderURL)

            case .failure(let error):
                viewModel.errorMessage = error.localizedDescription
            }
        }
        .sheet(isPresented: $isSettingsPresented) {
            SettingsView(viewModel: viewModel)
        }
        .alert("Rename files?", isPresented: $isConfirmationPresented) {
            Button("Cancel", role: .cancel) {}

            Button("Rename") {
                viewModel.rename()
            }
        } message: {
            Text(renameConfirmationMessage)
        }
        .alert(
            "Error",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { newValue in
                    if !newValue {
                        viewModel.errorMessage = nil
                    }
                }
            )
        ) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .alert(
            "Complete",
            isPresented: Binding(
                get: { viewModel.completionMessage != nil },
                set: { newValue in
                    if !newValue {
                        viewModel.completionMessage = nil
                    }
                }
            )
        ) {
            Button("OK") {
                viewModel.completionMessage = nil
            }
        } message: {
            Text(viewModel.completionMessage ?? "")
        }
        .alert(
            "Error Details",
            isPresented: Binding(
                get: { errorDetailsMessage != nil },
                set: { newValue in
                    if !newValue {
                        errorDetailsMessage = nil
                    }
                }
            )
        ) {
            Button("OK") {
                errorDetailsMessage = nil
            }
        } message: {
            Text(errorDetailsMessage ?? "")
        }
        .alert(deleteConfirmationTitle, isPresented: $isDeleteConfirmationPresented) {
            Button("Cancel", role: .cancel) {
                pendingDeleteItemIDs = []
            }

            Button("Move to Trash", role: .destructive) {
                viewModel.deleteItems(pendingDeleteItemIDs)
                pendingDeleteItemIDs = []
            }
        } message: {
            Text(deleteConfirmationMessage)
        }
        .onChange(of: itemIDs) { _, newItemIDs in
            pruneTransientSelection(availableItemIDs: Set(newItemIDs))
        }

    }

    private var header: some View {
        Button {
            isFolderImporterPresented = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "folder")

                Text(viewModel.folderName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)

                Spacer()
            }
        }
        .buttonStyle(.plain)
        .font(viewModel.selectedFolderURL == nil ? .body : .title3)
        .foregroundStyle(viewModel.selectedFolderURL == nil ? .tertiary : .secondary)
        .help(selectedFolderHelp)
        .padding()
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            if let fraction = viewModel.scanProgressFraction {
                ProgressView(value: fraction)
                    .frame(width: 260)
            } else {
                ProgressView()
            }

            Text(viewModel.scanProgressText)
                .foregroundStyle(.secondary)

            Button("Cancel") {
                viewModel.cancelPreviewLoading()
            }
            .keyboardShortcut(.cancelAction)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        ContentUnavailableView {
            Label(emptyViewTitle, systemImage: "photo.on.rectangle.angled")
        } description: {
            Text(emptyViewDescription)
        } actions: {
            Button("Select Folder...") {
                isFolderImporterPresented = true
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyViewTitle: String {
        if viewModel.selectedFolderURL == nil {
            return String(localized: "Select a Photo Folder", defaultValue: "Select a Photo Folder")
        }

        return String(localized: "emptyFolder.title", defaultValue: "No Image Files Found")
    }

    private var emptyViewDescription: String {
        if viewModel.selectedFolderURL == nil {
            return String(
                localized: "Choose a folder containing supported image files.",
                defaultValue: "Choose a folder containing supported image files."
            )
        }

        return String(
            localized: "emptyFolder.description",
            defaultValue: "This folder does not contain supported image files."
        )
    }

    private var previewTable: some View {
        Table(sortedItems, selection: $selectedPreviewItemID, sortOrder: $sortOrder) {
            TableColumn("Current Filename", value: \.originalName) { item in
                Text(item.originalName)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .width(min: 180, ideal: 240)

            TableColumn("New Filename", value: \.renamedName) { item in
                Text(item.renamedName)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .width(min: 220, ideal: 280)

            TableColumn("Date Source", value: \.dateSourceSortValue) { item in
                Text(item.dateSource.label)
            }
            .width(min: 100, ideal: 120)

            TableColumn("Status", value: \.stateSortValue) { item in
                StatusView(state: item.state)
            }
            .width(min: 130, ideal: 160)

            if viewModel.hasDuplicateItems {
                TableColumn("Duplicate", value: \.duplicateSortValue) { item in
                    if let duplicateOfURL = item.duplicateOfURL {
                        Label {
                            Text(duplicateOfURL.lastPathComponent)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        } icon: {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(.red)
                        }
                    } else {
                        Text("")
                    }
                }
                .width(min: 160, ideal: 220)
            }
        }
        .contextMenu(forSelectionType: RenameItem.ID.self) { itemIDs in
            if let itemID = itemIDs.first {
                Button("Quick Look") {
                    selectedPreviewItemID = itemID
                    _ = openQuickLook(for: itemID)
                }

                Button("Reveal in Finder") {
                    revealInFinder(itemID: itemID)
                }

                if let errorDetails = errorDetails(for: itemID) {
                    Divider()

                    Button("Error Details") {
                        errorDetailsMessage = errorDetails
                    }
                }

                Divider()

                if viewModel.isManuallySkipped(itemID: itemID) {
                    Button("Mark for Rename") {
                        viewModel.markItemsAsReady(itemIDs)
                    }
                } else if viewModel.isReadyForRename(itemID: itemID) {
                    Button("Skip Rename") {
                        viewModel.markItemsAsSkipped(itemIDs)
                    }
                }

                Button("Delete File...", role: .destructive) {
                    pendingDeleteItemIDs = itemIDs
                    isDeleteConfirmationPresented = true
                }
            }
        } primaryAction: { itemIDs in
            if let itemID = itemIDs.first {
                selectedPreviewItemID = itemID
                _ = openQuickLook(for: itemID)
            }
        }
        .onKeyPress(.space) {
            openSelectedQuickLook() ? .handled : .ignored
        }
    }

    private var footer: some View {
        HStack {
            if viewModel.isRenaming {
                ProgressView(value: viewModel.renameProgressFraction ?? 0)
                    .frame(width: 120)
            }

            Text(summaryText)
                .foregroundStyle(.secondary)

            Spacer()

            Button("Rename Files") {
                isConfirmationPresented = true
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.readyCount == 0 || viewModel.isLoading || viewModel.isRenaming)
        }
        .padding()
    }

    private var sortedItems: [RenameItem] {
        viewModel.items.sorted(using: sortOrder)
    }

    private var itemIDs: [RenameItem.ID] {
        viewModel.items.map(\.id)
    }

    private func pruneTransientSelection(availableItemIDs: Set<RenameItem.ID>) {
        if let selectedPreviewItemID,
            !availableItemIDs.contains(selectedPreviewItemID)
        {
            self.selectedPreviewItemID = nil
        }

        pendingDeleteItemIDs.formIntersection(availableItemIDs)
    }

    private var deleteConfirmationTitle: String {
        if pendingDeleteItemIDs.count == 1 {
            return String(localized: "deleteConfirmation.title.single", defaultValue: "Move this file to the Trash?")
        }

        let format = String(localized: "deleteConfirmation.title.multiple.format", defaultValue: "Move %lld files to the Trash?")
        return String(format: format, pendingDeleteItemIDs.count)
    }

    private var deleteConfirmationMessage: String {
        String(
            localized: "deleteConfirmation.message",
            defaultValue: "This moves the selected file to the Trash."
        )
    }

    private var selectedFolderHelp: String {
        viewModel.selectedFolderURL?.path ?? String(localized: "Select a folder", defaultValue: "Select a folder")
    }

    private func openSelectedQuickLook() -> Bool {
        guard let selectedPreviewItemID else {
            return false
        }

        return openQuickLook(for: selectedPreviewItemID)
    }

    private func openQuickLook(for itemID: RenameItem.ID) -> Bool {
        guard let previewURL = previewURL(for: itemID) else {
            return false
        }

        quickLookPresenter = QuickLookPreviewPresenter(
            url: previewURL,
            accessURL: viewModel.selectedFolderURL ?? previewURL
        ) {
            quickLookPresenter = nil
        }
        quickLookPresenter?.present()
        return true
    }

    private func revealInFinder(itemID: RenameItem.ID) {
        guard let url = previewURL(for: itemID) else {
            return
        }

        let accessURL = viewModel.selectedFolderURL ?? url
        let isAccessing = accessURL.startAccessingSecurityScopedResource()
        NSWorkspace.shared.activateFileViewerSelecting([url])

        if isAccessing {
            accessURL.stopAccessingSecurityScopedResource()
        }
    }

    private func errorDetails(for itemID: RenameItem.ID) -> String? {
        guard let item = viewModel.items.first(where: { $0.id == itemID }) else {
            return nil
        }

        return item.state.detail
    }

    private func previewURL(for itemID: RenameItem.ID) -> URL? {
        guard let item = viewModel.items.first(where: { $0.id == itemID }) else {
            return nil
        }

        if item.state == .completed,
            let destinationURL = item.destinationURL
        {
            return destinationURL
        }

        return item.sourceURL
    }

    private var summaryText: String {
        if viewModel.isRenaming {
            if let totalRenameFileCount = viewModel.totalRenameFileCount {
                let format = String(
                    localized: "summary.renamingProgress.format",
                    defaultValue: "Renaming files: %lld of %lld"
                )
                return String(format: format, viewModel.renamedFileCount, totalRenameFileCount)
            }

            return String(localized: "summary.renaming", defaultValue: "Renaming files...")
        }

        let format = String(localized: "summary.readyCount.format", defaultValue: "%lld items, %lld ready to rename")
        return String(format: format, viewModel.items.count, viewModel.readyCount)
    }

    private var renameConfirmationMessage: String {
        let format = String(
            localized: "rename.confirmation.message.format",
            defaultValue: "Rename %lld files. Review the New Filename column before continuing."
        )
        return String(format: format, viewModel.readyCount)
    }
}

private struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    let viewModel: PhotoRenameViewModel

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Filename") {
                    Picker(
                        "Date format",
                        selection: Binding(
                            get: { viewModel.filenameFormat },
                            set: { newValue in
                                viewModel.filenameFormat = newValue
                                viewModel.loadPreview()
                            }
                        )
                    ) {
                        ForEach(FilenameFormat.allCases) { format in
                            Text(format.title)
                                .tag(format)
                        }
                    }

                    Picker(
                        "Date used in filename",
                        selection: Binding(
                            get: { viewModel.timeZoneStyle },
                            set: { newValue in
                                viewModel.timeZoneStyle = newValue
                                viewModel.loadPreview()
                            }
                        )
                    ) {
                        ForEach(FilenameTimeZoneStyle.allCases) { style in
                            Text(style.title)
                                .tag(style)
                        }
                    }

                    Picker(
                        "Extension style",
                        selection: Binding(
                            get: { viewModel.extensionStyle },
                            set: { newValue in
                                viewModel.extensionStyle = newValue
                                viewModel.loadPreview()
                            }
                        )
                    ) {
                        ForEach(FilenameExtensionStyle.allCases) { style in
                            Text(style.title)
                                .tag(style)
                        }
                    }
                }

                Section("Files to Scan") {
                    Picker(
                        "File types",
                        selection: Binding(
                            get: { viewModel.imageFileSelection },
                            set: { newValue in
                                viewModel.imageFileSelection = newValue
                                viewModel.loadPreview()
                            }
                        )
                    ) {
                        ForEach(ImageFileSelection.allCases) { selection in
                            Text(selection.title)
                                .tag(selection)
                        }
                    }

                    Toggle(
                        "Include subfolders",
                        isOn: Binding(
                            get: { viewModel.includeSubfolders },
                            set: { newValue in
                                viewModel.includeSubfolders = newValue
                                viewModel.loadPreview()
                            }
                        )
                    )

                    Toggle(
                        "Use file creation date when capture date is missing",
                        isOn: Binding(
                            get: { viewModel.useFileCreationDateAsFallback },
                            set: { newValue in
                                viewModel.useFileCreationDateAsFallback = newValue
                                viewModel.loadPreview()
                            }
                        )
                    )
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()

                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 500, height: 470)
    }
}

private final class QuickLookPreviewPresenter: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    private let url: URL
    private let accessURL: URL
    private let onClose: () -> Void
    private var isAccessingSecurityScopedResource = false

    init(url: URL, accessURL: URL, onClose: @escaping () -> Void) {
        self.url = url
        self.accessURL = accessURL
        self.onClose = onClose
    }

    func present() {
        isAccessingSecurityScopedResource = accessURL.startAccessingSecurityScopedResource()

        guard let panel = QLPreviewPanel.shared() else {
            stopAccessingSecurityScopedResource()
            onClose()
            return
        }

        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        1
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        url as NSURL
    }

    func previewPanelWillClose(_ notification: Notification!) {
        stopAccessingSecurityScopedResource()
        onClose()
    }

    private func stopAccessingSecurityScopedResource() {
        if isAccessingSecurityScopedResource {
            accessURL.stopAccessingSecurityScopedResource()
            isAccessingSecurityScopedResource = false
        }
    }
}

private struct StatusView: View {
    let state: RenameItem.State

    var body: some View {
        Label {
            Text(state.label)
                .lineLimit(1)
                .foregroundStyle(.primary)
        } icon: {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
        }
        .help(state.detail ?? state.label)
    }

    private var iconName: String {
        switch state {
        case .ready:
            return "arrow.right.circle.fill"

        case .skipped:
            return "pause.circle"

        case .alreadyRenamed, .completed:
            return "checkmark.circle"

        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }

    private var iconColor: Color {
        switch state {
        case .ready:
            return .green

        case .skipped:
            return .gray

        case .alreadyRenamed, .completed:
            return .gray

        case .failed:
            return .red
        }
    }
}

#Preview {
    ContentView()
        .frame(width: 900, height: 600)
}
