# Loxi

Bytecode interpreter for [the Lox language](https://craftinginterpreters.com/the-lox-language.html) with a mark and sweep garbage collector, based on the second half of [Crafting Interpreters by Robert Nystorm](https://craftinginterpreters.com/).

You can use the [WASM playground](https://shettysach.github.io/Loxi/) hosted on GitHub Pages. 

## Lists

Also supports lists and has additional native functions. Credits to [Caleb Schoepp's blog](https://calebschoepp.com/blog/2020/adding-a-list-data-type-to-lox/). 

```c
var l = [1, 2, 3, 4, 5];
print "List";
print l; // [1, 2, 3, 4, 5]

print "Append";
append(l, 6);
print l; // [1, 2, 3, 4, 5, 6];

print "Insert";
insert(l, 0, -1);
print l; // [-1, 1, 2, 3, 4, 5, 6];

print "Pop";
print pop(l); // 6

print "Delete";
delete(l, 0);
print l; // [1, 2, 3, 4, 5];

fun reverse(l) {
    var n = len(l); // also works on strings

    for (var i = 0; i < n / 2; i = i + 1) {
        var tmp = l[i];
        l[i] = l[n - 1 - i];
        l[n - 1 - i] = tmp;
    }
}

print "Reversed";
reverse(l);
print l; // [5, 4, 3, 2, 1];

var x = list(0, 5); 
print x; // [0, 0, 0, 0, 0]
x[1] = "hello";
x[2] = reverse;
x[3] = "world";
print x; // [0, hello, <fn reverse>, world, 0]
x[2](x); // [0, world, <fn reverse>, hello, 0]
print x;
```

```c
var fib = [0, 1]; 
for (var i=0; i<15; i=i+1) append(fib, fib[-1] + fib[-2]);

print "Fibonacci numbers";
print fib; // [0, 1, 1, 2, 3, 5, 8, 13, 21, 34, 55, 89, 144, 233, 377, 610, 987]
```


> [!NOTE]
> ### Flags
> - Use the Odin compiler's optimization flags, such as `-o:speed` flag on the below commands.
> - For NaN boxing, you can use the flag `-define:NAN_BOXING=true` on the below commands.
> - You can use the debug flags `-define:PRINT_CODE=true`,  `-define:TRACE_EXECUTION=true` and `-define:LOG_GC=true`.

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
odin build loxi
```

## Run

```sh
# repl
./loxi.bin # unix

.\loxi.exe # windows
```

```sh
# file
./loxi.bin <filepath> # unix

.\loxi.exe <filepath> # windows
```

## WASM

```sh
git switch wasm
odin build ./loxi -target:js_wasm32 -out:./docs/loxi.wasm -no-entry-point -o:speed
miniserve ./docs --index ./docs/index.html
```
