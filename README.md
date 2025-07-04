# Loxi

Lox bytecode interpreter in Odin.

> [!NOTE]
> You can use the Odin compiler's `-o:speed` flag for better performance. \
> `odin run loxi -o:speed --  eg/fib.lox`

## Build and run

### Repl
```sh
odin run loxi -define:REPL=true 
```

### File
```sh
odin run loxi -- <filepath>
```

## Build

### Repl
```sh
odin build loxi -define:REPL=true 
```

### File
```sh
odin build loxi 
```

## Run

### Repl
```sh
./loxi.bin
```

### File
```sh
./loxi.bin <filepath>
```

## Debug flags

### Repl
```sh
odin run loxi -define:PRINT_CODE=true -define:TRACE_EXECUTION=true -define:LOG_GC=true -define:REPL=true
```

### File
```sh
odin run loxi -define:PRINT_CODE=true -define:TRACE_EXECUTION=true -define:LOG_GC=true -- <filepath>
```

## Credits / Resources

- [Crafting Interpreters by Robert Nystorm](https://craftinginterpreters.com/) 
- [Nrosa01/OdinLox](https://github.com/Nrosa01/OdinLox)
