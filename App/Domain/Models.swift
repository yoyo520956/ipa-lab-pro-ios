//
//  Models.swift
//  IPA Lab Pro
//  数据模型层
//

import Foundation

// MARK: - 分析项目

struct AnalysisProject: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var isFavorite: Bool = false
    var tags: [String] = []
    var note: String = ""
    /// 状态: pending / analyzing / paused / done / failed / cancelled
    var status: String = "pending"
    var statusMessage: String = ""

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - 包信息（从 IPA / Info.plist 解析）

struct BundleSummary: Codable, Equatable {
    var displayName: String = ""
    var bundleIdentifier: String = ""
    var version: String = ""
    var buildVersion: String = ""
    var minOSVersion: String = ""
    var executableName: String = ""
    var platformName: String = ""
    var sdkName: String = ""
    var entryCount: Int = 0
    var appSizeBytes: Int64 = 0
    var binarySizeBytes: Int64 = 0
    var architectures: [String] = []
    var frameworks: [String] = []
    var plugins: [String] = []
}

// MARK: - Mach-O 分析结果

struct MachOSectionInfo: Identifiable, Codable, Equatable {
    var id: String { segmentName + "." + sectionName }
    var segmentName: String
    var sectionName: String
    var address: UInt64
    var size: UInt64
    var fileOffset: UInt64
}

struct MachOSegmentInfo: Identifiable, Codable, Equatable {
    var id: String { name }
    var name: String
    var vmAddress: UInt64
    var vmSize: UInt64
    var fileOffset: UInt64
    var fileSize: UInt64
    var maxProtection: String
    var initProtection: String
    var flags: String
}

struct MachOSymbolInfo: Identifiable, Codable, Equatable {
    var id: Int
    var name: String
    var demangled: String
    var address: UInt64
    var type: String
}

struct LoadCommandInfo: Identifiable, Codable, Equatable {
    var id: Int
    var name: String
    var size: UInt32
    var detail: String
}

struct MachOInfo: Codable, Equatable {
    var magic: String = ""
    var cputype: String = ""
    var cpusubtype: String = ""
    var fileType: String = ""
    var flags: [String] = []
    var ncmds: UInt32 = 0
    var sizeofcmds: UInt32 = 0
    var segments: [MachOSegmentInfo] = []
    var sections: [MachOSectionInfo] = []
    var loadCommands: [LoadCommandInfo] = []
    var linkedDylibs: [String] = []
    var symbols: [MachOSymbolInfo] = []
    var functionStarts: [UInt64] = []
    var codeSigned: Bool = false
    var hasChainedFixups: Bool = false
    var isEncrypted: Bool = false
    var cryptId: Int = 0
}

// MARK: - 字符串

struct StringEntry: Identifiable, Codable, Equatable {
    var id: Int
    var value: String
    var section: String
    var fileOffset: UInt64
    var vmAddress: UInt64
    var length: Int
}

// MARK: - 反汇编

struct InstructionEntry: Identifiable, Codable, Equatable {
    var id: Int
    var address: UInt64
    var size: UInt32
    var mnemonic: String
    var operands: String
    var bytes: String
}

// MARK: - ObjC 元数据

struct ObjCMethodInfo: Codable, Equatable {
    var name: String
    var types: String
    var impAddress: UInt64
}

struct ObjCClassInfo: Identifiable, Codable, Equatable {
    var id: String { name }
    var name: String
    var isaName: String
    var instanceMethods: [ObjCMethodInfo]
    var classMethods: [ObjCMethodInfo]
    var isMetaParsed: Bool
}

struct ObjCMetadataInfo: Codable, Equatable {
    var classNames: [String] = []
    var selectors: [String] = []
    var categories: [String] = []
    var classes: [ObjCClassInfo] = []
    var parseNote: String = ""
}

// MARK: - 分析检查点（断点恢复）

struct AnalysisCheckpoint: Codable {
    var phase: String
    var completedPhases: [String] = []
    var updatedAt: Date = Date()
    var machOInfo: MachOInfo?
    var strings: [StringEntry]?
    var objc: ObjCMetadataInfo?
    var bundle: BundleSummary?
}

// MARK: - 文件树条目

struct ArchiveEntry: Identifiable, Codable, Equatable {
    var id: String { path }
    var path: String
    var size: UInt64
    var isDirectory: Bool
    var category: String
}
