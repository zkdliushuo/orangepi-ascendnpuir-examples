# ABI 参考实现（上游 910B 路径，未在 310B1 上验证）

这里是从上游示例 `ascend-abi-examples` 原样保留的稳定 C ABI shim：

* `include/ascend_abi_runtime.h`、`src/ascend_abi_runtime.cpp`：
  `ascend_abi_kernel_load_vector` 内部走 `aclrtBinaryLoadFromData`，需要
  metainfo / 同名 kernel JSON；
* `src/main.cpp`：用该 shim 跑 16 个 i16 的 vecadd。

`../llvm/launch_add.ll` 调用的就是这里的 `ascend_abi_launch_add`。

**注意**：这条路径依赖二进制加载接口的元数据（`aclrtBinaryLoadFromFile` 通常要求
metainfo 或 JSON），在 Ascend310B1 上用裸 `kernel.o` 注册时并不可靠，
本仓库没有在 310B1 上验证它。310B1 上验证过的做法是
`../src/vecadd_runner_310b1.cpp` 与 `../llvm/launch_add_310b1.ll`
使用的 AscendC runtime ABI（`RegisterAscendBinary` / `LaunchAscendKernel`），
见 `docs/02-vecadd-pipeline.md` 与 `docs/03-llvm-ir-launch.md`。
