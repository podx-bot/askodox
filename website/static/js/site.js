/* ASKODOX website — progressive enhancement only. Every page works without JS. */
(function () {
  "use strict";

  var doc = document;
  var cfgEl = doc.getElementById("ax-config");
  var CFG = {};
  try { CFG = cfgEl ? JSON.parse(cfgEl.textContent) : {}; } catch (e) { CFG = {}; }
  var reduceMotion = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  function $(sel, root) { return (root || doc).querySelector(sel); }
  function $$(sel, root) { return Array.prototype.slice.call((root || doc).querySelectorAll(sel)); }
  function el(tag, attrs, html) {
    var n = doc.createElement(tag);
    if (attrs) Object.keys(attrs).forEach(function (k) { n.setAttribute(k, attrs[k]); });
    if (html != null) n.innerHTML = html;
    return n;
  }
  function esc(s) { return String(s).replace(/[&<>"']/g, function (c) { return ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]; }); }

  /* ---------------------------------------------------------------
     <askodox-companion> — the ASKODOX AI companion slot.
     Today it renders the brand orb. Future renderers (voice, animated
     or 3D companions) register on window.ASKODOX.companionRenderers
     and are chosen with the `renderer` attribute — pages don't change.
     States: idle | listening | thinking | speaking
     --------------------------------------------------------------- */
  window.ASKODOX = window.ASKODOX || {};
  var renderers = window.ASKODOX.companionRenderers = window.ASKODOX.companionRenderers || {};
  renderers.orb = function (host) {
    host.innerHTML = '<div class="orb" aria-hidden="true"><div class="orb-ring"></div><div class="orb-core"></div><div class="orb-eyes"><span></span><span></span></div></div>';
  };
  if (window.customElements && !customElements.get("askodox-companion")) {
    customElements.define("askodox-companion", class extends HTMLElement {
      connectedCallback() {
        if (this.dataset.ready) return;
        this.dataset.ready = "1";
        var name = this.getAttribute("renderer") || "orb";
        (renderers[name] || renderers.orb)(this);
        if (!this.hasAttribute("state")) this.setAttribute("state", "idle");
      }
      setState(s) { this.setAttribute("state", s); }
    });
  }

  /* ---------------- Mobile menu ---------------- */
  var menu = $("#mobile-menu"), openBtn = $("#menu-open"), closeBtn = $("#menu-close");
  function setMenu(open) {
    if (!menu) return;
    menu.classList.toggle("is-open", open);
    menu.setAttribute("aria-hidden", open ? "false" : "true");
    openBtn && openBtn.setAttribute("aria-expanded", open ? "true" : "false");
    doc.body.style.overflow = open ? "hidden" : "";
    if (open) { closeBtn && closeBtn.focus(); } else { openBtn && openBtn.focus(); }
  }
  openBtn && openBtn.addEventListener("click", function () { setMenu(true); });
  closeBtn && closeBtn.addEventListener("click", function () { setMenu(false); });
  doc.addEventListener("keydown", function (e) { if (e.key === "Escape" && menu && menu.classList.contains("is-open")) setMenu(false); });

  /* ---------------- Language selector ---------------- */
  var lang = $("#lang-select");
  lang && lang.addEventListener("change", function () {
    var opt = lang.options[lang.selectedIndex];
    if (opt && opt.dataset.href) window.location.href = opt.dataset.href;
  });

  /* ---------------- Hero ask box ---------------- */
  var EXAMPLES = [
    { q: "Find a plumber who can come tonight", r: [["Service", "plumber"], ["When", "tonight"], ["Where", "near you"]] },
    { q: "Sell my old road bike for €450", r: [["You are", "selling"], ["Item", "road bike"], ["Price", "€450"]] },
    { q: "A laptop for video editing under $900", r: [["Product", "laptop"], ["Use", "video editing"], ["Budget", "up to $900"]] },
    { q: "Catering for 40 guests this Saturday", r: [["Service", "catering"], ["Guests", "40"], ["Date", "Saturday"]] },
    { q: "Weekend photography work near me", r: [["You are", "offering a service"], ["Skill", "photography"], ["When", "weekends"]] },
    { q: "What does this rental agreement say about the deposit?", r: [["Task", "explain a document"], ["Focus", "deposit"]] },
    { q: "Any good offers on running shoes this week?", r: [["Looking for", "deals"], ["Product", "running shoes"]] },
    { q: "Show me video reviews comparing two phones", r: [["Looking for", "videos and reviews"], ["Compare", "phones"]] },
    { q: "A maths tutor who speaks Telugu, for my son", r: [["Service", "tutor"], ["Subject", "maths"], ["Language", "Telugu"]] }
  ];

  function readingChips(target, pairs) {
    if (!target) return;
    target.innerHTML = "";
    pairs.forEach(function (p, i) {
      var c = el("span", { "class": "chip" }, esc(p[0]) + " <b>" + esc(p[1]) + "</b>");
      c.style.animationDelay = (i * 120) + "ms";
      target.appendChild(c);
    });
  }

  function guess(text) {
    var t = (" " + text.toLowerCase() + " ");
    var out = [];
    var kind = "general";
    if (/\b(sell|selling|list my|offer my|i make|i bake|i'm a|i am a|i provide|hire me|work as|looking for work|weekend work|freelanc)/.test(t)) kind = "supply";
    else if (/\b(deal|deals|offer|offers|coupon|discount|sale)\b/.test(t)) kind = "deals";
    else if (/\b(video|videos|review|reviews|unboxing|compare)\b/.test(t)) kind = "videos";
    else if (/\b(document|agreement|contract|pdf|file|letter|invoice|form)\b/.test(t)) kind = "document";
    else if (/\b(plumber|electrician|repair|fix|clean|cleaning|tutor|teacher|catering|caterer|driver|ride|doctor|lawyer|salon|mechanic|painter|carpenter|photographer|service|install|book|appointment)\b/.test(t)) kind = "service";
    else if (/\b(buy|price|cheap|best|under|laptop|phone|shoes|tv|car|bike|rice|chicken|order|need a|want a|looking for)\b/.test(t)) kind = "product";
    var labels = { supply: ["You are", "offering something"], deals: ["Looking for", "deals and offers"], videos: ["Looking for", "videos and reviews"], document: ["Task", "understand a document"], service: ["Looking for", "a service"], product: ["Looking for", "a product"], general: ["Looking for", "help"] };
    out.push(labels[kind]);
    var money = text.match(/([€$£₹¥]|aed|usd|eur|inr|rs\.?)\s?\d[\d,.]*k?|\d[\d,.]*\s?(dollars|euros|rupees|aed)/i);
    if (money) out.push(["Budget", money[0]]);
    var when = text.match(/\b(today|tonight|tomorrow|this week|this weekend|weekend|weekends|monday|tuesday|wednesday|thursday|friday|saturday|sunday|now|asap)\b/i);
    if (when) out.push(["When", when[0]]);
    if (/\b(near|nearby|near me|around|local|close by)\b/i.test(text)) out.push(["Where", "near you"]);
    return { kind: kind, chips: out };
  }

  var PLAN = {
    supply: ["Understand what you offer and who it suits", "Turn it into a clear listing or profile", "Show it to people nearby who are asking for it", "Share your contact only when you accept a request"],
    service: ["Ask a couple of questions so it fits your situation", "Find suitable providers near you first", "Help you compare availability, reviews and price", "Send your request; contact is shared only after they accept"],
    product: ["Check what matters to you: use, budget, brand", "Look at nearby stores and sellers first, then online", "Compare options and point out trade-offs", "Connect you to the seller or the right link"],
    deals: ["Understand what you want to buy", "Show offers that actually apply to it", "Explain any conditions before you act", "Link you to the offer, clearly marked if it is a partner link"],
    videos: ["Understand what you're deciding", "Find helpful videos and reviews", "Summarise what reviewers agree and disagree on", "Help you decide what fits you"],
    document: ["Read the file you share", "Explain it in plain words", "Point out what to check or ask about", "Connect you with a professional if you need one"],
    general: ["Understand what you need", "Ask a follow-up question if something is unclear", "Find nearby and online options, information or people", "Help you decide and take the next step"]
  };

  var hero = $("#ask-form");
  if (hero) {
    var input = $("#ask-input"), reading = $("#ask-reading"), companion = $(".hero askodox-companion");
    var idx = 0, typing = null, rotating = true, userTouched = false;

    function typeExample(ex, done) {
      if (reduceMotion) { input.setAttribute("placeholder", ex.q); readingChips(reading, ex.r); done && setTimeout(done, 4200); return; }
      var i = 0;
      companion && companion.setState && companion.setState("listening");
      clearInterval(typing);
      reading.innerHTML = "";
      typing = setInterval(function () {
        if (!rotating) { clearInterval(typing); return; }
        i++;
        input.setAttribute("placeholder", ex.q.slice(0, i));
        if (i >= ex.q.length) {
          clearInterval(typing);
          companion && companion.setState && companion.setState("thinking");
          setTimeout(function () {
            if (!rotating) return;
            readingChips(reading, ex.r);
            companion && companion.setState && companion.setState("idle");
            done && setTimeout(done, 2600);
          }, 500);
        }
      }, 38);
    }
    function cycle() {
      if (!rotating) return;
      typeExample(EXAMPLES[idx % EXAMPLES.length], function () { idx++; cycle(); });
    }
    function stopRotation() {
      if (!rotating) return;
      rotating = false; clearInterval(typing);
      input.setAttribute("placeholder", CFG.askPrompt || "Type what you need");
      if (!userTouched) reading.innerHTML = "";
    }
    setTimeout(cycle, reduceMotion ? 0 : 1400);
    input.addEventListener("focus", stopRotation);
    input.addEventListener("input", function () {
      userTouched = true;
      var v = input.value.trim();
      if (v.length < 4) { reading.innerHTML = ""; return; }
      readingChips(reading, guess(v).chips);
    });
    hero.addEventListener("submit", function (e) {
      e.preventDefault();
      var v = input.value.trim();
      if (!v) { input.focus(); return; }
      if (CFG.webAppUrl) { window.location.href = CFG.webAppUrl + (CFG.webAppUrl.indexOf("?") > -1 ? "&" : "?") + "q=" + encodeURIComponent(v); return; }
      openSheet(v, guess(v).kind);
    });
    $$("[data-ask-mode]").forEach(function (b) {
      b.addEventListener("click", function () { openSheet(null, "mode:" + b.getAttribute("data-ask-mode")); });
    });
    $$('a[href="#ask-form"]').forEach(function (a) {
      a.addEventListener("click", function (e) { e.preventDefault(); stopRotation(); input.focus(); hero.scrollIntoView({ block: "center", behavior: reduceMotion ? "auto" : "smooth" }); });
    });
    $$("[data-example]").forEach(function (a) {
      a.addEventListener("click", function (e) {
        if (e.metaKey || e.ctrlKey) return;
        var q = a.getAttribute("data-example");
        if (!q) return;
        e.preventDefault();
        stopRotation(); userTouched = true;
        input.value = q; input.focus();
        readingChips(reading, guess(q).chips);
      });
    });
  }

  var sheet = $("#ask-sheet");
  function openSheet(text, kind) {
    if (!sheet) return;
    var body = $(".sheet-body", sheet);
    var modeNames = { voice: "Ask by voice", photo: "Ask with a photo", file: "Ask with a file" };
    var html = "";
    if (kind.indexOf("mode:") === 0) {
      var m = kind.slice(5);
      html += "<h2 id='sheet-title'>" + esc(modeNames[m] || "Ask ASKODOX") + "</h2>";
      html += "<p class='muted'>In the ASKODOX app you can speak, share a photo or attach a file, in the same conversation. It is in beta on Android today and coming to the web.</p>";
    } else {
      html += "<h2 id='sheet-title'>Here's how ASKODOX would help</h2>";
      html += "<div class='sheet-quote'>" + esc(text) + "</div>";
      html += "<ol class='sheet-plan'>" + PLAN[kind].map(function (s) { return "<li>" + esc(s) + "</li>"; }).join("") + "</ol>";
      html += "<p class='muted'>Asking on the web is coming soon. Today ASKODOX answers inside the Android app, which is in beta.</p>";
    }
    html += "<div class='btn-row'><a class='btn btn-primary' href='/join/'>Get early access</a><a class='btn btn-ghost' href='/how-it-works/'>See how it works</a></div>";
    body.innerHTML = html;
    if (typeof sheet.showModal === "function") sheet.showModal(); else window.location.href = "/how-it-works/";
  }
  if (sheet) {
    $(".sheet-close", sheet).addEventListener("click", function () { sheet.close(); });
    sheet.addEventListener("click", function (e) { if (e.target === sheet) sheet.close(); });
  }

  /* ---------------- Journey demo ---------------- */
  var ICON = {
    voice: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><rect x="9" y="3" width="6" height="12" rx="3"/><path d="M5 11a7 7 0 0 0 14 0M12 18v3"/></svg>',
    photo: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><rect x="3" y="6" width="18" height="14" rx="3"/><circle cx="12" cy="13" r="3.5"/><path d="M9 6l1.5-2h3L15 6"/></svg>',
    file: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"/><path d="M14 3v5h5"/></svg>',
    text: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M4 6h16M4 12h10M4 18h7"/></svg>'
  };
  ICON.pin = '<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 21s-7-6.2-7-11a7 7 0 0 1 14 0c0 4.8-7 11-7 11z"/><circle cx="12" cy="10" r="2.5"/></svg>';
  ICON.globe = '<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3c2.5 2.7 2.5 15.3 0 18M12 3c-2.5 2.7-2.5 15.3 0 18"/></svg>';
  var MODE_LABEL = { voice: "Voice", photo: "Photo", file: "File", text: "Typed" };
  function R(kind, title, sub, tag) { return { kind: kind, title: title, sub: sub, tag: tag }; }

  var SCENES = {
    plumber: { label: "Fix something tonight", steps: [
      { s: 1, who: "user", mode: "voice", text: "My kitchen sink is leaking. Can someone come tonight?" },
      { s: 3, who: "ai", text: "Got it. Have you turned off the water under the sink? And roughly where are you?", chips: ["Plumber", "Tonight", "Leak", "Near you"] },
      { s: 3, who: "user", mode: "text", text: "Valve is off. Near Alfama, Lisbon." },
      { s: 4, who: "ai", text: "Here's what fits:", results: [R("near", "Plumber", "1.4 km · evening visits", "Nearby"), R("near", "Home repair service", "2.1 km · emergency calls", "Nearby"), R("online", "Stop a sink leak until help arrives", "Video · 4 min", "Online")] },
      { s: 5, who: "ai", text: "The first one can come after 7 pm and handles leaks like yours. Shall I send them your request?" },
      { s: 6, who: "user", mode: "text", text: "Yes, send it." },
      { s: 7, who: "ai", text: "Request sent. Your number is shared only if they accept. I'll tell you the moment they reply.", action: "Request sent" }
    ] },
    bike: { label: "Sell something once", steps: [
      { s: 1, who: "user", mode: "photo", text: "I want to sell this bike." },
      { s: 3, who: "ai", text: "Looks like a road bike in good condition. What price do you have in mind, and when can buyers see it?", chips: ["Selling", "Road bike", "Used"] },
      { s: 3, who: "user", mode: "text", text: "€450. Saturday works." },
      { s: 4, who: "ai", text: "Your listing is ready:", results: [R("near", "Road bike, used", "€450 · viewing Saturday", "Your listing")] },
      { s: 5, who: "ai", text: "Publish it so people nearby who are looking for a bike can find it?" },
      { s: 6, who: "user", mode: "text", text: "Publish." },
      { s: 7, who: "ai", text: "Published. Interested buyers send a request, and you decide who gets your number.", action: "Listing live" }
    ] },
    laptop: { label: "Choose the right product", steps: [
      { s: 1, who: "user", mode: "text", text: "Best laptop for video editing under $900?" },
      { s: 3, who: "ai", text: "Do you edit 4K or mostly 1080p? Windows or Mac?", chips: ["Laptop", "Video editing", "Up to $900"] },
      { s: 3, who: "user", mode: "voice", text: "Mostly 1080p, Windows." },
      { s: 4, who: "ai", text: "I compared graphics, memory and screen:", results: [R("online", "3 laptops that fit", "Prices unverified until you open them", "Online"), R("near", "2 stores with stock", "Within 5 km", "Nearby"), R("online", "Editing laptops reviewed", "Video review", "Video")] },
      { s: 5, who: "ai", text: "For 1080p work, option two gives the most for the money. Want to see it nearby or online?" },
      { s: 6, who: "user", mode: "text", text: "Nearby, I want to try it." },
      { s: 7, who: "ai", text: "Here are directions to the closest store that has it.", action: "Directions" }
    ] },
    catering: { label: "Plan an event", steps: [
      { s: 1, who: "user", mode: "text", text: "Catering for 40 people this Saturday, vegetarian." },
      { s: 3, who: "ai", text: "What's your budget per plate, and should they serve at your venue?", chips: ["Catering", "40 guests", "Saturday", "Vegetarian"] },
      { s: 3, who: "user", mode: "text", text: "₹350 a plate, served at home in Hyderabad." },
      { s: 4, who: "ai", text: "Two caterers near you fit:", results: [R("near", "Caterer", "3 km · vegetarian menus", "Nearby"), R("near", "Event caterer with staff", "5 km · serves at home", "Nearby")] },
      { s: 5, who: "ai", text: "Both fit your budget. The second also brings serving staff." },
      { s: 6, who: "user", mode: "text", text: "Ask both." },
      { s: 7, who: "ai", text: "Done. Their replies will appear in Updates.", action: "2 requests sent" }
    ] },
    photographer: { label: "Find work", steps: [
      { s: 1, who: "user", mode: "voice", text: "I'm a photographer. I'd like weekend work: events and portraits." },
      { s: 3, who: "ai", text: "Which area do you cover? A few sample photos would help people choose you.", chips: ["Offering a service", "Photography", "Weekends"] },
      { s: 3, who: "user", mode: "file", text: "Within 15 km. Here are three samples." },
      { s: 4, who: "ai", text: "Your profile is ready:", results: [R("near", "Event and portrait photographer", "Weekends · within 15 km", "Your profile")] },
      { s: 5, who: "ai", text: "Turn on requests so people nearby who need a photographer can reach you?" },
      { s: 6, who: "user", mode: "text", text: "Yes." },
      { s: 7, who: "ai", text: "You're on. When someone nearby asks for a photographer, their request comes straight to you.", action: "Requests on" }
    ] },
    document: { label: "Understand a document", steps: [
      { s: 1, who: "user", mode: "file", text: "rental-agreement.pdf: what should I check before signing?" },
      { s: 3, who: "ai", text: "I'll go through it. Is this a home you'll live in, or a shop?", chips: ["Explain a document", "Rental agreement"] },
      { s: 3, who: "user", mode: "text", text: "A flat." },
      { s: 4, who: "ai", text: "Three things to look at closely:", results: [R("online", "Deposit refund terms", "When and how it is returned", "Check"), R("online", "Notice period", "How early either side must tell", "Check"), R("online", "Repairs", "Who pays for what", "Check")] },
      { s: 5, who: "ai", text: "These notes help you ask the right questions. They aren't legal advice." },
      { s: 6, who: "user", mode: "text", text: "Can someone confirm it for me?" },
      { s: 7, who: "ai", text: "I can connect you with a lawyer near you who reviews rental agreements.", action: "Find a lawyer" }
    ] }
  };

  var journey = $("#journey");
  if (journey) {
    var chat = $("#demo-chat", journey), stepsEls = $$(".steps li", journey), tabs = $$(".need-tabs button", journey);
    var phoneCompanion = $(".phone askodox-companion", journey);
    var timer = null, current = null, started = false, autoAdvance = true;

    function render(step) {
      var m = el("div", { "class": "msg " + (step.who === "user" ? "msg-user" : "msg-ai") });
      var h = "";
      if (step.who === "user" && step.mode) h += "<span class='msg-mode'>" + ICON[step.mode] + MODE_LABEL[step.mode] + "</span>";
      h += esc(step.text);
      if (step.chips) h += "<div class='msg-chips'>" + step.chips.map(function (c) { return "<span>" + esc(c) + "</span>"; }).join("") + "</div>";
      if (step.results) h += step.results.map(function (r) {
        return "<div class='result'><i class='" + (r.kind === "online" ? "online" : "") + "'>" + (r.kind === "online" ? ICON.globe : ICON.pin) + "</i><div><b>" + esc(r.title) + "</b><small>" + esc(r.sub) + "</small></div><em>" + esc(r.tag) + "</em></div>";
      }).join("");
      if (step.action) h += "<span class='msg-action'>" + esc(step.action) + "</span>";
      m.innerHTML = h;
      chat.appendChild(m);
      while (chat.children.length > 4) chat.removeChild(chat.firstChild);
    }
    function markSteps(s) {
      stepsEls.forEach(function (li, i) {
        var n = i + 1;
        li.classList.toggle("is-active", n === s);
        li.classList.toggle("is-done", n < s);
      });
    }
    function play(key) {
      clearTimeout(timer);
      current = key;
      tabs.forEach(function (t) { t.setAttribute("aria-selected", t.dataset.scene === key ? "true" : "false"); t.tabIndex = t.dataset.scene === key ? 0 : -1; });
      chat.innerHTML = "";
      var steps = SCENES[key].steps;
      if (reduceMotion) {
        steps.slice(-4).forEach(render);
        markSteps(7);
        return;
      }
      var i = 0;
      (function next() {
        if (current !== key) return;
        var st = steps[i];
        if (st.s === 1) markSteps(1);
        phoneCompanion && phoneCompanion.setState && phoneCompanion.setState(st.who === "user" ? "listening" : "speaking");
        if (st.s === 1) { render(st); markSteps(2); }
        else { markSteps(st.s); render(st); }
        i++;
        if (i < steps.length) { timer = setTimeout(next, st.who === "user" ? 1300 : 2300); }
        else {
          phoneCompanion && phoneCompanion.setState && phoneCompanion.setState("idle");
          if (autoAdvance) {
            timer = setTimeout(function () {
              var keys = Object.keys(SCENES);
              play(keys[(keys.indexOf(key) + 1) % keys.length]);
            }, 4200);
          }
        }
      })();
    }
    tabs.forEach(function (t, i) {
      t.addEventListener("click", function () { autoAdvance = false; play(t.dataset.scene); });
      t.addEventListener("keydown", function (e) {
        var d = e.key === "ArrowRight" ? 1 : e.key === "ArrowLeft" ? -1 : 0;
        if (!d) return;
        e.preventDefault();
        var n = tabs[(i + d + tabs.length) % tabs.length];
        n.focus(); autoAdvance = false; play(n.dataset.scene);
      });
    });
    function start() { if (started) return; started = true; play(tabs[0].dataset.scene); }
    // Show a finished example straight away (also covers print and full-page captures).
    SCENES[tabs[0].dataset.scene].steps.slice(-4).forEach(render);
    markSteps(7);
    if ("IntersectionObserver" in window) {
      var io = new IntersectionObserver(function (entries) { entries.forEach(function (en) { if (en.isIntersecting) { start(); io.disconnect(); } }); }, { threshold: 0.25 });
      io.observe(journey);
    } else { start(); }
    doc.addEventListener("visibilitychange", function () { if (doc.hidden) { clearTimeout(timer); } else if (started && current) { play(current); } });
  }

  /* ---------------- Roles (multi-select) ---------------- */
  var ROLES = {
    buyer: { t: "Buying", items: [["Ask", "Describe what you want in your own words, with a budget if you have one."], ["Compare", "See nearby and online options side by side, with the trade-offs explained."], ["Connect", "Send a request to the seller; they see your number only if you choose."]], link: ["/discover/", "How discovery works"] },
    seller: { t: "Selling", items: [["List", "Tell ASKODOX what you sell; it drafts the listing for you."], ["Reach", "People nearby who ask for it can find you."], ["Decide", "Accept the requests you want. Contact is shared after you accept."]], link: ["/sellers/", "ASKODOX for sellers"] },
    provider: { t: "Offering a service", items: [["Profile", "Say what you do, where and when; add photos of past work."], ["Requests", "Relevant requests from people nearby come to you."], ["Grow", "Build repeat customers through direct connections."]], link: ["/service-providers/", "ASKODOX for service providers"] },
    freelancer: { t: "Freelancing", items: [["Show your skill", "Describe your work once; ASKODOX keeps it ready to share."], ["Find work", "Get matched with people who need exactly that skill."], ["Stay in control", "Choose which requests to take."]], link: ["/service-providers/", "Freelancers and professionals"] },
    creator: { t: "Creating", items: [["Help people decide", "Useful videos and reviews can be shown when someone is choosing."], ["Programme", "A creator programme is being prepared."], ["Status", "Coming soon. Tell us you're interested."]], link: ["/videos/", "Videos and creators"] },
    business: { t: "Running a business", items: [["Be found", "Show up when people nearby ask for what you offer."], ["Offers", "Run offers that are shown only when they're relevant."], ["Partner", "Talk to us about integrations and partnerships."]], link: ["/partners/", "Partner with ASKODOX"] },
    oneoff: { t: "Selling one thing", items: [["Snap and say", "Take a photo, say a price, and your listing is ready."], ["Nearby buyers", "People close by can find it quickly."], ["Private", "You share your number only with the buyer you accept."]], link: ["/sellers/", "Selling something once"] },
    survey: { t: "Sharing opinions", items: [["Surveys", "Take part in surveys and share what you think."], ["Status", "Coming soon."], ["Your choice", "Participation will always be optional."]], link: ["/status/", "See what's coming"] },
    curious: { t: "Looking for help or information", items: [["Ask anything", "Questions, documents, comparisons, how-tos."], ["Plain answers", "ASKODOX explains things simply and says when it isn't sure."], ["Next step", "If you need a person, it helps you find the right one."]], link: ["/how-it-works/", "How ASKODOX works"] }
  };
  var picker = $("#role-picker"), out = $("#role-out");
  if (picker && out) {
    function paint() {
      var on = $$("button[aria-pressed='true']", picker).map(function (b) { return b.dataset.role; });
      if (!on.length) { out.innerHTML = "<h3>Pick one or more</h3><p class='muted'>Most people are more than one thing. Choose everything that fits you.</p>"; return; }
      var h = "<h3>" + esc(on.map(function (k) { return ROLES[k].t; }).join(" + ")) + "</h3><ul>";
      var seen = {};
      on.forEach(function (k) {
        ROLES[k].items.slice(0, on.length > 2 ? 1 : on.length > 1 ? 2 : 3).forEach(function (it) { h += "<li><b>" + esc(it[0]) + "</b><span>" + esc(it[1]) + "</span></li>"; });
      });
      h += "</ul><p style='margin-top:1.25rem'>" + on.map(function (k) { var l = ROLES[k].link; if (seen[l[0]]) return ""; seen[l[0]] = 1; return "<a href='" + l[0] + "'>" + esc(l[1]) + "</a>"; }).filter(Boolean).join("<br>") + "</p>";
      out.innerHTML = h;
    }
    $$("button", picker).forEach(function (b) {
      b.addEventListener("click", function () { b.setAttribute("aria-pressed", b.getAttribute("aria-pressed") === "true" ? "false" : "true"); paint(); });
    });
    paint();
  }

  /* ---------------- Forms (mailto composer, or endpoint when configured) ---------------- */
  $$("form[data-compose]").forEach(function (form) {
    form.addEventListener("submit", function (e) {
      e.preventDefault();
      if (!form.reportValidity()) return;
      var data = {};
      $$("input, select, textarea", form).forEach(function (f) { if (f.name && f.type !== "checkbox") data[f.name] = f.value.trim(); if (f.type === "checkbox") data[f.name] = f.checked ? "yes" : "no"; });
      var subject = (form.getAttribute("data-subject") || "ASKODOX website") + (data.topic ? ": " + data.topic : "");
      var result = $(".form-result", form);
      if (CFG.formsEndpoint) {
        fetch(CFG.formsEndpoint, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ form: form.getAttribute("data-compose"), subject: subject, fields: data, page: location.pathname }) })
          .then(function (r) { if (!r.ok) throw new Error(r.status); result.textContent = "Sent. We'll reply by email."; result.classList.add("show"); form.reset(); })
          .catch(function () { mail(); });
      } else { mail(); }
      function mail() {
        var lines = Object.keys(data).map(function (k) { return k.replace(/_/g, " ") + ": " + data[k]; });
        var to = form.getAttribute("data-to") || CFG.supportEmail;
        window.location.href = "mailto:" + to + "?subject=" + encodeURIComponent(subject) + "&body=" + encodeURIComponent(lines.join("\n") + "\n\n(sent from " + location.href + ")");
        result.innerHTML = "Your email app should open with this message ready to send. If it doesn't, write to <a href='mailto:" + esc(to) + "'>" + esc(to) + "</a>.";
        result.classList.add("show");
      }
    });
  });
})();
