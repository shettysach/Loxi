# Loxi

Lox bytecode interpreter with a mark and sweep garbage collector, based on the second half of [Crafting Interpreters by Robert Nystorm](https://craftinginterpreters.com/).

> [!WARNING]
>
> - You can use NaN boxing for better cache locality, but tested only on x86_64.
>
> ```sh
> odin run loxi -o:speed -define:NAN_BOXING=true -- eg/fib.lox
> ```

## Build and run

```sh
odin build ./loxi -target:js_wasm32 -out:./docs/loxi.wasm -no-entry-point -o:speed
miniserve ./docs --index ./docs/index.html
```
