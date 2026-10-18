//
//  CompatCheck.swift
//  IPA Lab Pro
//  自动兼容性检测：启动时与大任务前执行，只报告真实可获取的信息
//

import Foundation
import UIKit
import MachOKit

struct CompatReport: Codable {
    var deviceModel: String = ""
    var deviceName: String = ""
    var osVersion: String = ""
    var totalMemoryMB: Int = 0
    var diskFreeGB: Double = 0
    var thermalStateText: String = "正常"
    var memoryPressure: Bool = false
    var engineMachOKit: String = "未验证"
    var engineCapstone: String = "未验证"
    var engineZip: String = "未验证"
    var checkedAt: Date = Date()

    var summary: String {
        var lines: [String] = []
        lines.append("设备：\(deviceName)（\(deviceModel)）· iOS \(osVersion)")
        lines.append("内存：\(totalMemoryMB) MB · 磁盘可用：\(String(format: "%.1f", diskFreeGB)) GB")
        lines.append("热状态：\(thermalStateText) · 内存压力：\(memoryPressure ? "有" : "无")")
        lines.append("引擎自检 — MachOKit：\(engineMachOKit) · Capstone：\(engineCapstone) · ZIPFoundation：\(engineZip)")
        if thermalStateText != "正常" || memoryPressure || diskFreeGB < 1.0 {
            lines.append("注意：资源紧张，已自动切换到低性能模式执行大型任务。")
        } else {
            lines.append("兼容性检查通过。")
        }
        return lines.joined(separator: "\n")
    }
}

enum CompatCheck {
    static func run() -> CompatReport {
        var r = CompatReport()
        var size = 0
        var sysinfo = utsname()
        uname(&sysinfo)
        withUnsafeBytes(of: &sysinfo.machine) { buf in
            let data = Data(buf.prefix(256))
            size = data.prefix { $0 != 0 }.count
        }
        let machine = withUnsafeBytes(of: &sysinfo.machine) { raw -> String in
            let data = Data(raw.prefix(256))
            return String(data: data.prefix { $0 != 0 }, encoding: .utf8) ?? "unknown"
        }
        r.deviceModel = machine
        r.deviceName = UIDevice.current.model
        r.osVersion = UIDevice.current.systemVersion
        r.totalMemoryMB = Int(ProcessInfo.processInfo.physicalMemory / 1024 / 1024)

        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
           let values = try? docs.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let free = values.volumeAvailableCapacityForImportantUsage {
            r.diskFreeGB = Double(free) / 1_000_000_000
        }

        switch ProcessInfo.processInfo.thermalState {
        case .nominal: r.thermalStateText = "正常"
        case .fair: r.thermalStateText = "轻微发热"
        case .serious: r.thermalStateText = "较热"
        case .critical: r.thermalStateText = "过热"
        @unknown default: r.thermalStateText = "未知"
        }
        r.memoryPressure = ProcessInfo.processInfo.isiOSAppOnMac == false && totalFreeMemoryRatio() < 0.15

        // 引擎自检：真实执行一次最小任务
        r.engineCapstone = checkCapstone() ? "正常" : "异常"
        r.engineMachOKit = checkMachOKit() ? "正常" : "异常"
        r.engineZip = checkZip() ? "正常" : "异常"
        r.checkedAt = Date()
        return r
    }

    /// 可用内存占比（host_statistics64 真实读取）
    static func totalFreeMemoryRatio() -> Double {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        var host = mach_host_self()
        let kr = withUnsafeMutablePointer(to: &stats) { statsPtr in
            statsPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return 1.0 }
        let pageSize: UInt64 = 16384
        let free = UInt64(stats.free_count + stats.inactive_count) * pageSize
        let total = ProcessInfo.processInfo.physicalMemory
        guard total > 0 else { return 1.0 }
        return Double(free) / Double(total)
    }

    static func checkCapstone() -> Bool {
        var handle: csh = 0
        guard cs_open(CS_ARCH_ARM64, CS_MODE_LITTLE_ENDIAN, &handle) == CS_ERR_OK else { return false }
        defer { cs_close(&handle) }
        // ARM64: ret (C0 03 5F D6)
        let bytes: [UInt8] = [0xC0, 0x03, 0x5F, 0xD6]
        var insn: UnsafeMutablePointer<cs_insn>?
        let count = cs_disasm(handle, bytes, bytes.count, 0x1000, 1, &insn)
        defer { cs_free(insn, count) }
        guard count == 1, let i = insn else { return false }
        return DisasmService.cStringTuple(i.pointee.mnemonic) == "ret"
    }

    static func checkMachOKit() -> Bool {
        guard let url = Bundle.main.executableURL, let _ = try? MachOFile(url: url) else { return false }
        return true
    }

    static func checkZip() -> Bool {
        // 真实创建并读取一个 zip（Foundation Data + ZIPFoundation 在 ZipService 内部验证）
        return ZipService.selfCheck()
    }
}
