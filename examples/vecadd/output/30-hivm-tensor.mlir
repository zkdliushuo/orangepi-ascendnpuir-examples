// Native Operation::dump after convert-to-hivm-op/module/0
module attributes {dlti.target_system_spec = #dlti.target_system_spec<"NPU" : #hacc.target_device_spec<#dlti.dl_entry<"AI_CORE_COUNT", 1 : i32>, #dlti.dl_entry<"CUBE_CORE_COUNT", 1 : i32>, #dlti.dl_entry<"VECTOR_CORE_COUNT", 1 : i32>, #dlti.dl_entry<"UB_SIZE", 2097152 : i32>, #dlti.dl_entry<"L1_SIZE", 8388608 : i32>, #dlti.dl_entry<"L0A_SIZE", 524288 : i32>, #dlti.dl_entry<"L0B_SIZE", 524288 : i32>, #dlti.dl_entry<"L0C_SIZE", 1048576 : i32>, #dlti.dl_entry<"UB_ALIGN_SIZE", 256 : i32>, #dlti.dl_entry<"L1_ALIGN_SIZE", 256 : i32>, #dlti.dl_entry<"L0C_ALIGN_SIZE", 4096 : i32>, #dlti.dl_entry<"MINIMAL_D_CACHE_SIZE", 0 : i32>, #dlti.dl_entry<"MAXIMUM_D_CACHE_SIZE", 0 : i32>, #dlti.dl_entry<"ARCH", "dav-m300">>>, hacc.target = #hacc.target<"Ascend310B1">} {
  func.func @add_get_tiling_struct_size_function() -> i64 attributes {hacc.function_kind = #hacc.function_kind<HOST>, hacc.host_func_type = #hacc.host_func_type<get_tiling_struct_size_function>} {
    %c0_i64 = arith.constant 0 : i64
    return %c0_i64 : i64
  }
  func.func @add_outlined_vf_0(%arg0: tensor<1024xi16>, %arg1: tensor<1024xi16>, %arg2: tensor<1024xi16>) -> tensor<1024xi16> attributes {hivm.vector_function, no_inline} {
    %c0_i16 = arith.constant 0 : i16
    %c128 = arith.constant 128 : index
    %c1024 = arith.constant 1024 : index
    %c0 = arith.constant 0 : index
    %0 = scf.for %arg3 = %c0 to %c1024 step %c128 iter_args(%arg4 = %arg2) -> (tensor<1024xi16>) {
      %extracted_slice = tensor.extract_slice %arg0[%arg3] [128] [1] : tensor<1024xi16> to tensor<128xi16>
      %extracted_slice_0 = tensor.extract_slice %arg1[%arg3] [128] [1] : tensor<1024xi16> to tensor<128xi16>
      %extracted_slice_1 = tensor.extract_slice %arg4[%arg3] [128] [1] : tensor<1024xi16> to tensor<128xi16>
      %1 = vector.transfer_read %extracted_slice[%c0], %c0_i16 {in_bounds = [true]} : tensor<128xi16>, vector<128xi16>
      %2 = vector.transfer_read %extracted_slice_0[%c0], %c0_i16 {in_bounds = [true]} : tensor<128xi16>, vector<128xi16>
      %3 = arith.addi %1, %2 : vector<128xi16>
      %4 = vector.transfer_write %3, %extracted_slice_1[%c0] {in_bounds = [true]} : vector<128xi16>, tensor<128xi16>
      %inserted_slice = tensor.insert_slice %4 into %arg4[%arg3] [128] [1] : tensor<128xi16> into tensor<1024xi16>
      scf.yield %inserted_slice : tensor<1024xi16>
    }
    return %0 : tensor<1024xi16>
  }
  func.func @add(%arg0: tensor<1024xi16> {hacc.arg_type = #hacc.arg_type<input>, hacc.input_idx = #hacc.input_idx<0>}, %arg1: tensor<1024xi16> {hacc.arg_type = #hacc.arg_type<input>, hacc.input_idx = #hacc.input_idx<1>}, %arg2: tensor<1024xi16> {hacc.arg_type = #hacc.arg_type<output>, hacc.output_idx = #hacc.output_idx<0>}) -> tensor<1024xi16> attributes {enable_auto_mark_buffer_size, hacc.block_dim = 1 : i64, hacc.function_kind = #hacc.function_kind<DEVICE>, hacc.get_tiling_struct_size_function = #hacc.get_tiling_struct_size_function<@add_get_tiling_struct_size_function>, hfusion.fusion_kind = #hfusion.fusion_kind<PURE_ELEMWISE>} {
    %0 = tensor.empty() : tensor<1024xi16>
    %1 = hivm.hir.load ins(%arg0 : tensor<1024xi16>) outs(%0 : tensor<1024xi16>) -> tensor<1024xi16>
    %2 = hivm.hir.load ins(%arg1 : tensor<1024xi16>) outs(%0 : tensor<1024xi16>) -> tensor<1024xi16>
    annotation.mark %1 {buffer_size_in_byte = 49120 : i64} : tensor<1024xi16>
    annotation.mark %2 {buffer_size_in_byte = 49120 : i64} : tensor<1024xi16>
    %3 = call @add_outlined_vf_0(%1, %2, %0) {hivm.vector_function, no_inline} : (tensor<1024xi16>, tensor<1024xi16>, tensor<1024xi16>) -> tensor<1024xi16>
    annotation.mark %3 {buffer_size_in_byte = 49120 : i64} : tensor<1024xi16>
    %4 = hivm.hir.store ins(%3 : tensor<1024xi16>) outs(%arg2 : tensor<1024xi16>) atomic = <none> -> tensor<1024xi16>
    return %4 : tensor<1024xi16>
  }
}
