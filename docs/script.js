const textarea = document.getElementById("code-input");
const lineNumbers = document.getElementById("line-numbers");
const highlightedCode = document.getElementById("highlighted-code");
const output = document.getElementById("output");
const dropdown = document.getElementById("example-dropdown");

const worker = new Worker("./worker.js");

worker.onmessage = ({ data }) => {
  const span = document.createElement("span");
  span.textContent = data.text;
  if (data.type === "err") span.style.color = "var(--err)";
  output.appendChild(span);
};

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
  const scrollTop = textarea.scrollTop;
  const scrollLeft = textarea.scrollLeft;

  highlightedCode.parentElement.scrollTop = scrollTop;
  highlightedCode.parentElement.scrollLeft = scrollLeft;
  lineNumbers.scrollTop = scrollTop;
}

textarea.addEventListener("input", updateHighlighting);
textarea.addEventListener("scroll", syncScroll);

document.addEventListener("keydown", function (e) {
  if (e.key === "Tab" && document.activeElement === textarea) {
    e.preventDefault();
    const start = textarea.selectionStart;
    const end = textarea.selectionEnd;
    textarea.value =
      textarea.value.substring(0, start) + "\t" + textarea.value.substring(end);
    textarea.selectionStart = textarea.selectionEnd = start + 1;
    updateHighlighting();
  } else if (e.key === "Enter" && e.ctrlKey) {
    e.preventDefault();
    window.submitCode();
  }
});

window.addEventListener("DOMContentLoaded", () => {
  updateHighlighting();
  loadExamples();
});

window.submitCode = () => {
  output.textContent = "";
  worker.postMessage({ code: textarea.value });
};

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
