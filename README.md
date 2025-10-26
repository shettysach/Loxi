# Loxi

Lox bytecode interpreter with a mark and sweep garbage collector, based on the second half of [Crafting Interpreters by Robert Nystorm](https://craftinginterpreters.com/).

## Build and run

```sh
odin build ./loxi \
  -target:js_wasm32 \
  -out:./docs/loxi.wasm \
  -o:speed \
  -no-entry-point \
  -disable-assert \
  -no-bounds-check \
  -no-crt \
  -extra-linker-flags:-O3 \
  -define:NAN_BOXING=true
miniserve ./docs --index ./docs/index.html
```
