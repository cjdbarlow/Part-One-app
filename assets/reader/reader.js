(function () {
  "use strict";

  const highlightSelector = "mark[data-quarto-reader-highlight]";
  const marginSelector = [
    ".column-margin",
    ".margin-caption",
    ".tabset-margin-content",
    "div.aside",
    "aside:not(.footnotes):not(.sidebar)",
  ].join(",");

  function clearHighlights() {
    document.querySelectorAll(highlightSelector).forEach((mark) => {
      const parent = mark.parentNode;
      mark.replaceWith(document.createTextNode(mark.textContent || ""));
      if (parent) parent.normalize();
    });
    document.querySelectorAll(".qr-transient-reveal").forEach((element) => {
      element.classList.remove("qr-transient-reveal");
    });
  }

  function setSidenotesVisible(visible) {
    clearHighlights();
    document.body.classList.toggle("qr-sidenotes-visible", Boolean(visible));
    document.body.classList.toggle("qr-sidenotes-hidden", !visible);
  }

  function isExcludedTextNode(node) {
    const parent = node.parentElement;
    return !parent || Boolean(parent.closest("script,style,noscript,textarea,math,.math,.MathJax"));
  }

  function nextMatch(text, lowerTerms, start) {
    const lowerText = text.toLocaleLowerCase();
    let found = null;
    lowerTerms.forEach((term) => {
      const index = lowerText.indexOf(term, start);
      if (index < 0) return;
      if (!found || index < found.index || (index === found.index && term.length > found.length)) {
        found = { index: index, length: term.length };
      }
    });
    return found;
  }

  function markTextNode(node, lowerTerms) {
    const text = node.nodeValue || "";
    let match = nextMatch(text, lowerTerms, 0);
    if (!match) return [];

    const fragment = document.createDocumentFragment();
    const marks = [];
    let offset = 0;
    while (match) {
      if (match.index > offset) {
        fragment.append(document.createTextNode(text.slice(offset, match.index)));
      }
      const mark = document.createElement("mark");
      mark.className = "qr-search-highlight";
      mark.dataset.quartoReaderHighlight = "match";
      mark.textContent = text.slice(match.index, match.index + match.length);
      fragment.append(mark);
      marks.push(mark);
      offset = match.index + match.length;
      match = nextMatch(text, lowerTerms, offset);
    }
    if (offset < text.length) fragment.append(document.createTextNode(text.slice(offset)));
    node.replaceWith(fragment);
    return marks;
  }

  function visible(element) {
    return Boolean(element.getClientRects().length) &&
      window.getComputedStyle(element).visibility !== "hidden";
  }

  function normaliseTerm(value) {
    return value.toLocaleLowerCase().replace(/[^\p{L}\p{N}]/gu, "");
  }

  function pageTitleTerms(root) {
    const title = root.querySelector("#title-block-header h1, h1.title");
    if (!title) return new Set();
    return new Set(title.textContent.split(/\s+/).map(normaliseTerm).filter(Boolean));
  }

  function highlight(options) {
    clearHighlights();
    const settings = options && typeof options === "object" ? options : {};
    const terms = Array.isArray(settings.terms) ? settings.terms : [];
    const lowerTerms = Array.from(new Set(terms
      .filter((term) => typeof term === "string" && term.trim())
      .map((term) => term.toLocaleLowerCase())))
      .sort((first, second) => second.length - first.length);
    const anchorName = typeof settings.anchor === "string"
      ? settings.anchor.replace(/^#/, "")
      : "";
    const anchor = anchorName ? document.getElementById(anchorName) : null;

    if (!lowerTerms.length) {
      if (anchor) anchor.scrollIntoView({ block: "start" });
      return;
    }

    const root = document.querySelector("main#quarto-document-content") || document.body;
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
    const textNodes = [];
    while (walker.nextNode()) {
      if (!isExcludedTextNode(walker.currentNode)) textNodes.push(walker.currentNode);
    }

    const marks = textNodes.flatMap((node) => markTextNode(node, lowerTerms));
    marks.forEach((mark) => {
      const margin = mark.closest(marginSelector);
      if (margin && document.body.classList.contains("qr-sidenotes-hidden")) {
        margin.classList.add("qr-transient-reveal");
      }
    });

    const titleTerms = pageTitleTerms(root);
    const anchoredHit = anchor && anchor !== root
      ? marks.find((mark) => anchor.contains(mark) && visible(mark))
      : null;
    const relevantHit = marks.find((mark) =>
      visible(mark) && !titleTerms.has(normaliseTerm(mark.textContent || "")));
    const firstVisible = anchoredHit || relevantHit || marks.find(visible);
    if (firstVisible) firstVisible.dataset.quartoReaderHighlight = "active";
    const anchorIsSearchRoot = anchor === root || anchor?.id === "quarto-document-content";
    const destination = anchorIsSearchRoot
      ? firstVisible || anchor
      : anchor && visible(anchor) ? anchor : firstVisible;
    if (destination) destination.scrollIntoView({ block: "center" });
  }

  window.quartoReader = Object.freeze({
    setSidenotesVisible: setSidenotesVisible,
    highlight: highlight,
  });
})();
