// Driver for launch_add_310b1.ll: the kernel is launched from LLVM IR, this
// file only owns the ACL context, the device buffers and the result check.
#include <acl/acl.h>

#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <fstream>
#include <iterator>
#include <vector>

extern "C" {
uint32_t RegisterAscendBinary(const char *data, size_t size, uint32_t type,
                              void **handle);
int UnregisterAscendBinary(void *handle);
bool AscendCheckSoCVersion(const char *socVersion, char *errorMessage);
void AscendProfRegister();
// implementd by launch_add_310b1.ll
int32_t launch_and_wait_310b1(void *handle, uint64_t key, void *stream,
                              void **args);
}

namespace {
constexpr size_t kElements = 1024;
constexpr size_t kBytes = kElements * sizeof(int16_t);

std::vector<char> readBinary(const char *path) {
  std::ifstream input(path, std::ios::binary);
  if (!input)
    return {};
  return std::vector<char>(std::istreambuf_iterator<char>(input),
                           std::istreambuf_iterator<char>());
}

bool aclFailed(const char *operation, aclError error) {
  if (error == ACL_SUCCESS)
    return false;
  std::fprintf(stderr, "%s failed: %d\n", operation, static_cast<int>(error));
  return true;
}
} // namespace

int main(int argc, char **argv) {
  if (argc != 2) {
    std::fprintf(stderr, "usage: %s <kernel.o>\n", argv[0]);
    return 2;
  }

  std::vector<char> image = readBinary(argv[1]);
  if (image.empty()) {
    std::fprintf(stderr, "cannot read kernel binary: %s\n", argv[1]);
    return 2;
  }

  if (aclFailed("aclInit", aclInit(nullptr)))
    return 1;
  if (aclFailed("aclrtSetDevice", aclrtSetDevice(0)))
    return 1;
  aclrtStream stream = nullptr;
  if (aclFailed("aclrtCreateStream", aclrtCreateStream(&stream)))
    return 1;

  char socError[512] = {};
  if (!AscendCheckSoCVersion("ascend310b1", socError)) {
    std::fprintf(stderr, "unexpected SoC: %s\n", socError);
    return 1;
  }
  AscendProfRegister();

  void *handle = nullptr;
  uint32_t status = RegisterAscendBinary(image.data(), image.size(), 0,
                                         &handle);
  std::printf("RegisterAscendBinary ret=%u\n", status);
  if (status != 0)
    return 1;

  std::vector<int16_t> hostA(kElements), hostB(kElements, 1),
      hostC(kElements, -1);
  for (size_t i = 0; i < kElements; ++i)
    hostA[i] = static_cast<int16_t>(i);

  void *deviceA = nullptr;
  void *deviceB = nullptr;
  void *deviceC = nullptr;
  if (aclFailed("aclrtMalloc", aclrtMalloc(&deviceA, kBytes,
                                           ACL_MEM_MALLOC_HUGE_FIRST)) ||
      aclFailed("aclrtMalloc", aclrtMalloc(&deviceB, kBytes,
                                           ACL_MEM_MALLOC_HUGE_FIRST)) ||
      aclFailed("aclrtMalloc", aclrtMalloc(&deviceC, kBytes,
                                           ACL_MEM_MALLOC_HUGE_FIRST)) ||
      aclFailed("aclrtMemcpy", aclrtMemcpy(deviceA, kBytes, hostA.data(),
                                           kBytes, ACL_MEMCPY_HOST_TO_DEVICE)) ||
      aclFailed("aclrtMemcpy", aclrtMemcpy(deviceB, kBytes, hostB.data(),
                                           kBytes, ACL_MEMCPY_HOST_TO_DEVICE)))
    return 1;

  void *args[] = {deviceA, deviceB, deviceC};
  static_assert(sizeof(args) == 24, "three pointers must occupy 24 bytes");

  // the launch itself happens inside launch_add_310b1.ll
  int32_t launchStatus = launch_and_wait_310b1(handle, 0, stream, args);
  std::printf("launch_and_wait_310b1 ret=%d\n", static_cast<int>(launchStatus));
  if (launchStatus != 0)
    return 1;

  if (aclFailed("aclrtMemcpy", aclrtMemcpy(hostC.data(), kBytes, deviceC,
                                           kBytes, ACL_MEMCPY_DEVICE_TO_HOST)))
    return 1;

  size_t mismatches = 0;
  for (size_t i = 0; i < kElements; ++i) {
    if (hostC[i] != static_cast<int16_t>(i + 1))
      ++mismatches;
  }
  std::printf("check: %zu/%zu mismatched; c[0]=%d c[1]=%d c[%zu]=%d\n",
              mismatches, kElements, static_cast<int>(hostC[0]),
              static_cast<int>(hostC[1]), kElements - 1,
              static_cast<int>(hostC[kElements - 1]));
  std::printf(mismatches == 0 ? "VECADD PASS (LLVM IR launcher)\n"
                              : "VECADD FAIL (LLVM IR launcher)\n");

  UnregisterAscendBinary(handle);
  aclrtFree(deviceC);
  aclrtFree(deviceB);
  aclrtFree(deviceA);
  aclrtDestroyStream(stream);
  aclrtResetDevice(0);
  aclFinalize();
  return mismatches == 0 ? 0 : 1;
}
