# Tomato for VS Code

Syntax highlighting, bracket and indent rules, and snippets for `.tom` files.

The grammar knows every keyword of the language (including `async`, `await`, `start`, `yield`, `catch`, `export`, `override` and `private`), the `@main` / `@init` / `@iter` style markers, `!name` LLVM declarations and calls, `int[length=N]` / `uint[length=N]`, `fn(...)` and `task[...]` types, the built-in functions and error classes, and f-strings. The grammar file (`syntaxes/tomato.tmLanguage.json`, scope `source.tomato`) is a standard TextMate grammar, so it also works in Sublime Text, TextMate, IntelliJ (TextMate bundles) and GitHub Linguist.

Install from a folder: copy this directory to `~/.vscode/extensions/tomato-language`, or run `npx @vscode/vsce package` here and install the `.vsix`.
