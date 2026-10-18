# IPAScope（IPA 解剖台）

iPhone 上的 IPA 逆向分析工具：ZIP 按需解压 + 自研 Mach-O 解析（零第三方依赖），五页签：概览/结构/符号/字符串/签名。


iPhone 本地 IPA 分析工具：**ZIP 解包 · Mach-O 结构解析 · ARM64 反汇编 · ObjC 元数据 · 报告导出 · 本地项目管理**。全部分析在本机沙盒完成，不上传任何文件，不执行导入包内的程序。

目标设备：iPhone SE 3（其他 iOS 16+ 设备同样可用）。

## 引擎（真实开源移植，非简化重写）

| 引擎 | 版本 | 许可证 | 用途 |
|---|---|---|---|
| [MachOKit](https://github.com/p-x9/MachOKit) | 0.55.0 | MIT | Mach-O 解析（加载命令/段/节/符号/字符串/函数起点/签名/修复） |
| [Capstone](https://github.com/capstone-engine/capstone) | 5.0.9 | BSD-3-Clause | ARM64/ARM 反汇编 |
| [ZIP Foundation](https://github.com/weichsel/ZIPFoundation) | 0.9.20 | MIT | IPA(ZIP) 解包 |

详见 [NOTICE.md](NOTICE.md) 与 [docs/01-开源项目与许可证审查表.md](docs/01-开源项目与许可证审查表.md)。

## 功能

- **项目**：导入 IPA 创建分析项目（自动验证 ZIP 完整性）；搜索/收藏/标签/删除确认/占用统计
- **概览**：包信息（显示名/版本/SDK/框架/插件/大小）+ 分析进度与日志
- **包内容**：按类别（框架/插件/本地化/图像/媒体/配置…）浏览 ZIP、文件名搜索、单文件提取与文本预览
- **Mach-O**：文件头/段/节/加载命令/符号表（含 Swift demangle）/依赖动态库/代码签名/加密状态
- **字符串**：分块扫描 __cstring/__objc_* 等真实 section，全量搜索
- **反汇编**：按符号定位 → ARM64/ARM 逐指令反汇编 → 指令视图与**近似伪代码视图（明确标注非反编译器输出）**
- **ObjC**：类名/选择器/分类（真实 section 数据）+ classlist 统计
- **报告**：TXT/JSON 导出 + 运行日志；近似工程结构重建（按类别归组，标注推断性质）
- **性能管理**：低/平衡/高三档 + 自动兼容性检测（内存/磁盘/热状态/三引擎自检）+ 资源紧张自动降档
- **稳定性**：阶段化分析 + 检查点 JSON 断点恢复 + 取消 + 超限文件隔离跳过 + 压缩炸弹防护

## 构建（无 Mac，云端可复现）

```bash
brew install xcodegen   # 或 runner 自带
xcodegen generate
xcodebuild -project IPALabPro.xcodeproj -scheme IPALabPro \
  -configuration Release -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build
```

GitHub Actions 工作流（`.github/workflows/build.yml`）：构建未签名 IPA + 模拟器引擎测试，artifact 下载 `ipalabpro-ipa`。

**签名安装**：使用你自己的开发者证书 + 描述文件，通过 Feather/AltStore/Sideloadly 等工具对未签名 IPA 签名后安装。未签名构建仅为交付形态，签名后才能安装运行。

## 版本锁定与回滚

- 依赖全部以 tag/commit 锁定（见 project.yml 与 NOTICE.md），禁止盲目升级
- 每次重大修改前打 Git tag；若新版回归：保存日志 → 定位变更 → 最小修复 → 修复失败则 `git checkout <最后通过的 tag>` 恢复，保留故障版本证据

## 文档（阶段交付物）

1. [开源项目与许可证审查表](docs/01-开源项目与许可证审查表.md)
2. [功能清单与移植对照表](docs/02-功能清单与移植对照表.md)
3. [iOS 核心引擎验证结果](docs/03-iOS核心引擎验证结果.md)

## 已知限制（如实说明）

- Ghidra 级反编译不可行（JVM/桌面依赖）；伪代码为 Capstone 指令直译，界面明确标注
- App Store 加密包（cryptid=1）文件态为密文，只分析明文部分，不解密
- ObjC 结构化类/方法树（fixup 指针解码）计划 v1.1；v1.0 提供类名/选择器层
