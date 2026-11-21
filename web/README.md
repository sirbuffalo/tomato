# Tomato Playground

A local web page that runs the Python interpreter in the browser through Pyodide (Python compiled to WebAssembly). It is a prototype, not the compiler, and it does not use any account or server-side code.

- Rebuild the bundle after changing `tomato/` or `examples/`: `python3 web/build.py`
- Serve it on this machine only: `cd web && python3 -m http.server 49211 --bind 127.0.0.1`
- Pyodide 0.26.4 loads from the jsDelivr CDN, so the viewing browser needs internet access.
- Programs run in a Web Worker; Stop terminates the worker, so an endless loop can be cancelled.
