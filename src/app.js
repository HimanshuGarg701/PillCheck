import "./style.css";
import {
  DISCLAIMER,
  PHARMACIST,
  samples,
  localDay,
  atTime,
  uid,
  canonical,
  isHighRisk,
  validateMedication,
  dailyMg,
  checkRisks,
  scheduleFor,
  recordDose,
  applyReplan,
  ensureToday,
} from "./domain.js";
import { loadState, saveState, storedData } from "./storage.js";
import { makeHistoryPdf, downloadFile } from "./pdf.js";
import { icon } from "./icons.js";
import {
  enablePush,
  syncPush,
  disablePush,
  testPush,
  pushSupported,
} from "./push.js";
const app = document.querySelector("#app");
const esc = (v) =>
  String(v ?? "").replace(
    /[&<>"']/g,
    (c) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[
        c
      ],
  );
const time = (v) =>
  new Date(v).toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
const date = (v) =>
  new Date(`${v}T12:00:00`).toLocaleDateString([], {
    month: "short",
    day: "numeric",
    year: "numeric",
  });
const statuses = {
  pending: "Upcoming",
  taken_on_time: "Taken on time",
  taken_late: "Taken late",
  missed: "Missed",
  skipped: "Skipped",
  cancelled: "Regimen updated",
};
let state;
try {
  state = loadState();
} catch (e) {
  app.innerHTML = `<main><h1>Saved records need attention</h1><p>${esc(e.message)}</p><button id="recover">Download saved records</button></main>`;
  document.querySelector("#recover").onclick = () =>
    downloadFile(storedData(), "pillcheck-recovery.json", "application/json");
  throw e;
}
let page = "today",
  verified = false,
  reminder = null,
  recognition = null,
  pendingCandidate = null,
  scanInfo = null;
const monthAgo = new Date();
monthAgo.setDate(monthAgo.getDate() - 29);
let filter = { from: localDay(monthAgo), to: state.day, medication: "" };
const medFor = (d) => state.medications.find((m) => m.id === d.medicationId);
const today = () =>
  state.doses
    .filter(
      (d) => localDay(d.scheduledAt) === state.day && d.status !== "cancelled",
    )
    .sort((a, b) => a.scheduledAt.localeCompare(b.scheduledAt));
const now = () => new Date(state.demoTime);
const disclaimer = () =>
  `<p class="disclaimer">${icon("shield", 16)}<span>${DISCLAIMER}</span></p>`;
function persist() {
  saveState(state);
  navigator.serviceWorker?.controller?.postMessage({
    type: "BLOCK_DOSES",
    ids: state.doses.filter((d) => d.status !== "pending").map((d) => d.id),
  });
}
function toast(message) {
  const el = document.querySelector("#toast");
  el.textContent = message;
  el.className = "toast visible";
  clearTimeout(toast.timer);
  toast.timer = setTimeout(() => (el.className = "toast"), 6500);
}
function closeDialog() {
  recognition?.abort();
  recognition = null;
  window.speechSynthesis?.cancel();
  document.querySelector("dialog")?.close();
  document.querySelector("#modal-root").innerHTML = "";
  reminder = null;
}
function modal(title, body, wide = false) {
  closeDialog();
  document.querySelector("#modal-root").innerHTML =
    `<dialog class="${wide ? "wide" : ""}" aria-labelledby="dialog-title"><div class="dialog-head"><h2 id="dialog-title">${title}</h2><button class="icon-button" data-action="close" aria-label="Close dialog">${icon("close")}</button></div>${body}</dialog>`;
  const d = document.querySelector("dialog");
  d.showModal();
  d.addEventListener("cancel", () => {
    recognition?.abort();
    reminder = null;
  });
}
function commit(message) {
  persist();
  render();
  if (message) toast(message);
  if (state.pushEnabled) syncPush(state).catch((e) => toast(e.message));
}
async function ai(body) {
  if (!navigator.onLine)
    throw new Error(
      "You are offline. Saved schedules and dose tracking still work; Meta needs a connection.",
    );
  const r = await fetch("/api/ai", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  const data = await r.json();
  if (!r.ok)
    throw new Error(data.error || "Meta could not complete this request.");
  verified = true;
  document.querySelector("#meta-status")?.classList.add("verified");
  if (document.querySelector("#meta-status"))
    document.querySelector("#meta-status").textContent =
      "Muse Spark 1.3 · live";
  return data;
}
function flagHtml(f) {
  return `<article class="flag"><div class="flag-title">${icon("alert", 20)}<strong>${esc(f.title)}</strong></div><p>${esc(f.explanation)}</p>${f.combinedMg ? `<p class="total">Combined daily ${esc(pendingCandidate?.ingredient || "ingredient")}: <strong>${f.combinedMg.toLocaleString()} mg</strong></p>` : ""}${f.url ? `<a href="${esc(f.url)}" target="_blank" rel="noreferrer">${esc(f.source)} ↗</a>` : ""}</article>`;
}
function activeFlags() {
  const all = state.medications
    .filter((m) => m.status === "active")
    .flatMap((m) => checkRisks(m, state.medications, state.problems));
  const seen = new Set();
  return all.filter((f) => {
    const k = f.kind + [...(f.medications || []), f.title].sort().join();
    if (seen.has(k)) return false;
    seen.add(k);
    return true;
  });
}
function render() {
  const titles = {
    today: "Today",
    medicines: "My medicines",
    history: "History",
    settings: "Preferences",
  };
  app.innerHTML = `<div class="layout"><aside class="sidebar"><a href="#today" class="brand" aria-label="PillCheck home"><span class="brand-mark">${icon("check", 24)}</span>PillCheck<span class="brand-dot">.</span></a><span class="nav-label">YOUR DAILY COMPANION</span><nav aria-label="Main navigation">${Object.entries(
    titles,
  )
    .map(
      ([id, label]) =>
        `<button class="nav-item ${page === id ? "selected" : ""}" data-action="nav" data-page="${id}" ${page === id ? 'aria-current="page"' : ""}>${icon(id === "medicines" ? "pill" : id === "settings" ? "settings" : id)}<span>${label}</span>${id === "today" ? `<span class="nav-count">${today().filter((d) => d.status === "pending").length}</span>` : ""}</button>`,
    )
    .join(
      "",
    )}</nav><div class="sidebar-note">${icon("leaf", 28)}<h3>A little clarity.<br>Every day.</h3><p>Your schedule, your records,<br>all in one place.</p></div><div class="profile"><span class="avatar">AM</span><div><strong>Alex Morgan</strong><small>Fictional demo profile</small></div></div></aside><div class="workspace"><header class="topbar"><span>PillCheck <span class="slash">/</span> ${titles[page]}</span><div class="header-right"><span class="demo-tag">SYNTHETIC DEMO</span><span class="avatar small">AM</span></div></header><main id="main"><div class="connection ${navigator.onLine ? "" : "offline"}" ${navigator.onLine ? "hidden" : ""}>You’re offline. Saved records and in-app reminders are available. AI and background push need internet.</div>${page === "today" ? todayView() : page === "medicines" ? medicinesView() : page === "history" ? historyView() : settingsView()}<footer>${disclaimer()}<div class="footer-links"><span id="meta-status" class="${verified ? "verified" : ""}">${verified ? "Muse Spark 1.3 · live" : "Powered by Meta · Muse Spark 1.3"}</span><a href="https://github.com/HimanshuGarg701/PillCheck" target="_blank" rel="noreferrer">View source ↗</a></div></footer></main></div></div>`;
}
function heading(kicker, title, copy, button = "") {
  return `<div class="page-heading"><div><p class="eyebrow">${kicker}</p><h1>${title}</h1><p class="subtitle">${copy}</p></div>${button}</div>`;
}
function todayView() {
  const doses = today();
  const pending = doses.filter((d) => d.status === "pending");
  const first = pending[0];
  const group = first
    ? pending.filter((d) => d.scheduledAt === first.scheduledAt)
    : [];
  const taken = doses.filter((d) => d.status.startsWith("taken")).length;
  const percent = Math.round((taken / Math.max(doses.length, 1)) * 100);
  const flags = activeFlags();
  return `${heading(new Date(`${state.day}T12:00:00`).toLocaleDateString([], { weekday: "long", month: "long", day: "numeric" }), "One day at a time.", "A clear plan for your medicines. A little more peace of mind.", `<button class="button secondary" data-action="add">${icon("plus")} Add medicine</button>`)}<div class="dashboard-grid"><div><section class="hero"><div class="hero-top"><span class="pill-label">${icon(first && new Date(first.scheduledAt).getHours() >= 17 ? "moon" : "sun", 17)} ${first ? "UP NEXT" : "ALL CHECKED IN"}</span><span class="hero-time">${first ? time(first.scheduledAt) : "For today"}</span></div><h2>${first ? (new Date(first.scheduledAt).getHours() < 12 ? "Your morning, made simpler." : new Date(first.scheduledAt).getHours() < 17 ? "A moment for your afternoon." : "An easier evening.") : "You’ve recorded every dose."}</h2><p>${first ? `${group.length} ${group.length === 1 ? "medicine is" : "medicines are"} on this part of your recorded schedule.` : "Your day is saved in History, including any skipped or missed doses."}</p><div class="hero-meds">${group
    .map((d) => {
      const m = medFor(d);
      return `<span><span class="mini-pill ${m.color || "sage"}">${icon("pill", 15)}</span>${esc(m.name)} <b>${m.strengthMg} mg</b></span>`;
    })
    .join(
      "",
    )}</div>${first ? `<div class="hero-actions"><button class="button primary" data-action="reminder" data-id="${esc(first.id)}">Review ${group.length > 1 ? "medicines" : "medicine"} ${icon("arrow", 19)}</button><button class="button text-button" data-action="read" data-id="${esc(first.id)}">${icon("sound", 20)} Read aloud</button></div>` : `<button class="button primary" data-action="nav" data-page="history">See your history ${icon("arrow", 19)}</button>`}<div class="hero-decoration" aria-hidden="true">${icon("leaf", 115)}</div></section><section class="section schedule-section"><div class="section-heading"><h2>Today’s schedule <span class="count-badge">${doses.length}</span></h2><span class="muted">Local time</span></div><div class="timeline">${
    doses
      .map((d) => {
        const m = medFor(d);
        const done = d.status.startsWith("taken");
        return `<article class="dose-row"><div class="timeline-time"><strong>${time(d.scheduledAt)}</strong><span class="timeline-dot ${done ? "complete" : ""}">${done ? icon("check", 12) : ""}</span></div><div class="med-icon ${m.color || "sage"}">${icon("pill", 23)}</div><div class="dose-details"><h3>${esc(m.name)} <span>${m.strengthMg} mg</span></h3><p>${m.doseQuantity} ${esc(m.doseUnit)}${m.doseQuantity > 1 ? "s" : ""} · ${esc(m.instructions || "Recorded prescription")}</p>${d.replanReason ? `<small class="rescheduled">${icon("clock", 13)} Moved from ${time(d.originalScheduledAt)} · reason saved</small>` : ""}</div><div class="dose-action">${d.status === "pending" ? `<button class="button compact secondary" data-action="reminder" data-id="${esc(d.id)}">Review</button>` : `<span class="status ${d.status}">${done ? icon("check", 14) : ""}${statuses[d.status]}</span>`}</div></article>`;
      })
      .join("") || '<p class="empty">No medicines scheduled today.</p>'
  }</div></section>${flags.length ? `<section class="section"><h2>Things to check with your pharmacist</h2>${flags.map(flagHtml).join("")}</section>` : ""}</div><aside class="right-column"><section class="card progress-card"><div class="section-heading"><h2>Your daily check-in</h2>${icon("leaf", 20)}</div><div class="progress-ring" style="--progress:${percent}%"><div><strong>${taken}<span> / ${doses.length}</span></strong><small>doses recorded taken</small></div></div><p>${taken ? "Every check-in keeps your record clear." : "Small steps make a steady routine."}</p><div class="progress-legend"><span><i></i> Taken</span><span><i class="pale"></i> Still to record</span></div></section><section class="card demo-card"><span class="eyebrow">TAKE A LOOK AROUND</span><h2>Try the full story</h2><p>Explore with fictional labels and a practice clock.</p><button class="demo-action" data-action="add"><span class="action-icon">${icon("scan", 20)}</span><span><strong>Read a medicine label</strong><small>Try a photo, no camera needed</small></span>${icon("arrow", 17)}</button><button class="demo-action" data-action="demo-reminder"><span class="action-icon peach">${icon("bell", 20)}</span><span><strong>Try a spoken reminder</strong><small>Review, listen, and check in</small></span>${icon("arrow", 17)}</button><button class="demo-action" data-action="late"><span class="action-icon lavender">${icon("clock", 20)}</span><span><strong>Explore a late dose</strong><small>See a live AI timing proposal</small></span>${icon("arrow", 17)}</button><div class="demo-clock">${icon("clock", 16)} Practice clock <strong>${time(state.demoTime)}</strong><button data-action="clock" aria-label="Adjust practice clock">Adjust</button></div></section><section class="quiet-note">${icon("shield", 21)}<div><strong>A companion to your care</strong><p>Flags help you prepare questions for your pharmacist. This demo does not make treatment decisions.</p></div></section></aside></div>`;
}
function medicinesView() {
  const active = state.medications.filter((m) => m.status === "active");
  const stopped = state.medications.filter((m) => m.status !== "active");
  return `${heading("YOUR MEDICINE CABINET", "Everything in one place.", "Review a label before saving. Your earlier regimens stay in your history.", `<button class="button primary" data-action="add">${icon("plus")} Add medicine</button>`)}<div class="medicine-grid">${active.map((m) => `<article class="card medicine-card"><div class="medicine-card-top"><span class="med-icon ${m.color || "sage"}">${icon("pill", 26)}</span><span class="status taken_on_time">Active regimen</span></div><h2>${esc(m.name)} <span>${m.strengthMg} mg</span></h2><p class="ingredient">${esc(m.ingredient)}</p><div class="medicine-facts"><div><small>RECORDED DOSE</small><strong>${m.doseQuantity} ${esc(m.doseUnit)} · ${m.times.length}× daily</strong></div><div><small>SCHEDULE</small><strong>${m.times.join(" · ")}</strong></div><div><small>DAILY INGREDIENT</small><strong>${dailyMg(m).toLocaleString()} mg</strong></div><div><small>STARTED</small><strong>${date(m.startDate)}</strong></div></div>${isHighRisk(m) ? `<p class="inline-warning">${PHARMACIST}</p>` : ""}<p class="muted">${esc(m.instructions)}</p><div class="card-actions"><button class="button secondary" data-action="edit" data-id="${m.id}">Update record</button><button class="button text-button" data-action="archive" data-id="${m.id}">Archive</button></div></article>`).join("")}</div><section class="section"><div class="section-heading"><h2>Reference checks</h2><span class="muted">Active + recently stopped medicines</span></div>${activeFlags().length ? activeFlags().map(flagHtml).join("") : '<div class="card"><strong>No known interaction found in this demo’s reference set.</strong><p>This is a limited reference set, not a complete interaction check. It does not mean a combination is safe. Ask your pharmacist to check all medicines and supplements.</p></div>'}</section><section class="section"><h2>Earlier regimens & stopped medicines</h2>${stopped.length ? stopped.map((m) => `<div class="archive-row"><strong>${esc(m.name)} ${m.strengthMg} mg</strong><span>${date(m.startDate)} → ${date(m.endDate)}</span><span>${esc(m.archiveReason || "Archived")}</span></div>`).join("") : '<p class="empty">Earlier regimens appear here when you update or archive a record.</p>'}</section>`;
}
function filteredDoses() {
  return state.doses.filter(
    (d) =>
      localDay(d.scheduledAt) >= filter.from &&
      localDay(d.scheduledAt) <= filter.to &&
      (!filter.medication || d.medicationId === filter.medication),
  );
}
function historyView() {
  const list = filteredDoses().sort((a, b) =>
    b.scheduledAt.localeCompare(a.scheduledAt),
  );
  const eligible = list.filter(
    (d) => !["cancelled", "pending"].includes(d.status),
  );
  const taken = eligible.filter((d) => d.status.startsWith("taken")).length;
  return `${heading("YOUR RECORD, OVER TIME", "A clearer picture of your routine.", "Thirty days of fictional history are included. Every new check-in stays on this device.", `<button class="button primary" data-action="pdf">${icon("download")} Export PDF</button>`)}<div class="card filters"><label>From<input type="date" id="from" value="${filter.from}"></label><label>To<input type="date" id="to" value="${filter.to}"></label><label>Medicine<select id="medicine-filter"><option value="">All medicines & regimens</option>${state.medications.map((m) => `<option value="${m.id}" ${filter.medication === m.id ? "selected" : ""}>${esc(m.name)}${m.status === "active" ? "" : " (archived)"}</option>`).join("")}</select></label><button class="button secondary" data-action="filter">Apply filters</button></div><div class="stats-grid"><div class="card stat"><small>DOSES RECORDED TAKEN</small><strong>${eligible.length ? Math.round((taken / eligible.length) * 100) : 0}<span>%</span></strong><p>${taken} of ${eligible.length} completed dose records</p></div><div class="card stat"><small>ON TIME</small><strong>${eligible.filter((d) => d.status === "taken_on_time").length}</strong><p>Within 30 minutes of the recorded time</p></div><div class="card stat"><small>NEEDS A CONVERSATION</small><strong>${eligible.filter((d) => ["missed", "skipped"].includes(d.status)).length}</strong><p>Missed or skipped · share with your pharmacist</p></div></div><section class="section"><h2>Dose history</h2><div class="table-wrap"><table><thead><tr><th>Scheduled</th><th>Medicine</th><th>Status</th><th>Confirmed</th></tr></thead><tbody>${list
    .map((d) => {
      const m = medFor(d);
      return `<tr><td>${date(localDay(d.scheduledAt))}<small>${time(d.scheduledAt)}${d.replanReason ? " · adjusted" : ""}</small></td><td><strong>${esc(m?.name || "Archived")}</strong><small>${m?.strengthMg} mg · ${m?.doseQuantity} ${esc(m?.doseUnit)}</small></td><td><span class="status ${d.status}">${statuses[d.status]}</span>${d.reason ? `<small>${esc(d.reason)}</small>` : ""}</td><td>${d.confirmedAt ? `${time(d.confirmedAt)}<small>${esc(d.method)} confirmation</small>` : "—"}</td></tr>`;
    })
    .join(
      "",
    )}</tbody></table>${!list.length ? '<p class="empty">No records in this range.</p>' : ""}</div></section><details class="audit"><summary>Record changes & acknowledgments (${state.audit.length})</summary>${[
    ...state.audit,
  ]
    .reverse()
    .map(
      (a) =>
        `<div class="audit-row"><strong>${esc(a.type.replaceAll("_", " "))}</strong><time>${new Date(a.at).toLocaleString()}</time><p>${esc(a.reason)}</p></div>`,
    )
    .join("")}</details>`;
}
function settingsView() {
  return `${heading("MAKE IT YOURS", "A little help, your way.", "Choose how you hear reminders and keep a copy of your records.")}<div class="settings-grid"><section class="card"><h2>${icon("sound")} Voice & language</h2><p>Meta writes the reminder. Your device reads it aloud. Voice availability depends on your browser.</p><label>Spoken reminder language<select id="language"><option value="en-US" ${state.language === "en-US" ? "selected" : ""}>English</option><option value="es-ES" ${state.language === "es-ES" ? "selected" : ""}>Español</option><option value="hi-IN" ${state.language === "hi-IN" ? "selected" : ""}>हिन्दी</option></select></label><p class="muted">Microphone access is optional and requested only when you choose voice confirmation. Some browsers process speech online.</p></section><section class="card"><h2>${icon("bell")} Reminders</h2><label class="checkbox"><input id="reminders" type="checkbox" ${state.remindersEnabled ? "checked" : ""}> In-app reminders using the practice clock</label><p>Repeats at the scheduled time, 15 minutes later, then every 30 minutes until recorded or the reminder window ends. Works offline while this page is open.</p><label>Mark unconfirmed doses missed after<select id="window"><option value="60" ${state.reminderWindowMinutes === 60 ? "selected" : ""}>1 hour</option><option value="120" ${state.reminderWindowMinutes === 120 ? "selected" : ""}>2 hours</option><option value="240" ${state.reminderWindowMinutes === 240 ? "selected" : ""}>4 hours</option></select></label><hr><h3>Background Web Push</h3><p>Uses your device’s real clock and internet connection. Delivery depends on browser permission and OS settings. On iPhone, install this site on your Home Screen first. Opening the app refreshes the next 7 days.</p><button class="button secondary" data-action="push">${icon("bell")}${state.pushEnabled ? "Turn off background reminders" : "Enable background reminders"}</button>${state.pushEnabled ? '<button class="button text-button" data-action="test-push">Send a test notification</button>' : ""}<p class="muted">${pushSupported() ? "Notifications contain no medicine names." : "Web Push is unavailable in this browser. Use a supported browser for background reminders."}</p></section><section class="card"><h2>${icon("shield")} Recorded class concerns</h2><p>Store a fictional medication-class concern to include it in checks when adding medicines.</p><label>Concern classes, separated by commas<input id="problems" value="${esc(state.problems.join(", "))}" placeholder="e.g. statin"></label><button class="button secondary" data-action="save-problems">Save concerns</button></section><section class="card"><h2>${icon("download")} Your demo records</h2><p>Records stay in this browser. Label images go to Meta only when you choose to read them. Use synthetic labels; this public demonstration is not a clinical service.</p><button class="button secondary" data-action="json">Download all records</button><button class="button text-button" data-action="verify">Verify live Meta connection</button><p class="muted">No account needed. Clearing browser storage removes your local records.</p></section></div>`;
}
function addDialog() {
  modal(
    "Add a medicine",
    `<p class="dialog-intro">Start with a synthetic label. Review every field before it joins your schedule.</p><div class="sample-grid">${samples.map((s) => `<button class="sample-card" data-action="sample" data-id="${s.id}"><img src="/labels/${s.id}.png" alt="Synthetic ${s.name} prescription label"><strong>${s.name}</strong><small>${s.caption}</small></button>`).join("")}</div><label class="upload-box">${icon("upload", 26)}<strong>Upload a label photo</strong><span>PNG, JPG, or WebP · up to 2.5 MB · synthetic data only</span><input id="label-file" type="file" accept="image/png,image/jpeg,image/webp"></label><div class="split-actions"><button class="button secondary" data-action="text-entry">Paste label text</button><button class="button secondary" data-action="manual">Enter manually</button></div>${disclaimer()}`,
    true,
  );
}
async function scanImage(file) {
  if (file.size > 2500000)
    throw new Error("Choose an image smaller than 2.5 MB.");
  const data = await new Promise((resolve, reject) => {
    const r = new FileReader();
    r.onload = () => resolve(r.result);
    r.onerror = reject;
    r.readAsDataURL(file);
  });
  await extract({ image: data });
}
async function extract(payload) {
  modal(
    "Reading your label",
    `<div class="loading"><span class="spinner"></span><h3>Muse Spark 1.3 is reading the label…</h3><p>Missing details will stay blank for you to confirm.</p></div>${disclaimer()}`,
  );
  try {
    const data = await ai({ task: "scan", ...payload });
    scanInfo = data;
    entryDialog(data);
  } catch (e) {
    modal(
      "The label needs another look",
      `<p class="inline-warning">${esc(e.message)}</p><p>No medicine has been added.</p><button class="button primary" data-action="manual">Enter details manually</button><button class="button text-button" data-action="add">Try another label</button>${disclaimer()}`,
    );
  }
}
function entryDialog(m = {}, editing = false) {
  const source = m.source === "meta";
  modal(
    editing ? "Update this regimen" : "Review medicine details",
    `${source ? `<div class="source-note">${icon("check", 18)} Read live by ${esc(m.model)} · review required</div><p>${esc(m.explanation)}</p>${m.uncertainFields?.length ? `<p class="inline-warning">Please confirm: ${esc(m.uncertainFields.join(", "))}. Timing instructions: ${esc(m.frequency || "not specified")}.</p>` : ""}` : '<p class="dialog-intro">Copy the fictional prescription exactly. Do not use this form to decide a dose.</p>'}<form id="medicine-form" data-edit="${editing ? esc(m.id) : ""}"><div class="form-grid"><label>Medicine name<input name="name" list="known-medicines" value="${esc(m.name)}" required maxlength="100" placeholder="e.g. Metformin"><datalist id="known-medicines">${[...samples, { name: "Amlodipine" }, { name: "Atorvastatin" }, { name: "Warfarin" }, { name: "Insulin" }].map((s) => `<option value="${s.name}"></option>`).join("")}</datalist></label><label>Active ingredient<input name="ingredient" value="${esc(m.ingredient)}" required maxlength="100" placeholder="Confirm from label"></label><label>Strength (mg)<input name="strengthMg" type="number" min="0.001" step="any" value="${esc(m.strengthMg)}" required></label><label>Quantity per dose<input name="doseQuantity" type="number" min="0.01" max="100" step="any" value="${esc(m.doseQuantity)}" required></label><label>Dose unit<input name="doseUnit" value="${esc(m.doseUnit)}" placeholder="tablet, capsule…" required maxlength="30"></label><label>Start date<input name="startDate" type="date" value="${editing ? state.day : m.startDate || state.day}" required></label><label class="full">Times (24-hour, separated by commas)<input name="times" value="${esc(m.times?.join(", "))}" placeholder="08:00, 18:00" required></label><label class="full">Label instructions<input name="instructions" value="${esc(m.instructions)}" maxlength="300" placeholder="e.g. with meals"></label><label class="full">Medication class (if known)<input name="riskClass" value="${esc(m.riskClass)}" maxlength="60" placeholder="e.g. statin"></label></div><label class="checkbox"><input type="checkbox" name="highRisk" ${isHighRisk(m) ? "checked" : ""}> High-risk medicine / specialist timing plan</label><p class="muted">Recognized high-risk medicines are protected automatically, even if this box is unchecked.</p><label class="checkbox required"><input type="checkbox" name="reviewed" required> I checked every field against the synthetic prescription.</label><p id="form-error" class="inline-warning" hidden></p><button class="button primary full-width" type="submit">Check & save record ${icon("arrow", 18)}</button></form>${disclaimer()}`,
    true,
  );
}
function reviewCandidate(form) {
  const f = new FormData(form);
  const old = state.medications.find((m) => m.id === form.dataset.edit);
  const candidate = validateMedication({
    id: old?.id || uid(),
    name: f.get("name"),
    ingredient: f.get("ingredient"),
    strengthMg: Number(f.get("strengthMg")),
    doseQuantity: Number(f.get("doseQuantity")),
    doseUnit: f.get("doseUnit"),
    startDate: f.get("startDate"),
    times: f
      .get("times")
      .split(",")
      .map((t) => t.trim()),
    instructions: f.get("instructions"),
    riskClass: f.get("riskClass"),
    highRisk: f.has("highRisk"),
    status: "active",
    color: old?.color || "sage",
    demo: true,
    source: scanInfo?.source === "meta" ? "meta-reviewed" : "manual-reviewed",
  });
  if (old && candidate.startDate !== state.day)
    throw new Error(
      "Regimen updates take effect today. Add a separate future-start record if needed.",
    );
  if (candidate.startDate < state.day)
    throw new Error(
      "New regimens must start today or later; earlier dose records are preserved.",
    );
  pendingCandidate = { ...candidate, editing: old?.id };
  const identical =
    !old &&
    state.medications.find(
      (m) =>
        m.status === "active" &&
        canonical(m.name) === canonical(candidate.name) &&
        m.strengthMg === candidate.strengthMg &&
        m.doseQuantity === candidate.doseQuantity &&
        m.times.join() === candidate.times.join(),
    );
  if (identical) {
    closeDialog();
    page = "medicines";
    render();
    toast(
      "This exact medicine and schedule are already recorded. No duplicate was added.",
    );
    return;
  }
  const flags = checkRisks(candidate, state.medications, state.problems, now());
  if (flags.length) {
    modal(
      "Before this joins your schedule",
      `${flags.map(flagHtml).join("")}<label class="checkbox required"><input id="acknowledge" type="checkbox"> I understand these flags and will confirm with a doctor or pharmacist before starting this medicine.</label><p id="candidate-error" class="inline-warning" role="alert" hidden></p><button class="button primary full-width" data-action="save-candidate">Acknowledge & save demo record</button>${disclaimer()}`,
    );
    pendingCandidate.flags = flags;
  } else saveCandidate();
}
function saveCandidate() {
  const c = pendingCandidate;
  if (!c) return;
  const at = now().toISOString();
  if (c.editing) {
    state.medications = state.medications.map((m) =>
      m.id === c.editing
        ? {
            ...m,
            status: "stopped",
            endDate: c.startDate,
            archiveReason: "Regimen updated",
          }
        : m,
    );
    state.doses = state.doses.map((d) =>
      d.medicationId === c.editing &&
      d.status === "pending" &&
      localDay(d.scheduledAt) >= c.startDate
        ? {
            ...d,
            status: "cancelled",
            reason: "Superseded by a reviewed regimen",
          }
        : d,
    );
    c.id = uid();
  }
  const { editing, flags, ...med } = c;
  state.medications.push(med);
  state.doses.push(
    ...scheduleFor(med, state.day).filter(
      (d) => new Date(d.scheduledAt) >= now(),
    ),
  );
  state.flags.push(
    ...(flags || []).map((f) => ({
      ...f,
      id: uid(),
      medicationId: med.id,
      at,
      acknowledgedAt: at,
    })),
  );
  state.audit.push({
    id: uid(),
    type: editing ? "regimen_updated" : "medicine_added",
    at,
    reason: `${med.name}: reviewed ${med.doseQuantity} ${med.doseUnit} at ${med.times.join(", ")}.${flags?.length ? " Risk flags acknowledged." : ""}`,
  });
  pendingCandidate = null;
  scanInfo = null;
  closeDialog();
  page = "medicines";
  commit("Reviewed medicine record saved.");
}
function showReminder(id, read = false) {
  const d = state.doses.find((d) => d.id === id);
  if (!d || !["pending", "missed"].includes(d.status)) {
    toast("This dose is already recorded.");
    return;
  }
  const group = today().filter(
    (x) =>
      x.scheduledAt === d.scheduledAt &&
      ["pending", "missed"].includes(x.status),
  );
  drawReminder({ ids: group.map((d) => d.id), index: 0 });
  if (read) readReminder();
}
function drawReminder(r) {
  const d = state.doses.find((d) => d.id === r.ids[r.index]);
  const m = medFor(d);
  const late = now() - new Date(d.scheduledAt) > 30 * 60000;
  modal(
    "A moment to check in",
    `<div class="reminder-card"><span class="pill-label">MEDICINE ${r.index + 1} OF ${r.ids.length} · ${time(d.scheduledAt)}</span><span class="reminder-icon ${m.color || "sage"}">${icon("pill", 44)}</span><h3>${esc(m.name)}</h3><p class="reminder-strength">${m.strengthMg} mg</p><p class="reminder-dose">Recorded dose: <strong>${m.doseQuantity} ${esc(m.doseUnit)}</strong></p><p>${esc(m.instructions)}</p>${late ? `<div class="inline-warning">${isHighRisk(m) ? PHARMACIST : "This dose is late. Do not double a dose. Confirm timing with your pharmacist; record here only if already taken."}</div>` : ""}<div id="spoken-text" class="spoken-text" aria-live="polite"></div><button class="button secondary full-width large" data-action="speak">${icon("sound")} Read this reminder aloud</button><div class="reminder-controls">${r.index < r.ids.length - 1 ? '<button class="button primary large" data-action="next-card">Next medicine →</button>' : `<button class="button primary large" data-action="done">${icon("check")} Done — already taken${r.ids.length > 1 ? " all" : ""}</button>`}<button class="button secondary large" data-action="voice">${icon("mic")} Confirm by voice</button></div><button class="button text-button" data-action="skip">Record skipped dose</button><p class="muted">Practice confirmation time: ${time(state.demoTime)}. “Done” on the last card records all ${r.ids.length} ${r.ids.length === 1 ? "medicine" : "medicines"}.</p></div>${disclaimer()}`,
  );
  reminder = r;
}
async function readReminder() {
  if (!reminder) return;
  const d = state.doses.find((d) => d.id === reminder.ids[reminder.index]);
  const m = medFor(d);
  const box = document.querySelector("#spoken-text");
  box.textContent = "Generating a spoken reminder with Meta…";
  try {
    const data = await ai({
      task: "speak",
      medications: [m],
      language: state.language,
    });
    if (!document.contains(box)) return;
    box.textContent = data.text;
    speak(data.text);
  } catch (e) {
    box.textContent = e.message;
  }
}
function speak(text) {
  if (!window.speechSynthesis) {
    toast(
      "Speech playback is unavailable. The full reminder is shown on screen.",
    );
    return;
  }
  speechSynthesis.cancel();
  const speech = new SpeechSynthesisUtterance(text);
  speech.lang = state.language;
  speech.rate = 0.88;
  speechSynthesis.speak(speech);
}
function done(method = "button") {
  if (!reminder) return;
  const ids = [...reminder.ids];
  if (reminder.index !== ids.length - 1) {
    reminder.index++;
    drawReminder(reminder);
    return;
  }
  for (const id of ids) state = recordDose(state, id, "taken", method, now());
  closeDialog();
  commit("Dose confirmations saved with their exact time.");
  const late = ids
    .map((id) => state.doses.find((d) => d.id === id))
    .find((d) => d.status === "taken_late");
  if (late) offerReplan(late);
}
function voice() {
  const SR = window.SpeechRecognition || window.webkitSpeechRecognition;
  if (!SR) {
    toast(
      "Voice recognition is unavailable in this browser. The large Done button records the same confirmation.",
    );
    return;
  }
  recognition = new SR();
  recognition.lang = state.language;
  recognition.interimResults = false;
  const box = document.querySelector("#spoken-text");
  box.textContent =
    state.language === "es-ES"
      ? "Di “listo” o “siguiente”."
      : state.language === "hi-IN"
        ? "“हो गया” या “अगला” कहें।"
        : "Say “done” or “next”. Only these commands confirm or advance.";
  recognition.onresult = (e) => {
    const word = e.results[0][0].transcript
      .toLowerCase()
      .replace(/[.!?]/g, "")
      .trim();
    if (["done", "listo", "हो गया"].includes(word)) done("voice");
    else if (
      ["next", "siguiente", "अगला"].includes(word) &&
      reminder &&
      reminder.index < reminder.ids.length - 1
    ) {
      reminder.index++;
      drawReminder(reminder);
    } else
      box.textContent = `Heard “${word}”. No dose recorded. Please say the displayed command or use the button.`;
  };
  recognition.onerror = () => {
    box.textContent =
      "Microphone unavailable or no speech recognized. Use the large button to continue.";
  };
  recognition.start();
}
function offerReplan(d) {
  const m = medFor(d);
  if (isHighRisk(m)) {
    state.audit.push({
      id: uid(),
      type: "pharmacist_guardrail",
      at: now().toISOString(),
      reason: PHARMACIST,
    });
    persist();
    modal(
      "Check with your pharmacist",
      `<p class="inline-warning">${PHARMACIST}</p><p>Your confirmation is saved. No later times have been changed.</p>${disclaimer()}`,
    );
    return;
  }
  const future = today().filter(
    (x) => x.medicationId === m.id && x.status === "pending",
  );
  if (!future.length) return;
  modal(
    "Your late confirmation is saved",
    `<p>${esc(m.name)} was recorded at <strong>${time(d.confirmedAt)}</strong>, after its ${time(d.scheduledAt)} time.</p><p>The model can propose a timing change for this fictional metformin scenario. Its 10-hour spacing is a demonstration constraint, not a clinical dosing rule. Other medicines need a pharmacist-approved plan.</p><button class="button primary" data-action="replan" data-id="${esc(d.id)}">Ask Meta for a demo timing plan</button>${disclaimer()}`,
  );
}
async function replan(id) {
  const confirmed = state.doses.find((d) => d.id === id);
  const medication = medFor(confirmed);
  const future = today().filter(
    (d) => d.medicationId === medication.id && d.status === "pending",
  );
  modal(
    "Reviewing the demo timing",
    `<div class="loading"><span class="spinner"></span><p>Meta is preparing a timing-only proposal. Dose quantities stay unchanged.</p></div>${disclaimer()}`,
  );
  try {
    const result = await ai({
      task: "replan",
      medication,
      confirmed,
      future,
      timeZone: Intl.DateTimeFormat().resolvedOptions().timeZone,
    });
    state = applyReplan(state, medication, confirmed, result);
    commit();
    modal(
      "A timing adjustment, explained",
      `<span class="source-note">${icon("check", 18)} Live ${esc(result.model)} response</span><div class="timing-change">${result.changes.map((c) => `<span>${time(future.find((d) => d.id === c.doseId).scheduledAt)}</span>${icon("arrow", 28)}<strong>${time(c.newTime)}</strong>`).join("")}</div><p>${esc(result.explanation)}</p><p class="muted">Saved to the fictional schedule and change history. Quantity remains ${medication.doseQuantity} ${esc(medication.doseUnit)}.</p><button class="button secondary" data-action="read-explanation">${icon("sound")} Read explanation aloud</button><button class="button primary" data-action="close">Back to my day</button>${disclaimer()}`,
    );
    document.querySelector('[data-action="read-explanation"]').onclick = () =>
      speak(result.explanation);
  } catch (e) {
    state.audit.push({
      id: uid(),
      type: "replan_not_applied",
      at: now().toISOString(),
      reason: e.message,
    });
    persist();
    modal(
      "A pharmacist needs to review this",
      `<p class="inline-warning">${esc(e.message)}</p><p>Your recorded dose is saved. No remaining times or quantities have changed. Do not double a dose.</p>${disclaimer()}`,
    );
  }
}
function lateDemo() {
  const d = today().find(
    (d) =>
      d.medicationId === "med-metformin" &&
      new Date(d.originalScheduledAt).getHours() === 8,
  );
  if (!d) {
    toast(
      "The original demo regimen has been updated. Its historical records are preserved.",
    );
    return;
  }
  if (d.status.startsWith("taken")) {
    offerReplan(d);
    return;
  }
  modal(
    "Explore a late-dose check-in",
    `<p>In this fictional example, Alex’s 8:00 AM metformin dose was already taken at 10:00 AM.</p><p>Record that event, then ask Meta to adjust the remaining demo time. No medication amount will change.</p><button class="button primary" data-action="record-late" data-id="${esc(d.id)}">Record the 10:00 AM check-in</button>${disclaimer()}`,
  );
}
async function handle(action, el) {
  if (action === "nav") {
    page = el.dataset.page;
    render();
    window.scrollTo(0, 0);
  } else if (action === "close") closeDialog();
  else if (action === "add") {
    scanInfo = null;
    addDialog();
  } else if (action === "manual") {
    scanInfo = null;
    entryDialog();
  } else if (action === "sample") {
    const s = samples.find((x) => x.id === el.dataset.id);
    const r = await fetch(`/labels/${s.id}.png`);
    await scanImage(await r.blob());
  } else if (action === "text-entry") {
    modal(
      "Paste synthetic label text",
      `<form id="text-form"><label>Label text<textarea name="text" rows="7" maxlength="6000" required placeholder="Medicine, strength, dose and printed instructions…"></textarea></label><button class="button primary" type="submit">Read with Meta</button></form>${disclaimer()}`,
    );
  } else if (action === "edit") {
    scanInfo = null;
    entryDialog(
      state.medications.find((m) => m.id === el.dataset.id),
      true,
    );
  } else if (action === "save-candidate") {
    if (!document.querySelector("#acknowledge").checked) {
      const box = document.querySelector("#candidate-error");
      box.textContent = "Acknowledge the flags before saving this demo record.";
      box.hidden = false;
      return;
    }
    saveCandidate();
  } else if (action === "archive") {
    const m = state.medications.find((m) => m.id === el.dataset.id);
    modal(
      "Archive a medication record",
      `<p>This records an existing prescription change; it does not recommend stopping ${esc(m.name)}.</p><form id="archive-form" data-id="${m.id}"><label>Reason<input name="reason" required maxlength="200" placeholder="e.g. prescription already discontinued"></label><label class="checkbox required"><input type="checkbox" required> This reflects a change already made in the fictional care plan.</label><button class="button primary" type="submit">Archive record & retain history</button></form>${disclaimer()}`,
    );
  } else if (action === "reminder" || action === "read")
    showReminder(el.dataset.id, action === "read");
  else if (action === "demo-reminder") {
    const d = today().find((d) => d.status === "pending");
    if (d) showReminder(d.id);
    else
      toast("All of today’s doses have been recorded. Review them in History.");
  } else if (action === "speak") await readReminder();
  else if (action === "next-card") {
    const next = { ...reminder, index: reminder.index + 1 };
    drawReminder(next);
  } else if (action === "done") done();
  else if (action === "voice") voice();
  else if (action === "skip") {
    const id = reminder.ids[reminder.index];
    modal(
      "Record a skipped dose",
      `<p>Only record what already happened. For advice about a missed or skipped dose, contact your pharmacist.</p><form id="skip-form" data-id="${esc(id)}"><label>Reason (optional)<input name="reason" maxlength="200" placeholder="Add a note to your record"></label><button class="button primary" type="submit">Record skipped</button></form>${disclaimer()}`,
    );
  } else if (action === "late") lateDemo();
  else if (action === "record-late") {
    state.demoTime = atTime(state.day, "10:00");
    state = recordDose(
      state,
      el.dataset.id,
      "taken",
      "button",
      now(),
      "Fictional late-dose demonstration",
    );
    commit();
    offerReplan(state.doses.find((d) => d.id === el.dataset.id));
  } else if (action === "replan") await replan(el.dataset.id);
  else if (action === "clock") {
    modal(
      "Adjust the practice clock",
      `<p>Use a practice time to explore due, late, and missed reminders without waiting. Background Web Push uses real time.</p><form id="clock-form"><label>Practice time<input name="time" type="time" value="${new Date(state.demoTime).toTimeString().slice(0, 5)}" required></label><button class="button primary" type="submit">Set practice time</button></form>`,
    );
  } else if (action === "filter") {
    filter = {
      from: document.querySelector("#from").value,
      to: document.querySelector("#to").value,
      medication: document.querySelector("#medicine-filter").value,
    };
    if (!filter.from || !filter.to || filter.from > filter.to)
      throw new Error("Choose a valid date range.");
    render();
  } else if (action === "pdf") {
    el.disabled = true;
    const bytes = await makeHistoryPdf(state, filteredDoses(), filter);
    downloadFile(
      bytes,
      `pillcheck-history-${filter.from}-${filter.to}.pdf`,
      "application/pdf",
    );
    el.disabled = false;
    toast("Your history PDF is ready.");
  } else if (action === "json")
    downloadFile(
      JSON.stringify(state, null, 2),
      "pillcheck-demo-records.json",
      "application/json",
    );
  else if (action === "verify") {
    el.disabled = true;
    try {
      const d = await ai({ task: "connection" });
      toast(`${d.message} Model: ${d.model}.`);
    } finally {
      el.disabled = false;
    }
  } else if (action === "save-problems") {
    state.problems = document
      .querySelector("#problems")
      .value.split(",")
      .map((x) => x.trim())
      .filter(Boolean);
    state.audit.push({
      id: uid(),
      type: "class_concerns_updated",
      at: now().toISOString(),
      reason: state.problems.join(", ") || "No concerns recorded",
    });
    commit("Class concerns saved.");
  } else if (action === "push") {
    el.disabled = true;
    try {
      if (state.pushEnabled) {
        await disablePush(state);
        state.pushEnabled = false;
      } else {
        await enablePush(state);
        state.pushEnabled = true;
      }
      commit("Background reminder preferences saved.");
    } finally {
      el.disabled = false;
    }
  } else if (action === "test-push") {
    await testPush();
    toast("A test notification is scheduled in 10 seconds.");
  }
}
document.addEventListener("click", async (e) => {
  const el = e.target.closest("[data-action]");
  if (!el) return;
  try {
    await handle(el.dataset.action, el);
  } catch (err) {
    toast(err.message);
  }
});
document.addEventListener("submit", async (e) => {
  e.preventDefault();
  const f = e.target;
  try {
    if (f.id === "medicine-form") reviewCandidate(f);
    else if (f.id === "text-form")
      await extract({ text: new FormData(f).get("text") });
    else if (f.id === "skip-form") {
      state = recordDose(
        state,
        f.dataset.id,
        "skipped",
        "button",
        now(),
        new FormData(f).get("reason"),
      );
      closeDialog();
      commit("Skipped dose recorded.");
    } else if (f.id === "clock-form") {
      state.demoTime = atTime(state.day, new FormData(f).get("time"));
      closeDialog();
      commit("Practice clock updated.");
      checkReminders();
    } else if (f.id === "archive-form") {
      const id = f.dataset.id;
      const reason = new FormData(f).get("reason");
      state.medications = state.medications.map((m) =>
        m.id === id
          ? {
              ...m,
              status: "stopped",
              endDate: state.day,
              archiveReason: reason,
            }
          : m,
      );
      state.doses = state.doses.map((d) =>
        d.medicationId === id &&
        d.status === "pending" &&
        new Date(d.scheduledAt) >= now()
          ? { ...d, status: "cancelled", reason }
          : d,
      );
      state.audit.push({
        id: uid(),
        type: "medicine_archived",
        at: now().toISOString(),
        reason,
      });
      closeDialog();
      commit("Record archived. Earlier doses and regimens are preserved.");
    }
  } catch (err) {
    const box = document.querySelector("#form-error");
    if (box) {
      box.hidden = false;
      box.textContent = err.message;
    } else toast(err.message);
  }
});
document.addEventListener("change", async (e) => {
  const el = e.target;
  try {
    if (el.id === "label-file" && el.files[0]) await scanImage(el.files[0]);
    else if (el.id === "language") {
      state.language = el.value;
      persist();
    } else if (el.id === "reminders") {
      state.remindersEnabled = el.checked;
      persist();
      checkReminders();
    } else if (el.id === "window") {
      state.reminderWindowMinutes = Number(el.value);
      commit();
    } else if (el.name === "name") {
      const m = [...samples, ...state.medications].find(
        (m) => canonical(m.name) === canonical(el.value),
      );
      const ingredient = el.form.elements.ingredient;
      if (m && !ingredient.value) ingredient.value = m.ingredient;
    }
  } catch (err) {
    toast(err.message);
  }
});
function checkReminders() {
  if (!state.remindersEnabled) return;
  let changed = false;
  for (const d of today().filter((d) => d.status === "pending")) {
    const elapsed = (now() - new Date(d.scheduledAt)) / 60000;
    if (elapsed >= state.reminderWindowMinutes) {
      state = recordDose(
        state,
        d.id,
        "missed",
        "timer",
        now(),
        "Reminder window elapsed without confirmation",
      );
      changed = true;
      continue;
    }
    if (elapsed < 0) continue;
    const stage = elapsed < 15 ? 0 : 1 + Math.floor((elapsed - 15) / 30);
    if (
      !document.querySelector("dialog[open]") &&
      (state.reminderAttempts[d.id] ?? -1) < stage
    ) {
      state.reminderAttempts[d.id] = stage;
      showReminder(d.id);
      changed = true;
      break;
    }
  }
  if (changed) {
    commit();
  }
}
window.addEventListener("online", () => {
  render();
  if (state.pushEnabled) syncPush(state).catch((e) => toast(e.message));
});
window.addEventListener("offline", render);
setInterval(() => {
  const next = ensureToday(state);
  if (next !== state) {
    state = next;
    commit();
  }
  if (state.remindersEnabled) {
    state.demoTime = new Date(now().getTime() + 15000).toISOString();
    checkReminders();
    persist();
  }
}, 15000);
if ("serviceWorker" in navigator)
  navigator.serviceWorker
    .register("/sw.js")
    .catch(() => toast("Offline caching is unavailable in this browser."));
render();
persist();
if (state.pushEnabled) syncPush(state).catch((e) => toast(e.message));
