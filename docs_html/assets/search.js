/* ═══════════════════════════════════════════════════════════════════
   syncitron Docs — Full-Text Fuzzy Search
   Loads search-index.json, indexes content with bigrams for
   similarity matching, and provides instant search results.
   ═══════════════════════════════════════════════════════════════════ */

(function () {
  'use strict';

  let INDEX = null;      // loaded from search-index.json
  let searchOpen = false;

  // ── Bigram helpers (fuzzy matching) ────────────────────────────────
  function bigrams(str) {
    const s = str.toLowerCase().trim();
    const set = new Set();
    for (let i = 0; i < s.length - 1; i++) set.add(s.slice(i, i + 2));
    return set;
  }

  function similarity(a, b) {
    if (!a || !b) return 0;
    const A = bigrams(a), B = bigrams(b);
    let inter = 0;
    for (const bg of A) if (B.has(bg)) inter++;
    const union = A.size + B.size - inter;
    return union === 0 ? 0 : inter / union;
  }

  // ── Tokenize & normalize ───────────────────────────────────────────
  function normalize(str) {
    return str.toLowerCase().replace(/[^a-z0-9äöüß]+/g, ' ').trim();
  }

  function tokens(str) {
    return normalize(str).split(/\s+/).filter(t => t.length > 1);
  }

  // ── Highlight matches ──────────────────────────────────────────────
  function highlight(text, queryTokens) {
    if (!text || !queryTokens.length) return text;
    // Escape regex chars
    const escaped = queryTokens.map(t => t.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'));
    const re = new RegExp('(' + escaped.join('|') + ')', 'gi');
    return text.replace(re, '<mark>$1</mark>');
  }

  // ── Extract snippet around match ───────────────────────────────────
  function snippet(text, queryTokens, maxLen) {
    maxLen = maxLen || 180;
    const lower = text.toLowerCase();
    let bestPos = -1;
    let bestScore = 0;
    for (const tok of queryTokens) {
      const idx = lower.indexOf(tok);
      if (idx !== -1 && tok.length > bestScore) {
        bestPos = idx;
        bestScore = tok.length;
      }
    }
    if (bestPos === -1) return text.slice(0, maxLen) + (text.length > maxLen ? '…' : '');

    const start = Math.max(0, bestPos - 60);
    const end = Math.min(text.length, bestPos + maxLen - 60);
    let snip = text.slice(start, end);
    if (start > 0) snip = '…' + snip;
    if (end < text.length) snip += '…';
    return snip;
  }

  // ── Score a single document against the query ──────────────────────
  function scoreDoc(doc, query, qTokens) {
    let score = 0;
    const titleLower = doc.title.toLowerCase();
    const queryLower = query.toLowerCase();

    // Exact substring in title → very high score
    if (titleLower.includes(queryLower)) score += 100;

    // Token matches in title
    for (const tok of qTokens) {
      if (titleLower.includes(tok)) score += 30;
    }

    // Fuzzy title match (bigram similarity)
    const titleSim = similarity(query, doc.title);
    score += titleSim * 40;

    // Section heading matches
    for (const sec of (doc.sections || [])) {
      const secLower = sec.toLowerCase();
      if (secLower.includes(queryLower)) score += 25;
      for (const tok of qTokens) {
        if (secLower.includes(tok)) score += 10;
      }
    }

    // Content matches (exact tokens)
    const contentLower = doc.content.toLowerCase();
    for (const tok of qTokens) {
      // Count occurrences (cap at 10 to avoid runaway scores)
      const re = new RegExp(tok.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'gi');
      const matches = contentLower.match(re);
      const count = matches ? Math.min(matches.length, 10) : 0;
      score += count * 3;
    }

    // Fuzzy match: for each query token, check bigram similarity against
    // high-value terms (section headings, title words)
    const docTerms = tokens(doc.title + ' ' + (doc.sections || []).join(' '));
    for (const tok of qTokens) {
      let bestSim = 0;
      for (const dt of docTerms) {
        const sim = similarity(tok, dt);
        if (sim > bestSim) bestSim = sim;
      }
      if (bestSim > 0.3) score += bestSim * 15;
    }

    return score;
  }

  // ── Main search function ───────────────────────────────────────────
  function search(query) {
    if (!INDEX || !query.trim()) return [];
    const q = query.trim();
    const qTokens = tokens(q);
    if (qTokens.length === 0) return [];

    const results = [];
    for (const doc of INDEX) {
      const score = scoreDoc(doc, q, qTokens);
      if (score > 5) {
        results.push({
          title: doc.title,
          url: doc.url,
          snippet: snippet(doc.content, qTokens),
          score: score,
        });
      }
    }

    results.sort((a, b) => b.score - a.score);
    return results.slice(0, 20);
  }

  // ── UI: Open / Close ──────────────────────────────────────────────
  function openSearch() {
    const overlay = document.getElementById('search-overlay');
    const input = document.getElementById('search-input');
    if (!overlay) return;
    overlay.classList.add('open');
    searchOpen = true;
    setTimeout(() => input && input.focus(), 100);
  }

  function closeSearch() {
    const overlay = document.getElementById('search-overlay');
    if (!overlay) return;
    overlay.classList.remove('open');
    searchOpen = false;
  }

  // ── UI: Render results ─────────────────────────────────────────────
  function renderResults(query) {
    const container = document.getElementById('search-results');
    if (!container) return;

    if (!query.trim()) {
      container.innerHTML =
        '<div class="search-empty">' +
        '<div class="search-empty-icon">🔍</div>' +
        '<p>Start typing to search across all documentation…</p>' +
        '<p class="search-hint">Supports fuzzy matching — typos are OK!</p>' +
        '</div>';
      return;
    }

    const results = search(query);
    const qTokens = tokens(query);

    if (results.length === 0) {
      container.innerHTML =
        '<div class="search-empty">' +
        '<div class="search-empty-icon">😕</div>' +
        '<p>No results for "<strong>' + escHtml(query) + '</strong>"</p>' +
        '<p class="search-hint">Try different keywords or check spelling</p>' +
        '</div>';
      return;
    }

    let html = '<div class="search-count">' + results.length +
      ' result' + (results.length !== 1 ? 's' : '') + '</div>';

    for (const r of results) {
      html +=
        '<a class="search-result" href="' + r.url + '">' +
        '<div class="search-result-title">' + highlight(escHtml(r.title), qTokens) + '</div>' +
        '<div class="search-result-url">' + r.url + '</div>' +
        '<div class="search-result-snippet">' + highlight(escHtml(r.snippet), qTokens) + '</div>' +
        '</a>';
    }

    container.innerHTML = html;
  }

  function escHtml(s) {
    return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }

  // ── Debounce ───────────────────────────────────────────────────────
  function debounce(fn, ms) {
    let timer;
    return function () {
      clearTimeout(timer);
      const args = arguments, ctx = this;
      timer = setTimeout(function () { fn.apply(ctx, args); }, ms);
    };
  }

  // ── Keyboard shortcut: Cmd/Ctrl+K or / ────────────────────────────
  document.addEventListener('keydown', function (e) {
    // Cmd/Ctrl+K
    if ((e.metaKey || e.ctrlKey) && e.key === 'k') {
      e.preventDefault();
      searchOpen ? closeSearch() : openSearch();
      return;
    }
    // "/" key (if not in an input)
    if (e.key === '/' && !['INPUT', 'TEXTAREA', 'SELECT'].includes(document.activeElement.tagName)) {
      e.preventDefault();
      openSearch();
      return;
    }
    // Escape
    if (e.key === 'Escape' && searchOpen) {
      closeSearch();
    }
  });

  // ── Initialize on DOM ready ────────────────────────────────────────
  document.addEventListener('DOMContentLoaded', function () {
    // Load search index
    fetch('search-index.json')
      .then(function (r) { return r.json(); })
      .then(function (data) { INDEX = data; })
      .catch(function (err) { console.warn('Search index not loaded:', err); });

    // Wire up input
    const input = document.getElementById('search-input');
    if (input) {
      input.addEventListener('input', debounce(function () {
        renderResults(input.value);
      }, 150));
    }

    // Close on overlay background click
    const overlay = document.getElementById('search-overlay');
    if (overlay) {
      overlay.addEventListener('click', function (e) {
        if (e.target === overlay) closeSearch();
      });
    }

    // Close button
    const closeBtn = document.getElementById('search-close');
    if (closeBtn) closeBtn.addEventListener('click', closeSearch);
  });

  // Expose for topbar button
  window.openSearch = openSearch;
  window.closeSearch = closeSearch;
})();
