module attributes {dlti.target_system_spec = #dlti.target_system_spec<"NPU" : #hacc.target_device_spec<#dlti.dl_entry<"AI_CORE_COUNT", 1 : i32>, #dlti.dl_entry<"CUBE_CORE_COUNT", 1 : i32>, #dlti.dl_entry<"VECTOR_CORE_COUNT", 1 : i32>, #dlti.dl_entry<"UB_SIZE", 2097152 : i32>, #dlti.dl_entry<"L1_SIZE", 8388608 : i32>, #dlti.dl_entry<"L0A_SIZE", 524288 : i32>, #dlti.dl_entry<"L0B_SIZE", 524288 : i32>, #dlti.dl_entry<"L0C_SIZE", 1048576 : i32>, #dlti.dl_entry<"UB_ALIGN_SIZE", 256 : i32>, #dlti.dl_entry<"L1_ALIGN_SIZE", 256 : i32>, #dlti.dl_entry<"L0C_ALIGN_SIZE", 4096 : i32>, #dlti.dl_entry<"MINIMAL_D_CACHE_SIZE", 0 : i32>, #dlti.dl_entry<"MAXIMUM_D_CACHE_SIZE", 0 : i32>, #dlti.dl_entry<"ARCH", "dav-m300">>>, hacc.target = #hacc.target<"Ascend310B1">, hivm.module_core_type = #hivm.module_core_type<AIV>} {
  func.func @add_get_tiling_struct_size_function() -> i64 attributes {hacc.function_kind = #hacc.function_kind<HOST>, hacc.host_func_type = #hacc.host_func_type<get_tiling_struct_size_function>} {
    %0 = llvm.mlir.constant(0 : i64) : i64
    return %0 : i64
  }
  func.func @add_outlined_vf_0(%arg0: memref<1024xi16, #hivm.address_space<ub>>, %arg1: memref<1024xi16, #hivm.address_space<ub>>, %arg2: memref<1024xi16, #hivm.address_space<ub>>) attributes {hivm.vector_function, no_inline} {
    %0 = llvm.mlir.constant(0 : index) : i64
    %1 = llvm.mlir.constant(0 : i32) : i32
    %2 = llvm.mlir.constant(1024 : i32) : i32
    %3 = llvm.mlir.constant(128 : i32) : i32
    cf.br ^bb1(%1 : i32)
  ^bb1(%4: i32):  // 2 preds: ^bb0, ^bb2
    %5 = arith.cmpi slt, %4, %2 : i32
    cf.cond_br %5, ^bb2, ^bb3
  ^bb2:  // pred: ^bb1
    %6 = llvm.sext %4 : i32 to i64
    %7 = builtin.unrealized_conversion_cast %6 : i64 to index
    %base_buffer, %offset, %sizes, %strides = memref.extract_strided_metadata %arg0 : memref<1024xi16, #hivm.address_space<ub>> -> memref<i16, #hivm.address_space<ub>>, index, index, index
    %reinterpret_cast = memref.reinterpret_cast %base_buffer to offset: [%7], sizes: [128], strides: [1] : memref<i16, #hivm.address_space<ub>> to memref<128xi16, strided<[1], offset: ?>, #hivm.address_space<ub>>
    %8 = builtin.unrealized_conversion_cast %reinterpret_cast : memref<128xi16, strided<[1], offset: ?>, #hivm.address_space<ub>> to !llvm.struct<(ptr<6>, ptr<6>, i64, array<1 x i64>, array<1 x i64>)>
    %base_buffer_0, %offset_1, %sizes_2, %strides_3 = memref.extract_strided_metadata %arg1 : memref<1024xi16, #hivm.address_space<ub>> -> memref<i16, #hivm.address_space<ub>>, index, index, index
    %reinterpret_cast_4 = memref.reinterpret_cast %base_buffer_0 to offset: [%7], sizes: [128], strides: [1] : memref<i16, #hivm.address_space<ub>> to memref<128xi16, strided<[1], offset: ?>, #hivm.address_space<ub>>
    %9 = builtin.unrealized_conversion_cast %reinterpret_cast_4 : memref<128xi16, strided<[1], offset: ?>, #hivm.address_space<ub>> to !llvm.struct<(ptr<6>, ptr<6>, i64, array<1 x i64>, array<1 x i64>)>
    %base_buffer_5, %offset_6, %sizes_7, %strides_8 = memref.extract_strided_metadata %arg2 : memref<1024xi16, #hivm.address_space<ub>> -> memref<i16, #hivm.address_space<ub>>, index, index, index
    %reinterpret_cast_9 = memref.reinterpret_cast %base_buffer_5 to offset: [%7], sizes: [128], strides: [1] : memref<i16, #hivm.address_space<ub>> to memref<128xi16, strided<[1], offset: ?>, #hivm.address_space<ub>>
    %10 = builtin.unrealized_conversion_cast %reinterpret_cast_9 : memref<128xi16, strided<[1], offset: ?>, #hivm.address_space<ub>> to !llvm.struct<(ptr<6>, ptr<6>, i64, array<1 x i64>, array<1 x i64>)>
    %11 = llvm.extractvalue %8[1] : !llvm.struct<(ptr<6>, ptr<6>, i64, array<1 x i64>, array<1 x i64>)>
    %12 = llvm.extractvalue %8[2] : !llvm.struct<(ptr<6>, ptr<6>, i64, array<1 x i64>, array<1 x i64>)>
    %13 = llvm.getelementptr %11[%12] : (!llvm.ptr<6>, i64) -> !llvm.ptr<6>, i16
    %14 = llvm.mlir.constant(0 : i32) : i32
    %15 = llvm.mlir.constant(0 : i32) : i32
    %16 = llvm.mlir.constant(0 : i32) : i32
    %17 = "hivm_regbaseintrins.intr.hivm.vldsx1.v128s16"(%13, %14, %16, %15) : (!llvm.ptr<6>, i32, i32, i32) -> vector<128xi16>
    %18 = llvm.extractvalue %9[1] : !llvm.struct<(ptr<6>, ptr<6>, i64, array<1 x i64>, array<1 x i64>)>
    %19 = llvm.extractvalue %9[2] : !llvm.struct<(ptr<6>, ptr<6>, i64, array<1 x i64>, array<1 x i64>)>
    %20 = llvm.getelementptr %18[%19] : (!llvm.ptr<6>, i64) -> !llvm.ptr<6>, i16
    %21 = llvm.mlir.constant(0 : i32) : i32
    %22 = llvm.mlir.constant(0 : i32) : i32
    %23 = llvm.mlir.constant(0 : i32) : i32
    %24 = "hivm_regbaseintrins.intr.hivm.vldsx1.v128s16"(%20, %21, %23, %22) : (!llvm.ptr<6>, i32, i32, i32) -> vector<128xi16>
    %25 = llvm.mlir.constant(0 : i32) : i32
    %26 = llvm.mlir.constant(0 : i32) : i32
    %27 = "hivm_regbaseintrins.intr.hivm.pge.b16"(%25, %26) {mask_bit_width = 16 : i32} : (i32, i32) -> vector<256xi1>
    %28 = builtin.unrealized_conversion_cast %27 : vector<256xi1> to vector<128xi1>
    %29 = "hivm_regbaseintrins.intr.hivm.vadd.s.x"(%17, %24, %27) : (vector<128xi16>, vector<128xi16>, vector<256xi1>) -> vector<128xi16>
    %30 = llvm.mlir.constant(0 : i32) : i32
    %31 = llvm.mlir.constant(0 : i32) : i32
    %32 = "hivm_regbaseintrins.intr.hivm.pge.b16"(%30, %31) {mask_bit_width = 16 : i32} : (i32, i32) -> vector<256xi1>
    %33 = builtin.unrealized_conversion_cast %32 : vector<256xi1> to vector<128xi1>
    %34 = llvm.extractvalue %10[1] : !llvm.struct<(ptr<6>, ptr<6>, i64, array<1 x i64>, array<1 x i64>)>
    %35 = llvm.extractvalue %10[2] : !llvm.struct<(ptr<6>, ptr<6>, i64, array<1 x i64>, array<1 x i64>)>
    %36 = llvm.getelementptr %34[%35] : (!llvm.ptr<6>, i64) -> !llvm.ptr<6>, i16
    %37 = llvm.mlir.constant(0 : i32) : i32
    %38 = llvm.mlir.constant(0 : i32) : i32
    %39 = llvm.mlir.constant(1 : i32) : i32
    "hivm_regbaseintrins.intr.hivm.vstsx1.v128s16"(%29, %36, %37, %39, %38, %32) : (vector<128xi16>, !llvm.ptr<6>, i32, i32, i32, vector<256xi1>) -> ()
    %40 = arith.addi %4, %3 overflow<nsw> : i32
    cf.br ^bb1(%40 : i32)
  ^bb3:  // pred: ^bb1
    return
  }
  func.func private @load_gm_to_ubuf_1d_int16_t(memref<?xi16, strided<[?], offset: ?>, #hivm.address_space<gm>>, memref<?xi16, strided<[?], offset: ?>, #hivm.address_space<ub>>, i32, i16, index, i32) attributes {hacc.function_kind = #hacc.function_kind<DEVICE>, hacc.noinline, hivm.func_core_type = #hivm.func_core_type<AIV>, hivm_regbaseintrins.target = #hivm_regbaseintrins.target<"dav-m300">, llvm.emit_c_interface}
  func.func private @store_ubuf_to_gm_1d_int16_t(memref<?xi16, strided<[?], offset: ?>, #hivm.address_space<ub>>, memref<?xi16, strided<[?], offset: ?>, #hivm.address_space<gm>>, i32) attributes {hacc.function_kind = #hacc.function_kind<DEVICE>, hacc.noinline, hivm.func_core_type = #hivm.func_core_type<AIV>, hivm_regbaseintrins.target = #hivm_regbaseintrins.target<"dav-m300">, llvm.emit_c_interface}
  func.func @add(%arg0: memref<1024xi16, #hivm.address_space<gm>> {hacc.arg_type = #hacc.arg_type<input>, hacc.input_idx = #hacc.input_idx<0>}, %arg1: memref<1024xi16, #hivm.address_space<gm>> {hacc.arg_type = #hacc.arg_type<input>, hacc.input_idx = #hacc.input_idx<1>}, %arg2: memref<1024xi16, #hivm.address_space<gm>> {hacc.arg_type = #hacc.arg_type<output>, hacc.output_idx = #hacc.output_idx<0>}) attributes {enable_auto_mark_buffer_size, hacc.block_dim = 1 : i64, hacc.function_kind = #hacc.function_kind<DEVICE>, hacc.get_tiling_struct_size_function = #hacc.get_tiling_struct_size_function<@add_get_tiling_struct_size_function>, hfusion.fusion_kind = #hfusion.fusion_kind<PURE_ELEMWISE>, hivm_regbaseintrins.target = #hivm_regbaseintrins.target<"dav-m300">} {
    %0 = llvm.mlir.constant(0 : index) : i64
    %1 = builtin.unrealized_conversion_cast %0 : i64 to index
    %2 = llvm.mlir.constant(0 : i16) : i16
    %3 = llvm.mlir.constant(0 : i32) : i32
    %4 = llvm.mlir.constant(2048 : i64) : i64
    %5 = llvm.mlir.constant(0 : i64) : i64
    %6 = hivm.hir.pointer_cast(%5) : memref<1024xi16, #hivm.address_space<ub>>
    %7 = hivm.hir.pointer_cast(%5) : memref<1024xi16, #hivm.address_space<ub>>
    %cast = memref.cast %arg0 : memref<1024xi16, #hivm.address_space<gm>> to memref<?xi16, strided<[?], offset: ?>, #hivm.address_space<gm>>
    %cast_0 = memref.cast %7 : memref<1024xi16, #hivm.address_space<ub>> to memref<?xi16, strided<[?], offset: ?>, #hivm.address_space<ub>>
    call @load_gm_to_ubuf_1d_int16_t(%cast, %cast_0, %3, %2, %1, %3) : (memref<?xi16, strided<[?], offset: ?>, #hivm.address_space<gm>>, memref<?xi16, strided<[?], offset: ?>, #hivm.address_space<ub>>, i32, i16, index, i32) -> ()
    %8 = hivm.hir.pointer_cast(%4) : memref<1024xi16, #hivm.address_space<ub>>
    %cast_1 = memref.cast %arg1 : memref<1024xi16, #hivm.address_space<gm>> to memref<?xi16, strided<[?], offset: ?>, #hivm.address_space<gm>>
    %cast_2 = memref.cast %8 : memref<1024xi16, #hivm.address_space<ub>> to memref<?xi16, strided<[?], offset: ?>, #hivm.address_space<ub>>
    call @load_gm_to_ubuf_1d_int16_t(%cast_1, %cast_2, %3, %2, %1, %3) : (memref<?xi16, strided<[?], offset: ?>, #hivm.address_space<gm>>, memref<?xi16, strided<[?], offset: ?>, #hivm.address_space<ub>>, i32, i16, index, i32) -> ()
    hivm.hir.set_flag[<PIPE_MTE2>, <PIPE_V>, <EVENT_ID0>]
    hivm.hir.wait_flag[<PIPE_MTE2>, <PIPE_V>, <EVENT_ID0>]
    call @add_outlined_vf_0(%7, %8, %6) {hivm.vector_function, no_inline} : (memref<1024xi16, #hivm.address_space<ub>>, memref<1024xi16, #hivm.address_space<ub>>, memref<1024xi16, #hivm.address_space<ub>>) -> ()
    hivm.hir.set_flag[<PIPE_V>, <PIPE_MTE3>, <EVENT_ID0>]
    hivm.hir.wait_flag[<PIPE_V>, <PIPE_MTE3>, <EVENT_ID0>]
    %cast_3 = memref.cast %6 : memref<1024xi16, #hivm.address_space<ub>> to memref<?xi16, strided<[?], offset: ?>, #hivm.address_space<ub>>
    %cast_4 = memref.cast %arg2 : memref<1024xi16, #hivm.address_space<gm>> to memref<?xi16, strided<[?], offset: ?>, #hivm.address_space<gm>>
    call @store_ubuf_to_gm_1d_int16_t(%cast_3, %cast_4, %3) : (memref<?xi16, strided<[?], offset: ?>, #hivm.address_space<ub>>, memref<?xi16, strided<[?], offset: ?>, #hivm.address_space<gm>>, i32) -> ()
    return
  }
}
