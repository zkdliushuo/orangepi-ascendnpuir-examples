# 用 LLVM IR 调用 vecadd

## 1. 三份 IR 的分工

| 文件 | 内容 | 在 310B1 上 |
| --- | --- | --- |
| `llvm/launch_add.ll` | 调用稳定 C ABI shim `ascend_abi_launch_add(runtime, kernel, blockDim, in0, in1, out)` | 可编译；运行需要配套的 `ascend_abi_runtime.cpp`（内部走 `aclrtBinaryLoadFromData`，该路径依赖 metainfo/JSON，不是 310B1 上验证过的注册方式） |
| `llvm/direct_aclrt_launch.ll` | 教学版：直接声明 `aclrtKernelArgsInit/Append/Finalize` 与 `aclrtLaunchKernelWithConfig` | 用于说明 ACL Runtime 的调用形态，可编译 |
| `llvm/launch_add_310b1.ll` | 直接调用 AscendC 运行时 ABI：`LaunchAscendKernel(...)` + `aclrtSynchronizeStream` | **在设备上验证通过** |

上游那份 shim（`ascend_abi_runtime.{h,cpp}` 与 `main.cpp`）保存在
`examples/vecadd/abi_reference/`，只作参考：它走的是 910B 的
`aclrtBinaryLoadFromData` 路径，在 310B1 上用裸 `kernel.o` 注册并不可靠。

## 2. 310B1 版本的启动 IR

```llvm
target triple = "aarch64-unknown-linux-gnu"

declare i32 @LaunchAscendKernel(ptr, i64, i32, ptr, i32, ptr)
declare i32 @aclrtSynchronizeStream(ptr)

define i32 @launch_and_wait_310b1(ptr %handle, i64 %key, ptr %stream,
                                  ptr %args) {
entry:
  %launch_status = call i32 @LaunchAscendKernel(
      ptr %handle, i64 %key, i32 1, ptr %args, i32 24, ptr %stream)
  %ok = icmp eq i32 %launch_status, 0
  br i1 %ok, label %wait, label %done
wait:
  %sync_status = call i32 @aclrtSynchronizeStream(ptr %stream)
  ret i32 %sync_status
done:
  ret i32 %launch_status
}
```

参数含义：

| 参数 | 值 | 说明 |
| --- | --- | --- |
| `handle` | `RegisterAscendBinary` 的返回值 | opaque 内核句柄 |
| `key` | `0` | 入口符号 `add_0` 的 tiling key |
| `blocks` | `1` | 310B1 单核；内核以 `-block-dim=1` 编译 |
| `args` | `void *args[3]` | 三个设备地址，顺序 = 设备函数声明顺序 |
| `argsSize` | `24` | 必须与 `__CCE_KernelArgSize` 中的值一致 |

## 3. 编译与运行

```bash
./scripts/22_llvm_ir_launcher.sh
```

脚本做四件事：

1. 用 `bisheng` 把 `launch_add.ll`、`direct_aclrt_launch.ll` 编译成 `.o`
   （与上游示例一致，验证这两份 IR 与目标一致）；
2. 把 `launch_add_310b1.ll` 编译成 `launch_add_310b1.o`；
3. 与 `src/llvm_launch_driver_310b1.cpp` 链接成 `out/vecadd/llvm_launch`：
   驱动负责 ACL 初始化、显存、拷贝与结果校验，**启动动作完全在 IR 里**；
4. 上板运行并校验。

期望输出：

```
RegisterAscendBinary ret=0
launch_and_wait_310b1 ret=0
check: 0/1024 mismatched; c[0]=1 c[1]=2 c[1023]=1024
VECADD PASS (LLVM IR launcher)
```

## 4. 在自己的编译器里生成这段 IR

`BackendLoweringSketch.cpp` 给出了 CPU 侧 lowering 的核心思路：

```cpp
llvm::FunctionCallee getAscendLaunchAdd(llvm::Module &module) {
  auto *signature = llvm::FunctionType::get(
      i32, {pointer, pointer, i32, i64, i64, i64}, false);
  return module.getOrInsertFunction("ascend_abi_launch_add", signature);
}
```

也就是说，CPU 后端不需要理解设备指令，只需：

1. 把设备 ELF 注册成 opaque handle；
2. 把三个设备地址放进 24 字节参数块；
3. 调用 launch + synchronize。

设备端的 `add` 完全由 AscendNPU-IR + `ccec` 生成，两者通过 `kernel.o`
（第 5 节的容器格式）对接。
