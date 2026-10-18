# NOTICE / 第三方组件声明

本软件（IPA Lab Pro）使用了以下开源组件，感谢原作者：

## 1. MachOKit
- 来源：https://github.com/p-x9/MachOKit
- 版本：0.55.0（commit f0c6565435659aeb23369810874578d5344d13b7）
- 许可证：MIT License
- 用途：Mach-O 文件结构解析
- 版权：(c) p-x9 及贡献者
- MIT 原文见 https://github.com/p-x9/MachOKit/blob/main/LICENSE

## 2. Capstone Engine
- 来源：https://github.com/capstone-engine/capstone
- 版本：5.0.9（commit 022575848782a4801fd150fdbc927effcbca0864）
- 许可证：BSD-3-Clause（Capstone 主许可）与 BSD-3-Clause（LLVM 衍生代码）
- 用途：ARM64/ARM 反汇编
- 许可原文：随本仓库分发于 Vendor/capstone/LICENSE.TXT 与 Vendor/capstone/LICENSE_LLVM.TXT
- 版权：(c) Capstone Engine 作者与贡献者；LLVM 部分 (c) LLVM 项目

## 3. ZIP Foundation
- 来源：https://github.com/weichsel/ZIPFoundation
- 版本：0.9.20
- 许可证：MIT License
- 用途：ZIP/IPA 归档读取与解包
- 版权：(c) Thomas Zoechling (weichsel)
- MIT 原文见 https://github.com/weichsel/ZIPFoundation/blob/main/LICENSE

## 集成方式说明
- MachOKit 与 ZIP Foundation 通过 Swift Package Manager 以原始代码集成，未做任何修改。
- Capstone 以源码 vendor 方式集成（仅 AArch64/ARM 架构 + 公共编译单元），许可原文文件原样保留，未修改任何源文件内容。
