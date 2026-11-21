; LLVM functions a Tomato program can call as !name (D27a). Run with: --llvm examples/mathlib.ll
declare double @llvm.sqrt.f64(double)

define double @sqrt(double %x) {
  %r = call double @llvm.sqrt.f64(double %x)
  ret double %r
}

define i64 @add(i64 %a, i64 %b) {
  %r = add i64 %a, %b
  ret i64 %r
}

define i1 @is_even(i32 %n) {
  %r = and i32 %n, 1
  %z = icmp eq i32 %r, 0
  ret i1 %z
}

define i32 @mul32(i32 %a, i32 %b) {
  %r = mul i32 %a, %b
  ret i32 %r
}

define void @nothing() {
  ret void
}
