let instance;

async function init() {
  const res = await fetch("./loxi.wasm");
  const wasmBytes = await res.arrayBuffer();

  const imports = {
    odin_env: {
      write: () => {},
      time_now: () => BigInt(Date.now()),
    },
    dom_interface: {
      read_in(ptr) {
        const mem = new Uint8Array(instance.exports.memory.buffer);
        const bytes = new TextEncoder().encode(currentInput);
        mem.set(bytes.subarray(0, 4096), ptr);
        return Math.min(bytes.length, 4096);
      },
      write_out(ptr, len) {
        const mem = new Uint8Array(instance.exports.memory.buffer);
        const text = new TextDecoder().decode(mem.subarray(ptr, ptr + len));
        postMessage({ type: "out", text });
      },
      write_err(ptr, len) {
        const mem = new Uint8Array(instance.exports.memory.buffer);
        const text = new TextDecoder().decode(mem.subarray(ptr, ptr + len));
        postMessage({ type: "err", text });
      },
    },
  };

  const { instance: inst } = await WebAssembly.instantiate(wasmBytes, imports);
  instance = inst;
}

let currentInput = "";
let replActive = false;

onmessage = async ({ data }) => {
  if (!instance) await init();

  switch (data.type) {
    case "run_file":
      currentInput = String(data.code);
      instance.exports.run_file();
      break;
    case "init_repl":
      instance.exports.init_repl();
      replActive = true;
      postMessage({ type: "prompt", braces: 0 });
      break;
    case "repl_line":
      currentInput = String(data.line);
      const braces = instance.exports.repl_line();
      postMessage({ type: "prompt", braces });
      break;
    case "free_repl":
      if (replActive) {
        instance.exports.free_repl();
        replActive = false;
      }
      break;
  }
};
