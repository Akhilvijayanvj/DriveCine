import SwiftUI
import AppKit

public final class ActiveTransfersViewModel: ObservableObject {
    @Published public var searchText: String = ""
    @Published public var filterStatus: String = "All"
    @Published public var showingNewSheet: Bool = false
    public init() {}
}

public struct ActiveTransfersView: View {
    @ObservedObject private var engine = DownloadEngine.shared
    @StateObject private var vm = ActiveTransfersViewModel()

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            if let session = currentSession {
                // Project Header Card
                projectHeader(session: session)

                Divider().background(ProTheme.borderSubtle)

                // Master Metrics Strip
                metricsStrip(session: session)

                Divider().background(ProTheme.borderSubtle)

                // File Transfer Table Header & Actions
                transferListToolbar

                Divider().background(ProTheme.borderSubtle)

                // File Transfer List
                fileTasksList(session: session)
            } else {
                emptyState
            }
        }
        .background(ProTheme.bgDarkest)
        .sheet(isPresented: $vm.showingNewSheet) {
            NewTransferSheet()
        }
    }

    private var currentSession: TransferSession? {
        if let id = engine.currentSessionId {
            return engine.sessions.first(where: { $0.id == id })
        }
        return engine.sessions.first
    }

    // MARK: - Project Header

    private func projectHeader(session: TransferSession) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "folder.fill")
                .font(.system(size: 24))
                .foregroundColor(ProTheme.warning)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(session.name)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(ProTheme.textPrimary)

                    SessionStatusPill(status: session.status)
                }

                HStack(spacing: 8) {
                    Image(systemName: "externaldrive.fill")
                        .font(.system(size: 11))
                        .foregroundColor(ProTheme.textMuted)

                    Text(session.destinationPath)
                        .font(.system(size: 11))
                        .foregroundColor(ProTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Button {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: session.destinationPath)
                    } label: {
                        Text("Reveal in Finder")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(ProTheme.accent)
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            // Session Master Controls
            HStack(spacing: 8) {
                if session.status == .downloading {
                    Button {
                        engine.pauseSession(sessionId: session.id)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "pause.fill")
                            Text("Pause All")
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(ProTheme.bgSurface)
                        .foregroundColor(ProTheme.warning)
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(ProTheme.borderSubtle, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                } else if session.status == .paused || session.status == .ready {
                    Button {
                        engine.resumeSession(sessionId: session.id)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "play.fill")
                            Text("Resume All")
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(ProTheme.accent)
                        .foregroundColor(Color.black)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }

                if hasFailedTasks {
                    Button {
                        engine.retryFailedTasks()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                            Text("Retry Failed")
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(ProTheme.danger.opacity(0.15))
                        .foregroundColor(ProTheme.danger)
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(ProTheme.danger.opacity(0.3), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(ProTheme.bgDark)
    }

    // MARK: - Metrics Strip

    private func metricsStrip(session: TransferSession) -> some View {
        VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 20) {
                // Live Speed
                SpeedBadge(speed: engine.totalSpeed)

                // Transferred Data
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.to.line.compact")
                        .font(.system(size: 12))
                        .foregroundColor(ProTheme.textMuted)

                    Text(session.formattedProgress)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(ProTheme.textPrimary)
                }

                // File Counts
                HStack(spacing: 6) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12))
                        .foregroundColor(ProTheme.textMuted)

                    Text(session.formattedCounts)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(ProTheme.textSecondary)
                }

                // Active Streams
                HStack(spacing: 6) {
                    Circle()
                        .fill(engine.totalActiveCount > 0 ? ProTheme.success : ProTheme.textMuted)
                        .frame(width: 6, height: 6)

                    Text("\(engine.totalActiveCount) active streams")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(ProTheme.textSecondary)
                }

                Spacer()

                // Overall ETA
                if let eta = overallEta(session: session) {
                    HStack(spacing: 4) {
                        Image(systemName: "hourglass")
                            .font(.system(size: 11))
                            .foregroundColor(ProTheme.textMuted)

                        Text("ETA: \(eta)")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(ProTheme.accent)
                    }
                }
            }

            // Master Progress Bar
            ProProgressBar(progress: session.progress, height: 8, tintColor: ProTheme.accent, showGlow: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(ProTheme.bgSurface)
    }

    private func overallEta(session: TransferSession) -> String? {
        guard engine.totalSpeed > 1024, session.status == .downloading else { return nil }
        let remainingBytes = Double(session.totalBytes - session.completedBytes)
        guard remainingBytes > 0 else { return "0s" }
        let seconds = remainingBytes / engine.totalSpeed
        if seconds < 60 {
            return String(format: "%ds", Int(seconds))
        } else if seconds < 3600 {
            return String(format: "%dm %ds", Int(seconds) / 60, Int(seconds) % 60)
        } else {
            return String(format: "%dh %dm", Int(seconds) / 3600, (Int(seconds) % 3600) / 60)
        }
    }

    // MARK: - Toolbar

    private var transferListToolbar: some View {
        HStack(spacing: 12) {
            // Status Filter Tabs
            HStack(spacing: 4) {
                ForEach(["All", "Active", "Queued", "Completed", "Failed"], id: \.self) { tab in
                    Button {
                        vm.filterStatus = tab
                    } label: {
                        Text(tab)
                            .font(.system(size: 11, weight: vm.filterStatus == tab ? .bold : .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .foregroundColor(vm.filterStatus == tab ? ProTheme.textPrimary : ProTheme.textMuted)
                            .background(vm.filterStatus == tab ? ProTheme.bgSurfaceHover : Color.clear)
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            // Search Filter
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(ProTheme.textMuted)
                    .font(.system(size: 11))
                TextField("Filter files...", text: $vm.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundColor(ProTheme.textPrimary)
                    .frame(width: 140)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(ProTheme.bgDarkest)
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(ProTheme.borderSubtle, lineWidth: 1))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(ProTheme.bgDark)
    }

    // MARK: - File Tasks List

    private func fileTasksList(session: TransferSession) -> some View {
        let tasks = filteredTasks
        return Group {
            if tasks.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 28))
                        .foregroundColor(ProTheme.textMuted)
                    Text("No files match the current filter")
                        .font(.system(size: 12))
                        .foregroundColor(ProTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(tasks) { task in
                        taskRow(task: task)
                            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                            .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(ProTheme.bgDarkest)
            }
        }
    }

    private func taskRow(task: DownloadTask) -> some View {
        HStack(spacing: 12) {
            // Media Icon
            Image(systemName: fileIcon(name: task.fileName))
                .font(.system(size: 14))
                .foregroundColor(fileColor(name: task.fileName))
                .frame(width: 20)

            // File Details
            VStack(alignment: .leading, spacing: 2) {
                Text(task.fileName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(ProTheme.textPrimary)
                    .lineLimit(1)

                Text(task.relativePath)
                    .font(.system(size: 10))
                    .foregroundColor(ProTheme.textMuted)
                    .lineLimit(1)
            }
            .frame(width: 220, alignment: .leading)

            // Progress Bar & Info
            VStack(alignment: .leading, spacing: 3) {
                ProProgressBar(
                    progress: task.progress,
                    height: 5,
                    tintColor: task.status == .failed ? ProTheme.danger : (task.status == .completed ? ProTheme.success : ProTheme.accent)
                )

                HStack {
                    Text(task.formattedProgressText)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(ProTheme.textMuted)

                    Spacer()

                    if task.status == .downloading {
                        Text(task.formattedSpeed)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(ProTheme.accent)

                        Text("• ETA: \(task.formattedETA)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(ProTheme.textSecondary)
                    } else if let err = task.errorMessage {
                        Text(err)
                            .font(.system(size: 10))
                            .foregroundColor(ProTheme.danger)
                            .lineLimit(1)
                    }
                }
            }

            // MD5 Checksum Badge
            if let md5 = task.md5Checksum {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 12))
                    .foregroundColor(task.status == .completed ? ProTheme.success : ProTheme.textMuted.opacity(0.6))
                    .help("Google Drive MD5: \(md5)")
            }

            // Status Pill
            StatusPill(status: task.status)
                .frame(width: 100, alignment: .center)

            // Actions
            HStack(spacing: 4) {
                if task.status == .downloading {
                    Button {
                        engine.pauseTask(taskId: task.id)
                    } label: {
                        Image(systemName: "pause.circle")
                            .font(.system(size: 14))
                            .foregroundColor(ProTheme.warning)
                    }
                    .buttonStyle(.plain)
                    .help("Pause download")
                } else if task.status == .paused || task.status == .failed {
                    Button {
                        engine.resumeTask(taskId: task.id)
                    } label: {
                        Image(systemName: "arrow.clockwise.circle")
                            .font(.system(size: 14))
                            .foregroundColor(ProTheme.accent)
                    }
                    .buttonStyle(.plain)
                    .help("Resume / Retry download")
                }

                if task.status == .completed {
                    Button {
                        NSWorkspace.shared.selectFile(task.localPath, inFileViewerRootedAtPath: (task.localPath as NSString).deletingLastPathComponent)
                    } label: {
                        Image(systemName: "magnifyingglass.circle")
                            .font(.system(size: 14))
                            .foregroundColor(ProTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .help("Reveal file in Finder")
                }
            }
            .frame(width: 40)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(ProTheme.bgSurface)
        .cornerRadius(6)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(ProTheme.borderSubtle, lineWidth: 1))
    }

    private var filteredTasks: [DownloadTask] {
        return engine.activeTasks.filter { task in
            if !vm.searchText.isEmpty {
                if !task.fileName.localizedCaseInsensitiveContains(vm.searchText) &&
                   !task.relativePath.localizedCaseInsensitiveContains(vm.searchText) {
                    return false
                }
            }

            switch vm.filterStatus {
            case "Active": return task.status == .downloading || task.status == .verifying
            case "Queued": return task.status == .queued
            case "Completed": return task.status == .completed
            case "Failed": return task.status == .failed
            default: return true
            }
        }
    }

    private var hasFailedTasks: Bool {
        return engine.activeTasks.contains { $0.status == .failed }
    }

    private func fileIcon(name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "mov", "mp4", "m4v", "mxf", "braw", "r3d": return "film.stack.fill"
        case "wav", "mp3", "aac", "aif": return "waveform"
        case "arw", "cr2", "cr3", "dng", "jpg", "png": return "camera.aperture"
        case "cube", "look", "drp": return "slider.horizontal.3"
        default: return "doc.fill"
        }
    }

    private func fileColor(name: String) -> Color {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "mov", "mp4", "m4v", "mxf", "braw", "r3d": return Color(red: 0.36, green: 0.68, blue: 0.99)
        case "wav", "mp3", "aac", "aif": return Color(red: 0.40, green: 0.88, blue: 0.60)
        case "arw", "cr2", "cr3", "dng", "jpg", "png": return Color(red: 0.89, green: 0.48, blue: 0.93)
        case "cube", "look", "drp": return Color(red: 1.0, green: 0.55, blue: 0.25)
        default: return Color(red: 0.65, green: 0.65, blue: 0.70)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(ProTheme.bgSurface)
                    .frame(width: 80, height: 80)
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 40))
                    .foregroundColor(ProTheme.accent)
            }

            VStack(spacing: 6) {
                Text("No Active Transfer Session")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(ProTheme.textPrimary)

                Text("Paste a shared Google Drive wedding or project folder link to begin.")
                    .font(.system(size: 13))
                    .foregroundColor(ProTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                vm.showingNewSheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                    Text("New Project Transfer")
                }
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(Color.black)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(ProTheme.accent)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
