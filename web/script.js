let instance;

async function initWasm() {
  const res = await fetch("./loxi.wasm");
  const wasmBytes = await res.arrayBuffer();

  const imports = {
    odin_env: {
      write: () => {},
      time_now: Date.now
    },

    dom_interface: {
      // Odin expects: proc(buffer: [4096]u8) -> int
      read_input(ptr) {
        const mem = new Uint8Array(instance.exports.memory.buffer);
        const input = document.getElementById("code-input").value;
        const bytes = new TextEncoder().encode(input);
        const n = Math.min(bytes.length, 1024);
        mem.set(bytes.subarray(0, n), ptr);
        return n;
      },

      // Odin expects: proc(out: string) --- (lowered as ptr + len)
      write_output(ptr, len) {
        const mem = new Uint8Array(instance.exports.memory.buffer);
        const text = new TextDecoder().decode(mem.subarray(ptr, ptr + len));
        document.getElementById("output").textContent += text;
      }
    }
  };

  const { instance: inst } = await WebAssembly.instantiate(wasmBytes, imports);
  instance = inst;
  instance.exports.setup();
}


window.submitCode = () => {
  document.getElementById("output").textContent = "";
  instance.exports.run_file();
};

window.clearOutput = () => {
  document.getElementById("output").textContent = "";
};

window.addEventListener("DOMContentLoaded", initWasm);
