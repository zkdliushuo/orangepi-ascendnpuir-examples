; CPU-side LLVM IR. Opaque runtime and kernel handles are ordinary pointers.
; Device addresses are explicit 64-bit integers on the AArch64 host.
target triple = "aarch64-unknown-linux-gnu"

declare i32 @ascend_abi_launch_add(ptr, ptr, i32, i64, i64, i64)
declare i32 @ascend_abi_synchronize(ptr)

define i32 @launch_and_wait(ptr %runtime, ptr %kernel,
                            i64 %input0, i64 %input1, i64 %output) {
entry:
  %launch_status = call i32 @ascend_abi_launch_add(
      ptr %runtime, ptr %kernel, i32 1,
      i64 %input0, i64 %input1, i64 %output)
  %launch_ok = icmp eq i32 %launch_status, 0
  br i1 %launch_ok, label %wait, label %done
wait:
  %wait_status = call i32 @ascend_abi_synchronize(ptr %runtime)
  ret i32 %wait_status
done:
  ret i32 %launch_status
}
