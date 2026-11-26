; Inline copies of the runtime's small-number and reference-count fast paths, for the link that `tomato run` and `tomato build` make in
; debug mode (native/tomato). The runtime's own functions (the ALWAYS ones in tomato_rt.c: tomato_int_add_c, tomato_retain, ...) are
; compiled apart from the program, so a plain link makes a call for every integer operation; the debug link used to avoid that with
; link-time optimisation, which costs about a second per build and, with clang 21 on Linux at -O1, inlined nothing anyway. Instead
; native/tomato puts this file in front of the program IR, and renames the program's calls to tomato_X into calls to tomato_inl_X (the
; ones defined here), so clang's ordinary -O1 inlines them. Nothing else is linked in: whatever a fast path does not handle (a big
; number, an overflow) calls the real tomato_X, which repeats the test and takes the slow path, so a copy here can only go wrong on
; the cases it claims to decide itself.
;
; Rules: the name of a copy is tomato_inl_ followed by the name of the runtime function without its tomato_ (the renaming reads the
; names from the `define` lines below, so a function added here is picked up with no other change); every copy is internal and
; alwaysinline, so none survives in the program; a `declare` here is dropped when the program declares the name itself. A number is
; a tagged word: odd words are small numbers (2v + 1, v in [-2^62, 2^62)), see int_mk_small in tomato_rt.c. Each copy must agree with
; the C function it names: tests/run.sh checks that on boundary values (the "inline fast paths" test).

declare void @llvm.assume(i1)
declare i1 @llvm.expect.i1(i1, i1)
declare { i64, i1 } @llvm.sadd.with.overflow.i64(i64, i64)
declare { i64, i1 } @llvm.ssub.with.overflow.i64(i64, i64)
declare { i64, i1 } @llvm.smul.with.overflow.i64(i64, i64)
declare i64 @tomato_int_dup(i64)
declare void @tomato_int_free(i64)
declare i64 @tomato_int_add_c(i64, i64, i32)
declare i64 @tomato_int_sub_c(i64, i64, i32)
declare i64 @tomato_int_mul_c(i64, i64, i32)
declare i64 @tomato_int_floordiv_c(i64, i64, i32)
declare i64 @tomato_int_mod_c(i64, i64, i32)
declare i64 @tomato_int_floordivp2_c(i64, i32, i32)
declare i64 @tomato_int_modp2_c(i64, i32, i32)
declare i32 @tomato_int_cmp_c(i64, i64, i32)
declare i64 @tomato_int_shl_c(i64, i64, i32)
declare i64 @tomato_int_shr_c(i64, i64, i32)
declare i64 @tomato_int_not(i64)
declare i64 @tomato_int_raw_c(i64, i32)

; a reference count (the first word of an object) that is above zero goes up; an immortal object (negative) is never counted
define internal void @tomato_inl_retain(ptr %p) alwaysinline {
entry:
  %null = icmp eq ptr %p, null
  br i1 %null, label %done, label %load
load:
  %rc = load i64, ptr %p
  %live = icmp sgt i64 %rc, 0
  br i1 %live, label %bump, label %done
bump:
  %rc1 = add i64 %rc, 1
  store i64 %rc1, ptr %p
  br label %done
done:
  ret void
}

define internal i64 @tomato_inl_int_dup(i64 %x) alwaysinline {
entry:
  %t = and i64 %x, 1
  %small0 = icmp ne i64 %t, 0
  %small = call i1 @llvm.expect.i1(i1 %small0, i1 true)
  br i1 %small, label %fast, label %slow
fast:
  ret i64 %x
slow:
  %r = call i64 @tomato_int_dup(i64 %x)
  ret i64 %r
}

; a big number has its own memory (the word 0 is a small zero too)
define internal void @tomato_inl_int_free(i64 %x) alwaysinline {
entry:
  %t = and i64 %x, 1
  %big = icmp eq i64 %t, 0
  %nz = icmp ne i64 %x, 0
  %both0 = and i1 %big, %nz
  %both = call i1 @llvm.expect.i1(i1 %both0, i1 false)
  br i1 %both, label %slow, label %done
slow:
  call void @tomato_int_free(i64 %x)
  br label %done
done:
  ret void
}

; (2a+1) + (2b+1) - 1 = 2(a+b)+1, and the 64-bit overflow flag is exactly "a+b is out of the small range"
define internal i64 @tomato_inl_int_add_c(i64 %x, i64 %y, i32 %m) alwaysinline {
entry:
  %a = and i64 %x, %y
  %t = and i64 %a, 1
  %small0 = icmp ne i64 %t, 0
  %small = call i1 @llvm.expect.i1(i1 %small0, i1 true)
  br i1 %small, label %fast, label %slow
fast:
  %y1 = sub i64 %y, 1
  %p = call { i64, i1 } @llvm.sadd.with.overflow.i64(i64 %x, i64 %y1)
  %ov = extractvalue { i64, i1 } %p, 1
  br i1 %ov, label %slow, label %ok
ok:
  %s = extractvalue { i64, i1 } %p, 0
  ret i64 %s
slow:
  %r = call i64 @tomato_int_add_c(i64 %x, i64 %y, i32 %m)
  ret i64 %r
}
define internal i64 @tomato_inl_int_add(i64 %x, i64 %y) alwaysinline {
entry:
  %r = call i64 @tomato_inl_int_add_c(i64 %x, i64 %y, i32 0)
  ret i64 %r
}

define internal i64 @tomato_inl_int_sub_c(i64 %x, i64 %y, i32 %m) alwaysinline {
entry:
  %a = and i64 %x, %y
  %t = and i64 %a, 1
  %small0 = icmp ne i64 %t, 0
  %small = call i1 @llvm.expect.i1(i1 %small0, i1 true)
  br i1 %small, label %fast, label %slow
fast:
  %y1 = sub i64 %y, 1
  %p = call { i64, i1 } @llvm.ssub.with.overflow.i64(i64 %x, i64 %y1)
  %ov = extractvalue { i64, i1 } %p, 1
  br i1 %ov, label %slow, label %ok
ok:
  %s = extractvalue { i64, i1 } %p, 0
  ret i64 %s
slow:
  %r = call i64 @tomato_int_sub_c(i64 %x, i64 %y, i32 %m)
  ret i64 %r
}
define internal i64 @tomato_inl_int_sub(i64 %x, i64 %y) alwaysinline {
entry:
  %r = call i64 @tomato_inl_int_sub_c(i64 %x, i64 %y, i32 0)
  ret i64 %r
}

; (2a+1 - 1) * b = 2ab, plus 1
define internal i64 @tomato_inl_int_mul_c(i64 %x, i64 %y, i32 %m) alwaysinline {
entry:
  %a = and i64 %x, %y
  %t = and i64 %a, 1
  %small0 = icmp ne i64 %t, 0
  %small = call i1 @llvm.expect.i1(i1 %small0, i1 true)
  br i1 %small, label %fast, label %slow
fast:
  %x1 = sub i64 %x, 1
  %yv = ashr i64 %y, 1
  %p = call { i64, i1 } @llvm.smul.with.overflow.i64(i64 %x1, i64 %yv)
  %ov = extractvalue { i64, i1 } %p, 1
  br i1 %ov, label %slow, label %ok
ok:
  %s = extractvalue { i64, i1 } %p, 0
  %r1 = or i64 %s, 1
  ret i64 %r1
slow:
  %r = call i64 @tomato_int_mul_c(i64 %x, i64 %y, i32 %m)
  ret i64 %r
}
define internal i64 @tomato_inl_int_mul(i64 %x, i64 %y) alwaysinline {
entry:
  %r = call i64 @tomato_inl_int_mul_c(i64 %x, i64 %y, i32 0)
  ret i64 %r
}

; Python-style floor division and modulo of two small numbers (a zero divisor and the one overflow, -2^62 // -1, are left to the runtime)
define internal i64 @tomato_inl_int_floordiv_c(i64 %x, i64 %y, i32 %m) alwaysinline {
entry:
  %a = and i64 %x, %y
  %t = and i64 %a, 1
  %small0 = icmp ne i64 %t, 0
  %small = call i1 @llvm.expect.i1(i1 %small0, i1 true)
  br i1 %small, label %check, label %slow
check:
  %av = ashr i64 %x, 1
  %bv = ashr i64 %y, 1
  %amin = icmp eq i64 %av, -4611686018427387904
  %bneg = icmp eq i64 %bv, -1
  %ovf = and i1 %amin, %bneg
  %bzero = icmp eq i64 %bv, 0
  %bad = or i1 %ovf, %bzero
  br i1 %bad, label %slow, label %fast
fast:
  %q = sdiv i64 %av, %bv
  %r = srem i64 %av, %bv
  %bpos = icmp sgt i64 %bv, 0
  %rneg = ashr i64 %r, 63
  %rpos = icmp sgt i64 %r, 0
  %rposx = sext i1 %rpos to i64
  %adj = select i1 %bpos, i64 %rneg, i64 %rposx
  %q2 = add i64 %q, %adj
  %w = shl i64 %q2, 1
  %w1 = or i64 %w, 1
  ret i64 %w1
slow:
  %s = call i64 @tomato_int_floordiv_c(i64 %x, i64 %y, i32 %m)
  ret i64 %s
}
define internal i64 @tomato_inl_int_floordiv(i64 %x, i64 %y) alwaysinline {
entry:
  %r = call i64 @tomato_inl_int_floordiv_c(i64 %x, i64 %y, i32 0)
  ret i64 %r
}

define internal i64 @tomato_inl_int_mod_c(i64 %x, i64 %y, i32 %m) alwaysinline {
entry:
  %a = and i64 %x, %y
  %t = and i64 %a, 1
  %small0 = icmp ne i64 %t, 0
  %small = call i1 @llvm.expect.i1(i1 %small0, i1 true)
  br i1 %small, label %check, label %slow
check:
  %av = ashr i64 %x, 1
  %bv = ashr i64 %y, 1
  %amin = icmp eq i64 %av, -4611686018427387904
  %bneg = icmp eq i64 %bv, -1
  %ovf = and i1 %amin, %bneg
  %bzero = icmp eq i64 %bv, 0
  %bad = or i1 %ovf, %bzero
  br i1 %bad, label %slow, label %fast
fast:
  %r = srem i64 %av, %bv
  %bpos = icmp sgt i64 %bv, 0
  %rneg = icmp slt i64 %r, 0
  %rpos = icmp sgt i64 %r, 0
  %addp = select i1 %rneg, i64 %bv, i64 0
  %addn = select i1 %rpos, i64 %bv, i64 0
  %add = select i1 %bpos, i64 %addp, i64 %addn
  %r2 = add i64 %r, %add
  %w = shl i64 %r2, 1
  %w1 = or i64 %w, 1
  ret i64 %w1
slow:
  %s = call i64 @tomato_int_mod_c(i64 %x, i64 %y, i32 %m)
  ret i64 %s
}
define internal i64 @tomato_inl_int_mod(i64 %x, i64 %y) alwaysinline {
entry:
  %r = call i64 @tomato_inl_int_mod_c(i64 %x, i64 %y, i32 0)
  ret i64 %r
}

; x // 2^k and x % 2^k for a constant k from 1 to 61: a shift and a mask on a tagged word
define internal i64 @tomato_inl_int_floordivp2_c(i64 %x, i32 %k, i32 %m) alwaysinline {
entry:
  %t = and i64 %x, 1
  %small0 = icmp ne i64 %t, 0
  %small = call i1 @llvm.expect.i1(i1 %small0, i1 true)
  br i1 %small, label %fast, label %slow
fast:
  %k64 = zext i32 %k to i64
  %s = ashr i64 %x, %k64
  %r1 = or i64 %s, 1
  ret i64 %r1
slow:
  %r = call i64 @tomato_int_floordivp2_c(i64 %x, i32 %k, i32 %m)
  ret i64 %r
}
define internal i64 @tomato_inl_int_modp2_c(i64 %x, i32 %k, i32 %m) alwaysinline {
entry:
  %t = and i64 %x, 1
  %small0 = icmp ne i64 %t, 0
  %small = call i1 @llvm.expect.i1(i1 %small0, i1 true)
  br i1 %small, label %fast, label %slow
fast:
  %k1 = add i32 %k, 1
  %k64 = zext i32 %k1 to i64
  %bit = shl i64 1, %k64
  %mask = sub i64 %bit, 2
  %v = and i64 %x, %mask
  %r1 = or i64 %v, 1
  ret i64 %r1
slow:
  %r = call i64 @tomato_int_modp2_c(i64 %x, i32 %k, i32 %m)
  %low = and i64 %r, 1
  %odd = icmp ne i64 %low, 0
  call void @llvm.assume(i1 %odd)
  ret i64 %r
}

; odd words order like the numbers they hold
define internal i32 @tomato_inl_int_cmp_c(i64 %x, i64 %y, i32 %m) alwaysinline {
entry:
  %a = and i64 %x, %y
  %t = and i64 %a, 1
  %small0 = icmp ne i64 %t, 0
  %small = call i1 @llvm.expect.i1(i1 %small0, i1 true)
  br i1 %small, label %fast, label %slow
fast:
  %lt = icmp slt i64 %x, %y
  %gt = icmp sgt i64 %x, %y
  %l = sext i1 %lt to i32
  %g = zext i1 %gt to i32
  %c = or i32 %l, %g
  ret i32 %c
slow:
  %r = call i32 @tomato_int_cmp_c(i64 %x, i64 %y, i32 %m)
  ret i32 %r
}
define internal i32 @tomato_inl_int_cmp(i64 %x, i64 %y) alwaysinline {
entry:
  %r = call i32 @tomato_inl_int_cmp_c(i64 %x, i64 %y, i32 0)
  ret i32 %r
}

; a shift by a small count: left when the result stays small, right by any small count
define internal i64 @tomato_inl_int_shl_c(i64 %x, i64 %n, i32 %m) alwaysinline {
entry:
  %a = and i64 %x, %n
  %t = and i64 %a, 1
  %small = icmp ne i64 %t, 0
  %c = ashr i64 %n, 1
  %inr = icmp ult i64 %c, 62
  %ok = and i1 %small, %inr
  br i1 %ok, label %fast, label %slow
fast:
  %v = ashr i64 %x, 1
  %r = shl i64 %v, %c
  %back = ashr i64 %r, %c
  %same = icmp eq i64 %back, %v
  %hi = icmp sle i64 %r, 4611686018427387903
  %lo = icmp sge i64 %r, -4611686018427387904
  %in = and i1 %hi, %lo
  %good = and i1 %same, %in
  br i1 %good, label %done, label %slow
done:
  %w = shl i64 %r, 1
  %w1 = or i64 %w, 1
  ret i64 %w1
slow:
  %s = call i64 @tomato_int_shl_c(i64 %x, i64 %n, i32 %m)
  ret i64 %s
}
define internal i64 @tomato_inl_int_shl(i64 %x, i64 %n) alwaysinline {
entry:
  %r = call i64 @tomato_inl_int_shl_c(i64 %x, i64 %n, i32 0)
  ret i64 %r
}

define internal i64 @tomato_inl_int_shr_c(i64 %x, i64 %n, i32 %m) alwaysinline {
entry:
  %a = and i64 %x, %n
  %t = and i64 %a, 1
  %small = icmp ne i64 %t, 0
  %c = ashr i64 %n, 1
  %nonneg = icmp sge i64 %c, 0
  %ok = and i1 %small, %nonneg
  br i1 %ok, label %fast, label %slow
fast:
  %v = ashr i64 %x, 1
  %big = icmp uge i64 %c, 63
  %cc = select i1 %big, i64 63, i64 %c
  %r = ashr i64 %v, %cc
  %w = shl i64 %r, 1
  %w1 = or i64 %w, 1
  ret i64 %w1
slow:
  %s = call i64 @tomato_int_shr_c(i64 %x, i64 %n, i32 %m)
  ret i64 %s
}
define internal i64 @tomato_inl_int_shr(i64 %x, i64 %n) alwaysinline {
entry:
  %r = call i64 @tomato_inl_int_shr_c(i64 %x, i64 %n, i32 0)
  ret i64 %r
}

; ~x is -1 - v, which is always small too (the range check mirrors the C function)
define internal i64 @tomato_inl_int_not(i64 %x) alwaysinline {
entry:
  %t = and i64 %x, 1
  %small0 = icmp ne i64 %t, 0
  %small = call i1 @llvm.expect.i1(i1 %small0, i1 true)
  br i1 %small, label %fast, label %slow
fast:
  %v = ashr i64 %x, 1
  %r = sub i64 -1, %v
  %hi = icmp sle i64 %r, 4611686018427387903
  %lo = icmp sge i64 %r, -4611686018427387904
  %in = and i1 %hi, %lo
  br i1 %in, label %ok, label %slow
ok:
  %w = shl i64 %r, 1
  %w1 = or i64 %w, 1
  ret i64 %w1
slow:
  %s = call i64 @tomato_int_not(i64 %x)
  ret i64 %s
}

; a machine integer from a number (a big one that does not fit stops the program in the runtime)
define internal i64 @tomato_inl_int_raw_c(i64 %x, i32 %m) alwaysinline {
entry:
  %t = and i64 %x, 1
  %small0 = icmp ne i64 %t, 0
  %small = call i1 @llvm.expect.i1(i1 %small0, i1 true)
  br i1 %small, label %fast, label %slow
fast:
  %v = ashr i64 %x, 1
  ret i64 %v
slow:
  %r = call i64 @tomato_int_raw_c(i64 %x, i32 %m)
  ret i64 %r
}
define internal i64 @tomato_inl_int_raw(i64 %x) alwaysinline {
entry:
  %r = call i64 @tomato_inl_int_raw_c(i64 %x, i32 0)
  ret i64 %r
}
