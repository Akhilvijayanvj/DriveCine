import SwiftUI

public struct FileTreeView: View {
    @Binding public var rootItem: DriveItem?
    @Binding public var selectedCategory: MediaCategory
    @Binding public var searchText: String

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
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .foregroundColor(selectedCategory == cat ? Color.black : ProTheme.textSecondary)
                                    .background(selectedCategory == cat ? ProTheme.accent : ProTheme.bgSurface)
                                    .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Spacer()

                // Search field
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(ProTheme.textMuted)
                        .font(.system(size: 11))
                    TextField("Search footage...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
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
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(ProTheme.borderSubtle, lineWidth: 1))
                .frame(width: 180)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
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
            if item.name.localizedCaseInsensitiveContains(searchText) { return true }
            if item.isFolder {
                let flat = item.flattenFiles()
                return flat.contains { $0.name.localizedCaseInsensitiveContains(searchText) }
            }
            return false
        }

        if filterCategory == .all { return true }
        if item.isFolder {
            let flat = item.flattenFiles()
            return flat.contains { $0.mediaCategory == filterCategory }
        }
        return item.mediaCategory == filterCategory
    }
}
