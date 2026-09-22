# 补丁

补丁用 `git apply` 应用（脚本 `10_build_frontend.sh` / `11_build_hivmc.sh`
会自动做，并且是幂等的：已应用过的会跳过）。

```bash
# 前端（deps/AscendNPU-IR-a5，dev/regbase 的 worktree）
cd ../deps/AscendNPU-IR-a5
git apply ../../ascend310b1-vecadd/patches/frontend/*.patch

# 后端 hivmc（deps/AscendNPU-IR，master）
cd ../deps/AscendNPU-IR
git apply ../../ascend310b1-vecadd/patches/hivmc/*.patch
```

## frontend/

| 补丁 | 文件 | 原因 |
| --- | --- | --- |
| `0001-hfusion-matmul-anon-namespace.patch` | `lib/Conversion/HFusionToHIVM/Matmul.cpp` | GCC 不接受匿名命名空间模板在命名空间外的显式特化 |
| `0002-arith-to-hivmave-aptypehelper.patch` | `lib/Conversion/ArithToHIVMAVE/ArithToHIVMAVE.cpp` | GCC 不接受类作用域内的成员模板显式特化 |
| `0003-execution-engine-static-cast.patch` | `lib/ExecutionEngine/CreateHostMain.cpp` | GCC 无法解析 `cast<ShapedType>` 的重载集 |
| `0004-triton-verifybarrier-inline-*.patch` | `triton/.../TritonNvidiaGPU/Transforms/Utility.{h,cpp}` | 静态库顺序导致 `verifyBarrierType` 未定义 |

## hivmc/

| 补丁 | 文件 | 原因 |
| --- | --- | --- |
| `0001-arith-to-hivmave-aptypehelper.patch` | `lib/Conversion/ArithToHIVMAVE/ArithToHIVMAve.cpp` | 同前端第 2 条（master 上也有） |
| `0002-triton-verifybarrier-inline-*.patch` | 同上（triton） | 同前端第 4 条 |
| `0003-hivmc-cmake-link-group.patch` | `tools/hivmc/CMakeLists.txt` | BiShengIR/Triton 静态库成环，需要链接分组 |
| `0004-hivmc-a5-dav-m300-arch.patch` | `lib/Tools/hivmc/A5/HIVMCMainA5.cpp` | 310B 必须用 `dav-m300`，上游硬编码成 `dav-c220` |

链接分组只解决了 `LINK_LIBRARIES` 中的第一份库列表；CMake 追加的最后一组库仍然
在组外，因此 `scripts/11_build_hivmc.sh` 还会调用
`scripts/lib/relink_hivmc.py` 重新链接一次。
