//
//  PerformanceProfile.swift
//  IPA Lab Pro
//  三档性能模式 + 分析配置（全部真实生效）
//

import Foundation

enum PerformanceMode: String, CaseIterable, Codable, Identifiable {
    case low = "低性能模式"
    case balanced = "平衡模式"
    case high = "高性能模式"

    var id: String { rawValue }

    /// 字符串扫描分块大小（字节）
    var scanChunkSize: Int {
        switch self {
        case .low: return 256 * 1024
        case .balanced: return 1024 * 1024
        case .high: return 4 * 1024 * 1024
        }
    }

    /// 字符串提取上限（条）
    var stringLimit: Int {
        switch self {
        case .low: return 30_000
        case .balanced: return 80_000
        case .high: return 200_000
        }
    }

    /// 单次反汇编最大指令数
    var disasmLimit: Int {
        switch self {
        case .low: return 5_000
        case .balanced: return 20_000
        case .high: return 60_000
        }
    }

    /// 符号表缓存上限
    var symbolLimit: Int {
        switch self {
        case .low: return 20_000
        case .balanced: return 60_000
        case .high: return 150_000
        }
    }

    /// 解包并发数
    var extractionConcurrency: Int {
        switch self {
        case .low: return 1
        case .balanced: return 2
        case .high: return 4
        }
    }

    /// 内存缓存上限（字节）— 有界缓存
    var memoryCacheLimit: Int {
        switch self {
        case .low: return 16 * 1024 * 1024
        case .balanced: return 48 * 1024 * 1024
        case .high: return 128 * 1024 * 1024
        }
    }

    /// 低性能模式：阶段性落盘检查点间隔（阶段数）
    var checkpointEveryPhase: Bool { self == .low }

    var descriptionText: String {
        switch self {
        case .low:
            return "串行处理 + 分块读取 + 磁盘中间文件 + 阶段性检查点。目标：降低闪退风险，尽可能让大型任务完整执行。"
        case .balanced:
            return "速度、内存与电量的平衡默认档。适度并发与缓存，保留完整功能。"
        case .high:
            return "提高并发与缓存以缩短运行时间。仍受 iOS 资源限制保护，不会无限制占用。"
        }
    }
}

/// 专业设置（用户可调，真实影响引擎行为）
struct AnalysisConfig: Codable {
    var performanceMode: PerformanceMode = .balanced
    /// 自动模式：根据内存压力/热状态/剩余空间自动降档
    var autoAdjust: Bool = true
    var minStringLength: Int = 4
    var maxScanBytes: Int = 256 * 1024 * 1024
    var logLevel: Int = 1 // 0=quiet 1=info 2=debug
    var includeSectionsInStrings: [String] = ["__cstring", "__objc_methname", "__objc_classname", "__ustring", "__const"]
    var exportFormat: String = "txt" // txt / json
    var pseudocodeView: Bool = true

    static let key = "iplab.analysisConfig.v1"

    static func load() -> AnalysisConfig {
        if let data = UserDefaults.standard.data(forKey: key),
           let cfg = try? JSONDecoder().decode(AnalysisConfig.self, from: data) {
            return cfg
        }
        return AnalysisConfig()
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// 自动兼容性降档：内存压力 / 过热 / 磁盘紧张 → 自动降到低性能
    static func effectiveMode(for config: AnalysisConfig, compat: CompatReport?) -> PerformanceMode {
        guard config.autoAdjust, let c = compat else { return config.performanceMode }
        if c.thermalStateText != "正常" || c.diskFreeGB < 1.0 || c.memoryPressure {
            return .low
        }
        return config.performanceMode
    }
}
