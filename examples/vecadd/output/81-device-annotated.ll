; ModuleID = 'LLVMDialectModule'
source_filename = "LLVMDialectModule"

; Function Attrs: noduplicate noinline willreturn
define internal ptc_simdvf void @add_outlined_vf_0(ptr addrspace(6) noalias %0, ptr addrspace(6) noalias %1, ptr addrspace(6) noalias %2) #0 {
  br label %4

4:                                                ; preds = %7, %3
  %5 = phi i32 [ %17, %7 ], [ 0, %3 ]
  %6 = icmp slt i32 %5, 1024
  br i1 %6, label %7, label %18

7:                                                ; preds = %4
  %8 = sext i32 %5 to i64
  %9 = getelementptr i16, ptr addrspace(6) %0, i64 %8
  %10 = call <128 x i16> @llvm.hivm.vldsx1.v128s16(ptr addrspace(6) %9, i32 0, i32 0, i32 0)
  %11 = getelementptr i16, ptr addrspace(6) %1, i64 %8
  %12 = call <128 x i16> @llvm.hivm.vldsx1.v128s16(ptr addrspace(6) %11, i32 0, i32 0, i32 0)
  %13 = call <256 x i1> @llvm.hivm.pge.b16(i32 0, i32 0)
  %14 = call <128 x i16> @llvm.hivm.vadd.s.x.v128i16(<128 x i16> %10, <128 x i16> %12, <256 x i1> %13)
  %15 = call <256 x i1> @llvm.hivm.pge.b16(i32 0, i32 0)
  %16 = getelementptr i16, ptr addrspace(6) %2, i64 %8
  call void @llvm.hivm.vstsx1.v128s16(<128 x i16> %14, ptr addrspace(6) %16, i32 0, i32 1, i32 0, <256 x i1> %15)
  %17 = add nsw i32 %5, 128
  br label %4

18:                                               ; preds = %4
  ret void
}

; Function Attrs: noinline
define private void @load_gm_to_ubuf_1d_int16_t(ptr addrspace(1) %0, ptr addrspace(1) %1, i64 %2, i64 %3, i64 %4, ptr addrspace(6) %5, ptr addrspace(6) %6, i64 %7, i64 %8, i64 %9, i32 %10, i16 %11, i64 %12, i32 %13) #1 {
  %15 = insertvalue { ptr addrspace(1), ptr addrspace(1), i64, [1 x i64], [1 x i64] } undef, ptr addrspace(1) %0, 0
  %16 = insertvalue { ptr addrspace(1), ptr addrspace(1), i64, [1 x i64], [1 x i64] } %15, ptr addrspace(1) %1, 1
  %17 = insertvalue { ptr addrspace(1), ptr addrspace(1), i64, [1 x i64], [1 x i64] } %16, i64 %2, 2
  %18 = insertvalue { ptr addrspace(1), ptr addrspace(1), i64, [1 x i64], [1 x i64] } %17, i64 %3, 3, 0
  %19 = insertvalue { ptr addrspace(1), ptr addrspace(1), i64, [1 x i64], [1 x i64] } %18, i64 %4, 4, 0
  %20 = alloca { ptr addrspace(1), ptr addrspace(1), i64, [1 x i64], [1 x i64] }, i64 1, align 8
  store { ptr addrspace(1), ptr addrspace(1), i64, [1 x i64], [1 x i64] } %19, ptr %20, align 8
  %21 = insertvalue { ptr addrspace(6), ptr addrspace(6), i64, [1 x i64], [1 x i64] } undef, ptr addrspace(6) %5, 0
  %22 = insertvalue { ptr addrspace(6), ptr addrspace(6), i64, [1 x i64], [1 x i64] } %21, ptr addrspace(6) %6, 1
  %23 = insertvalue { ptr addrspace(6), ptr addrspace(6), i64, [1 x i64], [1 x i64] } %22, i64 %7, 2
  %24 = insertvalue { ptr addrspace(6), ptr addrspace(6), i64, [1 x i64], [1 x i64] } %23, i64 %8, 3, 0
  %25 = insertvalue { ptr addrspace(6), ptr addrspace(6), i64, [1 x i64], [1 x i64] } %24, i64 %9, 4, 0
  %26 = alloca { ptr addrspace(6), ptr addrspace(6), i64, [1 x i64], [1 x i64] }, i64 1, align 8
  store { ptr addrspace(6), ptr addrspace(6), i64, [1 x i64], [1 x i64] } %25, ptr %26, align 8
  call void @_mlir_ciface_load_gm_to_ubuf_1d_int16_t(ptr %20, ptr %26, i32 %10, i16 %11, i64 %12, i32 %13)
  ret void
}

; Function Attrs: noinline
declare dso_local void @_mlir_ciface_load_gm_to_ubuf_1d_int16_t(ptr, ptr, i32, i16, i64, i32) #1

; Function Attrs: noinline
define private void @store_ubuf_to_gm_1d_int16_t(ptr addrspace(6) %0, ptr addrspace(6) %1, i64 %2, i64 %3, i64 %4, ptr addrspace(1) %5, ptr addrspace(1) %6, i64 %7, i64 %8, i64 %9, i32 %10) #1 {
  %12 = insertvalue { ptr addrspace(6), ptr addrspace(6), i64, [1 x i64], [1 x i64] } undef, ptr addrspace(6) %0, 0
  %13 = insertvalue { ptr addrspace(6), ptr addrspace(6), i64, [1 x i64], [1 x i64] } %12, ptr addrspace(6) %1, 1
  %14 = insertvalue { ptr addrspace(6), ptr addrspace(6), i64, [1 x i64], [1 x i64] } %13, i64 %2, 2
  %15 = insertvalue { ptr addrspace(6), ptr addrspace(6), i64, [1 x i64], [1 x i64] } %14, i64 %3, 3, 0
  %16 = insertvalue { ptr addrspace(6), ptr addrspace(6), i64, [1 x i64], [1 x i64] } %15, i64 %4, 4, 0
  %17 = alloca { ptr addrspace(6), ptr addrspace(6), i64, [1 x i64], [1 x i64] }, i64 1, align 8
  store { ptr addrspace(6), ptr addrspace(6), i64, [1 x i64], [1 x i64] } %16, ptr %17, align 8
  %18 = insertvalue { ptr addrspace(1), ptr addrspace(1), i64, [1 x i64], [1 x i64] } undef, ptr addrspace(1) %5, 0
  %19 = insertvalue { ptr addrspace(1), ptr addrspace(1), i64, [1 x i64], [1 x i64] } %18, ptr addrspace(1) %6, 1
  %20 = insertvalue { ptr addrspace(1), ptr addrspace(1), i64, [1 x i64], [1 x i64] } %19, i64 %7, 2
  %21 = insertvalue { ptr addrspace(1), ptr addrspace(1), i64, [1 x i64], [1 x i64] } %20, i64 %8, 3, 0
  %22 = insertvalue { ptr addrspace(1), ptr addrspace(1), i64, [1 x i64], [1 x i64] } %21, i64 %9, 4, 0
  %23 = alloca { ptr addrspace(1), ptr addrspace(1), i64, [1 x i64], [1 x i64] }, i64 1, align 8
  store { ptr addrspace(1), ptr addrspace(1), i64, [1 x i64], [1 x i64] } %22, ptr %23, align 8
  call void @_mlir_ciface_store_ubuf_to_gm_1d_int16_t(ptr %17, ptr %23, i32 %10)
  ret void
}

; Function Attrs: noinline
declare dso_local void @_mlir_ciface_store_ubuf_to_gm_1d_int16_t(ptr, ptr, i32) #1

define void @add(ptr addrspace(1) %0, ptr addrspace(1) %1, ptr addrspace(1) %2) #2 {
  call void @load_gm_to_ubuf_1d_int16_t(ptr addrspace(1) %0, ptr addrspace(1) %0, i64 0, i64 1024, i64 1, ptr addrspace(6) null, ptr addrspace(6) null, i64 0, i64 1024, i64 1, i32 0, i16 0, i64 0, i32 0)
  call void @load_gm_to_ubuf_1d_int16_t(ptr addrspace(1) %1, ptr addrspace(1) %1, i64 0, i64 1024, i64 1, ptr addrspace(6) inttoptr (i64 2048 to ptr addrspace(6)), ptr addrspace(6) inttoptr (i64 2048 to ptr addrspace(6)), i64 0, i64 1024, i64 1, i32 0, i16 0, i64 0, i32 0)
  call void @llvm.hivm.SET.FLAG.IMM(i64 4, i64 1, i64 0)
  call void @llvm.hivm.WAIT.FLAG.IMM(i64 4, i64 1, i64 0)
  call ptc_simdvf void @add_outlined_vf_0(ptr addrspace(6) null, ptr addrspace(6) inttoptr (i64 2048 to ptr addrspace(6)), ptr addrspace(6) null)
  call void @llvm.hivm.SET.FLAG.IMM(i64 1, i64 5, i64 0)
  call void @llvm.hivm.WAIT.FLAG.IMM(i64 1, i64 5, i64 0)
  call void @store_ubuf_to_gm_1d_int16_t(ptr addrspace(6) null, ptr addrspace(6) null, i64 0, i64 1024, i64 1, ptr addrspace(1) %2, ptr addrspace(1) %2, i64 0, i64 1024, i64 1, i32 0)
  ret void
}

; Function Attrs: nounwind readonly
declare <128 x i16> @llvm.hivm.vldsx1.v128s16(ptr addrspace(6) nocapture readonly, i32, i32, i32) #3

; Function Attrs: nounwind
declare <256 x i1> @llvm.hivm.pge.b16(i32, i32) #4

; Function Attrs: nounwind readnone
declare <128 x i16> @llvm.hivm.vadd.s.x.v128i16(<128 x i16>, <128 x i16>, <256 x i1>) #5

; Function Attrs: nounwind writeonly
declare void @llvm.hivm.vstsx1.v128s16(<128 x i16>, ptr addrspace(6) nocapture readonly, i32, i32, i32, <256 x i1>) #6

; Function Attrs: nounwind
declare void @llvm.hivm.SET.FLAG.IMM(i64, i64, i64) #4

; Function Attrs: nounwind
declare void @llvm.hivm.WAIT.FLAG.IMM(i64, i64, i64) #4

attributes #0 = { noduplicate noinline willreturn }
attributes #1 = { noinline "target-cpu"="dav-m300" "target-features"="+dav-m300" }
attributes #2 = { "target-cpu"="dav-m300" "target-features"="+dav-m300" }
attributes #3 = { nounwind readonly  }
attributes #4 = { nounwind }
attributes #5 = { nounwind readnone  }
attributes #6 = { nounwind writeonly  }

!llvm.module.flags = !{!0}

!0 = !{i32 2, !"Debug Info Version", i32 3}
!hivm.annotations = !{!1}
!1 = !{ptr @add, !"kernel", i32 1}
