# Loxi

Lox bytecode interpreter with a mark and sweep garbage collector, based on the second half of [Crafting Interpreters by Robert Nystorm](https://craftinginterpreters.com/).

## Build and run

```sh
odin build ./loxi -target:js_wasm32 -out:./docs/loxi.wasm -no-entry-point -o:speed
miniserve ./docs --index ./docs/index.html
```
