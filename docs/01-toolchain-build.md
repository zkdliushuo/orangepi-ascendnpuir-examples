# 工具链部署与构建细节

本项目提供两种部署方式：**下载已经构建好的二进制编译器**，或**从源码编译**。
两种方式最终都得到 `out/bin/bishengir-compile` 与 `out/bin/hivmc`，随后使用相同的
vecadd 编译、运行和校验流程。第 0 节给出完整操作步骤，第 1～7 节保留分支选择、
模板 bitcode、补丁和构建机制的说明。

## 0. 选择部署方式

| 方式 | 适用场景 | 是否需要上游源码与 LLVM 构建目录 |
| --- | --- | --- |
| 二进制部署（0.2 节） | 在兼容的 Linux aarch64 香橙派上直接使用本次发布的编译器 | 不需要 |
| 源码编译（0.3 节） | 修改编译器、调整构建选项，或为其他主机环境重新构建 | 需要 |

二进制发布在本仓库的 [GitHub Releases](https://github.com/zkdliushuo/orangepi-ascendnpuir-examples/releases)，
不作为普通 Git 文件保存。它包含本项目已打补丁的 BiShengIR **1.2.0** 前端和后端
（LLVM **19.1.7**）、许可证及构建来源说明。**CANN toolkit、310B 算子包、设备驱动
和从 CANN 提取的模板 bitcode 均不包含在下载包中**；这些依赖仍需在目标机器上准备。

### 0.1 两种方式共用的准备工作

以下命令在目标香橙派的 Bash 中执行。推荐使用与发布机器一致的 **Ubuntu 22.04
aarch64**。二进制需要的最高符号版本为 `GLIBC_2.34`、`GLIBCXX_3.4.30`、
`CXXABI_1.3.11`；发布机器使用 glibc 2.35。`GLIBCXX_3.4.30` 来自 GCC 12
运行库，不能仅凭已经安装 GCC 11 就判断兼容。其他 Linux 发行版或系统版本需自行
确认这些运行库与 CANN 的兼容性；此包不能在 x86_64 Windows/Linux 上直接运行。
上述符号版本门槛仅适用于预编译包；选择源码编译时，运行库要求由本机实际构建结果决定。

#### 第 1 步：创建工作区并获取示例仓库

```bash
export WORK_ROOT="$HOME/ascend-workspace"
sudo apt-get update
sudo apt-get install -y git
mkdir -p "$WORK_ROOT/deps"
cd "$WORK_ROOT"
git clone --branch main \
  https://github.com/zkdliushuo/orangepi-ascendnpuir-examples.git \
  ascend310b1-vecadd
cd "$WORK_ROOT/ascend310b1-vecadd"
```

公开仓库使用 HTTPS 克隆即可，无需 GitHub 账号或 SSH key。已经配置 GitHub SSH
的开发者也可将克隆地址换成
`git@github.com:zkdliushuo/orangepi-ascendnpuir-examples.git`。下文均假定当前目录是
`$WORK_ROOT/ascend310b1-vecadd`；在新终端中操作时先重新设置 `WORK_ROOT` 并进入该目录。

#### 第 2 步：安装系统依赖并检查主机架构、运行库

```bash
sudo apt-get update
sudo apt-get install -y \
  build-essential git python3 curl ca-certificates tar gzip binutils \
  libc6 libgcc-s1 libstdc++6 zlib1g

uname -m                                  # 必须是 aarch64
getconf GNU_LIBC_VERSION                   # 推荐 glibc 2.35
strings /usr/lib/aarch64-linux-gnu/libstdc++.so.6 \
  | grep -Fx GLIBCXX_3.4.30                # 二进制部署必须能找到此行
```

若系统仓库提供的 `libstdc++6` 尚未导出 `GLIBCXX_3.4.30`，先通过适用于该发行版的
软件源升级运行库，或改用 0.3 节在本机源码编译。不要把其他机器的 glibc 文件直接
覆盖到系统目录。`build-essential` 用于编译示例的 CPU 侧 C++ 程序；下载编译器后
仍需要它，但无需构建 LLVM。

#### 第 3 步：安装 CANN 9.0.0 与 310B 算子包

从昇腾社区按其许可自行取得 aarch64 版
`Ascend-cann-toolkit_9.0.0_linux-aarch64.run` 和
`Ascend-cann-kernels-310b_9.0.0_linux.run`，放到 `$WORK_ROOT/deps`，再执行：

```bash
cd "$WORK_ROOT/deps"
chmod +x Ascend-cann-toolkit_9.0.0_linux-aarch64.run \
         Ascend-cann-kernels-310b_9.0.0_linux.run
./Ascend-cann-toolkit_9.0.0_linux-aarch64.run \
  --install --install-path="$WORK_ROOT/deps" --quiet
./Ascend-cann-kernels-310b_9.0.0_linux.run \
  --install --install-path="$WORK_ROOT/deps" --quiet

# 找到本次安装生成的 toolkit 根目录（同时包含 bin/ 与 tools/）。
# 安装器的版本目录可能不同，以实际安装结果为准。
find "$WORK_ROOT/deps" -name set_env.sh -print
export ASCEND_HOME_PATH="$WORK_ROOT/deps/cann-9.0.0"  # 改成上一步找到的实际 toolkit 根目录
source "$ASCEND_HOME_PATH/set_env.sh"
ls "$ASCEND_HOME_PATH/bin/bishengir-compile-a5"
ls "$ASCEND_HOME_PATH/tools/ccec_compiler/bin/ccec"
cd "$WORK_ROOT/ascend310b1-vecadd"
```

已有 CANN 9.0.0 时跳过重复安装，将 `ASCEND_HOME_PATH` 设为实际 toolkit 目录并
加载其 `set_env.sh`。该目录必须包含上面检查的两个程序。需要持久保存自定义路径时，
可在 `scripts/config.local.sh` 中写入 `ASCEND_HOME_PATH="/实际/toolkit/目录"`；
该文件已由 Git 忽略。

设备驱动和固件由香橙派镜像或对应驱动包提供，默认驱动目录是
`/usr/local/Ascend/driver`，位置不同时设置 `ASCEND_DRIVER_DIR`。确认设备文件及
当前登录会话的组权限：

```bash
ls -l /dev/davinci0 /dev/davinci_manager
id
# 当前用户尚无设备组时执行，然后退出 SSH 并重新登录
sudo usermod -aG HwHiAiUser,HwBaseUser,HwDmUser "$(whoami)"
```

重新登录后再继续下面的安装和测试。已具备设备组时无需再次执行 `usermod`。

### 0.2 方式一：从 GitHub Release 部署二进制

完成 0.1 节后，按以下步骤下载、校验、解压查看、安装并测试。该流程不会下载
AscendNPU-IR 上游源码，也不需要 `deps/build-ascendnpu-ir`。

#### 第 1 步：下载固定版本的压缩包与校验文件

本次发布：[toolchain-v1.2.0-310b1-20261123](https://github.com/zkdliushuo/orangepi-ascendnpuir-examples/releases/tag/toolchain-v1.2.0-310b1-20261123)。

```bash
cd "$WORK_ROOT/ascend310b1-vecadd"
mkdir -p out/downloads
cd out/downloads
release_url="https://github.com/zkdliushuo/orangepi-ascendnpuir-examples/releases/download/toolchain-v1.2.0-310b1-20261123"
archive="ascend310b1-toolchain-1.2.0-linux-aarch64.tar.gz"
curl -fL --retry 3 -o "$archive" "$release_url/$archive"
curl -fL --retry 3 -o SHA256SUMS "$release_url/SHA256SUMS"
```

也可以在浏览器中打开该 Release，在 **Assets** 中下载这两个文件，再复制到
目标机器的 `out/downloads/`。选择上述命名的工具链包；GitHub 自动生成的
`Source code (zip)` / `Source code (tar.gz)` 只有示例仓库源码，不包含编译器。

#### 第 2 步：校验下载内容并解压查看

```bash
# 仍在仓库的 out/downloads/ 中
sha256sum -c SHA256SUMS
# 期望：ascend310b1-toolchain-1.2.0-linux-aarch64.tar.gz: OK

tar -tzf "$archive"
mkdir -p inspect
tar -xzf "$archive" -C inspect
find inspect -maxdepth 3 -type f | sort
```

确认校验输出为 `OK` 后再安装。`inspect/` 是用于查看压缩包内编译器、许可证和
来源信息的解压目录；下一步安装脚本直接读取原始 `.tar.gz`，并完成包内校验和安装。

#### 第 3 步：安装到本仓库的 out/bin

```bash
cd "$WORK_ROOT/ascend310b1-vecadd"
./scripts/06_install_toolchain.sh \
  "$PWD/out/downloads/ascend310b1-toolchain-1.2.0-linux-aarch64.tar.gz"
ls -lh out/bin/bishengir-compile out/bin/hivmc
```

安装位置是当前仓库的 `out/bin/`，无需 `sudo`，也无需修改 `/usr/bin`。现有脚本
默认从这里读取编译器。若要在终端中直接按名字使用，可执行
`export PATH="$PWD/out/bin:$PATH"`；运行本项目脚本无需这一步。

#### 第 4 步：检查版本、目标与动态依赖

```bash
./out/bin/bishengir-compile --version
./out/bin/hivmc --version
./out/bin/bishengir-compile --help | grep Ascend310B
./out/bin/hivmc --help | grep Ascend310B1
ldd out/bin/bishengir-compile
ldd out/bin/hivmc
```

前后端版本都应为 **1.2.0**，帮助中应包含 `Ascend310B1`，`ldd` 不应出现
`not found`。若报 `GLIBCXX_3.4.30 not found` 或 `GLIBC_2.34 not found`，先解决
0.1 节的主机运行库兼容问题。

#### 第 5 步：提取本机 CANN 模板并重新编译算子

```bash
./scripts/05_capture_a5_templates.sh
ls -lh out/a5-templates/host.bc out/a5-templates/regbaseM300.bc
./scripts/20_build_vecadd.sh
ls -lh out/vecadd/kernel.o out/vecadd/run_add
```

模板从目标机器已安装的 CANN 9.0.0 获取。第 20 号脚本实际使用下载的前后端，将
`examples/vecadd/mlir/add_310b1.mlir` 重新编译为 `out/vecadd/kernel.o`，并构建
CPU 侧运行程序；它检验了编译器与本机 CANN 之间的整条编译流水线。

#### 第 6 步：上板运行并验证两种启动方式

```bash
./scripts/21_run_vecadd.sh
./scripts/22_llvm_ir_launcher.sh
```

第一个程序应输出：

```text
check: 0/1024 mismatched; c[0]=1 c[1]=2 c[1023]=1024
VECADD PASS
```

LLVM IR launcher 应输出相同的零错误比较结果，以及
`VECADD PASS (LLVM IR launcher)`。两项都通过，才说明二进制部署在当前板上完成
端到端验证。只看到 `--version` 成功还不能说明设备编译和启动可用。

本次发布已于 **2026-11-23** 在 Ubuntu 22.04.3 aarch64、glibc 2.35、
CANN 9.0.0、Ascend310B1 上完成上述验证：在独立项目目录安装压缩包，
重新提取模板、生成内核并运行两种启动程序，二者均为 `0/1024 mismatched`、
`VECADD PASS`。测试使用新目录的默认 `out/`，没有复用旧目录的内核。
这不代表已验证其他系统或 CANN 版本；精确前端源码提交未记录，详见包内 `build-info.txt`。

以后可在仓库根目录直接执行 `./scripts/99_verify.sh` 重复完整验证；使用二进制
部署时保留默认的 `BUILD_TOOLCHAIN=0`，不要设置 `BUILD_TOOLCHAIN=1`，后者会转为
从源码重建工具链。

### 0.3 方式二：从源码编译

完成 0.1 节后，准备构建工具及上游源码，再依次构建前端、后端。无需下载 0.2 节的
Release 包。

#### 第 1 步：安装符合版本要求的 CMake 与 Ninja

```bash
sudo apt-get install -y python3-venv zlib1g-dev
python3 -m venv "$WORK_ROOT/build-tools"
source "$WORK_ROOT/build-tools/bin/activate"
python3 -m pip install 'cmake>=3.28,<4' 'ninja>=1.12'
cmake --version
ninja --version
export CMAKE_GENERATOR=Ninja
```

如果系统已提供 CMake ≥ 3.28、Ninja ≥ 1.12，可以直接使用系统版本。
`CMAKE_GENERATOR=Ninja` 保证全新构建目录使用 Ninja；后端脚本的重链接步骤需要
读取 Ninja 生成的链接命令。新终端中需重新激活虚拟环境并设置该变量。

#### 第 2 步：获取上游源码并建立 dev/regbase 工作树

```bash
cd "$WORK_ROOT/deps"
git clone --branch master https://github.com/Ascend/AscendNPU-IR.git AscendNPU-IR
cd AscendNPU-IR
git submodule update --init --recursive
git fetch origin dev/regbase
git worktree add ../AscendNPU-IR-a5 origin/dev/regbase

cd ../AscendNPU-IR-a5
mkdir -p third-party
# worktree 检出未初始化的子模块时可能留下空目录；仅移除空目录。
# 若目录已有内容，rmdir 会失败并中止，请先确认其中内容后再继续。
for component in llvm-project shmem torch-mlir; do
  dependency="third-party/$component"
  if [[ -d "$dependency" && ! -L "$dependency" ]]; then
    rmdir -- "$dependency" || {
      echo "非空依赖目录，请先检查：$dependency" >&2
      exit 1
    }
  fi
done
ln -sfn ../../AscendNPU-IR/third-party/llvm-project third-party/llvm-project
ln -sfn ../../AscendNPU-IR/third-party/shmem        third-party/shmem
ln -sfn ../../AscendNPU-IR/third-party/torch-mlir   third-party/torch-mlir
cd "$WORK_ROOT/ascend310b1-vecadd"
```

这里使用与现有构建脚本相对应的 `master` / `dev/regbase` 分支。上游分支持续变化，
若补丁不能应用，应核对上游版本与本仓库补丁，而不是跳过补丁继续生成 310B1 内核。
有关两个分支以及补丁作用，见第 1、4、5 节。

#### 第 3 步：按顺序构建前端和后端

```bash
JOBS=3 ./scripts/10_build_frontend.sh
JOBS=3 ./scripts/11_build_hivmc.sh
./out/bin/bishengir-compile --version
./out/bin/hivmc --version
./out/bin/bishengir-compile --help | grep Ascend310B
./out/bin/hivmc --help | grep Ascend310B1
```

两个脚本共享 `deps/build-ascendnpu-ir`，产物安装到 `out/bin/`。首次构建在 3 核
香橙派上约需 6～8 小时，具体取决于 CPU、内存和存储；内存不足时可降低 `JOBS`。
前端必须先构建，后端脚本复用前端建立的构建目录。不要并行运行这两个脚本。

#### 第 4 步：编译并运行完整示例

```bash
./scripts/05_capture_a5_templates.sh
./scripts/20_build_vecadd.sh
./scripts/21_run_vecadd.sh
./scripts/22_llvm_ir_launcher.sh
```

检查标准与 0.2 节第 6 步相同：C 示例及 LLVM IR launcher 都必须报告
`0/1024 mismatched` 和对应的 `VECADD PASS`。工具链、依赖与上游源码均已准备好时，
也可用 `BUILD_TOOLCHAIN=1 ./scripts/99_verify.sh` 顺序执行构建与完整验证。

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
