//
//  BundleTab.swift + MachOTab.swift
//  IPA Lab Pro
//  包内容浏览（ZIP）与 Mach-O 结构页
//

import SwiftUI
import ZIPFoundation

struct BundleTab: View {
    @ObservedObject var engine: AnalysisEngine
    @State private var entries: [ArchiveEntry] = []
    @State private var filter = ""
    @State private var selectedCategory = "全部"
    @State private var loading = false
    @State private var errorText: String?
    @State private var previewEntry: ArchiveEntry?
    @State private var previewText = ""

    var categories: [String] {
        ["全部"] + Array(Set(entries.map(\.category))).sorted()
    }

    var visible: [ArchiveEntry] {
        var list = entries
        if selectedCategory != "全部" { list = list.filter { $0.category == selectedCategory } }
        if !filter.isEmpty {
            let q = filter.lowercased()
            list = list.filter { $0.path.lowercased().contains(q) }
        }
        return list
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("搜索文件名", text: $filter)
                    .textFieldStyle(.roundedBorder)
                Picker("", selection: $selectedCategory) {
                    ForEach(categories, id: \.self) { Text($0) }
                }
                .pickerStyle(.menu)
            }
            .padding(.horizontal)
            .padding(.bottom, 6)

            if loading {
                ProgressView().padding()
            }
            if let e = errorText {
                Text(e).font(.caption).foregroundStyle(DS.red).padding(.horizontal)
            }

            List(visible.prefix(3000), id: \.path) { entry in
                HStack(spacing: 10) {
                    Image(systemName: icon(for: entry))
                        .foregroundStyle(DS.accent)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text((entry.path as NSString).lastPathComponent)
                            .font(.footnote)
                            .lineLimit(1)
                        Text("\(entry.category) · \(entry.isDirectory ? "目录" : DirectoryUtils.byteText(Int64(entry.uncompressedSize)))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !entry.isDirectory {
                        Button("提取") {
                            extractAndPreview(entry)
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                    }
                }
            }
            .listStyle(.plain)
        }
        .onAppear { load() }
        .sheet(isPresented: .init(get: { previewEntry != nil }, set: { if !$0 { previewEntry = nil } })) {
            NavigationStack {
                ScrollView {
                    Text(previewText.isEmpty ? "（二进制或空文件，不显示预览）" : previewText)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding()
                }
                .navigationTitle(previewEntry.map { ($0.path as NSString).lastPathComponent } ?? "")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    private func icon(for e: ArchiveEntry) -> String {
        if e.isDirectory { return "folder" }
        switch e.category {
        case "框架": return "building.blocks"
        case "图像": return "photo"
        case "媒体": return "waveform"
        case "配置": return "gearshape.2"
        case "文本": return "doc.plaintext"
        case "本地化": return "globe"
        case "扩展插件": return "puzzlepiece.extension"
        default: return "doc"
        }
    }

    @MainActor
    private func load() {
        guard entries.isEmpty, !loading else { return }
        loading = true
        errorText = nil
        let config = engine.config      // MainActor 上取快照
        let ipaURL = engine.ipaURL
        Task.detached {
            let list = (try? ZipService(config: config).listEntries(at: ipaURL)) ?? []
            await MainActor.run {
                entries = list
                loading = false
                if list.isEmpty { errorText = "包内容为空或尚未解包完成" }
            }
        }
    }

    @MainActor
    private func extractAndPreview(_ entry: ArchiveEntry) {
        let config = engine.config      // MainActor 上取快照
        let ipaURL = engine.ipaURL
        Task.detached {
            do {
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "_" + (entry.path as NSString).lastPathComponent)
                _ = try ZipService(config: config).extractEntry(named: entry.path, from: ipaURL, to: tmp)
                let lower = entry.path.lowercased()
                var text = ""
                if ["txt", "json", "plist", "xml", "strings", "stringsdict", "md", "html", "css", "js"].contains(where: lower.hasSuffix) {
                    let data = (try? Data(contentsOf: tmp)) ?? Data()
                    text = String(data: data.prefix(200_000), encoding: .utf8) ?? "（无法按文本解码）"
                } else if lower.hasSuffix("info.plist") || entry.category == "配置" {
                    if let data = try? Data(contentsOf: tmp),
                       let obj = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) {
                        text = "\(obj)"
                    }
                }
                await MainActor.run {
                    previewText = text
                    previewEntry = entry
                }
                try? FileManager.default.removeItem(at: tmp)
            } catch {
                await MainActor.run { errorText = error.localizedDescription }
            }
        }
    }
}

// MARK: - Mach-O 页

struct MachOTab: View {
    @ObservedObject var engine: AnalysisEngine
    @State private var subTab = 0
    @State private var symbolFilter = ""

    var body: some View {
        VStack(spacing: 0) {
            Picker("子视图", selection: $subTab) {
                Text("结构").tag(0)
                Text("段/节").tag(1)
                Text("加载命令").tag(2)
                Text("符号").tag(3)
            }
            .pickerStyle(.segmented)
            .padding([.horizontal, .top], 8)

            if engine.machOInfo == nil {
                ContentUnavailableCompatView(text: "尚未完成 Mach-O 解析")
            } else {
                switch subTab {
                case 0: structureView
                case 1: segmentsView
                case 2: loadCommandsView
                default: symbolsView
                }
            }
        }
    }

    private var structureView: some View {
        List {
            if let m = engine.machOInfo {
                Section("文件头") {
                    KVRow(key: "magic", value: m.magic, mono: true)
                    KVRow(key: "cputype", value: m.cputype, mono: true)
                    KVRow(key: "cpusubtype", value: m.cpusubtype, mono: true)
                    KVRow(key: "filetype", value: m.fileType, mono: true)
                    KVRow(key: "ncmds / sizeofcmds", value: "\(m.ncmds) / \(m.sizeofcmds)", mono: true)
                    KVRow(key: "flags", value: m.flags.joined(separator: " "), mono: true)
                }
                Section("安全状态") {
                    KVRow(key: "代码签名", value: m.codeSigned ? "有" : "无")
                    KVRow(key: "App Store 加密 (cryptid)", value: m.isEncrypted ? "是 (\(m.cryptId))" : "否")
                    KVRow(key: "dyld 链式修复", value: m.hasChainedFixups ? "有" : "无")
                    KVRow(key: "函数起点", value: "\(m.functionStarts.count)")
                }
                if !m.linkedDylibs.isEmpty {
                    Section("依赖动态库（\(m.linkedDylibs.count)）") {
                        ForEach(m.linkedDylibs, id: \.self) { d in
                            Text(d).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        }
                    }
                }
            }
        }
    }

    private var segmentsView: some View {
        List {
            if let m = engine.machOInfo {
                Section("段（\(m.segments.count)）") {
                    ForEach(m.segments) { seg in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(seg.name).font(.subheadline.weight(.medium))
                            Text("vm 0x\(String(seg.vmAddress, radix: 16)) + 0x\(String(seg.vmSize, radix: 16)) · file 0x\(String(seg.fileOffset, radix: 16)) + 0x\(String(seg.fileSize, radix: 16)) · prot \(seg.initProtection)/\(seg.maxProtection)")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section("节（\(m.sections.count)，显示前 200）") {
                    ForEach(m.sections.prefix(200)) { sec in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(sec.segmentName),\(sec.sectionName)").font(.system(.caption, design: .monospaced))
                            Text("addr 0x\(String(sec.address, radix: 16)) · size 0x\(String(sec.size, radix: 16)) · off 0x\(String(sec.fileOffset, radix: 16))")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var loadCommandsView: some View {
        List {
            if let m = engine.machOInfo {
                Section("加载命令（\(m.loadCommands.count)）") {
                    ForEach(m.loadCommands) { cmd in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(cmd.name).font(.system(.caption, design: .monospaced).weight(.medium))
                                Spacer()
                                Text("cmd #\(cmd.id + 1)").font(.caption2).foregroundStyle(.secondary)
                            }
                            if !cmd.detail.isEmpty {
                                Text(cmd.detail).font(.system(.caption2, design: .monospaced)).foregroundStyle(DS.accent).textSelection(.enabled)
                            }
                        }
                    }
                }
            }
        }
    }

    private var symbolsView: some View {
        VStack(spacing: 0) {
            TextField("搜索符号（含反混淆名）", text: $symbolFilter)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
                .padding(.bottom, 6)
            if let m = engine.machOInfo {
                let filtered: [MachOSymbolInfo] = {
                    guard !symbolFilter.isEmpty else { return m.symbols }
                    let q = symbolFilter.lowercased()
                    return m.symbols.filter { $0.name.lowercased().contains(q) || $0.demangled.lowercased().contains(q) }
                }()
                List(Array(filtered.prefix(4000))) { s in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.demangled == s.name ? s.name : s.demangled)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(2)
                        HStack {
                            Text("0x\(String(s.address, radix: 16))").font(.system(.caption2, design: .monospaced)).foregroundStyle(DS.accent)
                            Text(s.type).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .textSelection(.enabled)
                }
                .listStyle(.plain)
            }
        }
    }
}

struct ContentUnavailableCompatView: View {
    let text: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "hourglass").font(.largeTitle).foregroundStyle(.secondary)
            Text(text).font(.footnote).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
