# IPA Lab Pro — iOS 核心引擎验证结果（阶段A交付物 3/3）

## 一、验证方法

由于无 Mac，验证在 GitHub Actions 免费公开仓库的 macOS runner（macos-26 + Xcode 26.2 + iPhone SE (3rd generation) 模拟器）上执行：
构建真实 iOS App（ARM64）并运行 XCTest 单元测试，测试内容全部为**真实引擎执行**而非桩测试：

| 引擎 | 验证内容 |
|---|---|
| Capstone 5.0.9 | cs_open(CS_ARCH_ARM64)→反汇编 `ret`(C0 03 5F D6) 与 `mov x0,#0x1337`(E0 66 82 D2) → 断言助记符与操作数 |
| MachOKit 0.55.0 | 解析测试宿主 App 自身 Mach-O → 断言加载命令>5、__TEXT 段、__text 节存在；提取段/节/符号/加载命令结构 |
| ZIPFoundation 0.9.20 | 真实创建 zip→回读→断言内容一致 |
| 组合 | ObjC 元数据分析（不崩溃+说明完整）、近似伪代码生成、兼容性自检三引擎 |
| 安全 | zip slip 路径拒绝测试 |
| 平台层 | ProjectStore CRUD/搜索/删除；字符串扫描（含中文 UTF-8） |

## 二、验证结果（构建后更新）

| 项 | 结果 |
|---|---|
| XcodeGen 工程生成 | 待构建 |
| Capstone（ARM64+ARM）iOS ARM64 编译 | 待构建 |
| MachOKit SPM 解析与编译 | 待构建 |
| ZIPFoundation 编译 | 待构建 |
| 单元测试（模拟器执行） | 待构建 |
| 未签名 IPA 打包 | 待构建 |

构建 run 编号与结论将在下表回填：

| Run | 结果 | 备注 |
|---|---|---|
| （待填） | | |

## 三、预先评估结论（基于源码审查与平台 API 事实）

1. **Ghidra 不可移植（⛔）**：Ghidra 核心为 Java/Swing，依赖 JVM；其反编译器为 C++ 原生二进制（按平台分发），无 iOS 目标。iOS 沙盒无 JVM。此结论为确定性，无需构建验证。
2. **Capstone 可移植性（高）**：纯 C，无系统调用依赖，官方支持裸机编译；只需 ARM64/ARM 两个架构目录 + 7 个公共 .c 文件，用 `CAPSTONE_HAS_ARM64/ARM` 宏裁剪。
3. **MachOKit 可移植性（高）**：纯 Swift + 内嵌 C 头（MachOKitC），平台要求 iOS 13+，SPM 一等支持；依赖链（swift-fileio 等）均为纯 Swift。
4. **真反编译引擎现状（如实说明）**：当前开源生态中无"可在 iOS App 内静态链接的成熟 ARM64 反编译器"（RetDec/Snowman 以 x86 为主且体量巨大；Ghidra 需 JVM）。因此 v1.0 的伪代码 = Capstone 反汇编上的指令直译视图，界面明确标注，不冒充反编译器输出。
5. **App Store 加密包边界**：从 App Store 下载的 IPA 主二进制 cryptid=1（FairPlay 文件态密文），其 __TEXT 部分文件态不可反汇编。本 App 只分析明文部分并在界面明确提示，不做也不应做解密。
