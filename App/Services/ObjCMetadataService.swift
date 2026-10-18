//
//  ObjCMetadataService.swift
//  IPA Lab Pro
//  ObjC 元数据分析 v1（字符串层：类名/选择器/分类名，来自 __objc_* section 的真实数据）
//  结构化类/方法树需要 dyld fixup 指针解码，列为 v1.1（见 docs 功能对照表）
//

import Foundation

final class ObjCMetadataService {
    let config: AnalysisConfig

    init(config: AnalysisConfig) { self.config = config }

    /// 提取 ObjC 命名数据：__objc_classname / __objc_methname / __objc_methtype / __objc_catname
    func analyze(at url: URL, machO: MachOInfo, isCancelled: @escaping () -> Bool = { false }) -> ObjCMetadataInfo {
        var result = ObjCMetadataInfo()
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            result.parseNote = "二进制文件读取失败"
            return result
        }
        let limit = config.performanceMode.stringLimit

        func cstrings(inSection name: String, into array: inout [String], cancelled: () -> Bool) {
            guard let sec = machO.sections.first(where: { $0.sectionName == name }), sec.size > 0 else { return }
            let start = Int(sec.fileOffset)
            let end = min(start + Int(sec.size), data.count)
            var i = start
            var buf = [UInt8]()
            while i < end {
                if cancelled() { break }
                let b = data[data.startIndex + i]
                if b != 0 {
                    buf.append(b)
                } else {
                    if !buf.isEmpty, array.count < limit,
                       let s = String(bytes: buf, encoding: .utf8), !s.isEmpty {
                        array.append(s)
                    }
                    buf = []
                }
                i += 1
            }
        }

        cstrings(inSection: "__objc_classname", into: &result.classNames, cancelled: isCancelled)
        cstrings(inSection: "__objc_methname", into: &result.selectors, cancelled: isCancelled)
        cstrings(inSection: "__objc_catname", into: &result.categories, cancelled: isCancelled)

        // __objc_classlist 存在性统计
        let classlistCount = machO.sections.first(where: { $0.sectionName == "__objc_classlist" }).map { Int($0.size / 8) } ?? 0
        let methodlistCount = machO.sections.first(where: { $0.sectionName == "__objc_const" }).map { _ in 0 } ?? 0

        if result.classNames.isEmpty && result.selectors.isEmpty && classlistCount == 0 {
            result.parseNote = "未检测到 ObjC 元数据（可能是纯 Swift 二进制或已剥离）"
        } else {
            var note = "类名 \(result.classNames.count) · 选择器 \(result.selectors.count) · 分类 \(result.categories.count)"
            if classlistCount > 0 { note += " · __objc_classlist 条目 \(classlistCount)" }
            if methodlistCount == 0 { /* 占位 */ }
            if machO.hasChainedFixups {
                note += "。该二进制使用 dyld 链式修复（指针编码态），结构化类/方法树将在 v1.1 通过 fixup 解码提供"
            } else {
                note += "。结构化类/方法树（class_ro_t 解析）将在 v1.1 提供"
            }
            result.parseNote = note
        }
        return result
    }
}
