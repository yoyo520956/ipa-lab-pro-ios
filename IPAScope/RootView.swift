import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @StateObject private var engine = AnalysisEngine()
    @State private var showPicker = false
    @State private var showImportError = false

    var body: some View {
        TabView {
            OverviewTab(engine: engine, showPicker: $showPicker)
                .tabItem { Label("概览", systemImage: "doc.text.magnifyingglass") }

            SectionsTab(engine: engine)
                .tabItem { Label("结构", systemImage: "square.split.2x2") }

            ClassesTab(engine: engine)
                .tabItem { Label("符号", systemImage: "c.circle") }

            StringsTab(engine: engine)
                .tabItem { Label("字符串", systemImage: "textformat") }

            ResourcesTab(engine: engine)
                .tabItem { Label("资源", systemImage: "folder") }

            DisasmTab(engine: engine)
                .tabItem { Label("汇编", systemImage: "waveform.path") }

            ProvisionTab(engine: engine)
                .tabItem { Label("签名", systemImage: "checkmark.seal") }
        }
        .onAppear {
            engine.refreshImportList()
            if let first = engine.importedURLs.first, engine.pickedURL == nil {
                engine.openLocal(first)
            }
        }
        // 导入通道 1：文件选择器
        .fileImporter(isPresented: $showPicker,
                      allowedContentTypes: [UTType.data],
                      allowsMultipleSelection: false) { res in
            if case .success(let urls) = res, let u = urls.first {
                engine.importFromURL(u)
            }
        }
        // 导入通道 2：文件 App「分享 → 用 IPAScope 打开」
        .onOpenURL { url in
            engine.importFromURL(url)
        }
        // 错误弹窗（选了无法导入等问题可见化）
        .alert("分析失败", isPresented: $showImportError) {
            Button("好", role: .cancel) {}
        } message: {
            if case .failed(let msg) = engine.phase {
                Text(msg)
            }
        }
        .onChange(of: engine.phase) { p in
            if case .failed = p { showImportError = true }
        }
        .overlay(alignment: .top) {
            if let t = engine.toast {
                Text(t)
                    .font(.footnote)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation { engine.toast = nil }
                        }
                    }
            }
        }
    }
}
