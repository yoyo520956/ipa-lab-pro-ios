//
//  SettingsView.swift
//  IPA Lab Pro
//  性能模式 / 专业设置 / 兼容性报告 / 关于与许可证
//

import SwiftUI

struct SettingsView: View {
    @State private var config = AnalysisConfig.load()
    @State private var compat: CompatReport?
    @State private var showCompat = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("性能模式", selection: $config.performanceMode) {
                        ForEach(PerformanceMode.allCases) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    Toggle("自动调整（内存压力/过热/磁盘紧张时自动降为低性能）", isOn: $config.autoAdjust)
                    if let compat {
                        Text(compat.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("性能管理")
                } footer: {
                    Text(config.performanceMode.descriptionText)
                }

                Section("专业设置 · 分析") {
                    Stepper("字符串最小长度：\(config.minStringLength)", value: $config.minStringLength, in: 3...32)
                    Stepper("扫描上限：\(config.maxScanBytes / 1024 / 1024) MB", value: $config.maxScanBytes, in: 16_000_000...1_000_000_000, step: 16_000_000)
                    Picker("报告默认格式", selection: $config.exportFormat) {
                        Text("TXT").tag("txt")
                        Text("JSON").tag("json")
                    }
                    Toggle("反汇编显示近似伪代码视图", isOn: $config.pseudocodeView)
                }

                Section("专业设置 · 日志") {
                    Picker("日志级别", selection: $config.logLevel) {
                        Text("安静").tag(0)
                        Text("常规").tag(1)
                        Text("调试").tag(2)
                    }
                    Text("分析日志写入各项目目录 analysis.log")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("兼容性") {
                    Button {
                        compat = CompatCheck.run()
                        showCompat = true
                    } label: {
                        Label("运行完整兼容性检测", systemImage: "stethoscope")
                    }
                }

                Section("数据与安全") {
                    Label("所有分析在本机沙盒完成，不上传任何文件", systemImage: "lock.shield")
                        .font(.footnote)
                    Label("不执行导入包内的任何程序", systemImage: "nosign")
                        .font(.footnote)
                }

                Section("关于") {
                    LabeledContent("版本", value: "1.0.0 (20261018.01)")
                    LabeledContent("引擎", value: "MachOKit 0.55.0 · Capstone 5.0.9")
                    LabeledContent("ZIP", value: "ZIPFoundation 0.9.20")
                    NavigationLink("开源许可证") {
                        LicenseView()
                    }
                }
            }
            .navigationTitle("设置")
            .onAppear { config = AnalysisConfig.load() }
            .onDisappear { config.save() }
            .sheet(isPresented: $showCompat) {
                if let c = compat { CompatReportSheet(report: c) }
            }
        }
    }
}

struct LicenseView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                licenseCard(
                    name: "MachOKit",
                    license: "MIT License",
                    source: "github.com/p-x9/MachOKit @ 0.55.0 (commit f0c6565)",
                    usage: "Mach-O 文件结构解析：文件头/加载命令/段与节/符号表/字符串数据/函数起点/代码签名/绑定与修复信息。原始代码，未经修改集成（SPM）。"
                )
                licenseCard(
                    name: "Capstone Engine",
                    license: "BSD-3-Clause（含 LLVM 衍生代码 BSD-3-Clause）",
                    source: "github.com/capstone-engine/capstone @ 5.0.9 (commit 0225758)",
                    usage: "ARM64/ARM 反汇编引擎。仅启用 ARM64+ARM 架构源码，直接编译进 App（BSD-3-Clause 声明保留于 Vendor/capstone/LICENSE.TXT）。"
                )
                licenseCard(
                    name: "ZIP Foundation",
                    license: "MIT License",
                    source: "github.com/weichsel/ZIPFoundation @ 0.9.20",
                    usage: "IPA(ZIP) 归档读取/解包/单文件提取。原始代码，未经修改集成（SPM）。"
                )
                licenseCard(
                    name: "Ghidra（未集成·仅对照）",
                    license: "Apache-2.0",
                    source: "github.com/NationalSecurityAgency/ghidra",
                    usage: "经审查不移植：需要 JVM 与桌面 GUI，无法在 iOS 沙盒内运行。其反编译能力以 Capstone 反汇编 + 明确标注的近似伪代码视图替代。"
                )
                licenseCard(
                    name: "LIEF（未集成·备选）",
                    license: "Apache-2.0",
                    source: "github.com/lief-project/LIEF",
                    usage: "功能与 MachOKit 重叠且体积/构建复杂度显著更高，v1.0 未引入；如后续需要 C++ 级解析能力再评估。"
                )
                Text("本项目自身代码以用户指定方式交付；以上第三方组件的版权与许可声明原文见仓库 NOTICE.md 与 Vendor 目录。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .background(DS.bg)
        .navigationTitle("开源许可证")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func licenseCard(name: String, license: String, source: String, usage: String) -> some View {
        DSCard(title: name, icon: "curlybraces.square") {
            Text(license).font(.footnote.weight(.semibold))
            Text(source).font(.system(.caption2, design: .monospaced)).foregroundStyle(DS.accent)
            Text(usage).font(.caption).foregroundStyle(.secondary)
        }
    }
}
