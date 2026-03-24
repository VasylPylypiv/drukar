// Flips spellcheck="false" to "true" on chat input elements in Cursor
// Used via apc.imports in Cursor settings
(function() {
  const observer = new MutationObserver(function() {
    document.querySelectorAll('[spellcheck="false"]').forEach(function(el) {
      if (el.isContentEditable || el.tagName === 'TEXTAREA' || el.tagName === 'INPUT') {
        el.setAttribute('spellcheck', 'true');
      }
    });
  });
  observer.observe(document.body, { childList: true, subtree: true, attributes: true, attributeFilter: ['spellcheck'] });
  // Initial pass
  document.querySelectorAll('[spellcheck="false"]').forEach(function(el) {
    if (el.isContentEditable || el.tagName === 'TEXTAREA' || el.tagName === 'INPUT') {
      el.setAttribute('spellcheck', 'true');
    }
  });
})();
