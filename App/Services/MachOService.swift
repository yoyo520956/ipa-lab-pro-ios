//
//  MachOService.swift
//  IPA Lab Pro
//  Mach-O 引擎封装（MachOKit 0.55.0 · MIT，commit f0c6565）
//  结构解析/段/节/符号/字符串扫描/函数起点/代码签名/加密状态
//

import Foundation
import MachOKit

final class MachOService {
    let config: AnalysisConfig

    init(config: AnalysisConfig) { self.config = config }

    // MARK: - Load command 名称映射

    static let loadCommandNames: [UInt32: String] = [
        0x1: "LC_SEGMENT", 0xB: "LC_DYSYMTAB", 0xC: "LC_LOAD_DYLIB", 0xD: "LC_ID_DYLIB",
        0xE: "LC_LOAD_DYLINKER", 0xF: "LC_ID_DYLINKER", 0x10: "LC_PREBOUND_DYLIB",
        0x11: "LC_ROUTINES", 0x12: "LC_SUB_FRAMEWORK", 0x13: "LC_SUB_UMBRELLA",
        0x14: "LC_SUB_CLIENT", 0x15: "LC_SUB_LIBRARY", 0x16: "LC_TWOLEVEL_HINTS",
        0x17: "LC_PREBIND_CKSUM", 0x18: "LC_LOAD_WEAK_DYLIB", 0x19: "LC_SEGMENT_64",
        0x1A: "LC_ROUTINES_64", 0x1B: "LC_UUID", 0x1C: "LC_RPATH(64)",
        0x1D: "LC_CODE_SIGNATURE", 0x1E: "LC_SEGMENT_SPLIT_INFO", 0x1F: "LC_RPATH",
        0x20: "LC_REEXPORT_DYLIB", 0x21: "LC_ENCRYPTION_INFO", 0x22: "LC_DYLD_INFO",
        0x23: "LC_DYLD_INFO_ONLY", 0x24: "LC_LOAD_UPWARD_DYLIB", 0x25: "LC_VERSION_MIN_MACOSX",
        0x26: "LC_FUNCTION_STARTS", 0x27: "LC_DYLD_ENVIRONMENT", 0x28: "LC_MAIN",
        0x29: "LC_DATA_IN_CODE", 0x2A: "LC_SOURCE_VERSION", 0x2B: "LC_DYLIB_CODE_SIGN_DRS",
        0x2C: "LC_ENCRYPTION_INFO_64", 0x2D: "LC_LINKER_OPTION", 0x2E: "LC_LINKER_OPTIMIZATION_HINT",
        0x2F: "LC_VERSION_MIN_TVOS", 0x30: "LC_VERSION_MIN_WATCHOS", 0x31: "LC_NOTE",
        0x32: "LC_BUILD_VERSION", 0x33: "LC_DYLD_EXPORTS_TRIE", 0x34: "LC_DYLD_CHAINED_FIXUPS",
        0x35: "LC_FILESET_ENTRY", 0x36: "LC_ATOM_INFO"
    ]

    static let fileTypeNames: [UInt32: String] = [
        1: "MH_OBJECT（目标文件）", 2: "MH_EXECUTE（可执行）", 3: "MH_FVMLIB",
        4: "MH_CORE", 5: "MH_PRELOAD", 6: "MH_DYLIB（动态库）", 7: "MH_DYLINKER",
        8: "MH_BUNDLE", 9: "MH_DYLIB_STUB", 10: "MH_DSYM", 11: "MH_KEXT_BUNDLE",
        12: "MH_FILESET", 13: "MH_GPU_EXECUTE", 14: "MH_GPU_DYLIB"
    ]

    static func cpuTypeName(_ raw: UInt32) -> String {
        switch raw {
        case 7: return "x86 / i386"
        case 7 + 0x0100_0000: return "x86_64"
        case 12: return "ARM64 (arm64)"
        case 12 + 0x0100_0000: return "ARM64e (arm64e)"
        case 11: return "ARM (armv7)"
        default: return "cputype(\(raw))"
        }
    }

    static func magicName(_ raw: UInt32) -> String {
        switch raw {
        case 0xFEED_FACE: return "MH_MAGIC (32位)"
        case 0xFEED_FACF: return "MH_MAGIC_64 (64位)"
        case 0xBEBA_BEBA: return "FAT (通用二进制)"
        case 0xFEED_FACE.bigEndian: return "MH_CIGAM (32位·字节反序)"
        case 0xFEED_FACF.bigEndian: return "MH_CIGAM_64 (64位·字节反序)"
        default: return String(format: "未知 magic 0x%08X", raw)
        }
    }

    static func flagsNames(_ raw: UInt32) -> [String] {
        var out: [String] = []
        let table: [(UInt32, String)] = [
            (0x1, "MH_NOUNDEFS"), (0x2, "MH_INCRLINK"), (0x4, "MH_DYLDLINK"),
            (0x8, "MH_BINDATLOAD"), (0x10, "MH_PREBOUND"), (0x40, "MH_TWOLEVEL"),
            (0x80, "MH_PREBINDABLE"), (0x400, "MH_NO_HEAP_EXECUTION"), (0x2000, "MH_NO_REEXPORTED_DYLIBS"),
            (0x100000, "MH_ALL_THREADS_BOUND"), (0x200000, "MH_PIE"), (0x400000, "MH_DEAD_STRIPPABLE_DYLIB"),
            (0x800000, "MH_HAS_TLV_DESCRIPTORS"), (0x1000000, "MH_NO_FIXUP_CHAINS"), (0x2000000, "MH_APP_EXTENSION_SAFE")
        ]
        for (bit, name) in table where raw & bit != 0 { out.append(name) }
        return out
    }

    // MARK: - 主解析

    func parseFile(at url: URL) throws -> MachOInfo {
        let machO = try MachOFile(url: url)
        var info = MachOInfo()

        let header = machO.header
        let h = header.layout
        info.magic = Self.magicName(UInt32(truncatingIfNeeded: h.magic))
        info.cputype = Self.cpuTypeName(UInt32(truncatingIfNeeded: h.cputype))
        info.cpusubtype = "cpusubtype(\(h.cpusubtype))"
        info.fileType = Self.fileTypeNames[UInt32(truncatingIfNeeded: h.filetype)] ?? "filetype(\(h.filetype))"
        info.ncmds = UInt32(truncatingIfNeeded: h.ncmds)
        info.sizeofcmds = UInt32(truncatingIfNeeded: h.sizeofcmds)
        info.flags = Self.flagsNames(UInt32(truncatingIfNeeded: h.flags))

        // 段与节
        var sections: [MachOSectionInfo] = []
        for seg in machO.segments64 {
            let s = MachOSegmentInfo(
                name: seg.segmentName,
                vmAddress: UInt64(bitPattern: Int64(seg.virtualMemoryAddress)),
                vmSize: UInt64(bitPattern: Int64(seg.virtualMemorySize)),
                fileOffset: UInt64(bitPattern: Int64(seg.fileOffset)),
                fileSize: UInt64(bitPattern: Int64(seg.fileSize)),
                maxProtection: Self.protText(UInt8(truncatingIfNeeded: seg.layout.maxprot)),
                initProtection: Self.protText(UInt8(truncatingIfNeeded: seg.layout.initprot)),
                flags: String(format: "0x%08X", seg.layout.flags)
            )
            info.segments.append(s)
        }
        for sec in machO.sections64 {
            let s = MachOSectionInfo(
                segmentName: sec.segmentName,
                sectionName: sec.sectionName,
                address: UInt64(bitPattern: Int64(sec.address)),
                size: UInt64(bitPattern: Int64(sec.size)),
                fileOffset: UInt64(bitPattern: Int64(sec.offset)),
                )
            sections.append(s)
        }
        info.sections = sections

        // 加载命令
        var idx = 0
        for cmd in machO.loadCommands {
            let name = Self.loadCommandNames[cmd.type.rawValue] ?? cmd.type.rawValue.map { String(format: "LC(0x%X)", $0) }
            var detail = ""
            if let dylib = cmd.info as? DylibCommand {
                detail = (try? dylib.dylib(in: machO).name) ?? ""
            }
            info.loadCommands.append(LoadCommandInfo(id: idx, name: name, size: cmd.layout.cmdsize, detail: detail))
            idx += 1
        }
        info.linkedDylibs = Array(Set(info.loadCommands.compactMap { $0.detail.isEmpty ? nil : $0.detail })).sorted()

        // 符号表（上限保护）
        var symbols: [MachOSymbolInfo] = []
        var si = 0
        for symbol in machO.symbols {
            if si >= config.performanceMode.symbolLimit { break }
            let addr: UInt64
            let ntype: UInt8
            if let n64 = symbol.nlist as? Nlist64 {
                addr = n64.layout.n_value
                ntype = n64.layout.n_type
            } else {
                addr = 0
                ntype = 0
            }
            let typeChar: String = {
                if ntype & 0x0E == 0x0E { return "SECT" }
                if ntype & 0x01 != 0 { return "EXT" }
                return "ABS/UNDF"
            }()
            symbols.append(MachOSymbolInfo(id: si, name: symbol.name, demangled: symbol.demangledName, address: addr, type: typeChar))
            si += 1
        }
        info.symbols = symbols

        // 函数起点
        if let fs = machO.functionStarts {
            var count = 0
            for f in fs {
                if count >= 50_000 { break }
                info.functionStarts.append(UInt64(f.offset))
                count += 1
            }
            info.functionStarts.sort()
        }

        // 代码签名
        info.codeSigned = machO.codeSign != nil
        // 加密状态
        if let enc = machO.loadCommands.info(of: LoadCommand.encryptionInfo64) {
            info.isEncrypted = enc.layout.cryptid != 0
            info.cryptId = Int(enc.layout.cryptid)
        } else if let enc32 = machO.loadCommands.info(of: LoadCommand.encryptionInfo) {
            info.isEncrypted = enc32.layout.cryptid != 0
            info.cryptId = Int(enc32.layout.cryptid)
        }
        // 链式修复
        info.hasChainedFixups = machO.loadCommands.of(.dyldChainedFixups).first(where: { _ in true }) != nil

        return info
    }

    static func protText(_ raw: UInt8) -> String {
        var s = ""
        if raw & 4 != 0 { s += "r" }
        if raw & 2 != 0 { s += "w" }
        if raw & 1 != 0 { s += "x" }
        return s.isEmpty ? "-" : s
    }

    // MARK: - vmaddr → file offset

    static func fileOffset(for vmAddr: UInt64, segments: [MachOSegmentInfo]) -> UInt64? {
        for seg in segments where vmAddr >= seg.vmAddress && vmAddr < seg.vmAddress + seg.vmSize {
            return vmAddr - seg.vmAddress + seg.fileOffset
        }
        return nil
    }

    // MARK: - 字符串扫描（分块 + 上限 + 取消，性能档位真实生效）

    func scanStrings(at url: URL, machO: MachOInfo, progress: @escaping (Double) -> Void, isCancelled: @escaping () -> Bool) throws -> [StringEntry] {
        let data: Data
        do {
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            return []
        }
        var entries: [StringEntry] = []
        var id = 0
        let targetSections = machO.sections.filter { config.includeSectionsInStrings.contains($0.sectionName) }
        let total = targetSections.reduce(0) { $0 + $1.size }
        var scanned: UInt64 = 0
        let minLen = config.minStringLength
        let mode = config.performanceMode

        for section in targetSections {
            if isCancelled() { break }
            guard section.size > 0, section.fileOffset + section.size <= UInt64(data.count) else { continue }
            let start = Int(section.fileOffset)
            let end = min(start + Int(section.size), data.count)
            var pos = start
            while pos < end {
                if isCancelled() { break }
                let chunkEnd = min(pos + mode.scanChunkSize, end)
                pos = Self.scanRange(data: data, from: pos, to: chunkEnd, minLen: minLen) { str, off, len in
                    guard entries.count < mode.stringLimit else { return }
                    let vm = machO.sections.first(where: { $0.fileOffset <= off && off < $0.fileOffset + $0.size })?.address ?? 0
                    entries.append(StringEntry(id: id, value: str, section: section.sectionName, fileOffset: off, vmAddress: vm, length: len))
                    id += 1
                }
                scanned += UInt64(chunkEnd - pos)
            }
            progress(min(0.999, Double(scanned) / Double(max(total, 1))))
        }
        progress(1.0)
        return entries
    }

    /// 在 [from, to) 范围扫描 UTF-8 字符串，返回新位置（有界缓存 friendly）
    static func scanRange(data: Data, from: Int, to: Int, minLen: Int, emit: (String, UInt64, Int) -> Void) -> Int {
        var runStart = -1
        var buf = [UInt8]()
        var i = from
        while i < to {
            let b = data[data.startIndex + i]
            let printable = (b >= 0x20 && b <= 0x7E) || b >= 0x80 || b == 0x09
            if printable {
                if runStart < 0 { runStart = i; buf = [] }
                buf.append(b)
            } else {
                if runStart >= 0 && buf.count >= minLen {
                    if let s = String(bytes: buf, encoding: .utf8), !s.isEmpty {
                        emit(s, UInt64(runStart), buf.count)
                    }
                }
                runStart = -1
                buf = []
            }
            i += 1
        }
        if runStart >= 0 && buf.count >= minLen {
            if let s = String(bytes: buf, encoding: .utf8), !s.isEmpty {
                emit(s, UInt64(runStart), buf.count)
            }
        }
        return to
    }
}
