# vecadd 算子的编译与容器格式

## 1. 输入

`examples/vecadd/mlir/add_310b1.mlir`：1024 个 i16 的向量加，设备函数：

```mlir
func.func @add(%a: tensor<1024xi16>, %b: tensor<1024xi16>) -> (tensor<1024xi16>)
attributes {hacc.function_kind = #hacc.function_kind<DEVICE>} { ... }
```

## 2. 前端 + 后端

```bash
out/bin/bishengir-compile \
  --target=Ascend310B1 -enable-hfusion-compile=true -block-dim=1 \
  --link-aicore-bitcode=out/a5-templates/regbaseM300.bc \
  --hivmc-args=--link-host-bitcode=out/a5-templates/host.bc \
  examples/vecadd/mlir/add_310b1.mlir -o out/vecadd/pipeline.o
```

* `--link-aicore-bitcode` / `--link-host-bitcode` 是 A5 的模板 bitcode
  （见 `scripts/05_capture_a5_templates.sh`）。CANN 自带的 `hivmc-a5` 内置它们，
  自建版本需要显式给出，否则报
  `[ERROR]cannot find any bitcode files for coreType:...`。
* 后端把设备模块写成 LLVM IR 后调用 CANN 的设备编译器 `ccec`
  （`--cce-aicore-arch=dav-m300`）。本仓库用一个"捕获 shim"替换 `bisheng`，
  在调用真实编译器之前把该 `.ll` 复制到
  `out/vecadd/capture/module-<pid>-<n>.ll`，既能拿到流水线原始产物，
  又不影响正常编译。

## 3. 设备 IR 必须补的内核入口元数据

AscendC 路径（例如 `ccec` 直接编译 AscendC 内核）产出的 IR 里有：

```llvm
!hivm.annotations = !{!1}
!1 = !{ptr @add, !"kernel", i32 1}
```

AscendNPU-IR 流水线产出的设备 IR 没有这一段。它告诉设备编译器"`@add` 是内核入口"；
缺了它就不会生成参数前导，核心里读参数时拿到寄存器垃圾值，运行时报：

```
DDR address of the MTE instruction is out of range
```

`examples/vecadd/tools/patch_310b1_annotation.py` 负责补上（纯文本处理，
会自动挑选未被占用的 metadata 编号）。

## 4. 设备编译与静态链接

```bash
ccec --cce-aicore-arch=dav-m300 --cce-aicore-only -O2 \
     -cce-bitcode-is-aicore -cce-link-aicore-ll-module out/a5-templates/regbaseM300.bc \
     -mllvm --cce-vf-auto-sync=global \
     -mllvm -cce-aicore-dcci-insert-for-scalar=false \
     --cce-aicore-input-parameter-size=1536 \
     -o out/vecadd/kernel.reloc.o out/vecadd/kernel.annotated.ll

ld.lld -m aicorelinux -Ttext=0 out/vecadd/kernel.reloc.o \
       -static -o out/vecadd/kernel.linked.o
```

`--cce-aicore-input-parameter-size=1536` 是 A5 的参数区上限；本内核实际只用
24 字节，由下面的容器节告诉运行时。

## 5. AscendC 容器格式

AscendC 运行时（`libascendc_runtime.a`）通过 `RegisterAscendBinary` 注册内核，
它期望的是一份"带元数据的对象"：

| 元素 | 值 | 不满足时的现象 |
| --- | --- | --- |
| 入口符号名 | `add_0`（内核名 + tiling key），且 `st_size` ≠ 0 | 裸 `add` 被 `CheckKernelsName` 拒绝（`cannot find '_'`）；`st_size` 为 0 时内核长度算成 0 |
| `__CCE_KernelArgSize` 节 | 4 字节 OBJECT 符号 `add_0__`，值为 24 | 运行时不知道参数块大小 |
| 注册类型 | `type = 0`（mix） | 1/2 会得到 507035 / 507015 |
| SoC 字符串 | 小写 `ascend310b1` | `AscendCheckSoCVersion` 失败 |

`scripts/20_build_vecadd.sh` 里的关键一步：

```bash
python3 -c 'import struct,sys;open(sys.argv[1],"wb").write(struct.pack("<I",24))' \
        out/vecadd/argsz.bin
llvm-objcopy --add-section __CCE_KernelArgSize=out/vecadd/argsz.bin \
             --redefine-sym add=add_0 \
             --add-symbol add_0__=__CCE_KernelArgSize:0,object,weak \
             out/vecadd/kernel.linked.o out/vecadd/kernel.o
```

这里必须用 `--redefine-sym`（保留编译器给出的符号大小），不要用
`--add-symbol`（新符号的 `st_size` 为 0）。

自检：

```bash
llvm-objdump -t out/vecadd/kernel.o | grep add_0
```

## 6. 主机侧启动序列

`examples/vecadd/src/vecadd_runner_310b1.cpp`：

```
aclInit → aclrtSetDevice → aclrtCreateStream
AscendCheckSoCVersion("ascend310b1")
AscendProfRegister()
RegisterAscendBinary(image, size, type=0, &handle)
aclrtMalloc x3 → aclrtMemcpy x2 (H2D)
LaunchAscendKernel(handle, tilingKey=0, blocks=1, args=void*[3], argsSize=24, stream)
aclrtSynchronizeStream → aclrtMemcpy (D2H) → 逐元素比较
```

设备函数 `add` 不是 CPU 可以直接 `call` 的符号：主机必须先加载设备 ELF 得到
opaque handle，再用参数块启动。这也正是 `llvm/launch_add.ll` 与
`llvm/direct_aclrt_launch.ll` 想表达的边界。
