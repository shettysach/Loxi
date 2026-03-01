/* ── DOM refs ─────────────────────────────────────────── */

const textarea = document.getElementById("code-input");
const lineNumbers = document.getElementById("line-numbers");
const highlightedCode = document.getElementById("highlighted-code");
const output = document.getElementById("output");
const dropdown = document.getElementById("example-dropdown");
const fileMode = document.getElementById("file-mode");
const replMode = document.getElementById("repl-mode");
const replHistory = document.getElementById("repl-history");
const replInput = document.getElementById("repl-input");
const replHighlighted = document.getElementById("repl-highlighted");
const replPrompt = document.getElementById("repl-prompt");
const replScroll = document.getElementById("repl-scroll");
const fileControls = document.getElementById("file-controls");
const tabButtons = document.querySelectorAll("#tab-bar .tab");
const mainEl = document.getElementById("main");

/* ── Constants ───────────────────────────────────────── */

const INPUT_LIMIT = 4096;
const REPL_HISTORY_MAX = 10;
const encoder = new TextEncoder();

/* ── Worker ──────────────────────────────────────────── */

const worker = new Worker("./worker.js");
let currentMode = "file";

worker.onmessage = ({ data }) => {
  if (data.type === "prompt") {
    replPrompt.textContent = data.braces > 0 ? "• " : "> ";
    replScroll.scrollTop = replScroll.scrollHeight;
    replInput.focus();
    return;
  }

  if (currentMode === "repl") {
    const span = document.createElement("span");
    span.textContent = data.text;
    span.className = data.type === "err" ? "repl-err" : "repl-out";
    replHistory.appendChild(span);
    replScroll.scrollTop = replScroll.scrollHeight;
  } else {
    const span = document.createElement("span");
    span.textContent = data.text;
    if (data.type === "err") span.style.color = "var(--err)";
    output.appendChild(span);
  }
};

/* ── File editor ─────────────────────────────────────── */

function updateLineNumbers() {
  const lines = textarea.value.split("\n").length;
  lineNumbers.textContent = Array.from({ length: lines }, (_, i) => i + 1).join(
    "\n",
  );
}

function updateHighlighting() {
  highlightedCode.textContent = textarea.value;
  hljs.highlightElement(highlightedCode);
  updateLineNumbers();
}

function syncScroll() {
  highlightedCode.parentElement.scrollTop = textarea.scrollTop;
  highlightedCode.parentElement.scrollLeft = textarea.scrollLeft;
  lineNumbers.scrollTop = textarea.scrollTop;
}

textarea.addEventListener("input", updateHighlighting);
textarea.addEventListener("scroll", syncScroll);

window.submitCode = () => {
  output.textContent = "";
  const code = textarea.value;
  if (encoder.encode(code).length > INPUT_LIMIT) {
    const span = document.createElement("span");
    span.style.color = "var(--err)";
    span.textContent = "Input exceeds 4096 byte limit.\n";
    output.appendChild(span);
    return;
  }
  worker.postMessage({ type: "run_file", code });
};

/* ── REPL ────────────────────────────────────────────── */

const replCommandHistory = [];
let replHistoryIndex = -1;

function updateReplHighlighting() {
  replHighlighted.textContent = replInput.value;
  hljs.highlightElement(replHighlighted);
}

replInput.addEventListener("input", updateReplHighlighting);

function submitReplLine() {
  const line = replInput.value;
  if (line === "" && replPrompt.textContent.trim() === ">") return;

  if (
    line !== "" &&
    line !== replCommandHistory[replCommandHistory.length - 1]
  ) {
    replCommandHistory.push(line);
    if (replCommandHistory.length > REPL_HISTORY_MAX)
      replCommandHistory.shift();
  }
  replHistoryIndex = replCommandHistory.length;

  const entry = document.createElement("div");
  entry.className = "repl-entry";

  const prompt = document.createElement("span");
  prompt.className = "repl-prompt-char";
  prompt.textContent = replPrompt.textContent;

  const code = document.createElement("code");
  code.className = "language-lox";
  code.textContent = line;
  hljs.highlightElement(code);

  entry.appendChild(prompt);
  entry.appendChild(code);
  replHistory.appendChild(entry);

  replInput.value = "";
  updateReplHighlighting();

  const payload = line + "\n";
  if (encoder.encode(payload).length > INPUT_LIMIT) {
    const err = document.createElement("span");
    err.className = "repl-err";
    err.textContent = "Input exceeds 4096 byte limit.\n";
    replHistory.appendChild(err);
    replScroll.scrollTop = replScroll.scrollHeight;
    return;
  }

  worker.postMessage({ type: "repl_line", line: payload });
  replScroll.scrollTop = replScroll.scrollHeight;
}

/* ── Key handling ────────────────────────────────────── */

function insertTab(el, updateFn) {
  const start = el.selectionStart;
  const end = el.selectionEnd;
  el.value = el.value.substring(0, start) + "\t" + el.value.substring(end);
  el.selectionStart = el.selectionEnd = start + 1;
  updateFn();
}

document.addEventListener("keydown", (e) => {
  if (e.key === "Tab" && document.activeElement === textarea) {
    e.preventDefault();
    insertTab(textarea, updateHighlighting);
  } else if (e.key === "Tab" && document.activeElement === replInput) {
    e.preventDefault();
    insertTab(replInput, updateReplHighlighting);
  } else if (e.key === "Enter" && e.ctrlKey) {
    e.preventDefault();
    if (currentMode === "file") window.submitCode();
  } else if (e.key === "Enter" && document.activeElement === replInput) {
    e.preventDefault();
    submitReplLine();
  } else if (
    e.key === "ArrowUp" &&
    document.activeElement === replInput &&
    replInput.value.lastIndexOf("\n", replInput.selectionStart - 1) === -1 &&
    replCommandHistory.length > 0
  ) {
    e.preventDefault();
    if (replHistoryIndex > 0) replHistoryIndex--;
    replInput.value = replCommandHistory[replHistoryIndex];
    updateReplHighlighting();
  } else if (
    e.key === "ArrowDown" &&
    document.activeElement === replInput &&
    replInput.value.indexOf("\n", replInput.selectionStart) === -1 &&
    replCommandHistory.length > 0 &&
    replHistoryIndex < replCommandHistory.length - 1
  ) {
    e.preventDefault();
    replHistoryIndex++;
    replInput.value = replCommandHistory[replHistoryIndex];
    updateReplHighlighting();
  }
});

/* ── Tab switching ───────────────────────────────────── */

function switchTab(mode) {
  if (mode === currentMode) return;
  currentMode = mode;

  tabButtons.forEach((btn) => {
    btn.classList.toggle("active", btn.dataset.tab === mode);
  });

  if (mode === "repl") {
    fileMode.style.display = "none";
    replMode.style.display = "flex";
    mainEl.classList.add("repl-active");
    fileControls.style.display = "none";
    output.textContent = "";
    replHistory.innerHTML = "";
    replPrompt.textContent = "> ";
    replHistoryIndex = replCommandHistory.length;
    worker.postMessage({ type: "init_repl" });
    replInput.focus();
  } else {
    replMode.style.display = "none";
    fileMode.style.display = "flex";
    mainEl.classList.remove("repl-active");
    fileControls.style.display = "flex";
    worker.postMessage({ type: "free_repl" });
  }
}

tabButtons.forEach((btn) => {
  btn.addEventListener("click", () => switchTab(btn.dataset.tab));
});

/* ── Examples ────────────────────────────────────────── */

let examples = {};

async function loadExamples() {
  const response = await fetch("./examples.json");
  examples = await response.json();

  for (const [key, value] of Object.entries(examples)) {
    const option = document.createElement("option");
    option.value = key;
    option.textContent = key;
    dropdown.appendChild(option);
  }
}

dropdown.addEventListener("change", (e) => {
  const selectedExample = e.target.value;
  if (examples[selectedExample]) {
    textarea.value = examples[selectedExample];
    updateHighlighting();
  }
});

/* ── Init ────────────────────────────────────────────── */

window.addEventListener("DOMContentLoaded", () => {
  updateHighlighting();
  loadExamples();
});
