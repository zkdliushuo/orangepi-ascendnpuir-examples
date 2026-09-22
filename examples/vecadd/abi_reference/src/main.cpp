#include "ascend_abi_runtime.h"

#include <array>
#include <cstdint>
#include <cstdlib>
#include <iostream>

int main(int argc, char **argv) {
  const char *binary = argc > 1 ? argv[1] : "build/kernel.o";
  int32_t device_id = argc > 2 ? std::atoi(argv[2]) : 0;
  constexpr uint64_t bytes = 16 * sizeof(int16_t);
  std::array<int16_t, 16> input0{};
  std::array<int16_t, 16> input1{};
  std::array<int16_t, 16> output{};
  for (int i = 0; i < 16; ++i) {
    input0[i] = static_cast<int16_t>(i);
    input1[i] = 1;
  }

  AscendAbiRuntime *runtime = nullptr;
  AscendAbiKernel *kernel = nullptr;
  uintptr_t device0 = 0, device1 = 0, device_output = 0;
  int status = ascend_abi_runtime_create(device_id, &runtime);
  if (status != 0)
    goto cleanup;
  status = ascend_abi_kernel_load_vector(runtime, binary, "add", &kernel);
  if (status != 0)
    goto cleanup;
  if ((status = ascend_abi_malloc(runtime, bytes, &device0)) != 0 ||
      (status = ascend_abi_malloc(runtime, bytes, &device1)) != 0 ||
      (status = ascend_abi_malloc(runtime, bytes, &device_output)) != 0)
    goto cleanup;
  if ((status = ascend_abi_memcpy(
           runtime, device0, bytes, reinterpret_cast<uintptr_t>(input0.data()),
           bytes, ASCEND_ABI_MEMCPY_HOST_TO_DEVICE)) != 0 ||
      (status = ascend_abi_memcpy(
           runtime, device1, bytes, reinterpret_cast<uintptr_t>(input1.data()),
           bytes, ASCEND_ABI_MEMCPY_HOST_TO_DEVICE)) != 0)
    goto cleanup;
  status = ascend_abi_launch_add(runtime, kernel, 1, device0, device1,
                                 device_output);
  if (status != 0 || (status = ascend_abi_synchronize(runtime)) != 0)
    goto cleanup;
  status = ascend_abi_memcpy(
      runtime, reinterpret_cast<uintptr_t>(output.data()), bytes,
      device_output, bytes, ASCEND_ABI_MEMCPY_DEVICE_TO_HOST);
  if (status != 0)
    goto cleanup;
  for (int i = 0; i < 16; ++i) {
    if (output[i] != i + 1) {
      std::cerr << "mismatch at " << i << ": " << output[i] << '\n';
      status = 1;
      goto cleanup;
    }
  }
  std::cout << "PASS: add[0..15] == [1..16]\n";

cleanup:
  ascend_abi_free(runtime, device_output);
  ascend_abi_free(runtime, device1);
  ascend_abi_free(runtime, device0);
  ascend_abi_kernel_destroy(kernel);
  int destroy_status = ascend_abi_runtime_destroy(runtime);
  return status != 0 ? status : destroy_status;
}
