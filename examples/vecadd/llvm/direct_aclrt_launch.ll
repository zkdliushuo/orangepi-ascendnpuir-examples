; Teaching-only direct ACL Runtime declaration.
target triple = "aarch64-unknown-linux-gnu"
declare i32 @aclrtKernelArgsInit(ptr, ptr)
declare i32 @aclrtKernelArgsAppend(ptr, ptr, i64, ptr)
declare i32 @aclrtKernelArgsFinalize(ptr)
declare i32 @aclrtLaunchKernelWithConfig(ptr, i32, ptr, ptr, ptr, ptr)

define i32 @launch_add_direct(ptr %function, ptr %stream, ptr %aiv_config,
                              i64 %input0, i64 %input1, i64 %output) {
entry:
  %args.slot = alloca ptr, align 8
  %arg0 = alloca i64, align 8
  %arg1 = alloca i64, align 8
  %arg2 = alloca i64, align 8
  %param.slot = alloca ptr, align 8
  store i64 %input0, ptr %arg0, align 8
  store i64 %input1, ptr %arg1, align 8
  store i64 %output, ptr %arg2, align 8
  %s0 = call i32 @aclrtKernelArgsInit(ptr %function, ptr %args.slot)
  %args = load ptr, ptr %args.slot, align 8
  %s1 = call i32 @aclrtKernelArgsAppend(ptr %args, ptr %arg0, i64 8,
                                        ptr %param.slot)
  %s2 = call i32 @aclrtKernelArgsAppend(ptr %args, ptr %arg1, i64 8,
                                        ptr %param.slot)
  %s3 = call i32 @aclrtKernelArgsAppend(ptr %args, ptr %arg2, i64 8,
                                        ptr %param.slot)
  %s4 = call i32 @aclrtKernelArgsFinalize(ptr %args)
  %status = call i32 @aclrtLaunchKernelWithConfig(
      ptr %function, i32 1, ptr %stream, ptr %aiv_config, ptr %args, ptr null)
  ret i32 %status
}
