"""Illustrated demo blocks for the ASKODOX website.

Everything here is EXAMPLE content: no real businesses, listings, prices,
reviews or availability. Every block that shows example results carries a
visible "Example" marker and a note saying so. Product pictures are
illustrations drawn in SVG, never photos of real items.
"""
from __future__ import annotations

from build import e, fbadge, icon, t

# ---------------------------------------------------------------------------
# Line-art product illustrations (viewBox 0 0 160 110)
# ---------------------------------------------------------------------------

ART = {
    "bike": '<circle cx="42" cy="72" r="22"/><circle cx="118" cy="72" r="22"/><path d="M42 72l24-36h34l18 36M66 36l18 36h-42M84 72l16-36M60 30h14M96 30l8-6h10"/>',
    "laptop": '<rect x="40" y="22" width="80" height="52" rx="5"/><rect x="47" y="29" width="66" height="38" rx="2"/><path d="M28 80h104l-8 10H36z"/>',
    "shoe": '<path d="M26 74c0-14 6-26 14-30l16 10c10 6 22 8 34 8 18 0 34 6 42 16v8H26z"/><path d="M26 82h106M56 54l-6 8M66 59l-5 8M76 62l-4 8"/>',
    "sofa": '<rect x="34" y="34" width="92" height="30" rx="8"/><path d="M26 52c0-6 8-8 10-2v22h88V50c2-6 10-4 10 2v24H26zM36 76v8M124 76v8M80 36v28"/>',
    "ac": '<rect x="28" y="30" width="104" height="36" rx="8"/><path d="M38 56h84M44 76c4 4 4 10 0 14M80 76c4 4 4 10 0 14M116 76c4 4 4 10 0 14"/><circle cx="118" cy="42" r="3"/>',
    "phone": '<rect x="58" y="14" width="44" height="82" rx="8"/><path d="M72 22h16M76 86h8"/><rect x="64" y="30" width="32" height="48" rx="2"/>',
    "scooter": '<circle cx="40" cy="80" r="12"/><circle cx="120" cy="80" r="12"/><path d="M40 80h56l14-52h12M110 28l10 52M52 70h44"/><path d="M118 24h10"/>',
    "wrench": '<path d="M96 22a18 18 0 0 0-22 24L38 82l10 10 36-36a18 18 0 0 0 24-22l-11 11-9-2-2-9z"/>',
    "camera": '<rect x="34" y="34" width="92" height="56" rx="10"/><circle cx="80" cy="62" r="18"/><circle cx="80" cy="62" r="8"/><path d="M58 34l8-12h28l8 12M112 44h6"/>',
    "box": '<path d="M36 40l44-18 44 18v44l-44 18-44-18z"/><path d="M36 40l44 18 44-18M80 58v44M58 31l44 18"/>',
    "store": '<path d="M30 46l8-24h84l8 24M30 46h100v8a12 12 0 0 1-25 0 12 12 0 0 1-25 0 12 12 0 0 1-25 0 12 12 0 0 1-25 0z"/><path d="M36 60v34h88V60M68 94V72h24v22"/>',
    "plate": '<circle cx="80" cy="58" r="32"/><circle cx="80" cy="58" r="20"/><path d="M30 26v62M24 26v14a6 6 0 0 0 12 0V26M132 26c-8 4-10 18-6 30h6v32"/>',
}

TONES = {"violet": "art-violet", "blue": "art-blue", "amber": "art-amber", "mint": "art-mint", "rose": "art-rose"}


def art(key: str, tone: str = "violet", label: str = "") -> str:
    lab = e(label or f"Illustration of a {key}")
    return (f'<figure class="art {TONES.get(tone, "art-violet")}"><svg viewBox="0 0 160 110" role="img" aria-label="{lab}">'
            f'<g fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round">{ART[key]}</g></svg></figure>')


# ---------------------------------------------------------------------------
# Result cards
# ---------------------------------------------------------------------------

TAG_CLASS = {"Nearby": "t-near", "Online": "t-web", "Used": "t-used", "New": "t-new", "Surplus": "t-surplus",
             "Offer": "t-offer", "Service": "t-service", "Affiliate link": "t-paid", "Sponsored": "t-paid"}


def tags(names: list[str]) -> str:
    return '<span class="tags">' + "".join(f'<span class="tag {TAG_CLASS.get(n, "")}">{e(n)}</span>' for n in names) + "</span>"


def result_card(r: dict) -> str:
    """r: art, tone, tags, title, price, was, meta, avail, trust[list], action, kinds."""
    price = f'<span class="price">{e(r["price"])}</span>' if r.get("price") else ""
    if r.get("was"):
        price += f' <s class="was" aria-label="Before: {e(r["was"])}">{e(r["was"])}</s>'
    note = f'<span class="unverified">{e(r["note"])}</span>' if r.get("note") else ""
    trust = "".join(f'<li>{icon(i)}<span>{e(txt)}</span></li>' for i, txt in r.get("trust", []))
    trust_html = f'<ul class="trust-row">{trust}</ul>' if trust else ""
    return f"""<article class="rcard" data-kinds="{e(' '.join(r['kinds']))}">
  {art(r['art'], r.get('tone', 'violet'), r.get('alt', ''))}
  <div class="rbody">
    {tags(r['tags'])}
    <h3>{e(r["title"])}</h3>
    <p class="pline">{price}{note}</p>
    <p class="meta">{icon('pin')}<span>{e(r['meta'])}</span></p>
    <p class="avail">{icon('clock')}<span>{e(r['avail'])}</span></p>
    {trust_html}
    <span class="ract">{e(r['action'])}</span>
  </div>
</article>"""


BIKE_RESULTS = [
    {"art": "bike", "tone": "violet", "tags": ["Nearby", "Used"], "kinds": ["nearby", "used"], "title": "Road bike, 2019, size M", "price": "€420",
     "meta": "1.2 km · Alfama", "avail": "Can be seen Saturday", "trust": [("check", "Phone-verified seller"), ("star", "Reviews after completed requests")], "action": "Send request", "alt": "Illustration of a road bike"},
    {"art": "bike", "tone": "blue", "tags": ["Nearby", "New", "Offer"], "kinds": ["nearby", "new", "offers"], "title": "New road bike, local shop", "price": "€489", "was": "€549",
     "meta": "2.8 km · Baixa", "avail": "In stock today", "trust": [("check", "Phone-verified seller")], "action": "Send request", "alt": "Illustration of a new road bike"},
    {"art": "box", "tone": "amber", "tags": ["Nearby", "Surplus"], "kinds": ["nearby", "surplus", "offers"], "title": "Clearance: last year's model", "price": "€399",
     "meta": "4.1 km · Benfica", "avail": "Last unit", "trust": [("check", "Phone-verified seller")], "action": "Send request", "alt": "Illustration of a boxed bike"},
    {"art": "wrench", "tone": "mint", "tags": ["Nearby", "Service"], "kinds": ["nearby", "services"], "title": "Bike mechanic: check-up before you buy", "price": "from €25",
     "meta": "900 m · Graça", "avail": "Free tomorrow morning", "trust": [("check", "Phone-verified provider")], "action": "Send request", "alt": "Illustration of a wrench"},
    {"art": "bike", "tone": "rose", "tags": ["Online", "New"], "kinds": ["online", "new"], "title": "Road bike, online store", "price": "€465", "note": "Price unverified",
     "meta": "Ships to Lisbon", "avail": "Delivery in 3 to 5 days", "trust": [], "action": "Open link", "alt": "Illustration of a road bike sold online"},
    {"art": "store", "tone": "violet", "tags": ["Online", "Affiliate link"], "kinds": ["online", "offers"], "title": "Partner store (how a partner result looks)", "price": "€472", "note": "Price unverified",
     "meta": "Online", "avail": "Shown only when a partner programme is approved", "trust": [], "action": "Open partner link", "alt": "Illustration of an online store"},
]

FILTERS = [("all", "All"), ("nearby", "Nearby"), ("online", "Online"), ("used", "Used"), ("new", "New"), ("surplus", "Surplus"), ("offers", "Offers"), ("services", "Services")]


def results_demo(cfg: dict) -> str:
    filters = "".join(f'<button type="button" data-filter="{k}" aria-pressed="{"true" if k == "all" else "false"}">{e(v)}</button>' for k, v in FILTERS)
    cards = "".join(result_card(r) for r in BIKE_RESULTS)
    return f"""<div class="results-demo" id="results-demo">
  <div class="convo">
    <div class="bubble b-user"><span class="bmode">{icon('mic')}Voice</span>A road bike under €500, near me. Used is fine.</div>
    <div class="bubble b-ai">Got it: road bike, up to €500, new or used, near Alfama. What size do you ride?
      <span class="asks"><span>Size?</span><span>Pick up or delivery?</span></span></div>
    <div class="bubble b-user">Medium. I can pick up.</div>
    <div class="bubble b-ai">Here's what fits, closest first. I've added a mechanic in case you buy used.</div>
  </div>
  <div class="filters" role="group" aria-label="Filter example results">{filters}</div>
  <div class="rgrid" aria-live="polite">{cards}</div>
  <p class="demo-flag"><span class="tag t-example">{e(t('example'))}</span> Sample results to show how ASKODOX labels things. Not real listings, prices, sellers or availability. No partner programme is active yet.</p>
</div>"""


LEGEND = [
    ("Nearby", "Sellers and providers around you. Shown first."),
    ("Online", "From the web, when it fits or nothing suitable is nearby."),
    ("Used", "Second-hand, sold by a person or shop."),
    ("New", "New items."),
    ("Surplus", "Clearance, overstock or end-of-line."),
    ("Offer", "A discount or deal that applies to your request."),
    ("Service", "A person or business who does the job."),
    ("Affiliate link", "ASKODOX may earn a commission. Always labelled."),
    ("Sponsored", "Paid placement. Always labelled. Not used today."),
]


def label_legend() -> str:
    rows = "".join(f'<li><span class="tag {TAG_CLASS.get(n, "")}">{e(n)}</span><span>{e(d)}</span></li>' for n, d in LEGEND)
    return f'<ul class="legend-list">{rows}</ul>'


# ---------------------------------------------------------------------------
# Local first, online fallback, no local match
# ---------------------------------------------------------------------------

def fallback_flow(cfg: dict) -> str:
    return f"""<ol class="widen">
  <li><span class="ring r1" aria-hidden="true"></span><div><h3>Around you</h3><p>Sellers and providers closest to you come first.</p></div></li>
  <li><span class="ring r2" aria-hidden="true"></span><div><h3>A wider area</h3><p>If nothing fits, ASKODOX looks further out and tells you how far.</p></div></li>
  <li><span class="ring r3" aria-hidden="true"></span><div><h3>Online</h3><p>Relevant online options, labelled Online, with prices marked unverified. {fbadge(cfg, 'online_fallback')}</p></div></li>
</ol>"""


def no_match(cfg: dict) -> str:
    return f"""<div class="nomatch">
  <div class="nm-card" role="img" aria-label="Example of ASKODOX saying no suitable nearby result yet">
    <div class="bubble b-user">Hand-made leather sandals, size 42, near me</div>
    <div class="bubble b-ai nm-ai">
      <strong>No suitable nearby result yet.</strong>
      <span>I couldn't find a seller near you with this today. Here's what I can do:</span>
      <span class="nm-actions"><span>See online options</span><span>Widen the area</span><span>Tell me when one appears</span></span>
    </div>
    <span class="tag t-example">{e(t('example'))}</span>
  </div>
  <div class="nm-paths">
    <a href="/discover/#online"><b>See online alternatives</b><span>Labelled Online, prices unverified until you check. {fbadge(cfg, 'online_fallback')}</span></a>
    <a href="/join/#seller"><b>Make this yours: register your business or service</b><span>People are asking. Be the one nearby who answers.</span></a>
    <a href="/join/#refer"><b>Know someone who sells this?</b><span>Refer a seller, provider or business.</span></a>
    <div class="nm-why"><b>Why join ASKODOX</b><ul><li>Requests from people nearby who already want what you offer</li><li>List by chatting, no forms or catalogues</li><li>You choose which requests to accept</li><li>Free during the beta</li></ul></div>
  </div>
</div>"""


# ---------------------------------------------------------------------------
# Videos and reviews
# ---------------------------------------------------------------------------

VIDEO_TYPES = [
    {"k": "review", "tab": "Product review", "kind": "Review", "title": "Electric scooter: 6 months later", "len": "8:24", "art": "scooter", "tone": "violet",
     "q": "Is the battery good enough for a 20 km daily ride?",
     "a": "In this review the owner gets about 25 to 30 km per charge in city riding, less on hills. For 20 km a day you'd charge daily.",
     "cmp": ["Range", "Weight", "Service nearby"],
     "rel": [("scooter", "Nearby", "Same model, showroom", "₹54,999", "3.4 km · Madhapur"), ("wrench", "Service", "Scooter service centre", "Service from ₹499", "2.1 km"), ("scooter", "Online", "Longer-range model", "₹61,500 · unverified", "Online")]},
    {"k": "owner", "tab": "Owner experience", "kind": "Owner story", "title": "Why we switched to a split AC", "len": "5:10", "art": "ac", "tone": "blue",
     "q": "Would a 1.5 ton unit cool a 180 sq ft room?",
     "a": "The owner's room is similar and they say 1.5 ton is comfortable. For 180 sq ft, 1 to 1.5 ton is the usual range; a 5-star rating saves power.",
     "cmp": ["Tonnage", "Power use", "Installation"],
     "rel": [("ac", "Nearby", "1.5 ton split AC, dealer", "₹38,990", "1.8 km"), ("wrench", "Service", "AC installation", "from ₹1,500", "Available tomorrow"), ("ac", "Used", "1 ton split AC, 2 years old", "₹17,000", "4 km")]},
    {"k": "howto", "tab": "How-to", "kind": "How-to", "title": "Fix a leaking tap in 10 minutes", "len": "4:02", "art": "wrench", "tone": "mint",
     "q": "Mine is a mixer tap. Will this work?",
     "a": "The video shows a single tap. Mixer taps use a cartridge, so you'd need the matching part. If it's still dripping, a plumber nearby can do it.",
     "cmp": ["Do it yourself", "Part needed", "Call a plumber"],
     "rel": [("box", "Nearby", "Tap cartridge, hardware shop", "€9", "600 m"), ("wrench", "Service", "Plumber", "Visit from €40", "Free this evening")]},
    {"k": "compare", "tab": "Comparison", "kind": "Comparison", "title": "Two mid-range phones, side by side", "len": "12:47", "art": "phone", "tone": "rose",
     "q": "Which one has the better camera at night?",
     "a": "The reviewer prefers the second phone's night photos but says the first has better battery life. If night photos matter most, choose the second.",
     "cmp": ["Night camera", "Battery", "Price"],
     "rel": [("phone", "Nearby", "Phone B, mobile store", "$449", "1.5 km"), ("phone", "Online", "Phone B, online", "$429 · unverified", "Online"), ("phone", "Used", "Phone A, like new", "$310", "3 km")]},
    {"k": "seller", "tab": "Seller video", "kind": "Seller video", "title": "Inside our furniture workshop", "len": "2:30", "art": "sofa", "tone": "amber",
     "q": "Can they make this sofa in 2 metres?",
     "a": "The seller says in the video that sizes are made to order. I can send them your request with the size; they'll reply in Updates.",
     "cmp": ["Custom size", "Fabric", "Delivery time"],
     "rel": [("sofa", "Nearby", "This workshop", "Made to order", "5 km"), ("sofa", "Online", "Ready-made 2 m sofa", "$899 · unverified", "Online")]},
    {"k": "provider", "tab": "Provider video", "kind": "Provider video", "title": "What a deep clean includes", "len": "3:15", "art": "box", "tone": "mint",
     "q": "Do they bring their own supplies?",
     "a": "Yes, the provider says supplies are included. Ask about pets or allergies when you send the request.",
     "cmp": ["Supplies", "Time taken", "Price"],
     "rel": [("wrench", "Service", "This cleaning team", "from AED 250", "Available Saturday"), ("wrench", "Service", "Another team nearby", "from AED 220", "Available Sunday")]},
    {"k": "creator", "tab": "Creator", "kind": "Creator", "title": "Best street food on a budget", "len": "9:58", "art": "plate", "tone": "rose",
     "q": "Where is the second place and is it open now?",
     "a": "The second stall in the video is about 2 km from you and opens at 6 pm. Want directions?",
     "cmp": ["Distance", "Opening hours", "Veg options"],
     "rel": [("plate", "Nearby", "Stall from the video", "Open 6 pm", "2 km"), ("plate", "Nearby", "Similar stall", "Open now", "800 m")]},
]


def _rel_card(item: tuple) -> str:
    a, tag, title, price, meta = item
    return (f'<div class="relc">{art(a, "violet", "")}<div><span class="tag {TAG_CLASS.get(tag, "")}">{e(tag)}</span>'
            f'<b>{e(title)}</b><small>{e(price)} · {e(meta)}</small></div></div>')


def video_demo(cfg: dict, compact: bool = False) -> str:
    tabs = "".join(f'<button type="button" role="tab" id="vt-{v["k"]}" aria-controls="vp-{v["k"]}" aria-selected="{"true" if i == 0 else "false"}" tabindex="{0 if i == 0 else -1}">{e(v["tab"])}</button>'
                   for i, v in enumerate(VIDEO_TYPES))
    panels = []
    for i, v in enumerate(VIDEO_TYPES):
        rel = "".join(_rel_card(r) for r in v["rel"])
        cmp_ = "".join(f"<span>{e(c)}</span>" for c in v["cmp"])
        panels.append(f"""<div class="vpanel" role="tabpanel" id="vp-{v['k']}" aria-labelledby="vt-{v['k']}"{'' if i == 0 else ' hidden'}>
  <div class="player">
    <div class="poster poster-{v['tone']}">{art(v['art'], v['tone'], '')}<span class="vkind">{e(v['kind'])}</span><span class="vplay" aria-hidden="true"></span><span class="vlen">{e(v['len'])}</span></div>
    <p class="vtitle">{e(v['title'])}</p>
  </div>
  <div class="vchat">
    <div class="bubble b-user">{e(v['q'])}</div>
    <div class="bubble b-ai">{e(v['a'])}<span class="asks">{cmp_}</span></div>
    <div class="vrel"><p class="vrel-h">Related options</p>{rel}</div>
    <div class="vacts"><span>Send request</span><span>Compare</span><span>Ask another question</span></div>
  </div>
</div>""")
    return f"""<div class="video-demo" id="video-demo">
  <div class="vtabs" role="tablist" aria-label="Kinds of video">{tabs}</div>
  {''.join(panels)}
  <p class="demo-flag"><span class="tag t-example">{e(t('example'))}</span> Illustrated example. Videos, answers and options shown are samples, not real content or listings.</p>
</div>"""


def video_flow(cfg: dict) -> str:
    steps = [("Watch", "A review, how-to or seller video."), ("Ask", "Type or say a question about it."), ("Understand", "ASKODOX uses the video and product context."),
             ("Explain", "A plain answer, with what the video does and doesn't cover."), ("Compare", "Against what matters to you."), ("Options", "Nearby and online, labelled."), ("Act", "Request, connect, buy or register.")]
    return '<ol class="vflow">' + "".join(f"<li><b>{e(a)}</b><span>{e(b)}</span></li>" for a, b in steps) + "</ol>"


# ---------------------------------------------------------------------------
# Deals
# ---------------------------------------------------------------------------

def deals_demo(cfg: dict) -> str:
    return f"""<div class="deals-demo">
  <div class="bubble b-user">Running shoes for flat feet, size 9, under $120</div>
  <div class="bubble b-ai">These fit your size and budget. Two have offers that apply.</div>
  <div class="dgrid">
    <article class="dcard">{art('shoe', 'blue', 'Illustration of a running shoe')}<div>{tags(['Nearby', 'Offer'])}<b>Stability running shoe</b>
      <p class="pline"><span class="price">$96</span> <s class="was">$120</s></p><p class="dterm">Store offer: 20% off this week, in-store only.</p></div></article>
    <article class="dcard">{art('shoe', 'violet', 'Illustration of a running shoe')}<div>{tags(['Online', 'Affiliate link'])}<b>Same shoe, online</b>
      <p class="pline"><span class="price">$99</span><span class="unverified">Price unverified</span></p><p class="dterm">How a partner offer would look. No partner programme is active yet.</p></div></article>
    <article class="dcard">{art('shoe', 'amber', 'Illustration of a running shoe')}<div>{tags(['Nearby', 'Used'])}<b>Worn twice, size 9</b>
      <p class="pline"><span class="price">$55</span></p><p class="dterm">From a person nearby.</p></div></article>
    <article class="dcard dcard-reward"><div class="rbadge" aria-hidden="true">★</div><div>{tags(['Offer'])}<b>Reward on completion</b>
      <p class="dterm">Some ASKODOX offers add a reward once you confirm the request is complete. {fbadge(cfg, 'rewards')}</p></div></article>
  </div>
  <p class="demo-flag"><span class="tag t-example">{e(t('example'))}</span> Sample offers. Not real stores, prices or promotions.</p>
</div>"""


# ---------------------------------------------------------------------------
# Consent
# ---------------------------------------------------------------------------

def consent_demo(cfg: dict) -> str:
    return f"""<div class="consent">
  <div class="cphone"><span class="cstate">Before they accept</span><b>Request: AC repair tomorrow</b><span class="cline">{icon('pin')} Area: Kondapur</span><span class="cline masked">{icon('phone')} +•• ••••• •••••</span><span class="clock">Number hidden</span></div>
  <div class="carrow" aria-hidden="true"></div>
  <div class="cphone open"><span class="cstate">After they accept</span><b>Request accepted</b><span class="cline">{icon('pin')} Area: Kondapur</span><span class="cline">{icon('phone')} Contact shared with both sides</span><span class="clock ok">Connected</span></div>
</div>"""
