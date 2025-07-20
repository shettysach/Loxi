const textarea = document.getElementById("code-input");
const lineNumbers = document.getElementById("line-numbers");
const output = document.getElementById("output");

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

textarea.addEventListener("input", updateLineNumbers);

textarea.addEventListener("keydown", function (e) {
  if (e.key === "Tab") {
    e.preventDefault();
    const start = this.selectionStart;
    const end = this.selectionEnd;
    this.value =
      this.value.substring(0, start) + "  " + this.value.substring(end);
    this.selectionStart = this.selectionEnd = start + 2;
  } else if (e.key === "Enter" && e.ctrlKey) {
    e.preventDefault();
    window.submitCode();
  }
});

window.addEventListener("DOMContentLoaded", updateLineNumbers);
window.submitCode = () => {
  output.textContent = "";
  worker.postMessage({ code: textarea.value });
};
