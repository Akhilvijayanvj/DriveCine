import SwiftUI
import AppKit

public struct TransferHistoryView: View {
    @ObservedObject private var engine = DownloadEngine.shared

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Transfer History")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(ProTheme.textPrimary)
                    Text("All persisted Google Drive download sessions")
                        .font(.system(size: 11))
                        .foregroundColor(ProTheme.textSecondary)
                }

                Spacer()
            }
            .padding(16)
            .background(ProTheme.bgDark)

            Divider().background(ProTheme.borderSubtle)

            if engine.sessions.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 32))
                        .foregroundColor(ProTheme.textMuted)
                    Text("No past transfers found")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(ProTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(engine.sessions) { session in
                        sessionRow(session: session)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(ProTheme.bgDarkest)
            }
        }
        .background(ProTheme.bgDarkest)
    }

    private func sessionRow(session: TransferSession) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "folder.fill")
                .font(.system(size: 20))
                .foregroundColor(session.status == .completed ? ProTheme.success : ProTheme.warning)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(session.name)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(ProTheme.textPrimary)

                    SessionStatusPill(status: session.status)
                }

                Text(session.destinationPath)
                    .font(.system(size: 11))
                    .foregroundColor(ProTheme.textMuted)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(session.formattedProgress)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(ProTheme.textSecondary)

                Text(session.formattedCounts)
                    .font(.system(size: 10))
                    .foregroundColor(ProTheme.textMuted)
            }

            // Actions
            HStack(spacing: 8) {
                Button {
                    engine.selectSession(session)
                } label: {
                    Text("Inspect")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(ProTheme.bgSurfaceHover)
                        .foregroundColor(ProTheme.textPrimary)
                        .cornerRadius(5)
                }
                .buttonStyle(.plain)

                Button {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: session.destinationPath)
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 12))
                        .foregroundColor(ProTheme.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Reveal in Finder")

                Button {
                    engine.deleteSession(sessionId: session.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundColor(ProTheme.danger.opacity(0.8))
                }
                .buttonStyle(.plain)
                .help("Delete session record")
            }
        }
        .padding(12)
        .background(ProTheme.bgSurface)
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(ProTheme.borderSubtle, lineWidth: 1))
    }
}
