# Loxi

Lox bytecode interpreter in Odin.

> [!NOTE]
> - You can use the Odin compiler's `-o:speed` flag for better performance.
> - You can use NaN boxing for better cache locality. Tested only on x86_64.
>```sh
>odin run loxi -o:speed -define:NAN_BOXING=true -- eg/fib.lox 
>```

## Build and run

```sh
# repl
odin run loxi -define:REPL=true 
```

```sh
# file
odin run loxi -- <filepath>
```

## Build

```sh
# repl
odin build loxi -define:REPL=true 
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
odin run loxi -define:PRINT_CODE=true -define:TRACE_EXECUTION=true -define:LOG_GC=true -define:REPL=true
```

```sh
# file
odin run loxi -define:PRINT_CODE=true -define:TRACE_EXECUTION=true -define:LOG_GC=true -- <filepath>
```

## Credits / Resources

- [Crafting Interpreters by Robert Nystorm](https://craftinginterpreters.com/) 
