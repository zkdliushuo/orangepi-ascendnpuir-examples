// vecadd for Ascend310B1, 1024 x i16 (device-only)
func.func @add(%a: tensor<1024xi16>, %b: tensor<1024xi16>) -> (tensor<1024xi16>)
attributes {hacc.function_kind = #hacc.function_kind<DEVICE>} {
  %0 = tensor.empty() : tensor<1024xi16>
  %1 = linalg.elemwise_binary { fun = #linalg.binary_fn<add> }
       ins(%a, %b : tensor<1024xi16>, tensor<1024xi16>)
       outs(%0 : tensor<1024xi16>) -> tensor<1024xi16>
  return %1 : tensor<1024xi16>
}
