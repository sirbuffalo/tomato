// What the website repl compiles for a piece of text (site/wasm/tomato.js, wrapMain): prints the wrapped program, or "same" when the
// text is left alone. tests/run.sh compiles the wrapped text, so a piece with no statements (an import) reports its own error.
//   jsc tests/repl_wrap.js -- 'from itertools import progress_bar'   (or: node native/jsc-on-node.js tests/repl_wrap.js -- ...)
load("site/wasm/tomato.js");
var src = arguments[arguments.length - 1], w = TomatoWasm.wrapMain(src);
print(w.text === src ? "same" : w.text);
