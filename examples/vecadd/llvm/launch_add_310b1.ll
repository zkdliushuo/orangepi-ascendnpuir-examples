; Ascend310B1 (dav-m300) launch path expressed as CPU-side LLVM IR.
;
; The device function `add` is not a symbol the CPU can call.  The host has to
; hand the kernel ELF to the AscendC runtime, which returns an opaque handle,
; and then launch it with a 24 byte argument block holding the three 64-bit
; device addresses (input0, input1, output).  This file is the IR form of the
; launch sequence in ../src/vecadd_runner_310b1.cpp; the accompanying C++
; driver owns the ACL context, the device buffers and the result check.
target triple = "aarch64-unknown-linux-gnu"

declare i32 @LaunchAscendKernel(ptr, i64, i32, ptr, i32, ptr)
declare i32 @aclrtSynchronizeStream(ptr)

; handle   - value returned by RegisterAscendBinary
; key      - tiling key of the entry symbol (add_0 -> 0)
; stream   - aclrtStream
; args     - pointer to void *args[3]
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
