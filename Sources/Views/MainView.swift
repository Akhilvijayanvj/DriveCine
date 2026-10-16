import SwiftUI
import AppKit

public enum NavigationTab: String, CaseIterable, Identifiable {
    case transfers = "Active Transfers"
    case history = "Transfer History"
    case settings = "Settings"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .transfers: return "arrow.down.circle.fill"
        case .history: return "clock.arrow.circlepath"
        case .settings: return "gearshape.fill"
        }
    }
}

public final class NavigationViewModel: ObservableObject {
    @Published public var selectedTab: NavigationTab = .transfers
    @Published public var showingNewSheet: Bool = false
    @Published public var quickLinkInput: String = ""
    public init() {}
}

public struct MainView: View {
    @ObservedObject private var engine = DownloadEngine.shared
    @StateObject private var nav = NavigationViewModel()

    public init() {}

    public var body: some View {
        NavigationSplitView {
            sidebarContent
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 300)
        } detail: {
            detailContent
        }
        .toolbar {
            toolbarItems
        }
        .sheet(isPresented: $nav.showingNewSheet) {
            NewTransferSheet()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenNewTransferSheet"))) { _ in
            nav.showingNewSheet = true
        }
    }

    // MARK: - Sidebar

    private var sidebarContent: some View {
        VStack(spacing: 0) {
            // App Header
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: [ProTheme.accent, Color(red: 0.1, green: 0.4, blue: 0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 32, height: 32)
                    Image(systemName: "film.stack.fill")
                        .font(.system(size: 16))
                        .foregroundColor(Color.black)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("DriveCine Pro")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(ProTheme.textPrimary)
                    Text("GDrive Media Transfer")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(ProTheme.textMuted)
                }

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(ProTheme.bgDark)

            Divider().background(ProTheme.borderSubtle)

            // Primary Navigation Items
            List(selection: $nav.selectedTab) {
                Section("WORKSPACE") {
                    ForEach(NavigationTab.allCases) { tab in
                        NavigationLink(value: tab) {
                            HStack(spacing: 8) {
                                Image(systemName: tab.iconName)
                                    .font(.system(size: 13))
                                    .foregroundColor(nav.selectedTab == tab ? ProTheme.accent : ProTheme.textSecondary)

                                Text(tab.rawValue)
                                    .font(.system(size: 12, weight: nav.selectedTab == tab ? .semibold : .regular))
                                    .foregroundColor(nav.selectedTab == tab ? ProTheme.textPrimary : ProTheme.textSecondary)

                                Spacer()

                                if tab == .transfers && engine.totalActiveCount > 0 {
                                    Text("\(engine.totalActiveCount)")
                                        .font(.system(size: 10, weight: .bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(ProTheme.accent)
                                        .foregroundColor(Color.black)
                                        .clipShape(Capsule())
                                } else if tab == .history && !engine.sessions.isEmpty {
                                    Text("\(engine.sessions.count)")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(ProTheme.textMuted)
                                }
                            }
                        }
                    }
                }

                if !engine.sessions.isEmpty {
                    Section("RECENT PROJECTS") {
                        ForEach(engine.sessions.prefix(5)) { session in
                            Button {
                                engine.selectSession(session)
                                nav.selectedTab = .transfers
                            } label: {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(session.status == .completed ? ProTheme.success : ProTheme.warning)
                                        .frame(width: 6, height: 6)

                                    Text(session.name)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(engine.currentSessionId == session.id ? ProTheme.textPrimary : ProTheme.textSecondary)
                                        .lineLimit(1)

                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(ProTheme.bgDarkest)

            Divider().background(ProTheme.borderSubtle)

            // Bottom Quick Ingestion Pill
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    nav.showingNewSheet = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("New Project Transfer")
                        Spacer()
                        Text("⌘N")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color.black.opacity(0.6))
                    }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .background(ProTheme.accent)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(ProTheme.bgDark)
        }
        .background(ProTheme.bgDarkest)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailContent: some View {
        switch nav.selectedTab {
        case .transfers:
            ActiveTransfersView()
        case .history:
            TransferHistoryView()
        case .settings:
            SettingsView()
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                nav.showingNewSheet = true
            } label: {
                Label("New Transfer", systemImage: "plus")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(ProTheme.accent)
            .foregroundColor(Color.black)
            .help("Start new Google Drive folder transfer (⌘N)")
            .keyboardShortcut("n", modifiers: .command)
        }

        ToolbarItem(placement: .status) {
            if engine.totalSpeed > 0 {
                HStack(spacing: 7) {
                    Circle()
                        .fill(ProTheme.success)
                        .frame(width: 7, height: 7)

                    Text("\(DriveItem.formatBytes(Int64(engine.totalSpeed)))/s")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(ProTheme.textPrimary)
                }
                .padding(.leading, 8)
                .padding(.trailing, 10)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.25))
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                .clipShape(Capsule())
            }
        }
    }
}
