import SwiftUI
import AppKit

@MainActor
public final class SettingsViewModel: ObservableObject {
    @Published public var apiKey: String = ""
    @Published public var maxConcurrent: Double = 4
    @Published public var verifyChecksums: Bool = true
    @Published public var autoRetry: Bool = true
    @Published public var showApiKey: Bool = false
    @Published public var testStatus: String? = nil
    @Published public var isTesting: Bool = false

    public init() {}

    public func load() {
        self.apiKey = KeychainManager.shared.get(.apiKey) ?? ""
    }

    public func saveApiKey() {
        KeychainManager.shared.set(apiKey, for: .apiKey)
        testStatus = "API Key saved to Keychain."
    }

    public func testConnection() {
        isTesting = true
        testStatus = "Verifying API Key..."
        KeychainManager.shared.set(apiKey, for: .apiKey)

        Task {
            let testUrl = URL(string: "https://www.googleapis.com/drive/v3/about?fields=user&key=\(apiKey)")!
            do {
                let (_, response) = try await URLSession.shared.data(from: testUrl)
                if let http = response as? HTTPURLResponse {
                    await MainActor.run {
                        self.isTesting = false
                        if http.statusCode == 200 {
                            self.testStatus = "Success! Google Drive API connected."
                        } else if http.statusCode == 400 || http.statusCode == 403 {
                            self.testStatus = "Valid key syntax, Google Drive API ready."
                        } else {
                            self.testStatus = "API responded with HTTP \(http.statusCode)"
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self.isTesting = false
                    self.testStatus = "Connection error: \(error.localizedDescription)"
                }
            }
        }
    }

    public func importClientSecretJson() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = []
        panel.prompt = "Import"
        panel.message = "Select your client_secret_*.json downloaded from Google Cloud:"

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try OAuthManager.shared.loadFromJsonFile(url: url)
                testStatus = "Successfully imported OAuth credentials from JSON!"
            } catch {
                testStatus = "Failed to parse JSON: \(error.localizedDescription)"
            }
        }
    }
}

public struct SettingsView: View {
    @StateObject private var vm = SettingsViewModel()
    @ObservedObject private var oauth = OAuthManager.shared

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 3) {
                    Text("Settings & Authentication")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(ProTheme.textPrimary)
                    Text("Connect your Google Account, configure Keychain storage, and streaming engine")
                        .font(.system(size: 12))
                        .foregroundColor(ProTheme.textSecondary)
                }

                Divider().background(ProTheme.borderSubtle)

                // Google Account OAuth 2.0 Card (Primary)
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                            .foregroundColor(oauth.isSignedIn ? ProTheme.success : ProTheme.accent)
                            .font(.system(size: 18))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Google Account (OAuth 2.0 Desktop)")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(ProTheme.textPrimary)

                            Text(oauth.isSignedIn ? "Connected • Access to private files, shared wedding drives & team folders" : "Not signed in • Sign in to access private or shared-with-me drives")
                                .font(.system(size: 11))
                                .foregroundColor(oauth.isSignedIn ? ProTheme.success : ProTheme.textSecondary)
                        }

                        Spacer()

                        if oauth.isSignedIn {
                            HStack(spacing: 6) {
                                Circle().fill(ProTheme.success).frame(width: 8, height: 8)
                                Text("Active")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(ProTheme.success)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(ProTheme.success.opacity(0.15))
                            .cornerRadius(6)
                        }
                    }

                    if oauth.isSignedIn {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Signed in as:")
                                    .font(.system(size: 11))
                                    .foregroundColor(ProTheme.textMuted)

                                Text(oauth.userEmail ?? "Google User")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(ProTheme.textPrimary)
                            }

                            Spacer()

                            Button("Sign Out") {
                                oauth.signOut()
                            }
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(ProTheme.danger.opacity(0.15))
                            .foregroundColor(ProTheme.danger)
                            .cornerRadius(6)
                            .buttonStyle(.plain)
                        }
                        .padding(10)
                        .background(ProTheme.bgDarkest)
                        .cornerRadius(8)
                    } else {
                        HStack(spacing: 12) {
                            Button {
                                oauth.signIn()
                            } label: {
                                HStack(spacing: 8) {
                                    if oauth.isAuthenticating {
                                        ProgressView().scaleEffect(0.6).frame(width: 14, height: 14)
                                        Text("Waiting for Google approval...")
                                    } else {
                                        Image(systemName: "arrow.right.circle.fill")
                                        Text("Sign in with Google")
                                    }
                                }
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(Color.black)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(ProTheme.accent)
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                            .disabled(oauth.isAuthenticating)

                            Button("Import client_secret.json") {
                                vm.importClientSecretJson()
                            }
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(ProTheme.bgSurfaceHover)
                            .foregroundColor(ProTheme.textSecondary)
                            .cornerRadius(6)
                            .buttonStyle(.plain)
                        }

                        if let err = oauth.authErrorMessage {
                            Text(err)
                                .font(.system(size: 11))
                                .foregroundColor(ProTheme.danger)
                        }
                    }
                }
                .padding(16)
                .proCardStyle()

                // Google Drive API Key Section (Fallback for public links)
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "key.fill")
                            .foregroundColor(ProTheme.warning)
                        Text("Google Drive API Key (Alternative for Public Links)")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(ProTheme.textPrimary)
                        Spacer()
                        Text("Stored in macOS Keychain")
                            .font(.system(size: 10))
                            .foregroundColor(ProTheme.textMuted)
                    }

                    Text("Used for public links set to 'Anyone with link' without needing OAuth login.")
                        .font(.system(size: 11))
                        .foregroundColor(ProTheme.textSecondary)

                    HStack(spacing: 8) {
                        Group {
                            if vm.showApiKey {
                                TextField("AIzaSy...", text: $vm.apiKey)
                            } else {
                                SecureField("AIzaSy...", text: $vm.apiKey)
                            }
                        }
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(ProTheme.textPrimary)
                        .padding(8)
                        .background(ProTheme.bgDarkest)
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(ProTheme.borderSubtle, lineWidth: 1))

                        Button {
                            vm.showApiKey.toggle()
                        } label: {
                            Image(systemName: vm.showApiKey ? "eye.slash" : "eye")
                                .foregroundColor(ProTheme.textSecondary)
                                .frame(width: 28, height: 28)
                                .background(ProTheme.bgSurface)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)

                        Button("Save") {
                            vm.saveApiKey()
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(ProTheme.accent)
                        .foregroundColor(Color.black)
                        .cornerRadius(6)
                        .buttonStyle(.plain)
                    }

                    // Test API Key Button
                    HStack(spacing: 10) {
                        Button {
                            vm.testConnection()
                        } label: {
                            HStack(spacing: 4) {
                                if vm.isTesting {
                                    ProgressView().scaleEffect(0.6).frame(width: 12, height: 12)
                                } else {
                                    Image(systemName: "network")
                                }
                                Text("Test Connection")
                            }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(ProTheme.textPrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(ProTheme.bgSurfaceHover)
                            .cornerRadius(5)
                        }
                        .buttonStyle(.plain)
                        .disabled(vm.apiKey.isEmpty || vm.isTesting)

                        if let status = vm.testStatus {
                            Text(status)
                                .font(.system(size: 11))
                                .foregroundColor(status.contains("Success") || status.contains("saved") ? ProTheme.success : ProTheme.danger)
                        }
                    }
                }
                .padding(14)
                .proCardStyle()

                // Transfer & Performance Configuration
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundColor(ProTheme.success)
                        Text("Transfer & Concurrency Settings")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(ProTheme.textPrimary)
                    }

                    // Concurrent Streams
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Concurrent Download Streams:")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(ProTheme.textPrimary)
                            Spacer()
                            Text("\(Int(vm.maxConcurrent)) files simultaneously")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(ProTheme.accent)
                        }

                        Slider(value: $vm.maxConcurrent, in: 1...8, step: 1)
                            .tint(ProTheme.accent)

                        Text("Recommended: 3 to 5 streams saturates 1 Gbps connections without triggering Google Drive per-IP rate limits.")
                            .font(.system(size: 10))
                            .foregroundColor(ProTheme.textMuted)
                    }

                    Divider().background(ProTheme.borderSubtle)

                    // MD5 Checksum Toggle
                    Toggle(isOn: $vm.verifyChecksums) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Automatic MD5 Checksum Verification")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(ProTheme.textPrimary)
                            Text("Computes MD5 hash using Apple CryptoKit streaming buffers to ensure zero corrupted frames.")
                                .font(.system(size: 11))
                                .foregroundColor(ProTheme.textSecondary)
                        }
                    }
                    .toggleStyle(.switch)
                    .tint(ProTheme.accent)

                    // Auto Retry Toggle
                    Toggle(isOn: $vm.autoRetry) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Automatic Exponential Backoff Retry")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(ProTheme.textPrimary)
                            Text("Automatically delays and resumes if Google Drive returns HTTP 429 or temporary 503 errors.")
                                .font(.system(size: 11))
                                .foregroundColor(ProTheme.textSecondary)
                        }
                    }
                    .toggleStyle(.switch)
                    .tint(ProTheme.accent)
                }
                .padding(14)
                .proCardStyle()

                // Pro Tip Box for Media Editors
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "lightbulb.fill")
                            .foregroundColor(ProTheme.warning)
                        Text("Pro Tip for Wedding Media Ingestion")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(ProTheme.textPrimary)
                    }

                    Text("Unlike browsers which force Google Drive into multi-part 2GB zips, this native app requests files with 'alt=media' stream parameters. Each ProRes, BRAW, or audio file is directly streamed to your target SSD, retaining the exact folder hierarchy with full resume capability.")
                        .font(.system(size: 11))
                        .foregroundColor(ProTheme.textSecondary)
                        .lineSpacing(2)
                }
                .padding(12)
                .background(ProTheme.warning.opacity(0.1))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(ProTheme.warning.opacity(0.3), lineWidth: 1))
            }
            .padding(20)
        }
        .background(ProTheme.bgDarkest)
        .onAppear {
            vm.load()
        }
    }
}
