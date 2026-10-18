# ipa-lab-pro · 本地编译指南

源码快照：commit c314cd4b（第 12 轮，2026-10-19 凌晨）

## 一、环境要求

| 项 | 要求 |
|---|---|
| macOS | 26.x（Xcode 26.2 配套） |
| Xcode | 26.2（CI 同版本；26.x 其他小版本也可试） |
| XcodeGen | `brew install xcodegen` |
| 网络 | 首次打开会自动拉 SPM 依赖（p-x9/MachOKit、weichsel/ZIPFoundation），需能访问 GitHub |

## 二、生成工程并编译

```bash
cd ipa-lab-pro
xcodegen generate          # 生成 IPALabPro.xcodeproj
open IPALabPro.xcodeproj   # Xcode 打开，等 SPM resolve 完成
# 选一个目的地（真机或模拟器），Cmd+B
```

命令行版：

```bash
xcodegen generate
xcodebuild -project IPALabPro.xcodeproj -scheme IPALabPro \
  -destination 'generic/platform=iOS' -configuration Release \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | tee build.log
```

## 三、当前已知失败点（CI 第 12 轮实锤，本地重点看这两处）

CI（Xcode 26.2 / iOS 26.2 SDK）报 5 个 error，全部集中在两个文件。本地编译请重点看这两处，**把完整的错误 + 所有 note/candidate 行发给我**：

**App/Views/AnalysisTabs.swift:124**（DisasmTab.body 内，ScrollView > LazyVStack > if 分支里）

```swift
let pseudoLines = DisasmService.pseudocode(for: instructions)
let lineModels = Self.makePseudoLines(pseudoLines, instructions)
ForEach(lineModels, id: \.id) { lm in        // ← error 行
    Text(lm.text)                             // ← 级联 error
```

CI 错误：`cannot convert value of type '[PseudoLine]' to expected argument type 'Binding<C>'` + `generic parameter 'C' could not be inferred` + `cannot infer key path type from context`。

**App/Views/BundleTab.swift:58**（List 内）

```swift
List {
    ForEach(visibleCapped, id: \.path) { entry in   // ← error 行
        Image(systemName: icon(for: entry))          // ← 级联 error
```

CI 错误：`cannot convert value of type '[ArchiveEntry]' to expected argument type 'Range<Int>'` / `'Binding<C>'`。

**排查方向提示**：同一工程其他 30+ 处 ForEach（`[Project]`、`[MachOSymbolInfo]` 等同形态）全部编译通过；`PseudoLine: Identifiable`（fileprivate，id: Int）与 `ArchiveEntry: Identifiable`（internal，id: String 计算属性）符合性均完好。怀疑点：ViewBuilder 深层嵌套中调用 static 方法返回 fileprivate 类型数组触发 iOS 26.2 SDK ForEach 重载（新增 Binding/editActions 系）决议异常；或两文件更上游类型（DisasmService/InstructionEntry/MachOInfo 等）在 26.2 SDK 下的签名变化导致 body 整体 type-check 失败，ForEach 只是症状。**本地完整 note 列表能一锤定音。**

## 四、项目结构

```
App/
  Bridging/IPALab-Bridging-Header.h    # 桥接头 → Vendor/capstone/include/capstone/capstone.h
  Domain/       Models.swift, PerformanceProfile.swift
  Services/     AnalysisEngine, MachOService, DisasmService, ObjCMetadataService,
                ProjectStore, ReportService, ZipService, CompatCheck
  Views/        RootView, ProjectsView, ProjectDetailView, AnalysisTabs, BundleTab,
                DisasmTab(在AnalysisTabs.swift), SettingsView, DesignSystem
  IPALabApp.swift
Vendor/capstone/    # capstone 5.0.9 精简版：7 个核心 .c + 27 个头文件 + ARM/AArch64 巨表 .inc
Tests/              # 单元测试
project.yml         # XcodeGen 工程定义（iOS 16.0 target，C 优化 -O1）
docs/ NOTICE.md README.md
```

## 五、如果本地编译通过

直接 Cmd+R 跑起来验证功能即可；也可以打 IPA 给我回传结果——CI 侧我会根据你本地看到的第一手错误继续修。
