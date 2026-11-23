// Native Operation::dump after hfusion-auto-schedule/module/0
module attributes {dlti.target_system_spec = #dlti.target_system_spec<"NPU" : #hacc.target_device_spec<#dlti.dl_entry<"AI_CORE_COUNT", 1 : i32>, #dlti.dl_entry<"CUBE_CORE_COUNT", 1 : i32>, #dlti.dl_entry<"VECTOR_CORE_COUNT", 1 : i32>, #dlti.dl_entry<"UB_SIZE", 2097152 : i32>, #dlti.dl_entry<"L1_SIZE", 8388608 : i32>, #dlti.dl_entry<"L0A_SIZE", 524288 : i32>, #dlti.dl_entry<"L0B_SIZE", 524288 : i32>, #dlti.dl_entry<"L0C_SIZE", 1048576 : i32>, #dlti.dl_entry<"UB_ALIGN_SIZE", 256 : i32>, #dlti.dl_entry<"L1_ALIGN_SIZE", 256 : i32>, #dlti.dl_entry<"L0C_ALIGN_SIZE", 4096 : i32>, #dlti.dl_entry<"MINIMAL_D_CACHE_SIZE", 0 : i32>, #dlti.dl_entry<"MAXIMUM_D_CACHE_SIZE", 0 : i32>, #dlti.dl_entry<"ARCH", "dav-m300">>>, hacc.target = #hacc.target<"Ascend310B1">} {
  func.func @add_tiling_function(%arg0: tensor<1024xi16> {hacc.arg_type = #hacc.arg_type<input>, hacc.input_idx = #hacc.input_idx<0>}, %arg1: tensor<1024xi16> {hacc.arg_type = #hacc.arg_type<input>, hacc.input_idx = #hacc.input_idx<1>}, %arg2: tensor<1024xi16> {hacc.arg_type = #hacc.arg_type<output>, hacc.output_idx = #hacc.output_idx<0>}) -> (i64 {hacc.arg_type = #hacc.arg_type<tiling_key>}, i64 {hacc.arg_type = #hacc.arg_type<tiling_data>}, i64 {hacc.arg_type = #hacc.arg_type<tiling_data>}, i64 {hacc.arg_type = #hacc.arg_type<tiling_data>}, i64 {hacc.arg_type = #hacc.arg_type<tiling_data>}) attributes {hacc.function_kind = #hacc.function_kind<HOST>, hacc.host_func_type = #hacc.host_func_type<tiling_function>} {
    %c49120_i64 = arith.constant 49120 : i64
    %c1_i64 = arith.constant 1 : i64
    %c1024_i64 = arith.constant 1024 : i64
    %c0_i64 = arith.constant 0 : i64
    return %c0_i64, %c1024_i64, %c1_i64, %c1_i64, %c49120_i64 : i64, i64, i64, i64, i64
  }
  func.func @add(%arg0: tensor<1024xi16> {hacc.arg_type = #hacc.arg_type<input>, hacc.input_idx = #hacc.input_idx<0>}, %arg1: tensor<1024xi16> {hacc.arg_type = #hacc.arg_type<input>, hacc.input_idx = #hacc.input_idx<1>}, %arg2: tensor<1024xi16> {hacc.arg_type = #hacc.arg_type<output>, hacc.output_idx = #hacc.output_idx<0>}, %arg3: i64 {hacc.arg_type = #hacc.arg_type<tiling_key>}, %arg4: i64 {hacc.arg_type = #hacc.arg_type<tiling_data>}, %arg5: i64 {hacc.arg_type = #hacc.arg_type<tiling_data>}, %arg6: i64 {hacc.arg_type = #hacc.arg_type<tiling_data>}, %arg7: i64 {hacc.arg_type = #hacc.arg_type<tiling_data>}) -> tensor<1024xi16> attributes {enable_auto_mark_buffer_size, hacc.block_dim = 1 : i64, hacc.function_kind = #hacc.function_kind<DEVICE>, hacc.tiling_function = #hacc.tiling_function<@add_tiling_function>, hfusion.fusion_kind = #hfusion.fusion_kind<PURE_ELEMWISE>} {
    %c1 = arith.constant 1 : index
    %c0 = arith.constant 0 : index
    %0 = tensor.empty() : tensor<1024xi16>
    %1 = arith.index_cast %arg4 : i64 to index
    %2 = scf.for %arg8 = %c0 to %c1 step %c1 iter_args(%arg9 = %arg2) -> (tensor<1024xi16>) {
      %3 = affine.apply affine_map<()[s0, s1] -> (-s0 + 1024 ceildiv s1)>()[%arg8, %1]
      %4 = scf.for %arg10 = %c0 to %3 step %c1 iter_args(%arg11 = %arg9) -> (tensor<1024xi16>) {
        %5 = arith.addi %arg8, %arg10 : index
        %6 = affine.apply affine_map<()[s0, s1] -> (s0 * s1)>()[%5, %1]
        %7 = affine.min affine_map<()[s0, s1] -> (-(s1 * s0) + 1024, s0)>()[%1, %5]
        %extracted_slice = tensor.extract_slice %arg0[%6] [%7] [1] : tensor<1024xi16> to tensor<?xi16>
        %extracted_slice_0 = tensor.extract_slice %0[%6] [%7] [1] : tensor<1024xi16> to tensor<?xi16>
        %8 = hfusion.load {__intermediate_producer__} ins(%extracted_slice : tensor<?xi16>) outs(%extracted_slice_0 : tensor<?xi16>) -> tensor<?xi16>
        annotation.mark %8 {buffer_size_in_byte = 49120 : i64} : tensor<?xi16>
        %extracted_slice_1 = tensor.extract_slice %arg1[%6] [%7] [1] : tensor<1024xi16> to tensor<?xi16>
        %9 = hfusion.load {__intermediate_producer__} ins(%extracted_slice_1 : tensor<?xi16>) outs(%extracted_slice_0 : tensor<?xi16>) -> tensor<?xi16>
        annotation.mark %9 {buffer_size_in_byte = 49120 : i64} : tensor<?xi16>
        %10 = linalg.elemwise_binary {__intermediate_producer__, fun = #linalg.binary_fn<add>} ins(%8, %9 : tensor<?xi16>, tensor<?xi16>) outs(%extracted_slice_0 : tensor<?xi16>) -> tensor<?xi16>
        annotation.mark %10 {buffer_size_in_byte = 49120 : i64} : tensor<?xi16>
        %extracted_slice_2 = tensor.extract_slice %arg11[%6] [%7] [1] : tensor<1024xi16> to tensor<?xi16>
        %11 = hfusion.store {hfusion.return_operand_num = 0 : i64} ins(%10 : tensor<?xi16>) outs(%extracted_slice_2 : tensor<?xi16>) -> tensor<?xi16>
        %inserted_slice = tensor.insert_slice %11 into %arg11[%6] [%7] [1] : tensor<?xi16> into tensor<1024xi16>
        scf.yield %inserted_slice : tensor<1024xi16>
      } {__tiled_for___2}
      scf.yield %4 : tensor<1024xi16>
    } {__tiled_for___1, map_for_to_forall, mapping = [#hivm.block]}
    return %2 : tensor<1024xi16>
  }
}
