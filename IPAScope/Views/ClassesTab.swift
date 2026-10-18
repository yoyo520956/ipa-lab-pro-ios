import SwiftUI

struct ClassesTab: View {
    @ObservedObject var engine: AnalysisEngine
    @State private var mode = 0          // 0=类 1=方法 2=全部符号
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
            .navigationTitle("符号")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var emptyHint: some View {
        VStack(spacing: 8) {
            Image(systemName: "c.circle")
                .font(.system(size: 30))
                .foregroundStyle(.tertiary)
            Text("先在「概览」选择 IPA")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var listArea: some View {
        VStack(spacing: 0) {
            Picker("来源", selection: $mode) {
                Text("类 \(engine.result.classNames.count)").tag(0)
                Text("方法 \(engine.result.methodNames.count)").tag(1)
                Text("符号 \(engine.result.symbols.count)").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 14)
            .padding(.top, 8)

            TextField("搜索…", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(12)

            rowList()
        }
    }

    private func rowList() -> some View {
        List {
            rows(Repos.filtered(source(mode), query))
        }
        .listStyle(.plain)
    }

    private func rows(_ items: [StringItem]) -> some View {
        ForEach(items) { item in
            VStack(alignment: .leading, spacing: 1) {
                Text(item.text)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(2)
            }
            .padding(.vertical, 2)
        }
    }

    private func source(_ m: Int) -> [String] {
        if m == 0 { return engine.result.classNames }
        if m == 1 { return engine.result.methodNames }
        return engine.result.symbols
    }
}

// MARK: - 行模型 + 过滤（链式形态收口处）

struct StringItem: Identifiable, Hashable {
    let id: Int
    let text: String
}

enum Repos {
    static func filtered(_ src: [String], _ q: String, cap: Int = 5000) -> [StringItem] {
        let key = q.trimmingCharacters(in: .whitespaces)
        let picked: [String]
        if key.isEmpty {
            picked = src
        } else {
            picked = src.filter { $0.localizedCaseInsensitiveContains(key) }
        }
        return picked.prefix(cap).enumerated().map {
            StringItem(id: $0.offset, text: $0.element)
        }
    }
}
