let instance;

async function init() {
  const res = await fetch("./loxi.wasm");
  const wasmBytes = await res.arrayBuffer();

  const imports = {
    odin_env: {
      write: () => {},
      time_now: () => BigInt(Date.now()) * 1_0n,
    },
    dom_interface: {
      read_in(ptr) {
        const mem = new Uint8Array(instance.exports.memory.buffer);
        const bytes = new TextEncoder().encode(currentInput);
        mem.set(bytes.subarray(0, 1024), ptr);
        return Math.min(bytes.length, 1024);
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

onmessage = async ({ data }) => {
  if (!instance) await init();
  currentInput = data.code;
  instance.exports.run_file();
};
