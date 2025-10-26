// docs/lox.js
// Highlight.js language definition for Lox
(function () {
  function lox(hljs) {
    const IDENT = hljs.IDENT_RE;

    return {
      name: "Lox",
      keywords: {
        keyword:
          "and class else false for fun if nil or print return super this true var while list append insert delete push pop clock",
        literal: "true false nil",
        built_in: "clock",
      },
      contains: [
        // Line comments
        hljs.COMMENT("//", "$"),
        // Block comments
        hljs.COMMENT("/\\*", "\\*/", { contains: ["self"] }),

        // Strings: double-quoted with escapes
        {
          className: "string",
          begin: '"',
          end: '"',
          contains: [{ className: "subst", begin: "\\\\.", relevance: 0 }],
        },

        // Numbers: integers and decimals
        {
          className: "number",
          variants: [{ begin: "\\b\\d+(?:\\.\\d+)?\\b" }],
          relevance: 0,
        },

        // Function definitions: fun name(...)
        {
          className: "function",
          beginKeywords: "fun",
          end: "\\(",
          excludeEnd: true,
          contains: [{ className: "title", begin: IDENT, relevance: 0 }],
        },

        // Class definitions: class Name { ... }
        {
          className: "class",
          beginKeywords: "class",
          end: "\\{",
          excludeEnd: true,
          contains: [{ className: "title", begin: IDENT, relevance: 0 }],
        },

        // Property/method access: .name
        {
          className: "built_in",
          begin: "\\." + IDENT,
          relevance: 0,
        },

        // Operators
        {
          className: "operator",
          begin: /(==|!=|<=|>=|=|!|<|>|\+|-|\*|\/|%)/,
          relevance: 0,
        },

        // Identifiers (optional mild highlighting)
        // { className: "variable", begin: "\\b" + IDENT + "\\b", relevance: 0 },
      ],
    };
  }

  if (typeof window !== "undefined" && window.hljs) {
    window.hljs.registerLanguage("lox", lox);
  } else if (typeof module !== "undefined") {
    module.exports = lox;
  }
})();
