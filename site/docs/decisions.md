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

### D34a — error output has debug, normal and release modes: accepted

- Evidence: Davis wrote “I want readable errors in debug and somewhat in normal bt not needed in release debug full error normal outputs codes thta cna be decoded back tom debug that chatgpt”, then “with the source code normal can be decoded to debug style with a second prohrsm” and “the chatgpt does not matter”, withdrawing the unreadable phrase.
- Debug mode prints full readable errors; normal mode prints a short code that a second program decodes against the source into the debug text; release mode needs no readable errors.
- Open: the code format, how a mode is selected, location details, and what release prints, if anything.

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
- Open: weak references, dicts and sets, interfaces, errors, big-number `int`, small values stored inline in the data word, atomic counts for threads, and a chunked string index.

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
- Open: a bitwise-not symbol (`~`), shifts, and bitwise operators on `bool`.

### D38a — new code is Tomato and LLVM; each compiler builds the next: accepted (reading to confirm)

- Evidence: Davis wrote “ok no more python for now on only in tomato”, “and llvm” and “use the previos version to compile the next”, and then “commit changes don't push each time”, “you have control of commiting” and “once a feature fully works push”.
- Reading: from now on new compiler and tooling code is written in Tomato (with LLVM IR for low-level runtime pieces), not Python. The Python implementation stays as the bootstrap: it builds compiler v1 written in Tomato, v1 builds v2, and so on. The Python interpreter is not extended unless a Tomato program needs a feature it lacks.
- First step: `compiler/src/lexer.tom`, a lexer in Tomato that produces exactly the tokens of the Python lexer on every example, standard-library and self-hosting file (checked by `tests/test_selfhost.py`). It runs under the interpreter; the Python compiler cannot build it yet (`in` on lists and text, text methods and slicing, reading files in compiled code).
- Git: I commit as I go and push once a feature fully works, not every time. The first push was a single clean commit on top of `origin/main`.
- Stage 1 works for the lexer: the Python compiler builds `compiler/src/lexer.tom` into a native program that prints the same tokens as the Python lexer on every example and self-hosting file (`tests/test_selfhost.py`). Compiled code gained `x in list`, file reading and writing, and the text methods `find`, `replace`, `split`, `startswith` and `endswith` for it (P49, P50).
- A first end-to-end slice of the compiler is written in Tomato (`compiler/src/compiler.tom`, P53): it takes the Tomato parser's tree and writes LLVM IR for int, bool, str and list programs, with reference counting like the Python compiler. clang builds that IR with the C runtime into programs that print what the interpreter prints and report no leaks, and the compiler built natively by the Python compiler writes byte-for-byte the same IR as when it runs interpreted (`tests/test_selfhost_compiler.py`). Classes, single inheritance, `Error`, `raise`, imports and entry inputs are in too, and the Tomato compiler has compiled the Tomato lexer: the resulting program lexes every example and self-hosting file exactly like the Python lexer (first self-hosting milestone). The Tomato compiler compiles itself: stage 1 (the Python compiler builds the Tomato compiler) compiles the compiler's own source to IR, clang builds that into stage 2, and stage 2 compiles the source to byte-for-byte the same IR (a fixed point, `tests/test_stage2.py`); stage 2 also compiles sample programs that behave like the interpreter. Before that it compiled the Tomato parser too: the native program builds the same syntax trees as the Python parser for every example and self-hosting file. Still to write: dicts, sets, optionals, default arguments, `try`/`catch`, interfaces and imports in the Tomato compiler; then stage 2, the compiler compiling itself.
- The parser is written in Tomato too (`compiler/src/parser.tom`, P52). Interpreted and compiled by the Python compiler, it builds exactly the same syntax tree as `python/tomato/parser.py` for every example, standard-library and self-hosting file, including its own source (`tests/test_selfhost_parser.py`). The lexer was split into `lexer.tom` (library) and `lextool.tom` (command) so a library can be imported without clashing entry points.
- Imported modules compile (P51): the compiler can now build programs made of several files, which the compiler in Tomato needs. `examples/features.tom`, which was “not compiled yet” because it imports `math`, builds with the same output as the interpreter.
- Tools built on it: `server/compile_server.py` serves a page (`web/compile.html`) that compiles and runs a Tomato program with the Tomato-built compiler (it builds stage 2 on first start and runs programs with a 5 second limit; plain Python standard library, since Tomato has no networking yet; it binds to 127.0.0.1 only). `install-native.sh` installs a `tomato` command (`run`, `build`, `compile`) that needs only clang: it builds `tomatoc` from the checked-in `compiler/bootstrap/tomatoc.ll`, the compiler's own IR (`compiler/bootstrap/refresh.sh` refreshes it, and `tests/test_stage2.py` fails when it is out of date). The Python command stays as `tomato-py`.
- Confirmed by Davis (asked whether Python may still change): language features go in the Python bootstrap until Tomato can build itself; new tools and the compiler passes are written in Tomato.
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
- `a // b` rounds the quotient down: whole numbers give a whole number (D05s typing), a float involved gives a float (P56). A constant zero divisor fails at compile time like `/` (D05ac).
- `a ** b`: whole ** whole is a whole number and a negative exponent is an error, because the result type may not depend on a value (write `2.0 ** -2`); a float on either side gives a float. `**` binds tighter than a minus on its left (`-2 ** 2` is -4) and nests to the right (P57).
- Open: mixing `rational` with `float`, how a fixed-width result of `//` or `**` is typed from literals (it needs an explicit conversion like other non-literal results), `float` as an entry-point parameter in compiled programs beyond what D28b gives, and the compiler written in Tomato, which does not have these yet.

### D42a — top-level code, version numbers and the repl: accepted (reading to confirm)

- Evidence: Davis wrote “no @main needed toplevel code works”, then “though if there is a @main run it instead”, then “you can just do @main()”; “add version number this is v0” and “python is v-1” with “v0.x” and “v-1.x”; and asked for a repl (“tomato shell … open a shell … with compiling and variables already set”), then chose the name `repl`.
- A main program may have statements at the top level; they are the program, run top to bottom. If the file has an `@main`, only `@main` runs and the top-level code is checked but not run; code can also call `main()` itself. This replaces the “no top-level code” rule of D16a for the main program. Imported modules still may not have top-level code (P60).
- The compiler written in Tomato is v0.x and the Python implementation is v-1.x. The number lives in `VERSION` (v0.1 now); `tomato version` prints it.
- `tomato repl [FILE ...]` (alias `shell`) reads one piece at a time and needs no Python: each piece joins the session, the whole session is compiled by the compiler written in Tomato and run, and only the new output is shown (Davis: “no more python”). It offers `:load`, `:program`, `:save`, `:compile`, `:reset`. The Python implementation keeps its own interpreter-based repl, which holds live values (P59).
- Open: whether top-level code should run after `@main` finishes; top-level code in the compiler written in Tomato (the compile server wraps it for now); a repl written in Tomato, which needs standard input, and a repl that keeps live values instead of re-running the session.

### D43a — the website, releases and `tomato update`: accepted (reading to confirm)

- Evidence: Davis asked for tomato.davismcd.com to be a page about Tomato with a repl, a place to run programs and full documentation, “a pkg download” and a `tomato update` command, chose GitHub Pages with GitHub Releases, and asked to move the website into `site/`, delete the old `site/`, reorganize the project and remove code that is not needed.
- `site/` is a static site (overview, guide, reference rendered from the repository's Markdown, download, and a Run and Repl page that calls a compile server). `release/build.sh` builds `tomato-VERSION.tar.gz` and `latest.json` (version, URL, SHA-256); `tomato update` reads `latest.json`, verifies the checksum and reinstalls.
- Layout: `python/` (the Python implementation), `compiler/` (`src/` and `bootstrap/`), `server/`, `site/`, `release/`, `native/`, `docs/`, `examples/`, `tests/`. The old chat and decision site, its `static/` page and the Pyodide playground were deleted; they remain in git history.
- Open: the public location of the releases (the repository is private today) and the public URL of the compile server.

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

## Pending discussion

The simplicity/performance direction is accepted in D02a–D02b. Other priorities, including correctness, build time, and distribution, remain open.

Numeric details remain open: detailed width-expression rules, representation, overflow error handling, analysis outside D05x, contextual typing beyond D05s–w’s literal-only arithmetic rules, remaining arithmetic rules beyond D05s–w, D05y–aj, and D05at, remaining division/modulo rules under D05y, and resource-exhaustion behavior. Compiler implementation and merging this task remain outside the authorized scope.

Remaining interface details are queued: duplicate declarations, exact import/export syntax, re-exports, processing phase, and interface inheritance. The basic declaration choices are settled, but the interface model is not complete.

Current queue: class details (initialization/defaults, other modifier placement and init writes, @init allocation/receiver model, @add operand/result rules, construction, overriding and member compatibility), remaining interface details, detailed inference, web-app host integration, integer quotient/modulo and remaining numeric rules, and priority/release scope. The classes and integers are not complete.

## Public page status

The earlier public decision page, its password-protected chat and the chat bridge are retired and their code (`site/`, `static/`) has been removed from the repository. They are not to be restarted or redeployed. Decisions are read from these Markdown files; the local Python playground in `web/` is separate and holds no chat.

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
