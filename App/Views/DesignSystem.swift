//
//  DesignSystem.swift
//  IPA Lab Pro
//  设计令牌与通用组件
//

import SwiftUI

enum DS {
    static let bg = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let accent = Color(red: 0.36, green: 0.55, blue: 1.0)
    static let orange = Color.orange
    static let green = Color.green
    static let red = Color.red

    static func statusColor(_ s: String) -> Color {
        switch s {
        case "done": return green
        case "analyzing": return accent
        case "failed": return red
        case "cancelled": return orange
        case "paused": return orange
        default: return .secondary
        }
    }

    static func statusText(_ s: String) -> String {
        switch s {
        case "pending": return "待分析"
        case "analyzing": return "分析中"
        case "done": return "已完成"
        case "failed": return "失败"
        case "cancelled": return "已取消"
        case "paused": return "已暂停"
        default: return s
        }
    }
}

struct DSCard<Content: View>: View {
    let title: String
    var icon: String = "doc.text.magnifyingglass"
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(DS.card, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct KVRow: View {
    let key: String
    let value: String
    var mono: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(key)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value.isEmpty ? "—" : value)
                .font(mono ? .system(.footnote, design: .monospaced) : .subheadline)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }
}

struct SectionHeader: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
