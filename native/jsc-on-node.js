// Runs a script written for the jsc shell (macOS JavaScriptCore) under Node, so Linux can run the same WebAssembly checks as macOS.
//   node native/jsc-on-node.js SCRIPT.js -- ARGS...
// It gives the script jsc's globals (load, read, print, printErr) and its `arguments`; the script itself is not changed.
const fs = require("fs"), vm = require("vm");
const out = (fd) => (s) => fs.writeSync(fd, String(s) + "\n");   // like jsc, one line per call; synchronous, so stdout and stderr keep their order
Object.assign(globalThis, {
  print: out(1), printErr: out(2),
  read: (p, mode) => mode === "binary" ? new Uint8Array(fs.readFileSync(p)) : fs.readFileSync(p, "utf8"),
  load: (p) => vm.runInThisContext(fs.readFileSync(p, "utf8"), { filename: p }),   // a global script, so its top-level declarations are shared like jsc's
});
const [script, ...rest] = process.argv.slice(2);
if (!script) { console.error("usage: node jsc-on-node.js SCRIPT.js -- ARGS..."); process.exit(2); }
const args = rest[0] === "--" ? rest.slice(1) : rest;   // jsc passes what follows `--` as `arguments`
globalThis.arguments = args;   // jsc has `arguments` at the top level of the script
load(script);
