// Native Operation::dump after convert-linalg-to-hfusion/module/0
module attributes {dlti.target_system_spec = #dlti.target_system_spec<"NPU" : #hacc.target_device_spec<#dlti.dl_entry<"AI_CORE_COUNT", 1 : i32>, #dlti.dl_entry<"CUBE_CORE_COUNT", 1 : i32>, #dlti.dl_entry<"VECTOR_CORE_COUNT", 1 : i32>, #dlti.dl_entry<"UB_SIZE", 2097152 : i32>, #dlti.dl_entry<"L1_SIZE", 8388608 : i32>, #dlti.dl_entry<"L0A_SIZE", 524288 : i32>, #dlti.dl_entry<"L0B_SIZE", 524288 : i32>, #dlti.dl_entry<"L0C_SIZE", 1048576 : i32>, #dlti.dl_entry<"UB_ALIGN_SIZE", 256 : i32>, #dlti.dl_entry<"L1_ALIGN_SIZE", 256 : i32>, #dlti.dl_entry<"L0C_ALIGN_SIZE", 4096 : i32>, #dlti.dl_entry<"MINIMAL_D_CACHE_SIZE", 0 : i32>, #dlti.dl_entry<"MAXIMUM_D_CACHE_SIZE", 0 : i32>, #dlti.dl_entry<"ARCH", "dav-m300">>>, hacc.target = #hacc.target<"Ascend310B1">} {
  func.func @add(%arg0: tensor<1024xi16>, %arg1: tensor<1024xi16>) -> tensor<1024xi16> attributes {hacc.function_kind = #hacc.function_kind<DEVICE>} {
    %0 = tensor.empty() : tensor<1024xi16>
    %1 = linalg.elemwise_binary {fun = #linalg.binary_fn<add>} ins(%arg0, %arg1 : tensor<1024xi16>, tensor<1024xi16>) outs(%0 : tensor<1024xi16>) -> tensor<1024xi16>
    return %1 : tensor<1024xi16>
  }
}
