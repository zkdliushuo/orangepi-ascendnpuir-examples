# 工具链内部机制与验证记录

本文解释分支选择、模板 bitcode、补丁与链接机制，并保留已完成的验证记录。
部署操作请见 [工具链部署](01-toolchain-build.md)。

## 1. 为什么要两个分支

| 组件 | 分支 | 说明 |
| --- | --- | --- |
| `bishengir-compile` | `dev/regbase` | A5（Ascend310B / 950）前端。`include/bishengir/Tools/bishengir-compile/Options.td` 里注册了 `Ascend310B1..B4`；`include/bishengir/Dialect/HACC/Targets/NPUTargetSpec.td` 里 `Ascend310B_BaseSpec.Arch = "dav-m300"` |
| `hivmc` | `master` | `dev/regbase` 中 `lib/Tools/bishengir-compile/Utility.cpp` 把下游工具名写死为 `hivmc-a5`，仓库里没有 `tools/hivmc`；只有 master 带 `lib/Tools/hivmc/A5`（`HIVMCMainA5.cpp` / `PassPipelineA5.cpp`），且 master 同样是 BiShengIR **1.2.0** |

版本一致这一点很关键，见第 7 节。

## 2. 共享一个 LLVM/MLIR 构建目录

两个组件都基于同一份 `deps/AscendNPU-IR/third-party/llvm-project`。脚本先用
`LLVM_EXTERNAL_BISHENGIR_SOURCE_DIR=../deps/AscendNPU-IR-a5/bishengir` 配置构建目录
并编译前端，然后**在同一个构建目录**里改成
`LLVM_EXTERNAL_BISHENGIR_SOURCE_DIR=../deps/AscendNPU-IR` 再编译 hivmc。
LLVM/MLIR 库只编译一次，切换只会让 bishengir 部分的产物失效。

参考耗时（3 核香橙派 20T，`-j3`）：

| 阶段 | 耗时 |
| --- | --- |
| 首次配置 + 编译 LLVM/MLIR + 前端 | 约 5.5 小时 |
| 切换到 master 并编译 hivmc（含重链接） | 约 2.5 小时 |

## 3. 模板 bitcode 是什么、为什么要抓

"抓取 A5 模板 bitcode"指的是：把 CANN 自带的 `hivmc-a5` 内部使用的那份
**设备侧模板库（LLVM bitcode）**提取成普通文件，因为编译 310B1 内核时必须把它
和内核 IR 链接在一起。对应的脚本是 `scripts/05_capture_a5_templates.sh`。

### 3.1 什么是"模板"

前端 lowering 只负责把算子写成"调用若干设备例程"的 IR，真正的设备实现放在模板库
里。在 `out/a5-templates/regbaseM300.bc` 中可以直接看到编译期残留的源文件路径：

```
.../bishengir/lib/Template/lib/RegBase/Vector/Copy1D.cpp
.../bishengir/lib/Template/lib/RegBase/CubeM300/Fixpipe.cpp
.../bishengir/lib/Template/include/RegBase/DMAUtils.h
AscendNPU-IR Compiler 202602 clang version 15.0.5
```

（该文件里 `load_gm_to_ubuf` 出现 166 次、`store_ubuf_to_gm` 出现 177 次，
此外还有 `vadd / vsts / vlds / vcmp` 等向量内建封装。）

与之对应，流水线产出的设备 IR 里正是对这些例程的调用：

```llvm
define private void @load_gm_to_ubuf_1d_int16_t(...)   ; GM → UB 拷贝
define private void @store_ubuf_to_gm_1d_int16_t(...)  ; UB → GM 拷贝
declare <128 x i16> @llvm.hivm.vadd.s.x.v128i16(...)   ; 向量加
```

bitcode 是 LLVM IR 的二进制形式（文件头 `42 43 c0 de`），不是机器码：它是交给
设备编译器（`bisheng` / `ccec`，target `dav-m300`）做链接和代码生成的中间产物。

### 3.2 为什么叫"抓"而不是"下载"

| 文件 | 在 CANN 中的形态 | 获取方式 |
| --- | --- | --- |
| `host.bc` | 作为文件安装在 `tools/bishengir/lib/host.bc` | 直接复制（与抓取到的 `autogen_host.bc` 逐字节相同） |
| `regbaseM300.bc` | 没有安装成文件；内置在 `hivmc-a5` 中，编译时才写到临时路径传给设备编译器（内部名 `autogen_regbaseM300.bc`） | 用捕获 shim 保存下来 |

### 3.3 抓取机制

`examples/vecadd/tools/capture_bisheng_310b1.sh` 充当"假的 bisheng"：

1. 用 CANN 的 `bishengir-compile-a5` 跑一遍示例 MLIR（它内部的 `hivmc-a5` 会把
   模板路径以 `-cce-link-aicore-ll-module <file>.bc` 的形式传给设备编译器）；
2. shim 在转发给真正的 `bisheng` 之前，把该 `.bc` 复制成 `m300-support.bc`，
   同时把每次交给设备编译器的 `.ll`（设备模块、host 模块）也存档；
3. 产物：`out/a5-templates/host.bc`、`out/a5-templates/regbaseM300.bc`，
   以及顺带的参考设备 IR `out/a5-templates/device-reference.ll`。

### 3.4 谁在用它

自建的 `hivmc`（master）没有把模板编译进二进制（未开启
`BISHENGIR_BUILD_TEMPLATE`），因此 `scripts/20_build_vecadd.sh` 必须显式传入：

```bash
--link-aicore-bitcode=out/a5-templates/regbaseM300.bc       # 设备侧模板
--hivmc-args=--link-host-bitcode=out/a5-templates/host.bc   # host 侧模板
```

不传会报：

```
[ERROR]cannot find any bitcode files for coreType:1
[WARNING]cannot find bitcode from hivm attribute for host!
```

CANN 自带的 `hivmc-a5` 内置这两份文件，因此它在同样场景下不传也能编译；
本仓库选择从 toolkit 抓取，保证模板与板上驱动/固件一致。

## 4. 前端补丁（`patches/frontend/`）

该分支主要按 clang 开发，GCC 11 会拦下几处 clang 容忍的写法：

1. `0001-hfusion-matmul-anon-namespace.patch`
   `lib/Conversion/HFusionToHIVM/Matmul.cpp` 里在匿名命名空间中声明的模板
   `MatmulOpToHIVMMatmulOp`，其显式特化写在了命名空间之外：
   `explicit specialization ... outside its namespace must use a
   nested-name-specifier`。修法是把特化包进 `namespace { ... }`。
2. `0002-arith-to-hivmave-aptypehelper.patch`
   `lib/Conversion/ArithToHIVMAVE/ArithToHIVMAVE.cpp` 在类作用域内对成员类模板
   `APTypeHelper<T>` 做显式特化（`explicit specialization in non-namespace
   scope`，`-fpermissive` 也无法放行）。修法是把两个 helper 提升到命名空间
   作用域（`PLTAPTypeHelper` / `VCIVCPAPTypeHelper`），类内用别名模板引用。
3. `0003-execution-engine-static-cast.patch`
   `lib/ExecutionEngine/CreateHostMain.cpp` 中的
   `static_cast<ShapedType (*)(const Type &)>(cast<ShapedType>)`：GCC 无法在该
   上下文解析重载集（`invalid static_cast from <unresolved overloaded
   function type>`），改为无捕获 lambda。
4. `0004-triton-verifybarrier-inline-*.patch`
   `triton/.../TritonNvidiaGPU/Transforms/Utility.h/.cpp`：`verifyBarrierType`
   的定义在 `TritonNvidiaGPUTransforms`，而链接命令行里该库排在
   `TritonNvidiaGPUIR` 之前，导致 `undefined reference`。改为在头文件里
   `inline` 定义。

## 5. 后端补丁（`patches/hivmc/`）

1. `0001-arith-to-hivmave-aptypehelper.patch` —— 与前端第 2 条相同的 GCC 问题，
   master 上同样存在。
2. `0002-triton-verifybarrier-inline-*.patch` —— 与前端第 4 条相同。
3. `0003-hivmc-cmake-link-group.patch` ——
   `tools/hivmc/CMakeLists.txt` 把库列表放进链接分组。BiShengIR 与 Triton 的
   静态库互相成环（`BiShengIRHIVMTransforms ↔ BiShengIRHIVMCLib`、
   `TritonAscendGPUToLLVM ↔ TritonAscendGPUToDPX`），一次左到右扫描无法解析，
   典型报错是
   `undefined reference to 'mlir::hivm::createFlattenModulePass()'`。
   CMake 生成的命令行里最后一组库（来自工具的 `DEPENDS`）仍未被分组包住，
   因此 `scripts/11_build_hivmc.sh` 用 `scripts/lib/relink_hivmc.py`
   重新生成一条把所有归档包在同一个组里的链接命令。
4. `0004-hivmc-a5-dav-m300-arch.patch` ——
   `lib/Tools/hivmc/A5/HIVMCMainA5.cpp` 里设备架构只区分
   "Ascend950 → `dav-c310`，其余 → `dav-c220`"，于是 Ascend310B 被交给 `ccec`
   当作 `dav-c220-vec` 编译，报
   `fatal error: error in backend: Do not know how to split the result of this operator!`。
   补丁增加 `isAscend310B(target) → dav-m300` 分支（与 CANN 自带 `hivmc-a5`
   实际使用的架构一致）。

## 6. 构建开关与两个坑

* `-DBISHENGIR_BUILD_HIVMC=ON`：默认虽然是 ON，但构建目录里可能已被缓存成 OFF。
* `-DLLVM_INCLUDE_TESTS=ON -DMLIR_INCLUDE_TESTS=ON`：hivmc 的库列表里
  **无条件**包含 `MLIRTestTransforms`、`TritonTestDialect` 等测试库，
  否则 CMake 直接报 `The dependency target "MLIRTestTransforms" ... does not exist`。
* `SkewShapeTable.inc`：由 `build-tools/coverage/shape_registry.py` 生成，
  但生成物只通过 `add_dependencies` 挂在库目标上，对象库没有依赖关系，
  `-j3` 下会与 `ShapeRegistry.cpp` 的编译竞态（`SkewShapeTable.inc: No such
  file or directory`）。脚本在编译前显式生成一次。

## 7. 验证产物

```bash
./out/bin/bishengir-compile --version          # bishengir-compile 1.2.0
./out/bin/bishengir-compile --help | grep Ascend310B
./out/bin/hivmc --version                      # hivmc 1.2.0
./out/bin/hivmc --help | grep Ascend310B1
```

更直接的验证是"同一前端 + 默认参数"的对照实验（默认参数意味着后端必须接受
`hacc.noinline`）：

* CANN 9 自带 `hivmc-a5`（1.0.0）→
  `'llvm.func' op Unsupported attribute type: "hacc.noinline"`；
* 本仓库构建的 `hivmc`（1.2.0）→ 流水线成功。

这就是"前后端版本对齐后不再需要 `--enable-lib-call-no-inline=false`"的含义。


## 8. CANN 环境与 507033

`set_env.sh` 可能将 `ASCEND_HOME_PATH` 归一化为实际安装路径，这是正常行为。
在这次验证的 310B1 镜像上，它还会导出 `ASCEND_AICPU_PATH`，带入此值会使
`aclrtSetDevice` 报 `507033`、`TsdOpen failed ... tdt error=31`。本项目的 vecadd
只使用 AI Core，`scripts/00_env.sh` 的 `run_on_device` 会仅在示例启动子进程中
清除该 AI CPU 路径覆盖，因此按部署文档加载 CANN 后可以直接运行第 21、22 号脚本。
若使用旧克隆，请先更新仓库。手动启动同一示例时可使用：

```bash
env -u ASCEND_AICPU_PATH ./out/vecadd/run_add out/vecadd/kernel.o
# 该命令仅适用于本文 AI Core 示例，不作为其他 AI CPU 算子的环境配置。
```

## 9. 2026-11-23 二进制逐步部署验证记录

本次发布已于 **2026-11-23** 在 Ubuntu 22.04.3 aarch64、glibc 2.35、
CANN 9.0.0、Ascend310B1 上按当时的逐步部署流程复测：在全新工作区通过 HTTPS 克隆
仓库，从 GitHub Release 重新下载并校验压缩包，解压检查、安装两个编译器，
重新提取模板、生成内核并运行两种启动程序。C 示例和 LLVM IR launcher
均为 `0/1024 mismatched`、`VECADD PASS`。

测试前清空继承的工具路径覆盖变量，使用新仓库默认 `out/`，新工作区的 `deps/`
保持为空，没有引用旧项目的编译器、模板、内核或上游源码/LLVM 构建目录。
系统依赖和 CANN 9.0.0 按部署文档中“已有安装”的分支复用，未重装 CANN 或驱动。
首次严格按文档加载 `set_env.sh` 后发现上述 `507033 / TsdOpen error=31`，
修复示例启动子进程的 AI CPU 路径覆盖后，重新安装、编译和两种上板测试均通过，
并确认调用者的 `ASCEND_AICPU_PATH` 未被修改。
这不代表已验证其他系统或 CANN 版本；精确前端源码提交未记录，详见包内 `build-info.txt`。

以上记录针对当时逐步执行的部署流程；一键安装脚本的验证结果以该脚本的实际执行日志为准。

## 10. 2026-11-23 一键二进制部署验证

在 `orangepi-pro` 的新工作区重新克隆仓库，确认 `out/` 不存在、`deps/` 为空，
加载已安装的 CANN 9.0.0 后，仅执行 `./scripts/06_install_toolchain.sh`。
脚本从 GitHub 下载固定 Release，完成外部 SHA256 与包内校验、编译器安装和自检，
再自动执行 05 → 20 → 21 → 22。C 示例及 LLVM IR launcher 均得到
`0/1024 mismatched` 和各自的 `VECADD PASS`，脚本退出码为 0。
模板和内核在新目录重新生成，没有上游源码或 LLVM 构建目录；调用者的 CANN 环境保持不变。

同一脚本传入本地压缩包后也完整通过，原编译器、模板和示例输出保留备份。
错误校验和的包、不可用的 C++ 编译器均被拒绝，退出码为 1，现有两个编译器的哈希不变。
完整日志位于 `out/logs/install-toolchain.log`，每次执行的阶段日志单独保存在 `out/logs/install-*/`。

本次实测修正了符号链接路径的误判：服务器 `/home/ls` 实际指向 `/data/ls`，
路径约束需将实际值和期望值都规范化后比较。验证复用板上系统依赖、CANN 9.0.0 和驱动，
不包含重新安装这些前置软件的测试。
