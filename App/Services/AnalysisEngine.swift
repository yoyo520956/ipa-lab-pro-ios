//
//  AnalysisEngine.swift
//  IPA Lab Pro
//  分析任务编排：分阶段执行 + 进度 + 取消 + 检查点（低性能模式断点恢复）
//

import Foundation
import ZIPFoundation
import Combine

enum AnalysisPhase: String, CaseIterable {
    case validating = "验证 IPA"
    case extracting = "解包资源"
    case locating = "定位二进制"
    case macho = "Mach-O 结构解析"
    case strings = "字符串提取"
    case objc = "ObjC 元数据"
    case done = "完成"
}

@MainActor
final class AnalysisEngine: ObservableObject {
    @Published var phase: AnalysisPhase = .validating
    @Published var progress: Double = 0
    @Published var isRunning = false
    @Published var log: [String] = []
    @Published var bundleSummary = BundleSummary()
    @Published var machOInfo: MachOInfo?
    @Published var strings: [StringEntry] = []
    @Published var objc: ObjCMetadataInfo?
    @Published var errorMessage: String?

    private var task: Task<Void, Never>?
    let project: AnalysisProject
    var config: AnalysisConfig
    private(set) var performanceMode: PerformanceMode

    var projectDir: URL { ProjectStore.shared.directory(for: project) }
    var ipaURL: URL { projectDir.appendingPathComponent("original.ipa") }
    var extractDir: URL { projectDir.appendingPathComponent("extracted") }
    var checkpointURL: URL { projectDir.appendingPathComponent("checkpoint.json") }

    init(project: AnalysisProject, config: AnalysisConfig, compat: CompatReport?) {
        self.project = project
        self.config = config
        self.performanceMode = AnalysisConfig.effectiveMode(for: config, compat: compat)
    }

    func addLog(_ s: String) {
        let line = "[\(Self.timeText())] \(s)"
        log.append(line)
        if log.count > 2000 { log.removeFirst(log.count - 2000) }
        if config.logLevel >= 1 {
            let logURL = projectDir.appendingPathComponent("analysis.log")
            if let handle = FileHandle(forWritingAtPath: logURL.path) {
                handle.seekToEndOfFile()
                handle.write((line + "\n").data(using: .utf8) ?? Data())
                try? handle.close()
            } else {
                try? (line + "\n").write(to: logURL, atomically: true, encoding: .utf8)
            }
        }
    }

    static func timeText() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: Date())
    }

    // MARK: - 启动 / 取消

    func start() {
        guard !isRunning else { return }
        isRunning = true
        errorMessage = nil
        let compatAdjusted = performanceMode
        addLog("性能模式：\(compatAdjusted.rawValue)（自动调整：\(config.autoAdjust ? "开" : "关")）")
        task = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.runAllPhases()
                self.phase = .done
                self.progress = 1
                self.isRunning = false
                self.addLog("分析完成")
                var p = self.project
                p.status = "done"
                p.statusMessage = "分析完成"
                ProjectStore.shared.update(p)
            } catch is CancellationError {
                self.isRunning = false
                self.addLog("⏹ 已取消")
                var p = self.project
                p.status = "cancelled"
                p.statusMessage = "已取消"
                ProjectStore.shared.update(p)
            } catch {
                self.isRunning = false
                self.errorMessage = error.localizedDescription
                self.addLog("错误：\(error.localizedDescription)")
                var p = self.project
                p.status = "failed"
                p.statusMessage = error.localizedDescription
                ProjectStore.shared.update(p)
            }
        }
    }

    func cancel() {
        task?.cancel()
    }

    private func checkCancelled() throws {
        if Task.isCancelled { throw CancellationError() }
    }

    // MARK: - 阶段执行

    private func runAllPhases() async throws {
        // 断点恢复：读取检查点
        var checkpoint = (try? Data(contentsOf: checkpointURL))
            .flatMap { try? JSONDecoder().decode(AnalysisCheckpoint.self, from: $0) }
        if let cp = checkpoint, !cp.completedPhases.isEmpty {
            addLog("发现检查点（\(cp.completedPhases.joined(separator: "→"))），从断点恢复")
            bundleSummary = cp.bundle ?? BundleSummary()
            machOInfo = cp.machOInfo
            strings = cp.strings ?? []
            objc = cp.objc
        }

        let zip = ZipService(config: config)
        let macho = MachOService(config: config)
        let objcSvc = ObjCMetadataService(config: config)

        if !(checkpoint?.completedPhases.contains(AnalysisPhase.validating.rawValue) ?? false) {
            phase = .validating
            addLog("验证 IPA 完整性…")
            _ = try Archive(url: ipaURL, accessMode: .read) // 打开即验证中央目录
            try checkCancelled()
            markPhase(.validating, &checkpoint)
        }

        if !(checkpoint?.completedPhases.contains(AnalysisPhase.extracting.rawValue) ?? false) {
            phase = .extracting
            addLog("解包中（串行分块 · 单文件上限 \(ByteCountFormatter.string(fromByteCount: zip.maxEntrySize, countStyle: .file))）…")
            try? FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
            try zip.extractAll(at: ipaURL, to: extractDir) { [weak self] p in
                Task { @MainActor in self?.progress = p * 0.4 }
            } isCancelled: { [weak self] in Task.isCancelled }
            try checkCancelled()
            markPhase(.extracting, &checkpoint)
        }

        var binaryURL: URL?
        if !(checkpoint?.completedPhases.contains(AnalysisPhase.locating.rawValue) ?? false) {
            phase = .locating
            try checkCancelled()
            binaryURL = try locateMainBinary()
            guard let bin = binaryURL else {
                throw NSError(domain: "AnalysisEngine", code: 10, userInfo: [NSLocalizedDescriptionKey: "未找到主可执行文件（Payload/*.app/ 下无匹配二进制）"])
            }
            try parseBundleSummary(binaryURL: bin)
            markPhase(.locating, &checkpoint)
        } else {
            binaryURL = try locateMainBinary()
        }
        guard let binaryURL else { return }

        if !(checkpoint?.completedPhases.contains(AnalysisPhase.macho.rawValue) ?? false) {
            phase = .macho
            addLog("Mach-O 结构解析：\(binaryURL.lastPathComponent)")
            try checkCancelled()
            let t0 = Date()
            let info = try macho.parseFile(at: binaryURL)
            machOInfo = info
            addLog("解析完成：\(info.loadCommands.count) 条加载命令 · \(info.segments.count) 段 · \(info.symbols.count) 符号 · \(String(format: "%.1f", Date().timeIntervalSince(t0)))s")
            bundleSummary.binarySizeBytes = DirectoryUtils.directorySize(binaryURL.deletingLastPathComponent()) > 0 ? Int64(FileManager.default.fileSize(atPath: binaryURL.path) ?? 0) : 0
            bundleSummary.architectures = [info.cputype]
            markPhase(.macho, &checkpoint)
        }

        if !(checkpoint?.completedPhases.contains(AnalysisPhase.strings.rawValue) ?? false) {
            phase = .strings
            addLog("字符串扫描（分块 \(config.performanceMode.scanChunkSize / 1024)KB · 上限 \(config.performanceMode.stringLimit) 条）…")
            guard let info = machOInfo else { return }
            try checkCancelled()
            strings = try macho.scanStrings(at: binaryURL, machO: info) { [weak self] p in
                Task { @MainActor in self?.progress = 0.4 + p * 0.4 }
            } isCancelled: { Task.isCancelled }
            addLog("提取字符串 \(strings.count) 条")
            markPhase(.strings, &checkpoint)
        }

        if !(checkpoint?.completedPhases.contains(AnalysisPhase.objc.rawValue) ?? false) {
            phase = .objc
            try checkCancelled()
            objc = objcSvc.analyze(at: binaryURL, machO: machOInfo ?? MachOInfo())
            addLog("ObjC：\(objc?.parseNote ?? "无")")
            markPhase(.objc, &checkpoint)
        }

        // 汇总包信息
        if bundleSummary.entryCount == 0 {
            let entries = (try? zip.listEntries(at: ipaURL)) ?? []
            bundleSummary.entryCount = entries.count
            bundleSummary.appSizeBytes = DirectoryUtils.directorySize(extractDir)
            bundleSummary.frameworks = Array(Set(entries.filter { $0.category == "框架" }.compactMap { e in
                e.path.components(separatedBy: "/").first(where: { $0.hasSuffix(".framework") })
            })).sorted()
            bundleSummary.plugins = Array(Set(entries.filter { $0.category == "扩展插件" }.compactMap { e in
                e.path.components(separatedBy: "/").first(where: { $0.hasSuffix(".appex") })
            })).sorted()
        }
        saveCheckpoint(checkpoint, force: true)
    }

    private func markPhase(_ p: AnalysisPhase, _ checkpoint: inout AnalysisCheckpoint?) {
        var cp = checkpoint ?? AnalysisCheckpoint(phase: p.rawValue)
        cp.completedPhases.append(p.rawValue)
        cp.phase = p.rawValue
        cp.updatedAt = Date()
        cp.bundle = bundleSummary
        cp.machOInfo = machOInfo
        cp.strings = performanceMode.checkpointEveryPhase ? strings : nil // 低性能模式全量落盘
        cp.objc = objc
        checkpoint = cp
        saveCheckpoint(cp, force: performanceMode.checkpointEveryPhase)
    }

    private func saveCheckpoint(_ cp: AnalysisCheckpoint?, force: Bool) {
        guard let cp else { return }
        if let data = try? JSONEncoder().encode(cp) {
            try? data.write(to: checkpointURL, options: .atomic)
        }
    }

    // MARK: - 定位主二进制 + 包摘要

    func locateMainBinary() throws -> URL? {
        // Payload/<Name>.app/<Name>
        guard let en = FileManager.default.enumerator(at: extractDir, includingPropertiesForKeys: [.isRegularFileKey]) else { return nil }
        var candidates: [URL] = []
        for case let f as URL in en {
            guard f.lastPathComponent == InfoPlistParser.executableHint else { continue }
            if f.pathExtension == "app" { continue }
            candidates.append(f)
        }
        // 直接解析 Info.plist 更可靠
        guard let infoPlist = findInfoPlist() else { return candidates.first }
        guard let exeName = InfoPlistParser.value(forKey: "CFBundleExecutable", in: infoPlist) as? String else { return candidates.first }
        let appDir = infoPlist.deletingLastPathComponent()
        let bin = appDir.appendingPathComponent(exeName)
        return FileManager.default.fileExists(atPath: bin.path) ? bin : candidates.first
    }

    func findInfoPlist() -> URL? {
        guard let en = FileManager.default.enumerator(at: extractDir, includingPropertiesForKeys: nil) else { return nil }
        for case let f as URL in en where f.lastPathComponent == "Info.plist" {
            // 主 app 的 Info.plist 在 Payload/X.app/Info.plist（非 framework/plug-in 内）
            let rel = f.path.replacingOccurrences(of: extractDir.path + "/", with: "")
            if rel.hasPrefix("Payload/"), rel.components(separatedBy: "/").count == 3 {
                return f
            }
        }
        return nil
    }

    func parseBundleSummary(binaryURL: URL) throws {
        guard let plist = findInfoPlist() else { return }
        let dict = InfoPlistParser.parse(plist)
        bundleSummary.displayName = dict["CFBundleDisplayName"] as? String ?? dict["CFBundleName"] as? String ?? ""
        bundleSummary.bundleIdentifier = dict["CFBundleIdentifier"] as? String ?? ""
        bundleSummary.version = dict["CFBundleShortVersionString"] as? String ?? ""
        bundleSummary.buildVersion = dict["CFBundleVersion"] as? String ?? ""
        bundleSummary.minOSVersion = dict["MinimumOSVersion"] as? String ?? ""
        bundleSummary.executableName = dict["CFBundleExecutable"] as? String ?? ""
        bundleSummary.platformName = dict["DTPlatformName"] as? String ?? ""
        bundleSummary.sdkName = dict["DTSDKName"] as? String ?? ""
        bundleSummary.appSizeBytes = DirectoryUtils.directorySize(extractDir)
        bundleSummary.binarySizeBytes = Int64(FileManager.default.fileSize(atPath: binaryURL.path) ?? 0)
        addLog("包：\(bundleSummary.displayName) \(bundleSummary.version)(\(bundleSummary.buildVersion)) · \(bundleSummary.bundleIdentifier)")
    }

    /// 分析产物数据库（近似工程结构重建：按类别归组的真实文件树）
    func approximatedProjectStructure() -> [String: [String]] {
        let entries = (try? ZipService(config: config).listEntries(at: ipaURL)) ?? []
        var groups: [String: [String]] = [:]
        for e in entries where !e.isDirectory {
            groups[e.category, default: []].append(e.path)
        }
        return groups
    }
}

extension FileManager {
    func fileSize(atPath path: String) -> Int? {
        (try? attributesOfItem(atPath: path))?[.size] as? Int
    }
}

enum InfoPlistParser {
    static let executableHint = "__EXEC_HINT__" // 占位（未用）

    static func parse(_ url: URL) -> [String: Any] {
        guard let data = try? Data(contentsOf: url), let dict = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else { return [:] }
        return dict
    }

    static func value(forKey key: String, in url: URL) -> Any? {
        parse(url)[key]
    }
}
