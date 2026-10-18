import SwiftUI
import AppKit

@MainActor
public final class NewTransferViewModel: ObservableObject {
    @Published public var inputUrl: String = ""
    @Published public var destinationPath: String = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path ?? "/Volumes"
    @Published public var isScanning: Bool = false
    @Published public var scanStatus: String = ""
    @Published public var errorMessage: String? = nil
    @Published public var parsedResource: ParsedDriveResource? = nil
    @Published public var scannedRootItem: DriveItem? = nil
    @Published public var selectedCategory: MediaCategory = .all
    @Published public var searchText: String = ""
    @Published public var showingSelectionFilterSheet: Bool = false

    public init() {}

    public var selectedItems: [DriveItem] {
        guard let root = scannedRootItem else { return [] }
        return root.flattenFiles().filter { $0.isSelected }
    }

    public var selectedTotalBytes: Int64 {
        return selectedItems.reduce(0) { $0 + $1.size }
    }

    public func pasteFromClipboard() {
        if let clipboard = NSPasteboard.general.string(forType: .string) {
            self.inputUrl = clipboard
            self.parsedResource = LinkParser.parse(input: clipboard)
        }
    }

    public func selectDestinationDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Destination"
        panel.message = "Choose an external SSD or local volume to store downloaded footage:"

        if panel.runModal() == .OK, let url = panel.url {
            self.destinationPath = url.path
        }
    }

    public func scanGoogleDrive() {
        guard let resource = parsedResource ?? LinkParser.parse(input: inputUrl) else {
            errorMessage = "Invalid Google Drive Link format."
            return
        }

        isScanning = true
        errorMessage = nil
        scanStatus = "Connecting to Google Drive API..."

        Task {
            do {
                let root = try await GoogleDriveClient.shared.traverseFolder(
                    folderId: resource.id,
                    onProgress: { status in
                        Task { @MainActor in
                            self.scanStatus = status
                        }
                    }
                )

                await MainActor.run {
                    self.scannedRootItem = root
                    self.isScanning = false
                    self.scanStatus = ""
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isScanning = false
                    self.scanStatus = ""
                }
            }
        }
    }

    public func startTransfer() {
        guard let root = scannedRootItem else { return }
        let itemsToDownload = selectedItems
        guard !itemsToDownload.isEmpty else { return }

        DownloadEngine.shared.createSession(
            name: root.name,
            rootDriveId: root.id,
            originalUrl: inputUrl,
            destinationDirectory: destinationPath,
            items: itemsToDownload
        )
    }
}

public struct NewTransferSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = NewTransferViewModel()
    @ObservedObject private var oauth = OAuthManager.shared

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("New Google Drive Transfer")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(ProTheme.textPrimary)
                    Text("Direct folder stream • Bypass 2GB zip splitting • Resumable downloads")
                        .font(.system(size: 11))
                        .foregroundColor(ProTheme.textSecondary)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(ProTheme.textMuted)
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(ProTheme.bgDark)

            Divider().background(ProTheme.borderSubtle)

            // Content Area
            ScrollView {
                VStack(spacing: 16) {
                    // Google Auth Status Card
                    if !oauth.isSignedIn && (KeychainManager.shared.get(.apiKey) == nil || KeychainManager.shared.get(.apiKey)!.isEmpty) {
                        HStack(spacing: 12) {
                            Image(systemName: "lock.shield.fill")
                                .foregroundColor(ProTheme.warning)
                                .font(.system(size: 22))

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Google Sign-In Required")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(ProTheme.textPrimary)
                                Text("Sign in once to authorize downloading shared wedding footage & private folders.")
                                    .font(.system(size: 11))
                                    .foregroundColor(ProTheme.textSecondary)
                            }

                            Spacer()

                            Button {
                                oauth.signIn()
                            } label: {
                                HStack(spacing: 6) {
                                    if oauth.isAuthenticating {
                                        ProgressView().scaleEffect(0.6).frame(width: 14, height: 14)
                                        Text("Signing In...")
                                    } else {
                                        Image(systemName: "person.crop.circle.badge.plus")
                                        Text("Sign in with Google")
                                    }
                                }
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(Color.black)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(ProTheme.accent)
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                            .disabled(oauth.isAuthenticating)
                        }
                        .padding(12)
                        .background(ProTheme.warning.opacity(0.12))
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(ProTheme.warning.opacity(0.35), lineWidth: 1))
                    } else if oauth.isSignedIn {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(ProTheme.success)
                                .font(.system(size: 12))
                            Text("Signed in as \(oauth.userEmail ?? "Google Account")")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(ProTheme.textSecondary)
                            Spacer()
                        }
                    }
                    // Google Drive Link Input
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Google Drive Link or Folder ID")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(ProTheme.textPrimary)

                        HStack(spacing: 8) {
                            HStack {
                                Image(systemName: "link")
                                    .foregroundColor(ProTheme.textMuted)
                                    .font(.system(size: 12))

                                TextField("https://drive.google.com/drive/folders/1A2B3C...", text: $vm.inputUrl)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12))
                                    .foregroundColor(ProTheme.textPrimary)
                                    .onChange(of: vm.inputUrl) { _, val in
                                        vm.parsedResource = LinkParser.parse(input: val)
                                    }

                                if !vm.inputUrl.isEmpty {
                                    Button {
                                        vm.inputUrl = ""
                                        vm.parsedResource = nil
                                        vm.scannedRootItem = nil
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(ProTheme.textMuted)
                                            .font(.system(size: 12))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(8)
                            .background(ProTheme.bgSurface)
                            .cornerRadius(6)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(ProTheme.borderSubtle, lineWidth: 1))

                            Button {
                                vm.pasteFromClipboard()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "doc.on.clipboard")
                                    Text("Paste")
                                }
                                .font(.system(size: 12, weight: .medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(ProTheme.bgSurface)
                                .foregroundColor(ProTheme.textPrimary)
                                .cornerRadius(6)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(ProTheme.borderSubtle, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }

                        if let parsed = vm.parsedResource {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(ProTheme.success)
                                    .font(.system(size: 11))
                                Text("Detected ID: \(parsed.id)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(ProTheme.textSecondary)
                            }
                        }
                    }

                    // Destination Directory Picker
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Destination Volume / Local Folder")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(ProTheme.textPrimary)

                        HStack(spacing: 8) {
                            HStack {
                                Image(systemName: "externaldrive.fill")
                                    .foregroundColor(ProTheme.accent)
                                    .font(.system(size: 12))

                                Text(vm.destinationPath)
                                    .font(.system(size: 12))
                                    .foregroundColor(ProTheme.textPrimary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)

                                Spacer()
                            }
                            .padding(8)
                            .background(ProTheme.bgSurface)
                            .cornerRadius(6)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(ProTheme.borderSubtle, lineWidth: 1))

                            Button {
                                vm.selectDestinationDirectory()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "folder")
                                    Text("Browse...")
                                }
                                .font(.system(size: 12, weight: .medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(ProTheme.bgSurface)
                                .foregroundColor(ProTheme.textPrimary)
                                .cornerRadius(6)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(ProTheme.borderSubtle, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Scan Action Button
                    if vm.scannedRootItem == nil {
                        Button {
                            vm.scanGoogleDrive()
                        } label: {
                            HStack(spacing: 6) {
                                if vm.isScanning {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                        .frame(width: 14, height: 14)
                                    Text(vm.scanStatus.isEmpty ? "Scanning Google Drive..." : vm.scanStatus)
                                } else {
                                    Image(systemName: "magnifyingglass.circle.fill")
                                    Text("Scan & Inspect Folder")
                                }
                            }
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(Color.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(vm.parsedResource != nil ? ProTheme.accent : ProTheme.textMuted)
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .disabled(vm.parsedResource == nil || vm.isScanning)
                    }

                    // Scanned Hierarchy & Preview
                    if let root = vm.scannedRootItem {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(root.name)
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(ProTheme.textPrimary)

                                    Text("\(vm.selectedItems.count) files selected (\(DriveItem.formatBytes(vm.selectedTotalBytes)))")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(ProTheme.accent)
                                }

                                Spacer()

                                Button {
                                    vm.showingSelectionFilterSheet = true
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: "checklist.checked")
                                        Text("Paste Selection List")
                                    }
                                    .font(.system(size: 11, weight: .bold))
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 4)
                                    .background(ProTheme.accent.opacity(0.18))
                                    .foregroundColor(ProTheme.accent)
                                    .cornerRadius(5)
                                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(ProTheme.accent.opacity(0.4), lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                                .help("Filter files by photo numbers like 8024, 8025 or full filenames")

                                Button {
                                    vm.scanGoogleDrive()
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.clockwise")
                                        Text("Rescan")
                                    }
                                    .font(.system(size: 11))
                                    .foregroundColor(ProTheme.textSecondary)
                                }
                                .buttonStyle(.plain)
                            }

                            // Disk Space Bar
                            DiskSpaceBar(destinationPath: vm.destinationPath, requiredBytes: vm.selectedTotalBytes)

                            // File Tree View Container
                            FileTreeView(
                                rootItem: $vm.scannedRootItem,
                                selectedCategory: $vm.selectedCategory,
                                searchText: $vm.searchText
                            )
                            .frame(height: 240)
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(ProTheme.borderSubtle, lineWidth: 1))
                        }
                    }

                    // Error Banner
                    if let err = vm.errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(ProTheme.danger)
                            Text(err)
                                .font(.system(size: 12))
                                .foregroundColor(ProTheme.danger)
                            Spacer()
                        }
                        .padding(10)
                        .background(ProTheme.danger.opacity(0.12))
                        .cornerRadius(6)
                    }
                }
                .padding(16)
            }

            Divider().background(ProTheme.borderSubtle)

            // Footer
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                if vm.scannedRootItem != nil {
                    Button {
                        vm.startTransfer()
                        dismiss()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.down.circle.fill")
                            Text("Download Direct (\(DriveItem.formatBytes(vm.selectedTotalBytes)))")
                        }
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Color.black)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(ProTheme.accent)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .disabled(vm.selectedItems.isEmpty)
                }
            }
            .padding(16)
            .background(ProTheme.bgDark)
        }
        .frame(width: 680, height: 600)
        .background(ProTheme.bgDarkest)
        .sheet(isPresented: $vm.showingSelectionFilterSheet) {
            SelectionFilterSheet(rootItem: $vm.scannedRootItem)
        }
    }
}
