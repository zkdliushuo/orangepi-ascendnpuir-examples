# This script targets the existing Linux AArch64, unstripped 1.2.0 frontend.
set pagination off
set confirm off
set print thread-events off
set breakpoint pending off
# The leading * is essential: a normal function breakpoint skips the prologue,
# after which x0 no longer necessarily contains the Operation * argument.
break *'mlir::Operation::emitError(llvm::Twine const&)'
commands 1
silent
set $dump_op = $x0
printf "\n=== BEGIN NATIVE OPERATION DUMP ===\n"
call ((void(*)(void*))&'mlir::Operation::dump()')((void*)$dump_op)
printf "\n=== END NATIVE OPERATION DUMP ===\n"
disable 1
continue
end
run
