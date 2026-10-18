import SwiftUI

struct StringsTab: View {
    @ObservedObject var engine: AnalysisEngine
    @State private var query = ""

    var body: some View {
        NavigationStack {
            Group {
                if engine.phase == .done {
                    listArea
                } else {
                    emptyHint
                }
            }
            .navigationTitle("字符串")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var emptyHint: some View {
        VStack(spacing: 8) {
            Image(systemName: "textformat")
                .font(.system(size: 30))
                .foregroundStyle(.tertiary)
            Text("先在「概览」选择 IPA")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var listArea: some View {
        VStack(spacing: 0) {
            Text("共 \(engine.result.cstrings.count) 条（__cstring / ObjC / 符号名，去重后）")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.top, 8)

            TextField("搜索 URL / 域名 / 接口…", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(12)

            List {
                rows(Repos.filtered(engine.result.cstrings, query, cap: 8000))
            }
            .listStyle(.plain)
        }
    }

    private func rows(_ items: [StringItem]) -> some View {
        ForEach(items) { item in
            Text(item.text)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(3)
        }
    }
}
