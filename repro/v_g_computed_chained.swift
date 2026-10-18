import SwiftUI

private struct ArchiveEntry: Identifiable, Hashable {
    var id: String { path }
    var path: String
    var size: UInt64
    var isDirectory: Bool
}

private final class ZipEngine: ObservableObject {
    @Published var entries: [ArchiveEntry] = []
    @Published var filter = ""
}

private struct BundleTab: View {
    @StateObject private var engine = ZipEngine()
    @State private var selectedCategory = "全部"

    var visible: [ArchiveEntry] { engine.entries }
    var visibleCapped: [ArchiveEntry] { Array(visible.prefix(3000)) }

    var body: some View {
        List {
            ForEach(visibleCapped.map { $0 }, id: \.self) { entry in
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
    }
}
