// Minimal Ascend310B1 vecadd runner using the AscendC runtime ABI.
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
uint32_t LaunchAscendKernel(void *handle, uint64_t tilingKey,
                            uint32_t numBlocks, void **args,
                            uint32_t argsSize, const void *stream);
int UnregisterAscendBinary(void *handle);
bool AscendCheckSoCVersion(const char *socVersion, char *errorMessage);
void AscendProfRegister();
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
  std::fprintf(stderr, "%s failed: %d", operation, static_cast<int>(error));
  const char *message = aclGetRecentErrMsg();
  if (message != nullptr)
    std::fprintf(stderr, " (%s)", message);
  std::fputc('\n', stderr);
  return true;
}
} // namespace

int main(int argc, char **argv) {
  if (argc != 2) {
    std::fprintf(stderr, "usage: %s <kernel.o>\n", argv[0]);
    return 2;
  }

  static_assert(sizeof(void *) == 8,
                "the example requires a 64-bit AArch64 host");

  std::vector<char> image = readBinary(argv[1]);
  if (image.empty()) {
    std::fprintf(stderr, "cannot read kernel binary: %s\n", argv[1]);
    return 2;
  }

  bool aclInitialized = false;
  bool deviceSet = false;
  aclrtStream stream = nullptr;
  void *binaryHandle = nullptr;
  void *deviceA = nullptr;
  void *deviceB = nullptr;
  void *deviceC = nullptr;

  auto cleanup = [&]() {
    if (deviceC != nullptr)
      aclrtFree(deviceC);
    if (deviceB != nullptr)
      aclrtFree(deviceB);
    if (deviceA != nullptr)
      aclrtFree(deviceA);
    if (binaryHandle != nullptr)
      UnregisterAscendBinary(binaryHandle);
    if (stream != nullptr)
      aclrtDestroyStream(stream);
    if (deviceSet)
      aclrtResetDevice(0);
    if (aclInitialized)
      aclFinalize();
  };

  aclError aclStatus = aclInit(nullptr);
  if (aclFailed("aclInit", aclStatus))
    return 1;
  aclInitialized = true;

  aclStatus = aclrtSetDevice(0);
  if (aclFailed("aclrtSetDevice", aclStatus)) {
    cleanup();
    return 1;
  }
  deviceSet = true;

  aclStatus = aclrtCreateStream(&stream);
  if (aclFailed("aclrtCreateStream", aclStatus)) {
    cleanup();
    return 1;
  }

  char socError[512] = {};
  const bool socMatches = AscendCheckSoCVersion("ascend310b1", socError);
  std::printf("AscendCheckSoCVersion=%d msg=%s\n",
              static_cast<int>(socMatches), socError);
  if (!socMatches) {
    cleanup();
    return 1;
  }

  AscendProfRegister();
  std::printf("RegisterAscendBinary(size=%zu, type=0)\n", image.size());
  uint32_t runtimeStatus = RegisterAscendBinary(
      image.data(), image.size(), 0, &binaryHandle);
  std::printf("RegisterAscendBinary ret=%u handle=%p\n", runtimeStatus,
              binaryHandle);
  if (runtimeStatus != 0) {
    cleanup();
    return 1;
  }

  std::vector<int16_t> hostA(kElements);
  std::vector<int16_t> hostB(kElements, 1);
  std::vector<int16_t> hostC(kElements, -1);
  for (size_t i = 0; i < kElements; ++i)
    hostA[i] = static_cast<int16_t>(i);

  if (aclFailed("aclrtMalloc(A)",
                aclrtMalloc(&deviceA, kBytes, ACL_MEM_MALLOC_HUGE_FIRST)) ||
      aclFailed("aclrtMalloc(B)",
                aclrtMalloc(&deviceB, kBytes, ACL_MEM_MALLOC_HUGE_FIRST)) ||
      aclFailed("aclrtMalloc(C)",
                aclrtMalloc(&deviceC, kBytes, ACL_MEM_MALLOC_HUGE_FIRST)) ||
      aclFailed("aclrtMemcpy(A)",
                aclrtMemcpy(deviceA, kBytes, hostA.data(), kBytes,
                            ACL_MEMCPY_HOST_TO_DEVICE)) ||
      aclFailed("aclrtMemcpy(B)",
                aclrtMemcpy(deviceB, kBytes, hostB.data(), kBytes,
                            ACL_MEMCPY_HOST_TO_DEVICE))) {
    cleanup();
    return 1;
  }

  void *args[] = {deviceA, deviceB, deviceC};
  static_assert(sizeof(args) == 24,
                "three 64-bit device addresses must occupy 24 bytes");

  std::printf("LaunchAscendKernel(key=0, blocks=1, argsSize=%zu)\n",
              sizeof(args));
  runtimeStatus = LaunchAscendKernel(binaryHandle, 0, 1, args,
                                     static_cast<uint32_t>(sizeof(args)),
                                     stream);
  std::printf("LaunchAscendKernel ret=%u\n", runtimeStatus);
  if (runtimeStatus != 0) {
    cleanup();
    return 1;
  }

  aclStatus = aclrtSynchronizeStream(stream);
  std::printf("sync ret=%d\n", static_cast<int>(aclStatus));
  if (aclFailed("aclrtSynchronizeStream", aclStatus) ||
      aclFailed("aclrtMemcpy(C)",
                aclrtMemcpy(hostC.data(), kBytes, deviceC, kBytes,
                            ACL_MEMCPY_DEVICE_TO_HOST))) {
    cleanup();
    return 1;
  }

  size_t mismatches = 0;
  for (size_t i = 0; i < kElements; ++i) {
    if (hostC[i] != static_cast<int16_t>(i + 1))
      ++mismatches;
  }

  std::printf("check: %zu/%zu mismatched; c[0]=%d c[1]=%d c[%zu]=%d\n",
              mismatches, kElements, static_cast<int>(hostC[0]),
              static_cast<int>(hostC[1]), kElements - 1,
              static_cast<int>(hostC[kElements - 1]));
  std::printf(mismatches == 0 ? "VECADD PASS\n" : "VECADD FAIL\n");

  cleanup();
  return mismatches == 0 ? 0 : 1;
}
