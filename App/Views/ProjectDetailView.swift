//
//  ProjectDetailView.swift + AnalysisView.swift
//  IPA Lab Pro
//  项目详情与分析主界面（阶段进度 + 结果页签）
//

import SwiftUI
import UniformTypeIdentifiers

struct ProjectDetailView: View {
    let projectID: UUID
    @StateObject private var store = ProjectStore.shared
    @State private var engine: AnalysisEngine?
    @State private var config = AnalysisConfig.load()

    var project: AnalysisProject? { store.project(id: projectID) }

    var body: some View {
        Group {
            if let project {
                if let engine {
                    AnalysisView(engine: engine)
                } else {
                    VStack(spacing: 16) {
                        DSCard(title: project.name, icon: "shippingbox.fill") {
                            KVRow(key: "状态", value: DS.statusText(project.status))
                            KVRow(key: "占用", value: DirectoryUtils.byteText(store.storageUsage(for: project)))
                            KVRow(key: "创建", value: DateFormatter.localizedString(from: project.createdAt, dateStyle: .short, timeStyle: .short))
                        }
                        Button {
                            startAnalysis(project)
                        } label: {
                            Label("开始本地分析", systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        Spacer()
                    }
                    .padding()
                    .background(DS.bg)
                }
            } else {
                Text("项目不存在或已被删除")
            }
        }
        .navigationTitle(project?.name ?? "项目")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func startAnalysis(_ project: AnalysisProject) {
        config = AnalysisConfig.load()
        let e = AnalysisEngine(project: project, config: config, compat: CompatCheck.run())
        engine = e
        var p = project
        p.status = "analyzing"
        store.update(p)
        e.start()
    }
}

// MARK: - 分析主界面

struct AnalysisView: View {
    @ObservedObject var engine: AnalysisEngine
    @State private var tab = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("视图", selection: $tab) {
                Text("概览").tag(0)
                Text("包内容").tag(1)
                Text("Mach-O").tag(2)
                Text("字符串").tag(3)
                Text("反汇编").tag(4)
                Text("ObjC").tag(5)
                Text("报告").tag(6)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)

            Group {
                switch tab {
                case 0: OverviewTab(engine: engine)
                case 1: BundleTab(engine: engine)
                case 2: MachOTab(engine: engine)
                case 3: StringsTab(engine: engine)
                case 4: DisasmTab(engine: engine)
                case 5: ObjCTab(engine: engine)
                default: ReportTab(engine: engine)
                }
            }
        }
        .background(DS.bg)
        .navigationTitle("分析")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if engine.isRunning {
                    Button("取消") { engine.cancel() }
                        .foregroundStyle(DS.red)
                }
            }
        }
    }
}

// MARK: - 概览页

struct OverviewTab: View {
    @ObservedObject var engine: AnalysisEngine

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                DSCard(title: "分析进度", icon: "gauge.with.dots.needle.33percent") {
                    HStack {
                        Text(engine.phase.rawValue).font(.subheadline.weight(.medium))
                        Spacer()
                        Text("\(Int(engine.progress * 100))%")
                            .font(.subheadline.monospacedDigit())
                    }
                    ProgressView(value: engine.progress)
                    if engine.isRunning {
                        Text("运行中 · 性能模式：\(engine.performanceMode.rawValue)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let err = engine.errorMessage {
                        Text("错误：\(err)").font(.caption).foregroundStyle(DS.red)
                    }
                }

                DSCard(title: "包信息", icon: "shippingbox.fill") {
                    KVRow(key: "显示名", value: engine.bundleSummary.displayName)
                    KVRow(key: "Bundle ID", value: engine.bundleSummary.bundleIdentifier, mono: true)
                    KVRow(key: "版本", value: "\(engine.bundleSummary.version) (\(engine.bundleSummary.buildVersion))")
                    KVRow(key: "最低系统", value: "iOS \(engine.bundleSummary.minOSVersion)")
                    KVRow(key: "SDK", value: engine.bundleSummary.sdkName)
                    KVRow(key: "条目数", value: "\(engine.bundleSummary.entryCount)")
                    KVRow(key: "包大小", value: DirectoryUtils.byteText(engine.bundleSummary.appSizeBytes))
                    KVRow(key: "主二进制", value: DirectoryUtils.byteText(engine.bundleSummary.binarySizeBytes))
                    if !engine.bundleSummary.frameworks.isEmpty {
                        KVRow(key: "框架", value: "\(engine.bundleSummary.frameworks.count) 个")
                    }
                    if !engine.bundleSummary.plugins.isEmpty {
                        KVRow(key: "扩展插件", value: "\(engine.bundleSummary.plugins.count) 个")
                    }
                }

                if let m = engine.machOInfo {
                    DSCard(title: "二进制概要", icon: "cpu") {
                        KVRow(key: "格式", value: m.magic)
                        KVRow(key: "架构", value: m.cputype)
                        KVRow(key: "文件类型", value: m.fileType)
                        KVRow(key: "代码签名", value: m.codeSigned ? "有" : "无")
                        KVRow(key: "App Store 加密", value: m.isEncrypted ? "是（cryptid=\(m.cryptId)）" : "否")
                        KVRow(key: "链式修复", value: m.hasChainedFixups ? "有 (chained fixups)" : "无")
                    }
                }

                DSCard(title: "运行日志", icon: "text.justify.left") {
                    ForEach(engine.log.suffix(12), id: \.self) { line in
                        Text(line).font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
        }
    }
}
