let instance;

async function initWasm() {
  const res = await fetch("./loxi.wasm");
  const wasmBytes = await res.arrayBuffer();

const imports = {
	odin_env:{
    cos: Math.cos,
    sin: Math.sin,
    sqrt: Math.sqrt,
    floor: Math.floor,
    ceil: Math.ceil,
    trunc: Math.trunc,
    log: Math.log,
    exp: Math.exp,
    pow: Math.pow,
    atan2: Math.atan2,
    tan: Math.tan,
    write: () => {},
    time_now: () => {},
    mem_set_allocator: () => {}, // no-op placeholder
    mem_get_allocator: () => 0,
    mem_free: () => {}


	},
    
  dom_interface: {
    read_input(ptr, len) {
      const mem = new Uint8Array(instance.exports.memory.buffer);
      const input = document.getElementById("code-input").value + "\n";
      const encoded = new TextEncoder().encode(input);
      const n = Math.min(encoded.length, len);
      mem.set(encoded.subarray(0, n), ptr);
      return n;
    },
    write_output(ptr, len) {
      const mem = new Uint8Array(instance.exports.memory.buffer);
      const slice = mem.subarray(ptr, ptr + len);
      const text = new TextDecoder().decode(slice);
      document.getElementById("output").textContent += text;
    }
  },

  };

  const { instance: inst } = await WebAssembly.instantiate(wasmBytes, imports);
  instance = inst;
}

// Called when "Send" is clicked
window.submitCode = () => {
  document.getElementById("output").textContent = "";  // clear previous
  instance.exports.run_file();                         // call your Odin function
};

// Clears the output pane
window.clearOutput = () => {
  document.getElementById("output").textContent = "";
};

// Initialize WASM on page load
initWasm();
