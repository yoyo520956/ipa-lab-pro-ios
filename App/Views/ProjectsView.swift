//
//  ProjectsView.swift
//  IPA Lab Pro
//  项目列表：导入 IPA 创建项目 / 搜索 / 收藏 / 删除确认
//

import SwiftUI
import UniformTypeIdentifiers

struct ProjectsView: View {
    @StateObject private var store = ProjectStore.shared
    @State private var searchText = ""
    @State private var showImporter = false
    @State private var importError: String?
    @State private var importing = false
    @State private var pendingDelete: AnalysisProject?

    var body: some View {
        NavigationStack {
            List {
                if store.projects.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "shippingbox")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("还没有分析项目")
                            .font(.headline)
                        Text("导入一个 IPA 文件开始本地分析。文件只在本机处理，不会上传。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button {
                            showImporter = true
                        } label: {
                            Label("导入 IPA 文件", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .listRowBackground(Color.clear)
                }

                Section {
                    ForEach(store.search(text: searchText)) { project in
                        NavigationLink {
                            ProjectDetailView(projectID: project.id)
                        } label: {
                            projectRow(project)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                pendingDelete = project
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                            Button {
                                store.toggleFavorite(project)
                            } label: {
                                Label("收藏", systemImage: project.isFavorite ? "star.slash" : "star")
                            }
                            .tint(.yellow)
                        }
                    }
                } header: {
                    HStack {
                        Text("项目（\(store.projects.count)）")
                        Spacer()
                        Text("总占用 \(DirectoryUtils.byteText(store.totalStorageUsage()))")
                            .font(.caption2)
                    }
                } footer: {
                    Text("原始 IPA 副本与分析数据随项目存储；删除项目会同时删除其副本。")
                }
            }
            .searchable(text: $searchText, prompt: "搜索项目 / 备注 / 标签")
            .navigationTitle("IPA Lab Pro")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showImporter = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.data, .archive], allowsMultipleSelection: false) { result in
                handleImport(result)
            }
            .alert("导入失败", isPresented: .init(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
                Button("好", role: .cancel) {}
            } message: {
                Text(importError ?? "")
            }
            .alert("删除项目？", isPresented: .init(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
                Button("取消", role: .cancel) {}
                Button("删除", role: .destructive) {
                    if let p = pendingDelete { store.delete(p) }
                }
            } message: {
                if let p = pendingDelete {
                    Text("将删除「\(p.name)」及其原始 IPA 副本、解包数据与报告（约 \(DirectoryUtils.byteText(store.storageUsage(for: p)))），不可恢复。")
                }
            }
            .overlay {
                if importing {
                    ZStack {
                        Color.black.opacity(0.3).ignoresSafeArea()
                        ProgressView("正在导入…")
                            .padding(24)
                            .background(DS.card, in: RoundedRectangle(cornerRadius: 14))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func projectRow(_ p: AnalysisProject) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "shippingbox.fill")
                .foregroundStyle(DS.accent)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(p.name).font(.subheadline.weight(.medium)).lineLimit(1)
                    if p.isFavorite { Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow) }
                }
                Text("\(DS.statusText(p.status)) · \(DateFormatter.localizedString(from: p.updatedAt, dateStyle: .short, timeStyle: .short)) · \(DirectoryUtils.byteText(store.storageUsage(for: p)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let e):
            importError = e.localizedDescription
        case .success(let urls):
            guard let src = urls.first else { return }
            importing = true
            Task {
                defer { importing = false }
                do {
                    let scoped = src.startAccessingSecurityScopedResource()
                    defer { if scoped { src.stopAccessingSecurityScopedResource() } }
                    // 验证是有效 zip
                    _ = try Archive(url: src, accessMode: .read)
                    let project = store.create(name: src.deletingPathExtension().lastPathComponent)
                    let dir = store.directory(for: project)
                    let dest = dir.appendingPathComponent("original.ipa")
                    try? FileManager.default.removeItem(at: dest)
                    try FileManager.default.copyItem(at: src, to: dest)
                    var p = project
                    p.status = "pending"
                    p.statusMessage = "已导入 \(DirectoryUtils.byteText(DirectoryUtils.directorySize(dir)))"
                    store.update(p)
                } catch {
                    importError = "该文件不是有效的 IPA/ZIP 归档：\(error.localizedDescription)"
                }
            }
        }
    }
}

import ZIPFoundation
