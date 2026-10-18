//
//  ReportService.swift
//  IPA Lab Pro
//  分析报告导出：TXT / JSON（内容全部来自真实分析结果）
//

import Foundation

final class ReportService {
    let engine: AnalysisEngine

    init(engine: AnalysisEngine) { self.engine = engine }

    func buildTextReport() -> String {
        var lines: [String] = []
        lines.append("IPA Lab Pro 分析报告")
        lines.append("项目：\(engine.project.name)")
        lines.append("生成时间：\(DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .short))")
        lines.append("性能模式：\(engine.performanceMode.rawValue)")
        lines.append("")
        let b = engine.bundleSummary
        lines.append("== 包信息 ==")
        lines.append("名称：\(b.displayName) · 版本：\(b.version)(\(b.buildVersion))")
        lines.append("Bundle ID：\(b.bundleIdentifier)")
        lines.append("最低系统：iOS \(b.minOSVersion) · SDK：\(b.sdkName)")
        lines.append("条目数：\(b.entryCount) · 包大小：\(DirectoryUtils.byteText(b.appSizeBytes)) · 主二进制：\(DirectoryUtils.byteText(b.binarySizeBytes))")
        if !b.frameworks.isEmpty { lines.append("框架：\(b.frameworks.joined(separator: ", "))") }
        if !b.plugins.isEmpty { lines.append("插件：\(b.plugins.joined(separator: ", "))") }
        if let m = engine.machOInfo {
            lines.append("")
            lines.append("== Mach-O ==")
            lines.append("magic：\(m.magic) · 架构：\(m.cputype) · 类型：\(m.fileType)")
            lines.append("加载命令：\(m.ncmds) 条（\(m.sizeofcmds) 字节）")
            lines.append("段：\(m.segments.count) · 节：\(m.sections.count) · 符号：\(m.symbols.count) · 函数起点：\(m.functionStarts.count)")
            lines.append("代码签名：\(m.codeSigned ? "有" : "无") · 加密：\(m.isEncrypted ? "是（cryptid=\(m.cryptId)，App Store 竖屏包需注意仅本地静态分析可见明文部分）" : "否")")
            lines.append("链式修复：\(m.hasChainedFixups ? "有" : "无")")
            lines.append("")
            lines.append("== 段列表 ==")
            for s in m.segments {
                lines.append("\(s.name): vm=0x\(String(s.vmAddress, radix: 16)) size=0x\(String(s.vmSize, radix: 16)) prot=\(s.initProtection)")
            }
            if !m.linkedDylibs.isEmpty {
                lines.append("")
                lines.append("== 依赖动态库 ==")
                m.linkedDylibs.forEach { lines.append($0) }
            }
        }
        lines.append("")
        lines.append("== 字符串 ==")
        lines.append("共 \(engine.strings.count) 条（前 200 条）")
        for s in engine.strings.prefix(200) {
            lines.append("[\(s.section)] 0x\(String(s.fileOffset, radix: 16)) \(s.value.prefix(200))")
        }
        if let o = engine.objc {
            lines.append("")
            lines.append("== ObjC ==")
            lines.append(o.parseNote)
            lines.append("类名（前 100）：\(o.classNames.prefix(100).joined(separator: ", "))")
        }
        lines.append("")
        lines.append("== 分析日志 ==")
        engine.log.forEach { lines.append($0) }
        return lines.joined(separator: "\n")
    }

    @discardableResult
    func export(format: String) throws -> URL {
        let dir = engine.projectDir.appendingPathComponent("reports")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = Int(Date().timeIntervalSince1970)
        let url: URL
        if format == "json" {
            var payload: [String: Any] = [
                "project": engine.project.name,
                "generatedAt": ISO8601DateFormatter().string(from: Date()),
                "performanceMode": engine.performanceMode.rawValue,
                "bundle": [
                    "displayName": engine.bundleSummary.displayName,
                    "bundleIdentifier": engine.bundleSummary.bundleIdentifier,
                    "version": engine.bundleSummary.version,
                    "entryCount": engine.bundleSummary.entryCount
                ],
                "macho": engine.machOInfo.map { m in
                    [
                        "magic": m.magic, "cputype": m.cputype, "fileType": m.fileType,
                        "segments": m.segments.map { ["name": $0.name, "vmSize": String($0.vmSize)] },
                        "linkedDylibs": m.linkedDylibs,
                        "codeSigned": m.codeSigned, "isEncrypted": m.isEncrypted
                    ] as [String: Any]
                } ?? [:],
                "stringsCount": engine.strings.count,
                "strings": engine.strings.prefix(2000).map { ["value": $0.value, "section": $0.section, "offset": String($0.fileOffset)] }
            ]
            if let o = engine.objc {
                payload["objc"] = ["classNames": Array(o.classNames.prefix(2000)), "selectors": Array(o.selectors.prefix(5000)), "note": o.parseNote]
            }
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            url = dir.appendingPathComponent("report-\(stamp).json")
            try data.write(to: url, options: .atomic)
        } else {
            url = dir.appendingPathComponent("report-\(stamp).txt")
            try buildTextReport().write(to: url, atomically: true, encoding: .utf8)
        }
        return url
    }
}
