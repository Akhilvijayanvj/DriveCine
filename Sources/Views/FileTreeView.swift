import SwiftUI

public final class TreeViewState: ObservableObject {
    @Published public var showingSelectionFilterSheet: Bool = false
    public init() {}
}

public struct FileTreeView: View {
    @Binding public var rootItem: DriveItem?
    @Binding public var selectedCategory: MediaCategory
    @Binding public var searchText: String
    @StateObject private var treeState = TreeViewState()

    public init(
        rootItem: Binding<DriveItem?>,
        selectedCategory: Binding<MediaCategory>,
        searchText: Binding<String>
    ) {
        self._rootItem = rootItem
        self._selectedCategory = selectedCategory
        self._searchText = searchText
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Filter Bar
            HStack(spacing: 8) {
                // Category Pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach([MediaCategory.all, .video, .audio, .photo, .projectFile], id: \.self) { cat in
                            Button {
                                selectedCategory = cat
                                applyFilter(cat: cat)
                            } label: {
                                Text(cat.rawValue)
                                    .font(.system(size: 11, weight: selectedCategory == cat ? .bold : .medium))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .foregroundColor(selectedCategory == cat ? Color.black : ProTheme.textSecondary)
                                    .background(selectedCategory == cat ? ProTheme.accent : ProTheme.bgSurface)
                                    .cornerRadius(5)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Spacer()

                // Paste Selection List Button (Key Feature for Photographers)
                Button {
                    treeState.showingSelectionFilterSheet = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "checklist.checked")
                            .font(.system(size: 11, weight: .bold))
                        Text("Paste Selection List")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(ProTheme.accent.opacity(0.18))
                    .foregroundColor(ProTheme.accent)
                    .cornerRadius(5)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(ProTheme.accent.opacity(0.4), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("Paste numbers like 8024, 8025 or full filenames from client lists")

                // Search field (supports comma-separated queries like '8024, 8025')
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(ProTheme.textMuted)
                        .font(.system(size: 11))
                    TextField("Search or 8024, 8025...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundColor(ProTheme.textPrimary)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(ProTheme.textMuted)
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(ProTheme.bgDarkest)
                .cornerRadius(5)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(ProTheme.borderSubtle, lineWidth: 1))
                .frame(width: 170)

                // Quick Select All / None toggles
                HStack(spacing: 2) {
                    Button("All") { setAllSelection(selected: true) }
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .foregroundColor(ProTheme.textSecondary)

                    Text("|")
                        .font(.system(size: 10))
                        .foregroundColor(ProTheme.border)

                    Button("None") { setAllSelection(selected: false) }
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .foregroundColor(ProTheme.textSecondary)
                }
                .background(ProTheme.bgSurface)
                .cornerRadius(4)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(ProTheme.bgDark)

            Divider().background(ProTheme.borderSubtle)

            // Tree List
            if let root = rootItem {
                List {
                    DriveItemRow(item: Binding(
                        get: { self.rootItem ?? root },
                        set: { self.rootItem = $0 }
                    ), filterCategory: selectedCategory, searchText: searchText)
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .background(ProTheme.bgDarkest)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 32))
                        .foregroundColor(ProTheme.textMuted)
                    Text("No files loaded yet")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(ProTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $treeState.showingSelectionFilterSheet) {
            SelectionFilterSheet(rootItem: $rootItem)
        }
    }

    private func setAllSelection(selected: Bool) {
        guard var root = rootItem else { return }
        func update(item: inout DriveItem) {
            item.isSelected = selected
            if var children = item.children {
                for i in 0..<children.count {
                    update(item: &children[i])
                }
                item.children = children
            }
        }
        update(item: &root)
        self.rootItem = root
    }

    private func applyFilter(cat: MediaCategory) {
        guard rootItem != nil else { return }
        toggleSelection(for: &rootItem!, matching: cat)
    }

    private func toggleSelection(for item: inout DriveItem, matching cat: MediaCategory) {
        if item.isFolder {
            if var children = item.children {
                for i in 0..<children.count {
                    toggleSelection(for: &children[i], matching: cat)
                }
                item.children = children
                item.isSelected = children.contains { $0.isSelected }
            }
        } else {
            if cat == .all {
                item.isSelected = true
            } else {
                item.isSelected = (item.mediaCategory == cat)
            }
        }
    }
}

public final class DriveItemRowState: ObservableObject {
    @Published public var isExpanded: Bool = true
    public init() {}
}

public struct DriveItemRow: View {
    @Binding var item: DriveItem
    let filterCategory: MediaCategory
    let searchText: String
    @StateObject private var state = DriveItemRowState()

    public var body: some View {
        if isVisible {
            if item.isFolder {
                DisclosureGroup(isExpanded: $state.isExpanded) {
                    if let children = item.children {
                        ForEach(children.indices, id: \.self) { index in
                            DriveItemRow(
                                item: Binding(
                                    get: { self.item.children?[index] ?? children[index] },
                                    set: { if self.item.children != nil { self.item.children![index] = $0 } }
                                ),
                                filterCategory: filterCategory,
                                searchText: searchText
                            )
                        }
                    }
                } label: {
                    rowContent
                }
            } else {
                rowContent
            }
        }
    }

    private var rowContent: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: $item.isSelected)
                .labelsHidden()
                .toggleStyle(.checkbox)

            Image(systemName: item.iconName)
                .foregroundColor(item.categoryColor)
                .font(.system(size: 13))
                .frame(width: 16)

            Text(item.name)
                .font(.system(size: 12, weight: item.isFolder ? .semibold : .regular))
                .foregroundColor(ProTheme.textPrimary)
                .lineLimit(1)

            Spacer()

            if !item.isFolder, let md5 = item.md5Checksum {
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 10))
                    .foregroundColor(ProTheme.accent.opacity(0.8))
                    .help("Verified Google Drive MD5 Checksum: \(md5)")
            }

            Text(item.formattedSize)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(ProTheme.textMuted)
        }
        .padding(.vertical, 2)
    }

    private var isVisible: Bool {
        if !searchText.isEmpty {
            let tokens = SelectionMatcher.parseTokens(from: searchText)
            if !tokens.isEmpty {
                if item.isFolder {
                    let flat = item.flattenFiles()
                    return flat.contains { file in
                        tokens.contains { token in
                            SelectionMatcher.matches(fileName: file.name, token: token, mode: .smartNumber)
                        }
                    }
                } else {
                    return tokens.contains { token in
                        SelectionMatcher.matches(fileName: item.name, token: token, mode: .smartNumber)
                    }
                }
            }
        }

        if filterCategory == .all { return true }
        if item.isFolder {
            let flat = item.flattenFiles()
            return flat.contains { $0.mediaCategory == filterCategory }
        }
        return item.mediaCategory == filterCategory
    }
}
