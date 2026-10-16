import SwiftUI

public final class DiskSpaceViewModel: ObservableObject {
    @Published public var availableBytes: Int64 = 0
    @Published public var totalCapacityBytes: Int64 = 0
    @Published public var volumeName: String = "Disk"

    public init() {}

    public func update(path: String) {
        let url = URL(fileURLWithPath: path)
        do {
            let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey, .volumeNameKey])
            self.availableBytes = values.volumeAvailableCapacityForImportantUsage ?? 0
            self.totalCapacityBytes = Int64(values.volumeTotalCapacity ?? 0)
            self.volumeName = values.volumeName ?? url.lastPathComponent
        } catch {
            var stat = statfs()
            if statfs(path, &stat) == 0 {
                self.availableBytes = Int64(stat.f_bavail) * Int64(stat.f_bsize)
                self.totalCapacityBytes = Int64(stat.f_blocks) * Int64(stat.f_bsize)
                self.volumeName = url.lastPathComponent
            }
        }
    }
}

public struct DiskSpaceBar: View {
    public let destinationPath: String
    public let requiredBytes: Int64

    @StateObject private var vm = DiskSpaceViewModel()

    public init(destinationPath: String, requiredBytes: Int64) {
        self.destinationPath = destinationPath
        self.requiredBytes = requiredBytes
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "internaldrive.fill")
                    .foregroundColor(isSpaceSufficient ? ProTheme.accent : ProTheme.danger)

                Text(vm.volumeName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(ProTheme.textPrimary)

                Spacer()

                if requiredBytes > 0 {
                    Text("Required: \(DriveItem.formatBytes(requiredBytes))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(ProTheme.textSecondary)

                    Text("•")
                        .foregroundColor(ProTheme.textMuted)
                }

                Text("Free: \(DriveItem.formatBytes(vm.availableBytes))")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(isSpaceSufficient ? ProTheme.success : ProTheme.danger)
            }

            // Disk allocation visual bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.black.opacity(0.3))
                        .frame(height: 6)

                    let usedRatio = vm.totalCapacityBytes > 0 ? Double(vm.totalCapacityBytes - vm.availableBytes) / Double(vm.totalCapacityBytes) : 0
                    let reqRatio = vm.totalCapacityBytes > 0 ? Double(requiredBytes) / Double(vm.totalCapacityBytes) : 0

                    HStack(spacing: 1) {
                        // Current used
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.gray.opacity(0.5))
                            .frame(width: max(geo.size.width * CGFloat(usedRatio), 0), height: 6)

                        // Required portion
                        if requiredBytes > 0 {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(isSpaceSufficient ? ProTheme.accent : ProTheme.danger)
                                .frame(width: max(geo.size.width * CGFloat(reqRatio), 2), height: 6)
                        }
                    }
                }
            }
            .frame(height: 6)

            if !isSpaceSufficient && requiredBytes > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.octagon.fill")
                        .font(.system(size: 11))
                    Text("Insufficient disk space! Choose an external SSD or free up space.")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(ProTheme.danger)
            }
        }
        .padding(10)
        .background(ProTheme.bgSurface)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSpaceSufficient ? ProTheme.borderSubtle : ProTheme.danger.opacity(0.5), lineWidth: 1)
        )
        .onAppear {
            vm.update(path: destinationPath)
        }
        .onChange(of: destinationPath) { _, newPath in
            vm.update(path: newPath)
        }
    }

    private var isSpaceSufficient: Bool {
        guard requiredBytes > 0 else { return true }
        return vm.availableBytes > (requiredBytes + 2 * 1024 * 1024 * 1024)
    }
}
