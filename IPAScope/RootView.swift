import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @StateObject private var engine = AnalysisEngine()
    @State private var showPicker = false

    var body: some View {
        TabView {
            OverviewTab(engine: engine, onPick: { showPicker = true })
                .tabItem { Label("概览", systemImage: "doc.text.magnifyingglass") }

            SectionsTab(engine: engine)
                .tabItem { Label("结构", systemImage: "square.split.2x2") }

            ClassesTab(engine: engine)
                .tabItem { Label("符号", systemImage: "c.circle") }

            StringsTab(engine: engine)
                .tabItem { Label("字符串", systemImage: "textformat") }

            ProvisionTab(engine: engine)
                .tabItem { Label("签名", systemImage: "checkmark.seal") }
        }
        .fileImporter(isPresented: $showPicker,
                      allowedContentTypes: [UTType.data],
                      allowsMultipleSelection: false) { res in
            if case .success(let urls) = res, let u = urls.first {
                engine.open(url: u)
            }
        }
    }
}
