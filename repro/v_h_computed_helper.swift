import SwiftUI

private struct ArchiveEntry2: Identifiable, Hashable {
    var id: String { path }
    var path: String
    var size: UInt64
    var isDirectory: Bool
}

private final class ZipEngine2: ObservableObject {
    @Published var entries: [ArchiveEntry2] = []
    @Published var filter = ""
}

private struct BundleTab2: View {
    @StateObject private var engine = ZipEngine2()
    @State private var selectedCategory = "全部"

    var visible: [ArchiveEntry2] { engine.entries }
    var visibleCapped: [ArchiveEntry2] { Array(visible.prefix(3000)) }

    private func entryRows(_ list: [ArchiveEntry2]) -> some View {
        ForEach(list, id: \.self) { entry in
            HStack(spacing: 10) {
                Image(systemName: "doc")
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text((entry.path as NSString).lastPathComponent)
                        .font(.footnote)
                        .lineLimit(1)
                }
            }
        }
    }

    var body: some View {
        List {
            entryRows(visibleCapped)
        }
    }
}
