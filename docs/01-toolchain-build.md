# 工具链部署

在香橙派 Ascend310B1 上，两种方式都安装 BiShengIR 1.2.0 的前端和后端到 `out/bin/`。
直接使用编译器选[二进制部署](#binary-deploy)，需要修改编译器选[源码编译](#source-build)。
分支、模板、补丁和链接机制见 [工具链内部机制与验证记录](05-toolchain-internals.md)。

<a id="common-setup"></a>

## 1. 共用准备

以下命令在目标板的 Bash 中执行，系统采用 **Ubuntu 22.04 aarch64**，设备已安装配套驱动。
二进制需要 glibc ≥ 2.34、支持 `GLIBCXX_3.4.30` 和 `CXXABI_1.3.11` 的 libstdc++6。

### 安装依赖并获取示例仓库

```bash
sudo apt-get update
sudo apt-get install -y \
  build-essential git python3 curl ca-certificates tar gzip binutils \
  libc6 libgcc-s1 libstdc++6 zlib1g
export WORK_ROOT="$HOME/ascend-workspace"
mkdir -p "$WORK_ROOT/deps"
cd "$WORK_ROOT"
git clone --branch main \
  https://github.com/zkdliushuo/orangepi-ascendnpuir-examples.git \
  ascend310b1-vecadd
cd "$WORK_ROOT/ascend310b1-vecadd"
uname -m                                    # 应为 aarch64
```

下文默认在仓库根目录操作。新终端中需重新设置 `WORK_ROOT` 并进入该目录。

### 安装 CANN 9.0.0 与 310B 算子包

打开[昇腾社区 CANN 下载页](https://www.hiascend.com/cann/download?versionId=734&ids=d105,h0501,h0602,h0703)，
依次确认 **9.0.0 → 310B 系列产品 → AArch64 → Ubuntu → 离线安装（Runfile）**，
按官网提示阅读软件许可并下载以下两个独立包；详细说明见 [CANN 9.0.X 官方安装指南](https://www.hiascend.com/document/detail/zh/CANNCommunityEdition/900/softwareinst/instg/instg_0000.html)。

| 软件包 | 官方下载链接 |
| --- | --- |
| Toolkit | [Ascend-cann-toolkit_9.0.0_linux-aarch64.run](https://ascend-repo.obs.cn-east-2.myhuaweicloud.com/CANN/CANN%209.0.0/Ascend-cann-toolkit_9.0.0_linux-aarch64.run) |
| 310B 算子包 | [Ascend-cann-310b-ops_9.0.0_linux-aarch64.run](https://ascend-repo.obs.cn-east-2.myhuaweicloud.com/CANN/CANN%209.0.0/Ascend-cann-310b-ops_9.0.0_linux-aarch64.run) |

本项目使用板上已有驱动，请核对下载文件名；9.0.0 的算子包名为 `310b-ops`。
把两个文件放进 `$WORK_ROOT/deps` 后安装：

```bash
cd "$WORK_ROOT/deps"
chmod +x Ascend-cann-toolkit_9.0.0_linux-aarch64.run \
         Ascend-cann-310b-ops_9.0.0_linux-aarch64.run
./Ascend-cann-toolkit_9.0.0_linux-aarch64.run \
  --install --install-path="$WORK_ROOT/deps"
./Ascend-cann-310b-ops_9.0.0_linux-aarch64.run \
  --install --install-path="$WORK_ROOT/deps"
find "$WORK_ROOT/deps" -name set_env.sh -print
```

已有 CANN 9.0.0 时跳过安装。根据实际安装结果设置 toolkit 根目录：该目录应同时包含
`set_env.sh`、`bin/bishengir-compile-a5` 和 `tools/ccec_compiler/bin/ccec`。

```bash
export ASCEND_HOME_PATH=/实际/toolkit/目录       # 替换为本机路径
source "$ASCEND_HOME_PATH/set_env.sh"
ls "$ASCEND_HOME_PATH/bin/bishengir-compile-a5" \
   "$ASCEND_HOME_PATH/tools/ccec_compiler/bin/ccec"
cd "$WORK_ROOT/ascend310b1-vecadd"
```

### 确认设备权限

```bash
ls -l /dev/davinci0 /dev/davinci_manager
id
# 当前用户尚无下面的设备组时执行，然后退出 SSH 并重新登录
sudo usermod -aG HwHiAiUser,HwBaseUser,HwDmUser "$(whoami)"
```

驱动默认在 `/usr/local/Ascend/driver`，位置不同时设置 `ASCEND_DRIVER_DIR`。

<a id="binary-deploy"></a>

## 2. 二进制部署

完成共用准备并加载 CANN 环境后，执行一条命令：

```bash
./scripts/06_install_toolchain.sh
```

脚本自动从 [GitHub Release](https://github.com/zkdliushuo/orangepi-ascendnpuir-examples/releases/tag/toolchain-v1.2.0-310b1-20261123)
下载固定版本，校验、解压并安装两个编译器，检查版本与运行库，提取本机 CANN 模板，
编译 vecadd，再运行 C 示例和 LLVM IR launcher。无需下载上游源码或构建 LLVM。
如未加载环境，可在命令前加 `ASCEND_HOME_PATH=/实际/toolkit/目录`，替换为本机路径。
完整日志见 `out/logs/install-toolchain.log`；失败时脚本以非零状态退出，并提示失败阶段及日志路径。

成功时两种启动方式分别输出：

```text
check: 0/1024 mismatched; c[0]=1 c[1]=2 c[1023]=1024
VECADD PASS
...
VECADD PASS (LLVM IR launcher)
```

编译器位于 `out/bin/`，生成的内核与运行程序位于 `out/vecadd/`。
以后可执行 `./scripts/99_verify.sh` 重新编译并测试。

如已下载 Release 中的 `ascend310b1-toolchain-1.2.0-linux-aarch64.tar.gz`，
可将本地压缩包传给同一个脚本，跳过在线下载，其余安装、自检和上板测试照常执行：

```bash
./scripts/06_install_toolchain.sh \
  /path/to/ascend310b1-toolchain-1.2.0-linux-aarch64.tar.gz
```

本地包方式仍需本机已安装 CANN 9.0.0，并能访问 Ascend310B1 设备。

<a id="source-build"></a>

## 3. 源码编译

完成共用准备后，安装 CMake ≥ 3.28、Ninja ≥ 1.12，并选择 Ninja 生成器：

```bash
sudo apt-get install -y python3-venv zlib1g-dev
python3 -m venv "$WORK_ROOT/build-tools"
source "$WORK_ROOT/build-tools/bin/activate"
python3 -m pip install 'cmake>=3.28,<4' 'ninja>=1.12'
export CMAKE_GENERATOR=Ninja
```

获取上游 `master` 及子模块，再建立前端使用的 `dev/regbase` 工作树：

```bash
cd "$WORK_ROOT/deps"
git clone --branch master https://github.com/Ascend/AscendNPU-IR.git AscendNPU-IR
cd AscendNPU-IR
git submodule update --init --recursive
git fetch origin dev/regbase
git worktree add ../AscendNPU-IR-a5 origin/dev/regbase
cd ../AscendNPU-IR-a5
mkdir -p third-party
# 清除未初始化子模块留下的空目录，再复用 master 的依赖；非空目录会中止。
for component in llvm-project shmem torch-mlir; do
  dependency="third-party/$component"
  if [[ -d "$dependency" && ! -L "$dependency" ]]; then
    rmdir -- "$dependency" || { echo "请先检查非空目录：$dependency" >&2; exit 1; }
  fi
done
ln -sfn ../../AscendNPU-IR/third-party/llvm-project third-party/llvm-project
ln -sfn ../../AscendNPU-IR/third-party/shmem        third-party/shmem
ln -sfn ../../AscendNPU-IR/third-party/torch-mlir   third-party/torch-mlir
cd "$WORK_ROOT/ascend310b1-vecadd"
```

顺序构建前端和后端。两个脚本共用构建目录，不能同时运行；3 核板首次构建约需 6～8 小时。

```bash
JOBS=3 ./scripts/10_build_frontend.sh
JOBS=3 ./scripts/11_build_hivmc.sh
./out/bin/bishengir-compile --version
./out/bin/hivmc --version
```

两者版本应为 1.2.0。然后提取模板、编译算子，并运行两种启动方式：

```bash
./scripts/05_capture_a5_templates.sh
./scripts/20_build_vecadd.sh
./scripts/21_run_vecadd.sh
./scripts/22_llvm_ir_launcher.sh
```

C 示例和 LLVM IR launcher 都应报告 `0/1024 mismatched` 及对应的 `VECADD PASS`。
上游分支变化导致补丁无法应用时，请核对[构建细节](05-toolchain-internals.md)，再调整源码版本。
