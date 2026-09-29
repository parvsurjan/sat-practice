'use strict';

/* ============================== Store ============================== */

const MASTERY_STREAK = 2;
const REVIEW_INTERVAL_DAYS = 14;
const SAVE_KEY = 'satprep_save_v1';
const FILTERS_KEY = 'satprep_filters_v1';

const Store = {
  questions: [],
  byID: {},
  save: { progress: {}, history: [] },

  async loadQuestions() {
    const [rw, math] = await Promise.all([
      fetch('data/questions.json').then(r => r.json()),
      fetch('data/math-questions.json').then(r => r.ok ? r.json() : []).catch(() => [])
    ]);
    for (const q of rw) q.section = 'rw';
    for (const q of math) q.section = 'math';
    this.questions = rw.concat(math);
    this.byID = {};
    for (const q of this.questions) this.byID[q.id] = q;
  },

  loadSave() {
    try {
      const raw = localStorage.getItem(SAVE_KEY);
      if (raw) this.save = JSON.parse(raw);
    } catch (e) { /* corrupt or unavailable — start fresh */ }
    if (!this.save.progress) this.save.progress = {};
    if (!this.save.history) this.save.history = [];
  },

  persist() {
    try { localStorage.setItem(SAVE_KEY, JSON.stringify(this.save)); }
    catch (e) { /* storage full or unavailable */ }
  },

  question(id) { return this.byID[id]; },

  progress(id) {
    return this.save.progress[id] || {
      seen: 0, correct: 0, wrong: 0, streak: 0,
      everWrong: false, retired: false, bookmarked: false, lastAnswered: null
    };
  },

  isInWrongQueue(p) { return p.everWrong && !p.retired; },

  reviewUnlocksAt(p) {
    if (!this.isInWrongQueue(p) || !p.lastAnswered) return null;
    const d = new Date(p.lastAnswered);
    d.setDate(d.getDate() + REVIEW_INTERVAL_DAYS);
    return d;
  },

  isReviewLocked(p, now = new Date()) {
    const unlocks = this.reviewUnlocksAt(p);
    return unlocks ? now < unlocks : false;
  },

  domains() {
    return Array.from(new Set(this.questions.map(q => q.domain))).sort();
  },

  record(question, chosenIndex) {
    return this.recordResult(question, chosenIndex === question.correct);
  },

  recordResult(question, right) {
    const p = this.progress(question.id);
    p.seen += 1;
    p.lastAnswered = new Date().toISOString();
    if (right) {
      p.correct += 1;
      p.streak += 1;
      if (p.everWrong && p.streak >= MASTERY_STREAK) p.retired = true;
    } else {
      p.wrong += 1;
      p.streak = 0;
      p.everWrong = true;
      p.retired = false;
    }
    this.save.progress[question.id] = p;
    this.save.history.push({
      questionID: question.id, wasCorrect: right, date: new Date().toISOString(),
      exam: question.exam, difficulty: question.difficulty,
      domain: question.domain, skill: question.skill
    });
    this.persist();
    this.resetIfCycleComplete();
    return right;
  },

  resetIfCycleComplete() {
    const ids = this.questions.map(q => q.id);
    const complete = ids.length > 0 && ids.every(id => {
      const p = this.progress(id);
      return p.seen > 0 && !this.isInWrongQueue(p);
    });
    if (complete) this.resetAll();
  },

  toggleBookmark(id) {
    const p = this.progress(id);
    p.bookmarked = !p.bookmarked;
    this.save.progress[id] = p;
    this.persist();
  },

  resetAll() {
    this.save = { progress: {}, history: [] };
    this.persist();
  },

  bookmarkedQuestions() {
    return this.questions.filter(q => this.progress(q.id).bookmarked);
  },

  needsWork() {
    return this.questions.filter(q => this.isInWrongQueue(this.progress(q.id)));
  },

  needsWorkByUnlock(now = new Date()) {
    return this.needsWork().slice().sort((a, b) => {
      const ua = this.reviewUnlocksAt(this.progress(a.id)) || new Date(-8640000000000000);
      const ub = this.reviewUnlocksAt(this.progress(b.id)) || new Date(-8640000000000000);
      const la = ua > now, lb = ub > now;
      if (la !== lb) return la ? 1 : -1;
      return la ? ua - ub : 0;
    });
  },

  everMissed(filterFn) {
    return this.questions.filter(q => this.progress(q.id).everWrong && filterFn(q));
  },

  nextQuestion({ exams = new Set(), sections = new Set(), difficulties = new Set(), domains = new Set(), excluding = null }) {
    let pool = this.questions.filter(q =>
      (exams.size === 0 || exams.has(q.exam)) &&
      (sections.size === 0 || sections.has(q.section)) &&
      (difficulties.size === 0 || difficulties.has(q.difficulty)) &&
      (domains.size === 0 || domains.has(q.domain))
    );
    if (pool.length > 1 && excluding) pool = pool.filter(q => q.id !== excluding);
    if (pool.length === 0) return null;
    const unseen = pool.filter(q => this.progress(q.id).seen === 0);
    const from = unseen.length ? unseen : pool;
    return from[Math.floor(Math.random() * from.length)];
  }
};

/* ============================== Helpers ============================== */

function escapeHtml(s) {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

const UNDERLINE_ON = '', UNDERLINE_OFF = '';

function stripUnderlineMarkers(s) {
  return s.split(UNDERLINE_ON).join('').split(UNDERLINE_OFF).join('');
}

function styledHtml(s) {
  let out = '', underlined = false, run = '';
  const flush = () => {
    if (!run) return;
    out += underlined ? `<u>${escapeHtml(run)}</u>` : escapeHtml(run);
    run = '';
  };
  for (const ch of s) {
    if (ch === UNDERLINE_ON) { flush(); underlined = true; }
    else if (ch === UNDERLINE_OFF) { flush(); underlined = false; }
    else { run += ch; }
  }
  flush();
  return out;
}

function letterOf(i) { return String.fromCharCode(65 + i); }

function stemParts(stem) {
  const paras = stem.split('\n').filter(p => p.length > 0);
  if (paras.length === 0) return { passage: [], prompt: null };
  const last = paras[paras.length - 1];
  const stripped = stripUnderlineMarkers(last);
  if (stripped.endsWith('?') || stripped.endsWith(':')) {
    return { passage: paras.slice(0, -1), prompt: last };
  }
  return { passage: paras, prompt: null };
}

function stemHtml(stem) {
  const { passage, prompt } = stemParts(stem);
  let html = '<div class="stem">';
  for (const p of passage) html += `<p>${styledHtml(p)}</p>`;
  if (prompt) html += `<p class="prompt">${styledHtml(prompt)}</p>`;
  html += '</div>';
  return html;
}

function examBadge(exam) {
  return `<span class="badge badge-exam ${exam.toLowerCase()}">${exam}</span>`;
}
function difficultyBadge(diff) {
  return `<span class="badge badge-difficulty ${diff.toLowerCase()}">${diff.toUpperCase()}</span>`;
}
function tagBadge(text) {
  return `<span class="badge badge-tag">${escapeHtml(text)}</span>`;
}

function figuresHtml(figures) {
  return figures.map(name =>
    `<div class="figure-wrap" data-action="zoom" data-src="data/figures/${encodeURIComponent(name)}">
      <img src="data/figures/${encodeURIComponent(name)}" loading="lazy" alt="Figure">
    </div>`
  ).join('');
}

function fmtShortDate(d) {
  return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
}
function fmtLongDate(d) {
  return d.toLocaleDateString('en-US', { month: 'long', day: 'numeric', year: 'numeric' });
}

function mathImg(file) { return `data/math-figures/${encodeURIComponent(file)}`; }

function mathImagesHtml(files, cls) {
  return (files || []).map(f =>
    `<img class="${cls}" src="${mathImg(f)}" loading="lazy" alt="">`
  ).join('');
}

/** Loose equivalence for student-produced-response answers: exact string match
 *  (after trimming whitespace) or numeric match within a small tolerance, since
 *  College Board lists accepted answers as fractions, decimals, or both. */
function sprAnswerMatches(entered, accepted) {
  const norm = s => s.replace(/\s+/g, '');
  const e = norm(entered);
  if (!e) return false;
  if (accepted.some(a => norm(a) === e)) return true;
  const toNum = s => {
    const m = s.match(/^-?\d+\/\d+$/);
    if (m) { const [n, d] = s.split('/').map(Number); return d ? n / d : NaN; }
    return Number(s);
  };
  const eNum = toNum(e);
  if (Number.isNaN(eNum)) return false;
  return accepted.some(a => {
    const aNum = toNum(norm(a));
    return !Number.isNaN(aNum) && Math.abs(aNum - eNum) < 0.01;
  });
}

function questionPreviewHtml(q) {
  if (q.section === 'math') {
    const first = (q.stemImages || [])[0];
    return first ? `<img class="list-row-thumb" src="${mathImg(first)}" loading="lazy" alt="">` : '';
  }
  return `<div class="list-row-stem">${escapeHtml(stripUnderlineMarkers(q.stem))}</div>`;
}

function openZoom(src) {
  const root = document.getElementById('modal-root');
  const div = document.createElement('div');
  div.className = 'zoom-backdrop';
  div.innerHTML = `<button class="zoom-close" data-action="close-zoom">✕</button><img src="${src}" alt="Figure enlarged">`;
  div.addEventListener('click', (e) => {
    if (e.target === div || e.target.dataset.action === 'close-zoom') div.remove();
  });
  root.appendChild(div);
}

/* ============================== Question card controller ============================== */

/**
 * Renders an interactive question card + answer bar into `mount`.
 * config: {
 *   recordAnswer: bool,
 *   allowBookmark: bool,
 *   submitLabel, nextLabel: string,
 *   infoBannerHtml: string|null   (shown above the card, e.g. "practice only")
 *   captureBefore: () => any      (called right before recording, e.g. to snapshot queue state)
 *   afterSubmit: (before, question, wasCorrect) => string|null   (extra banner html after result)
 *   onNext: () => void
 * }
 */
function mountQuestionScreen(mount, question, config) {
  const isMath = question.section === 'math';
  const isSpr = isMath && question.type === 'spr';
  const state = {
    selection: null,       // choice index (mc) or typed string (spr)
    submitted: false,
    crossOutEnabled: false,
    crossedOut: new Set(),
    extraBanner: null
  };

  function choiceState(i) {
    if (!state.submitted) return state.selection === i ? 'selected' : 'idle';
    if (i === question.correct) return 'correct';
    if (i === state.selection) return 'wrong';
    return 'idle';
  }

  function hasSelection() {
    return isSpr ? !!(state.selection && state.selection.trim()) : state.selection !== null;
  }

  function bodyHtml() {
    if (isMath) {
      let html = mathImagesHtml(question.stemImages, 'stem-img');
      if (isSpr) {
        html += `<div class="spr-row">
          <input type="text" class="spr-input" data-action="spr-input" placeholder="Enter your answer"
                 value="${escapeHtml(state.selection || '')}" ${state.submitted ? 'disabled' : ''}>
        </div>`;
      } else {
        html += `<div class="choices">
          ${(question.choiceImages || []).map((files, i) => {
            const st = choiceState(i);
            const crossed = state.crossedOut.has(i);
            const showAbc = state.crossOutEnabled && !state.submitted;
            return `<div class="choice-row ${st}">
              <button class="choice-main" data-action="select" data-index="${i}">
                <span class="choice-letter">${letterOf(i)}</span>
                <span class="choice-text choice-text-img ${crossed ? 'crossed' : ''}">${mathImagesHtml(files, 'choice-img')}</span>
                ${st === 'correct' ? '<span class="choice-result-icon correct">✓</span>' : ''}
                ${st === 'wrong' ? '<span class="choice-result-icon wrong">✕</span>' : ''}
              </button>
              ${showAbc ? `<button class="choice-abc ${crossed ? 'crossed-off' : ''}" data-action="crossout" data-index="${i}">${crossed ? 'Undo' : 'ABC'}</button>` : ''}
            </div>`;
          }).join('')}
        </div>`;
      }
      return html;
    }
    return `${figuresHtml(question.figures || [])}${stemHtml(question.stem)}
      <div class="choices">
        ${question.choices.map((c, i) => {
          const st = choiceState(i);
          const crossed = state.crossedOut.has(i);
          const showAbc = state.crossOutEnabled && !state.submitted;
          return `<div class="choice-row ${st}">
            <button class="choice-main" data-action="select" data-index="${i}">
              <span class="choice-letter">${letterOf(i)}</span>
              <span class="choice-text ${crossed ? 'crossed' : ''}">${escapeHtml(c)}</span>
              ${st === 'correct' ? '<span class="choice-result-icon correct">✓</span>' : ''}
              ${st === 'wrong' ? '<span class="choice-result-icon wrong">✕</span>' : ''}
            </button>
            ${showAbc ? `<button class="choice-abc ${crossed ? 'crossed-off' : ''}" data-action="crossout" data-index="${i}">${crossed ? 'Undo' : 'ABC'}</button>` : ''}
          </div>`;
        }).join('')}
      </div>`;
  }

  function render() {
    const p = Store.progress(question.id);
    let html = '';
    if (config.infoBannerHtml) html += config.infoBannerHtml;

    html += `<div class="q-card" data-qid="${question.id}">
      <div class="q-meta">
        <div class="badge-row">
          ${examBadge(question.exam)}${difficultyBadge(question.difficulty)}${tagBadge(question.skill)}
        </div>
        <div class="q-toolrow">
          <button class="q-tool-btn ${p.bookmarked ? 'active' : ''}" data-action="bookmark" ${config.allowBookmark ? '' : 'disabled style="visibility:hidden"'}>
            <span class="bm-icon">${p.bookmarked ? '🔖' : '📑'}</span> Mark for Review
          </button>
          ${isSpr ? '' : `<button class="abc-btn ${state.crossOutEnabled ? 'active' : ''}" data-action="abc-toggle">ABC</button>`}
        </div>
        <div class="q-domain">${escapeHtml(question.domain)}</div>
      </div>
      <hr class="divider">
      ${bodyHtml()}
      ${state.submitted ? resultPanelHtml(question) : ''}
    </div>`;

    if (state.extraBanner) html += state.extraBanner;

    html += `<div class="answer-bar">
      <button class="answer-bar-btn ${state.submitted || hasSelection() ? 'enabled' : ''}" data-action="${state.submitted ? 'next' : 'submit'}">
        ${state.submitted ? config.nextLabel : config.submitLabel}
      </button>
    </div>`;

    mount.innerHTML = html;
    if (isSpr && !state.submitted) {
      const input = mount.querySelector('.spr-input');
      if (input) { input.focus(); input.setSelectionRange(input.value.length, input.value.length); }
    }
  }

  function resultPanelHtml(q) {
    const right = state.wasCorrect;
    const answerLabel = isMath
      ? (q.type === 'mc' ? letterOf(q.correct) : q.correctAnswers.join(' or '))
      : letterOf(q.correct);
    return `<div class="result-panel ${right ? 'right' : 'wrong'}">
      <div class="result-head">
        <span>${right ? '✅' : '❌'}</span>
        <span class="result-title">${right ? 'Correct' : 'Incorrect'}</span>
        <span class="result-correct-answer">Correct answer: ${answerLabel}</span>
      </div>
      <hr class="divider">
      <div class="rationale-label">RATIONALE</div>
      ${isMath ? `<div class="rationale-imgs">${mathImagesHtml(q.rationaleImages, 'rationale-img')}</div>`
               : `<div class="rationale-text">${escapeHtml(q.explanation)}</div>`}
    </div>`;
  }

  mount.addEventListener('click', (e) => {
    const btn = e.target.closest('[data-action]');
    if (!btn) return;
    const action = btn.dataset.action;
    if (action === 'zoom') { openZoom(btn.dataset.src); return; }
    if (action === 'bookmark') {
      if (!config.allowBookmark) return;
      Store.toggleBookmark(question.id);
      render();
      return;
    }
    if (action === 'abc-toggle') {
      state.crossOutEnabled = !state.crossOutEnabled;
      render();
      return;
    }
    if (action === 'crossout') {
      const i = Number(btn.dataset.index);
      if (state.crossedOut.has(i)) state.crossedOut.delete(i); else state.crossedOut.add(i);
      render();
      return;
    }
    if (action === 'select') {
      if (state.submitted) return;
      const i = Number(btn.dataset.index);
      state.selection = state.selection === i ? null : i;
      render();
      return;
    }
    if (action === 'submit') {
      if (!hasSelection() || state.submitted) return;
      state.submitted = true;
      const before = config.captureBefore ? config.captureBefore() : null;
      const wasCorrect = isSpr
        ? sprAnswerMatches(state.selection, question.correctAnswers)
        : state.selection === question.correct;
      state.wasCorrect = wasCorrect;
      if (config.recordAnswer) {
        if (isSpr) Store.recordResult(question, wasCorrect);
        else Store.record(question, state.selection);
      }
      if (config.afterSubmit) state.extraBanner = config.afterSubmit(before, question, wasCorrect);
      render();
      return;
    }
    if (action === 'next') {
      config.onNext();
      return;
    }
  });

  mount.addEventListener('input', (e) => {
    if (e.target.dataset.action === 'spr-input') {
      state.selection = e.target.value;
      const btn = mount.querySelector('.answer-bar-btn');
      if (btn) btn.classList.toggle('enabled', hasSelection());
    }
  });

  mount.addEventListener('keydown', (e) => {
    if (e.target.dataset && e.target.dataset.action === 'spr-input' && e.key === 'Enter' && hasSelection()) {
      mount.querySelector('.answer-bar-btn')?.click();
    }
  });

  render();
}

/* ============================== App shell / tabs ============================== */

const App = {
  tab: 'practice',
  filters: { exam: '', section: '', difficulties: [], domains: [] },
  examMenuOpen: false,
  sectionMenuOpen: false,
  filterSheetOpen: false,
  practiceCurrentId: null,
  reviewSection: 'needsWork',
  statsScope: null,          // null | 'SAT' | 'PSAT'
  statsSubview: null,        // null | { title, questions }
  searchQuery: ''
};

function loadFilters() {
  try {
    const raw = localStorage.getItem(FILTERS_KEY);
    if (raw) App.filters = Object.assign(App.filters, JSON.parse(raw));
  } catch (e) { /* ignore */ }
}
function saveFilters() {
  try { localStorage.setItem(FILTERS_KEY, JSON.stringify(App.filters)); } catch (e) { /* ignore */ }
}

function activeExamsSet() {
  return App.filters.exam ? new Set([App.filters.exam]) : new Set();
}
function activeSectionsSet() {
  return App.filters.section ? new Set([App.filters.section]) : new Set();
}
function activeDifficultiesSet() { return new Set(App.filters.difficulties); }
function activeDomainsSet() { return new Set(App.filters.domains); }

function renderApp() {
  const titleEl = document.getElementById('tab-title');
  const actionsEl = document.getElementById('topbar-actions');
  const root = document.getElementById('view-root');
  actionsEl.innerHTML = '';

  document.querySelectorAll('.tab-btn').forEach(b => b.classList.toggle('active', b.dataset.tab === App.tab));

  if (App.tab === 'practice') {
    titleEl.textContent = 'Practice';
    renderPracticeTopbar(actionsEl);
    renderPractice(root);
  } else if (App.tab === 'review') {
    titleEl.textContent = 'Review';
    renderReview(root);
  } else if (App.tab === 'stats') {
    if (App.statsSubview) {
      titleEl.innerHTML = `<button class="icon-btn" data-action="stats-back" style="font-weight:700;font-size:15px;">‹ ${escapeHtml(App.statsSubview.title)}</button>`;
      titleEl.querySelector('[data-action="stats-back"]').addEventListener('click', () => {
        App.statsSubview = null; renderApp();
      });
    } else {
      titleEl.textContent = 'Stats';
    }
    renderStats(root);
  } else if (App.tab === 'search') {
    titleEl.textContent = 'Search';
    renderSearch(root);
  }

  root.insertAdjacentHTML('beforeend', creditHtml());
}

function creditHtml() {
  return `<div class="credit-footer">Made by <strong>Parv Surjan</strong></div>`;
}

/* ---------------- Practice tab ---------------- */

function renderPracticeTopbar(actionsEl) {
  const examLabel = App.filters.exam || 'SAT + PSAT';
  const sectionLabel = App.filters.section === 'math' ? 'Math'
    : App.filters.section === 'rw' ? 'R&W' : 'R&W + Math';
  const hasFilters = App.filters.difficulties.length || App.filters.domains.length;

  const wrap = document.createElement('div');
  wrap.style.position = 'relative';
  wrap.style.display = 'flex';
  wrap.style.alignItems = 'center';
  wrap.style.gap = '8px';
  wrap.innerHTML = `
    <button class="menu-btn" data-action="exam-menu">${examLabel} <span class="chev">▾</span></button>
    <button class="menu-btn" data-action="section-menu">${sectionLabel} <span class="chev">▾</span></button>
    <button class="icon-btn ${hasFilters ? 'active' : ''}" data-action="open-filters">☰</button>
  `;
  actionsEl.appendChild(wrap);

  wrap.querySelector('[data-action="exam-menu"]').addEventListener('click', (e) => {
    e.stopPropagation();
    App.sectionMenuOpen = false;
    App.examMenuOpen = !App.examMenuOpen;
    renderExamMenu(wrap);
    renderSectionMenu(wrap);
  });
  wrap.querySelector('[data-action="section-menu"]').addEventListener('click', (e) => {
    e.stopPropagation();
    App.examMenuOpen = false;
    App.sectionMenuOpen = !App.sectionMenuOpen;
    renderExamMenu(wrap);
    renderSectionMenu(wrap);
  });
  wrap.querySelector('[data-action="open-filters"]').addEventListener('click', () => {
    openFilterSheet();
  });

  if (App.examMenuOpen) renderExamMenu(wrap);
  if (App.sectionMenuOpen) renderSectionMenu(wrap);
}

function popoverMenu(wrap, cls, options, current, onPick) {
  let existing = wrap.querySelector('.' + cls);
  if (existing) existing.remove();
  const pop = document.createElement('div');
  pop.className = 'popover ' + cls;
  pop.innerHTML = options.map(([val, label]) =>
    `<button class="popover-item ${current === val ? 'on' : ''}" data-val="${val}">${label}</button>`
  ).join('');
  wrap.appendChild(pop);
  pop.querySelectorAll('.popover-item').forEach(btn => {
    btn.addEventListener('click', (e) => {
      e.stopPropagation();
      onPick(btn.dataset.val);
    });
  });
  const closer = () => {
    App.examMenuOpen = false;
    App.sectionMenuOpen = false;
    const p = wrap.querySelector('.' + cls);
    if (p) p.remove();
    document.removeEventListener('click', closer);
  };
  setTimeout(() => document.addEventListener('click', closer), 0);
}

function renderExamMenu(wrap) {
  wrap.querySelector('.exam-pop')?.remove();
  if (!App.examMenuOpen) return;
  popoverMenu(wrap, 'exam-pop', [['', 'SAT and PSAT'], ['SAT', 'SAT'], ['PSAT', 'PSAT']],
    App.filters.exam, (val) => {
      App.filters.exam = val;
      App.examMenuOpen = false;
      saveFilters();
      App.practiceCurrentId = null;
      renderApp();
    });
}

function renderSectionMenu(wrap) {
  wrap.querySelector('.section-pop')?.remove();
  if (!App.sectionMenuOpen) return;
  popoverMenu(wrap, 'section-pop',
    [['', 'Reading & Writing + Math'], ['rw', 'Reading & Writing'], ['math', 'Math']],
    App.filters.section, (val) => {
      App.filters.section = val;
      App.sectionMenuOpen = false;
      saveFilters();
      App.practiceCurrentId = null;
      renderApp();
    });
}

function openFilterSheet() {
  const modalRoot = document.getElementById('modal-root');
  const backdrop = document.createElement('div');
  backdrop.className = 'sheet-backdrop';

  function draw() {
    backdrop.innerHTML = `
      <div class="sheet">
        <div class="sheet-header">
          <span class="sheet-title">Filters</span>
          <button class="sheet-done" data-action="done">Done</button>
        </div>
        <div class="sheet-section">
          <div class="sheet-section-label">Difficulty</div>
          ${['Easy', 'Medium', 'Hard'].map(d => `
            <div class="sheet-row ${App.filters.difficulties.includes(d) ? 'on' : ''}" data-kind="diff" data-val="${d}">
              <span>${d}</span><span class="check">✓</span>
            </div>`).join('')}
          <div class="sheet-section-footer">Nothing selected means every difficulty.</div>
        </div>
        <div class="sheet-section">
          <div class="sheet-section-label">Category</div>
          ${Store.domains().map(d => `
            <div class="sheet-row ${App.filters.domains.includes(d) ? 'on' : ''}" data-kind="domain" data-val="${escapeHtml(d)}">
              <span>${escapeHtml(d)}</span><span class="check">✓</span>
            </div>`).join('')}
          <div class="sheet-section-footer">Nothing selected means every category.</div>
        </div>
        <div class="sheet-section">
          <button class="sheet-danger" data-action="clear">Clear all filters</button>
        </div>
      </div>
    `;
    backdrop.querySelectorAll('[data-kind]').forEach(row => {
      row.addEventListener('click', () => {
        const kind = row.dataset.kind, val = row.dataset.val;
        const list = kind === 'diff' ? App.filters.difficulties : App.filters.domains;
        const idx = list.indexOf(val);
        if (idx >= 0) list.splice(idx, 1); else list.push(val);
        saveFilters();
        App.practiceCurrentId = null;
        draw();
      });
    });
    backdrop.querySelector('[data-action="clear"]').addEventListener('click', () => {
      App.filters.difficulties = []; App.filters.domains = [];
      saveFilters();
      App.practiceCurrentId = null;
      draw();
    });
    backdrop.querySelector('[data-action="done"]').addEventListener('click', close);
  }

  function close() {
    backdrop.remove();
    renderApp();
  }
  backdrop.addEventListener('click', (e) => { if (e.target === backdrop) close(); });

  draw();
  modalRoot.appendChild(backdrop);
}

function renderPractice(root) {
  const exams = activeExamsSet(), sections = activeSectionsSet(),
    difficulties = activeDifficultiesSet(), domains = activeDomainsSet();
  let current = App.practiceCurrentId ? Store.question(App.practiceCurrentId) : null;
  if (!current) {
    current = Store.nextQuestion({ exams, sections, difficulties, domains, excluding: null });
    App.practiceCurrentId = current ? current.id : null;
  }

  if (!current) {
    root.innerHTML = `<div class="empty-state">
      <div class="es-icon">☰</div>
      <div class="es-title">No questions match</div>
      <div class="es-desc">Loosen the filters to keep practising.</div>
    </div>`;
    return;
  }

  root.innerHTML = '';
  const mount = document.createElement('div');
  root.appendChild(mount);

  mountQuestionScreen(mount, current, {
    recordAnswer: true,
    allowBookmark: true,
    submitLabel: 'Submit answer',
    nextLabel: 'Next question',
    onNext: () => {
      const exams = activeExamsSet(), sections = activeSectionsSet(),
        difficulties = activeDifficultiesSet(), domains = activeDomainsSet();
      const next = Store.nextQuestion({ exams, sections, difficulties, domains, excluding: current.id });
      App.practiceCurrentId = next ? next.id : null;
      renderApp();
      window.scrollTo({ top: 0 });
    }
  });
}

/* ---------------- Review tab ---------------- */

function renderReview(root) {
  const needsWorkCount = Store.needsWork().length;
  const bookmarkedCount = Store.bookmarkedQuestions().length;

  root.innerHTML = `
    <div class="segmented">
      <button data-sec="needsWork" class="${App.reviewSection === 'needsWork' ? 'active' : ''}">Needs work (${needsWorkCount})</button>
      <button data-sec="bookmarked" class="${App.reviewSection === 'bookmarked' ? 'active' : ''}">Bookmarked (${bookmarkedCount})</button>
    </div>
    <div id="review-list"></div>
  `;
  root.querySelectorAll('.segmented button').forEach(b => {
    b.addEventListener('click', () => { App.reviewSection = b.dataset.sec; renderApp(); });
  });

  const listEl = root.querySelector('#review-list');
  const items = App.reviewSection === 'needsWork' ? Store.needsWorkByUnlock() : Store.bookmarkedQuestions();

  if (items.length === 0) {
    listEl.innerHTML = App.reviewSection === 'needsWork'
      ? `<div class="empty-state">
          <div class="es-icon">✅</div>
          <div class="es-title">Nothing to review</div>
          <div class="es-desc">Questions you miss land here. Each one unlocks two weeks after you last answered it; get it right twice in a row and it graduates out.</div>
        </div>`
      : `<div class="empty-state">
          <div class="es-icon">🔖</div>
          <div class="es-title">No bookmarks</div>
          <div class="es-desc">Tap the bookmark icon on any question to save it here.</div>
        </div>`;
    return;
  }

  const now = new Date();
  listEl.innerHTML = items.map(q => {
    const p = Store.progress(q.id);
    const locked = App.reviewSection === 'needsWork' && Store.isReviewLocked(p, now);
    const unlocks = Store.reviewUnlocksAt(p);
    const showStreak = App.reviewSection === 'needsWork';
    let dots = '';
    if (showStreak) {
      for (let i = 0; i < MASTERY_STREAK; i++) {
        dots += `<span class="streak-dot ${i < p.streak ? 'filled' : ''}"></span>`;
      }
      dots = `<span class="streak-dots">${dots}</span>`;
    }
    return `<div class="list-row ${locked ? 'locked' : ''}" data-qid="${q.id}">
      <div class="badge-row">${examBadge(q.exam)}${difficultyBadge(q.difficulty)}${tagBadge(q.skill)}${dots}</div>
      ${questionPreviewHtml(q)}
      <div class="list-row-foot">
        <span>${p.correct} right · ${p.wrong} wrong</span>
        ${locked && unlocks ? `<span style="margin-left:auto">🔒 Unlocks ${fmtShortDate(unlocks)}</span>` : ''}
      </div>
    </div>`;
  }).join('');

  listEl.querySelectorAll('.list-row:not(.locked)').forEach(row => {
    row.addEventListener('click', () => {
      const q = Store.question(row.dataset.qid);
      openReviewModal(q);
    });
  });
}

function openReviewModal(question) {
  const modalRoot = document.getElementById('modal-root');
  const wrap = document.createElement('div');
  wrap.className = 'qmodal-backdrop';
  wrap.innerHTML = `
    <div class="qmodal-header">
      <span class="qmodal-title">Review</span>
      <button class="qmodal-close" data-action="close">Close</button>
    </div>
    <div class="qmodal-body"></div>
  `;
  wrap.querySelector('[data-action="close"]').addEventListener('click', () => {
    wrap.remove();
    renderApp();
  });
  modalRoot.appendChild(wrap);

  const body = wrap.querySelector('.qmodal-body');
  let wasInQueue = Store.isInWrongQueue(Store.progress(question.id));

  mountQuestionScreen(body, question, {
    recordAnswer: true,
    allowBookmark: true,
    submitLabel: 'Submit answer',
    nextLabel: 'Done',
    captureBefore: () => wasInQueue,
    afterSubmit: (before, q) => {
      const p = Store.progress(q.id);
      if (before && p.retired) {
        return `<div class="info-banner good">🎓 Two in a row — removed from Needs work.</div>`;
      }
      const unlocks = Store.reviewUnlocksAt(p);
      if (unlocks) {
        return `<div class="info-banner">🔒 Locked until ${fmtLongDate(unlocks)} — try it again then.</div>`;
      }
      return null;
    },
    onNext: () => { wrap.remove(); renderApp(); }
  });
}

/* ---------------- Stats tab ---------------- */

function inScope(q) { return App.statsScope === null || q.exam === App.statsScope; }

function historyInScope() {
  return App.statsScope === null ? Store.save.history : Store.save.history.filter(e => e.exam === App.statsScope);
}

function bucketBy(history, keyFn) {
  const map = new Map();
  for (const e of history) {
    const k = keyFn(e);
    if (!map.has(k)) map.set(k, { name: k, correct: 0, total: 0 });
    const b = map.get(k);
    b.total += 1;
    if (e.wasCorrect) b.correct += 1;
  }
  return Array.from(map.values()).map(b => ({ ...b, accuracy: b.total ? b.correct / b.total : 0 }));
}

function renderStats(root) {
  if (App.statsSubview) {
    renderStatsSubview(root);
    return;
  }

  const history = historyInScope();
  const answered = history.length;
  const correct = history.filter(e => e.wasCorrect).length;
  const overall = answered ? correct / answered : 0;
  const bank = Store.questions.filter(inScope);
  const uniqueSeen = bank.filter(q => Store.progress(q.id).seen > 0).length;
  const needsWorkScoped = Store.needsWork().filter(inScope).length;

  let html = '';
  if (!Store.save.history.length) {
    root.innerHTML = `<div class="empty-state">
      <div class="es-icon">📊</div>
      <div class="es-title">No stats yet</div>
      <div class="es-desc">Answer a few questions and your strengths and weak spots show up here.</div>
    </div>`;
    return;
  }

  html += `<div class="segmented" id="scope-seg">
    <button data-scope="" class="${App.statsScope === null ? 'active' : ''}">All</button>
    <button data-scope="SAT" class="${App.statsScope === 'SAT' ? 'active' : ''}">SAT</button>
    <button data-scope="PSAT" class="${App.statsScope === 'PSAT' ? 'active' : ''}">PSAT</button>
  </div>`;

  if (answered === 0) {
    html += `<div class="empty-state">
      <div class="es-icon">📊</div>
      <div class="es-title">No ${App.statsScope || ''} stats yet</div>
      <div class="es-desc">Answer a few questions and your strengths and weak spots show up here.</div>
    </div>`;
    root.innerHTML = html;
    wireStatsHeader(root);
    return;
  }

  html += `<div class="stat-tiles">
    <div class="stat-tile"><div class="value">${Math.round(overall * 100)}%</div><div class="label">Accuracy</div></div>
    <div class="stat-tile"><div class="value">${answered}</div><div class="label">Answered</div></div>
    <div class="stat-tile"><div class="value">${needsWorkScoped}</div><div class="label">Needs work</div></div>
  </div>`;

  html += `<div class="plain-row" data-action="all-missed"><span>All missed questions</span><span class="val" id="all-missed-count"></span></div>`;
  html += `<div class="plain-row" style="cursor:default"><span>Question bank covered</span><span class="val">${uniqueSeen} of ${bank.length}</span></div>`;

  if (App.statsScope === null) {
    html += bucketSectionHtml('By test', bucketBy(history, e => e.exam).sort((a, b) => b.name.localeCompare(a.name)));
  }
  html += bucketSectionHtml('By difficulty', bucketBy(history, e => e.difficulty).sort((a, b) => {
    const order = { Easy: 0, Medium: 1, Hard: 2 };
    return order[a.name] - order[b.name];
  }));
  html += bucketSectionHtml('By category', bucketBy(history, e => e.domain).sort((a, b) => a.accuracy - b.accuracy));
  html += bucketSectionHtml('By skill — weakest first', bucketBy(history, e => e.skill).sort((a, b) => a.accuracy - b.accuracy));

  html += `<button class="danger-btn" data-action="reset">Reset all progress</button>
  <div class="danger-footnote">Clears answers, bookmarks and review queues. Questions stay.</div>`;

  root.innerHTML = html;
  root.querySelector('#all-missed-count').textContent = Store.everMissed(inScope).length;

  wireStatsHeader(root);

  root.querySelector('[data-action="all-missed"]').addEventListener('click', () => {
    App.statsSubview = { title: 'All missed', questions: Store.everMissed(inScope), reattempt: true };
    renderApp();
  });

  root.querySelectorAll('.bucket-row').forEach(rowEl => {
    rowEl.addEventListener('click', () => {
      const title = rowEl.dataset.name;
      const kind = rowEl.dataset.kind;
      const questions = Store.everMissed(q => {
        if (!inScope(q)) return false;
        if (kind === 'test') return q.exam === title;
        if (kind === 'difficulty') return q.difficulty === title;
        if (kind === 'domain') return q.domain === title;
        if (kind === 'skill') return q.skill === title;
        return false;
      });
      App.statsSubview = { title, questions, reattempt: true };
      renderApp();
    });
  });

  root.querySelector('[data-action="reset"]').addEventListener('click', () => {
    if (confirm("Reset all progress? This can't be undone.")) {
      Store.resetAll();
      App.statsScope = null;
      renderApp();
    }
  });
}

function wireStatsHeader(root) {
  const seg = root.querySelector('#scope-seg');
  if (!seg) return;
  seg.querySelectorAll('button').forEach(b => {
    b.addEventListener('click', () => {
      App.statsScope = b.dataset.scope || null;
      renderApp();
    });
  });
}

function bucketSectionHtml(title, buckets) {
  const kind = title === 'By test' ? 'test' : title === 'By difficulty' ? 'difficulty'
    : title === 'By category' ? 'domain' : 'skill';
  let html = `<div class="section-title">${title}</div>`;
  html += buckets.map(b => `
    <div class="bucket-row" data-kind="${kind}" data-name="${escapeHtml(b.name)}">
      <div class="bucket-head">
        <span class="bucket-name">${escapeHtml(b.name)}</span>
        <span class="bucket-pct">${Math.round(b.accuracy * 100)}%</span>
        <span class="bucket-frac">(${b.correct}/${b.total})</span>
      </div>
      <div class="bucket-bar-bg"><div class="bucket-bar-fg" style="width:${Math.max(2, b.accuracy * 100)}%"></div></div>
    </div>
  `).join('');
  return html;
}

function renderStatsSubview(root) {
  const { questions } = App.statsSubview;
  if (questions.length === 0) {
    root.innerHTML = `<div class="empty-state">
      <div class="es-icon">✅</div>
      <div class="es-title">Nothing missed</div>
      <div class="es-desc">Questions you get wrong in this group will be listed here.</div>
    </div>`;
    return;
  }
  root.innerHTML = questions.map(q => {
    const p = Store.progress(q.id);
    return `<div class="list-row" data-qid="${q.id}">
      <div class="badge-row">${examBadge(q.exam)}${difficultyBadge(q.difficulty)}${tagBadge(q.skill)}</div>
      ${questionPreviewHtml(q)}
      <div class="list-row-foot"><span>${p.correct} right · ${p.wrong} wrong</span></div>
    </div>`;
  }).join('');
  root.querySelectorAll('.list-row').forEach(row => {
    row.addEventListener('click', () => {
      openReattemptModal(Store.question(row.dataset.qid));
    });
  });
}

function openReattemptModal(question) {
  const modalRoot = document.getElementById('modal-root');
  const wrap = document.createElement('div');
  wrap.className = 'qmodal-backdrop';
  wrap.innerHTML = `
    <div class="qmodal-header">
      <span class="qmodal-title">Reattempt</span>
      <button class="qmodal-close" data-action="close">Close</button>
    </div>
    <div class="qmodal-body"></div>
  `;
  wrap.querySelector('[data-action="close"]').addEventListener('click', () => wrap.remove());
  modalRoot.appendChild(wrap);

  const body = wrap.querySelector('.qmodal-body');
  mountQuestionScreen(body, question, {
    recordAnswer: false,
    allowBookmark: false,
    submitLabel: 'Submit answer',
    nextLabel: 'Done',
    infoBannerHtml: `<div class="info-banner">ℹ️ Practice only — this won't affect your stats.</div>`,
    onNext: () => wrap.remove()
  });
}

/* ---------------- Search tab ---------------- */

const SEARCH_LIMIT = 150;

function searchQuestions(query) {
  const q = query.trim().toLowerCase();
  if (!q) return [];
  return Store.questions.filter(item => {
    if (item.id.toLowerCase() === q) return true;
    if (item.skill.toLowerCase().includes(q)) return true;
    if (item.domain.toLowerCase().includes(q)) return true;
    if (item.section === 'rw' && stripUnderlineMarkers(item.stem).toLowerCase().includes(q)) return true;
    return false;
  });
}

function renderSearch(root) {
  root.innerHTML = `
    <div class="search-row">
      <input type="text" class="search-input" id="search-input" placeholder="Search by keyword, skill, category, or question ID…" value="${escapeHtml(App.searchQuery)}">
    </div>
    <div id="search-results"></div>
  `;
  const input = root.querySelector('#search-input');
  const resultsEl = root.querySelector('#search-results');

  function draw() {
    const query = App.searchQuery;
    if (!query.trim()) {
      resultsEl.innerHTML = `<div class="empty-state">
        <div class="es-icon">🔎</div>
        <div class="es-title">Find any question</div>
        <div class="es-desc">Search the whole bank (Reading &amp; Writing and Math) by keyword, skill, category, or exact question ID. Nothing here affects your stats — this is just for looking things up.</div>
      </div>`;
      return;
    }
    const matches = searchQuestions(query);
    if (matches.length === 0) {
      resultsEl.innerHTML = `<div class="empty-state">
        <div class="es-icon">🔎</div>
        <div class="es-title">No matches</div>
        <div class="es-desc">Try a different keyword, skill name, or question ID.</div>
      </div>`;
      return;
    }
    const shown = matches.slice(0, SEARCH_LIMIT);
    resultsEl.innerHTML =
      `<div class="search-count">${matches.length} match${matches.length === 1 ? '' : 'es'}${matches.length > SEARCH_LIMIT ? ` — showing first ${SEARCH_LIMIT}` : ''}</div>` +
      shown.map(qq => `<div class="list-row" data-qid="${qq.id}">
        <div class="badge-row">${examBadge(qq.exam)}${difficultyBadge(qq.difficulty)}${tagBadge(qq.skill)}</div>
        ${questionPreviewHtml(qq)}
        <div class="list-row-foot"><span>${qq.id}</span></div>
      </div>`).join('');
    resultsEl.querySelectorAll('.list-row').forEach(row => {
      row.addEventListener('click', () => openReattemptModal(Store.question(row.dataset.qid)));
    });
  }

  input.addEventListener('input', () => {
    App.searchQuery = input.value;
    draw();
  });
  draw();
}

/* ============================== Boot ============================== */

async function boot() {
  document.getElementById('view-root').innerHTML = `<div class="empty-state"><div class="es-title">Loading questions…</div></div>`;
  loadFilters();
  Store.loadSave();
  await Store.loadQuestions();

  document.querySelectorAll('.tab-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      App.tab = btn.dataset.tab;
      App.statsSubview = null;
      window.scrollTo({ top: 0 });
      renderApp();
    });
  });

  renderApp();
}

boot();
