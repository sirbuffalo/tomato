# Tomato: decision log

## Recording rules

- **Confirmed requirement:** directly stated by Davis; recorded in the specification with unresolved interpretation visible.
- **Proposed:** an option or recommendation awaiting Davis's decision. It is not normative.
- **Open:** a question has not been settled, including one whose dependencies are unresolved.
- **Accepted:** Davis explicitly selected the language rule; record his answer and its scope. When the evidence came through the shared-password web chat (no per-person identity), the entry notes the channel; D12n–q came that way and were re-confirmed by Davis in the authenticated byre task on 2026-11-08. Any future web-chat-sourced rule stays Proposed until he confirms it there.
- **Superseded:** a previously accepted rule was explicitly replaced; retain its history and replacement reference.

Organizing documents and suggesting an order of discussion are agent work. Substantive language choices require Davis's decision. Silence, a recommendation, or familiarity with another language is not acceptance.

## Initial brief

Source: Davis's task brief, relayed by his lead agent at the start of this task.

> Ok lets start designing tomato I want it to be a well designed easy to use typed garbage collected language with python like syntax but compiled I want everything to be decided no assumed

Earlier direction, also relayed: something between Python and Go.

These establish R01–R07 in the [specification](specification.md). R08–R12 come from later decisions (for example D01a–b, D02b, D12a–f, D15a–b), recorded in the specification’s requirement table and in those decisions’ entries.

## Accepted design direction

Source: Davis's answer to “What are the first one or two things you would like to build with Tomato?”

> I want it ot compile to llvm I wnat to be able use it for  webservers math and  also like some wasm cpmpiled partaily tomato web apps

### D01a — Intended uses: accepted

- Support web servers, math, and web apps with parts written in Tomato and compiled to WebAssembly.
- No priority among these uses, exclusive scope, initial release scope, or specific math workload was stated.
- Informs typing, numeric behavior, concurrency, libraries, runtime, targets, and host integration; none of those detailed rules are selected automatically.

### D15a — LLVM compilation backend: accepted

- Use LLVM for compilation, as explicitly requested by Davis.
- Other backends were not compared; this is a direct requirement rather than acceptance of an agent recommendation.
- LLVM version, compilation pipeline, optimization policy, ahead-of-time/JIT model, linking, and native platform support remain open.

### D15b — WebAssembly output: accepted

- Support WebAssembly output for the partly-Tomato web-app use case.
- How Tomato components interact with the rest of a web app remains open; no JavaScript/TypeScript API, framework, DOM binding, or host language has been selected.
- Garbage collection remains a confirmed requirement. Its WebAssembly implementation, runtime footprint, and supported WebAssembly features must be decided explicitly.

### D02a — Simplicity versus runtime speed: accepted

- Davis explicitly selected **“Simple by default, control when needed.”**
- Keep ordinary code easy to write, and allow extra detail for performance-sensitive sections. The tradeoff presented was additional concepts to learn when optimizing.
- Alternatives presented were favoring simplicity throughout, accepting performance limits, or favoring predictable speed throughout, requiring more everyday programmer choices.
- The decision sets a priority; it does not select numeric representations, memory rules, unsafe features, or any particular optimization mechanism.

### D02b — Performance goal: accepted direction; measurement open

Source: Davis's Dashboard reply:

> I want faster than python but comaprable to go so like faster than python but like if it is half the sped of go thatbis fine

- Aim for faster execution than Python and performance in Go's general range; roughly half Go's speed is acceptable to Davis.
- This sets a tolerance rather than requiring parity with Go. It is neither a measured result nor a universal speed guarantee.
- Workloads, Python/Go implementations and versions, hardware, metrics, and exact acceptance criteria remain open. No runtime, type representation, or optimization follows automatically.

Further context from Davis:

> Like if it is going to make it super slow runtime but if it is 20% simplicity

Together with his explicit D02a selection, this suggests avoiding major runtime slowdowns for simplicity, and Davis confirmed this reading by ticking “Confirm the D02b slowdown reading” in the authenticated byre task on 2026-11-08. The referent of “20%” is not explicit, so this log does not establish a numerical per-feature slowdown limit. Resolve a precise threshold if a concrete decision needs one.

### D01b — Concrete math workloads: accepted

Source: Davis's answer to “What kind of math do you most want to write in Tomato?”

> Like simple prime checking like fibinouchi mod x

- Use simple prime checking and Fibonacci modulo a number as initial math examples.
- These suggest integer algorithms as useful design examples. Input sizes, integer representation, modulo semantics, and algorithms remain open. Integer range and fixed-width arithmetic overflow are addressed in D05c–D05e.
- This answer does not require a matrix, machine-learning, or symbolic-math focus; it does not exclude those uses either.

## Accepted detailed semantics

### D04a — Compile-time type checking: accepted

- Evidence: Davis selected **“During compilation”** in response to whether Tomato should normally catch type mistakes during compilation or execution.
- Check ordinary code's type compatibility during compilation. Reject known type mismatches before running, even if the offending code would never be reached.
- The illustration was calling a function that takes a number with `square("hello")`; this was not an approval of Tomato syntax or conversion rules.
- The alternative was permitting startup and reporting the mismatch only if execution reaches it. The accepted tradeoff is that ordinary code must satisfy the type rules before it runs.
- D04b settles function annotations and inferred locals; D05o–x settle integer conversions and several contextual arithmetic rules. Detailed inference, remaining conversions/type relationships, and any explicit dynamic features remain open. Runtime failures are not all statically detectable.

### D04b — Function annotations and local inference: accepted

- Evidence: Davis selected **“Types on functions, infer locals”** and added “yes that god example but I want classes and also interfaces”.
- Require explicit parameter and return types for ordinary named functions; infer local variable types where possible.
- Chosen over inference throughout, including signatures, and explicit types throughout, including locals. This keeps function contracts visible and bodies concise at the cost of signature annotations.
- The example showed an annotated `square` function with an inferred `result` variable. Davis liked the example, but the question explicitly separated annotation policy from syntax and numeric type names. Later D05l/m/aj/ak name fixed-width integers, growing `int`, `float`, and `rational`; remaining syntax and numeric types require explicit choices.
- Precise inference rules, ambiguous cases, lambdas, generics, method/receiver details, and module-level declarations remain open.

### D12a — Classes and interfaces: accepted feature requirement

- Evidence: Davis explicitly requested “classes and also interfaces” in his D04b answer.
- Include both features. No class/interface semantics were presented for acceptance in that question.
- D12b–i settle single class inheritance, explicit multiple interfaces without default bodies, and later implementation declarations with checked existing methods/imported types and explicit sharing. D05a–b settle shared object assignment and arguments. Construction, detailed fields/methods, visibility, dispatch, and remaining type relationships remain open. Neither Python's class model nor Go's interface model is adopted implicitly.

### D12b — Single class inheritance: accepted

- Evidence: Davis selected **“One parent class”** when asked whether a class should inherit fields and methods from other classes.
- A class may inherit fields and methods from at most one parent class and replace selected methods. Multiple class inheritance is excluded.
- Davis chose this over the agent's recommendation of no inheritance and over multiple inheritance. The presented benefit was convenient shared implementation; the cost was that parent changes can affect children and require overriding/initialization rules.
- Exact overriding, construction order, visibility, dispatch, and subtype rules remain open. Interface conformance, the number of implemented interfaces, and interface inheritance were not part of this choice.

### D12c — Explicit interface conformance: accepted

- Evidence: Davis selected **“Explicit declaration”** when asked whether matching an interface's requirements is enough.
- A class must explicitly declare the interfaces it implements, and the compiler checks that it satisfies their requirements. Matching members alone do not establish conformance.
- Chosen over automatic conformance based on matching members. The presented benefit was visible intent; the cost was an additional declaration and potentially editing a class or writing an adapter for a new interface.
- D12d permits several implemented interfaces, D12e excludes default bodies, and D12f–i settle later implementation declarations, existing-method checking, imported types, and explicit sharing. Exact declaration syntax, and remaining interface capabilities remain open.

### D12d — Multiple implemented interfaces: accepted

- Evidence: Davis selected **“Allow several interfaces”** when asked whether one class can implement several interfaces.
- A class may explicitly implement multiple interfaces, while still inheriting from at most one parent class.
- Chosen over limiting each class to one implemented interface. The presented benefit was separate, focused capabilities such as `Readable` and `Writable` on a `File`; the cost is defining how overlapping requirements interact.
- D12e excludes default method implementations. Other interface contents, overlapping requirements, and interface inheritance remain open. This does not reintroduce multiple class inheritance.

### D12e — No interface default method bodies: accepted

- Evidence: Davis selected **“No default bodies.”**
- Interfaces declare method requirements but cannot provide default method implementations.
- Chosen over defaults reusable by implementing classes. The presented benefit was simpler rules about where behavior comes from; the cost was possibly repeating small methods or calling shared helpers.
- Other interface member kinds and interface inheritance remain open. D12f–i settle separate declarations that check existing methods without supplying new implementations.

### D12f — Implementation declaration after a class definition: accepted feature requirement

Source: Davis's Dashboard message:

> Add a state ment that is like x implejts x so after a class is defined you can add it to a interface for like module

- Support a separate explicit statement associating an already-defined class with an interface it implements. `Class implements Interface` illustrates the requested shape, not finalized grammar or keyword spelling.
- This refines D12c: declarations need not be confined to a class definition. Matching members alone still do not imply conformance.
- Davis mentioned modules; later D12h permits imported classes/interfaces and D12i selects local effect unless explicitly exported/imported, with no automatic global effect. Exact import/export syntax and detailed member visibility remain open.
- D12g requires checking existing methods only and forbids supplying missing ones. Duplicate/conflicting declarations, inherited effects, and runtime versus compile-time processing remain open.

### D12g — External declarations check existing methods only: accepted

- Evidence: Davis selected **“Check existing methods only.”**
- The separate declaration checks that the existing class supplies methods compatible with the interface. Missing required methods cause a compilation error.
- It does not supply missing implementations or add methods to the class.
- Chosen over an accompanying implementation block that could define missing methods for the class/interface pair. This keeps method definitions in their existing locations, at the cost of needing another approach when a class lacks a required method.
- D12h permits imported types on both sides and D12i settles declaration scope/sharing. Detailed compatibility, inherited member handling, member visibility, duplicate declarations, and processing phase remain open.

### D12h — Imported class and imported interface permitted: accepted

- Evidence: Davis selected **“Allow both to be imported.”**
- A module may declare that an imported class implements an imported interface, without defining either one. Existing methods must still satisfy the interface.
- Chosen over requiring the declaring module to define at least one side. The benefit presented was connecting compatible libraries without editing either definition; the tradeoff was that the class/interface authors do not control every declared relationship.
- D12i settles declaration visibility/sharing through explicit export/import, without global effect. Exact export/import syntax, duplicate handling, processing phase, and detailed member access rules remain open.

### D12i — Share declarations through explicit imports: accepted

- Evidence: Davis selected **“Share through explicit imports.”**
- A separate implementation declaration applies locally unless exported. Another module can use the exported relationship by explicitly importing the declaration; there is no automatic program-wide effect.
- Chosen over local-only declarations, which require repetition, and program-wide declarations, which let unrelated declarations affect a module's type checking. The selected tradeoff is visible dependencies with extra import bookkeeping.
- This concerns using a concrete class where an interface is required. Passing values already typed as interfaces, re-exports, duplicate declarations, and exact import/export syntax remain open.

### D05a — Class assignment shares the same object: accepted

- Evidence: Davis selected **“Share the same object.”**
- Assigning a class instance copies a reference to that same object, without copying its fields.
- In the hypothetical mutable-counter example, after `b = a` and `b.value = 1`, reading `a.value` yields `1` too. Syntax and mutability defaults were explicitly outside the question's scope.
- Chosen over copying the object's fields into a separate instance. The benefit presented was preserving object identity without field copying; the tradeoff was that mutations through one reference are visible through another.
- D05b settles class arguments: share the object via a local parameter, so rebinding does not replace the caller’s variable. Explicit copying tools, field mutability defaults, non-class arguments, and separate value types remain open.

### D05b — Shared class objects with local parameters: accepted

- Evidence: Davis selected **“Share object, keep parameter local.”**
- Passing a class instance copies the reference into a local parameter. Permitted changes to the object's fields affect the shared instance; rebinding the parameter to another object does not replace the caller's variable.
- The example started with a counter at 0, changed its field to 1 inside the function, then rebound the parameter to a new counter at 99. The accepted result is that the caller's original counter holds 1.
- Chosen over sharing the caller's variable itself (which would replace its reference) or copying the object's fields for the call. This preserves object sharing while keeping parameter reassignment local.
- Explicit alternative parameter modes, non-class argument types, exact syntax, and mutability defaults remain open.

### D05c — Arbitrary-precision default integers: accepted

- Evidence: Davis selected **“Automatically growing integers”** and added **“arbatray size”**.
- Ordinary whole numbers are signed arbitrary-precision integers, growing automatically as needed subject to available resources. They have no fixed bit-width limit and do not silently wrap or truncate to a fixed range.
- Chosen over the agent's recommendation of a fixed 64-bit signed default. The benefit presented was exact whole-number results beyond a fixed ceiling; the cost was arithmetic and storage that accommodate increasing size.
- This is compatible with the desire for easy integer math, but does not demonstrate the stated performance target. No representation strategy or benchmark result is assumed.
- D05m names the growing integer `int`; D05d/f/g/l settle optional signed/unsigned fixed-width forms, programmer-chosen widths, and `int[length=x]` / `uint[length=x]` notation. D05o–x settle integer conversions and addition/subtraction/multiplication details; D05y–aj settle fractional division’s result and several error/rounding rules. Internal representation, resource exhaustion, remaining arithmetic/conversion rules, and integer quotient/modulo remain open. The default has no fixed-width overflow.

### D05d — Optional fixed-width integer types: accepted

- Evidence: Davis selected **“Offer optional fixed-width types.”**
- Provide explicitly chosen fixed-width integer types alongside ordinary arbitrary-precision integers. The default does not change.
- Chosen over having no built-in bounded integer types. The benefit presented was control over bounded representations for binary formats or performance-sensitive calculations; the cost is additional types, conversions, and overflow rules.
- D05l names fixed-width forms `int[length=x]` and `uint[length=x]`; D05m names growing `int`. D05o–r settle integer conversion/literal rules and D05x settles constant failure timing. D05e settles arithmetic overflow, D05f requires signed/unsigned forms, and D05g permits programmer-chosen widths. Remaining conversions, representation, resource limits, and arithmetic outside later accepted rules remain open. No performance improvement is guaranteed.

### D05e — Fixed-width arithmetic reports overflow: accepted

- Evidence: when asked “When arithmetic exceeds a fixed-width integer’s range, should Tomato report an error or wrap around?”, Davis selected **“Report an error.”**
- Arithmetic that produces a result outside the fixed-width type's representable range reports an overflow error rather than wrapping. Ordinary automatically growing integers keep D05c's accepted behavior.
- Chosen over wraparound. The presented benefit was catching out-of-range mistakes; the cost is overflow checks and a failure path. No particular performance cost is assumed.
- The original question illustrated a signed 8-bit range of −128 through 127: adding 127 and 1 reports overflow rather than producing −128. D05g/k/l subsequently accept programmer-chosen widths, this signed range, and the spelling `int[length=8]`.
- D05x settles compilation errors for evaluable constant overflow wherever written. Error representation, handling/recovery, analysis beyond D05x, remaining conversion rules, and separate explicit wrapping operations remain open.

### D05f — Signed and unsigned fixed-width integers: accepted

- Evidence: when asked “Should optional fixed-width integer types be signed only, or include both signed and unsigned types?”, Davis selected **“Signed and unsigned.”**
- Include both forms for optional fixed-width integers. Ordinary automatically growing integers remain signed, and D05e's overflow-error rule applies to both fixed-width forms.
- Chosen over signed-only fixed-width types. The presented benefit was a direct fit for nonnegative binary fields and counts alongside negative values; the cost is more types and conversion rules.
- The original question illustrated signed 8-bit −128 through 127 and unsigned 8-bit 0 through 255. D05g/k/l/n subsequently accept programmer-chosen widths, those ranges, and `int[length=8]` / `uint[length=8]` spelling.
- D05g settles the width-selection direction. D05l–m settle names and D05n settles unsigned ranges. D05o–r settle integer conversion policy/spelling and literal typing; D05x settles constant-error timing. D05s–w settle addition/subtraction/multiplication typing and D05y–aj settle several fractional division rules. Representation, remaining conversion details, division operand/context rules, integer quotient/modulo, and other operators remain open.

### D05g — Arbitrary fixed-width bit lengths: accepted

- Evidence: asked which fixed-width sizes to provide, Davis rejected both preset-list options and answered **“arbatrary bit lengths.”**
- Support programmer-chosen bit lengths for fixed-width integer types, rather than restricting them to 8/16/32/64 bits or that list plus 128.
- Both signed and unsigned forms remain required, and arithmetic overflow reports an error. This does not change ordinary automatically growing integers.
- The choice permits application-specific widths, at the cost of defining width syntax, validity, resources and type rules. D05l subsequently supplies accepted examples `int[length=7]` and `uint[length=19]`; broader grammar remains open.
- D05h settles compile-time versus runtime selection. D05i requires at least one bit. D05j allows constant calculations. D05o–r/x settle integer conversion/literal rules and constant-error timing. Resource limits, detailed expression rules, representation and remaining conversions remain open; D05l–m settle names and D05n settles unsigned ranges.

### D05h — Fixed-width bit length known at compile time: accepted

- Evidence: asked whether a fixed-width integer's bit length must be known at compile time or may be chosen by a running program, Davis selected **“Known at compile time.”**
- A fixed-width integer type's width must be known during compilation. Runtime input cannot directly select the width of such a type.
- Chosen over additionally supporting runtime-chosen bounded widths. This keeps width in ordinary static type information, at the cost of excluding that dynamic selection capability from these types.
- D05j allows constant calculations. D05l settles fixed-width type notation and D05o–r/x settle integer conversion/literal rules and constant-error timing. Detailed compile-time evaluation rules, resource limits, representation and remaining conversions remain open; D05n settles unsigned ranges; D05i settles the minimum width. This decision does not change ordinary automatically growing integers.

### D05i — Fixed widths require at least one bit: accepted

- Evidence: asked whether zero-bit integer types should be allowed or a fixed width must be at least one bit, Davis selected **“At least one bit.”**
- A width must be a positive whole number. Zero and negative widths are compilation errors, for signed and unsigned fixed-width integers.
- Chosen over allowing zero-bit types holding only zero. This avoids that special case, at the cost of rejecting width calculations that produce zero.
- D05j permits constant calculations. Resource limits, detailed width-expression rules, and memory representation remain open; D05l settles spelling and D05n settles unsigned ranges.

### D05j — Compile-time constant width calculations: accepted

- Evidence: asked whether a bit width may be calculated from compile-time constants or must be a literal number, Davis selected **“Allow constant calculations.”**
- Widths may use integer literals, named compile-time integer constants, and arithmetic using those constants. The result must be known during compilation and be a positive whole number.
- Chosen over literal-only widths. This reduces repetition and allows derived widths, at the cost of specifying allowed expressions and evaluation failures.
- The example used a compile-time constant of 10 multiplied by 8 to obtain an 80-bit width. It established a capability, not exact type or expression syntax.
- Detailed evaluation rules, constant declaration syntax, resource limits and broader compile-time execution capabilities remain open.

### D05k — One extra negative value in signed ranges: accepted

- Evidence: asked whether signed fixed-width integers should have one extra negative value or a symmetric range, Davis selected **“One extra negative value.”**
- A signed N-bit integer represents −2^(N−1) through 2^(N−1)−1, inclusive. The question explicitly gave −64 through 63 for 7 bits and −1 or 0 for 1 bit.
- Chosen over the symmetric range −(2^(N−1)−1) through 2^(N−1)−1. The accepted range gives every bit pattern a distinct mathematical value, at the cost of the minimum value's negation overflowing under D05e.
- This settles mathematical ranges, not memory layout. D05l–m settle names and D05n settles unsigned ranges. D05o–r/x settle integer conversion/literal rules and constant-error timing. D05s–w settle addition/subtraction/multiplication typing and D05y–aj settle several fractional division rules. Exact encoding, remaining conversion details, division operand/context rules, integer quotient/modulo, and other operators remain open.

### D05l — int[length=x] and uint[length=x]: accepted syntax

- Evidence: asked to choose a fixed-width type notation, Davis rejected the offered spellings and wrote **“no int[length=x] and uint[length=x]”.**
- Use `int[length=x]` for a signed fixed-width integer type and `uint[length=x]` for an unsigned one, with `length` specifying the compile-time bit width.
- The width still supports compile-time constants/arithmetic and must be a positive whole number. `int[length=7]` and `uint[length=19]` are accepted examples of this type notation.
- Chosen over `Int[7]`/`UInt[19]`, `i[7]`/`u[19]`, and `Int(7)`/`UInt(19)`. The selected notation makes the meaning of the parameter explicit, at the cost of additional text.
- D05m settles the bare ordinary integer name. Any bare unsigned-growing type, broader generic/named-argument syntax, detailed expression grammar, remaining conversions beyond D05o–r/x and memory encoding remain open; D05n settles unsigned ranges.

### D05m — int for ordinary growing integers: accepted syntax

- Evidence: asked whether to name the ordinary automatically growing integer `int` or `bigint`, Davis selected **`int`**.
- Bare `int` denotes the signed arbitrary-precision integer that grows as needed under D05c; `int[length=x]` retains the fixed-width meaning from D05l.
- Chosen over `bigint`. This keeps the ordinary name short and shares a name with its bounded form, at the cost of the bare name not explicitly advertising arbitrary precision.
- This does not approve a bare unsigned-growing type, settle annotation/declaration grammar, or change conversions, representation, resource-exhaustion behavior, or other numeric rules.

### D05n — Full unsigned fixed-width range: accepted

- Evidence: asked whether `uint[length=N]` should represent 0 through 2^N − 1 inclusive, Davis answered **“yes”**. The question gave 0 through 127 for 7 bits and 0 or 1 for 1 bit.
- Use that inclusive range for every valid positive width N. Arithmetic outside it reports overflow under D05e, including subtraction below zero.
- This uses all N bits for nonnegative values, without reserving a value or excluding zero. The tradeoff is that every bit pattern is already a numeric value, leaving no spare numeric pattern for a sentinel.
- This settles mathematical ranges, not memory encoding or the error mechanism. D05o–r/x settle integer conversion/literal rules and constant-error timing; D05s–w settle addition/subtraction/multiplication typing and D05y–aj settle several fractional division rules. Remaining conversion details, division operand/context rules, integer quotient/modulo, and other operators remain open.

### D05o — Automatic lossless integer conversions: accepted

- Evidence: asked whether integer conversions should happen automatically when the destination can represent every source-type value, Davis selected **“Allow automatic lossless conversions”** over requiring every conversion explicitly.
- For already-typed integer assignments, function arguments, and returns, permit an automatic conversion when the destination covers the source type’s entire range. This is a type-range rule, not a test of the current value.
- The accepted examples are `int[length=7]` to `int[length=16]`, `uint[length=7]` to `int[length=8]`, and any fixed-width integer to growing `int`.
- Other conversions between distinct integer types require an explicit request, even if a particular current value fits. This reduces repetitive widening requests, at the cost of some type changes being implicit.
- D05r settles direct literal typing. D05s–w settle integer addition/subtraction/multiplication typing, D05y–aj settle several integer division rules, and D05at settles exact rational addition. Remaining division operand/context rules, integer quotient/modulo, mixed rational operands, other operators, and resource-exhaustion behavior remain open; D05p settles out-of-range behavior and D05q settles integer conversion syntax. Earlier references to unresolved integer conversions are now narrowed by this decision.

### D05p — Errors for out-of-range explicit integer conversions: accepted

- Evidence: asked what an explicit integer conversion should do when a runtime value will not fit, Davis selected **“Report an error”** over wrapping or clamping.
- An ordinary explicit conversion reports an error if the runtime integer is outside the destination type’s representable range. This applies to signed and unsigned destinations.
- The accepted examples convert growing `int` values 300 and −1 to `uint[length=8]` (0 through 255); both fail, rather than producing 44/255 by wrapping or 255/0 by clamping.
- This preserves numeric meaning and catches mistakes, at the cost of a range check and a failure path. No exact performance cost is assumed.
- D05q settles integer conversion syntax. D05x settles compilation errors for evaluable constant out-of-range conversions wherever written. Error handling/representation, analysis beyond D05x, and separate explicit wrapping/clamping operations remain open.

### D05q — Call the destination type for integer conversions: accepted syntax

- Evidence: asked how to spell explicit integer conversions, Davis selected **“Call the destination type”** over `as` and a `convert` function.
- Use `int[length=8](value)`, `uint[length=8](value)`, or `int(value)` for integer-to-integer conversions, with the destination type before the parenthesized source value.
- Bounded destinations use D05p’s checked conversion rule. The syntax is compact and reuses the destination type, at the cost of call-shaped syntax also representing conversion.
- This does not approve class construction syntax, general function-call grammar, first-class type values, string parsing, or conversions from noninteger kinds of value.

### D05r — Integer literals take an expected type when they fit: accepted

- Evidence: asked whether integer literals should take an expected integer type or always start as growing `int`, Davis selected **“Use the expected type when it fits”**.
- A direct integer literal takes the expected integer type if its value is representable; without an expected integer type, it has type `int`.
- The accepted example passes literal `42` directly to a `uint[length=8]` parameter without a conversion. Literal `300` in that position is a compile error because it cannot fit.
- Chosen over making every literal start as `int` and requiring `uint[length=8](42)` for that argument. This reduces repetitive conversions, at the cost of literal types depending on context.
- Already-typed values retain D05o’s full-source-range conversion rule. D05v–w settle expected-type propagation for direct-literal and literal-only addition/subtraction/multiplication trees, including bounded intermediate checks. Constant expressions/contextual typing outside that scope, conversion-operand context, overload resolution, remaining arithmetic rules beyond accepted integer division and rational addition, and detailed literal/sign grammar remain open. D05x settles compilation errors for evaluable constant arithmetic overflow and out-of-range explicit integer conversions; error representation/handling and analysis outside that scope remain open.

### D05s — Use an operand type covering both integer ranges: accepted

- Evidence: asked how different already-typed integer operands should combine for addition, subtraction, and multiplication, Davis selected **“Use an operand type that covers both ranges”** over requiring identical types or synthesizing the smallest common type.
- Use one operand’s type when its range includes both operand types’ entire ranges. Convert the other operand losslessly; this common type is also the result type. Identical types retain their type.
- Accepted examples: signed 7-bit with signed 16-bit uses `int[length=16]`; any fixed-width integer with growing `int` uses `int`. Signed 8-bit with unsigned 8-bit is a compile error unless explicitly converted, since neither range contains the other.
- This permits convenient widening and keeps results in an existing operand type, at the cost of requiring explicit conversions for incomparable ranges. It does not synthesize a signed 9-bit type for signed/unsigned 8-bit operands.
- Fixed-width results still report overflow; type selection does not add result bits to avoid overflow. D05t settles direct literals and D05u settles destination context for a single operation with a typed operand. D05v settles single operations between two direct literals. D05w settles nested addition/subtraction/multiplication typing. D05y–aj settle fractional integer `/`, its `float` result, quotient rounding, zero-result signs, and zero-divisor/overflow responses and constant-case timing. Remaining division operand/context/conversion rules, the precise upper rounding boundary, integer quotient/modulo, comparisons, and other operators remain open.

### D05t — Arithmetic literals use the typed operand’s type: accepted

- Evidence: asked whether a direct literal in integer addition, subtraction, or multiplication should use the typed operand’s type or default to growing `int`, Davis selected **“Use the typed operand’s type”**.
- With no outside expected result type, a direct literal takes the other operand’s integer type if it fits. Either operand order follows the same rule, and the result retains that type. A literal outside its range is a compile error.
- The accepted example pairs a `uint[length=8]` value with literal `1`: the result remains unsigned 8-bit, and adding 1 to a current value of 255 overflows. Literal `300` does not fit and is rejected during compilation.
- Chosen over giving the literal growing type `int` and widening the operation to `int`. This keeps fixed-width arithmetic bounded without repeating its type, at the cost of rejecting an oversized literal unless the programmer changes the operand type explicitly.
- D05u extends this typed-operand rule to single operations with an outside expected result type. D05v settles single operations between two direct literals. D05w settles nested addition/subtraction/multiplication typing. Other constant expressions and detailed literal/sign grammar remain open. D05x settles compilation errors for evaluable constant overflow wherever written; evaluation details/resources and analysis beyond D05x remain open.

### D05u — Compute arithmetic from operands, then convert the result: accepted

- Evidence: asked whether a wider expected result type should change computation for addition/subtraction/multiplication containing a typed operand, Davis selected **“Compute from operands, then convert the result”** over using a wider expected type for computation.
- For a single such operation, operand types and direct literals follow D05s–t regardless of an assignment, argument, or return’s expected result type. Compute first, then perform any permitted result conversion. An outside expected type does not resolve incompatible operands.
- The accepted example adds unsigned 8-bit values currently holding 200 and 100 for an unsigned 16-bit destination. It overflows in unsigned 8-bit; explicitly converting an operand to unsigned 16-bit first permits the result 300.
- This keeps arithmetic behavior stable when the destination changes, at the cost of explicit widening before calculations that exceed the operand type’s range.
- The question reserved two-literal and nested-expression rules for separate decisions. D05x settles compilation errors for evaluable constant overflow wherever written. Error handling and evaluation details/resources outside D05x remain open.

### D05v — Two-literal arithmetic uses expected type, otherwise int: accepted

- Evidence: asked whether an expected integer type should supply computation type for one addition/subtraction/multiplication directly between two literals, Davis selected **“Use the expected type, otherwise growing `int`”** over always computing in growing `int`.
- With an expected integer type, both direct literals and the result use that type. Each literal must fit or compilation fails; arithmetic still checks overflow. Without an expected integer type, operands and result use growing `int`.
- Accepted examples: adding literals 1 and 2 for a `uint[length=8]` destination works without an explicit conversion; adding literals 200 and 100 in that context overflows.
- This extends contextual typing to simple literal arithmetic and avoids explicit conversions for fixed-width constant calculations, at the cost of computation type depending on context when there is no typed operand.
- D05w settles nested arithmetic typing. D05x settles compilation errors for evaluable constant overflow wherever written; evaluation details/resources and analysis beyond D05x remain open. D05u’s operand-first rule for operations containing typed operands is unchanged.

### D05w — Recursively type literal-only arithmetic subexpressions: accepted

- Evidence: asked whether contextual typing should extend recursively through literal-only arithmetic subexpressions, Davis selected **“Recursively type literal-only subexpressions”** over typing inner expressions first.
- For nested addition, subtraction, and multiplication, a known integer type on one side supplies the type throughout a literal-only subtree on the other side. Adding a `uint[length=8]` value to the product of literals 2 and 3 computes that product and sum in unsigned 8-bit.
- A wholly literal arithmetic expression uses the expected integer type throughout, otherwise growing `int`. Each literal must fit and each intermediate operation checks overflow. With expected unsigned 8-bit, adding 200 and 100 before subtracting 100 still overflows.
- Subexpressions containing typed values compute independently from their operands. An outer expected type or a wider outer operation does not retroactively widen such a subexpression.
- This avoids repeated conversions in nested constants, at the cost of contextual typing reaching further into expressions. The rejected alternative would first give the inner literal product type `int`, causing addition of a fixed-width value to produce `int`.
- This concerns trees built from integer literals and these three operations, not arbitrary compile-time expressions. D05y–aj settle several integer division rules, and D05at settles exact rational addition. Contextual typing for other operators, named-constant contextual rules, conversion-operand context, detailed literal/sign grammar, and error timing outside the accepted constant-error rules remain open. D05x rejects evaluable constant overflow during compilation wherever written.

### D05x — Reject constant integer range failures wherever written: accepted

- Evidence: asked whether constant integer overflow and out-of-range conversions should be compilation errors even in never-executed ordinary code, Davis selected **“Reject during compilation, wherever written”** over reporting the error only if executed.
- Reject these failures during compilation when evaluable from integer literals, named compile-time integer constants, and built-in integer arithmetic/conversions, including inside unreachable branches.
- Accepted examples: converting literal 300 to `uint[length=8]`, or adding literals 200 and 100 with expected unsigned 8-bit type. Invalid type-width expressions still fail their required compile-time validation.
- This catches constant mistakes early, at the cost of requiring valid constant calculations in dead code. It does not require proving arbitrary facts about runtime inputs.
- This settles the constant-failure timing left open in earlier numeric decisions. Runtime-dependent failures still report errors; representation/handling, exact constant-expression rules/resource limits, and additional analysis of runtime-derived facts remain open.

### D05y — Fractional division for integer operands: accepted syntax and direction

- Evidence: asked whether `/` between integers should mean fractional division or an integer quotient, Davis selected **“Fractional division”**.
- `/` between integer operands produces a fraction-capable numeric result; `5 / 2` has value 2.5. Use a fraction-capable result type even when the quotient is mathematically whole.
- Chosen over an integer quotient such as 5 divided by 2 giving 2. This gives `/` familiar mathematical meaning, at the cost of introducing fractional numeric behavior and needing a separate integer-quotient operation.
- D05z selects binary64 for the result. Integer-quotient operation and spelling, negative quotient rounding, operand compatibility, contextual typing, conversions, and large-integer details remain open.

### D05z — Binary64 result for integer division: accepted representation

- Evidence: asked what numeric type `/` between integers should produce, Davis selected **“Binary64 floating-point”** over exact rational or decimal arithmetic.
- Use a 64-bit binary floating-point result even for whole quotients. `5 / 2` is exactly 2.5; `1 / 3` is approximated.
- Chosen for everyday speed and bounded result storage, at the cost of finite precision and range rather than exact fractions.
- D05ae settles ordinary finite rounding and D05ah extends nearest/ties-even through subnormals and eventual zero without underflow errors. D05aj names the type `float`. Other special-value rules, operand compatibility/contextual typing, and conversions remain open; D05af selects overflow errors, with the precise upper boundary still open. D05ad selects rounding the mathematical quotient once rather than first converting operands. This does not establish defaults for other fractional expressions.

### D05aa — Exact rational type in the standard library: accepted requirement

- Evidence: after selecting binary64 for integer division, Davis said **“I do want a type in a standard library for exact rational”**.
- Provide an exact rational-number type in the standard library alongside the binary64 integer-division result.
- This offers explicitly chosen exact fractions alongside fast default division, at the cost of another numeric API and arithmetic/resource rules. It does not change D05z.
- D05ak names the type `rational`. D05al permits growing numerator/denominator sizes. D05aq settles two-integer construction spelling/order. Imports, remaining construction details, storage layout and resource policy, remaining operators beyond exact rational + in D05at, remaining normalization details, comparisons, conversions, and errors remain open.

### D05ab — Integer fractional division by zero reports an error: accepted behavior

- Evidence: asked what integer `/` should do when the divisor is zero, Davis selected **“Report an error”** over producing infinity or NaN.
- Integer operands with a zero divisor fail: both `5 / 0` and `0 / 0` report an error.
- This catches invalid calculations at the operation instead of continuing with special values, at the cost of a failure path.
- D05ac settles constant-case compilation timing; error representation/handling remain open. Floating-point-operand division and rational-library errors remain separate decisions.

### D05ac — Constant integer division by zero fails compilation: accepted timing

- Evidence: asked whether constant integer division by zero should fail compilation even in unreachable code, Davis selected **“Reject during compilation, wherever written”** over errors only when executed.
- Reject integer `/` with a zero divisor when evaluable from integer literals, named compile-time integer constants, and built-in integer arithmetic/conversions, wherever written in ordinary code, including unreachable branches. Both `5 / 0` and `0 / 0` are examples.
- This catches invalid constant calculations early and follows D05x, at the cost of requiring valid constant calculations in dead code. It does not require proving arbitrary facts about runtime inputs.
- Runtime-dependent zero divisors retain D05ab’s error behavior. Required compile-time contexts need valid values. Exact constant-expression rules/resource limits, additional runtime-derived analysis, and error representation/handling remain open.

### D05ad — Round the integer quotient once: accepted computation model

- Evidence: asked whether integer `/` should round its mathematical quotient or first convert each operand to binary64, Davis selected **“Round the quotient once”**.
- For a nonzero divisor, define the result by the quotient of the exact integer operands, rounded once to binary64. Do not independently approximate the operands first.
- A huge nonzero integer divided by itself yields binary64 value 1 even when that operand exceeds binary64’s finite range, subject to computation resources.
- This preserves operand information until final rounding, at the cost of division support beyond converting operands and using hardware floating-point division. It mandates neither a rational-object allocation nor a particular algorithm.
- D05ae settles ordinary finite-result rounding and D05ah settles tiny results; the precise upper rounding boundary, resource exhaustion, operand compatibility/contextual typing, and conversions remain open.

### D05ae — Nearest, ties-to-even quotient rounding: accepted rule

- Evidence: asked how integer `/` should round a quotient not exactly representable in binary64, Davis selected **“Nearest, ties to even”** over nearest/ties-away and toward-zero alternatives.
- For ordinary finite binary64 results, round the exact mathematical quotient once to the nearest representable value. At an exact midpoint, choose the neighbor whose least significant stored significand bit is zero (even).
- This gives nearest-value accuracy and avoids consistently increasing magnitude on halfway cases, at the cost of a less intuitive tie rule.
- D05af selects overflow errors. D05ah settles tiny results. D05ai settles zero-result signs. The precise upper rounding boundary and rounding for other operations remain separate decisions.

### D05af — Overflow error for integer division results: accepted behavior

- Evidence: asked whether integer `/` overflowing its binary64 result should report an error or produce infinity, Davis selected **“Report an overflow error”**.
- Report overflow instead of signed infinity. An integer equal to 10 to the power 400 divided by 1 is an example.
- The error concerns the quotient, not operand magnitude: huge equal nonzero operands still yield 1 under D05ad, subject to resources.
- Chosen to catch out-of-range results instead of continuing with infinity, at the cost of a failure path.
- D05ag settles constant-case reporting timing. Precise upper rounding/overflow boundary, error representation/handling, and other operations remain open; D05ah settles tiny results and D05ai settles zero-result signs.

### D05ag — Constant division result overflow fails compilation: accepted timing

- Evidence: asked whether constant integer `/` result overflow should fail compilation wherever written, Davis selected **“Reject during compilation, wherever written”** over errors only if executed.
- Reject binary64-result overflow from integer `/` when evaluable from integer literals, named compile-time integer constants, and built-in integer arithmetic/conversions, including unreachable ordinary code.
- This follows D05x and D05ac and catches mistakes early, at the cost of requiring valid constant calculations in dead code. Arbitrary facts about runtime inputs need not be proved.
- Runtime-dependent overflow retains D05af’s error behavior; required compile-time contexts need valid values. Precise overflow boundary, exact constant-expression rules/resources, further runtime-derived analysis, and error representation/handling remain open.

### D05ah — Subnormal division results and eventual zero: accepted behavior

- Evidence: asked whether tiny integer `/` quotients should use subnormals and eventually round to zero or report an error below the normal range, Davis selected **“Use subnormals, then round to zero”**.
- Extend nearest, ties-to-even rounding of the exact quotient through binary64 subnormals down to zero. A sufficiently tiny nonzero quotient may round to zero. No underflow error is reported for these results, including in constant calculations.
- Chosen over errors below the smallest normal magnitude. This retains small values where possible and keeps calculations going, at the cost of reduced relative precision and potentially losing the nonzero result entirely.
- D05ai settles zero-result signs. Other operations, resource exhaustion, and general constant-evaluation details remain separate.

### D05ai — Preserve division signs at zero: accepted result rule

- Evidence: asked whether integer `/` should preserve a negative zero result or always use positive zero, Davis selected **“Preserve the division sign”**.
- A tiny negative quotient rounded to binary64 zero produces negative zero. For an exactly zero numerator, treat integer zero as positive for determining the division sign: `0 / -5` produces negative zero and `0 / 5` produces positive zero.
- Chosen over canonical positive-zero results to retain sign information, at the cost of two zero representations. Zero denominators still error under D05ab.
- Printing, comparisons, other floating-point operations, and sign-inspection facilities remain open.

### D05aj — Binary64 type name float: accepted spelling

- Evidence: asked what Tomato should call the binary64 type produced by integer `/`, Davis selected **`float`** over `float64`.
- Use the exact lowercase spelling `float` for this fixed-precision binary64 type. Unlike growing `int`, its precision and range are fixed.
- Chosen for a short everyday name, at the cost of not showing the 64-bit format in the spelling.
- Other floating types, floating literal defaults/grammar, and conversions or constructor-like calls remain open; D05ak names the rational type.

### D05ak — Standard-library type name rational: accepted spelling

- Evidence: asked what the standard-library exact rational type should be named, Davis selected **`rational`** over `fraction`.
- Use the exact lowercase spelling `rational`, choosing the explicit mathematical name over more everyday fraction wording.
- This names the type only; it does not choose module/import paths or automatic availability. D05al settles growing numeric range. D05aq settles two-integer construction spelling/order. Remaining construction details, storage layout and resource policy, remaining operators beyond exact rational + in D05at, remaining normalization details, comparisons, conversions, and errors remain open.
- Integer `/` still returns `float`; this naming decision does not change division semantics.

### D05al — Automatically growing rational range: accepted numeric policy

- Evidence: asked whether `rational` should support automatically growing numerator/denominator sizes like `int`, Davis selected **“Grow automatically, subject to resources”** over fixed-size limits.
- Support exact ratios of integers without a fixed bit-width ceiling on numerator or denominator, growing automatically as needed subject to available resources.
- This permits very large exact fractions and matches growing `int`, at the cost of increasing storage and arithmetic work. It selects numeric range rather than physical layout.
- D05am selects automatic reduction to lowest terms. Remaining normalization details, intermediate arithmetic, resource-exhaustion behavior, remaining construction details (spelling/order in D05aq), and optional alternative rational types remain open.

### D05am — Automatic rational reduction: accepted normalization requirement

- Evidence: while discussing growing numerator/denominator sizes, Davis said **“well automatically reduce them”**.
- Automatically reduce `rational` fractions to lowest terms by cancelling common factors, without a separate manual simplification request. For example, six eighths becomes three quarters.
- This applies to values produced by construction or supported arithmetic without choosing the APIs/operators. It keeps fractions simplified at the cost of reduction work.
- D05an selects positive denominators and canonical zero. D05ao selects an error for zero-denominator construction. Physical storage and internal reduction strategy/timing and remaining arithmetic API beyond exact rational + in D05at remain open.

### D05an — Positive rational denominators: accepted normalization rule

- Evidence: asked whether reduced `rational` values should always have positive denominators, Davis selected **“Always use a positive denominator”** over allowing either sign.
- Put negative signs in the numerator. Six over negative eight reduces to negative three over positive four; negative six over negative eight reduces to positive three over positive four.
- With D05am, zero has fraction form 0 over 1. This gives one reduced mathematical fraction form per value instead of preserving denominator-sign arrangements.
- D05ao selects an error for zero-denominator construction. D05aq settles two-integer construction spelling/order. Physical storage, printed syntax, remaining construction details, and APIs remain open.

### D05ao — Zero-denominator rational construction errors: accepted behavior

- Evidence: asked what should happen when code tries to create a `rational` with denominator zero, Davis selected **“Report an error”** over adding infinity and NaN values.
- Both nonzero over zero and zero over zero report an error rather than producing infinity or NaN. This keeps valid `rational` values finite exact fractions, at the cost of a failure path.
- D05ap settles constant-case compilation timing. D05aq settles two-integer construction spelling/order. Remaining construction details, error representation/handling, and remaining rational arithmetic operators beyond exact + in D05at remain open.

### D05ap — Constant rational zero denominators: accepted compilation error

- Evidence: asked whether a constant zero denominator in rational construction should fail compilation wherever written, Davis selected **“Reject during compilation, wherever written”**. His lead relayed the same confirmed answer to the duplicate question; it is one decision, not a separate lead-selected rule.
- Reject such construction during compilation, including unreachable ordinary code, when the denominator is evaluable from integer literals, named compile-time integer constants, and built-in integer arithmetic/conversions. Both zero and nonzero numerators are covered.
- Do not require proving arbitrary facts about runtime inputs. Chosen over reporting the error only if executed to catch constant mistakes early, at the cost of requiring valid constant constructions in unused branches.
- D05aq settles two-integer construction spelling/order. Remaining construction details, error representation/handling, detailed constant-evaluation rules/resource limits, and remaining rational arithmetic operators beyond exact + in D05at remain open.

### D05aq — Rational type-call construction: accepted spelling and order

- Evidence: asked how code should create a rational from a numerator and denominator, Davis chose **“`rational(3, 4)`”** over `make_rational(3, 4)`.
- Use `rational(numerator, denominator)`: numerator first, denominator second. `rational(3, 4)` creates three quarters, subject to D05am–ap normalization and zero-denominator rules.
- The short spelling resembles the type-call shape already chosen for integer conversions, at the cost of type calls serving both construction and conversion.
- D05ar–as settle the integer-only boundary and independent integer input types. Imports/availability, literal context, named arguments, defaults, other construction/conversion forms, general call grammar, and class construction remain open.

### D05ar — Integer-only rational arguments: accepted argument-kind boundary

- Evidence: asked whether both arguments to `rational(numerator, denominator)` should accept only integers, Davis chose **“Accept only integers”** over also accepting finite whole-valued floats.
- Both arguments must be integers. Reject a `float` argument during compilation even if its current value is a whole number.
- This keeps construction exact without implicit float-to-integer conversion, at the cost of needing a separately chosen explicit facility to convert a float. No such facility or behavior is chosen here.
- D05as accepts integer argument types independently without narrowing or wrapping. Literal context and other construction/conversion forms remain open.

### D05as — Independent rational integer inputs: accepted compatibility rule

- Evidence: asked whether rational numerator and denominator may use different integer types, Davis chose **“Accept any integer type independently”** over requiring matching integer types.
- Each already-typed input may independently be growing `int`, signed fixed-width, or unsigned fixed-width. Types need not match: a signed 8-bit numerator and unsigned 16-bit denominator are allowed together.
- Preserve both exact values without narrowing or wrapping before construction. D05am–ap normalization and zero-denominator rules remain applicable.
- This avoids extra conversions and fits growing rational range, at the cost of supporting multiple integer input types. It does not mandate a conversion implementation. Literal contextual typing, general mixed arithmetic, and other conversion facilities remain open.

### D05at — Exact rational addition: accepted operator and result rule

- Evidence: asked whether `+` should add two rational values exactly and return another rational, Davis chose **“Use `+` for exact rational addition”** over a named library operation.
- For two rational operands, compute the exact mathematical sum and return a rational, subject to resources. One third plus one sixth gives one half, with D05am–an normalization and no float rounding.
- Familiar arithmetic syntax requires operator support for the standard-library type. Mixed operands, other operators, resource-exhaustion behavior, and implementation strategy remain open. D12j–l separately require custom-class +, select @add as a marker above an ordinary method, and use the left operand as its instance receiver with the right operand as its one other operand argument. Further signature/dispatch rules remain open.

### D12j — Custom-class operators using @add: accepted capability and spelling direction

- Evidence: Davis said **“yes add ways for custom classes to use + and stuff using @add”**.
- Channel: the source channel of this quote was not recorded in this log, so it is not known whether it came through the authenticated byre task or shared-password web chat; Davis re-confirmed this in the authenticated byre task on 2026-11-08, ticking “Confirm D12j (`@add`)” and “Confirm D12m (`@init`)” in answer to “Do you confirm D12j (@add) and D12m (@init) as your decisions?”
- Support custom classes using `+`, with the requested spelling `@add` for addition customization. Other operator customization is requested direction, but the operator list and other spellings remain unchosen.
- This enables arithmetic-style syntax for programmer-defined classes at the cost of explicit operator-definition and dispatch rules.
- D12k selects `@add` as a marker above an ordinary method; D12l selects the left instance receiver/right operand argument shape. Remaining signature rules, operand/result types, dispatch, inheritance, other operators, errors, and broader annotation grammar remain open. No general-purpose decorator or Python special-method behavior is inherited.

### D12k — @add above an ordinary method: accepted marker role

- Evidence: asked whether `@add` marks an ordinary method or is the special method’s name, Davis chose **“Marker above an ordinary method”**.
- Place `@add` above an ordinary method with a programmer-chosen name. The marker designates that method as the implementation of `+` for a custom class; the method is not specially named `@add`.
- This permits descriptive method names but adds a separate marker-to-operator relationship. It does not introduce general-purpose decorators.
- D12l selects the logical receiver and operand shape. Receiver spelling, operand/result types, dispatch, inheritance, ordinary method-call details, precise surrounding grammar, and other operator markers remain open.

### D12l — Left operand as @add receiver: accepted method shape

- Evidence: asked whether the @add method should use the left operand as receiver and take the right operand as its argument, Davis chose **“Left operand is the instance receiver”** over a class-associated method taking both operands explicitly.
- For `a + b`, invoke the marked instance method on `a`, passing `b` as its one other operand argument.
- This attaches addition behavior to the left object without passing it twice. The choice specifies logical receiver/operand shape only; receiver source spelling and declaration grammar remain open.
- Operand/return types, method lookup and inheritance, mixed-type selection, right-side fallback, mutation, and ordinary method-call details remain open.

### D12m — @init initialization marker: accepted role and spelling

- Evidence: while asked whether fields should be declared in the class body or inferred from initialization assignments, Davis answered **“@init marks the init function”** rather than choosing either field option.
- Channel: the source channel of this quote was not recorded in this log, so it is not known whether it came through the authenticated byre task or shared-password web chat; Davis re-confirmed this in the authenticated byre task on 2026-11-08, ticking “Confirm D12j (`@add`)” and “Confirm D12m (`@init`)” in answer to “Do you confirm D12j (@add) and D12m (@init) as your decisions?”
- Identify a class’s initialization function using the marker `@init`. This is a direct requested design choice, not an endorsement of a field-introduction policy.
- The marker gives initialization an explicit role; alternatives to its spelling were not presented or selected. Exact placement/grammar, signature/receiver, instance-versus-factory behavior, allocation, return values, invocation/construction syntax, inheritance, and errors remain open.
- D12n later accepts a class-body typed private-field form; D12u later requires every instance field to be declared in the class body; D12v requires every declaration to give its type. This does not introduce general-purpose decorators or inherit Python initializer behavior.

### D12n — private name: Type: accepted class-body field form

- Identity note: the evidence came through shared-password web chat with no per-person identity; Davis re-confirmed this in the authenticated byre task on 2026-11-08, ticking “Confirm D12n–o” and “Confirm D12p–q as `def private x`” (including the readings of “unit” as “init” and “Def private x” as lowercase) in answer to “Do you confirm the earlier chat-sourced decisions D12n–q and the D02b slowdown reading?”
- Evidence: clarifying his earlier description of fields “on the class but for the struct”, Davis wrote in private web chat **“What I meen is you do private x: int[length=8]”**.
- Support class-body declarations `private name: Type`, including that exact example: private modifier, field name, colon, explicit type. This makes the requested declaration form visible without importing Python storage behavior.
- D12r excludes direct subclass access. The remaining private-access boundary, initialization, other declaration forms, and surrounding class grammar remain open. D12t later settles per-instance storage and D12u requires every field to be declared; shared-field syntax remains open. This does not require all fields to be private; D12v requires every declaration to give its type. No separate struct type is selected. Alternatives to this requested spelling were not selected.

### D12o — const fields after initialization: accepted restriction

- Identity note: the evidence came through shared-password web chat with no per-person identity; Davis re-confirmed this in the authenticated byre task on 2026-11-08, ticking “Confirm D12n–o” and “Confirm D12p–q as `def private x`” (including the readings of “unit” as “init” and “Def private x” as lowercase) in answer to “Do you confirm the earlier chat-sourced decisions D12n–q and the D02b slowdown reading?”
- The reading of “unit” as “init” was explicitly confirmed with D12o in the answer to that question.
- Evidence: Davis added in private web chat **“You can also add const and then after unit it can not be changed”**. The reply explicitly interpreted “unit” as “init” in this initialization discussion.
- Provide `const` as a field modifier: after initialization, the marked field cannot be changed. This is a direct request, without selection of an alternative spelling.
- D12y settles `private const` order and D12z lets `@init` set a const field once; other modifier placement, exact write checking, const fields that also have declared values, default mutability, inheritance, and error reporting remain open. D12s later settles binding-only const: referenced objects stay changeable. Compile-time constant evaluation is not implied.

### D12p — def methods with optional private: accepted declaration direction

- Identity note: the evidence came through shared-password web chat with no per-person identity; Davis re-confirmed this in the authenticated byre task on 2026-11-08, ticking “Confirm D12n–o” and “Confirm D12p–q as `def private x`” (including the readings of “unit” as “init” and “Def private x” as lowercase) in answer to “Do you confirm the earlier chat-sourced decisions D12n–q and the D02b slowdown reading?”
- Evidence: Davis wrote in private web chat **“Yes method are just define with def you can add private”**.
- Use `def` to define class methods and permit a `private` modifier on a method. Alternatives to those spellings were not presented; this is a direct requested choice.
- D12q settles private after def and before the method name. Other modifier ordering, receiver/parameter/return syntax and annotations, method bodies and broader grammar, remaining private access (D12r excludes direct subclass access), dispatch, and inheritance interactions remain open. No Python method behavior is imported.

### D12q — def private name: accepted private-method prefix order

- Identity note: the evidence came through shared-password web chat with no per-person identity; Davis re-confirmed this in the authenticated byre task on 2026-11-08, ticking “Confirm D12n–o” and “Confirm D12p–q as `def private x`” (including the readings of “unit” as “init” and “Def private x” as lowercase) in answer to “Do you confirm the earlier chat-sourced decisions D12n–q and the D02b slowdown reading?”
- D12q is the agent’s reading of the capitalized chat text “Def private x” as lowercase `def private x`; Davis confirmed this reading in the authenticated byre task on 2026-11-08.
- Evidence: following def/optional-private discussion, Davis wrote in private web chat **“Def private x”**. The reply recorded the order as `def private x`, retaining the lowercase keyword already chosen in D12p rather than treating sentence capitalization as a keyword change.
- Put private after def and before the method name: `def private name`. This accepts the prefix order, not a complete method declaration. Alternatives to the order were not selected.
- Receiver/parameter/return syntax and annotations, parentheses/punctuation, other modifiers, bodies/grammar, and remaining private-access rules remain open; D12r excludes direct subclass access.

### D12r — no direct subclass access to parent private members: accepted

- Evidence: Davis selected **“No direct access from subclass methods”** on November 8, 2026 Pacific (November 9 UTC), answering whether subclass-defined methods may directly access parent private fields/methods.
- A method defined in a subclass cannot directly read/write the parent’s private fields or call its private methods. Use accessible parent methods instead.
- Chosen over allowing direct subclass access. This hides parent internals and reduces coupling, at the cost of potentially adding accessible parent methods for subclass use.
- lookup/overriding, and error details remain open. This does not prevent inherited parent-defined methods from performing their own work; their full access model remains to be specified.
- Open interaction for Davis: how this rule applies to parent fields inherited under D12b (whether they count as declared by the parent’s body or must be redeclared in a subclass) is undecided. See D12u.

### D12s — const fixes the field binding without freezing its object: accepted

- Evidence: Davis selected **“Keep the object changeable”** when asked whether an object held by a const field should still be changeable through that field.
- After initialization, a const field cannot be replaced with a different object, but accessible mutable fields and methods on the held object still work through it. Const does not freeze that object or nested objects.
- Chosen over read-only access through the const field. This keeps shared-object behavior simple, at the cost of const not guaranteeing an unchanging object. An illustrative const owner field may keep the same Person while that Person’s mutable name changes; no new syntax is selected by these names.
- D12y settles `private const` order and D12z lets `@init` set a const field once; other modifier placement, exact write checking, const fields that also have declared values, default mutability, inheritance, and errors remain open. No compile-time evaluation is implied.

### D12t — class-body fields belong to each instance: accepted

- Evidence: Davis selected **“A separate field in each instance”** when asked whether a field declared in a class body belongs separately to each instance.
- A class-body field such as `private x: int[length=8]` is stored per instance: each instance holds its own `x`, and changing one instance’s `x` does not change another’s.
- Chosen over one field shared by the class. Shared fields would need a separate later design.
- D12u later requires every field to be declared and D12v requires its type; initialization and defaults, shared-field syntax, other modifier placement, inheritance, and errors remain open.

### D12u — every instance field must be declared in the class body: accepted

- Evidence: Davis selected **“Yes, every field must be declared”** when asked whether every instance field must be declared in the class body.
- Reading or writing an undeclared field is a compile error; assignment in `@init` does not create fields. The class body lists every field. Open interaction for Davis: D12b lets a class inherit a parent’s fields, so whether an inherited field counts as declared by the parent’s body (versus being redeclared in the subclass) is not decided.
- Chosen over letting the first `@init` assignment declare a field and infer its type. This costs a little repetition for fields obvious from `@init`.
- D12v later requires every declaration to give its type. Initialization and defaults, `@init` write checks, and other modifier placement remain open. The `self.count = 0` example was illustrative, not syntax.

### D12v — field declarations always give the type: accepted

- Evidence: Davis selected **“Yes, always write the type”** when asked whether a class-body field declaration must always give its type.
- Every class-body field declaration names its type, as in `private x: int[length=8]`; types are not inferred from initial values.
- Chosen over inferring the type from an initial value, which would be shorter but make types less visible and depend on undecided initial-value syntax.
- Initialization values and defaults, `@init` write checks, shared-field syntax, and other modifier placement remain open.

### D12w — field declarations may give an initial value: accepted

- Evidence: Davis selected **“Yes, a declaration may give an initial value”** when asked whether a class-body field declaration may give an initial value.
- A new instance starts with that value for the field unless `@init` changes it. A field declared without a value must be set by `@init`; how that is checked is not decided.
- Chosen over allowing values only through `@init`, which keeps all starting values in one place at the cost of more `@init` code.
- The example `private x: int[length=8] = 0` is illustrative, not accepted syntax. Value syntax, evaluation time/order, whether arbitrary expressions are allowed, `@init` write checks, shared-field syntax, and other modifier placement remain open.

### D12x — fields without a value must be set by @init: accepted

- Evidence: Davis selected **“Yes, the compiler checks that @init sets it”** when asked whether a field declared without an initial value must be set by `@init`.
- The compiler checks that `@init` sets every declared field whose declaration gives no value. There are no hidden type-default values.
- Chosen over giving such fields a default value for their type, which needs a default for every type and can hide a forgotten assignment.
- Exact checking rules (paths, branches, reads before setting, error wording), value syntax and evaluation order, shared-field syntax, and other modifier placement remain open.

### D12y — field modifier order is private const: accepted

- Evidence: Davis selected **“`private const x: int[length=8]`”** when asked in what order `const` and `private` are written on a field.
- With both modifiers, `private` comes before `const`: `private const x: int[length=8]`. `const private` is not accepted.
- Chosen over const-first and over accepting either order, which would give two spellings for one meaning. This matches the `def private name` style of D12q.
- Other modifiers (D12aa makes members public unless marked `private`), value syntax, and shared-field syntax remain open.

### D12z — @init may set a const field once: accepted

- Evidence: Davis selected **“Yes, `@init` may set it once”** when asked whether `@init` may assign a `const` field. The chosen option read: “`@init` is the one place a const field may be assigned, and only once on every path through `@init`.”
- `@init` is where a const field may be assigned, once on every path through `@init`; afterward the field cannot change. A const field with no declared value must be set there (D12x).
- Chosen over requiring const fields to have a declared value, which is simpler but stops a const field from depending on `@init` arguments.
- Exact once-only checking (branches, loops, reads before setting, error wording), const fields that also have a declared value, inheritance, and other writers remain open.

### D12aa — members are public unless marked private: accepted

- Evidence: Davis selected **“Public unless marked `private`”** when asked whether a field or method is private unless it says otherwise, or public unless it says private.
- A field or method with no visibility modifier is reachable from other code; `private` hides it. No `public` keyword is introduced. D12r still hides parent private members from subclass methods.
- Chosen over private-by-default, which is safer but needs another modifier spelled now.
- other visibility modifiers, and errors remain open.

### D12ab — methods may use other instances' private members of the same class: accepted

- Evidence: Davis selected **“Yes, within the same class”** when asked whether a method of a class can use another instance's `private` fields of the same class.
- A method of a class may read or write a private field, or call a private method, of any instance of that class, including one other than the receiver. This does not extend to subclass methods (D12r) or code outside the class.
- Chosen over receiver-only private access, which hides more but needs extra accessor methods for simple comparisons.
- Nested or related classes, and errors remain open.

### D12ac — private means inside the class only: accepted

- Evidence: Davis selected **“No, private means inside the class only”** when asked whether code outside a class, in the same module, can use its `private` members.
- A private member is usable only by methods of its own class. Same-module functions and other classes, and subclass methods, use accessible members instead. No module or friend access exists.
- Chosen over same-module access, which is more convenient for helpers next to the class but hides less and needs a precise module definition first.
- Nested or related classes, and errors remain open.

### D12ad — no protected level: accepted

- Evidence: Davis selected **“No, parents expose public methods instead”** when asked whether a class should have a way to share a member with its subclasses.
- There is no `protected` modifier. Members are public unless marked `private`; a parent that wants subclasses to use something makes it public.
- Chosen over adding `protected`, which gives three levels but adds learning and specification cost, including its interaction with inherited fields.
- Nested or related classes and errors remain open.

### D12ae — instances are created by calling the class name: accepted

- Evidence: Davis selected **“Call the class name with arguments”** when asked how a new instance of a class is created.
- Calling the class name with arguments (the illustrative `Point(1, 2)`) allocates a new instance and runs `@init` with those arguments. There is no separate creation keyword.
- Chosen over a creation word such as `new`, which makes creation visible but adds a keyword and a second call style next to `rational(1, 2)`.
- `@init`'s signature, receiver spelling and return value, calls through a parent class, argument defaults or overloading, and errors remain open. This does not make type-call conversion and class construction one feature.

### D12af — a class without @init is callable when every field has a value: accepted

- Evidence: Davis selected **“Allowed when every field has a declared value”** when asked what a call does for a class without `@init`.
- Such a class is called with no arguments and gets its declared values; if any field lacks a declared value the class is a compile error (D12x). No empty `@init` is needed.
- Chosen over requiring every class to have `@init`, which gives one rule but adds boilerplate to simple classes.
- Calls through a parent class, argument defaults or overloading, `@init`'s signature, receiver and return value, and error wording remain open. `Counter()` is illustrative, not accepted syntax.

### D12ag — a subclass @init must explicitly call the parent's @init: accepted

- Evidence: Davis selected **“The subclass `@init` must explicitly call the parent's `@init`”** when asked how a subclass passes arguments up to its parent's `@init`.
- The parent's initialization runs only where the subclass's `@init` calls it, with the arguments the subclass chooses; the compiler checks that the call happens exactly once. Nothing runs the parent's `@init` automatically.
- Chosen over running the parent's `@init` automatically first with no arguments, which is shorter but cannot initialize a parent that needs arguments.
- Error wording remains open; D12ao settles the call spelling and D12ap the ordering, which also settles reads of subclass fields before the call.

### D12ah — a subclass of a class with @init must write its own @init: accepted

- Evidence: Davis selected **“Not allowed: the subclass must write its own `@init`”** when asked what happens when a subclass with no `@init` is called and its parent has one.
- Calling such a subclass is a compile error. The subclass's `@init` calls the parent's (D12ag); the parent's `@init` is not reused or forwarded. A subclass of a parent without `@init` follows D12af.
- Chosen over letting the subclass reuse the parent's `@init`, which is convenient but needs extra rules for the subclass's own fields.
- The call's spelling, ordering, and error wording remain open.

### D12ai — the @init method's name is chosen by the programmer: accepted

- Evidence: Davis selected **“The programmer chooses the name”** when asked whether the `@init` method has a fixed name or one the programmer chooses.
- `@init` marks an ordinary method with a programmer-chosen name, consistent with `@add` (D12k); no method name is reserved. The example `@init` above `def start(self, size: int)` is illustrative, not accepted syntax.
- Chosen over a fixed `init` name, which is simple to refer to but reserves a name and makes the marker redundant.
- The spelling of the subclass's call to the parent's `@init`, receiver and signature, return value, and errors remain open.

### D12aj — a class has at most one @init: accepted

- Evidence: Davis selected **“No, at most one `@init` per class”** when asked whether a class may have more than one `@init` method.
- Calling the class name always means that one method; a second `@init` in a class is a compile error.
- Chosen over several `@init` methods, which are more flexible but need overload or naming rules.
- Other ways to offer several creation styles need a separate design. The `@init` receiver and signature, return value, and errors remain open.

### D12ak — methods take an explicit first parameter named self: accepted

- Evidence: Davis selected **“An explicit first parameter named `self`”** when asked how a method refers to the object it is running on.
- A method names its instance through an explicit first parameter `self`, as in the illustrative `def area(self)`; the receiver is not an implicit built-in name.
- Chosen over an implicit built-in name such as `this`, which shortens signatures but hides the receiver and reserves a name.
- the rest of the parameter and return syntax, and calling syntax remain open.

### D12al — self has no written type: accepted

- Evidence: Davis selected **“No, `self`'s type is implied by the class”** when asked whether `self` is written with a type annotation in a method.
- Inside a class, `self` is written without a type; its type is the enclosing class. This is a stated exception to D04b's explicit parameter types, for the receiver only.
- Chosen over always writing the type, which is uniform with other parameters but repeats the class name in every method.
- the other parameters' and return syntax, calling syntax, and how `self` is typed in an inherited method remain open.

### D12am — methods are called with a dot on the instance: accepted

- Evidence: Davis selected **“Dot call on the instance, without writing `self`”** when asked how a method is called on an instance.
- A method is called as `instance.method(arguments)` (the illustrative `c.area()`); the instance before the dot becomes `self`, and the call does not write it.
- Chosen over passing the instance as an ordinary first argument, which needs no special call syntax but reads inside-out for chained calls.
- calls through a parent class, and error wording remain open.

### D12an — fields are accessed with a dot, self.x inside methods: accepted

- Evidence: Davis selected **“Yes, always `self.x`”** when asked whether a field must be written as `self.x` inside a method.
- A field is accessed with a dot on an instance (the illustrative `c.x`, subject to `private`); inside a method, the receiver's field is always `self.x`, and a bare `x` never means a field.
- Chosen over letting a bare `x` find the field, which is shorter but needs shadowing rules when a local has the same name.
- Shadowing rules for locals and error wording remain open.

### D12ao — the parent's @init is called by naming the parent class and passing self: accepted

- Evidence: Davis selected **“Name the parent class and pass `self`”** when asked how the parent's `@init` is called from a subclass `@init`.
- A subclass `@init` writes the parent class name, a dot, the parent's `@init` name, and `self` as the first argument (the illustrative `Shape.start(self, name)`). No `super` keyword is introduced.
- Chosen over a built-in `super`, which is shorter but adds a reserved word and needs a rule for longer parent chains.
- This is the only accepted class-qualified call form so far (D12am's ordinary form is the dot call on an instance). Whether it may call other methods, longer parent chains, ordering, reads before the call, and error wording remain open.

### D12ap — the parent @init call is the first statement: accepted

- Evidence: Davis selected **“It must be the first statement”** when asked whether the call to the parent's `@init` must be the first statement in a subclass `@init`.
- The call comes before any other statement, so the parent part is set up before subclass code runs and subclass code can rely on parent fields. A parent argument can be computed inline in the call, not by earlier statements.
- Chosen over allowing the call anywhere exactly once, which allows code before the call but needs a rule against reading parent fields not yet set.
- Argument expression limits, what counts as a statement, longer parent chains, and error wording remain open.

### D12aq — a def without self is a class function: accepted

- Evidence: Davis selected **“A function that belongs to the class, with no instance”** when asked what a `def` inside a class without `self` means.
- It is called through the class name (the illustrative `Circle.unit()`), cannot use `self` or instance fields, may use private members of instances it is given (D12ab), and may be marked `private`.
- Chosen over disallowing it, which is simplest but stops helpers that need private access from living beside the class.
- Whether class functions are inherited or replaced by subclasses, how a call through a subclass name resolves, whether `@init` may be one, and error wording remain open.

### D12ar — a subclass marks a method that replaces a parent method: accepted

- Evidence: Davis selected **“Mark the replacing method”** when asked how a subclass replaces a parent method.
- A replacing method carries a marker in the style of `@add` and `@init`. A marked method that replaces nothing, or an unmarked method that would replace, is a compile error.
- Chosen over letting a matching name replace silently, which writes less but turns a misspelled name into a new method without warning.
- D12as later spells the marker as the keyword `override`. and error wording remain open.

### D12as — the replacing-method marker is the keyword override: accepted

- Evidence: Davis answered **“Override keyword”**, outside the offered options (`@override`, `@replace`, another spelling), when asked how the replacing-method marker is spelled.
- The marker required by D12ar is the keyword `override`, not an `@` marker. `@add` and `@init` are unchanged.
- Reading: “keyword” is taken to mean `override` is written as a keyword, not `@override`; Davis can correct this if he meant the `@` form.
- D12at places it before `def`. Whether it is reserved everywhere and error wording remain open.

### D12at — override goes before def: accepted

- Evidence: Davis selected **“Before `def`: `override def private area(self)`”** when asked where `override` goes relative to `def` and `private`.
- `override` leads the declaration, before `def`; `private` stays after `def` (D12q). The example is illustrative.
- Chosen over putting `override` after `def` with the other modifiers, which keeps modifiers together but needs an order rule between `override` and `private`.
- Whether `override` is reserved everywhere, whether it combines with `@add` or `@init`, and error wording remain open.

### D12au — a replacing method must match name and types exactly: accepted

- Evidence: Davis selected **“Same name and exactly the same parameter and return types”** when asked which methods count as a match when a subclass replaces a parent method.
- An `override` method matches only with the parent's name and exactly the same parameter and return types; otherwise it is a compile error. No compatible-signature or variance rules.
- Chosen over compatible signatures, which are more flexible but need type-compatibility rules first.
- Whether parameter names take part, and error wording remain open.

### D12av — a replacing method calls the parent's version the same way: accepted

- Evidence: Davis selected **“Same form as the `@init` call: name the parent class and pass `self`”** when asked how a replacing method calls the parent's version of itself.
- Inside an `override` method, the parent's version is called as `ParentClass.name(self, args)` (illustrative `Shape.area(self)`). No `super` keyword. Unlike the `@init` call (D12ap), the call has no required position.
- Chosen over giving no way to call the replaced version, which is smallest but forces a helper method for any extension of parent behavior.
- Longer parent chains, calling a method the parent itself inherited, whether any instance method may be called this way, and error wording remain open.

### D12aw — only instance methods with self can be replaced: accepted

- Evidence: Davis selected **“No, only instance methods with `self` can be replaced”** when asked whether `@init` or a class function may be replaced with `override`.
- `override` applies only to instance methods that take `self`. `@init` is never replaced (D12ah); class functions (D12aq) are not replaced. A subclass class function with the same name as a parent's is a separate function (stated in the chosen option's description).
- Chosen over also allowing class-function replacement, which needs rules for how a call through a subclass name resolves.
- How a same-named class function resolves through each class name, and error wording, remain open.

### D12ax — the subclass's replacing method runs, chosen at run time: accepted

- Evidence: Davis selected **“The subclass's version runs, chosen when the program runs”** when asked which version of a method runs when a `Shape` variable holds a `Circle`.
- A dot-form call on an object runs the replacing method of the object's actual class, chosen at run time. Class-qualified calls (D12ao, D12av) name their class and skip this lookup.
- The question assumed a parent-typed variable can refer to a subclass instance. D12ay later accepts that assumption.
- Chosen over compile-time choice from the declared type, which is faster but makes replacement work only when called through the subclass type. Cost: a small lookup per call.
- Interface-typed values are settled by D12bb; error wording remains open.

### D12ay — a subclass instance can be used wherever its parent type is expected: accepted

- Evidence: Davis selected **“Yes, a subclass instance can be used wherever its parent type is expected”** when asked whether a variable or parameter typed as a parent class can hold a subclass instance.
- A subclass value can be assigned, passed or returned where the parent class type is written (the illustrative `s: Shape = Circle(2.0)`). The reverse stays an error without the explicit conversion of D12az.
- Chosen over exact-class variables, which are simplest but make replaced methods unreachable through the parent type. This settles the assumption under D12ax.
- Interface types, containers of subclass instances, and error wording remain open.

### D12az — a parent value can be converted to a subclass with a checked type-call: accepted

- Evidence: Davis selected **“Yes, with an explicit type-call that fails if the object isn't a `Circle`”** when asked whether a `Shape` value can be converted to a `Circle` when it really is one.
- `Circle(s)` (illustrative) converts a parent-typed `s` to `Circle`, and fails with an error when the object isn't a `Circle`.
- The question stated that this resembles creating a new `Circle` by calling the class name (D12ae); D12ba later resolves the overlap.
- Chosen over no conversion, which has no failing conversion but leaves subclass-only members unreachable from parent-typed values.
- The failure error's form, conversions to interface types, and conversions between unrelated classes remain open.

### D12ba — the compiler rejects a class whose call is ambiguous: accepted

- Evidence: Davis selected **“The compiler rejects the ambiguous class”** when asked which `Circle(x)` means when it could be creation or conversion.
- A class whose `@init` takes a single parameter that accepts a value of its parent type, or of its own type, is a compile error. A call `Circle(x)` therefore never means both. Copying an instance needs a differently named method.
- Chosen over letting creation win when `@init` accepts the argument, which allows copy-style `@init` but lets an `@init` parameter change silently change what existing calls mean.
- The exact set of rejected parameter types (for example, types between the class and its ancestors, or interface types) and error wording remain open.

### D12bb — an instance can be used where an interface it implements is expected: accepted

- Evidence: Davis selected **“Yes, any instance of an implementing class fits the interface type”** when asked whether an instance can be used where an interface it implements is expected. The question had been withdrawn when he moved the task; he answered it afterward, and that answer replaces the earlier cancellation. He added that no further questions should be asked.
- An interface can be a variable, parameter or return type, and any instance of a class that explicitly implements it fits. Dot-form calls dispatch to the actual class's method at run time (D12ax), as for parent classes (D12ay).
- Chosen over declaration-only interfaces, which are simplest but would not let different classes be used the same way.
- Interface-to-class conversion, interface inheritance, generic or container interface types, and error wording remain open.

### D12bc — an interface can extend one or more interfaces: accepted

- Evidence: Davis selected **“Yes, an interface can extend one or more interfaces”** when asked whether an interface can extend another interface.
- An interface may name one or more parent interfaces. A class implementing the child must provide every parent's methods, and its instances fit the child type and each parent type (D12bb).
- Chosen over a single parent only and over no interface inheritance; the latter would force classes to list every interface by hand.
- Overlapping requirements between parents, cycles, and error wording remain open.

### D12bd — one method can satisfy overlapping interface requirements: accepted

- Evidence: Davis selected **“Yes, one method satisfies both”** when asked whether one class can implement, or one interface extend, two interfaces that require a method with the same name and signature.
- A single method in the class satisfies both requirements. The same name with a different signature is an error.
- Chosen over rejecting all overlap and over requiring the method to be restated.
- Cycles and error wording remain open.

### D12be — interface inheritance cannot form a cycle: accepted

- Evidence: Davis selected **“No, a cycle is an error”** when asked whether an interface can extend itself through a cycle (A extends B, B extends A).
- An interface may not extend itself, directly or through other interfaces.
- Chosen over allowing cycles whose members require the union of methods.
- Error wording remains open.

### D12bf — subclasses inherit implemented interfaces: accepted

- Evidence: Davis selected **“Yes, subclasses inherit the interface”** when asked whether each subclass of a class that implements an interface also counts as implementing it.
- No further declaration is needed, and subclass instances fit the interface type (D12bb). A replacing method must still fit the interface.
- Chosen over requiring each subclass to redeclare the interface.
- Error wording remains open.

### D12bg — a method fits an interface requirement by exact types: accepted

- Evidence: Davis selected **“Same parameter types and same return type”** when asked how closely a class's method must match an interface's method requirement.
- Parameter types and return type must be exactly those of the requirement. Parameter names need not match.
- Chosen over also requiring matching names, and over accepting broader parameters and narrower return types, which would need a defined relation between types.
- Error wording remains open.

### D16a — no top-level code; `@main` is the default entry point: accepted

- Evidence: Davis wrote “remember no top level code only@main as entry points”, then “@x as entry point”, then “but @main is default if not specified”. These were chat messages, not a choice from options.
- Files hold only declarations. A top-level function marked `@name` is an entry point; with none chosen, `@main` runs. The prototype runs a chosen one with `--entry name`.
- This is one reading of three short messages. The alternative, that only `@main` exists, is covered by the same rule with a single entry point.
- Open: entry-point arguments, return value or exit status, several functions with one marker, a program with no `@main`, how an entry is chosen outside the prototype, module-level constants or variables, and error wording.

### D17a — string literals use `'` or `"`, with `'` recommended: accepted

- Evidence: Davis wrote “strings can use ' or \" but ' is recommended” in chat, in the middle of the string discussion. It was not a choice from options.
- Both quote kinds produce the same value. A literal may contain the other quote kind unescaped. "Recommended" is style guidance; the prototype neither warns nor rewrites.
- What a string is made of (question still open), escapes, a literal containing its own quote kind, multi-line literals, and string operations remain open.

### D05au — integer `%` is the mathematical remainder: accepted

- Evidence: Davis wrote “like mathematical remainder like Python” in answer to which sign `%` takes with negative operands. It was a chat answer, not a choice from options.
- The remainder takes the divisor's sign: `-7 % 3` is 2 and `7 % -3` is -2. A zero divisor is an error.
- Chosen over a remainder that takes the dividend's sign (as in Go), which Davis did not select.
- Open: `%` on floats and rationals, whether an integer-quotient operator exists, compile-time rejection of constant zero divisors (as D05ac does for `/`), and error wording.

### D05av — big integers are values: copied when set, freed when overwritten or dropped: accepted (replaces placeholder P63)

- Evidence: asked whether a big integer should be freed or shared, Davis wrote “They should be freed, no, a big int is duplicated when set.” It was a chat answer. I read it as value semantics; he did not say reference counting was ruled out for good, only that the copy is what he wants.
- A number too big for a tagged word is owned by exactly one place: a variable, a field, a list, tuple or set slot, a table value or a temporary. Assigning, passing, returning or storing it somewhere else makes a copy. The place frees its number when it is overwritten, when its scope or function ends (also when an error unwinds), and when its container is destroyed. No count, no sharing. Small numbers are plain words, so copying and freeing one is a test of one bit.
- A result computed from other numbers (`a * b`, a call's value) moves into its destination without a copy: `product *= i` copies nothing. A parameter that the function never assigns is lent by the caller and not copied. The runtime's arithmetic only reads its operands and returns a new number.
- Chosen over reference counting big numbers (one shared number and a count, so no copy when it is stored, but a count to keep for every number) and over keeping them until the program ends (P63), which used 1.5 GB for `bigint`. Cost: a big number that is stored in a list or field is copied limb by limb; the small-number paths gained a few bit tests.
- Debug mode counts live big numbers with the other objects, so the leak report also shows a missed free. Sets of ints compare big numbers by value, not by address.
- An error caught in the middle of an expression frees the temporaries that were waiting in it (`huge() // 0`, `huge() ** -1`, `huge() + int('x')`, an argument evaluated before one that raises, the items of a literal before a failing item, a fresh base before a failing index, a fresh object and its bounds before a failing bound of `obj[a:b]`, a big `range` bound before a later bound that raises or is too big). The compiler keeps a list of the owned temporaries an enclosing expression is holding while it evaluates the next operand (`hold` / `drop_held` in `compiler.tom`); every failing check (`fail_if`) and every error returned by a callee (`check_error`) releases that list together with the owned operands of the failing operation. The debug leak check for big numbers is strict again after errors (`temp_unwind` shows it; objects stay quiet after an error, because an unwound frame can leave a cycle or a task frame). Not every failing check names its operands yet: a check that precedes an operand's own consumption does, the rest (for example the `chr`/`ord` argument checks) still drop a big-number argument.
- Open: `&`, `|` and `^` on big numbers; moving the last use of a variable instead of copying it.

### D17b — strings are UTF-8: accepted

- Evidence: Davis wrote “strings are utf8” in chat. The question that prompted it offered three options (characters, bytes, or raw bytes); his answer chose the encoding but did not say what length and indexing count.
- Text is stored as UTF-8 and is always valid Unicode. I read "always valid" from "Unicode text"; he did not state it, so it is flagged for confirmation.
- Open: whether length, indexing and slicing count characters or bytes (asked next), invalid input, escapes, and string operations.

### D17c — string positions count characters; long strings may be chunked: accepted

- Evidence: asked whether length, indexing and slicing count characters or bytes, Davis wrote “but it does not need to always walk through a string especially for long strings it will be in chunks”. That answers the cost objection to the character option; he then confirmed by choosing “Characters (Unicode code points)”.
- Length, indexing and slicing count Unicode code points; slices never split a character. Implementations may index long strings in chunks, so positions need not be found by scanning from the start.
- Chosen over counting bytes, which the question described as fast but able to cut a character.
- Open: the chunk structure, whether "character" means code point or grapheme, indexing and slicing syntax, cost guarantees, and error wording.

### D18a — `for name in x:` loops; `range` is an ordinary class: accepted

- Evidence: asked what a `for` loop should look like (options: Python-style `for ... in range(n):` plus `while`, a Go-style counter loop, or both), Davis wrote “yes for i in x: range is just another class”. He chose the Python-style option and added that `range` is not special syntax.
- `x` can be anything iterable. `range` is a class like any other, so no language feature is reserved for it.
- Chosen over a Go-style counter loop and over offering both styles.
- D48a settles the iteration protocol (`@iter` and `yield`) and the `range` forms.
- Open: the iteration protocol (what makes a class iterable), the exact `range` forms and bounds, the loop variable's scope and type, `break` and `continue`, loops over other collections, and error wording.

### D19a — function form `def name(a: T, b: U) -> R:`: accepted

- Evidence: asked how a function is written (options: `def name(a: T, b: U) -> R:` with an indented body, return type after a colon, or return type before the name), Davis answered “yes what next”. I read “yes” as choosing the first option, which was the one the question proposed.
- Parameters are `name: Type`, the return type follows `->`, and the body is indented. A function without `->` returns nothing.
- Chosen over a trailing-colon return type and a return type before the name, which would break the Python look.
- Open: default and keyword arguments, how a no-value return is spelled in types, and error wording.

### D19b — class header `class Name(Parent) implements A, B:`: accepted

- Evidence: asked how a class is declared, Davis chose **“Parent in parentheses, then `implements` with a comma list”**. His answer arrived while the task was being moved and I recorded it late.
- The parent is in parentheses and omitted when absent. `implements` and a comma list name interfaces and may be omitted.
- Chosen over everything-in-parentheses and over `extends` plus `implements` keywords.
- Open: error wording for duplicate and unknown names, and repeated interfaces.

### D20a — a list is a growable `list[T]` with literal `[a, b, c]`: accepted

- Evidence: asked what a list should look like, Davis chose **“A growable list written `list[T]` with literal `[a, b, c]`”**. His answer arrived late and I recorded it late.
- 0-based indexing `names[i]`, `append`, and `len(names)`; every item has type `T`; assigning a list shares it (D05a).
- Chosen over an immutable list and over a fixed-size array `T[n]`.
- Open: empty literal typing, negative indexes, slicing, removal and insertion, equality, printing, error wording. Generics beyond `list[T]` are a separate question (open question 58).

### D20b — maps and sets exist: accepted (one chat message also settled D21a–D26a)

- Evidence: in one chat message Davis wrote “yes implent list maps sets use clases errors need to exist try catch fianally else none exist impory export exist a standar libray ezisst if and whil and beak and contue and else esxist open exust”. It answered the question of what a compiler written in Tomato needs, and was a list of features, not a choice among options or exact syntax.
- Each decision records only that the feature exists: maps and sets (D20b); classes model data such as syntax trees, with no enums for now (D21a); errors with try, catch, finally and else (D22a); a `None` value (D23a); import, export and a standard library (D24a); if, else, while, break and continue (D25a); opening files (D26a).
- The prototype implements each with Python-like placeholders, recorded as P28-P32 and in `python/tomato/PROVISIONAL.md`, so it can run real programs. Davis decides the exact forms.
- Open: every detail named in the matching entry in the specification.

### D21a — data structures use classes: accepted

- Evidence: the same chat message as D20b (“use clases”). Syntax trees and similar data are modeled with classes; enums and variants are not added now. Details: specification D21a.

### D22a — errors exist with try, catch, finally and else: accepted

- Evidence: the same chat message as D20b. Details and open items: specification D22a, placeholders P29.

### D23a — a None value exists: accepted

- Evidence: the same chat message as D20b (“none exist”). Details and open items: specification D23a, placeholders P30.

### D24a — import, export and a standard library exist: accepted

- Evidence: the same chat message as D20b. Details and open items: specification D24a, placeholders P31.
- Layout (later; Davis: "make built in a folder, break out the stuff in it, and put bitarray in it"): the standard library is `std/NAME.tom` for a module `NAME` and `std/errors.txt`, plus the folder `std/builtin/`. The built-ins, the names every file uses without an import, are its files `errors.tom` (`Error` and its subclasses), `range.tom`, `numbers.tom` (`abs`, `round`, `divmod`), `text.tom` (the str methods and the quoting of text inside a printed container), `sorting.tom` (`sorted` with `key=` or `cmp=`), `lists.tom` (`map`, `filter`, `any`, `all`, `==` on lists) and `format.tom` (f-string format specs). The compiler reads them in that order (`builtin_parts` in `compiler/src/compiler.tom`) as one module, so nothing about them changed but their files; they are not modules of their own (`import sorting` is "cannot find the module"). `std/builtin/bitarray.tom` is the module `bitarray` (D64a): loaded only when a file uses it, still imported as `import bitarray` or `from bitarray import ...`, and its types are still named `bitarray.bitarray` in messages (`builtin_modules` lists the modules that live in the folder). There is no dotted import such as `import builtin.bitarray`. A new built-in file needs its name added to `builtin_parts`, and every file of the folder must be in `TomatoWasm.STD` (`site/wasm/tomato.js`); `tests/run.sh` checks both.

### D25a — if, else, while, break and continue exist: accepted

- Evidence: the same chat message as D20b. Details and open items: specification D25a, placeholders P5.

### D26a — opening files exists: accepted

- Evidence: the same chat message as D20b (“open exust”). Details and open items: specification D26a, placeholders P32.

### D27a — `!x` refers to an LLVM function: accepted

- Evidence: Davis wrote “!x to referece a llvm function” in chat. It is a feature statement, not a choice among options.
- `!name` names the LLVM function `name`. It is the foreign-call mechanism that a compiler written in Tomato needs (R08; open question 71).
- Davis then asked for a way to let Python run LLVM. The prototype runs `!name(args)` through llvmlite when given LLVM IR with `--llvm file.ll` (P33). The browser playground cannot, because llvmlite is not available there.
- Open: how types are declared in Tomato, dotted LLVM names, pointer and aggregate types, where the IR comes from, and the final compiler's use of `!x`.

### D28a — command line `tomato run FILE ENTRY INPUTS...`: accepted

- Evidence: Davis wrote “ok implent in llbm command linesyntax tomato run file entry inputs”, then “code the tomato run file works” and “but cannot have any inputs and assumes main”. I read the last as: with no entry and no inputs, `tomato run FILE` runs `@main`.
- `ENTRY` names the entry point (without the `@`) and `INPUTS` are its arguments, in order. This settles part of D16a's open question about arguments.
- Open: exit status and return values, other subcommands, flags (the prototype has `--llvm`), collection-valued inputs, standard input, and error wording.

### D29a — memory is managed by reference counting: accepted

- Evidence: Davis wrote “make awebsite that will compile and run it use rference countinjg” in chat. It was not a choice among options. I read it as the language's memory strategy rather than a property of the website only; he did not say which.
- An object is freed when its last reference goes away. This meets R03 (garbage collected) without a tracing collector.
- Open: reference cycles (leak them, weak references, or a cycle collector), atomic counts for threads (R09), when counts change, cleanup actions on release, and memory layout. The Python prototype does not implement it.

### D30a — the compiler emits LLVM IR: accepted

- Evidence: asked what the first real compile target should be (native first, WebAssembly first, or design first), Davis wrote “compile to llvm ir it can compil to whatver”. He chose none of the three: the compiler's output is LLVM IR, and other LLVM tools make the target.
- Chosen over native-only and WebAssembly-only output, since one IR serves every target (R05, R08, R10).
- Open: LLVM version, how each target is linked and run, and the runtime.

### D31a — async and threads both exist; threading is a library: accepted

- Evidence: asked about concurrency for web servers (R09), Davis wrote “both async and threads threading as a library”. This answered my list of big decisions, which named concurrency; he did not choose between options.
- Async is part of the language; threading is a library. Both are required.
- Open: how async is written, the threading library's contents, interaction with reference counting (atomic counts), and the web-server model.

### D32a — plain int chooses its own size: accepted (reading to confirm)

- Evidence: asked about the big-number cost of unlimited `int` in compiled code, Davis wrote “int auto fetects some size and edcides”. I read it as the implementation picking the size a value needs, keeping D05c's unlimited range.
- Chosen reading over "the compiler picks one fixed size", which would break D05c; he can say which he meant.
- Open: the analysis, spilling to big numbers, and performance guarantees.

### D33a — types are checked at compile time: accepted

- Evidence: asked about the static type checker, Davis wrote “yes check types at compile”. This confirms D04a.
- Open: inference rules, optional types, generics, and error forms.

### D24b — a plain `import module` form exists: accepted

- Evidence: asked whether a plain `import module` form should exist besides `from module import a`, Davis wrote “import module uses the”. The sentence is incomplete, so only the existence of the form is recorded.
- Open: how names are used afterwards, aliases, and the rest of his sentence.

### D34a — error output has debug, normal and release modes: accepted (superseded by D34b: two modes)

- Evidence: Davis wrote “I want readable errors in debug and somewhat in normal bt not needed in release debug full error normal outputs codes thta cna be decoded back tom debug that chatgpt”, then “with the source code normal can be decoded to debug style with a second prohrsm” and “the chatgpt does not matter”, withdrawing the unreadable phrase.
- Debug mode prints full readable errors; normal mode prints a short code that a second program decodes against the source into the debug text; release mode needs no readable errors.
- Open: the code format, how a mode is selected, location details, and what release prints, if anything.

### D34b — two modes, debug and release: normal renamed to release, the old release removed: accepted

- Evidence: Davis decided to remove the build mode called `release` (which printed nothing) and rename `normal` to `release`, so Tomato has exactly two modes. This supersedes the three-mode wording of D34a; the history above stays.
- `debug` is the default: full readable errors and the leak report (D29c). `release` is what `normal` was: failures print a short code such as `E01:4`, and `tomato explain CODE FILE` decodes it back to the full message and the source line. `--mode normal` is refused with a message saying it was renamed to `release`.
- `tomato run`, `build` and `compile` all accept `--mode`. Release builds link at `clang -O2`; debug builds link at `-O1`.
- Chosen over keeping a silent third mode: a program that prints nothing on failure helped nobody, and two modes are easier to explain. Cost: no mode can drop the error codes entirely.

### D29b — best-effort compile-time cycle detection: accepted

- Evidence: asked how reference counting should handle cycles (weak references, an automatic collector, or leaking them), Davis wrote “do sonme cycle detection at compile but not impirtant”. He chose none of the three: some detection at compile time, with low priority.
- Compile-time detection is best effort: no guarantee of catching every cycle, and this decision adds no weak references and no collector. Later decisions added the collector: D29d settled that the runtime finds and frees reference cycles automatically, and D36a built it. The compile-time notice (a warning, P38) remains alongside it.
- Open: how accurate detection must be.

### D35a — a value is a 64-bit type code plus 64-bit data: accepted (reading to confirm)

- Evidence: Davis wrote “you decied memory model my idea is type code 64bit the data 64bit”. I read it as the runtime representation of every value.
- It fits D32a: a small `int` sits in the data word, a larger one points to a big number. Heap values hold a pointer and a reference count (D29a).
- Open: the type-code assignments, which types are inline, where reference counts live, and fixed-width integers wider than 64 bits.

### D20c — the key-value collection is `dict`: accepted

- Evidence: Davis wrote “dict not map”. The type is `dict[K, V]`; the literal and other D20b placeholders do not change.

### D24c — each module has its own namespace: accepted

- Evidence: Davis wrote “seperate namespaces”, answering whether modules keep sharing one namespace.
- Open: qualified names and aliases (with D24b), and re-exports.

### D31b — concurrency is async only for now: accepted (tentative)

- Evidence: Davis wrote “just async i hink” after choosing both async and threads (D31a). I record the hedge: the threading library is deferred, not removed.
- Open: how async is written and what it awaits.

### D27b — how `!` declarations work: accepted (delegated)

- Evidence: Davis wrote “you decide how !declemraions worj”. This is my design, not his choice.
- A top-level `!name(a: T, b: U) -> R` declares the types of LLVM function `name`; calls are type-checked. `int` maps to `i64`, `int[length=N]`/`uint[length=N]` to `iN`, `float` to `double`, `bool` to `i1`, no arrow to `void`.
- Chosen over inferring types from the call, which would make the LLVM call unchecked, and over a separate header file.
- Open: pointers, aggregates, where the IR comes from, and calling conventions.

### D12bh — an interface-typed value converts to a class with a conversion that can fail: accepted

- Evidence: asked whether a value of an interface type can be converted back to a specific class, Davis chose **“Yes, with an explicit conversion that can fail”**. His answer reached me late.
- Same style as D12az. The prototype already did this by the object's real class (P15).
- Open: the failure's form, the spelling beyond calling the class name, and error wording.

### D29c — weak references exist and debug mode reports leaks: accepted

- Evidence: asked how reference counting should handle cycles, Davis chose **“Weak references written by the programmer, plus a debug check that reports leaks”**. In chat he had also said “do sonme cycle detection at compile but not impirtant” (D29b). I read the two as compatible: all three mechanisms hold. He can say if only one was meant.
- Open: weak-reference syntax, what the leak check reports and when, and how it works with the error modes (D34a).

### D36a — the compiler does real allocation: accepted

- Evidence: Davis wrote “make the compiler do real allcoation”, after the compiler could only use stack values.
- Compiled programs allocate heap objects with a header {reference count, type code} (D35a) and free them by reference counting (D29a). The prototype does this for strings, lists and class instances. Debug mode reports objects never freed, which catches reference cycles (D29c).
- This is a first slice, not the full memory model: values are plain pointers rather than the 128-bit type-code-plus-data pair, and plain `int` is still a 64-bit integer.
- Open: weak references, dicts and sets, interfaces, errors, big-number `int`, small values stored inline in the data word, atomic counts for threads (the chunked string index is built).

### D37a — class instances always use pointers: accepted

- Evidence: Davis wrote “classes always use pointeres” in chat.
- An instance is a heap object reached through a pointer, so assignment and argument passing share it (D05a). The compiler already works this way.
- Open: packing of small fields, and whether a value type could ever exist.

### D29d — no manual memory control; cycles are freed automatically: accepted (reading to confirm)

- Evidence: asked how a weak reference should be written and read (a `weak[T]` type, a `weak` modifier, or wait for optional types), Davis wrote “no manaualy control”. I read it as rejecting programmer-written weak references in favour of the runtime handling cycles itself; he did not name that option.
- This reverses the weak-reference part of D29c. The debug leak check and best-effort compile-time cycle notices (D29b) remain.
- Open: when the collector runs, its cost, and its use with threads (D31a).

### D29e — weak references may live in the standard library: accepted

- Evidence: Davis wrote “week can exist in a standar lib” right after “no manaualy control” (D29d).
- Weak references are a library facility, not language syntax, so the language itself stays free of manual memory control.
- Open: the type's name and reading, what it gives once its target is gone (no optional types yet), runtime support to clear it, and its dependence on generics. Not built.

### D23b — optional values are the type `T | None`: accepted

- Evidence: Davis wrote “None should exist opyional stuff is just Type | None”, answering how a type says "this or None" (D23a left it open).
- `x: int | None` holds an int or `None`; the same form works for parameters, returns, fields and collection elements.
- Chosen over a separate `Optional[T]` or `T?` spelling, which were not offered.
- Open: unions other than with `None`, narrowing, operators on optionals, and `None | T`.

### D19c — a parameter can have a default value: accepted

- Evidence: Davis wrote “input:Type | None = None” right after deciding optionals. I read the example as a parameter with a default value.
- Davis confirmed this reading with “yes”.
- Open: allowed expressions, evaluation time (the prototype evaluates at each call), keyword arguments, and ordering rules.

### D23c — `is None` and `is not None` work: accepted

- Evidence: Davis wrote “is None work == None works in None works”. I implemented `is None` and `is not None` alongside `== None`; the last phrase (“in None works”) was unreadable and is left out.
- Open: `is` with operands other than `None` and objects.

### D23d — the type of None is None: accepted

- Evidence: asked what “in None works” meant, Davis wrote “X in None None's type is None”. I first read the earlier phrase as `X | None` typed with the wrong key; D23e corrects that.
- `None` is both a value and a type, so `X | None` is a union of two types. This matches the prototype, where `x: None` and `x: X | None` already work.
- Open: unions of other types, and `None | X`.

### D23e — `x in None` tests for None: accepted (reading to confirm)

- Evidence: Davis wrote “no you can do if x in None:”, correcting my reading that "in None" was a typo for `| None`.
- `x in None` is a membership test against the type `None` (D23d): it is true exactly when `x` is `None`, the same as `x is None`. He did not say what it returns, so this is my reading.
- Open: `in` against other type names, and whether `x in int` should work.

### D23f — `x in Type` is the type check: accepted

- Evidence: asked whether `x in None` meant "x is None" and what `in` does against other types, Davis answered “X IN TYPE WORKS THr is how you check if something is x type”.
- `x in Type` is true when the value's type is `Type`. This generalises D23e: `x in None`, `x in int`, `x in str`, `x in Circle`.
- My reading of the details, logged as P44: a class name also matches subclasses; an interface name matches any class that implements it; `int` matches plain unlimited ints only (not fixed-width ints or `bool`); an optional's value is tested by its current contents, so `y in int` is false when `y` is `None`.
- Open: generic types (`x in list[int]`), fixed-width types (`x in int[length=8]`), and unions on the right.

### D23g — `|` is a general type union: accepted (reading to confirm)

- Evidence: asked whether to build compiled optional `int`/`float`/`bool`, Davis wrote “you don;t need expkicith optional int float ool | is just a operator”.
- My reading: `|` is an ordinary operator on types, so `A | B | C` is a union of any types; `T | None` is just the union with `None` and needs no special optional feature (so no optional-specific compiler work). A value of a union type holds one member's value, and `x in Type` (D23f) tells which. `None | X` and `X | None` are the same type; a repeated member (`int | int`, `None | None`) is an error.
- Interpreter: values are checked against the first member that accepts them. Members are not narrowed: operations and member access on a union value are checked when the code runs (as for optionals, D23b).
- The compiler still supports only `T | None` with heap types; other unions stop with "does not support … yet".
- Open: narrowing after `in`/`is`, whether a union may include generic or fixed-width types in tests, and the compiled representation of unions.

### D23h — `&` intersection, bitwise `& | ^`, and `xor`: accepted (reading to confirm)

- Evidence: Davis wrote “add &”, chose “Both” when I offered type intersection, bitwise and, or both, then “^ xor”, “not x”, “and”, “or”, “xor space” and “like python biut with xor”. He also confirmed `==`, `!=`, `>` and `<=` exist.
- `&` between types is an intersection (`Named & Printable`): a value that is every member. Members are interfaces and at most one class. `x in A & B` tests all members.
- `&`, `|` and `^` between whole numbers are bitwise and, or and xor, with Python's precedence (`|` lowest, then `^`, then `&`, all below `+` and above comparisons). The result takes the wider operand's type. `|` between types remains the union (D23g); position decides which.
- The word operators are Python's `not`, `and`, `or` plus a new `xor`: both operands `bool`, true when exactly one is true, no short-circuit, precedence between `or` and `and`. My reading of his short messages.
- `&` between types needs at least one interface among its members (Davis: “& only works if at least 1 is a inteface for types”), so `Dog & Cat` is an error while `Animal & Named` and `Named & Sized` are valid.
- The compiler supports `xor`. It stops with "does not support … yet" for the bitwise operators and for intersection types.
- Open: a bitwise-not symbol (`~`), shifts, and bitwise operators on `bool` (`~` and shifts on whole numbers were built later: D67a).

### D38a — new code is Tomato and LLVM; each compiler builds the next: accepted (reading to confirm; the Python-bootstrap part is superseded by D46a)

- Evidence: Davis wrote “ok no more python for now on only in tomato”, “and llvm” and “use the previos version to compile the next”, and then “commit changes don't push each time”, “you have control of commiting” and “once a feature fully works push”.
- Reading: from now on new compiler and tooling code is written in Tomato (with LLVM IR for low-level runtime pieces), not Python. The Python implementation stays as the bootstrap: it builds compiler v1 written in Tomato, v1 builds v2, and so on. The Python interpreter is not extended unless a Tomato program needs a feature it lacks.
- First step: `compiler/src/lexer.tom`, a lexer in Tomato that produces exactly the tokens of the Python lexer on every example, standard-library and self-hosting file (checked by `tests/test_selfhost.py`). It runs under the interpreter; the Python compiler cannot build it yet (`in` on lists and text, text methods and slicing, reading files in compiled code).
- Git: I commit as I go and push once a feature fully works, not every time. The first push was a single clean commit on top of `origin/main`.
- Stage 1 works for the lexer: the Python compiler builds `compiler/src/lexer.tom` into a native program that prints the same tokens as the Python lexer on every example and self-hosting file (`tests/test_selfhost.py`). Compiled code gained `x in list`, file reading and writing, and the text methods `find`, `replace`, `split`, `startswith` and `endswith` for it (P49, P50).
- A first end-to-end slice of the compiler is written in Tomato (`compiler/src/compiler.tom`, P53): it takes the Tomato parser's tree and writes LLVM IR for int, bool, str and list programs, with reference counting like the Python compiler. clang builds that IR with the C runtime into programs that print what the interpreter prints and report no leaks, and the compiler built natively by the Python compiler writes byte-for-byte the same IR as when it runs interpreted (`tests/test_selfhost_compiler.py`). Classes, single inheritance, `Error`, `raise`, imports and entry inputs are in too, and the Tomato compiler has compiled the Tomato lexer: the resulting program lexes every example and self-hosting file exactly like the Python lexer (first self-hosting milestone). The Tomato compiler compiles itself: stage 1 (the Python compiler builds the Tomato compiler) compiles the compiler's own source to IR, clang builds that into stage 2, and stage 2 compiles the source to byte-for-byte the same IR (a fixed point, `tests/test_stage2.py`); stage 2 also compiles sample programs that behave like the interpreter. Before that it compiled the Tomato parser too: the native program builds the same syntax trees as the Python parser for every example and self-hosting file. Still to write: dicts, sets, optionals, default arguments, `try`/`catch`, interfaces and imports in the Tomato compiler; then stage 2, the compiler compiling itself.
- The parser is written in Tomato too (`compiler/src/parser.tom`, P52). Interpreted and compiled by the Python compiler, it builds exactly the same syntax tree as `python/tomato/parser.py` for every example, standard-library and self-hosting file, including its own source (`tests/test_selfhost_parser.py`). The lexer was split into `lexer.tom` (library) and `lextool.tom` (command) so a library can be imported without clashing entry points.
- Imported modules compile (P51): the compiler can now build programs made of several files, which the compiler in Tomato needs. `examples/features.tom`, which was “not compiled yet” because it imports `math`, builds with the same output as the interpreter.
- Tools built on it: `server/compile_server.py` serves a page (`web/compile.html`) that compiles and runs a Tomato program with the Tomato-built compiler (it builds stage 2 on first start and runs programs with a 5 second limit; plain Python standard library, since Tomato has no networking yet; it binds to 127.0.0.1 only). `install-native.sh` installs a `tomato` command (`run`, `build`, `compile`) that needs only clang: it builds `tomatoc` from the checked-in `compiler/bootstrap/tomatoc.ll`, the compiler's own IR (`compiler/bootstrap/refresh.sh` refreshes it, and `tests/test_stage2.py` fails when it is out of date). The Python command stays as `tomato-py`.
- (Superseded by D46a.) Confirmed by Davis (asked whether Python may still change): language features go in the Python bootstrap until Tomato can build itself; new tools and the compiler passes are written in Tomato.
- Open: the order of the remaining compiler passes (parser, checker, code generator), how the runtime moves from C to LLVM IR, and the compiled-code features the lexer needs.

### D28b — command-line inputs take the most restrictive type: accepted (reading to confirm)

- Evidence: Davis wrote “tomato run file main 6 should use the most restrictive type so int float bool str”, then “that is listed” when I asked whether he meant the declared parameter types.
- A parameter declared `int`, `float`, `bool` or `str` reads its input as that type (as before, D28a). A parameter whose type is a union of those (D23g) takes the first member that accepts the text, trying `int`, then `float`, then `bool`, then `str`; text that fits none is an error.
- Open: unions with other members, and the compiled programs (the compiler does not build unions yet).

### D39a — `*args` and `**kwargs`, typed with `tuple` and `dict`: accepted (reading to confirm)

- Evidence: Davis wrote “*args and **kwargs should exist and should work with entries but must be typedqithn tuple or froendcit”. I read “froendcit” as `dict`.
- Parameters: `*name: tuple[T]` collects extra positional arguments and `**name: dict[str, V]` collects extra keyword arguments. Both need an explicit type, take no default, and come last (`*args` before `**kwargs`). A wrong type is an error.
- `tuple[T]` is new (my placeholder, P48): an immutable sequence of `T`, created by `*args` binding. It supports indexing, `len`, `for` and `in` like a list, and cannot be appended to or assigned into.
- Keyword arguments `f(a, b=1)` exist at call sites of functions, methods and classes you define; a positional argument cannot follow a keyword one. A keyword names a parameter, or goes into `**kwargs` when there is one.
- Entry points (D28a, D28b): inputs beyond the fixed parameters fill `*args`, each read as the most restrictive type of `T` (D28b); `name=value` inputs fill the parameter of that name or `**kwargs` (values read the same way).
- The compiler stops with “does not support … yet” on all of this.
- Open: a tuple literal, tuples as ordinary values and types beyond `tuple[T]` (mixed item types), `*` and `**` at call sites to spread a tuple or dict, and the compiled form.

### D40a — type errors and constant failures are found before the program runs, in every function: accepted (reading to confirm)

- Evidence: Davis was shown that the interpreter checked expression types while running (so `x: int = 3; x = "s"` failed only when that line ran) and that constant failures inside `if False:` were not rejected, and answered “fix”. I read it as making the interpreter obey D04a, D05x, D05ac, D05ag and D05ap: it must find these errors before running, wherever they are written.
- Before the entry point runs, a check pass walks every function and method (including imported modules) and rejects: a constant integer divisor of zero (`5 / 0`, `1 // 0`); an out-of-range constant for a fixed-width type (`x: uint[length=8] = 300`, `int[length=8](200)`); `rational(1, 0)`; a value that cannot fit a declared variable, assignment, return type or argument; an arithmetic operator on types that cannot mix; and a condition that is not a bool.
- The pass is partial (P54): it infers a type only where that is certain and lets everything else through, so it never rejects a program the interpreter accepts. It will be tightened as more rules are decided.
- Open: narrowing after `x in Type` or a `None` check, collection and method types in the pass, and when a name assigned inside a branch is still defined afterwards (left as it is: a name stays visible after an `if` or `for`).

### D41a — float literals, mixed whole-number/float arithmetic, `//` and `**`: accepted (reading to confirm)

- Evidence: Davis was told that `**`, `//`, float literals and mixed float/int arithmetic did not exist, and answered “fix”; then wrote that `/` “should normaly do float”, that “it is called float” and “it uses float64”. `float` is the binary64 type of D05z and D05aj and stays the result of `/` between whole numbers; `rational` (D05ak–at) is a separate exact type and is unchanged.
- Float literals have digits on both sides of the point, with an optional exponent: `1.5`, `2e3`, `1.5e-3` (P55). `float(x)` makes a float from a whole number or text; `int(x)` on a float drops the fraction towards zero.
- A whole number combined with a float by `+ - * / % // **` or a comparison becomes a float first, and the result is a float (P58). A float result that is infinite or not a number is an error. Dividing a float by zero is an error.
- The conversion of a whole number to a float (`float(n)`, or implicit in mixed arithmetic, a comparison, `sqrt(n)` and formatting) rounds the exact value once to the nearest float, ties to even, whatever the size of `n`. A whole number too large for a float (about 1.8e308 and more, including values that round up past the largest float) is an `OverflowError` ("an int is too large to be a float", E436) at the conversion, never an infinity; `sqrt(10**400)` therefore stops, although its root would fit. `int / int` is not converted first: it divides the exact values and rounds once (D05ad), so `10**400 / 10**399` is 10.0 and `(2**60 + 1) / 3` is not the quotient of two rounded operands. Stage 0 of `docs/bigfloat-design.md`; it holds until floats get an unlimited exponent (stage 3 there).
- `a // b` rounds the quotient down: whole numbers give a whole number (D05s typing), a float involved gives a float (P56). A constant zero divisor fails at compile time like `/` (D05ac).
- `a ** b`: whole ** whole is a whole number and a negative exponent is an error, because the result type may not depend on a value (write `2.0 ** -2`); a float on either side gives a float. `**` binds tighter than a minus on its left (`-2 ** 2` is -4) and nests to the right (P57).
- Open: mixing `rational` with `float`, how a fixed-width result of `//` or `**` is typed from literals (it needs an explicit conversion like other non-literal results), `float` as an entry-point parameter in compiled programs beyond what D28b gives, and the compiler written in Tomato, which does not have these yet.

### D42a — top-level code, version numbers and the repl: accepted (reading to confirm; the top-level-code rule is replaced by D47a, the “v-1.x” Python version is retired by D46a)

- Evidence: Davis wrote “no @main needed toplevel code works”, then “though if there is a @main run it instead”, then “you can just do @main()”; “add version number this is v0” and “python is v-1” with “v0.x” and “v-1.x”; and asked for a repl (“tomato shell … open a shell … with compiling and variables already set”), then chose the name `repl`.
- A main program may have statements at the top level; they are the program, run top to bottom. If the file has an `@main`, only `@main` runs and the top-level code is checked but not run; code can also call `main()` itself. This replaces the “no top-level code” rule of D16a for the main program. Imported modules still may not have top-level code (P60).
- The compiler written in Tomato is v0.x and the Python implementation is v-1.x. The number lives in `VERSION` (v0.1 now); `tomato version` prints it.
- `tomato repl [FILE ...]` (alias `shell`) reads one piece at a time and needs no Python: each piece joins the session, the whole session is compiled by the compiler written in Tomato and run, and only the new output is shown (Davis: “no more python”). It offers `:load`, `:program`, `:save`, `:compile`, `:reset`. The Python implementation keeps its own interpreter-based repl, which holds live values (P59).
- Open: whether top-level code should run after `@main` finishes; top-level code in the compiler written in Tomato (the compile server wraps it for now); a repl written in Tomato, which needs standard input, and a repl that keeps live values instead of re-running the session.

### D43a — the website, releases and `tomato update`: accepted (reading to confirm; the Python-era layout it lists was replaced by D46a)

- Evidence: Davis asked for tomato.davismcd.com to be a page about Tomato with a repl, a place to run programs and full documentation, “a pkg download” and a `tomato update` command, chose GitHub Pages with GitHub Releases, and asked to move the website into `site/`, delete the old `site/`, reorganize the project and remove code that is not needed.
- `site/` is a static site (overview, guide, reference rendered from the repository's Markdown, download, and a Run and Repl page that calls a compile server). `release/build.sh` builds `tomato-VERSION.tar.gz` and `latest.json` (version, URL, SHA-256); `release/pkg.sh` (macOS, after build.sh) adds `tomato-VERSION.pkg`: a universal installer into `/usr/local/lib/tomato/native` with a `/usr/local/bin/tomato` link (the layout install-native.sh makes with `TOMATO_HOME=/usr/local/lib/tomato`, so `tomato update` works; its postinstall hands the folder to the console user so no sudo is needed, which lets that user rewrite a command others may run through the link; the install script leaves an already-correct link alone so update never writes to the root-owned /usr/local/bin) and records `pkg_url` and `pkg_sha256` in `latest.json` (the updater ignores them). It is unsigned until a Developer ID Installer identity is set in `TOMATO_PKG_SIGN`, so the page says to right-click Open; `tomato update` reads `latest.json`, verifies the checksum and reinstalls.
- Layout: `python/` (the Python implementation), `compiler/` (`src/` and `bootstrap/`), `server/`, `site/`, `release/`, `native/`, `docs/`, `examples/`, `tests/`. The old chat and decision site, its `static/` page and the Pyodide playground were deleted; they remain in git history.
- Open: the public location of the releases (the repository is private today) and the public URL of the compile server.

### D43b — signing and notarizing the macOS package: accepted (reading to confirm)

- Evidence: Davis asked for the installer to be signed and notarized so Gatekeeper accepts it without right-click Open, and set up a Developer ID Installer certificate and a `tomato-notary` notarytool profile on his MacBook Pro (the build Mac has no certificate).
- `release/sign-pkg.sh` (see `docs/releasing.md`) signs the binaries, signs the package, notarizes, staples and validates; identity and profile names come from `TOMATO_PKG_SIGN`, `TOMATO_APP_SIGN`, `TOMATO_NOTARY_PROFILE`. Private keys stay on the MacBook; the package is copied there and back.
- Finding: submitting the v0.49 package signed with the Installer certificate only was rejected (status Invalid) because the universal `tomatoc` inside was unsigned. After Davis installed a Developer ID Application certificate, `sign-pkg.sh` signed `tomatoc` (hardened runtime, secure timestamp, the only Mach-O file in the package), rebuilt, signed and notarized the package on the first try (Accepted); it was stapled and Gatekeeper reports `accepted, source=Notarized Developer ID`. The signed package replaced the v0.49 release asset and `pkg_sha256` was updated. The Download page no longer says the package is unsigned.

### D44a — editor support and syntax highlighting: accepted (reading to confirm)

- Evidence: Davis noted that GitHub does not recognise Tomato as a language and wrote “write full text make grammar make syntax highlighting and everything”.
- `editors/vscode/` is a VS Code extension: a TextMate grammar (`source.tomato`, works in other TextMate-based editors too), bracket and indent rules, and snippets. The website highlights its code blocks with the same token classes.
- `tomato` with an unknown command prints `error: unknown command` and exits with 2; `tomato help` lists the commands.
- Open: submitting the grammar to GitHub Linguist (it expects wide public use first), a language server, and publishing the extension to the marketplace.

### D45a — the website compiles and runs Tomato in the browser: accepted (reading to confirm)

- Evidence: Davis asked for the Run & Repl page to work, rejected a Python interpreter in the browser (“no more python interpreter”, “no compile in visitor's browser though tomato no python”) and said “run it with the tomato compiler in wasm”.
- The compiler written in Tomato is built with the C runtime into `site/wasm/tomatoc.wasm` (WASI, 32-bit pointers) and runs in a Web Worker. The IR it writes is run by a small LLVM IR interpreter in JavaScript (`site/wasm/llvm.js`) on top of `runtime.wasm`, the same C runtime built as a WebAssembly library; the generated tables are handed to it by `tomato_set_tables`. Nothing is sent to a server and no Python is involved. A program that runs past 5 seconds is stopped.
- The runtime's list code now reads pointer slots by byte offset (slots are 8 bytes on every target), so it also works with 32-bit pointers. Native behaviour is unchanged.
- The wasm files are committed (built with `site/wasm/build.sh` and the WASI SDK) so GitHub Pages needs no toolchain. Interpreted IR is slower than native code; it is meant for demos.
- Open: the compiler written in Tomato still has no top-level code, `//`, `**` or float literals (the page moves top-level code into `@main`); an IR-to-WebAssembly backend would be faster than interpreting; `tomato repl` on the command line still re-runs the session.

### D46a — the Python implementation is retired: accepted (reading to confirm)

- Evidence: Davis wrote “stop updating python version it should never be used … remove it from the github, delete it, it will still be backed up in past commit” and “no more python”.
- v0.6 removed `python/`, the Python compile server, the Python tests and `install.sh`. The runtime moved to `runtime/` and the standard library to `std/`. Tests are `tests/run.sh` (shell, clang only).
- D38a's “language features go in the Python bootstrap” no longer applies: features are added to the compiler written in Tomato. Features that existed only in the Python prototype (see the status table in the specification) are not implemented until rebuilt there. D40a, D41a and D42a describe intended behavior; the status table says what runs today.

### D47a — no top-level code, except in the repl: accepted (reading to confirm)

- Evidence: after v0.18 made the compiler read top-level statements as the program (D42a), Davis wrote “No top level”, then “Only main”, then “Except in repl”.
- A program file has no top-level code: files hold declarations, and execution starts at `@main` or another entry point (D16a stands). This replaces the top-level-code rule of D42a and P60. The repl is the one place bare statements are accepted; it wraps them into a generated `@main` and replays the session (D42a's repl part stands). The website's Run page follows the file rule; its repl tab follows the repl rule.
- Reading to confirm: “Only main” is read as keeping `@main` as the entry, not as removing the other `@name` entry points of D16a.

### D48a — iteration with `@iter` and `yield`; `range` is a class written in Tomato: accepted

- Evidence: Davis wrote that `print(range(100))` should print `range(0, 100, 1)`, that `range` should be its own type holding start, stop and step with sequence behaviour and O(1) memory, and then that it should be a real class written in Tomato rather than a compiler special case, "with an iterator", using `@iter` and `yield`: a class marks its iteration method with `@iter`, written as a generator with `yield`; `for x in obj:` calls it; generators also work as plain functions in a `for`. This settles D18a's open iteration protocol.
- `yield value` makes a function or method a generator; it declares what it yields with `-> Type`. A method marked `@iter` makes its class iterable: `for x in obj:` runs that method. `for x in gen(args):` and `for x in obj.gen(args):` run a generator function or method directly. Strings (`for ch in text`) and lists, tuples, sets and dicts keep their own loops.
- How it runs: the generator's body is compiled into the `for` loop that uses it. Each `yield v` sets the loop variable to `v` and runs the loop body; `break` leaves the loop, `continue` goes on after the `yield`, a bare `return` ends the generator. Nothing is built in memory, so a generator over a billion numbers takes the same space as one over three. Chosen over running the generator to the end into a list (not lazy, O(n) memory) and over coroutines or heap frames (which the WebAssembly interpreter would need extra machinery for). Cost: a generator can only be what a `for` loops over, not a value you store or pass; calling one anywhere else is a compile error. A generator cannot loop over itself, cannot `yield` inside `try`, and cannot return a value. The loop uses the static type's `@iter` method (a subclass's override is not chosen at run time).
- Other protocol markers, each on one method of the class: `@len` (`len(x)`), `@get` (`x[i]`, one parameter), `@slice` (`x[a:b:c]`, four ints: start, stop, step and flags, where flags 1/2/4 say which of the three were written), `@contains` (`v in x`, returns bool), `@reversed` (`reversed(x)`), alongside the existing `@str` and `@eq`. `sum`, `min`, `max`, `sorted`, `reversed` (without `@reversed`) and `list()` work on anything with an `@iter` method; `list()` of a list copies it.
- `range(stop)`, `range(start, stop)` and `range(start, stop, step)` make a value of the class `range` (in `std/builtin/range.tom`), which keeps start, stop and step (so `print(range(100))` shows `range(0, 100, 1)` and `range(5, 10)` shows `range(5, 10, 1)`), is iterable, has a length, indexes (negative too), slices into another range, supports `in`, `==` (equal when they hold the same numbers, so `range(0) == range(5, 5)`), `reversed` (a range counted backwards), `sorted` (a list), `sum`, `min`, `max` and `list()`. A step of 0 raises `RuntimeError`. `for i in range(n)`, `range(a, b)` and `range(a, b, step)` are counted by the compiler directly and behave the same as the class within the small numbers, -2^62 .. 2^62 - 1 (bounds and step are worked out once, a zero step raises the same `RuntimeError`; as with `range(a, b)`, a bound too big for a machine word stops with `the number is too big here`, and so does a counted loop whose variable would leave -2^62 .. 2^62 - 1: it runs the numbers before that and then stops, and a loop whose first number is already outside stops before its first pass, even when later numbers would be inside; the class has no such limit).
- `progress_bar` takes a list or a range and is itself iterable: `for x in progress_bar(items):` draws after each step and ends the line when the loop is done.
- Before: `range(...)` outside a `for` was an eager list (`print(range(5))` showed `[0, 1, 2, 3, 4]`, `len(range(10**9))` built a billion items). After: it is a `range` value, and a `list[int]` parameter no longer accepts a range (call `list(...)`).

### D49a — angles are a class, `Angle`, with a subclass per unit: accepted

- Evidence: Davis asked for sin, cos, tan and their inverses with the remark “angle is a thing and it can be any different formats”, then decided the spelling: `sin(deg(30))`, with `deg`, `rad`, `turn` and `grad` making angles, inverses returning an angle, and `a.deg()` / `a.rad()` converting out to floats. He then asked for a common base for all the units, and asked whether it would be a class or an interface.
- `Angle` is a base class in `std/math.tom`; `Degrees`, `Radians`, `Turns` and `Gradians` inherit from it. `deg(x)`, `rad(x)`, `turn(x)`, `grad(x)` build them (`degrees`, `radians`, `turns`, `gradians` are longer spellings of the same). Each takes an `int` or a `float`.
- Class, not interface: every method is the same for every unit, so it is written once on the base and a unit only overrides `per_turn()` (how many of itself make a full turn: 360, 2π, 1, 400), `unit()` (the printed name) and `like(v)` (a new angle of the same unit); each also overrides its own getter, so `deg(90).deg()` is exactly 90 and `rad(1.5).rad()` is exactly 1.5. The language has no abstract methods, so the base versions of `per_turn()` and `like()` raise “Angle is a base class”. Chosen over an interface (the four units would repeat all the logic) and over storing one canonical unit (then `deg(30)` would print as radians, and round trips would add rounding error).
- Methods, all returning plain floats unless noted: `turn()`, `rad()`, `deg()`, `grad()`; `to_turn()`, `to_rad()`, `to_deg()`, `to_grad()` give an `Angle` in that unit; `normalized()` (0 up to a full turn), `signed()` (−half turn up to and including half a turn), `negated()`, `abs()`, `is_close(other, tolerance)`. Operators: `a + b` and `a - b` (the result keeps the unit of `a`), `-a` and `number * a` (D85a), `a * number`, `a / number`, and `== < <= > >=`, which compare by size whatever the unit (`deg(180) == turn(0.5)`). `-a` is `a.negated()` and `number * a` is `a * number`. (This once said there was no unary minus on classes in v0.x, so negate with `a.negated()` or `a * -1`; D85a added it.)
- Printing: each angle prints in its own unit, with a whole number written without `.0`: `90 deg`, `1.5 rad`, `0.25 turn`, `100 grad`.
- `sin`, `cos`, `tan` take only an `Angle`: `sin(1.0)` is a compile error (“argument 1 of 'sin' (the parameter 'a') has type float, but math.Angle is expected”), which is the point of the type. `asin`, `acos`, `atan` and `atan2(y, x)` return an `Angle` in radians (`atan2` takes y first, and is an error at (0, 0)).
- Accuracy: the trig functions first reduce the angle to the nearest quarter turn in turns, so `sin(deg(90))` is exactly 1.0, `sin(deg(180))` is 0.0 and `cos(deg(90))` is 0.0; other results are libm's to within about 1 unit in the last place (`sin(deg(30))` is 0.49999999999999994), so tests compare them with a tolerance of 1e-9. `tan` at 90 or 270 degrees is an error (“tan is not defined at 90 deg”), not a huge number. *[D83a: a radian angle of double size now goes straight to the C library instead, because the reduction in turns rounded it.]*
- Open: angle ranges and units beyond these four. (Unary minus and a number on the left, open here at first, are D85a.)

### D49b — module constants: `const name = literal`, `export const` to share: accepted

- Evidence: Davis asked for `pi`, `tau` and `e`; programs have no top-level code (D47a), so a constant had to be something that is not code.
- `const name = 3.14` at the top level (and `export const`) declares a constant whose value is a number, text or `True`/`False` written out; the compiler puts the literal in wherever the name is used, so a constant has no memory and no start-up cost. `from math import pi, tau, e` imports them like any name. A local variable of the same name hides the constant. Anything but a literal is a compile error (“a constant is not code: write its value as a literal”).
- Float literals in the compiler are limited to what it reads exactly, so `pi`, `tau` and `e` are written with 16 digits: they are the nearest floats to the true values.
- Open: constants computed from other constants, and constants of class type.

### D49c — math functions, how libm is reached, and domain errors: accepted

- Evidence: Davis asked for sinh, cosh, tanh and inverses, hypot, sqrt, exp, log, pi, tau and e “if missing”, and to check libm and WebAssembly.
- `std/math.tom` adds `sqrt`, `cbrt`, `hypot`, `exp`, `expm1`, `log` (natural) and `log_base(x, base)`, `log2`, `log10`, `log1p`, `sinh`, `cosh`, `tanh`, `asinh`, `acosh`, `atanh`. They take an `int` or a `float` and return a `float`; the hyperbolic functions take plain numbers, not angles. They call libm through two small C functions in the runtime (`tomato_math1`, `tomato_math2`, reached with D27b's `!` declarations), so there is no new compiler mechanism. The WebAssembly build links the WASI C library, which includes libm, and the browser interpreter already calls any `tomato_*` function the runtime exports, so the same functions run in the browser with no extra work and no limits.
- A value libm cannot answer is a `RuntimeError` written in plain words, checked before the call: `sqrt` of a negative number, `log` of zero or less, `asin`/`acos` outside −1 to 1, `acosh` below 1, `atanh` at or beyond ±1, `atan2(0, 0)`, `tan` at a quarter turn; an overflowing result (`exp(1000)`) is “too large to be a float”. This follows D41a (a float result that is infinite or not a number is an error). Chosen over returning infinity or NaN, which Tomato does not allow as float values.
- The integer-only helpers `abs`, `min`, `max` and `pow` already in `math` are unchanged.
- Libm results are not identical between systems: glibc's `cbrt(27)` is 3.0000000000000004 where macOS gives 3.0. `tests/programs/angles.tom` therefore compares `cbrt` with a tolerance of 1e-9 (the same `near` helper it uses for the trig results), so it passes on both and still catches a wrong value; results every libm gets exactly right (`sqrt`, `hypot(3, 4)`, `exp(0)`, `log2(8)`) are still compared for equality.

### D53a — f-strings: `f'text {expr} more'`: accepted

- Evidence: the task brief asked for f-strings, following Python.
- A text literal with an `f` straight before the opening quote is an f-string. Each `{expr}` is replaced by `str(expr)`, so a value prints the way `print` shows it (a class with `@str` uses it); `{{` and `}}` give literal braces. Both quote styles work, and the usual escapes (`\n`, `\'`) work in the text parts. The lexer turns an f-string into the tokens of `('text ' + str(expr) + ' more')`, so it is an ordinary text expression of type `str`.
- Following Python: f-strings nest (`f'{f"{x}"}'`), and an expression may use the other quote kind. Not built: format options (`{x:5}`, `{x!r}`, `{x=}`) are an error saying so, and an expression cannot hold the f-string's own quote character.

### D53b — conditional expressions: `a if condition else b`: accepted

- Evidence: the task brief asked for it, following Python.
- `a if condition else b` has the loosest precedence of any operator and groups to the right (`x if p else y if q else z`). Only the chosen side is evaluated. The condition must be a `bool`.
- Both sides have one type. The exceptions: `None` with a class, text or list value gives that type with `| None`; a side that can be used as the other's type (a subclass, a smaller integer type) takes that type; and where a union or optional type is expected (a declared variable, a return, an argument) each side converts to it. Otherwise it is a compile error naming both types. Chosen over making the type a union of the two, which would hide mistakes such as `n if ok else 'none'`.

### D53c — list comprehensions: `[item for x in items if condition]`: accepted

- Evidence: the task brief asked for it, following Python.
- `[item for x in items]` and `[item for x in items if condition]` build a `list[T]`, where `T` is the type of `item`. `items` can be anything a `for` loop accepts, including `range`, text, a set, an object with `@iter` and `enumerate(xs)`/`zip(xs, ys)` with several variables (`[i * w for i, w in enumerate(ws)]`). The item and the condition may use any variable of the function. Comprehensions nest.
- The loop variable is an ordinary variable of the function, as in a `for` loop (not a private scope as in Python 3), so it keeps its last value and must have the same type as any variable of that name already in the function.
- Not built: several `for` clauses or several `if` clauses in one comprehension, and set and dict comprehensions.
### D56a — more built-ins: abs, chr, ord, dict methods and text methods: accepted

- Evidence: the built-in set lacked names every Python program uses. Where a detail was undecided it follows Python (the rule in the task brief); the details below are the ones Davis has not seen.
- `abs(x)` takes an `int` or a `float` and gives the same type (`abs(-0.0)` is `0.0`). Fixed-width integers are not accepted yet. `chr(n)` gives the one-character text with code point `n`; `ord(c)` gives the code point of a text of exactly one character. `chr` stops with a `RuntimeError` for a number outside 0 to 1114111 or a surrogate (a text is always valid Unicode, D17b); `ord` stops unless the text has exactly one character.
- `int(text)` is already settled in D50a; this decision adds nothing to it.
- `dict.get(key, default)` gives the value, or `default` when the key is missing; the one-argument form (which would give `None`) is not available yet. `dict.keys()` and `dict.values()` give new lists in insertion order (not live views). `dict.items()` gives a list of two-item tuples (key, value). A tuple has one item type today, so the pair's item type is `str` for a `dict[str, str]` and the union `str | V` for any other value type `V` (the items are boxed; `pair[0]` and `pair[1]` are narrowed with `x in str` as for any union). `for key, value in d.items()` waits for tuple unpacking. A dict whose values are unions, optionals, lists, sets, dicts, objects or fixed-width ints cannot use `items()` yet (a boxed value of those kinds would print as `<object>`; later, P89: a list, tuple, set, dict or object with `@str` in a union prints properly). (Later, P89: `items()` gives `tuple[str, V] (tuple[K, V] since D78a)` pairs, tuples of mixed item types, for every value type; `for key, value in d.items()` works since P87.) `chr` of a number beyond 64 bits is the same `RuntimeError` as any other out-of-range number.
- Text methods: `find(sub, start)` (a negative `start` counts from the end, as in Python), `rfind(sub)`, `count(sub)` (non-overlapping; the empty text matches between every character, so `'abc'.count('')` is 4), `isdigit()`, `isalpha()`, `isspace()`, `lstrip()` and `rstrip()` without a characters argument. `upper` and `lower` now use Unicode simple case mapping (see the end of this file); `strip` (D38a), `isdigit` and `isalpha` know only ASCII characters, and whitespace is space, tab, newline and carriage return (later, P89: `isdigit` and `isalpha` know all of Unicode 16.0). The one-argument `find` and the new `rfind`, `count` are in the runtime; the rest are in `std/builtin/text.tom`.
- Open: `find`/`rfind`/`count` with an end bound, `strip(chars)`, Unicode letters and digits, `get(key)` giving `None`, `dict.items()` as a typed pair. (All built since: P87 and P89.)
### D50a — reading input: `await input(prompt)`, one line of text: accepted

- Evidence: Davis asked "how should we add input". He chose `input(prompt)` "like Python" (the prompt is optional), end of input raising a catchable `EOFError`, and numbers through the existing conversions rather than new helpers. He rejected a separate `stdin()` / `read_all()` ("no just tomatos input function"); `tomato run` entry points already take inputs from the command line (D28a).
- `input()` returns the next line of standard input as `str`, without its line end (`\n` or `\r\n`); a last line with no line end is still a line. The prompt, when given, is written to standard output first and flushed.
- When there is no more input, `input` raises `EOFError` (a class in `std/builtin/errors.tom`, a subclass of `RuntimeError`, so `catch RuntimeError` also catches it); the message is "there is no more input to read".
- Numbers: `int(text)` and `float(text)` read decimal text with spaces around it allowed (`int(' 5 ')` is 5, `+5` and `-5` work; `float` takes `1.5`, `2e3`, not `nan`/`inf`/hex). Text that is not a number raises a catchable `RuntimeError` ("the text is not a whole number" / "the text is not a number"). Chosen over `input_int`/`input_float` helpers that re-ask by themselves, which would hide a loop.
- Davis then said input must be async (D51a), so `input()` can only be awaited: calling it without `await` is a compile error with the fix written out.

### D50b — the repl and the playground replay answers: accepted

- Evidence: Davis chose "Remember answers" for the repl, where each line re-runs the whole session, and an interactive playground that pauses at `input()` and shows a prompt field.
- Both use one mechanism. A program whose answers have run out and that asks for another stops with exit code 75 (the host sets `TOMATO_INPUT_ASK=1` in the environment; the browser host does the same); the host shows what the program printed up to its prompt, reads one line, and runs the program again from the start with all answers so far as its standard input. Answers are replayed silently and the program echoes each answer after its prompt (as a terminal would), so the output of every run starts with the output of the run before, and only the new part is shown. Nothing is asked twice.
- Repl: each line that asks adds its answers to the session; `:reset` forgets them. A line that fails does not keep its answers. The session `main` becomes `async def` when a statement uses `await`, `async` or `start`. In a script or pipe the answer is the next line of the script.
- Playground: the Run page shows a field right after the output when the program asks; Enter re-runs with the answer added. Pressing Run again starts over with no answers. The repl tab behaves like the installed repl. The 5 second limit applies to each run.
- Limit (bash 3.2): no `bind -x`/`READLINE_LINE`, so Up cannot itself show the multi-line form. Cost: a program that ran for a long time before asking is run again from the start for each answer, and a program with side effects outside itself repeats them (the same caveat the repl already had).

### D51a — `async def` and `await`: accepted

- Evidence: Davis answered the question "how should async be written" with "`async def` and `await`, like Python", chose "Compile error with a fix hint" for a call that is not awaited, and asked for full concurrency ("Full concurrency now"). This settles the syntax left open by D31a and D31b.
- `async def f(...) -> T:` declares an async function. Calling it does not run it: it makes a task (D51b). `await expr` waits for a task and gives its result, or raises the error the task raised. `await f(x)` runs `f` at once, up to its first wait, and the caller goes on from there when it is done. `@main` may be async (the scheduler runs it).
- Only async functions can `await`, `start` or use `async for`. Calling an async function without `await` or `start`, and awaiting something that is not a task are compile errors with a hint. Awaits in `while`/`elif` conditions and in `and`/`or` were refused here; D58e allows them. Any other await in an expression is allowed (`n = int(await input('n? '))`): the compiler moves each await into a statement of its own just before the statement that uses it, in left-to-right order.
- `await` and `async` are now keywords; `start` is a keyword only in `start name(...)`.
- `try`/`catch`/`finally`, loops, `break`, `continue` and `return` work across an await like anywhere else. Async methods are D58b.

### D51b — `start f()` makes a task that runs at the same time: accepted

- Evidence: Davis wrote "we will have start f() to that gives a object".
- `start f(args)` begins running an async function and gives a task object of type `task[T]` at once (T is the function's return type, `None` when it returns nothing); the task runs whenever the starting code waits (`await`), so tasks interleave. `await t` gives its result and can be done once or many times; if the task failed, the error is raised again at each `await`. Tasks can be stored in lists, passed and returned (`list[task[int]]`).
- Scheduling is cooperative on one thread: a task runs until it awaits something that is not ready or yields (D51c); nothing preempts it, so there are no data races. Tasks that are ready run in the order they became ready. When nothing is ready, the oldest task that asked for input gets the next line (so concurrent tasks that all ask for input are served in the order they asked).
- The program ends when `main` is done and no task is ready to run; a task that is waiting for something that never comes is dropped. If `main` is not done and nothing can run, the program stops with "every task is waiting for something that can no longer happen". An error in a task that nobody awaits is reported by D58a.
- Implementation: each async function becomes a frame (a heap object holding its variables and where it stopped) and a resume function written as a state machine, so it works the same in the native runtime and in the browser's IR interpreter, which cannot switch stacks. The scheduler is generated code; the runtime only keeps the ready queue and the queue of tasks waiting for input.

### D51c — `yield` in an async function reports status: accepted

- Evidence: Davis wrote "yield is how status is typically given in async functions" and chose: statuses are read with `async for status in t:`, `await t` gives the final result, and a task nobody reads statuses from just runs on (yielding never blocks it).
- An async function that yields says what it yields after the return type: `async def download(url: str) -> int yields str:`; the task type is then `task[int, str]`. `yield v` appends `v` to the task's list of statuses and then lets other tasks run. `async for s in t:` takes the statuses in order, waiting when there are none yet, and ends when the task is done and every status has been taken (it does not raise; `await t` after the loop gives the result or raises the error). Statuses are kept until read, without a limit.
- This is different from a generator `yield` (D48a), which is used by `for` and runs inline; in an async function `yield` always means a status.
- Open: a task awaited by `async for` from two tasks at once reading the same statuses.

### D58a — an error in a task nobody awaits: accepted

- Evidence: Davis chose "report to stderr, and the program exits with code 1 at its end", then said the error should be raised so it can be caught, "at all of the awaits", and confirmed "raised in the task that started it, at its next await".
- A task is unread when it failed and the last reference to it is dropped without any `await` or `async for` having taken its error (a task that is still held, in a variable or a list, can still be awaited, so it is not unread yet). Its error is then handed to the task that wrote `start f()`: it is raised at that task's next await of any kind (`await`, `await input()`, `async for`, `yield`), where a `try`/`catch` around that await catches it like any other error. Raised once.
- For `await f(...)` the error is raised before `f` is called; one that arrives while `f` runs waits for the await after it, so neither `f` nor its result is lost (D76b).
- If the starting task has already finished (or never awaits again), the error is written to standard error in the form of an uncaught error (D22a) followed by "in a task nobody awaited", the program carries on, and exits with code 1 when it ends. A task that was still held when the program ended is reported the same way.
- The starter is not woken for this: a starter that is waiting on something else sees the error when it next runs.
- Implementation: a task frame has one more fixed field, the starter; a runtime queue holds errors waiting for their starter. A task frame is recognised by bit 10 in the runtime kind table, so dropping one can look at it.

### D58b — async methods and async `@iter`: accepted

- Evidence: Davis accepted the proposed rules and chose "also allow `@iter` as an async iterator".
- A class can have `async def` methods (and `override async def`). The task made by calling one keeps `self` alive until the task ends. `await obj.m()`, `start obj.m()` and calls through a parent-typed variable (virtual dispatch: the method table holds the task constructor) work like functions; calling one without `await`/`start` is the same compile error.
- An override must be async exactly when the method it overrides is, with the same return and `yields` types; otherwise "must take and return the same types". `@init` cannot be async, and neither can an operator or protocol method except `@iter`.
- `@iter` may be `async def each(self) yields T:` (a return type is allowed too). `async for x in obj:` calls it, starts the task and reads its statuses as for any task (D51c). A plain `for` over such an object is a compile error that says to use `async for`; `list()`, `sum()` and the like do not accept it.

### D58c — `await sleep(seconds)`: accepted

- Evidence: Davis chose "real clock natively, virtual clock in the browser".
- `await sleep(seconds)` (an int or a float; zero or less just lets the other tasks run) waits that long inside an async function; calling it without `await` is a compile error with the fix written out. It is a built-in like `await input()`.
- Time is logical: a sleeper wakes at its wake-up time on a clock that moves only when every task is waiting (nothing is ready and no task wants input that is available), the earliest first and ties in the order they went to sleep. So the order of output is the same on every machine, natively and in the browser, and the time a task spends computing does not move the clock. Natively the process also really waits until the real time since the first sleep reaches the logical time; in WebAssembly there is no blocking sleep, so the clock just jumps and a sleep takes no real time (the playground's 5 second limit therefore never counts it).
- Exception (Davis chose "Real time once the network is used"): natively, from a program's first socket (`connect` or `listen`), request wait, or input wait without a complete line, a sleep or timeout counts real seconds from when it starts, computing included, so a timeout is neither early after a long computation nor late under constant traffic. Sleeps in such a program may wake in a different order on a slower machine. The browser is unchanged.
- Available input is served before the clock moves. Natively, when an input waiter has no complete line available, the scheduler waits for input alongside sockets and requests, and the clock follows real time from then on, as it does for network waits. In the browser input still uses the replay mechanism. A program stops with the "nothing can run" error only when no task is ready, none is asleep and none wants input.

### D58d — cancelling a task, `t.done()`: accepted

- Evidence: Davis accepted the proposed rules ("Yes, these rules"), including that `CancelledError` is a subclass of `RuntimeError`.
- `t.cancel()` is an ordinary call (no `await`). The task raises `CancelledError` ("the task was cancelled") at its next wait, or at once if it is waiting now: it is taken out of the queue it waits in (a sleep, an input request, another task it awaits) and made ready, so its `finally` blocks run and it may catch the error and carry on. A task not yet started raises at its first step, before running any of its body. Cancelling a finished task does nothing, cancelling twice is fine, and cancelling a task that waits for another task cancels only the waiter (changed by D76b for `await f(...)`: there the cancel reaches into the awaited call; awaiting a task made with `start` is unchanged).
- `await t` on a cancelled task raises `CancelledError` again like any task error. A task that ends with `CancelledError` is not an unread error (D58a).
- `t.done()` is `True` once the task has finished in any way (result, error or cancelled), without waiting. Any other method name on a task is a compile error that lists these two.
- Not included: `t.cancelled()`, cancelling many tasks at once, timeouts (since built as `asyncio.wait_for`, D76a).

### D58e — `await` in `while`, `elif` and the right side of `and`/`or`: accepted (follows Python; not asked separately)

- Evidence: the task brief listed it as the last item; there is one sensible meaning, Python's. Davis has not been asked about it separately, so veto it at review.
- `while await more():` runs the await again before every iteration, and `continue` goes back to it. An `elif` condition with an await runs only when the earlier conditions were false. `a and await f()` runs `f` only when `a` is true; `a or await f()` only when `a` is false. This replaces the compile errors of D51a for these three places.
- Implementation: the compiler rewrites them before compiling: the while becomes `while True:` with the await and an `if not condition: break` at the top; an elif with an await moves it and the branches after it into the else branch; `x and await f()` becomes `t = x` then `if t: t = await f()` (`not t` for `or`).
- An await in either value of `a if c else b` is now a compile error with the fix (before, it ran whatever the condition said, which was a bug).

### D52a — `not in` and more compound assignments: accepted (following Python)

- `x not in items` means `not (x in items)`, for everything `in` works on (lists, text, sets, dicts, tuples, ranges, classes with `@contains`, `x in Type`). It compares like `in` and `is not`, so it cannot be chained.
- `//=`, `**=`, `&=`, `|=` and `^=` join `+= -= *= /= %=`; `x op= v` is `x = x op v`.
### D55a — a union stays narrowed after an early exit and in `else`; `len` and `for` work on a union: accepted

- Evidence: Davis asked for a union narrowed by a type test to be usable beyond the body of `if x in T:`; this follows Python's type checkers (mypy, pyright), which narrow the same way.
- A union variable tested with `x in T` (T one of its members) is narrowed beyond the `if` body: in `else:` it is the members no condition matched, and after the `if` it is the members of the branches that fall through (a branch that ends in `return`, `raise`, `break` or `continue` does not count). One member left gives that type, several a smaller union that can be tested again. The narrowing lasts to the end of the block the `if` is in.
- Python's rule on assignment also holds: a narrowed variable cannot be assigned inside the check or in the rest of the block (compile error), so the type never goes stale at a loop head.
- `len(x)` on a union gives the length of whichever member it holds; `for item in x:` loops over whichever member it holds. Both need every member to support it, and a loop's items must have the same type in every member.
- A smaller union is accepted where a larger one with those members is wanted.
- A `for` over a union must name a plain variable; other expressions give the usual not-iterable error.
- Not covered: narrowing by `not in`, `is None`, `and`/`or`/`not` conditions, by `while` conditions or conditional expressions, of fields (`self.x`) and anything but a plain variable; other operations on a union as a whole (only `len` and `for`).

### D54a — tuple unpacking and multiple assignment: accepted

- Evidence: Davis asked for `a, b = b, a`, `x, y = some_tuple` and `a, b = f()` where `f` returns a tuple; details followed Python.
- Several targets (variables, fields or items, separated by commas) can stand left of `=`. With several values on the right (`a, b = b, a`) all values are evaluated first, then assigned left to right, so a swap works and the values may have different types. A different number of values and targets is a compile error (`cannot unpack 3 values into 2 variables`).
- With one value on the right (a `tuple`, `list` or text, such as the result of a call) its length is only known when the program runs: a wrong length is a `RuntimeError` with the same message. A trailing comma on the left (`only, = pair`) unpacks one item.
- Open: a starred target (`first, *rest = xs`), nested targets (`(a, b), c = ...`), unpacking in `for` loops (only `enumerate` and `zip` have two variables) and in declarations with types (`a: int, b: int = ...`).
### D57a — the built-in interfaces `Iterable[T]` and `Sized`: accepted

- Evidence: the task asked for two built-in interfaces, named as in Python's `collections.abc`: `Iterable` is anything a `for` loop accepts and `Sized` is anything with a length. A parameter typed `Iterable[int]` should take a `list[int]`, a `range` or a class with an `@iter` method.
- Names: `Iterable` and `Sized`. They are built in (no import). A program that defines its own `Iterable` or `Sized` class or interface keeps its own meaning: the built-in is used only when the name is not otherwise declared.
- `Iterable[T]` is satisfied by `list[T]`, `tuple[T]`, `set[T]`, `range` (and any class whose `@iter` method yields `T`), `str` (as `Iterable[str]`) and `dict[str, V]` (as `Iterable[str]`, its keys). `Sized` is satisfied by lists, tuples, sets, dicts, text and any class with an `@len` method that takes nothing and returns `int`. No `implements` line is needed or accepted: having the method is enough.
- The item type is written in brackets, as in `list[T]`: `Iterable[int]`, `Iterable[str]`. Interfaces are not generic in general; this is a special form of the two built-ins. The item type must match exactly (a `list[Dog]` is not an `Iterable[Animal]`, as a `list[Dog]` is not a `list[Animal]`).
- `Iterable[T] & Sized` is a value that is both (Python's `Collection`); `&` between these two built-ins is the only use of `&` between types in this version (D23h is otherwise not built). `Iterable[T] & Sized` can be used where `Iterable[T]` or `Sized` is wanted.
- Inside a function, `for x in items:` loops over an `Iterable[T]` (x is a `T`) and `len(items)` works on a `Sized`. A `for` over a plain `Sized`, or `len()` of a plain `Iterable[T]`, is a compile error. Nothing else is built on them yet: `sum`, `min`, `max`, `sorted`, `list()`, `in` and indexing on these types are follow-ups.
- How it works: a value of these types is boxed, as a union is, holding the concrete value passed in; a loop or `len()` is compiled once for every kind of value that can be in the box and the matching one runs. A generator is part of the loop that uses it, so it cannot be called through a plain interface, and this is how its loop is still lazy. A set or dict passed as an `Iterable` is boxed as a snapshot of its keys, which is what a `for` loop over it walks anyway (P28).
- `std/itertools.tom`'s `progress_bar` took `Iterable[int] & Sized`, so it accepted a list of ints, a range, or your own class with `@iter` and `@len`; D60a made it generic over the item type.

### D60a — generic classes and functions: accepted

- Evidence: Davis asked why `progress_bar` only took an `Iterable[int]`: it should work with any sized iterable (lists of text, objects, tuples, floats, ranges, text). The `Iterable[T]` of D57a is the only generic thing the language had; a class could not say "T" for its items, so `progress_bar` had to name one item type. The same limit held for the `itertools` helpers (`permutations`, `combinations`, `product`, ...), which were written for `list[int]`.
- Alternatives: an any-item `Iterable` that gives its items as a union (every loop would then need narrowing before using an item); making `progress_bar` and each helper a compiler special case (`Iterable[T]` already is one, and every library class would need another); copying the library source once per item type by hand. Real type parameters fix all of these with one feature.
- Syntax: a class or function lists its type parameters in brackets after its name: `class Box[T]:`, `class Pair[A, B]:`, `def first[T](items: list[T]) -> T:`. Inside the declaration `T` can be written anywhere a type is expected: a field, a parameter, a return type, a local (`out: list[T] = []`), `@iter` and `@len` methods, and the declaration may use itself (`Pair[B, A]`) and other generics. A type argument list is written the same way where a type is wanted: `b: Box[str]`, `def f(s: Stack[int])`. Up to two type parameters were accepted here; D62b raised that to five.
- Inference: a call finds each type parameter from the types of its arguments, matching them against the parameter types. A parameter typed `Iterable[T]` (or `Iterable[T] & Sized`) takes T from the item type of whatever is passed: a list, tuple, set, dict (text keys), text, `range` or a class with `@iter`. If one T gets two different types (`pair([1], ['a'])` with both parameters `list[T]`) the second argument is reported as a mismatch the usual way. If T cannot be found from the arguments, the compiler says so and asks for it written out. Only positional arguments are used to find T.
- Explicit form: `Stack[str]()` and `first[str](names)` write the one type argument out (with several type parameters, `Pair[str, int](...)`, see D62b).
- How it works: nothing is compiled for the declaration itself. Each use with other types makes a copy in which every type parameter stands for its type (monomorphization), compiled with the rest of the program; the same arguments always give the same copy. A copy of a class is an ordinary class named `Box[str]` in messages, with its own type code and method table, so objects, interfaces, `@iter`/`@len` and `Iterable` boxes all work on it as on any class. Because copies are made while the bodies are compiled, a copy that first appears after code that loops over every class fitting an `Iterable`/`Sized` type restarts the compile with that copy made first (up to a few dozen times, once per such copy), so no loop misses it. Nothing at run time changes.
- Not built: generic interfaces, generic methods (a method with its own type parameters), bounds on a type parameter (every use of T is checked in the copy, not against a promise), a generic class as a parent, async generic functions, and (until D62b) writing more than one type argument in a call.
- `itertools` now uses it: `class progress_bar[T]` (`for name in progress_bar(['a', 'b'])` gives text, `range(10)` gives ints) and `permutations`, `combinations`, `combinations_with_replacement`, `product`, `product_repeat`, `chain`, `pairwise`, `batched` and `repeat` take lists of any item type. Their order and results are unchanged. `accumulate` still adds, so it stays on `list[int]`.

### D62a — `clock()` and `std/cache.tom`, an LRU cache: accepted

- Evidence: Davis asked for a cache library. Asked how a missing key should behave he chose "`get(key, default)` plus `c[key]` raising"; asked how expiry and the clock should work he chose "add a `clock()` builtin (monotonic float seconds); the cache takes an injectable clock".
- `clock()` is a built-in that gives the seconds on a monotonic clock as a `float` (`time.monotonic()`); only the difference between two readings means anything. It is real time, not the logical clock of `await sleep` (D58c). In the browser it has the resolution of `Date.now()` (milliseconds).
- `dict.remove(key)` takes an entry out and releases its value; a missing key stops the program ("the key is not in the dict"), as for `set.remove`. Dicts had no way to forget a key before.
- Creating a generic class with its type written out and keyword arguments (`Box[int](1, n=2)`) silently dropped the keywords; it is now the same error as for other classes ("pass the arguments by position").
- `from cache import Cache, CacheMiss, Clock`. `Cache[V](capacity, ttl, timer)` (replaced by `Cache[K1, ..., R]` in D62b): text keys (dicts only have text keys) and one value type, so the generic class has one type parameter. `get(key, default)`, `c[key]` (raises `CacheMiss`, a `RuntimeError`), `peek`, `set(key, value, ttl)`, `delete`, `clear`, `keys()`, `len`, `key in c`. Optional return values are not available yet, so there is no `get(key)` giving `None`.
- Least recently used entries go first. `get`, `c[key]` and `set` count as a use; `in`, `peek` and `keys` do not. Every operation is O(1): a dict finds the entry and a doubly linked list orders them. Capacity 0 stores nothing; a negative capacity is an error.
- TTL: a cache-wide `ttl` (0 or less means none) and a per-entry `ttl` on `set`; an expired entry is dropped when next looked at and counts as a miss (`expirations`). Time comes from a `Clock` object (`now()` returns `clock()`); a test passes a subclass whose `now()` it controls. Chosen because functions are not values yet.
- Statistics: `hits`, `misses`, `evictions`, `expirations`, `hit_rate()`.
- Concurrency: the runtime runs one thing at a time and tasks switch only at `await`; no cache method awaits, so nothing is locked.
- Memoising (added later): `memoize(f, capacity)` returns a `Memo[K, V]` (also `Memo(f, capacity, ttl, timer)`), used as `m.call(x)`, because there are no closures to return a function. Results sit in a `Cache` keyed by the argument and are counted in `m.results` (D62b: functions of up to four parameters); an error is not remembered. `@cached` cannot exist (Davis): `@name` before a function is an entry point (P21) and before a method a role marker. Building it also fixed the compiler: a generic class with a function-typed field and a generic-class field failed with a false "no @init method" error.
- Not built: `@cached`, a size limit in bytes, a disk-backed cache, a request cache for the HTTP client, a wall-clock `time()`. Keyword arguments cannot be used when creating an object, so `ttl` and `timer` are positional in `Cache[int](100, 60.0)`; they work as keywords on methods (`set('a', 1, ttl=5.0)`).

### D62b — `Cache[K1, ..., R]`: multi-part keys, and generic declarations overloaded by number of type parameters: accepted

- Evidence: Davis decided that `Cache[V]` (text keys only) is the wrong shape: the cache must be written `Cache[K1, K2, ..., R]`, the LAST type being the result and the others the parts of the key, so that `Cache[int, int, str, float]` caches a function of `(int, int, str)` returning `float` and `memoize` works for functions of several arguments. A cache with a result and no key (`Cache[int]`) is not wanted. LRU, capacity, TTL, the injectable clock, the four counters, `get`, `peek`, `set`, `delete`, `clear`, `keys`, `len`, `in` and `CacheMiss` stay.
- What the language could not do, found first: a class took at most two type parameters (parse error E139); a generic class type could be written with at most two type arguments; `Name[A, B](...)` with two written type arguments was not built; one name could not be declared twice; `@get`/`@contains` objects could not be given a tuple written as `c[1, 2]` or `(1, 2) in c`.
- Compiler changes (small and general, not cache-specific): (1) up to **five** type parameters (E139 now says "at most five"); a type with three or more type arguments is parsed as `Name[A, B, C]` (stored as a list, like `tuple[A, B, C]`). (2) `Name[A, B, C](...)` and `f[A, B](...)` write several type arguments in a call. (3) **Overloads by number of type parameters**: a generic class or function may be declared again under the same name with another number of type parameters (`class Cache[K, R]`, `class Cache[K1, K2, R]`, ...); a use picks the declaration that has as many type parameters as it writes type arguments (`Cache[int, int, float]` is the three-parameter one), and a call without written type arguments (`Memo(f, 100)`, `memoize(f, 100)`) takes the first overload from which every type parameter can be found from the arguments (a function of two parameters finds `Memo[A, B, R]`, not `Memo[K, V]`). A number that fits no declaration is reported ("'Cache' takes 2, 3, 4 or 5 type arguments, but 1 given"). Two declarations with the same number are still "defined twice". Copies are named by their types as before (`Cache[int,int,float]` cannot collide between overloads). (4) A pattern `$K` no longer swallows a comma, so `fn(K) -> R` no longer matches a function of two parameters. (5) `c[1, 2]` and `(1, 2) in c` build the tuple for the type that the object's `@get`/`@contains` method takes (a tuple of mixed item types; it was reported as `tuple[int]` when every part was an int).
- Alternative rejected: separate names `Cache1[K, R]`, `Cache2[K1, K2, R]`... (nothing to write for Davis's `Cache[x, y, z, r]`); a real variadic type parameter list (`Cache[*K, R]`): far too large for one library; a hash-code dict (the runtime has none: dicts have text keys only).
- How `Cache` is built: there is one cache engine, `Lru[K, V]`, with the old code (a text-keyed dict and a doubly linked list; every entry carries the key as a value of type K for `keys()`). `Cache[K, R]`, `Cache[K1, K2, R]`, `Cache[K1, K2, K3, R]` and `Cache[K1, K2, K3, K4, R]` are four thin classes (one to four key parts) that turn the parts into text, call the engine and copy its four counters into their own fields (`c.hits`, `c.misses`, `c.evictions`, `c.expirations` stay plain fields). `Memo` and `memoize` are overloaded the same way for functions of one to four parameters: `memoize(f, capacity)` with `f(int, int, str) -> float` is a `Memo[int, int, str, float]`, called `m.call(1, 2, 'a')`, whose `m.results` is a `Cache[int, int, str, float]`.
- **Key encoding.** Dicts only have text keys, so a key is one text. Every key part is written as the number of characters of its `str` text, a colon and the text, and the parts are joined without a separator: the key `(1, 22, 'a:b')` is `1:12:223:a:b`. The length says where each part ends, so two different keys never give the same text (a part may itself contain digits and colons). No type tag is needed: every position of one cache has one static type, so a `1` and a `'1'` cannot meet. This holds for any key part whose `str` tells two values apart: `int`, `float` (`0.0` and `-0.0` are two keys, and `nan` is one key), `bool`, `str`, fixed-width integers. An object can be a key part only when its class has an `@str` method (the compiler rejects the use otherwise: "objects cannot be printed or converted to text"), and then that text must be different for different values. Checked by `tests/programs/cache_multi.tom` (`('a:1', 'b')`, `('a', '1:b')`, `('', 'a:1b')`, `('a:1b', '')` and `('12', '3')` against `('1', '23')` stay apart).
- Shape of the API (full signatures in the overview of the task): `Cache[K1, ..., R](capacity, ttl, timer)`; `get(k1, ..., default)`, `peek(k1, ..., default)`, `set(k1, ..., value, ttl)`, `delete(k1, ...)` take the key parts one by one; the operators take them as a tuple, `c[k1, k2]` and `(k1, k2) in c`; `keys()` is `list[K]` for one key part and `list[tuple[K1, K2, ...]]` for more. `CacheMiss` says `a is not in the cache` for one part and `(1, 'a') is not in the cache` for several.
- Cost and limits: each operation also builds the key text (one `str` and one concatenation per part) and copies four integers, so a one-part cache is a little slower than the old text-keyed one with an `int` key you had to turn into text yourself. At most four key parts. The compiler's overloads are by number of type parameters only (not by parameter types), and generic generator functions cannot be overloaded.
- Migration: `Cache[int](n)` with text keys became `Cache[str, int](n)`; the keys that were `str(n)` can now be the int `n` itself (`examples/lru_cache.tom`). `memoize` no longer keys by `str(x)`: a float and a text with the same `str` are different keys now, because their types differ.

### D61a — readable errors: color, warnings, call traces: accepted (the task asked for them; the choices below are the agent's)

- Evidence: the task asked for red errors in the terminal and on the website, and for better error checking: unused variables and imports, unreachable code, a missing `return`, use before a value is given, shadowing, duplicate definitions, a list changed while a loop goes through it, runtime errors that say where they happened.
- **Color is only dress.** The words of every message are the plain text of `docs/errors.md`; color adds ANSI codes around the same words, so a program that reads `tomato`'s output sees no change when color is off (the default when standard error is not a terminal). `--color=auto|always|never` (also `TOMATO_COLOR`) and `NO_COLOR` decide; `always` wins over `NO_COLOR` because it was asked for. The compiler writes only plain text; `tomato` (a small `awk` filter, `tomato paint`) colors it, the C runtime colors its own errors (the same codes), and the website colors in JavaScript with CSS classes. Style: `error:` bold red, `warning:` bold yellow, the message bold, `-->` blue and the location cyan, the gutter blue, the caret red (yellow for a warning), `help:` and its text green, call-trace lines dim.
- **Warnings are not errors.** A warning is about code that runs but is probably wrong or useless. It never stops a build, and it never changes the program or its exit status. Errors are reserved for code that cannot work: a missing return on some path (the function would stop at run time), a repeated parameter or method name, an argument of the wrong type. The compiler writes warnings as comment lines (`;! warning: ...`) at the end of the IR, so they travel the same way on the command line and in the browser (a program has one standard output, the IR, and one standard error, the first error); `tomato` shows them on standard error and strips them from `tomato compile`; the playground shows them above the program's own errors; the repl hides them (a session's variables would all be "unused").
- **Warning kinds**, each silenced on its own line with a comment `# allow: KIND`: `unused` (a variable given a value nothing reads, or an imported name never used; a name starting with `_` is meant to be unused, and loop, catch and parameter names are never reported), `unreachable` (a statement after a `return`, `raise`, `break` or `continue`, or after an `if`/`else` or `try` whose branches all leave), `unassigned` (a variable read where some path to it gave it no value), `shadow` (a variable named like a built-in, or like a function, class or constant of the same file), `loop-change` (`xs.append(...)` and similar inside `for x in xs:`). A kind is a word, not a number, so a comment explains itself. There is no switch that turns all warnings into errors in this version (`--no-warnings` hides them; `TOMATO_WARNINGS=off` does too).
- **Quiet on purpose.** When a case is unclear no warning is given (a call that ends a function may never return, so it counts as leaving; values given inside a loop count as given). The compiler, the standard library, the examples and the test programs compile with no warnings, and `tests/run.sh` checks it.
- **A function that gives a value must end every path with a return or a raise** (error). This was a run-time failure ("the function ended without returning a value"); it is now found when compiling. A last statement that is a call is accepted, because the call may be a helper that always raises.
- **Runtime errors show a call trace** in debug mode: `at FUNCTION (line N)` lines, innermost first, the line being where the error was raised and then the line each caller was at (methods as `Class.method`). A `catch` that handles the error discards the trace. At most 24 lines are kept; the rest are counted (`... and N more calls`). `--mode release` prints no trace (its output is a short code).
- **Argument errors name the parameter**: `argument 1 of 'f' (the parameter 'a') has type str, but int is expected`; with a keyword, `argument 'a' of 'f' ...`.
- Not done: a span (a column) for expressions, so some errors still underline the whole call or statement; checking that a function that always raises is used as "never returns"; turning warnings into errors; non-exhaustive cases (the language has no `match`); mutation through other names of the same list.

### D59a — repl: a recalled multi-line block is shown as real lines and edited line by line: accepted

- Evidence: in `tomato repl`, pressing the up arrow after a multi-line block showed it as one line with `⏎` markers (`for i in progress_bar(1000):⏎    if ...⏎        print(i)`). The request was to get the block back as multi-line text, ready to edit and run.
- Why not a true multi-line editor: the repl is bash 3.2 (macOS) without Python. Readline keeps one line per history entry and `read -e` cannot hand back or prefill a multi-line buffer (`-i` needs bash 4), so a real editor with arrow keys across lines is not possible without writing a terminal program; that was rejected as too large.
- Rule: a block is still stored as one history entry (lines joined by `⏎`, so the history file stays plain text). When a recalled entry is entered, the repl prints it as the real block (`>>> ` then `... ` lines, with their indentation) and asks `[Enter] run  [e] edit:`. Enter runs it whole. `e` goes through the lines: Enter keeps a line, Up puts the line into the editor to change it (on bash 4 and later it is prefilled instead), `-` deletes it; after the last line more lines may be added and an empty line finishes, as when typing a block. An edited block is remembered as a new history entry.
- Limit (bash 3.2): no `bind -x`/`READLINE_LINE`, so Up cannot itself show the multi-line form. Cost: the recalled one-line `⏎` form is still what the up arrow shows before Enter, and one extra Enter is needed to run a recalled block. Tested by `tests/repl_history.exp` (pty).
- `from itertools` alone keeps the error `expected 'import', but found the end of the line` with the caret just past the last character; this wording was judged acceptable and no compiler change was made.

### D62a — `std/toml.tom`: reading and writing TOML v1.0.0: accepted (the task asked for the library; the choices below are the agent's)

- Evidence: the task asked for `toml.loads(text)`, `toml.load(path)` and `toml.dumps(value)`, written in Tomato, covering tables, dotted keys, inline tables, arrays of tables, all string forms, integers in four bases, floats including `inf` and `nan`, booleans, the four date/time types, comments and the redefinition rules, with errors that give a line and column.
- **Import form.** `from toml import loads, load, dumps` (a plain `import toml` with `toml.loads(...)` is not in the language yet, D24b). `load(path)` reads the file with `open`; a file that cannot be opened raises `IOError`.
- **dump (file).** `dump(value, path)` writes `dumps(value)` to the file, replacing it, the counterpart of `load(path)`; the text is made before the file is opened, so a non-table value leaves it alone, and an unwritable path raises `IOError`. It takes a path only, like `load`. The json library got the same pair, `load(path)` and `dump(value, path, indent=0, sort_keys=False, ensure_ascii=False)`; `requests` gained `r.json()` (`loads(self.text)`) and `json=` takes a `Json` value (sent as `dumps(value)`) or ready-made text. MessagePack files came later: `load_msgpack(path)` and `dump_msgpack(value, path)` (D66a), on byte-level file functions in the runtime, since `open` is text-only.
- **Value model.** A decoded document is a `Toml`, one class for every kind of value, with a `kind` (`table`, `array`, `string`, `integer`, `float`, `boolean`, `datetime`, `local-datetime`, `local-date`, `local-time`) and the fields that kind uses. Alternatives: a union alias (a class field cannot hold a union and a `dict[str, union]` is not a field type, so a recursive union does not compile) and plain nested `dict`/`list` (not typeable without recursion). Cost: the reader asks for the kind it expects (`doc['server']['port'].as_int()`); a wrong kind or missing key raises a `RuntimeError` that says so. `doc['key']` reads a table (`@get`), `'key' in doc` and `len(doc)` work, `at(i)` and `items` read an array, `put` and `append` build one, and `==` compares whole documents. Tables keep the order the keys were written.
- **Errors.** `TOMLDecodeError` is a `RuntimeError` with `reason`, `line`, `column` (both from 1) and `pos` (character offset from 0); its message is `reason: line L column C (char P)`, the same shape as Python's `json`. Redefinition follows the spec: a key twice, a table twice, a table that dotted keys already defined, a table extended through an inline table or a static array, `[[a]]` over a table or an array value, and a table defined by `[a.b]` being given dotted keys from `[a]` are errors; `[a.b]` followed by `[a]` is allowed.
- **Numbers.** Integers outside the signed 64-bit range are an error, as TOML requires, although `int` has no limit. Hex, octal and binary have no sign; underscores sit between digits; leading zeros are an error. `inf` and `nan` cannot be a Tomato float (the language stops on them), so the value is `kind` `float` with `special` set to `inf`, `-inf` or `nan`, and `as_float()` says so; `-0.0` is kept. A float outside the range of a float is an error.
- **Dates and times.** There is no clock or date type in the language, so the four TOML types are one small class `Moment` (`kind`, `year`, `month`, `day`, `hour`, `minute`, `second`, `nano`, `offset` in minutes) that prints as RFC 3339. Ranges are checked (month, day with leap years, hour, minute, seconds up to 60). The space between date and time, lower-case `t` and `z`, and a fraction of any length (kept to nanoseconds) are accepted.
- **dumps.** Plain values first, then `[table]` sections, then `[[array of tables]]`, each group in insertion order; strings are written as basic strings with escapes, keys are bare when they can be; an array that is not all tables is written inline, with inline tables inside it. `loads(dumps(x)) == x` holds for every document tested. Not kept: comments, key order inside the groups beyond insertion order, and the original spelling of numbers (`0xFF` is written `255`). Floats are written with the runtime's shortest text that reads back as the same value, so floats survive a round trip.
- **Speed.** Reading a character of a text with non-ASCII characters is linear in the text, so the parser goes line by line; for an all-ASCII text the runtime now finds a character in constant time (a one-line change in `char_offset`), which also made `for c in text` linear. A 1 MB document loads, dumps and loads again in about 0.6 s. Arrays and inline tables nested more than 500 deep are an error, so a hostile input cannot overflow the stack.
- Not done: TOML 1.1 additions (`\e`, `\xHH`, optional seconds, newlines in inline tables), a streaming reader, preserving comments on a round trip.

- **List methods and equality (P86).** `pop([i])`, `insert(i, x)`, `extend(ys)`, `sort([key=|cmp=])` and `reverse()` change a list in place; `pop` and `insert` fail with a catchable `RuntimeError` on an empty list or an index out of range (`insert` allows 0 up to `len`, no clamping: Davis chose this over Python's rule), `extend` needs the same list type, and `==` / `!=` compare two lists of the same type item by item. Compact lists (bool, 1/2/4-byte integers) support every method except `sort`, which is limited to `int`, `float` and `str` items as `sorted` is.
- **URL, HTML and binary encodings: `urlparse`, `html`, `base64`, `hex` (D69a, Wave 1 pack 3, API sheet approved).** Four pure-Tomato standard-library modules, all matching Python 3 (verified against Python 3.14 as an oracle: the expected outputs of `tests/programs/url_*`, `html_*`, `base64_codec` and `hex_codec` were generated with it and checked in; no Python is added). `import urlparse` is a flat module (the approved sheet's choice, because nested package imports are not confirmed) and holds `urlparse`, `urlunparse`, `urljoin`, `quote(text, safe='/')`, `unquote`, `urlencode(pairs)`, `parse_qs(query)` and the class `ParseResult` (`scheme`, `netloc`, `path`, `params`, `query`, `fragment`; `str()` shows Python's `ParseResult(scheme='http', ...)`). Parsing follows `urllib.parse` of Python 3.14 (leading control characters and spaces removed, tab and line breaks dropped, scheme rules, `params` only for the schemes Python lists, the `[`/`]` host checks, and `urljoin` including `..`, `.` and the schemes that do not use relative references). Choices where the sheet is open: a malformed bracketed host is a `ValueError` as in Python (E390; the IPv6 syntax check is a small validator written for it), but the NFKC check of a non-ASCII netloc is not done (no Unicode normalization in the language), so such a netloc is accepted; the keyword options of Python (`scheme=`, `allow_fragments=`, `encoding=`, `errors=`, `doseq=`, `keep_blank_values=`, `strict_parsing=`, bytes arguments), `urlsplit`, `urldefrag`, `quote_plus`, `unquote_plus` and `parse_qsl` are outside the sheet and not built; `requests.quote` (no `safe`, nothing kept) is unchanged. `quote` encodes UTF-8 and keeps letters, digits, `_.-~` and the ASCII characters of `safe` (a non-ASCII `safe` character is ignored, as in Python); `urlencode` and `parse_qs` use `quote_plus` and `unquote_plus` semantics (space is `+`); `unquote` decodes escapes per run of ASCII text (a non-ASCII character ends the run, as Python does), keeps a malformed escape as written, and decodes invalid UTF-8 with one U+FFFD per maximal bad sequence. `parse_qs` splits on `&` only, keeps repeated names in order of first appearance, and drops fields whose value is empty (Python's default `keep_blank_values=False`). `html.escape(text, quote=True)` and `html.unescape(text)` follow Python: the escape writes `&#x27;` for `'`; the unescape implements the same scanner as Python's regular expression (names of up to 32 characters, optional `;`, the longest legacy no-semicolon name wins and the rest stays text, numbers without `;`, the HTML 5 repair table for 0 and 0x80-0x9F, U+FFFD for surrogates and numbers above 0x10FFFF, noncharacters and most controls dropped; a number with more than 4,300 digits does not raise as Python's `int()` does but is U+FFFD). The table of 2,231 named references (with the 106 legacy names that need no semicolon) is checked-in Tomato data at the end of `std/html.tom` (about 40 KB, one text of `name=hex` entries made from Python's `html.entities.html5`, then looked up by text search for the first 40 references of a call and by a dict after that, so a page with many references stays linear); every name was compared with Python in all four forms (with and without `;`, with a suffix). `base64.b64encode/b64decode/urlsafe_b64encode/urlsafe_b64decode` and `hex.encode/hex.decode` take and give `list[int]` bytes (no bytes type is decided); the decoders are strict as the sheet says (Python's `validate=True` behaviour: no whitespace or foreign characters, length a multiple of 4, `=` only at the end, at most two; the unused bits of the last character are not checked, as in Python); `urlsafe_b64decode` accepts only `-` and `_` (Python's accepts both and ignores unknown characters, which the sheet forbids). The hex decoder accepts either case (like `bytes.fromhex` and `binascii.unhexlify`) but not spaces (`fromhex` allows them, `unhexlify` does not; the sheet says nonhex input is rejected). Bytes outside 0-255 raise `ValueError` in both encoders. Errors E390-E395. The modules are in the playground's `STD` list and its `std/` copy.

### D70a — `std/random.tom`, `std/secrets.tom`, `std/uuid.tom`: seeded random numbers, secure tokens and UUIDs: accepted

- Evidence: Wave 1, pack 2 of `docs/wave1-api-sheets.md` (approved API contract) and item 4 of `docs/next-features.md`.
- API: `random.Random(seed: int)` with `random`, `seed`, `randint` (inclusive), `randrange(start, stop, step=1)`, `uniform`, `gauss`; `random.choice(rng, items)`, `random.shuffle(rng, items)`, `random.sample(rng, items, k)`; `secrets.token_bytes(nbytes=32) -> list[int]`, `token_hex(nbytes=32) -> str`, `randbelow(n)`; `uuid.UUID`, `uuid4()`, `uuid5(namespace, name)`, `parse(text)`. No module-level state or functions (D47a).
- **Deviation, to confirm:** the sheet lists `choice`, `shuffle` and `sample` as methods with a type parameter (`choice[T](xs: list[T]) -> T`). The compiler does not support generic methods (a method cannot take `list[T]` or return `T`: E313/E314), only generic classes and free functions, so they are free functions taking the generator first (`choice(rng, xs)`), logged as P91 in `docs/provisional.md`. They can become methods when the compiler allows it; the algorithms do not change.
- PRNG: xoshiro128** (four 32-bit words), written in Tomato with `&`, shifts and masks, so the sequence is the same natively and in the browser without a runtime change. The seed is reduced modulo 2**64 (negative seeds work; `-1` is not `1`); SplitMix32 started at `lo xor (hi * 0x85EBCA6B mod 2**32)` makes the four state words (never all zero). It does not match Python's Mersenne Twister, as the sheet allows. `random()` is `(a * 2**26 + b) / 2**53` with `a` the top 27 bits and `b` the top 26 bits of two outputs, as in Python. Numbers below `n` take the top `bit_length(n)` bits of an output (whole outputs, least significant first, above 32 bits) and draw again when too large (no modulo bias); `shuffle` runs Python's loop from the end, `sample` is a partial shuffle of a copy (always the pool method, so equal items by position may both appear). The whole algorithm was cross-checked against an independent implementation of the written specification, and the outputs in `tests/expected` agree to the last digit.
- `gauss` is Marsaglia's polar method with a logarithm written in plain arithmetic (`_ln`, within about 2 ulp of the system's): the system's `sin`/`cos`/`log` can differ in the last digit between glibc, macOS and the browser's libc, which would break "same seed, same numbers" across platforms. This is not Python's Box-Muller formula; the distribution is the same. Seeding or `seed()` clears the stored second value.
- Entropy: one C function `tomato_entropy(out, n)` fills a list with `n` bytes from `getentropy` (the kernel generator natively; WASI `random_get`, served by `crypto.getRandomValues` in `site/wasm/wasi.js`, in the browser). There is no `/dev/urandom` path, no time-based seed and no deterministic fallback: when it fails, `secrets` and `uuid4` raise `RuntimeError` "secure random bytes are not available on this system" (E398). A runtime built with `-DTOMATO_TEST_NO_ENTROPY` always fails, which is how `tests/run.sh` tests that path. `randbelow` takes `ceil(bits / 8)` bytes, drops the extra top bits and draws again when the number is not below `n`.
- Errors (all `ValueError` unless noted; ids E396-E405): `randint` with `b < a`; a zero `step`; an empty `randrange`; an empty `choice`; `sample` with `k` below 0 or above the length; a negative `token_bytes` or `token_hex` length (the message names `token_bytes`); `randbelow` with `n <= 0`; a `UUID` that is not 16 bytes of 0-255; text that `parse` rejects.
- UUID: `UUID` holds `data: list[int]` (16 bytes), `==` and `str()` (32 lower case hex digits as 8-4-4-4-12). `uuid4` sets the version nibble to 4 and the variant bits to 10; `uuid5` is the first 16 bytes of SHA-1(namespace bytes + UTF-8 name) with version 5 and variant 10, checked against RFC 9562 and Python's `uuid.uuid5` (the outputs are identical, including multi-block names and non-ASCII text). `parse` accepts what Python's `UUID(text)` accepts (hyphens anywhere, braces, `urn:uuid:`, any letter case) but only real hex digits (Python's `int(text, 16)` would also let `0x`, signs, spaces and underscores through in some spots). The constructor `UUID(data)` is public only because a class needs one.
- Left out: `uuid1`, `uuid3`, `UUID.version`/`.variant`/`.int`/`.hex`, namespace constants, a module-level generator, `getrandbits`, `choices`, `triangular`, `betavariate` and the other distributions, `SystemRandom`, `randbytes`, a `Random` state export.
- Browser: `tests/run.sh` runs the new programs through the wasm path, which needs `site/wasm/runtime.wasm` rebuilt with the new C function (`site/wasm/build.sh`).

### D73a — `std/datetime.tom`: `date`, `time`, `datetime` and `timedelta` with fixed offsets: accepted (Wave 1 pack 5; the API sheet in `docs/wave1-api-sheets.md` was approved before building)

- Evidence: `docs/wave1-api-sheets.md` section 5, checked against Python 3.14 as an oracle only: the test programs `datetime_arith`, `datetime_format` and `datetime_parse` have expected files generated by Python's `datetime` (about 400 arithmetic cases, 400 format cases, 320 parsing cases); no Python is in the repository.
- API: `from datetime import date, time, datetime, timedelta, date_fromisoformat, time_fromisoformat, datetime_fromisoformat, datetime_strptime, date_today, datetime_now`. Years 1 to 9999 (proleptic Gregorian), no time zone database, no daylight saving; an offset is a whole number of minutes strictly between -24 and +24 hours. Parts are `const` fields (read-only: assigning one is a compile error): `year month day`, `hour minute second microsecond`, and for a datetime `offset_minutes` (0 when naive) and `is_aware`; `timedelta` keeps `days`, `seconds` (0 to 86399) and `microseconds` (0 to 999999), normalised as Python does (`timedelta(0, -1)` is -1 day, 86399 seconds). `weekday()` (Monday 0), `isoformat()`, `strftime(fmt)` and `str(x)` as Python (a datetime's `str` has a space, a timedelta's is `1 day, 2:03:04`).
- Operators: `+` a `timedelta` to a date or datetime, `-` between two dates or two datetimes gives a `timedelta`, `+` and `-` between two timedeltas, and `== != < <= > >=` between values of the same kind. A date adds only the whole `days` of a timedelta (Python's rule); a datetime adds all of it, exactly, keeping its offset. A result before year 1 or after year 9999, or a timedelta of 1000000000 days or more, is an `OverflowError` (E407). Aware datetimes compare and subtract by the UTC instant, so `10:00+01:00 == 09:00+00:00`.
- Naive against aware: `<`, `<=`, `>`, `>=` and `-` raise `ValueError` (the sheet; Python raises `TypeError`), `==` is `False` and `!=` `True` (as Python).
- **What the language could not do, and what was done instead (nothing in the sheet changed in meaning):** (1) A class has one marker per operator, so `-` cannot be both date-minus-date and date-minus-timedelta (a union operand would make `(b - a).days` need a narrowing first). `-` between same kinds gives the timedelta, and taking a duration away is `x.minus(delta)` (or adding a negative timedelta); `minus` is the one name added to the sheet. (2) Constructors take positional arguments only (keyword arguments are not supported when creating an object), so `timedelta(days=1)` is written `timedelta(1)` and an offset is the eighth argument of `datetime`. (3) A parameter or field cannot be `int | None`, so `offset_minutes` is `int | bool` with the default `False` meaning naive (`True` is a `ValueError`); the read-only field is an int, and `is_aware` tells naive from UTC. (4) Properties are `const` fields, not computed properties.
- Parsing reads what `isoformat` writes: `2024-03-09`, `16:30`, `16:30:00.123456`, `2024-03-09T16:30:00+05:30` (any one character as the separator, a time may stop after the hour or minute, any number of fraction digits with the first six used, offsets `Z`, `+HH`, `+HHMM`, `+HH:MM`, `+HH:MM:00`). Not read although Python 3.11+ reads them: the basic form `20240309`, `24:00`, `,` as the fraction mark, an offset with non-zero seconds, `+05:60`, and a time with an offset (a `time` has none): all are a `ValueError` (tests/runtime/datetime_errors).
- `datetime_strptime(text, format)` knows `%Y %m %d %H %M %S %f %z %%`; it follows Python's patterns, including their alternatives and backtracking (`'131'` is month 1, day 31 for `%m%d`), digits only in ASCII, letters of the format match either case and a space matches a run of white space; `%z` reads `Z`, `+HHMM` and `+HH:MM` and makes the result aware. Other directives, a repeated directive, a stray `%`, a format without `%Y`, `%m` or `%d` (Python would default to 1900-01-01), text that does not match, and trailing text are a `ValueError`.
- `strftime` knows `%a %A %w %u %d %e %b %B %h %m %y %Y %C %H %I %p %M %S %f %z %Z %j %U %W %V %G %g %c %x %X %F %T %R %D %n %t %%` with the C-locale words; `%Y` and `%G` are at least four digits as in Python, `%c` has the year unpadded as the C library writes it; any other directive (`%Q`, `%E`, glibc flags such as `%-d`) and a trailing `%` are written as they are. For a naive value `%z` and `%Z` are empty; `%Z` of an aware value is `UTC` or `UTC+HH:MM`. A `time` has the date 1900-01-01 and a `date` the time 00:00:00.
- `date_today()` and `datetime_now()` use the UTC clock (`time_ns`); `datetime_now()` is aware with offset 0. The module reuses `timegm` and `gmtime` of `std/time.tom` for the calendar maths.
- Added later (outside the sheet, checked against Python in `tests/programs/datetime_extra.tom`): `timedelta.total_seconds()`, `td * int` (`@mul`, int on the right only), `td.negated()` (no unary minus on classes), `datetime.replace(...)` by keyword (`offset_minutes` makes a value aware or moves its offset), `datetime.timestamp()` (a naive value is read as UTC) and `datetime_combine(date, time[, offset_minutes])`.
- Not built: `timedelta` division and `*` by a float, `date`/`time` extraction from a datetime, `date.replace`/`time.replace`, `fromtimestamp`, `isocalendar`, `utcoffset`/`tzinfo`, `astimezone`, `strptime` directives beyond the sheet, `date.fromisoformat` basic forms, `min`/`max` constants, hashing of the classes. `toml.Moment` stays a separate type.

### D74a — `std/csv.tom`, `std/textwrap.tom` and `std/statistics.tom` (Wave 1 pack 4): accepted (the API is the approved sheet in `docs/wave1-api-sheets.md`; the choices below where the sheet is silent are the agent's)

- `from csv import reader, writer, dict_reader`: `reader(text, delimiter=',') -> list[list[str]]`, `writer(rows, delimiter=',') -> str`, `dict_reader(text, delimiter=',') -> list[dict[str, str]]`. The parser is Python's `csv` in strict mode (checked against real Python 3 as an oracle): a field may be quoted, `""` inside is a quote, a quote inside an unquoted field is plain text, a record ends at `\n`, `\r\n` or `\r` outside quotes and quoted fields keep their line breaks. A blank line is an empty row (`[]`), and a line break at the very end starts no extra row. Text after a closing quote (`"a"b`) and a quoted field that is never closed raise `ValueError` (E409, E410), as does a delimiter that is not one character or is a quote or line break (E408). The writer ends every row with `\r\n`, quotes only fields holding the delimiter, a quote, `\r` or `\n`, and writes a row of one empty field as `""` (as Python does, so it is not read back as a blank line).
- `dict_reader`: the first row gives the headers; blank lines are skipped, including before the headers (Python would take a blank first line as an empty header row, which is never useful); a repeated header keeps its first place and the last field; a short row gets empty text (Python's default is `None`, which a `dict[str, str]` cannot hold); a row with more fields than headers raises `ValueError` (E411; Python stores the extra fields under a `None` key).
- `from textwrap import wrap, fill, dedent, indent, shorten`, with Python's defaults and algorithm: tabs expand to 8 columns, `\n \r \v \f` become spaces, only ASCII whitespace separates words in `wrap` and `fill` (a no-break space is part of a word), words break after hyphens inside them and around `--`, and a word longer than the width is cut. `shorten`, `dedent` and `indent` treat any Unicode space (`str.isspace()`) as whitespace, as Python does. A width below 1 raises `ValueError` (E412); `shorten` raises `ValueError` (E413) when its placeholder without leading spaces is wider than the width (Python's own test, a little weaker than "longer than width" when the placeholder starts with spaces). Where Python's regular expression uses `\w`, the word characters are letters (`isalpha`), digits (`isdigit`) and `_`; the few numeric characters Python counts as word characters that Tomato's `isdigit` does not (such as fractions) are not treated as word characters.
- `from statistics import mean, median, mode, variance, stdev, quantiles` on `list[float]`. `mean`, `variance` and `stdev` use exact integer arithmetic (every float is a whole number over a power of two) and round once at the end, the way Python's `statistics` does with fractions, so results match Python to the last bit (300 random vectors and the test vectors were compared with Python 3.14); `stdev` uses Python's correctly rounded square root of the exact fraction. The built-in `/` is not used for the final division because it refuses whole numbers too big for a float even when the quotient is small; a private `_divide` rounds the quotient once instead (a subnormal result is rounded twice). `median` averages the two middle values of an even list in float arithmetic, as Python does. `mode` returns the most common value, the first one in the list on a tie. `quantiles(xs, n=4)` is the exclusive method with Python's integer interpolation. Empty data raises `ValueError` (E414); fewer than two values for `variance`, `stdev` and `quantiles` raise `ValueError` (E415); `n < 1` raises `ValueError` (E416). One deliberate difference from Python 3.14: `quantiles` of a single value is an error (the sheet says so) where Python returns that value repeated.
- Not built: `csv` quoting modes, `escapechar`, `skipinitialspace`, `dialect`s and file objects (use `open` and read the text), `DictWriter`, `TextWrapper` and its options (`initial_indent`, `max_lines`, `break_long_words`, `fix_sentence_endings`...), `indent` with a predicate, `fmean`, `geometric_mean`, `harmonic_mean`, `pstdev`, `pvariance`, `multimode`, `NormalDist`, `correlation`, `inclusive` quantiles, and `string` constants and `logging` (outside this pack).

### D75a-d — Wave 1, pack 1: `round`, `divmod`, `any`, `all`, more text methods, more `math`, and f-string format specs: accepted (the task implements the approved sheet in `docs/wave1-api-sheets.md` section 1; the choices below, where the sheet is silent, are the agent's)

- Evidence: the approved API sheet "Everyday built-ins, text and math". Python 3.14 was the oracle for every expected output (the committed files hold only the generated output, no Python): `tests/programs/round_divmod_any_all`, `text_methods_more`, `math_more` and `fstring_specs` print what Python prints for the same lines; a further 13,000 generated format cases and 1,475 `round` cases (not committed) agreed as well. `hash` is deferred, as the sheet says.
- **D75a, built-ins.** `round(x)` gives an `int`, a tie going to the even neighbour (`round(2.5)` is 2, `round(3.5)` is 4), for any float, however large (the int is exact). `round(x, ndigits)` gives the type of `x`: for a float, the float nearest to `x` with that many digits after the decimal point (before it when `ndigits` is negative), judged on the exact value of `x`, so `round(2.675, 2)` is 2.67 and `round(0.125, 2)` is 0.12; for an `int`, a non-negative `ndigits` changes nothing and a negative one rounds to tens, hundreds and so on with ties to even (`round(25, -1)` is 20). `ndigits` may be written as a keyword. Only a plain `int` or `float` is accepted (not a value typed `int | float`, and not a fixed-width integer). A result that is too large to be a float raises `OverflowError`. `divmod(a, b)` takes two ints and gives a `tuple[int, int]` of the floor quotient and the remainder (the remainder has the sign of `b`; `ZeroDivisionError` for 0). `any(xs)` and `all(xs)` take a `list[bool]` (not a general iterable). A program's own function named `round`, `divmod`, `any` or `all` still wins over the built-in. Because `-> tuple[int, int]` is a mixed tuple type (D64a-style, P89), the result unpacks (`q, r = divmod(a, b)`) and indexes, but cannot be compared with a tuple literal (`== (3, 1)`); compare the items.
- **D75b, text methods.** `splitlines(keepends=False)`, `partition(sep)`, `rpartition(sep)`, `rsplit(sep='', maxsplit=-1)`, `zfill(width)`, `ljust`, `rjust` and `center(width, fillchar=' ')`, `title()`, `capitalize()`, `isalnum()`, `removeprefix(prefix)` and `removesuffix(suffix)`, as Python, with these exceptions: an empty separator for `partition`/`rpartition` and a fill character that is not exactly one character raise `ValueError` (Python's `TypeError` for the fill); `rsplit` with the default empty `sep` splits on whitespace as Python's `rsplit()` does (the empty text cannot be a separator in `rsplit`, so there is no ambiguity). They are written in Tomato (`std/builtin/text.tom`, `_str_NAME`) and the compiler calls them like methods, so keywords and the messages about arguments name the method. `splitlines` ends a line at every Python line boundary (`\n`, `\r`, `\r\n`, `\v`, `\f`, the separators 28 to 30, NEL 133 and the Unicode line and paragraph separators 8232 and 8233). Whitespace for `rsplit` is the same four characters as `strip()` (space, tab, newline, carriage return). **Unicode limitations** (the casing and classification tables are the runtime's, D17d and P89): `title()` and `capitalize()` use the simple case mapping, so `'ß'.title()` stays `'ß'` (Python: `'Ss'`) and the digraph letters `'ǆ'` capitalize to `'Ǆ'` (Python: `'ǅ'`); a letter counts as part of a word when its upper and lower case differ; `isalnum()` is letters (`isalpha`) and digits (`isdigit`), so a character that Python only counts as numeric (such as `'½'`) is not alphanumeric here.
- **D75c, f-string format specs.** `f'{value:spec}'` with the spec `[[fill]align][sign][0][width][,][.precision][type]`: `align` is `<`, `>` or `^`; `sign` is `+`, `-` or a space; the types are `s`, `d`, `f`, `e`, `g` and none; width and precision are decimal literals of at most nine digits. Not built: `=` alignment written out, `z`, `#`, `_` grouping, the types `b c o x X E F G n %`, nested fields in a spec (`{x:{w}}`), `!r`, `!s` and `{x=}`. The lexer checks the form of the spec (a compile error with the column of the mistake) and turns the field into the call `_format_spec(value, 'spec')`; the compiler checks the spec against the type of the value and calls `_fmt_str`, `_fmt_int` or `_fmt_float` of `std/builtin/format.tom`; a spec is never read at run time. `{x:}` is `{x}`. Text accepts fill, align, width, precision (it cuts the text) and the type `s`; a sign, `,` or a number type on text is a compile error. An `int` (a fixed-width integer counts as an `int`) accepts everything but `s`; a precision needs the type `f`, `e` or `g`, which format the number as a float (a number too big for a float raises `OverflowError`, as in Python). A `float` accepts everything but `d` and `s`. A `bool`, a list, an object or anything else is a compile error ("make text with `str()` first"): Python formats a `bool` as the int 1 and refuses a spec on most objects, and neither suits Tomato. Defaults follow Python: numbers align right, text left; a `0` before the width pads after the sign with zeros (and, as in Python, with `,` the zeros are grouped and no comma starts the number, so `f'{1234:08,}'` is `0,001,234`); with an explicit alignment the `0` only chooses the fill; `f`, `e` and `g` use precision 6 unless one is written, and `e` has at least two exponent digits; no type on a float gives the shortest text that reads back (`1e+16`, `1.5`), and with a precision but no type it is `g`-like with the `.0` kept on whole numbers and the exponent form starting one place earlier (`f'{123.0:.3}'` is `1.23e+02`, as Python); a negative zero or a negative number that rounds to zero keeps its minus sign (`f'{-0.001:.1f}'` is `-0.0`). Digits are exact and rounded half to even on the exact binary value (`f'{2.675:.2f}'` is `2.67`, `f'{0.125:.2f}'` is `0.12`), from the C library's `printf` through `tomato_float_format` (glibc, macOS and the WASI C library all print exactly). Large integers (heap numbers) are formatted from their exact digits.
- **D75d, `math`.** `floor`, `ceil` and `trunc` take an `int | float` and give an `int` (exact, however large); `isnan`, `isinf` and `isfinite` give `bool`; `copysign(x, y)` gives a `float` (a `-0.0` counts as negative); `factorial(n)`, `comb(n, k)`, `perm(n, k)` (both arguments required: no default `k` as in Python 3.8+), `isqrt(n)` (exact for any size), `fsum(xs)` (Shewchuk's exact summation as Python's `fsum`, including the half-even correction) and `prod(xs)` (of ints; 1 for an empty list). A negative `n` or `k` raises `ValueError`; `k > n` gives 0 for `comb` and `perm`. A float in Tomato is always finite (an operation that would give infinity or NaN stops with an error), so `isnan` and `isinf` are false for every float and `isfinite` true; an `int` beyond the float range raises `OverflowError` in these three and in `copysign`, as in Python.
- Run-time pieces: `tomato_float_round(x, ndigits)` (`round` of a float, exact; `ndigits < 0` works on every digit of `x`) and `tomato_float_format(x, precision, kind)` in `runtime/tomato_rt.c`; the WebAssembly runtime must be rebuilt for them (`site/wasm/build.sh`), as for any runtime change. New std error ids: E417 to E423 and E436; compile errors E424 to E435 (E159 now says a format option is not supported).

### D78a — dict keys and set elements of any hashable type, `@hash` and `hash()`: accepted

- Evidence: Davis asked for "dictionaries should accept keys of any type, using @hash when implemented", then answered four questions: the method is `@hash def h(self) -> int` and a builtin `hash(x) -> int` exists ("`@hash def h(self) -> int` plus a builtin `hash(x) -> int`"); a class with `@eq` but no `@hash` is a compile error as a key; `list`, `set` and `dict` as keys are a compile error; and `set[K]` takes the same keys as `dict[K, V]`. About the identity fallback he first wrote "using @hash when implemented and otherwise the object's identity", then "remove the thing about defaulting to id", and chose "No identity fallback: a class without `@hash` cannot be a dict or set key".
- A dict is `dict[K, V]` and a set `set[K]` for any `K` that is `int` (any size), `bool`, `float`, `str`, a fixed-width integer (`int[length=8]`, `uint[length=16]`, ...), a tuple (`tuple[T]` or `tuple[A, B]`) whose items are keys, a class that has a method marked `@hash`, or an optional (`T | None`), a union (`int | str`) or an interface value built from those. Everything else is a compile error that says why: a list, set or dict "can change, so it cannot be a dict key or set element" (use a tuple); a class without `@hash`; a class with `@eq` but no `@hash`; a function, task, file or `Iterable`/`Sized` value (nothing gives them a value to hash). The check is made when the type is written (the form) and when a table of that type is first made or used (a class's `@hash`).
- Optional, union and interface keys: `None` hashes to 0 and equals only `None`. A union value is hashed by the member it holds, mixed with the member's place, and equals another only when it holds the same member type with an equal value (`1`, `True` and `1.0` are three different keys of `int | bool | float`). Davis chose this tagged rule over Python's, so it differs from `==` (where `1 == 1.0`); `hash(1) == hash(1.0)` still holds. He also approved the interface-key rule and `frozenbitarray` as a key. An interface value is hashed and compared by the class of its object, so every class that implements the interface (and whose parent does not) must have a `@hash`, else it is a compile error naming the class; two objects of unrelated classes are never equal, and an object of a subclass is compared as its implementing class (its `@eq` and `@hash` run, with overrides). Fixed-width integers are keys by value, in their own type (`d.keys()` is a `list[int[length=8]]`; a fixed-width dict value is still not built).
- `@hash` is an operator marker (D12j-l): a method that takes nothing besides `self` and returns an `int` of any size. A class that has `@hash` and `@eq` is compared by its `@eq`; one with `@hash` and no `@eq` is compared by identity (objects are equal only to themselves, so equal keys always have equal hashes). A subclass runs its own overriding `@hash` and `@eq`. `hash(x)` works on every key type: an `int` in the 62-bit small range is its own hash, `bool` is 0 or 1, a float with a whole value hashes as the equal int (`hash(1.0) == hash(1)`, as in Python), other floats, text and bigger numbers are mixed from their value (stable within a run, no other promise), a tuple mixes its items' hashes, and an object's is what its `@hash` returns. `hash()` of anything else is a compile error. It is the way a class's `@hash` hashes its fields: `return hash(self.x) * 31 + hash(self.y)`.
- Equality of keys: `int`, `bool`, `str` and tuples compare by value as `==` does; a float key compares as `==` does, so `0.0` and `-0.0` are one key. A float in Tomato is always finite (an operation that would give infinity or not a number stops with an error), so there is no `nan` key to decide about. A table keeps the hash it computed when a key was added: changing the fields an object's `@hash` reads while it is a key makes it unfindable by its new value (still listed by `keys()` and `for`), as in Python. An error raised by `@hash` or `@eq` while a table is searched reaches the caller, and the table is left as it was.
- Tables keep order of insertion (D20b). A key that is a heap value (text, object, tuple) is retained by the table and released when its entry is removed or the table is freed; a big number is copied; the cycle collector follows keys (a table with object keys is a possible root of a cycle even when its values hold no references), so an object that is a key of a table it can reach is freed with it. `print(d)`, `str(d)` and f-strings read a dict's entries by position, so they work even for a key that was changed after it was added. A literal infers its key type from its first key (`{(1, 2): 'a'}` is a `dict[tuple[int, int], str]`); `**kwargs` stays `dict[str, V]`. `for k in d`, `d.keys()` and `d.items()` give keys of the key type.
- Implementation: a dict type is written `dict[K,V]` inside the compiler (it was `dict[V]`, the key implied to be text). The runtime table has key kinds: word (bool), text, int, float, and object (class instances and tuples). For an object key the compiled code computes the hash (a helper written in Tomato from the type), walks the entries whose stored hash is equal (`tomato_dict_next`) and compares each with the key's own `==` (a helper too), then calls `tomato_dict_insert_h`/`tomato_dict_delete_h`/`tomato_dict_slot_at` with the place found. The C runtime never calls compiled code, so the browser's IR interpreter needs no callback. A hash from user code is scrambled before the table uses it, so a poor `@hash` (multiples of 1024) does not make every key collide; stored hashes are compared in full before `@eq` runs.
- `frozenbitarray.hash()` is now marked `@hash`, so a frozenbitarray is a dict key and a set member (`key()` still works).
- Not built: `==` on dicts and sets (unchanged); printing a dict or set whose keys are optional (the same limit as a list of optionals).

### D79a — `re` (Wave 2 pack C): accepted

Davis approved section 3 of `docs/wave2-api-sheets.md`, including C-Q1 through C-Q6, on 24 November 2026. The pure-Tomato module compiles patterns to an integer program and uses an explicit backtracking stack, with character positions and the same implementation in native and browser programs. `Pattern.step_limit` defaults to 20,000,000 matcher steps plus 16 for each character of the text; exhausting it raises `RegexError`. Module functions compile on every call, so reuse a `Pattern` in a loop. Flags use Python's numeric values (`I`, `M`, `S`, `X`, `A` and their long names).

The API provides `compile`, `match`, `search`, `fullmatch`, `findall`, `findall_groups`, `finditer`, `sub`, `subn`, `sub_with`, `split` and `escape`. `findall` always returns whole matches, `findall_groups` returns lists of captures, and `finditer` is eager. `Match.group` returns empty text for a group that did not participate; `matched` distinguishes it from a participating empty group. `start`, `end` and `span` give character offsets and -1 for a nonparticipating group. `split` includes capture texts and substitutes empty text for unmatched captures. Replacement templates accept numbered and named references; callbacks passed to `sub_with` are named functions and do not close over locals.

The syntax supports literals, classes, shorthands, anchors, groups, backreferences, alternation, greedy and lazy repetition, lookahead, fixed-width lookbehind, inline flags and verbose mode. Possessive quantifiers, atomic groups, conditionals, `\G`, Unicode properties, locale/Unicode flag letters and `\N{name}` are rejected. Unicode character categories use Tomato's `isalpha`/`isdigit`/`isspace` tables: `\d` includes some non-decimal digits, and `\w` omits some numeric characters Python includes. Ignore-case uses one-character simple case mappings, not multi-character folds. Bad patterns and replacement templates raise `RegexError` with `pos` (E486–E494); bad flags raise `ValueError` (E495); an invalid group key raises `IndexError` (E496). See `docs/regex.md`.

## Pending discussion

The simplicity/performance direction is accepted in D02a–D02b. Other priorities, including correctness, build time, and distribution, remain open.

Numeric details remain open: detailed width-expression rules, representation, overflow error handling, analysis outside D05x, contextual typing beyond D05s–w’s literal-only arithmetic rules, remaining arithmetic rules beyond D05s–w, D05y–aj, and D05at, remaining division/modulo rules under D05y, and resource-exhaustion behavior. Compiler implementation and merging this task remain outside the authorized scope.

Remaining interface details are queued: duplicate declarations, exact import/export syntax, re-exports, processing phase, and interface inheritance. The basic declaration choices are settled, but the interface model is not complete.

Current queue: class details (initialization/defaults, other modifier placement and init writes, @init allocation/receiver model, @add operand/result rules, construction, overriding and member compatibility), remaining interface details, detailed inference, web-app host integration, integer quotient/modulo and remaining numeric rules, and priority/release scope. The classes and integers are not complete.

## Public page status

The earlier public decision page, its password-protected chat and the chat bridge are retired and their code (`site/`, `static/`) has been removed from the repository. They are not to be restarted or redeployed. Decisions are read from these Markdown files; the local Python playground in `web/` is separate and holds no chat.

### D62a — the `requests` library: HTTP over the system libcurl, awaited and concurrent: accepted

- Evidence: Davis asked for a `requests`-style HTTP client and answered five design questions: load libcurl at run time, really concurrent requests, a response with fields for data and methods for work, Python-style error classes with no raise on 4xx/5xx, and native only with a clear error in the browser. (`import module` and `module.name` were added for it, following D24b.)
- `import requests` then `r = await requests.get(url)`; also `post`, `put`, `patch`, `delete`, `head` and the general `request(method, url, ...)`, all `async`. Keyword arguments: `params` (dict added to the query), `data` (text body), `form` (dict sent as an HTML form), `json` (JSON text for now; `r.json()` waits for the json library), `headers`, `timeout` (a float in seconds, 0 means none), `follow_redirects` (default True except `head`) and `max_redirects` (20).
- `Response` has the fields `status`, `ok`, `url` (after redirects), `text` (bytes that are not UTF-8 become U+FFFD), `content` (a list of byte values) and `headers` (lower-case names, a repeated header joins its values with `, `), and the method `raise_for_status()`.
- Errors: `RequestError` (an `IOError`) is the base; `ConnectionError` (DNS, refused, dropped, TLS), `TimeoutError`, `InvalidURL`, `TooManyRedirects`, and `HTTPError` (only from `raise_for_status()`, with `.status`). A 404 or 500 does not raise by itself. The names are written `requests.TimeoutError` and so on.
- Implementation: the C runtime loads libcurl with `dlopen` when the first request starts (no header, no link flag; a missing libcurl raises `ConnectionError` saying so, and other programs are unaffected) and drives curl's multi interface from the scheduler: a task waits with the compiler's hidden `await _http_wait(handle)`, and when nothing else can run the scheduler waits for the network (up to the first sleeper's wake-up), so requests overlap with each other and with other tasks. HTTPS, gzip and chunked encoding come from libcurl. A request body is text.
- `import module`: after `import m`, `m.name` names an exported name of `m` (the parser joins the tokens into one name); the module's names are not brought in bare. `from m import a` is unchanged.
- The browser playground has no sockets: every request raises `ConnectionError` ("requests is not available in the browser playground"). Open: browser support through the page's own networking, a binary request body, cookies and sessions, and `r.json()`.

## Template for subsequent decisions

- ID and title:
- Status:
- Question and concrete example (mark unapproved syntax):
- Relevant requirements and dependencies:
- Options, recommendation, and tradeoffs:
- Davis's decision and evidence:
- Exact accepted rule, if any:
- Consequences and affected decisions:
- Remaining questions:
- Supersedes / superseded by:

### D63a — function values, lambdas, `sorted(key=, cmp=)`, `map` and `filter`: accepted (Davis chose each point below)

- Evidence: TODO.md and open question 65 ("functions as values: lambdas, closures, passing functions"); `map` and `filter` waited on them, and `sorted` with a compare or key function needed a callback. Davis answered one question per point.
- Type: a function value has the type `fn(int, int) -> int`; with no `->` it returns nothing (`fn(str)`). It can be a local, parameter, return value, list item or class field, and is called like a function: `f(1, 2)`, `self.op(a, b)`, `fs[1](4)`. A call checks the argument count and types with the usual messages ("the function value 'f' takes 1 argument, but 2 given"). Function types must match exactly (no conversions). Keyword arguments and defaults do not apply to a function value.
- Named functions are passed by name: `apply(double, 5)`, `f = double`. Not passable yet: methods and bound methods (`obj.method`), generic functions, async functions, generators and functions with `*args`/`**kwargs`.
- Lambdas: `x -> expr` and `(a, b) -> expr`, one expression. Parameter types come from where the lambda is used (a parameter, a typed variable, the item type for `sorted`, `map`, `filter`); the result type is worked out from the body when the context does not give it (`sorted(xs, key=x -> x.age)`). A lambda written where no function type is expected is an error. There are no closures: a lambda may use its own parameters and global names, and using a local of the enclosing function is a compile error ("a lambda cannot use the variable 'k' ..."). A function value is therefore a plain code pointer, with no environment and no reference counting.
- Not comparable (`f == g` is an error), not printable or convertible to text, not allowed as `fn(...) | None`, and not a dict key or set item.
- `sorted(xs, key=f)` sorts by `f(item)`, called once per item; the keys must be `int`, `float` or `str`. `sorted(xs, cmp=f)` takes `f(a, b) -> int`, negative when `a` comes first. Giving both, or another keyword, is an error. Both are stable and give a new list; plain `sorted(xs)` is unchanged (native introsort). `map(f, xs)` and `filter(f, xs)` give new lists (not iterators); `f` takes one item, and for `filter` returns `bool`. Lists and objects with `@iter` are accepted, like `sorted`.
- How it works: the key sort calls the key function from Tomato code (`std/builtin/sorting.tom`), and the runtime sorts the keys with a stable merge sort and gathers the items (no callback from C, so it behaves the same in the browser); the compare sort is a stable run-detecting merge sort (binary-insertion runs, merging, no galloping) written in Tomato in `std/builtin/sorting.tom`, as are `map` and `filter` (`std/builtin/lists.tom`). An error raised in a callback stops the sort and propagates like any error, with nothing leaked. Lambdas become ordinary functions named `_lambdaN`.
- Not built: closures, bound methods as values, generic functions as values, optional function values, comparing functions, galloping in the merge.

### D64a — `bitarray` and `frozenbitarray` (`std/builtin/bitarray.tom`), and the operator markers they need: accepted

- Evidence: Davis asked for "byte and bytes types" for the MessagePack work, then "actually bit array", then narrowed it to two types: `bitarray` (mutable, packed) and `frozenbitarray` (immutable, hashable); no `byte`, `bytes` or `bytearray`. He chose the constructors by example: `bitarray(8)` is `1000`, `bitarray.from_hex('A2')`, and `bitarray.zeros(8)` ("actually zeros"); he did not like bare `b100`/`bxA2` literals, so there is no literal syntax. He asked for a method marker `@bitarray` that turns a class into a bitarray ("@bitarray method to for a function to turn in bitarray", reading to confirm).
- It is a library module like `rational`, written in Tomato, but needs no import (Davis: "available without an import"): a file that mentions `bitarray` or `frozenbitarray` gets `std/builtin/bitarray.tom` loaded and both names bound, and an explicit `from bitarray import bitarray, frozenbitarray` also works. Programs that do not use them do not compile it. The bits are stored 32 to a whole-number chunk in a list (small numbers are unboxed words, so no chunk allocates); the C runtime supplies `tomato_popcount`; whole-array operations (`& | ^ ~`, `count`, `find`, `==`, `hash`) work a chunk at a time.
- Bit 0 is the leftmost bit, the first one written in the text (most significant in a byte or hex digit). `bitarray('1011')`, `bitarray([True, False])`, `bitarray(8)` (the binary digits of a whole number, no leading zeros, `bitarray(0)` is `0`), `bitarray(8, 8)` (with a width, an error if it does not fit), `bitarray.zeros(n)`, `bitarray.from_hex('A2')` (four bits a digit), `bitarray.from_ints(xs, nbits)` (eight bits a byte, a list of 0 to 255; there is no bytes type) and `bitarray(other)` (a copy).
- Operations: `len`, `a[i]` and `a[i] = bit` (negative indexes count from the end; out of range is a `RuntimeError`), slices with the list rules (`a[1:3]`, `a[::-1]`), `for bit in a`, `bit in a`, `==`, `& | ^` (equal lengths) and `~`, `shift_left(n)`, `shift_right(n)`, `append`, `extend`, `count`, `any`, `all`, `find(bit, start)`, `copy`, `freeze`, `to_list`, `to_ints`, `to_hex`, `to_int`, and `str(a)` is the bits (`'1011'`).
- `frozenbitarray` is a separate type with the reading operations, plus `hash()`, `key()` (the bits as text, usable as a dict key) and `thaw()`; it has no `a[i] = bit`, `append` or `extend`. The two types do not mix in operators (a compile error); `frozenbitarray(a)`, `a.freeze()` and `f.thaw()` convert. Since D78a it can be a dict key and a set member (its `hash()` is marked `@hash`); `key()` still gives the bits as text.
- Language changes this needed: new operator markers `@bitand`, `@bitor`, `@bitxor` (for `& | ^` on a class), `@invert` and a new unary `~` (only for classes with `@invert`; `~` on a number was an error here and was added later by D67a), `@set` (for `obj[i] = value`), `@static` (a method called on the class, `bitarray.from_hex('A2')`; it runs on a throwaway object made by the class's `@init` called with no arguments, so the class needs an `@init` that works with no arguments) and `@bitarray` (a method with no arguments returning a bitarray: objects of that class are accepted wherever a bitarray is expected).
- Not built: bit order choice (always big-endian within a byte), hashing for sets of a frozenbitarray, a binary file mode, a `bytes` type.
- Later the file moved from `std/bitarray.tom` into the built-ins folder, `std/builtin/bitarray.tom` (see D24a); it is still the module `bitarray`, loaded only when used, and every way of naming it works as before.
### D68a — `std/time.tom`: wall clock, monotonic clock, UTC calendar maths and formatting: accepted (the task asked for a `time` module "modelled on Python's `time`"; the choices below are the agent's, built on a draft a review of the code-cleanup task wrote unasked)

- Evidence: Davis asked for a `time` module in the standard library like Python's: wall-clock time, a monotonic clock for timing, sleep, and simple formatting where it fits the language's std style. Asked nothing further; the points below are the agent's and are open to change.
- `from time import time, time_ns, monotonic, monotonic_ns, gmtime, timegm, mktime, strftime, asctime, ctime, isoformat, format_duration, Time, Stopwatch`. `time()` is the wall clock as float seconds since 1970-01-01 00:00:00 UTC and `time_ns()` the same in exact `int` nanoseconds (a float has no room for them); `monotonic()` is the built-in `clock()` (D62a) and `monotonic_ns()` the same clock in `int` nanoseconds. Three small C runtime functions back them (`tomato_time`, `tomato_time_ns`, `tomato_clock_ns`, using `clock_gettime`); in WebAssembly both clocks read `Date.now()`, so they have millisecond resolution there.
- `gmtime(seconds)` gives a `Time` with `year`, `month`, `day`, `hour`, `minute`, `second`, `weekday` (0 is Monday, as in Python) and `yearday` (1 is January 1st), rounding a fraction of a second down (also before 1970); `timegm(year, month, day, hour, minute, second)` and `mktime(t)` are its inverse (no range checks: 13 months or 70 seconds carry over). The proleptic Gregorian calendar is used for every year, by Howard Hinnant's integer algorithms, so there is no table and no limit but the size of `int`; `gmtime` raises `ValueError` (E387) beyond about plus or minus 9e18 seconds. The functions that take a moment (`gmtime`, `strftime`, `ctime`, `isoformat`) and `format_duration` accept an `int` or a `float`.
- Formatting: `strftime(fmt, t)` takes a `Time` or the seconds and knows `%Y %y %m %d %e %H %I %M %S %p %j %a %A %b %B %w %u %Z %z %F %T %R %D %c %x %X %n %t %%` (the C-locale words; names are English); any other directive is written as it is, and `%Y` is not padded (the C library does the same) while `isoformat` always pads the year to four digits (`-0001` before the year 0). `asctime(t)`, `ctime(seconds)` and `isoformat(seconds)` (`2024-03-09T16:00:00Z`) are ready-made formats; `format_duration(seconds)` writes a length of time for people (`250ms`, `12.5s`, `2m 05s`, `2h 03m 04s`; under a minute rounded to a millisecond, from a minute up truncated to the second).
- Making a `Time` by hand checks its fields (a `ValueError`, E388), so `strftime` never meets a month or weekday it has no name for. Everything is UTC, because the language has no time zones: there is no `localtime`, `%Z` is `UTC` and `%z` is `+0000`; `mktime` and `ctime` are the UTC versions. `Stopwatch()` (`elapsed()`, `restart()`) is a small helper over `monotonic()`, not in Python.
- `sleep`: not a function of this module. The built-in `await sleep(seconds)` (D58c) already waits, lets other tasks run and uses a logical clock so that output order does not depend on speed; a blocking `time.sleep` would stop every task and contradict that, and a module `sleep` cannot call the built-in under its own name. Davis can ask for a different choice.
- Not built: `strptime`, `localtime` and time zones, `perf_counter` and `process_time`, week-number directives (`%U %W %V %G`), locale names, `Time` comparison operators.

### D66a — `std/json.tom`: JSON and MessagePack: accepted

- Evidence: the task asked for a `json` library with `loads(text)` and `dumps(value, indent=...)`. Asked what `loads` returns Davis chose "A `Json` class with accessors" (the compiler cannot build a recursive union such as `None | bool | ... | list[JSON] | dict[str, JSON]`: a dict of unions is rejected and union fields are not narrowed). Numbers: "int when there is no fraction or exponent, else float". Errors, key order, duplicate keys and escapes: "accept as proposed". `dumps`: takes a `Json` plus builders; formatting "indent, no separators". MessagePack was added later by Davis to the same library; his lead settled that wire bytes and bin values are `list[int]` of 0..255 because there is no `bytes` type.
- API: `from json import loads, dumps, Json, JSONDecodeError`. `loads(text: str) -> Json`; `dumps(value: Json, indent: int = 0, sort_keys: bool = False, ensure_ascii: bool = False) -> str`. `Json` is a class with subclasses `JsonNull`, `JsonBool`, `JsonInt`, `JsonFloat`, `JsonStr`, `JsonList`, `JsonDict`; code builds values with those constructors (class functions such as `Json.from_int` are not built). Accessors on any `Json`: `j['a']` and `j[0]` (`@get`), `len(j)`, `'a' in j`, `j.get('a')` (a `Json | None`), `kind()` (`'null'`, `'bool'`, `'int'`, `'float'`, `'str'`, `'list'`, `'dict'`), `is_null()`, `as_bool()`, `as_int()`, `as_float()` (an int is accepted), `as_str()`, `as_list()`, `as_dict()`; `print(j)` and `str(j)` give the compact JSON text. Using a value as the wrong kind, a missing key or an index out of range raises `JSONTypeError` ("expected an int, but this is a str"); it does not give a path like `$.a[0]` because nodes keep no parent link.
- Parser (RFC 8259, strict): no trailing commas, comments, leading zeros, `+1`, `.5`, `1.`, NaN or Infinity, single quotes, raw control characters in strings, a byte order mark, whitespace other than space, tab, LF and CR; lone or reversed surrogate escapes are errors, valid pairs become one character; invalid UTF-8 (text read from a file is not checked when read) is an error; at most 512 levels of arrays and objects. Numbers with no fraction or exponent are exact ints of any size; any other number is a float, and a float literal too big for 64 bits (`1e999`) is an error, never infinity; `-0` is the int 0, `-0.0` the float -0.0. Objects keep the order of the document; a repeated key keeps its first position and its last value. `JSONDecodeError` is a `RuntimeError` with `message` (`Expecting ',' delimiter: line 3 column 5 (char 42)`, Python's wording), `reason`, `line`, `column` (1-based) and `pos` (a 0-based character offset).
- Writer: compact by default (`{"a":1,"b":[1,2]}`); `indent=N` (N > 0) puts each item on its own line indented N spaces per level, `"key": value`, empty `[]` and `{}` stay on one line, and `indent=0` means compact (not Python's newline-only form); no `separators` option. `sort_keys` orders keys by code point. `ensure_ascii=True` writes characters above 0x7E as `\uXXXX` with surrogate pairs; otherwise UTF-8 is written as is. Escapes: `"` `\` and the control characters below 0x20 (`\n \t \b \f \r`, else `\u00XX`); `/` and U+2028/2029 are not escaped. Floats are written as Python's `repr` does (`1500.0`, `1e-05`, `1e+22`) and keep their float-ness; a nan or infinite float (it cannot come from a literal and is only possible from MessagePack) raises `JSONEncodeError`, as does nesting deeper than 512 levels and a negative indent. Sets and arbitrary objects cannot be passed: the type system rejects them when compiling.
- MessagePack: `loads_msgpack(data: list[int]) -> Json` and `dumps_msgpack(value: Json) -> list[int]`. All formats decode: nil, bool, positive and negative fixints, uint8 to uint64, int8 to int64, float32 and float64 (NaN and infinity are kept), str (checked as UTF-8), bin, array, map (keys must be text; a repeated key keeps the last), ext, fixext and the timestamp extension (-1; 32, 64 and 96 bit forms). bin is `JsonBin` (`as_bytes()`), any other ext `JsonExt` (`ext_type()`, `as_bytes()`), timestamps `JsonTimestamp` (`seconds()`, `nanos()`; the 96-bit form is limited to ±2^62 seconds). Encoding writes every int in its shortest form (64 bits signed or unsigned; a larger int is a `MsgpackError`), floats as float64, text as str, and the shortest timestamp. Unexpected end of data, trailing data, the unused byte 0xc1, a byte list holding something other than 0..255 and more than 512 levels are `MsgpackError` (a `RuntimeError` with `pos`, a byte offset). `dumps` of a `JsonBin`, `JsonExt` or `JsonTimestamp` is a `JSONEncodeError`.
- MessagePack files (TODO item, Davis): `load_msgpack(path) -> Json` reads the whole file as bytes and decodes it like `loads_msgpack`; `dump_msgpack(value, path)` writes `dumps_msgpack(value)`, replacing the file. They mirror `load`/`dump`: the bytes are made before the file is opened, so a value MessagePack cannot hold (`MsgpackError`) leaves the file alone, and bad bytes in the file raise `MsgpackError` with the byte offset, without the path (as `load` does for JSON). A path that cannot be opened raises `IOError` E25 with the text `open()` uses (`could not open 'PATH': REASON`); a file that opens but cannot be read (a directory) raises `IOError` E381 `could not read 'PATH': REASON`, and one that cannot be written (a full disk) E382 `could not write 'PATH': REASON`. `open` is text-only, so the runtime has two internal byte-level helpers, `tomato_file_read_bytes(path, out)` and `tomato_file_write_bytes(path, data)` (C stdio, the same code in the WebAssembly build, where files live in the page's memory), and `tomato_file_error` writes the message, which `open()`'s own error now shares. A user-facing bytes file API (`open(path, 'rb')`) is not built.
- How it is built: the checking, number reading and string decoding are in the C runtime (`tomato_json_scan`, `tomato_msgpack_scan`): one pass writes a token tape (whole numbers, with the decoded text and floats in side lists) that Tomato turns into `Json` objects, and `dumps` and `dumps_msgpack` are Tomato methods that write into a list and join once (`tomato_json_quote`, `tomato_json_float` and the `tomato_mp_*` helpers do the text and number formatting). Reason: when this was written `s[i]` on non-ASCII text was a linear scan (the chunked index of D17c has since been built), so a character-by-character parser in Tomato would have been quadratic. The compiler change that made it possible: `!name(...)` LLVM declarations may now take list arguments (they could only take int, bool, float and text).
- Measured (Apple M1, `benchmarks/json/jsonbench.tom`, 40,000 records, 8.3 MB): `loads` 0.14 s with 124 MB resident (read included); compact `dumps` 0.47 s total, 185 MB; `indent=2` 0.53 s, 218 MB. 400,000 records (84.6 MB): `loads` 1.7 s and 1.0 GB, `dumps` 5.0 s and 1.6 GB: linear in the size.
- Not built: typed decoding into a user class (`loads_as(Point, text)`; needs reflection), a `separators` option, streaming or incremental parsing, duplicate-key and big-number options, `Json.from_*` class functions, and error paths such as `$.a[0]`.

### D67a — `<<`, `>>` and `~` on `int`, and a chunk-at-a-time `bitarray`: accepted

- Evidence: Davis asked to "add <<, >> and ~ on int, then use them to speed up bitarray", after D64a left them unbuilt.
- `x << n` and `x >> n` shift a whole number (`int` of any size, or a fixed-width type) as Python does: `<<` multiplies by 2 to the power n and never loses bits (`1 << 100` is exact), `>>` divides by 2 to the power n rounding towards minus infinity (`-5 >> 1` is `-3`, `-1 >> 200` is `-1`). The count is any whole number that is not negative; a negative count stops with "negative shift count" and one above 2^31 with "the shift count is too big". The result has the type of the left operand; for a fixed-width type it is range-checked like `+` (`uint[length=8](200) << 1` stops with "does not fit"). Precedence is Python's: shifts bind looser than `+` and `-` and tighter than `&` (`1 << 3 + 1` is 16, `a & b << 1` is `a & (b << 1)`). `<<=` and `>>=` assign.
- `~x` is `-x - 1` on an `int` (any size) and the bits flipped on a fixed-width type (`~uint[length=8](3)` is 252); on a class it still calls the `@invert` method (D64a). `~` on text, floats or `bool` is an error.
- `&`, `|` and `^` work on an `int` of any size too (added after D67a; they used to stop with "the bitwise operators & | ^ do not work on very large integers", E348, now a retired id). They follow Python: a negative number acts as its infinite two's complement, so `(-5) & (2**100 - 1)` is `2**100 - 5` and `(-1) ^ (1 << 80)` is `-(1 << 80) - 1`; the result is normalised (small when it fits). The runtime makes one pass over the limbs, forming each negative operand's two's complement on the fly, and takes time linear in the size of the larger operand; the small-number path is unchanged. Shifts and `~` have no size limit either. No `@lshift`/`@rshift` operator markers yet, so `bitarray` keeps `shift_left`/`shift_right` methods.
- `bitarray` now works a 32-bit chunk at a time wherever it used to loop over bits: `shift_left`/`shift_right`, unaligned `extend`, slices with step 1, `to_ints`, `to_hex`, `from_hex`, `from_ints`, `to_int` and `bitarray(int)`; the bit masks come from `1 << (31 - r)` rather than a C helper (only popcount is still C). Measured on a 2,000,000-bit array (Apple M1): shifts 0.077 s to 0.005 s, extend 0.055 s to 0.002 s, a 1.5 million bit slice 0.045 s to 0.002 s, `to_hex` plus `to_ints` plus `from_hex` of 500,000 digits 6.9 s to 0.04 s, a 20,000-bit `to_int` and `bitarray(int)` round trip 0.084 s to 0.006 s. Single-bit reads and writes are unchanged in cost.
- Not built: shifts of a `bool`, `@lshift`/`@rshift` markers, hex or binary integer literals.
- **Unicode case (Davis chose full Unicode simple case mapping):** `upper()` and `lower()` change every letter that has a one-letter simple mapping in Unicode: `'é'.upper()` is `'É'`, Greek and Cyrillic work, `'ǅ'.lower()` is `'ǆ'`. It is one letter to one letter, so the length never changes and `'ß'.upper()` stays `'ß'` (Python gives `'SS'`); there is no final-sigma rule. Bytes that are not valid UTF-8 are kept as they are. The two tables (about 380 rows of ranges, under 7 KB) are in `runtime/tomato_rt.c`, so the native and browser builds behave the same with no dependence on the C library's locale; `tools/gen_case_table.c` regenerates them (the macOS C library lacks the lowercase of four titlecase letters and is wrong for U+038D to U+038F, so the generator fixes those). `strip` is still ASCII only; `isalpha` and `isdigit` know Unicode since P89, with tables generated the same way from `UnicodeData.txt` (`tools/gen_ctype_table.c`).
- **`open()` failures:** the `IOError` message names the file and the reason, `could not open '/no/such.txt': No such file or directory` (the reason is the C library's `strerror`); in release mode it stays a short code (`std/errors.txt` line 21).
- **None and optional values in text:** `print(None)`, `str(None)`, and print, `str()` and f-strings of a `T | None` value show `None` when it is None and the value's usual text otherwise (a class with `@str`, a list, text). A list literal returned where `list[T] | None` is expected now compiles.

### D76a — `std/asyncio.tom`: `gather`, `wait_all`, `wait_for` and `Queue`: accepted

- Evidence: Davis approved the three named features ("Approve the three named features": `gather`, `wait_for`, `Queue` as specified below), then chose "Add `asyncio.wait_all(tasks)`" for tasks that give no result, since `gather` cannot build a `list[None]`.
- `import asyncio`. `await asyncio.gather(tasks)` takes a `list[task[T]]`, waits for every task and gives their results in the list's order (a task may be listed twice). When some fail it still waits for all of them, then raises the error of the first one in the list that failed; the other errors are taken too, so they are not reported as unread (D58a). On tasks that give no result it is a compile error that points to `wait_all`. `await asyncio.wait_all(tasks)` follows the same rules and gives nothing, for tasks of any result type.
- `await asyncio.wait_for(t, seconds)` (an int or a float) gives t's result, or raises its error, when t finishes within that many seconds of the scheduler's clock (the logical clock of `await sleep`, D58c). Otherwise it cancels t, waits until t has finished (its `finally` blocks have run, and a t that catches the cancel and returns still counts as late) and raises `asyncio.TimeoutError` (a `RuntimeError`). Zero or less seconds: t must already be finished. `t` stays awaitable afterwards.
- Cancelling a `gather`, `wait_all` or `wait_for` stops only that call: the tasks it waits for run on (D58d).
- `asyncio.Queue[T](maxsize=0)`: first in, first out; `await q.put(x)` waits while it is full, `await q.get()` while it is empty, and waiting tasks are served in the order they started waiting; `qsize()`, `empty()`, `full()` and the field `maxsize` do not wait. `maxsize` is set when the queue is made and cannot be changed. 0 means no limit; a negative maxsize is a `ValueError`. `maxsize` is given by position (constructors take no keyword arguments). A value (or free place) is promised to the task that has waited longest, so a later get waits for the next one even while `qsize()` still counts it. A get or put cancelled before it has its value leaves the line and passes its turn on; one whose value has already arrived keeps it, and the cancel is raised at the task's next wait, so a cancel loses no value. When a promised task is cancelled its value goes to the next in line, so a value already given to a later `get` can come out before it. A `wait_for` that runs out of time does drop a result its task had already received.
- Implementation: written in Tomato on three internal waits the compiler provides for this module: `await _settle(t)` (wait until t has finished without taking its result, so an error there is the waiter's own cancellation), `await _park(waiters)` (wait in a `list[task[None]]` until another task takes it out and passes it to `_unpark(t)`). A parked task is held only by that list, so a task left waiting on a queue nobody can reach is freed by the cycle collector, which now also follows a task's waiters and its starter. Nothing polls.
- Fixed with it: awaiting a finished task again gave an empty result (D51b says the result can be awaited many times); a generic async function or an async method of a generic class did not compile; `await f(start g())` was refused; a sleep that started after a slow HTTP request ended early (D58c, the exception); an error of a failed task that the cycle collector freed was lost (it is now reported, D58a).
- Not included in D76a: `Event` and `Lock` (now built: D76e), `t.cancelled()`, shielding.

### D76b — cancelling a task reaches into the call it awaits: accepted (changes D58d)

- Evidence: Davis chose "Cancel reaches the awaited call" when shown that a worker cancelled inside `await q.get()` left its `get` waiting in the queue, where it took the next value.
- A task cancelled while it waits in `await f(...)` (a call it awaits directly) passes the cancel to the task of that call, and so on down: `CancelledError` is raised at the innermost wait and travels out through each `await`, running every `finally`, as in Python. One cancel is still one `CancelledError`: a function that catches it carries on, and its caller gets its result.
- Waiting on a task made with `start` (`await t`) keeps D58d: only the waiter is cancelled, since others may hold `t`.
- A cancel made while the awaited call is running is raised at its next wait, or, when it ends without one, at its awaiter's next wait. If the call had already finished, its awaiter gets the result first. A task that never waits again ends normally.
- Implementation: `await f()` marks the new task as only its awaiter's (a header bit), and `tomato_task_cancel` follows that bit.

### D76d — UDP and asynchronous address lookup: accepted

- Davis chose `await socket.udp(host, port)` returning a `DatagramSocket` with `host`, `port`, `fd`, `await sendto(data: list[int], host: str, port: int)`, `await recvfrom(n: int = 65535) -> tuple[list[int], str, int]`, and `close()`. Each call sends or receives one datagram. Empty datagrams are valid; a receive buffer that is too small discards the datagram and raises `SocketError`. A destination name is resolved asynchronously to an address matching the socket family.
- Davis chose `await socket.getaddrinfo(host: str, port: int) -> list[Address]`; each record has numeric `host`, `port`, and `family` (4 or 6), in resolver order. Bad names or ports raise `AddressError`.
- Native name resolution, including TCP and UDP operations, runs off the scheduler thread. Cancelling a lookup releases the task immediately; the resolver may finish later. Socket operations still use the existing descriptor waits and browser calls raise `SocketError`.

### D76e — `asyncio.Lock`, `Semaphore` and `Event`: accepted

- Evidence: Davis chose the recommendations in `docs/locks-design.md` section 9, and "Add the details" for the deadlock diagnostic.
- `Lock`, `Semaphore(value=1)`, `Event` and `LockError` (a `RuntimeError`) are in `asyncio`, built on the Queue's waiter primitive (`_park` and `_unpark`); nothing polls. They are used with `try` and `finally`, not a `with` statement (deferred).
- `Lock` is non-reentrant and has no owner: any task may release it. `acquire` hands the lock directly to the longest-waiting task (FIFO); a cancelled waiter passes its turn on. An uncontended `acquire` does not yield. `locked()`, `waiting()`, `try_acquire()` and `release()` do not wait. Releasing a free lock, or one already handed to a waiter that has not run yet, raises `LockError`.
- `Semaphore` is bounded by its initial value: a release above it raises `LockError`; a negative value is a `ValueError`. `Event.set()` wakes every task now waiting and stays set until `clear()`.
- Timeouts use `wait_for(start lock.acquire(), seconds)`. If the task running the `wait_for` is cancelled, the acquire task is not (D58d): it runs on, takes the lock later and nothing releases it, so cancel it yourself in that case. `waiting()` counts a waiter that was cancelled but has not run yet.
- Diagnostic: when every task is waiting, the stop lists each task waiting in `Lock.acquire`: its task number, the line where it called `acquire`, and the line where the lock was last taken by `acquire`. Tasks are numbered as they start (main is 1), including tasks the library starts, such as `wait_for`'s timer. `Semaphore` and `Event` waiters are not listed, and there is no note about a lock still held at exit.
- Implementation: the call-site line of an async call is kept in the frame's error-line field until the task fails; the compiler's `_site()` reads it.

### D76c — `std/socket.tom`: TCP sockets: accepted

- Evidence: Davis chose "Approve TCP as above; UDP and a public `getaddrinfo` later" and "`list[int]` now, plus text helpers" (roadmap item 9; D3 of the roadmap, a `bytes` type, stays open).
- `import socket`. `conn = await socket.connect(host, port)` tries every address the name has (IPv4 and IPv6) in turn. `await conn.send(data)` sends every byte of a `list[int]` (each 0-255), `await conn.send_text(text)` sends text as UTF-8, `await conn.recv(n=4096)` gives up to n bytes as soon as there are any (`[]` once the other side has closed), `await conn.recv_line()` gives the next line with its `'\n'` (bad UTF-8 as U+FFFD; what is left, then `''`, at the end), `conn.close()`; `conn.peer_host`, `conn.peer_port`, `conn.fd`.
- `server = await socket.listen(host, port, backlog=128)` (SO_REUSEADDR; port 0 picks a free port, read back as `server.port`), `await server.accept()` gives a `Socket`, `server.close()`.
- Errors: `SocketError` (an `IOError`) and its kinds `ConnectionRefusedError`, `ConnectionResetError` (also writing to a closed connection: SIGPIPE never stops the program) and `AddressError`; using a closed socket is a `SocketError`. Timeouts come from `asyncio.wait_for`, which cancels the socket call when time runs out; cancelling the `wait_for` itself leaves a started call running (D76a).
- The scheduler waits on the sockets' descriptors with `poll`, in the same wait as libcurl (`curl_multi_poll` takes extra descriptors), so sockets, requests and sleeps overlap; nothing polls in a loop. Native only: in the browser every call raises `SocketError`.
- A task waiting on a socket keeps the program running after `main` is done (Davis chose "Keep running"), as a sleep or request does; close the socket to let it end.
- A socket call that does not need to wait still lets other tasks and timers run once in 16 calls, so a peer that is always ready cannot keep them waiting. `listen` uses the first address of the name that can be used. Waiting for a line of input (D50a) is part of the same wait, so sockets and timeouts keep running while a line is incomplete (native only; the browser still asks for input synchronously).
- At acceptance: name lookup blocked every task; UDP and public `getaddrinfo` were deferred. D76d adds them. No TLS or destructors; a socket nobody closes stays open until the program ends.

### D76d — small async fixes from the sockets reviews: accepted

- An error raised in a `finally` block that replaces the error being passed on no longer leaks the first one: the parked error is held in a reference-counted slot and released when the second takes over.
- A generator (`yield` in a plain function) can be used by a `for` loop inside an async function; `yield` in an async function still means a status for the task's reader, but not inside a generator.
- An async call that is not the one being awaited or started is no longer accepted where nothing would run it: a second call beside a `start` (`await [start f(), g()][0]`), an index (`await ts[len([g()]) - 1]`), an argument of a constructor, builtin or function value. It says `'g' is async, so it must be awaited or started`. The call that is the awaited value itself (`await [g()][0]`, `await f()`) still works.
- A task that waits for itself, or for a task that waits for it, raises `RuntimeError` ("a task cannot wait for itself, so this wait would never end") at the wait instead of waiting for ever. A wait through an awaited call (`await wait_for(me, 5)`) is found when the caller registers its wait, and the call is cancelled, so the caller sees `CancelledError` at once. Implementation: `tomato_task_cycle` follows the "waiting for" word of each frame.

### D77a — arbitrary-size `float`, and `float[length=64]` for the plain double: accepted (stages 0 to 5 built, see D77b, D77d and D77e; `float[length=64]` removed again in D77c)

- Evidence: Davis approved `docs/bigfloat-design.md` with all of its recommended answers: converting a huge `int` to `float` must not overflow, and **float exponents are arbitrary size**.
- Decided: (1) `float` itself becomes arbitrary-size, with a 53-bit mantissa and a big-int exponent, stored as a plain double whenever it fits (no new `bigfloat` type); (2) tiny numbers get unlimited exponents too (`1e-300 * 1e-300` is `1e-600`); (3) the mantissa stays 53 bits, so `float(10**400 + 1)` still rounds; (4) **`float[length=64]` is the name of the plain IEEE binary64 double, with an overflow error as today** (matching `int[length=N]`; there is no `float[length=32]` yet); (5) no optional-returning conversion: an `OverflowError` is enough; (6) `int` and `float` compare exactly (`2**53 + 1 == float(2**53)` becomes `False`); (7) a float with an exponent above 4096 bits prints as `0x1.8p+E`, below that in decimal; (8) the rounding fixes of stage 0 first.
- This replaces the part of D05aj that said a `float` has fixed range (the precision stays fixed), and the part of D05z and D05af that made `int / int` report an error when the result is too large for a binary64.
- **Built in stage 1:** only the name. `float[length=64]` is accepted wherever `float` is (annotations, parameters, results, fields, containers, generics, tuples, unions, `float[length=64](x)` as a conversion) and means exactly today's plain double: the two are the same type, so a `list[float[length=64]]` is a `list[float]` and the compiled code is unchanged. Any other length, such as `float[length=32]`, is a compile error ("float[length=N] exists only with N = 64"). When `float` itself becomes arbitrary-size (stage 3 of the plan), `float[length=64]` stays the fixed-size double and a conversion from `float` to it will raise `OverflowError` when the value does not fit.
- The arbitrary-size runtime (stage 2), the compiler (stage 3), the library and formats (stage 4) and the fast loops (stage 5) are built, see D77b, D77d and D77e.


### D77b — floats of any size in the compiler (stage 3 of `docs/bigfloat-design.md`): accepted behavior

- Evidence: the task "Bigfloat compiler integration" built stage 3 on the runtime of stage 2 (`docs/bigfloat-runtime.md`). Davis answered the one open language question: **float dict keys, set members and `hash()` stay**, for every float, boxed ones included (the design had assumed floats could not be keys; D78a had made them keys).
- Decided and built: (1) **`float` is any size.** A float is one 64-bit word: the bits of a double when the value is one, else a pointer to a small box holding the 53-bit significand and an `int` exponent. No operation on a `float` overflows or underflows: `1e300 * 1e300` is `1.0000000000000001e+600` (the double `1e300` is a little above 10^300), `1e-300 * 1e-300` is `1e-600`, `float(10 ** 400)` is `1e+400`, `10 ** 400 / 10 ** 399` is `10.0`, and E13 ("the float result is infinite or not a number"), E14 (a float that cannot become an `int`) and the lexer's limits on the digits and the exponent of a literal (`1e400`, `1e-400`, `1.5e1000000` and literals of any number of digits are legal) are gone. A result that fits a double is the double the hardware gives (the tests check it against exact arithmetic). (2) **There is one float type**: `float[length=64]` (D77a point 4, built as a name in stage 1) was removed by Davis's later decision, so `float[length=64]` and `float[length=64](x)` are compile errors ("float has no length"). (3) `int` and `float` compare **exactly** (`2 ** 53 + 1 == float(2 ** 53)` is `False`), a whole number converts to a float of any size, and `int / int` of any size rounds the exact quotient once. (4) **Printing**: a float that is not a double prints as `1.5e+1000000` (above an exponent of 4096 bits, `0x1.8p+E`); a subnormal double prints the digits a float needs (`2 ** -1074` is `4.9406564584124654e-324`, since `5e-324` is a different float). `float(text)` reads any exponent. (5) `int(x)` of a float is exact at any size. (6) `x ** y` with zero to a negative power is a `ZeroDivisionError` ("zero cannot be raised to a negative power") and a negative number to a power that is not whole is a `ValueError`. (7) A float is one word at rest: lists, tuples, dicts, sets, fields, unions, tasks and generators hold the word; **a box has one owner and is copied like a big int** (the compiler copies and frees floats where it does ints). The keys of a dict or set copy a box they keep; equal floats are equal keys and hash alike, `0.0` and `-0.0` are one key, and a whole float hashes as the equal `int`.
- Sorting a list of floats, `min`, `max`, `sum`, `abs`, `round(x)`, `int(x)`, `math.floor`, `ceil`, `trunc`, `isnan`, `isinf`, `isfinite`, `copysign`, f-string specs that are only fill, alignment and width, and `float(x)` of any size work as the types say. **Not yet** (stage 4): every `!` declaration that takes a `float` (the libm functions of `std/math`, `round(x, n)`, the `f`/`e`/`g` format specs, `sleep`, `time`, `requests` timeouts, JSON and MessagePack encoding) converts it to the nearest double at the call, so a float outside the double range stops there with an `OverflowError` ("a float is too large for a double", or "too small" for a tiny one that would come out as zero; one that comes out as a subnormal is converted as a double always was). Davis confirmed the `OverflowError` where the design said `ValueError` for `time`, `sleep` and `requests` timeouts. JSON, MessagePack and TOML are 64-bit formats: JSON and MessagePack keep NaN and infinite doubles in their own float class as before (as a `float` such a word is not a number to calculate with: arithmetic and `int()` stop with E13 and E14 as before, comparisons follow IEEE, and MessagePack decoding drops a NaN's payload); TOML reads a number beyond a double as "Float is out of range" and keeps a tiny one exactly. A double a `!` call returns is a plain float.
- Cost (accepted by Davis until stage 5): an operation on plain doubles runs the hardware instruction and one range test (a chain such as `zr * zr - zi * zi + cr` shares one test); a loop that only uses floats that fit a double runs about 2 to 3 times slower than it did, until the fast loop copy of stage 5 (about 11% by the design's measurements). With `float[length=64]` gone, a program has no way to ask for the old speed in the meantime.
- Not decided here: the library functions of stage 4 (built later, D77d) and the fast loops of stage 5 (built later, D77e).

### D77d — floats of any size in the library and the formats (stage 4 of `docs/bigfloat-design.md`): accepted behavior

- Evidence: the task "Bigfloat library and formats" built stage 4 on the runtime's math, rounding and format functions (`docs/bigfloat-runtime.md`). Davis chose the one open question: JSON and TOML reading cap a float's exponent at 4,300 digits (below).
- Decided and built, each a visible change:
  1. **`std/math`** takes and gives floats of any size. A float that is a double with a result that is a double gets the C library's answer as before; any other result is correctly rounded (`hypot` and `atan2` of a box: as exactly as the C library's on scaled operands). `sqrt(1e400)` is `1e+200`, `exp(1000)` is `1.970071114017047e+434`, `log(1e400)` is `921.0340371976183`, `hypot(1e400, 1)` is `1e+400`. **`OverflowError` E44 (`exp`, `expm1`, `sinh`, `cosh`) and E52 (`hypot`) are gone** (their ids are retired). **Tiny results are exact too**: `exp(-1000)` is `5.075958897549457e-435` (it was `0.0`), and `exp(-745.5)` is `1.7118422504935768e-324` (a subnormal double before). The domain errors stay (`sqrt(-1)`, `log(0)`). An angle above 2^53 turns has no fraction, so `sin(rad(1e400))` is `0.0` (a radian angle of double size goes to the C library instead, D83a).
  2. **`round(x, n)`** of any float gives a float of any size: `round(1e400, 2)` is `1e+400`, `round(1.7976931348623157e308, -308)` is `2e+308` (it was `OverflowError` E417, now retired), `round(1.23456e-400, 402)` is `1.23e-400`.
  3. **The f-string `f`, `e` and `g` formats** (and a precision with no type) take any float, and an `int` of any size with them: `f'{1e400:.3e}'` is `1.000e+400`, `f'{10 ** 400:e}'` is `1.000000e+400` (it was `OverflowError` E436, "an int is too large to be a float", now retired), `f'{1.5e-400:g}'` is `1.5e-400`, and a float near the bottom of the double range shows its own digits: `f'{5e-324:e}'` is `5.000000e-324` (the literal `5e-324` is not `2 ** -1074` since D77b, but it was rounded to that subnormal double at the call, giving `4.940656e-324`); `f` writes every digit of the whole part (`f'{1e400:.2f}'` is 403 characters), so its memory grows with the exponent's value.
  4. **JSON reads a number of any size**, as `float(text)` does (`[1e400]` was `JSONDecodeError: Number out of range`, and `[1e-400]` was read as `0.0`), and **writes a float as `str()` does**, so every float reads back as itself: `1e+400`, and a subnormal double with the digits a float needs (`2 ** -1074` is written `4.9406564584124654e-324`; `5e-324` is a different float since D77b). Every normal double is written as before. A float whose binary exponent has more than 4096 bits, which `str()` writes as `0x1.8p+E`, is `JSONEncodeError` E525 (that is not JSON).
  5. **TOML reads a float of any size** (`a = 1e400` was "Float is out of range") and writes it as `str()` does; a float beyond the 4096-bit exponent is `ValueError` E527 when written. `inf` and `nan` stay in `special`.
  6. **Reading caps the exponent at 4,300 digits** (Davis): JSON gives `JSONDecodeError: Number out of range` and TOML `TOMLDecodeError: Float is out of range` for more. Reading an exponent takes time in the square of its length (30,000 digits: 1.4 s; a 1 MB number about 25 minutes), so without a cap one small hostile document could stall a reader; 4,300 is Python's limit on the digits of an int read from text (CVE-2020-10735). The cap bounds each number to about 40 ms; a document's cost still grows with how many such numbers it holds (100 of them, 430 KB, take 3.6 s, so a 1 MB body about 8 s and a 10 MB one about 85 s), so a program reading untrusted JSON or TOML should still limit the size of the text, as it would for any parser. Every value up to 10^(10^4300) still reads. `float(text)` itself has no cap. **The cap bounds the reading only**: what a program then does with a huge value costs what it costs for any float of that size (`docs/bigfloat-runtime.md`, Limits). `exp`, `expm1`, `sinh`, `cosh` and `**` need time growing with the square of the result's exponent in bits (`exp(1e100000)` takes about 16 s), and the `f` format and `int(x)` write every digit of the whole part (`f'{1e10000000:.2f}'` is ten million digits). Before this change those calls stopped at once (E44, E436, or a float too large for a double), so a program that reads untrusted JSON or TOML and passes a field to them should check its size first (for example `abs(x) < 1e300`). D77f later added a limit to these calls: they now stop with an `OverflowError` beyond a result exponent of 2^16 bits (`f` beyond 100,000 digits), so the check is no longer needed for time.
  7. **MessagePack has only 64-bit floats**: encoding a float beyond the largest double, or so small that the nearest double is `0.0` (at most `2 ** -1075` in size), is `MsgpackError` E526 ("does not fit in a 64-bit float, the largest MessagePack has"), as an int beyond 64 bits is E86; it was an `OverflowError` from the C call. A float in the subnormal range is written as the nearest double, as before. A number read from JSON text is rounded twice on the way, though: to a 53-bit float when read (`1e-310` is a float of its own, not the subnormal double), then to the nearest double when packed. So a JSON document with subnormal-range numbers converts to MessagePack nearly as it did: in rare cases a number packs one unit of the last place away from the double C's `strtod` reads from the same text (`7.4109846876186981e-324` packs as `2 ** -1073`, not `2 ** -1074`), and a text just above `2 ** -1075`, such as `2.4703282292062328e-324`, whose 53-bit float is exactly `2 ** -1075`, is E526 where it used to pack as `2 ** -1074`. Decoding is unchanged.
  8. **An infinity or a NaN that JSON or MessagePack brought in** (D77b) goes through `math`, `round(x, n)` and the formats as the C library and Python treat it: `sqrt(nan)` is `nan`, `exp(-inf)` is `0.0`, `round(inf, -3)` is `inf`, `f'{nan:.2f}'` is `nan`, whatever the NaN's sign, as `str()` and Python print it (the formats raised the misleading E436 before).
- How it is built: a `!` declaration of a runtime function whose name starts with `tomato_bf_` takes and gives the float word itself (borrowed; the result is the caller's), not the nearest double, so `std/math.tom`, `round` and the formats call `tomato_bf_math1`, `tomato_bf_math2`, `tomato_bf_round` and `tomato_bf_format` directly (declared with an `int[length=32]` for the ownership mask, which they pass as 0). The JSON scanner reads a number outside a normal double's range with the runtime's float reader. `tomato_json_float` is removed.
- Not changed: `time`, `sleep`, `requests` timeouts and `struct`'s `f32`/`f64` keep D77b's `OverflowError` for a float a double cannot hold. The fast loop copy is stage 5 (D77e).

### D77e — the fast loop copy for floats (stage 5 of `docs/bigfloat-design.md`): built

- Evidence: the task "Float fast copy" built stage 5; measurements and the details are in "Stage 5 as built" at the end of `docs/bigfloat-design.md`.
- Built, with no change to what a program prints or raises: in release mode the fast copy of a loop nest keeps every float variable of the nest as a finite double (in a slot of type double of its own) and leaves for the general copy, at the start of the same statement, when a result would need a box, when it reads a box, or for an error. Tiny results are tested with the two-term rule of the design, and a product that is 0 because a factor is 0 counts as exact; float locals have intervals again, which in the fast copy spare the upper half of a test; `math.sqrt` there is the hardware square root. Debug mode and the browser (which compiles in debug mode) have no float fast copy.
- Cost against D77b's: on Linux mandelbrot runs as fast as before stage 3 (0.10 s), nbody 1.6 times and spectral_norm 1.45 times its time before stage 3 (they were 3.3 and 2.1 times); on an Apple M3 Pro 1.17, 1.9 and 1.24 times. In the browser the float loops stay 1.1 to 2.9 times slower than before stage 3.

### D77f — a limit on huge results: `exp`, `expm1`, `sinh`, `cosh`, `**` and the `f` format: accepted (Davis)

- Evidence: the task "huge-exponent limits" measured D77d's "the only limit is memory" (D77, D05c) on the runtime of this repository (Linux, a machine at load about 75, so a quiet one is perhaps 2 to 4 times faster). Memory stays flat but time grows with the square: `exp(1e30000)` 0.7 s, `exp(1e100000)` 7.7 s, `exp(1e300000)` 74 s; `10.0 ** 1e100000` 19.6 s; `f'{1e100000:.2f}'` 0.18 s, `f'{1e300000:.2f}'` 1.6 s, `f'{1e1000000:.2f}'` 24 s (ten million digits would take about 40 minutes), and its memory grows with the digits. `int(x)` and `round(x)` are binary and fast (1e100000000 in 0.2 s and 42 MB) and are already stopped by "out of memory" beyond 2^31 bits, so they are not limited. A 9-byte JSON document (`1e100000`) can bring such a value in. Davis chose a limit that can be configured, then, in the same task, changed it to **constants now and configuration from a TOML file later** (a TODO item): no `sys` setter.
- Decided and built:
  1. `exp`, `expm1`, `sinh`, `cosh` and `**` raise `OverflowError` (E528, "the result is too large to calculate: its exponent would have more than 65536 bits") when the exponent of the result would need more than 2^16 bits, that is when the argument (for `**`, the exponent) is above about 10^19,728 in size (`exp(1e19800)`). The time is then at most about a second. `exp(-x)` of such a number is refused too (the result is as tiny as the other is large); `expm1(-x)` is `-1.0` at once as before; a power of two to a power (`2.0 ** y`, exact and quick) and `1.0 ** y` are not limited. A float that is a double never reaches the limit (its exponent has at most 1,026 bits), so no existing calculation on doubles changes.
  2. The `f` format raises `OverflowError` (E529, "the number is too large to write with f: it has more than 100000 digits before the point") when the whole part would have more than 100,000 digits (a float of 1e100000 or more in size); that takes about 0.2 s. The `e` and `g` formats, `str()`, `round`, `int()` and JSON writing are fast for any size and are not limited.
  3. Both are catchable (`catch OverflowError`), raised where the calculation starts (the compiler for `**`, `std/math.tom` and `std/builtin/format.tom` for the others), before any time is spent. The two numbers are constants of the runtime (`BF_MAX_EXP_BITS`, `BF_MAX_FORMAT_DIGITS` in `runtime/tomato_rt.c`).
- Alternatives: leave them unbounded and document it (D77d's advice to check the size first); a setter like Python's `sys.set_int_max_str_digits` (more language surface and global state; Davis prefers a TOML configuration file later); a faster `exp` and digit generation (depends on subquadratic multiplication and division, and only moves the size at which a program stalls).
- Cost: an exception to "no operation can overflow", for results no program can use (a number with an exponent of 2^(2^16) bits); a program that read such a value from JSON can now catch the error instead of stalling.

### D77c — `float[length=64]` is removed: accepted (Davis)

- Evidence: Davis, in the stage 3 task, asked for a single `float` type with no `float[length=64]`, and chose to do the removal in that task rather than after the merge.
- Decided: the language has one float type. `float[length=64]` (written in a type, as a type argument or as a conversion) is a compile error, "float has no length: there is one float type, with an exponent of any size". This reverses D77a point 4 and the stage 1 name; the plain double exists only inside the compiler, where a float is converted to it at a `!` call. The questions it settled: a `list[float[length=64]]` is no longer a different type from a `list[float]` (there is one), and `float[length=64]`'s overflow errors (E13 for a float) are gone.
- Consequence: the tests `float_chains`, `float_ranges` and `float_length`, which tested the plain double's checks, were removed.

### Wave 2 pack D — binary and hashing modules: accepted

- Evidence: Davis approved section 4 and the shared UTF-8 module in section 0.3 of `docs/wave2-api-sheets.md`, with recommended D-Q1–D-Q6 and D-Q8, on 24 November 2026. D-Q7 was obsolete because `uuid5` already has private SHA-1 and UTF-8 helpers.
- Binary values are `list[int]` with each byte in 0–255. `utf8` provides text conversion; `hashlib` offers SHA-256, SHA-224, SHA-1, MD5 and PBKDF2; `hmac` provides HMAC and a best-effort `compare_digest`; `zlib` provides checksums; `struct` provides integer formats and typed readers and writers. SHA-1 and MD5 are weak for collision resistance. There is no claim of constant-time execution.
- Float packing (D-Q5) rejects unsupported values (Davis, 25 November 2026): reading NaN or infinity raises `ValueError` with the reader position unchanged, a finite value too large for f32 raises `OverflowError`, and negative zero and subnormals are preserved; this keeps D41a's finite-only rule and needs no runtime change.
- The optional file hash helper awaits pack A. UUID keeps its private implementation to preserve existing behavior.

### D80a — Wave 2 pack A: `sys`, `os`, `ospath`, `io` and files v2: accepted

Davis approved section 1 of `docs/wave2-api-sheets.md` as written, with A-Q1 to A-Q6, A-Q8 and A-Q9 as recommended, on 25 November 2026. **A-Q7 is deferred**: no `with` statement and no closing of a `File` when it leaves scope; the library helpers (`os.read_text`, `os.write_text`) close their file in `try`/`finally`, and `File` stays a built-in that is not an interface (so a `StringIO` cannot stand in for one).

- **Modules (A-Q1).** `sys` (`argv`, `exit`, `write_stderr`, `write_stdout`, `flush`, `platform`, `version`), `os` (`getenv`, `environ`, `putenv`, `unsetenv`, `getcwd`, `chdir`, `getpid`, `listdir`, `mkdir`, `makedirs`, `remove`, `rmdir`, `rename`, `stat` with `StatResult`, `read_text`, `write_text`, `read_bytes`, `write_bytes`), `ospath` (`sep`, `join`, `split`, `splitext`, `basename`, `dirname`, `normpath`, `isabs`, `abspath`, `relpath`, `expanduser`, `exists`, `isfile`, `isdir`, `islink`, `getsize`, `getmtime`) and `io` (`StringIO`). They are flat modules with functions and objects only, no module-level values besides `ospath.sep` (D49b). There is no `Path` class. `ospath` follows POSIX rules (`ospath.join` follows Python's `posixpath`: `join('a', '') == 'a/'`; the sheet's section 1.3 said an empty part is skipped, which differs; Davis confirmed Python's rule on 25 November 2026); its text functions give Python's `posixpath` results for the 293 cases of `tests/programs/ospath_text.tom`, which were generated once from Python 3.14.4 (see `tests/README.md`).
- **`sys.exit` (A-Q2, option a).** `exit(code=0)` flushes standard output and error and every open file (C `exit`) and ends the process at once with status `code` (0 to 255, else `ValueError` E513): `finally` blocks and other tasks do not run. `sys.version()` is a text literal in `std/sys.tom` that `tests/run.sh` checks against `VERSION`; the release script's bump step rewrites it, with `site/wasm/std/sys.tom` (compiled programs carry no VERSION file).
- **Entry points (A-Q3, option 1).** A last parameter `*name: tuple[str]` of the `@main` function receives the command-line words after the fixed inputs (any number, so there is no arity error). `**kwargs` entries are not built. `sys.argv()` returns every word whatever the entry takes; `argv()[0]` is the program as it was started.
- **File errors (A-Q4).** `FileNotFoundError` (E505), `FileExistsError` (E506), `PermissionError` (E507), `IsADirectoryError` (E508) and `NotADirectoryError` (E509) are subclasses of `IOError`, chosen from `errno` by `open()` and every `os`/`ospath` call; any other reason (a directory that is not empty, say) is a plain `IOError`. `open()` keeps the id E25 for all of them (the existing tests and uncaught-error output keep their ids), while the `os`/`ospath` calls use E505 to E509 for the subclasses and E515 for a plain `IOError`. `catch IOError` still catches all of them. The sheet's "ids stay (E25 etc., one new line per subclass)" is read as: E25, E381 and E382 stay for the failures of `open()`, reading and writing, and each subclass also has its own line in `std/errors.txt`, because the check that a library `raise` carries the id of its class needs one line per class. No `errno` field: the message says why (`could not list the directory 'p': No such file or directory`). Davis confirmed on 25 November 2026 that `open()` keeps the id E25 for these classes (the `os` and `ospath` calls use the new ids) and that `read()` raises `IOError` (E381) when the read fails, where it used to return `''`.
- **Listing (A-Q5).** `listdir` is sorted by bytes. **Bytes (A-Q6).** `read_bytes`/`write_bytes` take and give `list[int]`; a value outside 0 to 255 is a `ValueError` (E391) before the file is opened. `write_bytes(append=True)` appends (a C helper opens with `"ab"`).
- **Environment (A-Q9).** `getenv` raises `ValueError` (E512) for an empty name or one with `=` (E511 for NUL), `environ()` is a snapshot copy, `putenv` and `unsetenv` are functions.
- **Files v2.** `f.readline()` (the line with its `\n`, `''` at the end), `f.readlines()`, `f.writelines(list[str])`, `f.flush()` and `for line in f:` (the lines one at a time; a large file is not loaded) are built in. Reading raises `IOError` E381 when the read fails (a file opened for writing), which `read()` now does too (it used to return `''`). `open(path, mode)` takes `r w a x` with an optional `+` and raises `ValueError` E510 for anything else (so `b` and `t` are refused) before the file is opened; `x` creates the file and fails with `FileExistsError` when it exists (the C mode is `wx`). `open()` of a directory for reading is `IsADirectoryError` (some systems open one). A file opened with `+` reads and writes one stream: a write after a read goes at the position after what was read, and a read after a write continues after the written text (the runtime flushes or seeks between the two; there is no `seek` method yet, so `+` is mainly for `w+` and `r+` followed by one switch). Python's text files may behave differently here because they read ahead. A `for` loop over a file in a variable does not close it (the program does, with `close()`); `for line in open(path):` closes the file it opened (D82a). Using or closing a File after `close()` is undefined (a File is a bare C stream with no closed flag; this was already so for `read` and `write`), so close a file once and do not use it afterward, including a `close()` inside a `for line in f` loop over the same file. A-Q7 was deferred when this was written; D82a decides it.
- **Browser (A-Q8).** The playground host (`site/wasm/wasi.js`) keeps directories over its in-memory file map: `mkdir`, `rmdir`, `rename`, `readdir`, `stat` of directories, creating a file only in an existing directory (`/` and `/tmp` exist), append mode and modification times. `getcwd` returns `/`; `putenv`, `unsetenv`, `chdir` and `getpid` raise `RuntimeError` E514 there. `sys.platform()` is `wasi` in the browser.
- Built with a runtime change (`tomato_rt.c`: `tomato_set_args`, the environment, directory and stat calls, `tomato_file_readline` and friends) and a compiler change (the `File` methods, `for line in f`, the mode check and error classes in `open()`, entry `*args`), so `compiler/bootstrap/tomatoc.ll` and `site/wasm/*.wasm` are regenerated. Tests: `sys_basics`, `sys_args`, `os_env`, `os_files`, `ospath_text`, `file_lines`, `file_modes`, `bytes_files`, `string_io`, `os_browser` (WebAssembly only) and `tests/runtime/exit_status`/`exit_default`.

### D81a — Wave 2 pack B: `assert`, `testing` and `@test`: accepted

Davis approved section 2 of `docs/wave2-api-sheets.md` as written, with B-Q1 to B-Q6 as recommended, on 25 November 2026.

- **The `assert` statement (B-Q1).** `assert condition` and `assert condition, 'message'`, a new reserved word, **always on** (debug and release mode alike). The condition must be a `bool` (rule P8: `assert 1` and `assert (a, b)` are compile errors, not Python's always-true tuple) and the message a `str`. The parser rewrites it as `if condition: pass else: raise AssertionError(message, 'E519')`, with the line of the `assert`, so the usual `(raised on line N)` and call trace appear, and the message is worked out only when the check fails. (It does not narrow a type: the compiler gives `str | None` no narrowing after an `if` that raises either.) With no message the text is `assertion failed` (the expression text is not appended: the parser keeps no source spans).
- **`AssertionError` (B-Q5)** is a direct subclass of `Error` (E519, `std/errors.txt`), so `catch RuntimeError` does not catch a failed check.
- **The `testing` module.** `fail`, `assert_true`, `assert_false`, `assert_equal`, `assert_not_equal`, `assert_in`, `assert_not_in`, `assert_none`, `assert_not_none`, `assert_close`, `assert_raises`, `assert_raises_with`, `skip` and the class `SkipTest`, all pure Tomato. Each assertion raises `AssertionError` with the text of the sheet; a `message` is appended as `text: message`. `==` and `str()` on a type parameter `T` compile, so the sheet's typed-function fallback was not needed. A function type with no result is written `fn()` (the sheet's `fn() -> None` is not a type); `assert_none` and `assert_not_none` need the type written (`assert_none[str](name)`) because `T` is not found from `T | None`. `assert_close` follows Python's `math.isclose` with `rel_tol` and `abs_tol` (a negative tolerance is a `ValueError`, E524); a Tomato float is always finite, so there is no NaN or infinity case. **`assert_raises` (B-Q3, option a)** takes the class name as text, matches that class or any subclass, returns the error it caught and fails the test when nothing is raised or an unrelated class is. It needs two small runtime helpers: `tomato_error_is(err, name)` (walks the class and its parents by name; the compiler keeps the class names in release mode too when the program imports `testing`) and, for the runner, `tomato_caught_line()`.
- **`@test` and `tomato test` (B-Q2).** `@test` may mark any number of plain functions with no parameters and no result (nothing else may repeat an entry marker). The entry name `test` makes the compiler (`test_driver` in `compiler/src/compiler.tom`) append a generated function `@test_main` that calls `testing._run_all(names, functions, args)`; the running and printing are Tomato code in `std/testing.tom`. `tomato test FILE... [--filter TEXT] [--mode MODE]` compiles each file with entry `test` and runs it; with several files each run is headed `==> FILE <==`. There is no discovery of files, and no fixtures or parametrization. **Compatibility note (for the release notes):** the entry name `test` now always means the generated driver, so `tomato run FILE test` no longer runs an ordinary function marked `@test` that takes inputs; every function marked `@test` must take no parameters and return nothing (E521 otherwise). No example or test used `@test` as an ordinary entry point.
- **Output and exit (B-Q4).** `ok   NAME`, `FAIL NAME` followed by the message and `(raised on line N)`, `skip NAME  (reason)`, then `P passed, F failed, S skipped`, all on standard output; the status is 1 if any test failed (through `sys.exit`) or any file did not compile, else 0. The line is the line in the test function where the failure passed (debug mode keeps the call trace; release mode prints no line). `--filter` runs the tests whose name contains the text. A `--filter` that matches no test prints `warning: no test name contains 'TEXT'` before the counts, and the status stays 0 (whether an empty run should exit 1 is not decided).
- **No async tests (B-Q6).** `@test` on an `async def` is a compile error (E520), as is a test with parameters or a result (E521); a file with no `@test` function run with entry `test` says so (E522). Tests share one process: a test that calls `sys.exit` or changes the directory or environment affects later ones.
- **Native and browser.** `assert`, the `testing` module and the driver work natively and in the playground (entry name `test` in the compile call); `tomato test` is native only.
- Built with a compiler change (the `assert` keyword and its rewrite, repeatable `@test`, the driver, a class `Error` argument for LLVM functions, the module-name list) and a runtime change (the two helpers), so `compiler/bootstrap/tomatoc.ll` and `site/wasm/*.wasm` are regenerated. Also fixed on the way: a name declared twice was reported at the line of the module loaded last. Tests: `assert_ok`, `testing_lib`, `tests/runtime/assert_failed`/`assert_default`, the negative tests `assert_not_bool`, `assert_tuple`, `assert_message_not_text`, `test_on_async`, `test_with_parameter`, `test_with_result`, `duplicate_test_name`, `test_none_marked`, and the `tomato test` checks in `tests/run.sh`.

### D82a — A `File` opened in a `for` loop header is closed when the loop is left: accepted

A-Q7 of the Wave 2 sheets (deferred under D80a) asked what happens to the `File` in `for line in open(path):`. Before this, nothing closed it, so every such loop leaked a descriptor and a program that did it often ended in `EMFILE`.

- **Rule.** When the iterable of a `for` loop is a direct call of `open(...)`, the loop owns that file and closes it however the loop is left: when the lines run out, `break`, a `return` from inside the loop, or an error raised in the body or while reading. The compiler writes it as the statements a program would write (`for_open` in `compiler/src/compiler.tom`): the file goes in a variable no program can name, and a `try`/`finally` around a loop over that variable calls `close()`. So `break`, `return`, `continue`, nesting and errors need no code of their own. An `open()` that fails raises before the loop, with nothing to close. If the final `close()` fails (a full disk cannot happen on a read, but a `w+` file can), it raises the `IOError` as an explicit `close()` does.
- **What it covers.** Only a direct `open(...)` call that is the whole iterable, in a plain `for` (not `async for`, not an unpacking loop over `d.items()`). A file in a variable, `for line in f:`, is still closed by the program (it may want the file afterwards), and a function that returns a `File` (`for line in opener(path):`) is not closed, because the compiler cannot tell whether that function kept the file.
- **Chosen over** a warning when the header calls `open(...)`, which would leave the idiom wrong and ask every program to rewrite it, and over a closed flag on `File` that makes a use after `close()` raise `ValueError`. A closed flag changes what a `File` is (today a bare C stream) and the cost lands on every read and write, and it does not fix the leak (the program still has to close). It remains the way to make a use after `close()` defined, and that is not decided here: using or closing a `File` after `close()` is still undefined.
- **Test.** `tests/programs/file_loop_close` runs 15,000 loops (the end, `break`, `return`, an error, nested loops, next to a named file) and counts the entries of `/dev/fd` before and after: the difference is 0. Under the old compiler the same program fails with `Too many open files` when the limit is 256. It is native only (the playground has no descriptors).

### D83a — `sin`, `cos` and `tan` of a radian angle give the C library's answer: accepted (Davis)

The pre-release audit found that the trig functions reduced every angle to turns first (`_quarter` in `std/math.tom`), which is exact for degrees and gradians but rounds a radian angle when it divides by 2π: `sin(rad(10.0))` was 14 units in the last place off, `sin(rad(1e6))` right to 10 digits and `sin(rad(1e10))` to 6, and `tan(rad(-9 * pi / 2))` raised E47 (a multiple of a quarter turn in turns, but not in radians). D77d already said a double argument gets the C library's answer.

- **Rule.** A `Radians` angle whose value is a double (not beyond a double's range) goes straight to the C library's `sin`, `cos` or `tan`, whose argument reduction is exact over the whole double range (glibc, macOS libm and wasi-libc all reduce with the full bits of 2/π). `sin(rad(pi))` is `1.2246467991473532e-16`, as in C and Python, instead of `0.0`, and `tan` of a radian angle never raises E47.
- **What stays.** Degrees, turns and gradians are reduced in turns, so their multiples of a quarter turn stay exact (`sin(deg(180))` is `0.0`, `cos(deg(90))` is `0.0`, `tan(deg(90))` is an error). A radian angle beyond a double's range is reduced in turns as before, where it has no fraction (`sin(rad(1e400))` is `0.0`).
- **Chosen over** keeping `sin(rad(pi))` exactly `0.0` (Davis chose the C library's answer) and over a reduction of our own in double-double or big-float arithmetic, which would repeat what every C library already does exactly.
- **Test.** `tests/programs/trig_radians` compares 397 radian angles (multiples of π/2 up to 1000π, tiny, huge up to the largest double, negative and random) with Python 3's `math`, within one unit in the last place (16 next to a zero of `sin` or `cos`, where a correct C library may differ a little); it passes natively and in the browser build, and the old reduction fails it.

### D84a — Version numbers, pre-releases and compatibility: accepted (Davis)

- **Numbers.** From 1.0.0 a version is MAJOR.MINOR.PATCH, with an optional SemVer pre-release (`1.0.0-rc.1`); the releases before were 0.1 to 0.51, read as 0.NN.0. Versions are ordered by SemVer precedence (`1.0.0-rc.2` < `1.0.0-rc.10` < `1.0.0`).
- **Compatibility.** All 1.0.x releases are compatible with each other: a program in the implemented subset that works on one 1.0.x release works the same on every other, except the placeholders in `docs/provisional.md`. A minor release (1.1.0 and later) may change behaviour; each change is listed under Breaking changes in its changelog section and release notes. The release checklist's review of the changelog is the gate: a patch release has no Breaking changes.
- **Pre-releases.** A pre-release is a GitHub pre-release and is listed in `site/latest-pre.json`; `site/latest.json` and the website keep the latest stable release. `tomato update` never moves a stable install to a pre-release unless asked (`--pre`); an install of a pre-release moves to a later one or to the release.
- **Updates.** `tomato update` installs a newer patch release at once and a newer minor or major version only with `--minor`, since that may change behaviour.
- **Details** are in `docs/releasing.md` (Version numbers); `release/release.sh` takes `--version X` or `--bump major|minor|patch`.

### D85a — `@neg` and `@rmul`: unary minus and a number on the left, for any class: accepted

- Evidence: Davis asked whether `deg` and `rad` support `+` and the like. They did for `+`, `-`, `* number`, `/ number` and comparisons, but not for `-deg(30)` or `3 * deg(30)` (D49a listed both as open), and he asked for those two. Operators on a class came from D12j-l (`@add` marks an ordinary method, the left operand is the receiver), and the language had no way for a class to take part in `-x` or in a product whose left side is a number.
- Two new operator markers, written like the others (D12k) above an ordinary method whose name the class chooses, and inherited like them (a subclass's replacing method is the one that runs):
  - `@neg` marks a method that takes nothing besides `self` and returns the result (any type); `-x` on an object runs it. `~x` with `@invert` (D64a) is the same shape.
  - `@rmul` marks a method that takes one argument; `n * x` runs it on `x` with `n` as the argument, when `n` is not an object and `x`'s class has it. It is tried only after the left operand is found not to be an object, so `x * n` is still `@mul`, and `x * y` with two objects uses only the left operand's `@mul` (no fallback to the right operand's `@rmul`, as D12l has no right-side fallback). The argument is checked against the parameter type as for `@mul` (the error says "the left operand of *"). A class without `@rmul` gives `cannot use '*' with int and Box` with a help line that names the marker.
  - Errors: `-x` on an object without `@neg` says to add one; a `@neg` method that takes arguments or returns nothing, and an `@rmul` that does not take exactly one argument, are compile errors. Two new error ids (`std/errors.txt` ends with them).
- Chosen over Python-style reserved method names (`__neg__`, `__rmul__`), because D12k settled on markers; over a reflected marker for every operator (`@radd`, `@rsub`, `@rdiv` ...), because only `number * object` has a use here (scaling), and each extra marker is more to document and test, so another one can be added the same way later when a class needs it; and over defining `-x` as `0 - x` through `@sub`, which needs a zero for every class and gives `-0` surprises (`negated()` writes `0.0 - value` for that reason).
- `Angle` (`std/math.tom`): `negated()` is marked `@neg`, so `-deg(30)` is `-30 deg` and keeps its unit; a new `scaled(k)` is marked `@rmul`, so `3 * deg(30)` is `90 deg`. `a.negated()` and `a * number` keep working.
- Before: `-deg(30)` and `3 * deg(30)` were compile errors (`cannot use '-' on Angle`, `cannot use '*' with int and Angle`).
- After: both work; any class can define `@neg` and `@rmul`.
- A bug found on the way: an operator method on an object was given a number read from a field (`obj * box.x`) without a copy, so a method that changed `box.x` freed the number it was still using (a use after free for a number too big for a machine word). The right operand of an operator method is now copied first, like the number of `n * obj`. `tests/programs/at_neg_rmul` covers it (`@mul` and `@rmul`).
- Costs: `-x` of anything but a literal is no longer counted as a plain read by the loop-lending analysis (`pure_read`), since `x` may be an object whose `@neg` runs user code; numbers still go through `plain_num`, so the generated code for numbers is unchanged. Two more reserved marker names, which no program can have used because an unknown `@` marker was an error.
- Not done: a reflected form of the other operators (`@radd`, `@rsub` ...), and what an angle still lacks: `a % b` and `a // b`, `a / b` of two angles (a ratio), `a ** n`, `abs(a)`, `float(a)`, `int(a)` and `round(a)` (use `a.abs()` and `a.deg()`), `sum()`, `min()`, `max()` and `sorted()` of a list of angles (they take numbers or text only), `@hash` so an angle can be a dict key or set element (it has `@eq` and no `@hash`), and unary `+a`, which the language does not have for any type.

### D86a — The repl line editor in Tomato: the `terminal` and `lineedit` modules, stage 1 built: accepted

Davis asked for `tomato repl` to edit multi-line blocks like Python 3.13 (recall a block with Up and edit it in place, bracketed paste, resize, syntax highlighting from the compiler's own lexer), written **in Tomato as a library**, not as a C program (this replaces D59a's "not possible without writing a terminal program; rejected as too large"). `docs/repl-editor-design.md` is the design and its five stages. On 26 November 2026 Davis approved all seven recommendations of its section 14, and stage 1 was built.

- **Modules (question 1).** Two std modules, `terminal` (raw keys, size, colors, widths) and `lineedit` (the editor, stage 2), with the editor's hooks as `interface`s (`Highlighter`, `Validator`, `Indenter`) rather than function values, which cannot carry state (D63a). Everything specific to Tomato or to the repl stays outside `std/`.
- **The lexer stays non-public (question 2):** `lexer.tom` keeps living in `compiler/src/` (stage 3 adds `lex_spans` there); no `std/tokenize.tom`.
- **History (question 3):** the plain-text file keeps its `⏎`-joined format, so old and new `tomato` read each other's files.
- **Keys (question 4):** `Terminal.read_key` blocks; no async keys for stages 1 to 4.
- **Editing rules (questions 5 and 6, stage 2):** Enter continues on an open bracket (`x = (1,`), and an edit to a recalled history entry is dropped when the person moves to another entry.
- **Colors (question 7, stage 3):** keywords red `#EB3C27`, strings green `#009639`, the rest from the terminal's own palette, comments dim; no light or dark detection.
- **Built in stage 1** (`docs/terminal-api.md` is the sheet as built): eight runtime functions (`tomato_tty_open`, `close`, `is`, `raw`, `restore`, `size`, `read`, `write`) and `tomato_char_width` in `runtime/tomato_rt.c`, with stubs for the browser; `std/terminal.tom` (`Terminal`, `Key`, the pure `KeyDecoder`, `Style`, `rgb`, `ansi`, `sgr`, `styled`, `color_depth`, `char_width`, `text_width` and the escape helpers); an empty `std/lineedit.tom` (only its header comment) so that `std_modules()` gets both names in this one compiler change, one bootstrap refresh and one rebuild of `site/wasm/*.wasm` (built with WASI SDK 24, the same bytes on Linux and macOS); errors `TerminalError` (E532) and `ValueError` E533 to E535; the website's module lists (`TomatoWasm.STD`, the highlighter's module names) know both. The repl itself is unchanged.
- **Waiting for a key uses `select()`,** not `poll()`: on macOS 27 `poll()` on a terminal device answers `POLLNVAL` at once. A `SIGWINCH` handler writes to a self-pipe that the same `select()` watches, so a resize wakes a blocked read without a race.
- **The terminal is always given back:** `Terminal.leave()` in a `finally`, `atexit` (a normal end, `sys.exit`, an uncaught error), and handlers of `SIGTERM`, `SIGHUP`, `SIGINT`, `SIGQUIT` and of a fault, which restore the settings and take the default action. Only `SIGKILL` cannot be covered.
- **Own width tables** (`tomato_char_width`), not libc's `wcwidth`, which differs between macOS and glibc and needs `setlocale`; grapheme clusters are summed per code point (a flag can be a cell off).
- **Where the sheet was made precise (the design's section 6 was a proposal):** `Style` takes its fields positionally (a class cannot take keyword arguments); `cursor_column` counts from 0; control characters have width 0; `TOMATO_COLOR` is read when the mode is `auto`; lowering a truecolor value to 16 colors picks the nearest by RGB distance, which makes the brand red `#EB3C27` the bright red `91` and not `31`, so the stage 3 palette will choose `ansi(1)` itself for 16 colors or fewer (`docs/terminal-api.md`, Colors).
- **Tests.** `tests/terminal_logic.tom` (22 `@test` functions through `tomato test`, debug and release: the decoder at every byte split, widths, SGR lowering, `color_depth`), `tests/terminal_pty.tom` with `tests/terminal_pty.exp` (a program on a real pty: raw mode, keys, timeout, size and resize, and the settings (`stty -g`) the same after a normal end, `finally`, an uncaught error, `sys.exit`, no `leave()`, a stack overflow, `SIGTERM` and `SIGHUP`; run on Linux and on macOS 27 arm64), `tests/programs/terminal_browser.tom` (the browser path). On macOS the pty test ignores the `PENDIN` bit of `stty -g`: the kernel sets it whenever `ICANON` changes and clears it when the pending input is retyped, so it differs between two reads of unchanged settings.
- **Not built yet:** stage 2 (`lineedit`, the repl on it, the installer, tarball and `.pkg` steps), stage 3 (`lex_spans`, the highlighter), stage 4 (library polish and an example).
