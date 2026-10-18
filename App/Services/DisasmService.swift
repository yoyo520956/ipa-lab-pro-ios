//
//  DisasmService.swift
//  IPA Lab Pro
//  Capstone 反汇编封装（capstone 5.0.9 · BSD-3-Clause，commit 0225758）
//  ARM64 / ARM 双架构 + 近似伪代码生成（指令直译，明确标注非反编译器输出）
//

import Foundation
import MachOKit

struct DisasmRequest {
    var arch: cs_arch = CS_ARCH_ARM64
    var mode: cs_mode = CS_MODE_LITTLE_ENDIAN
    var startAddress: UInt64
    var fileOffset: UInt64
    var maxInstructions: Int
}

final class DisasmService {
    let config: AnalysisConfig

    init(config: AnalysisConfig) { self.config = config }

    /// C char[N] 元组 → Swift String（capstone mnemonic/op_str）
    static func cStringTuple<T>(_ tuple: T) -> String {
        withUnsafeBytes(of: tuple) { raw in
            let base = raw.baseAddress!.assumingMemoryBound(to: CChar.self)
            return String(cString: base)
        }
    }

    /// 反汇编指定文件偏移区间
    func disassemble(at url: URL, request: DisasmRequest, isCancelled: @escaping () -> Bool = { false }) throws -> [InstructionEntry] {
        guard request.maxInstructions > 0 else { return [] }
        guard let fh = FileHandle(forReadingAtPath: url.path) else {
            throw NSError(domain: "DisasmService", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法打开二进制文件"])
        }
        defer { try? fh.close() }
        let readLen = min(request.maxInstructions * 4 + 64, 8 * 1024 * 1024)
        try? fh.seek(toOffset: request.fileOffset)
        guard let data = try? fh.read(upToCount: readLen), !data.isEmpty else { return [] }

        var handle: csh = 0
        guard cs_open(request.arch, request.mode, &handle) == CS_ERR_OK else {
            throw NSError(domain: "DisasmService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Capstone 引擎初始化失败"])
        }
        defer { cs_close(&handle) }

        var out: [InstructionEntry] = []
        let cap = min(request.maxInstructions, config.performanceMode.disasmLimit)
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            var idx = 0
            while idx < cap, offset + 4 <= data.count {
                if isCancelled() { break }
                var insn: UnsafeMutablePointer<cs_insn>?
                let count = cs_disasm(handle, base.advanced(by: offset), data.count - offset, request.startAddress, 1, &insn)
                if count > 0, let i = insn {
                    let m = Self.cStringTuple(i.pointee.mnemonic)
                    let ops = Self.cStringTuple(i.pointee.op_str)
                    let bTuple = i.pointee.bytes
                    let bytes = withUnsafeBytes(of: bTuple) { raw -> String in
                        (0..<Int(i.pointee.size)).map { String(format: "%02x", raw[$0]) }.joined(separator: " ")
                    }
                    out.append(InstructionEntry(id: idx, address: i.pointee.address, size: i.pointee.size, mnemonic: m, operands: ops, bytes: bytes))
                    offset += Int(i.pointee.size)
                    cs_free(insn, count)
                    idx += 1
                } else {
                    // 无效字节：跳过 4 字节（ARM64 定长）
                    out.append(InstructionEntry(id: idx, address: request.startAddress + UInt64(offset), size: 4, mnemonic: ".byte", operands: String(format: "0x%02x%02x%02x%02x", raw[offset], raw[offset + 1], raw[offset + 2], raw[offset + 3]), bytes: ""))
                    offset += 4
                    idx += 1
                }
            }
        }
        return out
    }

    // MARK: - 近似伪代码（指令直译视图，非反编译器输出——界面明确标注）

    static func pseudocode(for instructions: [InstructionEntry]) -> [String] {
        instructions.map { insn in
            let ops = insn.operands
            switch insn.mnemonic {
            case "mov", "movz", "movk", "movn":
                return " \(ops.replacingOccurrences(of: ", ", with: " = "))"
            case "add", "adds":
                return " \(ops.components(separatedBy: ", ").first ?? "") += \(ops.components(separatedBy: ", ").dropFirst(1).joined(separator: " + "))"
            case "sub", "subs":
                return " \(ops.components(separatedBy: ", ").first ?? "") -= \(ops.components(separatedBy: ", ").dropFirst(1).joined(separator: " - "))"
            case "mul", "madd":
                return " \(ops)（乘法）"
            case "ldr", "ldrb", "ldrh", "ldrsb", "ldrsw":
                return " load \(ops) ; // 从内存读取"
            case "str", "strb", "strh":
                return " store \(ops) ; // 写入内存"
            case "b", "bl", "blr", "br":
                return " \(insn.mnemonic == "b" ? "goto" : "call") \(ops)"
            case "b.eq": return " if (eq) goto \(ops)"
            case "b.ne": return " if (ne) goto \(ops)"
            case "b.gt": return " if (>) goto \(ops)"
            case "b.lt": return " if (<) goto \(ops)"
            case "b.ge": return " if (>=) goto \(ops)"
            case "b.le": return " if (<=) goto \(ops)"
            case "cbz": return " if (\(ops.components(separatedBy: ", ").first ?? "") == 0) goto \(ops.components(separatedBy: ", ").dropFirst().joined())"
            case "cbnz": return " if (\(ops.components(separatedBy: ", ").first ?? "") != 0) goto \(ops.components(separatedBy: ", ").dropFirst().joined())"
            case "cmp": return " compare \(ops)"
            case "ret": return " return"
            case "nop": return " /* nop */"
            case "adrp": return " pagePtr \(ops)"
            case "stur", "ldur": return " mem\(insn.mnemonic.hasPrefix("s") ? "store" : "load") \(ops)"
            default:
                return " \(insn.mnemonic) \(ops)"
            }
        }
    }
}
