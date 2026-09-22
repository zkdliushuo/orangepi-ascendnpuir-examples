// Core of a CPU LLVM backend lowering. Error paths are omitted here.
llvm::FunctionCallee getAscendLaunchAdd(llvm::Module &module) {
  llvm::LLVMContext &context = module.getContext();
  llvm::Type *pointer = llvm::PointerType::getUnqual(context);
  llvm::Type *i32 = llvm::Type::getInt32Ty(context);
  llvm::Type *i64 = llvm::Type::getInt64Ty(context);
  auto *signature = llvm::FunctionType::get(
      i32, {pointer, pointer, i32, i64, i64, i64}, false);
  return module.getOrInsertFunction("ascend_abi_launch_add", signature);
}

llvm::Value *lowerAscendLaunch(llvm::IRBuilder<> &builder,
                               llvm::Module &module,
                               llvm::Value *runtime,
                               llvm::Value *kernel,
                               llvm::ArrayRef<llvm::Value *> addresses) {
  llvm::Value *blockDim = builder.getInt32(1);
  return builder.CreateCall(getAscendLaunchAdd(module),
                            {runtime, kernel, blockDim, addresses[0],
                             addresses[1], addresses[2]});
}
