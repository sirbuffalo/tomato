"""Bundle the interpreter and examples into web/bundle.json for the browser page."""
import glob
import json
import os

root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
bundle = {"files": {}, "examples": {}}
for p in sorted(glob.glob(os.path.join(root, "tomato", "*.py")) + glob.glob(os.path.join(root, "tomato", "std", "*.tom"))):
    with open(p) as f:
        bundle["files"][os.path.relpath(p, root)] = f.read()
for p in sorted(glob.glob(os.path.join(root, "examples", "*.tom"))):
    if os.path.basename(p) in ("mathlib.tom", "compiled.tom"):
        continue  # mathlib.tom needs llvmlite, which the browser lacks; compiled.tom needs a command-line input
    with open(p) as f:
        bundle["examples"][os.path.basename(p)] = f.read()
with open(os.path.join(root, "web", "bundle.json"), "w") as f:
    json.dump(bundle, f)
print("bundled %d modules, %d examples" % (len(bundle["files"]), len(bundle["examples"])))
