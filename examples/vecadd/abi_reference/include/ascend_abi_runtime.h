#ifndef ASCEND_ABI_RUNTIME_H
#define ASCEND_ABI_RUNTIME_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct AscendAbiRuntime AscendAbiRuntime;
typedef struct AscendAbiKernel AscendAbiKernel;
enum AscendAbiMemcpyKind {
  ASCEND_ABI_MEMCPY_HOST_TO_DEVICE = 1,
  ASCEND_ABI_MEMCPY_DEVICE_TO_HOST = 2
};
int ascend_abi_runtime_create(int32_t device_id, AscendAbiRuntime **runtime);
int ascend_abi_runtime_destroy(AscendAbiRuntime *runtime);
int ascend_abi_kernel_load_vector(AscendAbiRuntime *runtime,
                                  const char *binary_path,
                                  const char *kernel_name,
                                  AscendAbiKernel **kernel);
int ascend_abi_kernel_destroy(AscendAbiKernel *kernel);
int ascend_abi_malloc(AscendAbiRuntime *runtime, uint64_t bytes,
                      uintptr_t *device_address);
int ascend_abi_free(AscendAbiRuntime *runtime, uintptr_t device_address);
int ascend_abi_memcpy(AscendAbiRuntime *runtime, uintptr_t destination,
                      uint64_t destination_bytes, uintptr_t source,
                      uint64_t bytes, int32_t kind);
/* Asynchronous launch; device addresses follow the device declaration order. */
int ascend_abi_launch_add(AscendAbiRuntime *runtime, AscendAbiKernel *kernel,
                          uint32_t block_dim, uintptr_t input0,
                          uintptr_t input1, uintptr_t output);
int ascend_abi_synchronize(AscendAbiRuntime *runtime);
#ifdef __cplusplus
}
#endif
#endif
