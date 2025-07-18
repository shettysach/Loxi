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

        setTimeout(() => {
          const span = document.createElement("span");
          span.textContent = text;
          document.getElementById("output").appendChild(span);
        }, 0);
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

window.addEventListener("DOMContentLoaded", initWasm);

window.submitCode = () => {
  document.getElementById("output").textContent = "";
  instance.exports.run_file();
};

window.clearOutput = () => {
  document.getElementById("output").textContent = "";
};

const textarea = document.getElementById("code-input");
const lineNumbers = document.getElementById("line-numbers");

function updateLineNumbers() {
  const lines = textarea.value.split("\n").length;
  let numbers = "";
  for (let i = 1; i <= lines; i++) {
    numbers += i + "\n";
  }
  lineNumbers.textContent = numbers;
}

textarea.addEventListener("scroll", () => {
  lineNumbers.scrollTop = textarea.scrollTop;
});

window.addEventListener("load", updateLineNumbers);

textarea.addEventListener("cut", () => {
  setTimeout(updateLineNumbers, 0);
});

textarea.addEventListener("paste", () => {
  setTimeout(updateLineNumbers, 0);
});

textarea.addEventListener("keydown", function (e) {
  if (e.key === "Tab") {
    e.preventDefault();
    const start = this.selectionStart;
    const end = this.selectionEnd;

    this.value =
      this.value.substring(0, start) + "    " + this.value.substring(end);

    this.selectionStart = this.selectionEnd = start + 4;
  } else if (e.key === "Enter" && e.ctrlKey) {
    e.preventDefault();
    if (typeof window.submitCode === "function") {
      window.submitCode();
    }
  } else if (e.key === "Enter" || e.key === "Backspace") {
    setTimeout(updateLineNumbers, 0);
  }
});
