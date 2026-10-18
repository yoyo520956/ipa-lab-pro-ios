//
//  RootView.swift
//  IPA Lab Pro
//

import SwiftUI

struct RootView: View {
    @StateObject private var store = ProjectStore.shared
    @State private var showCompatReport = false
    @State private var compat: CompatReport?
    @State private var compatShownKey = "iplab.compatShown"

    var body: some View {
        TabView {
            ProjectsView()
                .tabItem { Label("项目", systemImage: "archivebox") }
            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
        .tint(DS.accent)
        .onAppear {
            if UserDefaults.standard.bool(forKey: compatShownKey) == false {
                compat = CompatCheck.run()
                showCompatReport = true
                UserDefaults.standard.set(true, forKey: compatShownKey)
            } else {
                compat = CompatCheck.run()
            }
        }
        .sheet(isPresented: $showCompatReport) {
            if let c = compat {
                CompatReportSheet(report: c)
            }
        }
    }
}

struct CompatReportSheet: View {
    let report: CompatReport
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    DSCard(title: "启动兼容性报告", icon: "stethoscope") {
                        Text(report.summary)
                            .font(.subheadline)
                            .textSelection(.enabled)
                    }
                    DSCard(title: "引擎自检", icon: "cpu") {
                        KVRow(key: "MachOKit（Mach-O 解析）", value: report.engineMachOKit)
                        KVRow(key: "Capstone（反汇编）", value: report.engineCapstone)
                        KVRow(key: "ZIPFoundation（解包）", value: report.engineZip)
                        KVRow(key: "检查时间", value: DateFormatter.localizedString(from: report.checkedAt, dateStyle: .short, timeStyle: .medium))
                    }
                    Text("所有分析均在本地沙盒内完成，不上传任何文件。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .background(DS.bg)
            .navigationTitle("兼容性检测")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("好") { dismiss() }
                }
            }
        }
    }
}
