//
//  ProjectStore.swift
//  IPA Lab Pro
//  本地项目管理：创建/导入/搜索/收藏/标签/删除确认/占用统计，全部持久化在沙盒
//

import Foundation

@MainActor
final class ProjectStore: ObservableObject {
    @Published private(set) var projects: [AnalysisProject] = []

    private let indexURL: URL
    private let indexLock = NSLock()

    static let shared = ProjectStore()

    var rootDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("Projects", isDirectory: true)
    }

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        indexURL = docs.appendingPathComponent("projects.index.json")
        ensureAll()
        loadIndex()
    }

    private func ensureAll() {
        try? FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
    }

    func directory(for project: AnalysisProject) -> URL {
        rootDirectory.appendingPathComponent(project.id.uuidString, isDirectory: true)
    }

    // MARK: - 索引持久化

    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexURL),
              let list = try? JSONDecoder().decode([AnalysisProject].self, from: data) else { return }
        projects = list.sorted { $0.updatedAt > $1.updatedAt }
    }

    func saveIndex() {
        indexLock.lock()
        defer { indexLock.unlock() }
        guard let data = try? JSONEncoder().encode(projects) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    // MARK: - CRUD

    @discardableResult
    func create(name: String) -> AnalysisProject {
        let p = AnalysisProject(name: name)
        try? FileManager.default.createDirectory(at: directory(for: p), withIntermediateDirectories: true)
        projects.insert(p, at: 0)
        saveIndex()
        return p
    }

    func update(_ project: AnalysisProject) {
        if let i = projects.firstIndex(where: { $0.id == project.id }) {
            var p = project
            p.updatedAt = Date()
            projects[i] = p
            saveIndex()
        }
    }

    func toggleFavorite(_ project: AnalysisProject) {
        var p = project
        p.isFavorite.toggle()
        update(p)
    }

    /// 删除：只删除本项目沙盒目录；原始导入副本随项目删除（导入前已在 UI 明确提示）
    func delete(_ project: AnalysisProject) {
        try? FileManager.default.removeItem(at: directory(for: project))
        projects.removeAll { $0.id == project.id }
        saveIndex()
    }

    func project(id: UUID) -> AnalysisProject? {
        projects.first { $0.id == id }
    }

    // MARK: - 搜索 / 过滤

    func search(text: String, favoritesOnly: Bool = false, tag: String? = nil) -> [AnalysisProject] {
        var list = projects
        if favoritesOnly { list = list.filter(\.isFavorite) }
        if let tag, !tag.isEmpty { list = list.filter { $0.tags.contains(tag) } }
        guard !text.isEmpty else { return list }
        let q = text.lowercased()
        return list.filter {
            $0.name.lowercased().contains(q)
                || $0.note.lowercased().contains(q)
                || $0.tags.contains { $0.lowercased().contains(q) }
                || $0.statusMessage.lowercased().contains(q)
        }
    }

    func allTags() -> [String] {
        Array(Set(projects.flatMap(\.tags))).sorted()
    }

    // MARK: - 占用统计

    func storageUsage(for project: AnalysisProject) -> Int64 {
        DirectoryUtils.directorySize(directory(for: project))
    }

    func totalStorageUsage() -> Int64 {
        DirectoryUtils.directorySize(rootDirectory)
    }
}

enum DirectoryUtils {
    static func directorySize(_ url: URL) -> Int64 {
        guard let en = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) else { return 0 }
        var total: Int64 = 0
        for case let f as URL in en {
            if let v = try? f.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]), v.isRegularFile == true {
                total += Int64(v.fileSize ?? 0)
            }
        }
        return total
    }

    static func byteText(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
