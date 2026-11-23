# vecadd 各级 IR 对照

这里保存 Ascend310B1（`dav-m300`）上同一段向量加法的实际编译输出：
`C[i] = A[i] + B[i]`，`0 ≤ i < 1024`，每个元素为 `i16`。
每个完整向量占 `1024 × 2 = 2048` 字节。编号表示观察顺序，并非编译器的全部 pass。

## 1. 先看每级增加了什么

| 文件 | 主要变化 | 阅读重点 |
| --- | --- | --- |
| [00-input.mlir](00-input.mlir) | 输入张量与逐元素加法 | `tensor<1024xi16>`、`linalg.elemwise_binary` |
| [10-hfusion.mlir](10-hfusion.mlir) | `convert-linalg-to-hfusion` 后 | 增加目标属性；本例的加法仍是 `linalg` |
| [20-hfusion-scheduled.mlir](20-hfusion-scheduled.mlir) | 自动调度后 | tiling 函数、切片和循环、`hfusion.load/store`、block 映射 |
| [30-hivm-tensor.mlir](30-hivm-tensor.mlir) | 转为 HIVM，仍用 tensor | 搬运为 `hivm.hir.load/store`，计算抽出为向量函数 |
| [40-hivm-buffer.mlir](40-hivm-buffer.mlir) | one-shot bufferization 后 | tensor 变为 memref、出现三个 `memref.alloc` |
| [50-hivm-memory-planned.mlir](50-hivm-memory-planned.mlir) | 内存规划后 | 显式 GM/UB 地址空间与 UB 偏移，结果复用输入 A 的 UB 副本 |
| [60-hivm-synchronized.mlir](60-hivm-synchronized.mlir) | 同步求解后 | MTE2→V、V→MTE3 的 set/wait 事件 |
| [70-final-frontend.mlir](70-final-frontend.mlir) | 前端最终输出 | 混合 memref、控制流、LLVM 操作及 regbase intrinsic |
| [80-device.ll](80-device.ll) | 后端生成的设备 LLVM IR | GM/UB 指针、`llvm.hivm.*`、设备函数 `@add` |
| [81-device-annotated.ll](81-device-annotated.ll) | 补内核入口注解 | 在设备 IR 上添加 `!hivm.annotations`，供后续设备编译使用 |

下面代码均从对应文件摘录；省略其他语句时，这些片段不能单独编译。

## 2. 计算：同一个加法逐渐具体化

[00](00-input.mlir) 描述整个张量上的加法：

```mlir
%1 = linalg.elemwise_binary { fun = #linalg.binary_fn<add> }
     ins(%a, %b : tensor<1024xi16>, tensor<1024xi16>)
     outs(%0 : tensor<1024xi16>) -> tensor<1024xi16>
```

[10](10-hfusion.mlir) 仍用 `linalg` 表示加法，HFusion 层可以混合使用其他 dialect 的操作。
[20](20-hfusion-scheduled.mlir) 增加 HFusion 的加载、存储、切片和调度信息。
[30](30-hivm-tensor.mlir) 把计算抽到 `@add_outlined_vf_0`，其核心是：

```mlir
%3 = arith.addi %1, %2 : vector<128xi16>
```

外围的 `hivm.hir.load/store` 负责搬运，向量函数负责计算；这份快照中没有
`hivm.hir.vadd`。到 [70](70-final-frontend.mlir) 才能看到
`hivm_regbaseintrins.intr.hivm.vadd.s.x`，到 [80](80-device.ll) 变为 LLVM intrinsic：

```llvm
%14 = call <128 x i16> @llvm.hivm.vadd.s.x.v128i16(<128 x i16> %10, <128 x i16> %12, <256 x i1> %13)
```

## 3. 存储：从张量到 GM 与 UB

[40](40-hivm-buffer.mlir) 有三个 `memref.alloc`，此时尚未给出最终 UB 偏移。
[50](50-hivm-memory-planned.mlir) 明确：输入、输出位于 GM，向量计算使用 UB。

```mlir
%c2048_i64 = arith.constant 2048 : i64
%c0_i64 = arith.constant 0 : i64
%0 = hivm.hir.pointer_cast(%c0_i64) : memref<1024xi16, #hivm.address_space<ub>>
%1 = hivm.hir.pointer_cast(%c0_i64) : memref<1024xi16, #hivm.address_space<ub>>
%2 = hivm.hir.pointer_cast(%c2048_i64) : memref<1024xi16, #hivm.address_space<ub>>
```

| 50 中的值 | 用途 | UB 字节区间 |
| --- | --- | --- |
| `%1` | 输入 A 从 GM 搬到 UB 的副本 | `[0, 2048)` |
| `%2` | 输入 B 从 GM 搬到 UB 的副本 | `[2048, 4096)` |
| `%0` | 加法结果 | `[0, 2048)`，与 A 的 UB 副本复用 |

因此本 IR **显式规划的向量数据区为 4096 字节**；这不是整个内核全部 UB 开销的统计。
计算读出 A、B 的当前向量后，把结果写到 A 副本所在的 UB 区域，再搬回输出 C 的 GM。
输入 A 的 GM 地址仍是输入参数；这里的复用不等于改写 A 的 GM 数据。

[80](80-device.ll) 中 GM 对应 `addrspace(1)`，UB 对应 `addrspace(6)`：

```llvm
define void @add(ptr addrspace(1) %0, ptr addrspace(1) %1, ptr addrspace(1) %2) #2 {
```

该函数调用向量函数时，UB 地址正是 0、2048、0：

```llvm
call ptc_simdvf void @add_outlined_vf_0(ptr addrspace(6) null, ptr addrspace(6) inttoptr (i64 2048 to ptr addrspace(6)), ptr addrspace(6) null)
```

这里的 UB `null` 表示该地址空间内的偏移 0。前面 [20](20-hfusion-scheduled.mlir) 等文件中的
`buffer_size_in_byte = 49120` 是调度阶段的标注，不能拿来代替 50 的最终显式布局。

## 4. 并行：一个 block 内做八轮 SIMD

[20](20-hfusion-scheduled.mlir) 起有 `hacc.block_dim = 1`，本例没有把 1024 个元素分给多个 block。
[30](30-hivm-tensor.mlir) 的向量函数循环从 0 到 1024，每轮步长 128。
在 [80](80-device.ll) 中仍能直接看到边界与步长：

```llvm
%6 = icmp slt i32 %5, 1024
%17 = add nsw i32 %5, 128
```

每轮处理 `128 × i16 = 256` 字节，共 `1024 / 128 = 8` 轮。
这是向量指令处理多个数据元素的 SIMD；循环的八轮并不是八个并行 block。

[80](80-device.ll) 中还有谓词掩码：

```llvm
%13 = call <256 x i1> @llvm.hivm.pge.b16(i32 0, i32 0)
```

`<256 x i1>` 是硬件谓词类型；加法的数据输入、输出仍是 `<128 x i16>`。
不能从“256 个谓词位”推导出“一次计算 256 个 i16 元素”。

## 5. 同步：先搬入，再计算，最后搬出

[60](60-hivm-synchronized.mlir) 在两个 GM→UB 加载之后、向量计算之前插入：

```mlir
hivm.hir.set_flag[<PIPE_MTE2>, <PIPE_V>, <EVENT_ID0>]
hivm.hir.wait_flag[<PIPE_MTE2>, <PIPE_V>, <EVENT_ID0>]
```

向量计算之后、UB→GM 存储之前插入：

```mlir
hivm.hir.set_flag[<PIPE_V>, <PIPE_MTE3>, <EVENT_ID0>]
hivm.hir.wait_flag[<PIPE_V>, <PIPE_MTE3>, <EVENT_ID0>]
```

MTE2 完成搬入后通知 V，V 完成计算后通知 MTE3。两组都用事件 0，但属于不同的流水线对。
这是**核内流水线同步**，不表示跨核同步或全局屏障；本例的 block 数仍为 1。

## 6. 如何复现与确认来源

[provenance.json](provenance.json) 记录编译器版本、二进制 SHA256、编译参数及各快照的 pass 编号。
[SHA256SUMS](SHA256SUMS) 用于校验这些生成文件，可在本目录运行 `sha256sum -c SHA256SUMS`。

先按仓库部署文档安装编译器、CANN 9.0.0 并准备设备权限。导出还需要 GDB：

```bash
sudo apt-get install -y gdb
# 在仓库根目录执行
./examples/vecadd/tools/export_ir_310b1.sh
# 或在本 IR 目录执行
../tools/export_ir_310b1.sh
```

当前 1.2.0 编译器未开放通用的 MLIR 逐 pass 打印。导出脚本利用缺失注入文件触发断点，
在选定 pass 之后调用编译器原生 `Operation::dump()`，保存当时的 module；没有手工重写算子。
诊断运行随后通过故意无效的后端选项停止，**诊断失败本身不算正常编译验证**。
脚本另做独立的正常编译来获取设备 LLVM IR（80），81 仅在 80 上补内核入口注解。

2026-11-23 已独立正常编译并运行 C 示例、LLVM IR launcher，两者均为
`0/1024 mismatched`、`VECADD PASS`。去除行尾空白并统一文件末尾换行后，80 与这次正常编译
捕获的设备 LLVM IR 的 SHA256 一致。导出文件仅做本机路径替换和上述空白整理。
这些快照用于解释本次 310B1 编译结果；不同编译器版本或调度选项可能产生不同 IR。
