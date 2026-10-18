//
//  ZipService.swift
//  IPA Lab Pro
//  ZIP 引擎封装（ZIPFoundation 0.9.20 · MIT）
//  含路径穿越防护、大小上限、分块解包、取消支持
//

import Foundation
import ZIPFoundation

enum ZipError: LocalizedError {
    case unsafePath(String)
    case tooLarge(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .unsafePath(let p): return "检测到不安全路径（已拒绝，防路径穿越）：\(p)"
        case .tooLarge(let p): return "文件超出安全大小上限，已跳过：\(p)"
        case .cancelled: return "任务已取消"
        }
    }
}

final class ZipService {
    let config: AnalysisConfig
    /// 单文件解包上限（防压缩炸弹）：低 256MB / 平衡 512MB / 高 1GB
    var maxEntrySize: Int64 {
        switch config.performanceMode {
        case .low: return 256_000_000
        case .balanced: return 512_000_000
        case .high: return 1_000_000_000
        }
    }

    init(config: AnalysisConfig) { self.config = config }

    // MARK: - 自检

    static func selfCheck() -> Bool {
        do {
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("iplab-zip-selfcheck-\(UUID().uuidString).zip")
            defer { try? FileManager.default.removeItem(at: tmp) }
            let src = FileManager.default.temporaryDirectory.appendingPathComponent("iplab-selfcheck-\(UUID().uuidString).txt")
            try Data("IPA Lab Pro zip engine check".utf8).write(to: src)
            defer { try? FileManager.default.removeItem(at: src) }
            let archive = try Archive(url: tmp, accessMode: .create)
            try archive.addEntry(with: src.lastPathComponent, relativeTo: src.deletingLastPathComponent())
            let readBack = try Archive(url: tmp, accessMode: .read)
            guard let entry = readBack.makeIterator().next() else { return false }
            var data = Data()
            _ = try readBack.extract(entry, bufferSize: 64 * 1024) { chunk in data.append(chunk) }
            return String(data: data, encoding: .utf8)?.hasPrefix("IPA Lab Pro") == true
        } catch {
            return false
        }
    }

    // MARK: - 路径安全（防 zip slip）

    static func isSafeEntryPath(_ path: String) -> Bool {
        guard !path.hasPrefix("/"), !path.contains(":") else { return false }
        let normalized = (path as NSString).standardizingPath
        return !normalized.hasPrefix("..") && !normalized.components(separatedBy: "/").contains("..")
    }

    // MARK: - 列表

    func listEntries(at ipaURL: URL) throws -> [ArchiveEntry] {
        let archive = try Archive(url: ipaURL, accessMode: .read)
        var out: [ArchiveEntry] = []
        var seenDirs = Set<String>()
        for entry in archive {
            let path = entry.path
            if !Self.isSafeEntryPath(path) { continue }
            let isDir = entry.type == .directory
            var dirPath: String?
            if isDir {
                dirPath = path.hasSuffix("/") ? String(path.dropLast()) : path
            } else if path.contains("/") {
                dirPath = String(path[..<path.lastIndex(of: "/")!])
            }
            if let d = dirPath, !d.isEmpty, !seenDirs.contains(d) {
                seenDirs.insert(d)
                out.append(ArchiveEntry(path: d + "/", size: 0, isDirectory: true, category: Self.category(of: d)))
            }
            if !isDir {
                out.append(ArchiveEntry(path: path, size: UInt64(entry.uncompressedSize), isDirectory: false, category: Self.category(of: path)))
            }
            if out.count >= 20_000 { break }
        }
        return out.sorted { $0.path < $1.path }
    }

    static func category(of path: String) -> String {
        let lower = path.lowercased()
        if lower.contains(".framework/") || lower.hasSuffix(".framework") { return "框架" }
        if lower.contains(".appex/") || lower.hasSuffix(".appex") { return "扩展插件" }
        if lower.contains(".lproj") { return "本地化" }
        if lower.hasSuffix(".nib") || lower.hasSuffix(".storyboardc") || lower.hasSuffix(".storyboard") { return "界面" }
        if ["png", "jpg", "jpeg", "webp", "pdf", "heic", "car"].contains(where: lower.hasSuffix) { return "图像" }
        if ["mp3", "m4a", "aac", "wav", "caf", "mp4", "mov"].contains(where: lower.hasSuffix) { return "媒体" }
        if ["plist"].contains(where: lower.hasSuffix) { return "配置" }
        if lower.hasSuffix(".strings") || lower.hasSuffix(".json") || lower.hasSuffix(".txt") || lower.hasSuffix(".xml") { return "文本" }
        if lower.hasSuffix(".dylib") { return "动态库" }
        if lower.hasSuffix(".dat") || lower.hasSuffix(".bin") { return "数据" }
        return "其他"
    }

    // MARK: - 提取

    /// 提取整个归档到目标目录（性能档位控制节奏，支持取消）
    func extractAll(at ipaURL: URL, to destDir: URL, progress: @escaping (Double) -> Void, isCancelled: @escaping () -> Bool) throws {
        let archive = try Archive(url: ipaURL, accessMode: .read)
        let entries = Array(archive)
        var done = 0
        for entry in entries {
            if isCancelled() { throw ZipError.cancelled }
            let path = entry.path
            guard Self.isSafeEntryPath(path) else { continue }
            let target = destDir.appendingPathComponent(path)
            if entry.type == .directory {
                try? FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            } else {
                if Int64(entry.uncompressedSize) > maxEntrySize { continue } // 上限保护
                let parent = target.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
                try archive.extract(entry, to: target, skipCRC32: true)
                // macOS 元数据文件直接跳过落盘意义不大，保留原样
            }
            done += 1
            if done % 20 == 0 { progress(Double(done) / Double(max(entries.count, 1))) }
        }
        progress(1.0)
    }

    /// 提取单个文件（用于资源预览/导出）
    func extractEntry(named path: String, from ipaURL: URL, to destURL: URL) throws -> URL {
        let archive = try Archive(url: ipaURL, accessMode: .read)
        guard let entry = archive.first(where: { $0.path == path }) else {
            throw NSError(domain: "ZipService", code: 404, userInfo: [NSLocalizedDescriptionKey: "未找到文件：\(path)"])
        }
        guard Self.isSafeEntryPath(path) else { throw ZipError.unsafePath(path) }
        if entry.type == .file, Int64(entry.uncompressedSize) > maxEntrySize { throw ZipError.tooLarge(path) }
        try FileManager.default.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try archive.extract(entry, to: destURL, skipCRC32: true)
        return destURL
    }
}
