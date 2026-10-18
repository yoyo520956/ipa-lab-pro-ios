//
//  StringsTab.swift + DisasmTab.swift + ObjCTab.swift + ReportTab.swift
//  IPA Lab Pro
//

import SwiftUI
import MachOKit

// MARK: - 字符串页

struct StringsTab: View {
    @ObservedObject var engine: AnalysisEngine
    @State private var filter = ""
    @State private var sectionFilter = "全部"

    var sections: [String] {
        ["全部"] + Array(Set(engine.strings.map(\.section))).sorted()
    }

    var visible: [StringEntry] {
        var list = engine.strings
        if sectionFilter != "全部" { list = list.filter { $0.section == sectionFilter } }
        if !filter.isEmpty {
            let q = filter.lowercased()
            list = list.filter { $0.value.lowercased().contains(q) }
        }
        return list
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("搜索字符串", text: $filter)
                    .textFieldStyle(.roundedBorder)
                Picker("", selection: $sectionFilter) {
                    ForEach(sections, id: \.self) { Text($0) }
                }
                .pickerStyle(.menu)
            }
            .padding(.horizontal)
            .padding(.bottom, 6)

            Text("共 \(engine.strings.count) 条 · 显示前 \(min(visible.count, 3000))")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

            List(visible.prefix(3000)) { s in
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.value)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(2)
                    Text("[\(s.section)] file 0x\(String(s.fileOffset, radix: 16)) · len \(s.length)")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .textSelection(.enabled)
            }
            .listStyle(.plain)
        }
    }
}

// MARK: - 反汇编页

struct DisasmTab: View {
    @ObservedObject var engine: AnalysisEngine
    @State private var selectedSymbol: MachOSymbolInfo?
    @State private var manualOffset = ""
    @State private var count = 200
    @State private var instructions: [InstructionEntry] = []
    @State private var running = false
    @State private var errorText: String?
    @State private var showPseudocode = false

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("起始符号").font(.caption).foregroundStyle(.secondary)
                Menu(selectedSymbol.map { "\($0.demangled == $0.name ? $0.name : $0.demangled) 0x\(String($0.address, radix: 16))" } ?? "选择符号") {
                    if let m = engine.machOInfo {
                        ForEach(m.symbols.filter { $0.address > 0 }.prefix(500)) { s in
                            Button("\(s.demangled == s.name ? s.name : s.demangled) (0x\(String(s.address, radix: 16)))") {
                                selectedSymbol = s
                            }
                        }
                    }
                }
                .font(.caption)
                Spacer()
                TextField("条数", value: $count, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                    .keyboardType(.numberPad)
            }
            .padding(.horizontal)

            if let m = engine.machOInfo, !m.isEncrypted {
                Text("近·似·伪·代·码 \(showPseudocode ? "开" : "关")（指令直译，非反编译器输出）")
                    .font(.caption2).foregroundStyle(.orange)
            }

            if running { ProgressView().padding() }
            if let e = errorText {
                Text(e).font(.caption).foregroundStyle(DS.red)
            }

            if engine.machOInfo?.isEncrypted == true {
                ContentUnavailableCompatView(text: "主二进制带 App Store 加密（cryptid=1）。文件态的密文段无法反汇编；仅可分析未加密部分。本地静态分析不会也不应解密。")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        if showPseudocode {
                            let pseudoLines = DisasmService.pseudocode(for: instructions)
                            ForEach(Array(pseudoLines.enumerated()), id: \.offset) { pair in
                                Text(pair.element)
                                    .font(.system(.caption2, design: .monospaced))
                                    .textSelection(.enabled)
                                if pair.offset < instructions.count {
                                    Text("0x\(String(instructions[pair.offset].address, radix: 16))").font(.system(.micro, design: .monospaced)).foregroundStyle(.tertiary)
                                }
                            }
                        } else {
                            ForEach(instructions) { insn in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("0x\(String(insn.address, radix: 16))")
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(DS.accent)
                                        .frame(width: 80, alignment: .leading)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text("\(insn.mnemonic) \(insn.operands)")
                                            .font(.system(.caption, design: .monospaced))
                                        if !insn.bytes.isEmpty {
                                            Text(insn.bytes).font(.system(.micro, design: .monospaced)).foregroundStyle(.tertiary)
                                        }
                                    }
                                    .textSelection(.enabled)
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .padding(.top, 4)
        .onAppear {
            if selectedSymbol == nil, let m = engine.machOInfo {
                selectedSymbol = m.symbols.first { $0.address > 0 }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    run()
                } label: {
                    Image(systemName: "play.fill")
                }
                .disabled(running || engine.machOInfo == nil)
            }
        }
    }

    @MainActor
    private func run() {
        guard let m = engine.machOInfo, let bin = try? engine.locateMainBinary() else { return }
        let startVM: UInt64
        let fileOff: UInt64
        if let s = selectedSymbol {
            startVM = s.address
            fileOff = MachOService.fileOffset(for: s.address, segments: m.segments) ?? 0
        } else {
            startVM = m.segments.first?.vmAddress ?? 0
            fileOff = m.segments.first?.fileOffset ?? 0
        }
        running = true
        errorText = nil
        instructions = []
        let config = engine.config      // MainActor 上取快照
        let req = DisasmRequest(
            arch: m.cputype.contains("ARM64") ? CS_ARCH_ARM64 : CS_ARCH_ARM,
            mode: CS_MODE_LITTLE_ENDIAN,
            startAddress: startVM,
            fileOffset: fileOff,
            maxInstructions: count
        )
        Task.detached {
            let svc = DisasmService(config: config)   // 闭包内新建，class 不跨隔离传递
            let result = (try? svc.disassemble(at: bin, request: req)) ?? []
            await MainActor.run {
                instructions = result
                running = false
                if result.isEmpty { errorText = "该位置无可反汇编内容" }
            }
        }
    }
}

// MARK: - ObjC 页

struct ObjCTab: View {
    @ObservedObject var engine: AnalysisEngine
    @State private var filter = ""

    var body: some View {
        VStack(spacing: 0) {
            TextField("筛选类名 / 选择器", text: $filter)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
                .padding(.bottom, 6)

            if let o = engine.objc {
                List {
                    Section("解析说明") {
                        Text(o.parseNote).font(.caption).foregroundStyle(.secondary)
                    }
                    if !o.classNames.isEmpty {
                        Section("类名（\(o.classNames.count)）") {
                            ForEach(o.classNames.filter { filter.isEmpty || $0.localizedCaseInsensitiveContains(filter) }.prefix(1000), id: \.self) { n in
                                Text(n).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            }
                        }
                    }
                    if !o.categories.isEmpty {
                        Section("分类（\(o.categories.count)）") {
                            ForEach(o.categories.prefix(500), id: \.self) { n in
                                Text(n).font(.system(.caption, design: .monospaced))
                            }
                        }
                    }
                    if !o.selectors.isEmpty {
                        Section("选择器（\(o.selectors.count)）") {
                            ForEach(o.selectors.filter { filter.isEmpty || $0.localizedCaseInsensitiveContains(filter) }.prefix(1500), id: \.self) { s in
                                Text(s).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            }
                        }
                    }
                }
            } else {
                ContentUnavailableCompatView(text: "ObjC 元数据尚未解析完成")
            }
        }
    }
}

// MARK: - 报告页

struct ReportTab: View {
    @ObservedObject var engine: AnalysisEngine
    @State private var exportedURL: URL?
    @State private var showShare = false
    @State private var errorText: String?
    @State private var structure: [String: [String]] = [:]

    var body: some View {
        List {
            Section("导出") {
                Button {
                    export("txt")
                } label: {
                    Label("导出 TXT 报告", systemImage: "doc.plaintext")
                }
                Button {
                    export("json")
                } label: {
                    Label("导出 JSON 报告", systemImage: "curlybraces.square")
                }
                if let e = errorText {
                    Text(e).font(.caption).foregroundStyle(DS.red)
                }
            }

            Section("近似工程结构（按类别归组，自动重建）") {
                ForEach(structure.keys.sorted(), id: \.self) { key in
                    DisclosureGroup("\(key)（\(structure[key]?.count ?? 0)）") {
                        ForEach((structure[key] ?? []).prefix(50), id: \.self) { p in
                            Text(p).font(.system(.caption2, design: .monospaced)).lineLimit(1)
                        }
                        if (structure[key]?.count ?? 0) > 50 {
                            Text("…其余 \(structure[key]!.count - 50) 项")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                Text("说明：编译会丢失源码布局、注释与局部变量名；此结构为从包内容自动重建的近似视图，不代表原始工程。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            structure = engine.approximatedProjectStructure()
        }
        .sheet(isPresented: $showShare) {
            if let url = exportedURL {
                ShareSheetCompat(url: url)
            }
        }
    }

    private func export(_ fmt: String) {
        do {
            let url = try ReportService(engine: engine).export(format: fmt)
            exportedURL = url
            showShare = true
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }
}

struct ShareSheetCompat: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
