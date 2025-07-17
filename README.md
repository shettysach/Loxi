# Loxi

Lox bytecode interpreter with a mark and sweep garbage collector, based on the second half of [Crafting Interpreters by Robert Nystorm](https://craftinginterpreters.com/).

> [!NOTE]
>
> - You can use the Odin compiler's `-o:speed` flag for better performance.
> - You can use NaN boxing for better cache locality. Tested only on x86_64.
>
> ```sh
> odin run loxi -o:speed -define:NAN_BOXING=true -- eg/fib.lox
> ```

## Build and run

```sh
# repl
odin run loxi
```

```sh
# file
odin run loxi -- <filepath>
```

## Build

```sh
# repl
odin build loxi
```

```sh
# file
odin build loxi
```

## Run

```sh
# repl
./loxi.bin
```

```sh
# file
./loxi.bin <filepath>
```

## Debug flags

```sh
# repl
odin run loxi -define:PRINT_CODE=true -define:TRACE_EXECUTION=true -define:LOG_GC=true
```

```sh
# file
odin run loxi -define:PRINT_CODE=true -define:TRACE_EXECUTION=true -define:LOG_GC=true -- <filepath>
```
