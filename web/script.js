let instance;

async function initWasm() {
  const res = await fetch("./loxi.wasm");
  const wasmBytes = await res.arrayBuffer();

  const imports = {
    odin_env: {
      write: () => {},
      time_now: () => BigInt(Date.now()) * 1_000_000n,
    },

    dom_interface: {
      read_in(ptr) {
        const mem = new Uint8Array(instance.exports.memory.buffer);
        const input = document.getElementById("code-input").value;
        const bytes = new TextEncoder().encode(input);
        const n = Math.min(bytes.length, 1024);
        mem.set(bytes.subarray(0, n), ptr);
        return n;
      },

      write_out(ptr, len) {
        const mem = new Uint8Array(instance.exports.memory.buffer);
        const text = new TextDecoder().decode(mem.subarray(ptr, ptr + len));

        const span = document.createElement("span");
        span.textContent = text;

        document.getElementById("output").appendChild(span);
      },

      write_err(ptr, len) {
        const mem = new Uint8Array(instance.exports.memory.buffer);
        const text = new TextDecoder().decode(mem.subarray(ptr, ptr + len));

        const errorSpan = document.createElement("span");
        errorSpan.style.color = "var(--err)";
        errorSpan.textContent = text;

        document.getElementById("output").appendChild(errorSpan);
      },
    },
  };

  const { instance: inst } = await WebAssembly.instantiate(wasmBytes, imports);
  instance = inst;
}

window.submitCode = () => {
  document.getElementById("output").textContent = "";
  instance.exports.run_file();
};

window.clearOutput = () => {
  document.getElementById("output").textContent = "";
};

window.addEventListener("DOMContentLoaded", initWasm);
