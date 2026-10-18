import Foundation
import Combine

// 分析总引擎：选 IPA → 按 ZIP 目录按需解压 → 找主二进制 → Mach-O 全解析
// 全程安全作用域 + 后台线程 + 主线程回调

@MainActor
final class AnalysisEngine: ObservableObject {
    enum Phase: Equatable {
        case idle
        case working(String)
        case done
        case failed(String)
    }

    @Published var phase: Phase = .idle
    @Published var result = AnalysisResult()
    @Published var pickedURL: URL?
    @Published var fileName: String = ""

    private var zip: ZipReader?
    private var binData: Data = Data()

    func open(url: URL) {
        phase = .working("打开文件…")
        result = AnalysisResult()
        binData = Data()
        fileName = url.lastPathComponent
        pickedURL = url
        let scoped = url.startAccessingSecurityScopedResource()
        Task {
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            await self.analyze(url: url)
        }
    }

    func reset() {
        phase = .idle
        result = AnalysisResult()
        binData = Data()
        pickedURL = nil
        fileName = ""
        zip = nil
    }

    // MARK: - 主流程

    private func analyze(url: URL) async {
        do {
            phase = .working("读取 ZIP 目录…")
            let z = try ZipReader(url: url)
            zip = z

            let zr = z
            result.entries = zr.entries
            result.totalUncompressed = zr.totalUncompressed

            // 定位 Payload/*.app/
            phase = .working("定位 App 包…")
            let appEntries = zr.entries.filter { $0.path.hasPrefix("Payload/") && !$0.isDirectory }
            guard !appEntries.isEmpty else { throw IPAError.notZip("包内无 Payload/ 目录") }
            let appFolder = "Payload/" + ((appEntries[0].path as NSString).deletingLastPathComponent) + "/"
            result.appFolder = appFolder

            // Info.plist
            phase = .working("读取 Info.plist…")
            if let ip = zr.entry(appFolder + "Info.plist") {
                let d = try zr.data(for: ip)
                result.info = Extractors.appInfo(from: d)
            }

            // 主二进制
            phase = .working("解压主二进制…")
            let exeName = result.info.executable.isEmpty ? "主程序" : result.info.executable
            let binPath = appFolder + exeName
            guard let binEntry = zr.entry(binPath) else {
                throw IPAError.noBinary("\(binPath)（查 Info.plist 的 CFBundleExecutable）")
            }
            binData = try zr.data(for: binEntry)
            result.summary.fileSize = binEntry.size

            // Mach-O
            phase = .working("解析 Mach-O 结构…")
            let parser = MachOParser(data: binData)
            try parser.parse()
            result.segments = parser.segments
            result.allSections = parser.allSections
            result.dylibs = parser.dylibs
            result.summary.minOS = parser.summary.minOS
            result.summary.sdkVersion = parser.summary.sdkVersion
            result.summary.uuid = parser.summary.uuid
            result.summary.encrypted = parser.summary.encrypted
            result.summary.fileType = parser.summary.fileType
            result.summary.format = parser.summary.format
            result.summary.symbolCount = parser.summary.symbolCount
            result.summary.dylibCount = parser.summary.dylibCount
            result.symbols = parser.symbolsRaw

            // 字符串与 ObjC
            phase = .working("提取类名与字符串…")
            var strings: [String] = []
            for sec in parser.allSections {
                let nm = sec.name
                guard nm == "__cstring" || nm == "__objc_classname" || nm == "__objc_methname" else { continue }
                let d = parser.sectionData(sec, from: binData, limit: 8 * 1024 * 1024)
                strings.append(contentsOf: Extractors.cStrings(from: d))
            }
            if result.summary.symbolCount > 0 {
                strings.append(contentsOf: parser.symbolsRaw)
            }
            let objc = Extractors.objcNames(strings)
            result.classNames = objc.classes
            result.methodNames = objc.methods
            result.cstrings = Array(Set(strings)).sorted()
            result.summary.classCount = objc.classes.count
            result.summary.methodCount = objc.methods.count

            // 描述文件
            phase = .working("读取描述文件…")
            if let mp = zr.entry(appFolder + "embedded.mobileprovision") {
                let raw = try zr.data(for: mp)
                result.provision = Extractors.provision(from: raw)
            }

            phase = .done
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    // MARK: - 给详情页用的原始数据

    func sectionRaw(_ sec: MachSection) -> Data {
        guard !binData.isEmpty else { return Data() }
        let parser = MachOParser(data: binData)
        return parser.sectionData(sec, from: binData, limit: 4096)
    }
}
