import SwiftUI
import AppKit

@MainActor
public final class SelectionFilterViewModel: ObservableObject {
    @Published public var inputText: String = ""
    @Published public var matchMode: MatchMode = .smartNumber
    @Published public var result: SelectionMatchResult? = nil

    public init() {}

    public func updateEvaluation(items: [DriveItem]) {
        let tokens = SelectionMatcher.parseTokens(from: inputText)
        if tokens.isEmpty {
            self.result = nil
        } else {
            self.result = SelectionMatcher.evaluate(tokens: tokens, items: items, mode: matchMode)
        }
    }

    public func pasteFromClipboard(items: [DriveItem]) {
        if let clip = NSPasteboard.general.string(forType: .string) {
            self.inputText = clip
            updateEvaluation(items: items)
        }
    }
}

public struct SelectionFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding public var rootItem: DriveItem?
    @StateObject private var vm = SelectionFilterViewModel()

    public init(rootItem: Binding<DriveItem?>) {
        self._rootItem = rootItem
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: "checklist.checked")
                            .foregroundColor(ProTheme.accent)
                        Text("Filter by Photo / File Selection List")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(ProTheme.textPrimary)
                    }
                    Text("Paste numbers (e.g. 8024, 8025) or full filenames from client lists, emails, or spreadsheets")
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

            // Content
            VStack(alignment: .leading, spacing: 14) {
                // Top controls bar
                HStack {
                    Text("Paste Selection Items:")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(ProTheme.textPrimary)

                    Spacer()

                    Button {
                        if let root = rootItem {
                            vm.pasteFromClipboard(items: [root])
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.clipboard")
                            Text("Paste from Clipboard")
                        }
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(ProTheme.bgSurfaceHover)
                        .foregroundColor(ProTheme.textPrimary)
                        .cornerRadius(5)
                    }
                    .buttonStyle(.plain)

                    if !vm.inputText.isEmpty {
                        Button("Clear") {
                            vm.inputText = ""
                            vm.result = nil
                        }
                        .font(.system(size: 11))
                        .foregroundColor(ProTheme.danger)
                        .buttonStyle(.plain)
                    }
                }

                // Text Input Area
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $vm.inputText)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(ProTheme.textPrimary)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(ProTheme.bgDarkest)
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(ProTheme.borderSubtle, lineWidth: 1))
                        .frame(height: 120)
                        .onChange(of: vm.inputText) { _, _ in
                            if let root = rootItem {
                                vm.updateEvaluation(items: [root])
                            }
                        }

                    if vm.inputText.isEmpty {
                        Text("e.g. 8024, 8025, 8054, 8042\nOR\n_DSC8024.JPG\n_DSC8025.JPG\n\n(Separated by commas, spaces, or lines)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(ProTheme.textMuted.opacity(0.8))
                            .padding(12)
                            .allowsHitTesting(false)
                    }
                }

                // Match Mode Selector
                VStack(alignment: .leading, spacing: 4) {
                    Text("Matching Logic:")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(ProTheme.textSecondary)

                    Picker("", selection: $vm.matchMode) {
                        ForEach(MatchMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .font(.system(size: 11))
                    .foregroundColor(ProTheme.textPrimary)
                    .onChange(of: vm.matchMode) { _, _ in
                        if let root = rootItem {
                            vm.updateEvaluation(items: [root])
                        }
                    }
                }

                // Evaluation Results Card
                if let res = vm.result {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: res.matchedCount > 0 ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                .foregroundColor(res.matchedCount > 0 ? ProTheme.success : ProTheme.warning)
                                .font(.system(size: 14))

                            Text("Found \(res.matchedCount) matching files (\(DriveItem.formatBytes(res.totalMatchedBytes))) out of \(res.totalCandidateFiles) total")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(ProTheme.textPrimary)
                        }

                        if !res.notFoundTokens.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("\(res.notFoundTokens.count) item(s) from your list were not found in this folder:")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(ProTheme.danger)

                                    Spacer()

                                    Button("Copy Missing") {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(res.notFoundTokens.joined(separator: ", "), forType: .string)
                                    }
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(ProTheme.accent)
                                    .buttonStyle(.plain)
                                }

                                Text(res.notFoundTokens.prefix(15).joined(separator: ", ") + (res.notFoundTokens.count > 15 ? " ...and \(res.notFoundTokens.count - 15) more" : ""))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(ProTheme.textMuted)
                                    .lineLimit(2)
                            }
                            .padding(8)
                            .background(ProTheme.danger.opacity(0.1))
                            .cornerRadius(6)
                        }
                    }
                    .padding(10)
                    .background(ProTheme.bgSurface)
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(ProTheme.borderSubtle, lineWidth: 1))
                }
            }
            .padding(16)

            Divider().background(ProTheme.borderSubtle)

            // Footer Actions
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                if let res = vm.result, res.matchedCount > 0 {
                    Button {
                        applySelection(selectMatchedOnly: false)
                        dismiss()
                    } label: {
                        Text("Add to Selection (+\(res.matchedCount))")
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(ProTheme.bgSurfaceHover)
                            .foregroundColor(ProTheme.textPrimary)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)

                    Button {
                        applySelection(selectMatchedOnly: true)
                        dismiss()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Select Matching Only (\(res.matchedCount) files)")
                        }
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(ProTheme.accent)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            .background(ProTheme.bgDark)
        }
        .frame(width: 580, height: 480)
        .background(ProTheme.bgDarkest)
        .onAppear {
            if let root = rootItem {
                vm.updateEvaluation(items: [root])
            }
        }
    }

    private func applySelection(selectMatchedOnly: Bool) {
        guard var root = rootItem, let res = vm.result else { return }
        SelectionMatcher.applySelection(
            matchedIds: res.matchedIds,
            rootItem: &root,
            selectMatchedOnly: selectMatchedOnly
        )
        self.rootItem = root
    }
}
