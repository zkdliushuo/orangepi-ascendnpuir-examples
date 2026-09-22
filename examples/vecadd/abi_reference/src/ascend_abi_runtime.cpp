#include "ascend_abi_runtime.h"

#include <acl/acl.h>
#include <acl/acl_rt.h>

#include <fstream>
#include <iostream>
#include <new>
#include <vector>

struct AscendAbiRuntime {
  int32_t device_id;
  aclrtStream stream;
};

struct AscendAbiKernel {
  std::vector<char> image;
  aclrtBinHandle binary;
  aclrtFuncHandle function;
};

static int report(const char *operation, aclError error) {
  if (error != ACL_SUCCESS)
    std::cerr << operation << " failed: " << error << '\n';
  return static_cast<int>(error);
}

extern "C" int ascend_abi_runtime_create(int32_t device_id,
                                          AscendAbiRuntime **output) {
  if (output == nullptr)
    return -1;
  *output = nullptr;
  aclError error = aclInit(nullptr);
  if (error != ACL_SUCCESS)
    return report("aclInit", error);
  error = aclrtSetDevice(device_id);
  if (error != ACL_SUCCESS) {
    aclFinalize();
    return report("aclrtSetDevice", error);
  }
  auto *runtime = new (std::nothrow) AscendAbiRuntime{device_id, nullptr};
  if (runtime == nullptr) {
    aclrtResetDevice(device_id);
    aclFinalize();
    return -1;
  }
  error = aclrtCreateStream(&runtime->stream);
  if (error != ACL_SUCCESS) {
    delete runtime;
    aclrtResetDevice(device_id);
    aclFinalize();
    return report("aclrtCreateStream", error);
  }
  *output = runtime;
  return 0;
}

extern "C" int ascend_abi_runtime_destroy(AscendAbiRuntime *runtime) {
  if (runtime == nullptr)
    return 0;
  int status = report("aclrtDestroyStream", aclrtDestroyStream(runtime->stream));
  aclError reset_error = aclrtResetDevice(runtime->device_id);
  if (status == 0)
    status = report("aclrtResetDevice", reset_error);
  aclError finalize_error = aclFinalize();
  if (status == 0)
    status = report("aclFinalize", finalize_error);
  delete runtime;
  return status;
}

extern "C" int ascend_abi_kernel_load_vector(AscendAbiRuntime *runtime,
                                               const char *binary_path,
                                               const char *kernel_name,
                                               AscendAbiKernel **output) {
  if (runtime == nullptr || binary_path == nullptr || kernel_name == nullptr ||
      output == nullptr)
    return -1;
  *output = nullptr;
  std::ifstream file(binary_path, std::ios::binary);
  if (!file)
    return -2;
  std::vector<char> image((std::istreambuf_iterator<char>(file)),
                          std::istreambuf_iterator<char>());
  if (image.empty())
    return -3;

  auto *kernel = new (std::nothrow) AscendAbiKernel{
      std::move(image), nullptr, nullptr};
  if (kernel == nullptr)
    return -1;
  aclrtBinaryLoadOption option{};
  option.type = ACL_RT_BINARY_LOAD_OPT_LAZY_MAGIC;
  option.value.magic = ACL_RT_BINARY_MAGIC_ELF_VECTOR_CORE;
  aclrtBinaryLoadOptions options{&option, 1};
  aclError error = aclrtBinaryLoadFromData(kernel->image.data(),
                                            kernel->image.size(), &options,
                                            &kernel->binary);
  if (error != ACL_SUCCESS) {
    delete kernel;
    return report("aclrtBinaryLoadFromData", error);
  }
  error = aclrtBinaryGetFunction(kernel->binary, kernel_name, &kernel->function);
  if (error != ACL_SUCCESS) {
    aclrtBinaryUnLoad(kernel->binary);
    delete kernel;
    return report("aclrtBinaryGetFunction", error);
  }
  *output = kernel;
  return 0;
}

extern "C" int ascend_abi_kernel_destroy(AscendAbiKernel *kernel) {
  if (kernel == nullptr)
    return 0;
  int status = report("aclrtBinaryUnLoad", aclrtBinaryUnLoad(kernel->binary));
  delete kernel;
  return status;
}

extern "C" int ascend_abi_malloc(AscendAbiRuntime *runtime, uint64_t bytes,
                                  uintptr_t *device_address) {
  if (runtime == nullptr || device_address == nullptr)
    return -1;
  void *pointer = nullptr;
  aclError error = aclrtMalloc(&pointer, bytes, ACL_MEM_MALLOC_HUGE_FIRST);
  if (error == ACL_SUCCESS)
    *device_address = reinterpret_cast<uintptr_t>(pointer);
  return report("aclrtMalloc", error);
}

extern "C" int ascend_abi_free(AscendAbiRuntime *runtime,
                                uintptr_t device_address) {
  if (runtime == nullptr || device_address == 0)
    return 0;
  return report("aclrtFree",
                aclrtFree(reinterpret_cast<void *>(device_address)));
}

extern "C" int ascend_abi_memcpy(AscendAbiRuntime *runtime,
                                  uintptr_t destination,
                                  uint64_t destination_bytes,
                                  uintptr_t source, uint64_t bytes,
                                  int32_t kind) {
  if (runtime == nullptr)
    return -1;
  aclrtMemcpyKind acl_kind;
  if (kind == ASCEND_ABI_MEMCPY_HOST_TO_DEVICE)
    acl_kind = ACL_MEMCPY_HOST_TO_DEVICE;
  else if (kind == ASCEND_ABI_MEMCPY_DEVICE_TO_HOST)
    acl_kind = ACL_MEMCPY_DEVICE_TO_HOST;
  else
    return -1;
  return report("aclrtMemcpy",
                aclrtMemcpy(reinterpret_cast<void *>(destination),
                            destination_bytes,
                            reinterpret_cast<const void *>(source), bytes,
                            acl_kind));
}

extern "C" int ascend_abi_launch_add(AscendAbiRuntime *runtime,
                                      AscendAbiKernel *kernel,
                                      uint32_t block_dim, uintptr_t input0,
                                      uintptr_t input1, uintptr_t output) {
  if (runtime == nullptr || kernel == nullptr)
    return -1;
  aclrtArgsHandle arguments = nullptr;
  aclError error = aclrtKernelArgsInit(kernel->function, &arguments);
  if (error != ACL_SUCCESS)
    return report("aclrtKernelArgsInit", error);
  for (uintptr_t address : {input0, input1, output}) {
    aclrtParamHandle parameter = nullptr;
    error = aclrtKernelArgsAppend(arguments, &address, sizeof(address),
                                  &parameter);
    if (error != ACL_SUCCESS)
      return report("aclrtKernelArgsAppend", error);
  }
  error = aclrtKernelArgsFinalize(arguments);
  if (error != ACL_SUCCESS)
    return report("aclrtKernelArgsFinalize", error);
  aclrtLaunchKernelAttr attribute{};
  attribute.id = ACL_RT_LAUNCH_KERNEL_ATTR_ENGINE_TYPE;
  attribute.value.engineType = ACL_RT_ENGINE_TYPE_AIV;
  aclrtLaunchKernelCfg config{&attribute, 1};
  return report("aclrtLaunchKernelWithConfig",
                aclrtLaunchKernelWithConfig(kernel->function, block_dim,
                                            runtime->stream, &config,
                                            arguments, nullptr));
}

extern "C" int ascend_abi_synchronize(AscendAbiRuntime *runtime) {
  if (runtime == nullptr)
    return -1;
  return report("aclrtSynchronizeStream",
                aclrtSynchronizeStream(runtime->stream));
}
