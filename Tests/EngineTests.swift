//
//  EngineTests.swift
//  IPA Lab Pro
//  引擎真实执行验证（阶段B验收）
//

import XCTest
@testable import IPALabPro

final class EngineTests: XCTestCase {

    // MARK: - Capstone

    func testCapstoneRetInstruction() throws {
        var handle: csh = 0
        XCTAssertEqual(cs_open(CS_ARCH_ARM64, CS_MODE_LITTLE_ENDIAN, &handle), CS_ERR_OK)
        defer { cs_close(&handle) }
        let bytes: [UInt8] = [0xC0, 0x03, 0x5F, 0xD6] // ret
        var insn: UnsafeMutablePointer<cs_insn>?
        let count = cs_disasm(handle, bytes, 4, 0x1000, 1, &insn)
        defer { cs_free(insn, count) }
        XCTAssertEqual(count, 1)
        XCTAssertEqual(String(cString: insn!.pointee.mnemonic), "ret")
    }

    func testCapstoneMovzInstruction() throws {
        var handle: csh = 0
        XCTAssertEqual(cs_open(CS_ARCH_ARM64, CS_MODE_LITTLE_ENDIAN, &handle), CS_ERR_OK)
        defer { cs_close(&handle) }
        let bytes: [UInt8] = [0xE0, 0x66, 0x82, 0xD2] // mov x0, #0x1337
        var insn: UnsafeMutablePointer<cs_insn>?
        let count = cs_disasm(handle, bytes, 4, 0x2000, 1, &insn)
        defer { cs_free(insn, count) }
        XCTAssertEqual(count, 1)
        XCTAssertEqual(String(cString: insn!.pointee.mnemonic), "mov")
        XCTAssertTrue(String(cString: insn!.pointee.op_str).contains("0x1337"))
    }

    // MARK: - MachOKit

    func testMachOKitParsesHostBinary() throws {
        // 测试宿主 = 本 App；解析自身 Mach-O 是真实的端到端验证
        guard let url = Bundle.main.executableURL else { return XCTFail("无宿主二进制") }
        let machO = try MachOFile(url: url)
        let commands = machO.loadCommands
        XCTAssertGreaterThan(commands.count, 5)
        let textSeg = machO.segments64.first { $0.segmentName == "__TEXT" }
        XCTAssertNotNil(textSeg, "必须有 __TEXT 段")
        let sections = machO.sections64
        XCTAssertTrue(sections.contains { $0.sectionName == "__text" }, "必须有 __text 节")
    }

    func testMachOServiceExtractsInfo() throws {
        guard let url = Bundle.main.executableURL else { return XCTFail("无宿主二进制") }
        let svc = MachOService(config: AnalysisConfig())
        let info = try svc.parseFile(at: url)
        XCTAssertTrue(info.magic.contains("MH_MAGIC_64"))
        XCTAssertTrue(info.cputype.contains("ARM"))
        XCTAssertFalse(info.segments.isEmpty)
        XCTAssertFalse(info.loadCommands.isEmpty)
        XCTAssertTrue(info.codeSigned || info.symbols.count > 0)
    }

    // MARK: - ZIP

    func testZipSelfCheck() {
        XCTAssertTrue(ZipService.selfCheck())
    }

    func testZipSlipPathRejected() {
        XCTAssertFalse(ZipService.isSafeEntryPath("../../etc/passwd"))
        XCTAssertFalse(ZipService.isSafeEntryPath("/absolute/path"))
        XCTAssertTrue(ZipService.isSafeEntryPath("Payload/App.app/Info.plist"))
    }

    // MARK: - 字符串扫描

    func testScanRangeFindsStrings() {
        var payload = Data("hello world".utf8)
        payload.append(0)
        payload.append(Data("IPA Lab Pro 中文测试".utf8))
        payload.append(0)
        var found: [String] = []
        MachOService.scanRange(data: payload, from: 0, to: payload.count, minLen: 4) { s, _, _ in
            found.append(s)
        }
        XCTAssertTrue(found.contains("hello world"))
        XCTAssertTrue(found.contains("IPA Lab Pro 中文测试"))
    }

    // MARK: - 近似伪代码

    func testPseudocodeGeneration() {
        let insns = [
            InstructionEntry(id: 0, address: 0, size: 4, mnemonic: "mov", operands: "x0, #8", bytes: ""),
            InstructionEntry(id: 1, address: 4, size: 4, mnemonic: "ret", operands: "", bytes: "")
        ]
        let lines = DisasmService.pseudocode(for: insns)
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[0].contains("x0"))
        XCTAssertTrue(lines[1].contains("return"))
    }

    // MARK: - ObjC（验证不崩溃 + 输出结构完整）

    func testObjCAnalysisOnHostBinary() throws {
        guard let url = Bundle.main.executableURL else { return XCTFail("无宿主二进制") }
        let macho = MachOService(config: AnalysisConfig())
        let info = try macho.parseFile(at: url)
        let svc = ObjCMetadataService(config: AnalysisConfig())
        let result = svc.analyze(at: url, machO: info)
        XCTAssertFalse(result.parseNote.isEmpty, "必须有解析说明")
    }

    // MARK: - 兼容性

    func testCompatCheckEngines() {
        let report = CompatCheck.run()
        XCTAssertEqual(report.engineCapstone, "正常")
        XCTAssertEqual(report.engineMachOKit, "正常")
        XCTAssertEqual(report.engineZip, "正常")
        XCTAssertGreaterThan(report.totalMemoryMB, 0)
    }

    // MARK: - 项目存储

    @MainActor
    func testProjectStoreCRUD() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let indexBackup = docs.appendingPathComponent("projects.index.json.backup-test")
        let index = docs.appendingPathComponent("projects.index.json")
        try? FileManager.default.removeItem(at: index)
        let store = ProjectStore()
        let before = store.projects.count
        let p = store.create(name: "test-project-\(UUID().uuidString.prefix(6))")
        XCTAssertEqual(store.projects.count, before + 1)
        p.isFavorite = true
        store.update(p)
        XCTAssertEqual(store.project(id: p.id)?.isFavorite, true)
        XCTAssertTrue(store.search(text: p.name).contains { $0.id == p.id })
        store.delete(p)
        XCTAssertEqual(store.projects.count, before)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.directory(for: p).path))
        try? FileManager.default.removeItem(at: index)
        _ = indexBackup
    }
}
