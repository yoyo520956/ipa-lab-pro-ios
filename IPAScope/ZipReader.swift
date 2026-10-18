import Foundation
import Compression

// 零依赖 ZIP 读取器：
// 只解析 EOCD + central directory，按需解压单条目（Compression raw deflate）。
// 适配 IPA 场景：大文件用 FileHandle 分段读，绝不整包进内存。

final class ZipReader {
    private let fh: FileHandle
    private let fileSize: UInt64
    private(set) var entries: [ZipEntry] = []
    private var entryByPath: [String: ZipEntry] = [:]
    private(set) var totalUncompressed: UInt64 = 0

    init(url: URL) throws {
        fh = try FileHandle(forReadingFrom: url)
        let attr = try FileManager.default.attributesOfItem(atPath: url.path)
        fileSize = (attr[.size] as? NSNumber)?.uint64Value ?? 0
        try locateCentralDirectory()
    }

    deinit {
        try? fh.close()
    }

    // MARK: - EOCD + Central Directory

    private func locateCentralDirectory() throws {
        // EOCD 固定 22 字节起，注释最多 65535 → 最多回扫 65557
        let scanLen = Int(min(fileSize, 65557 + 22))
        try fh.seek(toOffset: fileSize - UInt64(scanLen))
        let tail = fh.readData(ofLength: scanLen)
        let bytes = [UInt8](tail)
        var eocdPos = -1
        var i = bytes.count - 22
        while i >= 0 {
            if bytes[i] == 0x50, bytes[i+1] == 0x4b,
               bytes[i+2] == 0x05, bytes[i+3] == 0x06 {
                eocdPos = i
                break
            }
            i -= 1
        }
        guard eocdPos >= 0 else { throw IPAError.notZip("未找到 ZIP 结束标记（EOCD）") }

        let cdCount = Self.u16(bytes, eocdPos + 10)
        let cdSize = UInt64(Self.u32(bytes, eocdPos + 12))
        let cdOffset = UInt64(Self.u32(bytes, eocdPos + 16))

        try fh.seek(toOffset: cdOffset)
        let cdData = fh.readData(ofLength: Int(cdSize))
        let cd = [UInt8](cdData)

        var pos = 0
        var idx = 0
        while pos + 46 <= cd.count && idx < Int(cdCount) {
            guard cd[pos] == 0x50, cd[pos+1] == 0x4b, cd[pos+2] == 0x01, cd[pos+3] == 0x02 else { break }
            let method = Self.u16(cd, pos + 10)
            let packed = UInt64(Self.u32(cd, pos + 20))
            let size = UInt64(Self.u32(cd, pos + 24))
            let nameLen = Int(Self.u16(cd, pos + 28))
            let extraLen = Int(Self.u16(cd, pos + 30))
            let commentLen = Int(Self.u16(cd, pos + 32))
            let localOff = UInt64(Self.u32(cd, pos + 42))
            guard pos + 46 + nameLen <= cd.count else { break }
            let name = String(bytes: cd[(pos+46)..<(pos+46+nameLen)], encoding: .utf8) ?? ""
            let entry = ZipEntry(id: idx, path: name, size: size, packed: packed,
                                 method: method, offset: localOff)
            entries.append(entry)
            entryByPath[name] = entry
            totalUncompressed += size
            pos += 46 + nameLen + extraLen + commentLen
            idx += 1
        }
    }

    // MARK: - 单条目解压

    func data(for entry: ZipEntry, maxBytes: Int = 96 * 1024 * 1024) throws -> Data {
        guard !entry.isDirectory else { return Data() }
        guard Int(entry.size) <= maxBytes else {
            throw IPAError.tooLarge("\(entry.path) 解压后超 \(ByteFmt.text(UInt64(maxBytes)))")
        }
        // local header：30 字节 + 文件名 + 扩展区（长度可能与 central 不同，必须现场读）
        try fh.seek(toOffset: entry.offset)
        let lh = [UInt8](fh.readData(ofLength: 30))
        guard lh.count == 30, lh[0] == 0x50, lh[1] == 0x4b, lh[2] == 0x03, lh[3] == 0x04 else {
            throw IPAError.notZip("局部头损坏: \(entry.path)")
        }
        let nameLen = Int(Self.u16(lh, 26))
        let extraLen = Int(Self.u16(lh, 28))
        let dataOff = entry.offset + 30 + UInt64(nameLen) + UInt64(extraLen)
        try fh.seek(toOffset: dataOff)
        let comp = fh.readData(ofLength: Int(entry.packed))

        if entry.method == 0 {
            return comp
        }
        if entry.method == 8 {
            return try Self.inflate(comp, outSize: Int(entry.size))
        }
        throw IPAError.unsupported("压缩方法 \(entry.method) 不支持（仅 store/deflate）: \(entry.path)")
    }

    func entry(_ path: String) -> ZipEntry? { entryByPath[path] }

    func entries(in folder: String) -> [ZipEntry] {
        entries.filter { $0.path.hasPrefix(folder) && !$0.isDirectory }
    }

    static func inflate(_ src: Data, outSize: Int) throws -> Data {
        var dst = Data(count: outSize)
        let ok = dst.withUnsafeMutableBytes { db -> Int in
            src.withUnsafeBytes { sb -> Int in
                guard let sp = sb.bindMemory(to: UInt8.self).baseAddress,
                      let dp = db.bindMemory(to: UInt8.self).baseAddress else { return -1 }
                return compression_decode_buffer(dp, outSize, sp, src.count,
                                                 nil, COMPRESSION_ZLIB)
            }
        }
        guard ok >= 0 else { throw IPAError.unsupported("deflate 解压失败") }
        if ok < outSize {
            dst.removeSubrange(ok..<outSize)
        }
        return dst
    }

    static func u16(_ b: [UInt8], _ o: Int) -> UInt16 {
        UInt16(b[o]) | (UInt16(b[o+1]) << 8)
    }

    static func u32(_ b: [UInt8], _ o: Int) -> UInt32 {
        UInt32(b[o]) | (UInt32(b[o+1]) << 8) | (UInt32(b[o+2]) << 16) | (UInt32(b[o+3]) << 24)
    }

    static func u64(_ b: [UInt8], _ o: Int) -> UInt64 {
        var v: UInt64 = 0
        for i in 0..<8 { v |= UInt64(b[o+i]) << (8 * i) }
        return v
    }
}

// MARK: - 错误

enum IPAError: LocalizedError {
    case notZip(String)
    case tooLarge(String)
    case unsupported(String)
    case noBinary(String)

    var errorDescription: String? {
        switch self {
        case .notZip(let s): return "格式错误：\(s)"
        case .tooLarge(let s): return "体积超限：\(s)"
        case .unsupported(let s): return "不支持：\(s)"
        case .noBinary(let s): return "找不到主程序：\(s)"
        }
    }
}
