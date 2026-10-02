"""Page content for the ASKODOX website.

Every claim here must stay true. Feature availability is never written by
hand: use fbadge(cfg, "<feature id>") so the label follows config/site.json.
"""
from __future__ import annotations

import math

from build import Page, badge, e, fbadge, icon


# ---------------------------------------------------------------------------
# Shared fragments
# ---------------------------------------------------------------------------

def page_hero(title: str, lead: str, crumb: str, ctas: str = "") -> str:
    return f"""<section class="page-hero">
  <div class="wrap">
    <p class="crumbs"><a href="/">Home</a> / <span>{e(crumb)}</span></p>
    <h1>{e(title)}</h1>
    <p>{e(lead)}</p>
    {f'<div class="btn-row">{ctas}</div>' if ctas else ''}
  </div>
</section>"""


def cta_band(title: str, text: str, ctas: str) -> str:
    return f"""<section class="section-tight zone-day"><div class="wrap">
  <div class="cta-band"><h2>{e(title)}</h2><p>{e(text)}</p><div class="btn-row">{ctas}</div></div>
</div></section>"""


def blocks(items: list[tuple[str, str, str]]) -> str:
    out = []
    for title, text, status in items:
        out.append(f"<div><h3>{e(title)} {status}</h3><p>{text}</p></div>")
    return '<div class="blocks">' + "".join(out) + "</div>"


def mail(cfg: dict, kind: str = "support_email") -> str:
    m = cfg["contact"][kind]
    return f'<a href="mailto:{e(m)}">{e(m)}</a>'


def store_buttons(cfg: dict) -> str:
    app = cfg["app"]
    def one(url: str, ico: str, small_live: str, big: str, fid: str) -> str:
        if url:
            return f'<a class="store" href="{e(url)}" rel="noopener">{icon(ico)}<span><small>{e(small_live)}</small><b>{e(big)}</b></span></a>'
        status = cfg["feature"][fid]["status"]
        small = "In beta, coming soon to" if status == "beta" else "Coming soon to"
        return f'<span class="store" aria-disabled="true">{icon(ico)}<span><small>{small}</small><b>{e(big)}</b></span></span>'
    return '<div class="btn-row">' + one(app.get("play_store_url"), "android", "Get it on", "Google Play", "android_app") + one(app.get("app_store_url"), "apple", "Download on the", "App Store", "ios_app") + "</div>"


def phone_static() -> str:
    return """<div class="phone app-phone" aria-hidden="true"><div class="phone-screen">
  <div class="phone-bar"><askodox-companion></askodox-companion><div><b>ASKODOX</b><small>Here to help</small></div></div>
  <div class="chat">
    <div class="msg msg-user"><span class="msg-mode">Voice</span>Need someone to fix my AC tomorrow morning</div>
    <div class="msg msg-ai">Split or window AC? Is it not cooling, or not turning on?<div class="msg-chips"><span>AC repair</span><span>Tomorrow</span><span>Morning</span></div></div>
    <div class="msg msg-user">Split, not cooling</div>
    <div class="msg msg-ai">Two technicians near you have morning slots.<div class="result"><i>●</i><div><b>AC technician</b><small>1.8 km · 9–11 am</small></div><em>Nearby</em></div><span class="msg-action">Send request</span></div>
  </div>
  <div class="phone-input"><span>Ask ASKODOX</span></div>
</div></div>"""


def globe_svg() -> str:
    cx, cy, r = 200, 200, 150
    parts = [f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="url(#gg)" stroke="#30375F"/>']
    for lat in range(-60, 61, 30):
        y = cy - r * math.sin(math.radians(lat))
        rx = r * math.cos(math.radians(lat))
        parts.append(f'<ellipse cx="{cx}" cy="{y:.1f}" rx="{rx:.1f}" ry="{rx * 0.18:.1f}" fill="none" stroke="#30375F" stroke-width="1"/>')
    for lon in range(-75, 76, 25):
        rx = abs(r * math.sin(math.radians(lon)))
        parts.append(f'<ellipse cx="{cx}" cy="{cy}" rx="{rx:.1f}" ry="{r}" fill="none" stroke="#30375F" stroke-width="1"/>')
    pins = [(120, 150, "Hello"), (250, 120, "Hola"), (290, 210, "నమస్తే"), (150, 250, "مرحبا"), (230, 290, "Bonjour"), (95, 205, "Olá"), (310, 150, "你好")]
    for x, y, word in pins:
        parts.append(f'<circle cx="{x}" cy="{y}" r="5" fill="#39C8FF"/><circle cx="{x}" cy="{y}" r="12" fill="none" stroke="#39C8FF" stroke-opacity=".35"/>')
        parts.append(f'<text x="{x + 14}" y="{y + 4}" fill="#E2DAFF" font-size="14" font-family="Bricolage Grotesque, sans-serif">{e(word)}</text>')
    return ('<svg class="globe" viewBox="0 0 400 400" role="img" aria-label="A globe with greetings in several languages">'
            '<defs><radialGradient id="gg" cx=".35" cy=".3"><stop offset="0" stop-color="#2a2370"/><stop offset="1" stop-color="#090B1D"/></radialGradient></defs>'
            + "".join(parts) + "</svg>")


def map_svg() -> str:
    roads = "".join(f'<path d="{d}" stroke="#1d2247" stroke-width="{w}" fill="none"/>' for d, w in [
        ("M-20 120 C 120 100, 220 160, 520 110", 14), ("M60 -20 C 90 120, 150 260, 120 420", 12), ("M-20 300 C 140 280, 300 330, 520 290", 10),
        ("M330 -20 C 300 120, 360 260, 330 420", 10), ("M-20 210 L 520 230", 6), ("M220 -20 L 240 420", 6)])
    rings = "".join(f'<circle cx="230" cy="210" r="{r}" fill="none" stroke="#603EFF" stroke-opacity="{o}" stroke-dasharray="4 6"/>' for r, o in [(60, .7), (115, .45), (170, .25)])
    pins = "".join(f'<g transform="translate({x} {y})"><circle r="7" fill="{c}"/><circle r="15" fill="none" stroke="{c}" stroke-opacity=".35"/></g>' for x, y, c in [(180, 170, "#B48CFF"), (300, 250, "#B48CFF"), (140, 280, "#8A5CF6"), (330, 140, "#8A5CF6"), (420, 330, "#4f4a8a")])
    me = '<g transform="translate(230 210)"><circle r="11" fill="#39C8FF"/><circle r="5" fill="#fff"/></g>'
    return f'<svg class="map" viewBox="0 0 500 400" preserveAspectRatio="xMidYMid slice" aria-hidden="true"><rect width="500" height="400" fill="#0b0d22"/>{roads}{rings}{pins}{me}</svg>'


# ---------------------------------------------------------------------------
# Home
# ---------------------------------------------------------------------------

def home(cfg: dict) -> Page:
    b = cfg["brand"]
    entries = [
        ("#ask-form", "spark", "Ask ASKODOX", ""),
        ("/discover/#products", "bag", "Find products", "A laptop for video editing under $900"),
        ("/discover/#services", "tools", "Find services", "Find a plumber who can come tonight"),
        ("/discover/#nearby", "pin", "Discover nearby", "Good tailors near me"),
        ("/discover/#online", "globe", "Explore online", "Where can I buy this online?"),
        ("/deals/", "tag", "Deals and offers", "Any good offers on running shoes this week?"),
        ("/videos/", "play", "Videos and reviews", "Show me video reviews comparing two phones"),
        ("/sellers/", "store", "Sell or offer a service", ""),
    ]
    entry_html = "".join(
        f'<li class="{"entry-sell" if href == "/sellers/" else ""}"><a href="{href}"' + (f' data-example="{e(ex)}"' if ex else "") + f">{icon(ic)}{e(label)}</a></li>"
        for href, ic, label, ex in entries
    )
    tabs = [("plumber", "Fix something tonight"), ("laptop", "Choose a product"), ("bike", "Sell something once"), ("catering", "Plan an event"), ("photographer", "Find work"), ("document", "Understand a document")]
    tab_html = "".join(f'<button type="button" role="tab" aria-controls="journey-panel" data-scene="{k}" aria-selected="{"true" if i == 0 else "false"}" tabindex="{0 if i == 0 else -1}">{e(t)}</button>' for i, (k, t) in enumerate(tabs))
    steps = [
        ("A need", "Something to buy, fix, sell, learn or decide."),
        ("Ask ASKODOX", "In your own words: type, speak, show a photo or share a file."),
        ("It understands", "It picks out what matters and asks only what it needs to."),
        ("It discovers", "Nearby first, online too: products, people, services, information."),
        ("It helps you decide", "Clear comparisons and honest trade-offs."),
        ("It connects", "With the right person, with your consent."),
        ("You move forward", "And ASKODOX keeps you updated."),
    ]
    steps_html = "".join(f"<li><div><strong>{e(t)}</strong><span>{e(d)}</span></div></li>" for t, d in steps)

    roles = [("buyer", "Buyer", True), ("seller", "Seller", False), ("provider", "Service provider", False), ("freelancer", "Freelancer or professional", False), ("creator", "Creator", False), ("business", "Business", False), ("oneoff", "Selling one thing", False), ("survey", "Survey participant", False), ("curious", "Just looking for help", False)]
    roles_html = "".join(f'<button type="button" data-role="{k}" aria-pressed="{"true" if on else "false"}">{e(t)}</button>' for k, t, on in roles)

    body = f"""
<section class="hero" aria-labelledby="hero-title">
  <div class="wrap hero-inner">
    <askodox-companion data-rise style="--i:0" aria-hidden="true"></askodox-companion>
    <h1 id="hero-title"><span class="wordmark" data-rise style="--i:1">{e(b['name'])}</span><span class="tagline" data-rise style="--i:2">{e(b['tagline'])}</span></h1>
    <p class="hero-sub" data-rise style="--i:3">One place to ask for anything you need, discover the right options, decide with confidence and connect with the right people.</p>
    <form class="ask" id="ask-form" role="search" data-rise style="--i:4" action="/how-it-works/">
      <label class="ask-label" for="ask-input">{e(b['ask_prompt'])}</label>
      <div class="ask-box">
        <input id="ask-input" name="q" type="text" autocomplete="off" enterkeyhint="send" placeholder="Type what you need">
        <button class="ask-tool optional" type="button" data-ask-mode="photo" aria-label="Ask with a photo">{icon('camera')}</button>
        <button class="ask-tool optional" type="button" data-ask-mode="file" aria-label="Ask with a file">{icon('file')}</button>
        <button class="ask-tool" type="button" data-ask-mode="voice" aria-label="Ask by voice">{icon('mic')}</button>
        <button class="ask-go" type="submit" aria-label="Ask">{icon('send')}</button>
      </div>
      <div class="ask-reading" id="ask-reading" aria-live="polite"></div>
    </form>
    <ul class="entry" data-rise style="--i:5" aria-label="Ways to start">{entry_html}</ul>
  </div>
</section>

<section class="section zone-deep" id="journey" aria-labelledby="journey-title">
  <div class="wrap">
    <div class="section-head">
      <h2 id="journey-title">Say what you need. ASKODOX takes it from there.</h2>
      <p>It's not a search box, a shop or a directory. It's one conversation that moves from a need to a result. Pick a situation to see it.</p>
    </div>
    <div class="need-tabs" role="tablist" aria-label="Example situations">{tab_html}</div>
    <div class="journey-grid" id="journey-panel" role="tabpanel" aria-label="Example conversation">
      <div>
        <ol class="steps">{steps_html}</ol>
        <p class="demo-note">Illustrative example with sample data. Places and results shown are not real listings.</p>
      </div>
      <div class="phone" role="img" aria-label="An ASKODOX conversation playing on a phone">
        <div class="phone-screen">
          <div class="phone-bar"><askodox-companion></askodox-companion><div><b>ASKODOX</b><small>Here to help</small></div><span class="phone-sample">Sample</span></div>
          <div class="chat" id="demo-chat" aria-live="off"></div>
          <div class="phone-input">{icon('camera')}<span>Ask ASKODOX</span>{icon('mic')}</div>
        </div>
      </div>
    </div>
  </div>
</section>

<section class="section zone-day" aria-labelledby="modes-title">
  <div class="wrap">
    <div class="section-head">
      <h2 id="modes-title">Ask the way that's easiest for you</h2>
      <p>Switch between them in the same conversation. ASKODOX keeps the context.</p>
    </div>
    <div class="modes">
      <div class="mode"><div class="mode-icon">{icon('type')}</div><h3>Type it</h3><p><q>Gift ideas for my dad, he loves gardening, under £40.</q></p>{fbadge(cfg, 'text_ask')}</div>
      <div class="mode"><div class="mode-icon">{icon('mic')}</div><h3>Say it</h3><p><q>Need a driver to the airport at 5 tomorrow morning.</q> In your own language, as you'd say it to a friend.</p>{fbadge(cfg, 'voice_ask')}</div>
      <div class="mode"><div class="mode-icon">{icon('camera')}</div><h3>Show it</h3><p>A photo of a part, a product or a problem. <q>Where can I get this fixed?</q></p>{fbadge(cfg, 'image_ask')}</div>
      <div class="mode"><div class="mode-icon">{icon('file')}</div><h3>Share it</h3><p>A quote, a bill or an agreement. <q>Is this a fair price?</q></p>{fbadge(cfg, 'file_ask')}</div>
    </div>
  </div>
</section>

<section class="section zone-mist" id="nearby" aria-labelledby="nearby-title">
  <div class="wrap split">
    <div class="split-copy">
      <h2 id="nearby-title">Nearby first. Online when it's better.</h2>
      <p>Often the best option is around the corner. Sometimes it's online. ASKODOX looks at both and tells you which is which.</p>
      <ul class="ticks">
        <li><span>Uses your location only when you allow it, and never shows your exact location to others.</span></li>
        <li><span>Shows sellers and providers near you before anything far away.</span></li>
        <li><span>Adds online options when they fit, with prices marked unverified until you check them.</span></li>
        <li><span>Works by neighbourhood, city or country. {fbadge(cfg, 'nearby')}</span></li>
      </ul>
    </div>
    <div class="discover-visual" role="img" aria-label="A map with nearby options around you, and online options alongside">
      {map_svg()}
      <div class="dv-card"><span class="dv-tag near">Nearby</span><b>Tailor</b><small>650 m · open till 8 pm</small></div>
      <div class="dv-card"><span class="dv-tag near">Nearby</span><b>Alterations studio</b><small>1.2 km · same-day</small></div>
      <div class="dv-stack"><div class="dv-card"><span class="dv-tag web">Online</span><b>Hemming kit, how-to video</b><small>Delivery in 2 days</small></div></div>
    </div>
  </div>
</section>

<section class="section zone-day" aria-labelledby="roles-title">
  <div class="wrap roles">
    <div>
      <div class="section-head" style="margin-bottom:1.5rem">
        <h2 id="roles-title">You're probably more than one of these</h2>
        <p>Buy on Monday, sell on Saturday, offer your skills on Sunday. ASKODOX follows what you say you want to do, not a box you signed up in.</p>
      </div>
      <div class="role-picker" id="role-picker" role="group" aria-label="What do you do? Choose all that fit">{roles_html}</div>
      <p class="role-hint">Choose all that fit.</p>
    </div>
    <div class="role-out" id="role-out" aria-live="polite">
      <h3>Buying</h3>
      <ul><li><b>Ask</b><span>Describe what you want in your own words.</span></li><li><b>Compare</b><span>Nearby and online options side by side.</span></li><li><b>Connect</b><span>Send a request; your number is shared only if you choose.</span></li></ul>
    </div>
  </div>
</section>

<section class="section zone-mist" aria-labelledby="duo-title">
  <div class="wrap">
    <h2 id="duo-title" class="visually-hidden">Deals, videos and reviews</h2>
    <div class="duo">
      <a class="panel panel-deals" href="/deals/">
        <div class="btn-row">{fbadge(cfg, 'offers')}</div>
        <h3>Deals and offers that fit what you asked for</h3>
        <p>Not a wall of coupons. When an offer applies to your need, ASKODOX shows it, explains the conditions, and marks partner links clearly.</p>
        <div class="ticket" aria-hidden="true"><span class="pct">%</span><div><b>Offer matched to your request</b><small>Shown only when it's relevant</small></div></div>
        <div class="panel-foot"><strong>Explore deals</strong><span class="muted">Partner deals {badge(cfg['feature']['partner_deals']['status'])}</span></div>
      </a>
      <a class="panel panel-videos" href="/videos/">
        <div class="btn-row">{fbadge(cfg, 'video_results')}</div>
        <h3>Videos and reviews that help you decide</h3>
        <p>See how something works, what reviewers think and what owners wish they'd known, inside the answer.</p>
        <div class="reel" aria-hidden="true"><div>How it works</div><div>Honest review</div><div>Comparison</div></div>
        <div class="panel-foot"><strong>Explore videos</strong><span class="muted">Creator programme {badge(cfg['feature']['creators']['status'])}</span></div>
      </a>
    </div>
  </div>
</section>

<section class="section zone-night" aria-labelledby="connect-title">
  <div class="wrap">
    <div class="section-head">
      <h2 id="connect-title">Direct connections, on your terms</h2>
      <p>ASKODOX introduces you to the right person. Your phone number stays private until both sides say yes. {fbadge(cfg, 'consent_connect')}</p>
    </div>
    <ol class="flow">
      <li><h3>You ask</h3><p>A buyer, customer or client says what they need.</p></li>
      <li class="locked"><h3>A request goes out</h3><p>Only to relevant sellers or providers. They see the need and your area, not your number.</p></li>
      <li class="locked"><h3>They accept</h3><p>The seller or provider chooses to take it on.</p></li>
      <li class="unlocked"><h3>You're connected</h3><p>Contact details are shared, and you talk directly. No middleman in your conversation.</p></li>
    </ol>
  </div>
</section>

<section class="section zone-day" aria-labelledby="trust-title">
  <div class="wrap">
    <div class="section-head">
      <h2 id="trust-title">Built to be trusted</h2>
      <p>These are the rules ASKODOX is built around.</p>
    </div>
    <ul class="trust">
      <li><h3>You control your contact details</h3><p>Shared only after a request is accepted.</p></li>
      <li><h3>Your location stays yours</h3><p>Used when you allow it. Others see your area, never your exact spot.</p></li>
      <li><h3>Honest answers</h3><p>Unverified prices are labelled. When ASKODOX isn't sure, it says so.</p></li>
      <li><h3>Paid links are labelled</h3><p>Partner or affiliate links are always disclosed. <a href="/affiliate-disclosure/">How it works</a></p></li>
      <li><h3>Your data, your choice</h3><p>Download or delete your data from the app, or ask us by email.</p></li>
      <li><h3>Real people behind it</h3><p>Write to us and a person reads it: {mail(cfg)}</p></li>
    </ul>
  </div>
</section>

<section class="section zone-deep" aria-labelledby="global-title">
  <div class="wrap global">
    <div>{globe_svg()}</div>
    <div>
      <div class="section-head" style="margin-bottom:0">
        <h2 id="global-title">Made for your street, ready for the world</h2>
        <p>ASKODOX is built to work in any country, language and currency, while staying useful at the level of your own neighbourhood.</p>
      </div>
      <div class="facts">
        <div><b>Languages</b><span>The app speaks English and Telugu today, with more on the way. {fbadge(cfg, 'languages')}</span></div>
        <div><b>Currencies</b><span>Built to handle prices in any currency, shown the way you expect.</span></div>
        <div><b>Places</b><span>Nearby discovery is tuned for India first, with more countries planned.</span></div>
        <div><b>Partners</b><span>Built to plug into partners and services around the world as they're approved.</span></div>
      </div>
    </div>
  </div>
</section>

<section class="section zone-night" aria-labelledby="app-title">
  <div class="wrap app-band">
    <div>
      <div class="section-head" style="margin-bottom:1.5rem">
        <h2 id="app-title">ASKODOX in your pocket</h2>
        <p>The ASKODOX app has the full experience: the companion, voice, photos, nearby discovery, requests and updates. Android is in beta now. {fbadge(cfg, 'android_app')}</p>
      </div>
      {store_buttons(cfg)}
      <p class="muted" style="margin-top:1rem">Want to try the beta? <a href="/join/">Ask for early access</a>.</p>
    </div>
    {phone_static()}
  </div>
</section>

<section class="section zone-day" id="join" aria-labelledby="join-title">
  <div class="wrap">
    <div class="section-head">
      <h2 id="join-title">Join ASKODOX</h2>
      <p>Start in the way that fits you today. You can always do more later.</p>
    </div>
    <div class="join">
      <a href="/join/#buyer"><b>Join as a buyer</b><span>Ask, compare and connect.</span><em>Get early access</em></a>
      <a href="/join/#seller"><b>Join as a seller</b><span>List what you sell and receive requests.</span><em>Start selling</em></a>
      <a href="/join/#provider"><b>Join as a service provider</b><span>Get relevant requests from people nearby.</span><em>Offer your service</em></a>
      <a href="/join/#refer"><b>Refer a business</b><span>Know someone good? Tell us about them.</span><em>Refer them</em></a>
    </div>
  </div>
</section>

<dialog class="sheet" id="ask-sheet" aria-labelledby="sheet-title">
  <button class="sheet-close" type="button" aria-label="Close">×</button>
  <div class="sheet-body"></div>
</dialog>
"""
    return Page("/", "Home", f"ASKODOX helps you ask for anything you need, discover nearby and online options, decide with confidence and connect directly with the right people. {b['tagline']}", body, priority="1.0")


# ---------------------------------------------------------------------------
# Inner pages
# ---------------------------------------------------------------------------

def about(cfg: dict) -> Page:
    body = page_hero("Here to help you grow", "ASKODOX exists to help people move forward: to solve everyday needs, make better decisions, find opportunities and grow.", "About ASKODOX") + f"""
<section class="section zone-day"><div class="wrap prose">
  <p class="lead">Most days are full of small decisions and needs. Who can fix this? Is this a fair price? Where can I sell that? Who needs what I can offer? Today the answers are scattered across search engines, marketplaces, directories, social media and word of mouth.</p>
  <p>ASKODOX brings them into one conversation. You say what you need, in your own words and language. ASKODOX works out what matters, finds the right options nearby and online, helps you compare them and connects you with the right person, with your consent.</p>
  <h2>Not one more marketplace</h2>
  <p>ASKODOX isn't a shop, a directory or a chatbot. It's a gateway that works for everyone on both sides of a need: buyers and sellers, customers and service providers, people looking for work and people offering it, creators, businesses and anyone who just wants a clear answer.</p>
  <p>A person can be all of these on different days. ASKODOX follows what you want to do now, instead of locking you into one role.</p>
  <h2>What we believe</h2>
  <ul>
    <li><strong>Local matters.</strong> The best help is often close by. ASKODOX looks nearby first.</li>
    <li><strong>Consent comes first.</strong> Contact details are shared only when both sides agree.</li>
    <li><strong>Honesty over hype.</strong> We label what's live, what's in beta and what's coming. We don't invent numbers, reviews or partners.</li>
    <li><strong>Everyone, everywhere.</strong> Built for many countries, languages and currencies from day one.</li>
  </ul>
  <h2>Where we are today</h2>
  <p>ASKODOX is early. The Android app is in beta and being tested by real people. This website is live, and support is available by email. You can see exactly what's available on the <a href="/status/">What's live</a> page.</p>
  <h2>Talk to us</h2>
  <p>Questions, ideas or partnership interest: {mail(cfg, 'general_email')}.</p>
</div></section>
""" + cta_band("See ASKODOX in action", "Watch how one conversation goes from a need to a result.", '<a class="btn btn-primary" href="/how-it-works/">How it works</a><a class="btn btn-ghost" href="/join/">Get early access</a>')
    return Page("/about/", "About ASKODOX", "ASKODOX is an AI-powered everyday platform that helps people ask, discover, decide, connect and grow. Learn what we believe and where we are today.", body, crumb="About")


def how_it_works(cfg: dict) -> Page:
    steps = [
        ("Tell ASKODOX what you need", f"Type it, say it, show a photo or share a file. Use your own words and your own language. Nothing to fill in. {fbadge(cfg, 'text_ask')}"),
        ("ASKODOX understands", "It picks out what matters (what, where, when, budget, and whether you're buying, selling or offering something) and asks a short follow-up only when it needs to."),
        ("It discovers what fits", f"Sellers, service providers, professionals, products, information, videos and offers. Nearby first, online when that's better. {fbadge(cfg, 'nearby')}"),
        ("It helps you decide", "Options are compared on what you said matters. Trade-offs are explained. Unverified prices are labelled."),
        ("It connects you", f"Send a request to the seller or provider you choose. Your number is shared only after they accept. {fbadge(cfg, 'consent_connect')}"),
        ("You move forward", "Follow replies and updates in one place. If something goes wrong, ask for help from the same conversation."),
    ]
    items = "".join(f"<li><h3>{e(t)}</h3><p>{d}</p></li>" for t, d in steps)
    body = page_hero("How ASKODOX works", "One conversation, from a need to a result.", "How it works", '<a class="btn btn-primary" href="/join/">Get early access</a><a class="btn btn-ghost" href="/#journey">Watch an example</a>') + f"""
<section class="section zone-night"><div class="wrap">
  <h2 class="visually-hidden">Steps</h2>
  <ol class="flow" style="grid-template-columns:repeat(auto-fit,minmax(16rem,1fr))">{items}</ol>
</div></section>
<section class="section zone-day"><div class="wrap">
  <div class="section-head"><h2>The ASKODOX companion</h2><p>A calm, helpful presence in the app that listens, thinks and answers. It's there to advise, not to decorate. {fbadge(cfg, 'companion')}</p></div>
  {blocks([
      ("Listens", "Speak naturally. It understands everyday phrasing, not keywords.", fbadge(cfg, 'voice_ask')),
      ("Remembers the thread", "Answers a follow-up in the context of what you already said.", ""),
      ("Speaks back", "Replies can be read aloud, so you can keep your hands free.", ""),
  ])}
</div></section>
<section class="section zone-mist"><div class="wrap">
  <div class="section-head"><h2>What ASKODOX can help with</h2></div>
  {blocks([
      ("Products", "New, used, second-hand or surplus. Compare and find where to get them.", ""),
      ("Services", "Repairs, home services, tutors, events, transport and more.", ""),
      ("Selling and offering", "Turn what you sell or what you do into a listing or profile by chatting.", fbadge(cfg, 'listings')),
      ("Work and opportunities", "Find work that matches your skill, or people with the skill you need.", ""),
      ("Information and documents", "Plain explanations of documents, comparisons and how-tos.", fbadge(cfg, 'file_ask')),
      ("Support", "Get help with a request or a problem without leaving the conversation.", ""),
  ])}
</div></section>
""" + cta_band("Have a question?", "The FAQ covers the most common ones.", '<a class="btn btn-primary" href="/faq/">Read the FAQ</a><a class="btn btn-ghost" href="/contact/">Contact us</a>')
    return Page("/how-it-works/", "How it works", "See how ASKODOX turns a need into a result: ask in your own words, get understood, discover nearby and online options, decide and connect with consent.", body, crumb="How it works")


def discover(cfg: dict) -> Page:
    body = page_hero("Discover what you need", "Products, services, businesses, professionals, opportunities and information, nearby and online.", "Discover", '<a class="btn btn-primary" href="/join/">Get early access</a>') + f"""
<section class="section zone-day" id="products"><div class="wrap split">
  <div class="split-copy"><h2>Products</h2><p>Describe what you want and what matters: use, budget, brand, condition. ASKODOX checks nearby sellers and stores first, then online, and compares the options for you.</p>
  <ul class="ticks"><li><span>New, used, second-hand and surplus</span></li><li><span>Prices you can trust are shown as such; others are marked unverified</span></li><li><span>Videos and reviews alongside when they help</span></li></ul></div>
  <div class="note"><strong>Try asking:</strong> “A quiet washing machine for a small flat, under €400” or “Where can I buy fresh fish near me today?”</div>
</div></section>
<section class="section zone-mist" id="services"><div class="wrap split">
  <div class="split-copy"><h2>Services and professionals</h2><p>Plumbers, electricians, tutors, caterers, photographers, mechanics, drivers, lawyers and more. ASKODOX asks what it needs to, then finds people nearby who do exactly that.</p>
  <ul class="ticks"><li><span>Send a request to the providers you choose</span></li><li><span>Your number stays private until they accept</span></li><li><span>Follow replies in one place</span></li></ul></div>
  <div class="note"><strong>Try asking:</strong> “Someone to fix a ceiling fan tomorrow morning” or “A wedding photographer for 2 March”</div>
</div></section>
<section class="section zone-day" id="nearby"><div class="wrap split">
  <div class="split-copy"><h2>Nearby {fbadge(cfg, 'nearby')}</h2><p>{e(cfg['feature']['nearby']['note'])}</p></div>
  <div class="discover-visual" role="img" aria-label="Map showing options around you">{map_svg()}<div class="dv-card"><span class="dv-tag near">Nearby</span><b>Options around you</b><small>Closest first</small></div></div>
</div></section>
<section class="section zone-mist" id="online"><div class="wrap split">
  <div class="split-copy"><h2>Online {fbadge(cfg, 'online')}</h2><p>When the best option is online, ASKODOX shows relevant results from the web and explains why they fit. Partner links, if any, are always labelled.</p></div>
  <div class="note">Online results come from public web sources. Always check the final price and seller before you pay.</div>
</div></section>
<section class="section zone-day"><div class="wrap">
  <div class="section-head"><h2>Opportunities and information</h2></div>
  {blocks([
      ("Work", "Find work that matches your skill, or the right person for a job.", ""),
      ("Used and surplus", "Find second-hand items, or sell what you no longer need.", ""),
      ("Answers", "Plain explanations, comparisons and how-tos, with sources where it matters.", ""),
  ])}
</div></section>
""" + cta_band("Have something to offer?", "Sellers and service providers can reach people who are already asking.", '<a class="btn btn-primary" href="/sellers/">For sellers</a><a class="btn btn-ghost" href="/service-providers/">For service providers</a>')
    return Page("/discover/", "Discover products and services", "Discover products, services, businesses, professionals, opportunities and information with ASKODOX, nearby first and online when it's better.", body, crumb="Discover")


def sellers(cfg: dict) -> Page:
    body = page_hero("Sell to people who are already asking", "Whether you run a shop or want to sell one thing, ASKODOX puts you in front of people nearby who need what you have.", "For sellers", '<a class="btn btn-primary" href="/join/#seller">Start selling</a><a class="btn btn-ghost" href="/contact/">Talk to us</a>') + f"""
<section class="section zone-day"><div class="wrap">
  <div class="section-head"><h2>How selling works</h2></div>
  {blocks([
      ("List by chatting", "Tell ASKODOX what you sell, with a photo if you like. It drafts the listing for you.", fbadge(cfg, 'listings')),
      ("Get relevant requests", "When someone nearby asks for what you sell, their request reaches you.", fbadge(cfg, 'requests')),
      ("Accept and connect", "You choose which requests to accept. Contact is shared after you accept.", fbadge(cfg, 'consent_connect')),
      ("Shops and businesses", "List your range and be found when people nearby ask for it.", ""),
      ("Selling one thing", "Snap a photo, say the price, and nearby buyers can find it.", ""),
      ("Offers", "Run offers that are shown only when they're relevant to the request.", fbadge(cfg, 'offers')),
  ])}
</div></section>
<section class="section zone-mist"><div class="wrap prose">
  <h2>What sellers should know</h2>
  <ul>
    <li>Buyers pay you directly. Payments inside ASKODOX aren't available yet.</li>
    <li>You're responsible for your listings being accurate and lawful. See the <a href="/terms/">Terms</a>.</li>
    <li>Listing on ASKODOX is free during the beta. If that ever changes, we'll tell you clearly and in advance.</li>
  </ul>
</div></section>
""" + cta_band("Ready to sell?", "Ask for early access to the Android beta, or tell us about your business.", '<a class="btn btn-primary" href="/join/#seller">Start selling</a><a class="btn btn-ghost" href="/partners/">Partner with us</a>')
    return Page("/sellers/", "For sellers", "Sell on ASKODOX: list products by chatting, receive relevant requests from people nearby and connect directly with buyers once you accept.", body, crumb="For sellers")


def providers(cfg: dict) -> Page:
    body = page_hero("Get requests from people who need your skill", "Tradespeople, professionals, freelancers and small teams: tell ASKODOX what you do, and relevant requests come to you.", "For service providers", '<a class="btn btn-primary" href="/join/#provider">Offer your service</a>') + f"""
<section class="section zone-day"><div class="wrap">
  <div class="section-head"><h2>How it works for providers</h2></div>
  {blocks([
      ("Describe what you do", "Your service, area, availability and a few photos of past work.", fbadge(cfg, 'listings')),
      ("Receive requests", "When someone nearby needs exactly that, you see the request with the details.", fbadge(cfg, 'requests')),
      ("Accept the ones you want", "Contact details are shared only after you accept.", fbadge(cfg, 'consent_connect')),
      ("Freelancers and professionals", "Designers, tutors, photographers, consultants and more.", ""),
      ("Home and local services", "Repairs, cleaning, events, transport and more.", ""),
      ("Grow repeat business", "Direct connections help customers come back to you.", ""),
  ])}
</div></section>
<section class="section zone-mist"><div class="wrap prose">
  <h2>Good to know</h2>
  <ul>
    <li>Customers pay you directly for your work.</li>
    <li>Only accept requests you can deliver. Customers can report problems to us.</li>
    <li>Free during the beta. If that changes, we'll tell you clearly and in advance.</li>
  </ul>
</div></section>
""" + cta_band("Know a great provider?", "Refer them and we'll get in touch.", '<a class="btn btn-primary" href="/join/#refer">Refer a provider</a>')
    return Page("/service-providers/", "For service providers", "Offer your service on ASKODOX: describe what you do, receive relevant requests from people nearby and connect directly once you accept.", body, crumb="For service providers")


def deals(cfg: dict) -> Page:
    active = [l for l in cfg["links"] if l.get("status") == "active" and l.get("approved") and l.get("url")]
    partner_html = ("".join(f'<li><a href="/go/{e(l["slug"])}" rel="sponsored nofollow noopener">{e(l["partner"])}</a> <span class="muted">({e(l["programme"])}, affiliate link)</span></li>' for l in active)
                    if active else "<p>No partner or affiliate programmes are active yet. When one is approved, its offers will appear here and in answers, always labelled.</p>")
    body = page_hero("Deals and offers", "Offers that fit what you're actually looking for, with the conditions explained.", "Deals and offers") + f"""
<section class="section-tight zone-day"><div class="wrap"><p class="disclosure-strip">Some links on ASKODOX may be partner or affiliate links. They're always labelled and never decide which option we recommend. <a href="/affiliate-disclosure/">Affiliate disclosure</a></p></div></section>
<section class="section zone-day"><div class="wrap">
  <h2 class="visually-hidden">What is available</h2>
  {blocks([
      ("Offers in answers", "When an offer applies to your request, it shows up in the answer, with its conditions.", fbadge(cfg, 'offers')),
      ("Partner deals", "Deals from approved partners and programmes around the world.", fbadge(cfg, 'partner_deals')),
      ("Coupon codes", "Codes you can apply with participating sellers.", fbadge(cfg, 'coupons')),
  ])}
</div></section>
<section class="section zone-mist"><div class="wrap prose">
  <h2>Partner programmes</h2>
  {partner_html}
  <h2>For sellers and brands</h2>
  <p>Want to offer a deal to people asking for what you sell? Write to {mail(cfg, 'partners_email')}.</p>
</div></section>
"""
    return Page("/deals/", "Deals and offers", "Find deals and offers on ASKODOX that fit what you're looking for, with conditions explained and partner links always labelled.", body, crumb="Deals and offers")


def videos(cfg: dict) -> Page:
    body = page_hero("Videos and reviews", "See how things work, what reviewers think and what owners wish they'd known, right inside your answer.", "Videos and reviews") + f"""
<section class="section zone-day"><div class="wrap">
  <h2 class="visually-hidden">What is available</h2>
  {blocks([
      ("Helpful videos in answers", "Relevant explainers, how-tos and reviews shown when you're deciding.", fbadge(cfg, 'video_results')),
      ("Product and service videos", "Sellers and providers showing what they offer.", badge('soon')),
      ("Review summaries", "What reviewers agree and disagree on, in a few lines.", badge('soon')),
  ])}
</div></section>
<section class="section zone-mist" id="creators"><div class="wrap split">
  <div class="split-copy"><h2>For creators {fbadge(cfg, 'creators')}</h2><p>If you make honest, useful videos about products, services or skills, ASKODOX can put them in front of people at the moment they're deciding. A creator programme is being prepared.</p>
  <div class="btn-row" style="margin-top:1.5rem"><a class="btn btn-primary" href="mailto:{e(cfg['contact']['partners_email'])}?subject=ASKODOX%20creator%20programme">Tell us you're interested</a></div></div>
  <div class="note">We won't list creators, channels or partnerships here until they've actually joined.</div>
</div></section>
"""
    return Page("/videos/", "Videos and reviews", "ASKODOX shows helpful videos and reviews when you're deciding, and is preparing a creator programme for honest, useful video makers.", body, crumb="Videos and reviews")


def support(cfg: dict) -> Page:
    wa = cfg["contact"]["whatsapp_digits"]
    wa_html = (f'<a href="https://wa.me/{e(wa)}" rel="noopener">Message us on WhatsApp</a>' if wa else "Coming soon. We'll add the official number here.")
    body = page_hero("Help center", "Find answers, contact the team or report a problem.", "Help center") + f"""
<section class="section zone-day"><div class="wrap contact-grid">
  <div>
    <h2 style="font-size:var(--ax-step-3);margin-bottom:1rem">How can we help?</h2>
    <div class="channels">
      <div class="channel">{icon('help')}<div><h3>FAQ</h3><p>Quick answers about using ASKODOX, selling, privacy and the app.</p><p><a href="/faq/">Read the FAQ</a></p></div></div>
      <div class="channel">{icon('mail')}<div><h3>Email support {fbadge(cfg, 'email_support')}</h3><p>Write to us about anything. A person reads every message.</p><p>{mail(cfg)}</p></div></div>
      <div class="channel">{icon('chat')}<div><h3>WhatsApp support {fbadge(cfg, 'whatsapp_support')}</h3><p>{wa_html}</p></div></div>
      <div class="channel">{icon('flag')}<div><h3>Report a problem</h3><p>Something not working, or someone not behaving well? Tell us.</p><p><a href="/report-a-problem/">Report a problem</a></p></div></div>
      <div class="channel">{icon('shield')}<div><h3>Privacy and your data</h3><p>Download or delete your data, or ask a privacy question.</p><p><a href="/privacy/#your-rights">Your rights</a></p></div></div>
    </div>
  </div>
  <div>
    <h2 style="font-size:var(--ax-step-3);margin-bottom:1rem">Popular topics</h2>
    <div class="faq">{faq_html(FAQ[:1] + FAQ[1:2], limit=6)}</div>
    <p style="margin-top:1.5rem"><a href="/faq/">All questions</a></p>
  </div>
</div></section>
<section class="section-tight zone-mist"><div class="wrap prose"><p><strong>In the app:</strong> you can also ask ASKODOX for help in the conversation. If it can't solve the problem, it passes your case to our team with the context, so you don't have to repeat yourself.</p></div></section>
"""
    return Page("/support/", "Help center", "Get help with ASKODOX: FAQ, email support, WhatsApp support, reporting a problem and privacy requests.", body, crumb="Help center")


FAQ = [
    ("Using ASKODOX", [
        ("What is ASKODOX?", "<p>ASKODOX is an AI-powered everyday platform. You say what you need and it helps you understand your options, discover nearby and online choices, decide and connect with the right person.</p>"),
        ("Is ASKODOX only for shopping?", "<p>No. You can find services and professionals, sell something, offer your skills, find work, understand a document, compare options or simply ask a question.</p>"),
        ("How do I start?", "<p>The ASKODOX Android app is in beta. <a href='/join/'>Ask for early access</a>. Asking from this website is coming soon.</p>"),
        ("Which languages does it support?", "<p>The app works in English and Telugu today. More languages are planned. This website is in English for now.</p>"),
        ("Which countries does it work in?", "<p>ASKODOX is designed for any country. Nearby discovery is currently tuned for India first, and more countries are planned. Online answers work anywhere.</p>"),
        ("Does it cost anything?", "<p>Using ASKODOX is free during the beta. You pay sellers and providers directly for what you buy or book.</p>"),
    ]),
    ("Selling and offering services", [
        ("How do I list something?", "<p>In the app, tell ASKODOX what you're selling or offering. It drafts the listing or profile, and you confirm it.</p>"),
        ("Who sees my phone number?", "<p>Only the person whose request you accept, or the seller who accepts yours. Before that, they see the request and your general area only.</p>"),
        ("How do I get paid?", "<p>Customers pay you directly. Payments inside ASKODOX are not available yet.</p>"),
    ]),
    ("Privacy and safety", [
        ("Does ASKODOX track my location?", "<p>Only when you allow it, and only while you're using the app. Others see your area, never your exact location.</p>"),
        ("How do I delete my account or data?", "<p>In the Android app, open the Privacy screen to download or delete your data. You can also email <a href='mailto:{privacy}'>{privacy}</a>.</p>"),
        ("Are recommendations paid for?", "<p>No. Partner or affiliate relationships don't decide what ASKODOX recommends, and any partner link is labelled. See the <a href='/affiliate-disclosure/'>affiliate disclosure</a>.</p>"),
        ("How do I report someone?", "<p>Use <a href='/report-a-problem/'>Report a problem</a> or email us. Include what happened and when.</p>"),
    ]),
]


def faq_html(groups, limit: int | None = None, cfg: dict | None = None) -> str:
    out, n = [], 0
    for _, items in groups:
        for q, a in items:
            if limit is not None and n >= limit:
                break
            out.append(f"<details><summary>{e(q)}</summary><div>{a}</div></details>")
            n += 1
    return "".join(out)


def faq(cfg: dict) -> Page:
    privacy = cfg["contact"]["privacy_email"]
    groups = [(g, [(q, a.replace("{privacy}", e(privacy))) for q, a in items]) for g, items in FAQ]
    html_groups = "".join(f'<div class="faq-group"><h2>{e(g)}</h2>{faq_html([(g, items)])}</div>' for g, items in groups)
    import re as _re
    ld = {"@context": "https://schema.org", "@type": "FAQPage", "mainEntity": [
        {"@type": "Question", "name": q, "acceptedAnswer": {"@type": "Answer", "text": _re.sub(r"<[^>]+>", "", a)}} for _, items in groups for q, a in items]}
    body = page_hero("Frequently asked questions", "Quick answers about using ASKODOX.", "FAQ") + f"""
<section class="section zone-day"><div class="wrap faq">{html_groups}
<p style="margin-top:3rem">Didn't find your answer? Write to {mail(cfg)}.</p></div></section>"""
    return Page("/faq/", "FAQ", "Answers to common questions about ASKODOX: how it works, languages and countries, selling, privacy, safety and cost.", body, crumb="FAQ", jsonld=[ld])


def contact(cfg: dict) -> Page:
    c = cfg["contact"]
    wa = c["whatsapp_digits"]
    body = page_hero("Contact us", "We read every message.", "Contact us") + f"""
<section class="section zone-day"><div class="wrap contact-grid">
  <div class="channels"><h2 class="visually-hidden">Ways to reach us</h2>
    <div class="channel">{icon('mail')}<div><h3>General</h3><p>{mail(cfg, 'general_email')}</p></div></div>
    <div class="channel">{icon('help')}<div><h3>Support</h3><p>{mail(cfg, 'support_email')}</p></div></div>
    <div class="channel">{icon('store')}<div><h3>Partners and business</h3><p>{mail(cfg, 'partners_email')}</p></div></div>
    <div class="channel">{icon('shield')}<div><h3>Privacy</h3><p>{mail(cfg, 'privacy_email')}</p></div></div>
    <div class="channel">{icon('chat')}<div><h3>WhatsApp {fbadge(cfg, 'whatsapp_support')}</h3><p>{f'<a href="https://wa.me/{e(wa)}" rel="noopener">Message us</a>' if wa else 'Coming soon.'}</p></div></div>
  </div>
  <div>
    <h2 style="font-size:var(--ax-step-3);margin-bottom:.5rem">Send a message</h2>
    <p class="muted" style="margin-bottom:1.5rem">This opens your email app with your message ready to send.</p>
    <form class="form" data-compose="contact" data-subject="ASKODOX contact" data-to="{e(c['general_email'])}" novalidate>
      <div class="row"><label>Your name<input name="name" autocomplete="name" required></label><label>Your email<input name="email" type="email" autocomplete="email" required></label></div>
      <label>Topic<select name="topic"><option>General question</option><option>Support</option><option>Selling or offering a service</option><option>Partnership</option><option>Creator programme</option><option>Press</option><option>Privacy</option></select></label>
      <label>Country <span class="opt">(optional)</span><input name="country" autocomplete="country-name"></label>
      <label>Message<textarea name="message" required></textarea></label>
      <button class="btn btn-primary" type="submit">Write email</button>
      <div class="form-result" role="status"></div>
    </form>
  </div>
</div></section>"""
    return Page("/contact/", "Contact us", f"Contact ASKODOX by email at {c['general_email']} for questions, support, partnerships and privacy requests.", body, crumb="Contact us")


def report(cfg: dict) -> Page:
    body = page_hero("Report a problem", "Something broken, wrong or unsafe? Tell us and we'll look into it.", "Report a problem") + f"""
<section class="section zone-day"><div class="wrap contact-grid">
  <div class="prose">
    <h2 style="margin-top:0">What to include</h2>
    <ul><li>What happened and when</li><li>The phone number or email on your ASKODOX account, if you have one</li><li>Screenshots, if you can (attach them in your email app)</li></ul>
    <div class="note"><strong>If anyone is in danger, contact your local emergency services first.</strong> ASKODOX can't respond to emergencies.</div>
  </div>
  <form class="form" data-compose="report" data-subject="ASKODOX problem report" data-to="{e(cfg['contact']['support_email'])}" novalidate>
    <label>What kind of problem?<select name="topic"><option>Something isn't working</option><option>Wrong or misleading information</option><option>A seller or provider</option><option>A buyer or customer</option><option>Safety concern</option><option>Privacy concern</option><option>Something else</option></select></label>
    <div class="row"><label>Your email<input name="email" type="email" autocomplete="email" required></label><label>When did it happen?<input name="when" placeholder="Date and time"></label></div>
    <label>Device <span class="opt">(optional)</span><input name="device" placeholder="e.g. Android phone, website"></label>
    <label>What happened?<textarea name="details" required></textarea></label>
    <button class="btn btn-primary" type="submit">Write report</button>
    <p class="form-note">Opens your email app with the report ready to send to {e(cfg['contact']['support_email'])}.</p>
    <div class="form-result" role="status"></div>
  </form>
</div></section>"""
    return Page("/report-a-problem/", "Report a problem", "Report a bug, misleading information, a safety concern or a problem with a seller, provider or customer on ASKODOX.", body, crumb="Report a problem")


def join(cfg: dict) -> Page:
    paths = [
        ("buyer", "Join as a buyer", "Ask for anything, compare options and connect with the right people.", "Buyer"),
        ("seller", "Join as a seller", "Shops, businesses and people selling one thing.", "Seller"),
        ("provider", "Join as a service provider", "Tradespeople, professionals and freelancers.", "Service provider"),
        ("creator", "Join as a creator", "Make useful videos and reviews? Register your interest.", "Creator"),
    ]
    cards = "".join(f'<div class="channel" id="{k}"><div><h3>{e(t)}</h3><p>{e(d)}</p></div></div>' for k, t, d, _ in paths)
    options = "".join(f"<option>{e(r)}</option>" for *_, r in paths) + "<option>Business or partner</option><option>Survey participant</option><option>Just curious</option>"
    body = page_hero("Join ASKODOX", "The Android app is in beta. Tell us who you are and we'll send you early access as places open up.", "Join") + f"""
<section class="section zone-day"><div class="wrap contact-grid">
  <div>
    <h2 class="visually-hidden">Ways to join</h2>
    <div class="channels">{cards}</div>
    <p class="muted" style="margin-top:1rem">You can choose more than one. Most people do.</p>
  </div>
  <div>
    <h2 style="font-size:var(--ax-step-3);margin-bottom:.5rem">Request early access</h2>
    <p class="muted" style="margin-bottom:1.5rem">This opens your email app with your request ready to send.</p>
    <form class="form" data-compose="join" data-subject="ASKODOX early access" data-to="{e(cfg['contact']['general_email'])}" novalidate>
      <div class="row"><label>Your name<input name="name" autocomplete="name" required></label><label>Your email<input name="email" type="email" autocomplete="email" required></label></div>
      <label>I'd like to join as<select name="topic">{options}</select></label>
      <div class="row"><label>City<input name="city" autocomplete="address-level2"></label><label>Country<input name="country" autocomplete="country-name"></label></div>
      <label>Phone type <span class="opt">(optional)</span><select name="phone"><option>Android</option><option>iPhone</option><option>Other</option></select></label>
      <label>Anything else? <span class="opt">(optional)</span><textarea name="notes" placeholder="What you sell, what service you offer, or what you'd use ASKODOX for"></textarea></label>
      <button class="btn btn-primary" type="submit">Write request</button>
      <div class="form-result" role="status"></div>
    </form>
  </div>
</div></section>
<section class="section zone-mist" id="refer"><div class="wrap contact-grid">
  <div class="prose"><h2 style="margin-top:0">Refer a business or provider {fbadge(cfg, 'referrals')}</h2><p>Know a great shop, tradesperson or professional who should be on ASKODOX? Tell us about them. We'll only contact them about joining, and we'll mention that you referred them if you'd like.</p></div>
  <form class="form" data-compose="refer" data-subject="ASKODOX referral" data-to="{e(cfg['contact']['partners_email'])}" novalidate>
    <div class="row"><label>Business or person<input name="business" required></label><label>What they offer<input name="offer" required></label></div>
    <div class="row"><label>City and country<input name="location"></label><label>Their phone or email <span class="opt">(optional)</span><input name="their_contact"></label></div>
    <label>Your email<input name="your_email" type="email" required></label>
    <label style="display:flex;gap:.6rem;align-items:center;font-weight:400"><input type="checkbox" name="they_agreed" style="min-height:auto;width:20px;height:20px;margin:0;display:inline-block"> They're happy for me to share their details</label>
    <button class="btn btn-primary" type="submit">Write referral</button>
    <div class="form-result" role="status"></div>
  </form>
</div></section>"""
    return Page("/join/", "Join ASKODOX", "Join ASKODOX as a buyer, seller, service provider or creator, request early access to the Android beta, or refer a business.", body, crumb="Join")


def app_page(cfg: dict) -> Page:
    body = page_hero("The ASKODOX app", "The full ASKODOX experience: the companion, voice, photos, nearby discovery, requests and updates.", "The app") + f"""
<section class="section zone-night"><div class="wrap app-band">
  <div>
    <div class="section-head" style="margin-bottom:1.5rem"><h2>Get the app</h2><p>Android {fbadge(cfg, 'android_app')} &nbsp; iPhone {fbadge(cfg, 'ios_app')}</p></div>
    {store_buttons(cfg)}
    <p class="muted" style="margin-top:1rem">The Android app is in beta and not yet on Google Play. <a href="/join/">Ask for early access</a>.</p>
  </div>
  {phone_static()}
</div></section>
<section class="section zone-day"><div class="wrap">
  <div class="section-head"><h2>In the app</h2></div>
  {blocks([
      ("Ask by text, voice, photo or file", "In one conversation.", fbadge(cfg, 'voice_ask')),
      ("The ASKODOX companion", "Listens, thinks and answers.", fbadge(cfg, 'companion')),
      ("Nearby and online discovery", "Closest options first.", fbadge(cfg, 'nearby')),
      ("Requests and updates", "Follow replies in one place.", fbadge(cfg, 'requests')),
      ("Privacy controls", "Download or delete your data.", fbadge(cfg, 'privacy_tools')),
      ("Ask from the web", "Ask ASKODOX in your browser.", fbadge(cfg, 'web_chat')),
  ])}
</div></section>"""
    return Page("/app/", "The ASKODOX app", "The ASKODOX app for Android (beta) and iPhone (coming soon): ask by voice, text, photo or file, discover nearby and connect.", body, crumb="The app")


def partners(cfg: dict) -> Page:
    body = page_hero("Partner with ASKODOX", "For brands, businesses, affiliate networks, platforms and service companies who want to reach people at the moment they're deciding.", "Partners", f'<a class="btn btn-primary" href="mailto:{e(cfg["contact"]["partners_email"])}?subject=ASKODOX%20partnership">Start a conversation</a>') + f"""
<section class="section zone-day"><div class="wrap">
  <div class="section-head"><h2>Ways to work together</h2><p>ASKODOX is designed to connect with partners worldwide. Nothing below is presented as active until an agreement is in place.</p></div>
  {blocks([
      ("Affiliate and commerce programmes", "Approved programmes can be shown in answers, always disclosed.", fbadge(cfg, 'partner_deals')),
      ("Business onboarding", "Bring your catalogue or service network onto ASKODOX.", ""),
      ("Offers and rewards", "Run relevant offers for people asking for what you sell.", fbadge(cfg, 'offers')),
      ("Video and creator platforms", "Help people decide with useful video content.", fbadge(cfg, 'creators')),
      ("Maps, messaging and payments", "Integrations that help people act on a decision.", badge('soon')),
      ("Partner APIs", "Structured integrations for larger partners.", badge('soon')),
  ])}
</div></section>
<section class="section zone-mist"><div class="wrap prose">
  <h2>Our commitments to users come first</h2>
  <ul><li>Partner relationships never decide what we recommend.</li><li>Every partner or affiliate link is labelled.</li><li>We never share users' contact details without their consent.</li></ul>
  <p>Write to {mail(cfg, 'partners_email')}.</p>
</div></section>"""
    return Page("/partners/", "Partners", "Partner with ASKODOX: affiliate and commerce programmes, business onboarding, offers, creator platforms and integrations, with users' trust first.", body, crumb="Partners")


def trust(cfg: dict) -> Page:
    body = page_hero("Trust and safety", "How ASKODOX protects your privacy, keeps connections consensual and stays honest with you.", "Trust and safety") + f"""
<section class="section zone-day"><div class="wrap">
  <h2 class="visually-hidden">Our commitments</h2>
  <ul class="trust">
    <li><h3>Consent before contact</h3><p>Phone numbers are shared only after a request is accepted. Until then, others see the request and your general area. {fbadge(cfg, 'consent_connect')}</p></li>
    <li><h3>Location on your terms</h3><p>Location is used only when you allow it, and others never see your exact location.</p></li>
    <li><h3>Sign-in you can trust</h3><p>Accounts are verified with a one-time code sent to your phone.</p></li>
    <li><h3>Your data, your choice</h3><p>Download or delete your data in the app's Privacy screen. {fbadge(cfg, 'privacy_tools')}</p></li>
    <li><h3>Honest labels</h3><p>Unverified prices are labelled, partner links are disclosed and features show Live, Beta or Coming soon.</p></li>
    <li><h3>A person to talk to</h3><p>Report a problem and our team will look into it.</p></li>
  </ul>
</div></section>
<section class="section zone-mist"><div class="wrap prose">
  <h2>Staying safe when you meet or pay someone</h2>
  <ul><li>Meet in a public place when buying or selling in person.</li><li>Check an item or the work before you pay.</li><li>Never share one-time codes or passwords with anyone, including people claiming to be from ASKODOX.</li><li>If something feels wrong, stop and <a href="/report-a-problem/">report it</a>.</li></ul>
  <h2>Security issues</h2>
  <p>If you've found a security vulnerability, please email {mail(cfg, 'general_email')} with the details. Please don't access other people's data while testing.</p>
</div></section>"""
    return Page("/trust/", "Trust and safety", "How ASKODOX protects privacy, keeps connections consent-based, labels partner links and helps you stay safe.", body, crumb="Trust and safety")


def status(cfg: dict) -> Page:
    groups: dict[str, list] = {}
    for f in cfg["features"]:
        groups.setdefault(f["group"], []).append(f)
    tables = "".join(
        f'<table class="status-table"><caption>{e(g)}</caption><thead><tr><th scope="col">Feature</th><th scope="col">Status</th><th scope="col">Notes</th></tr></thead><tbody>'
        + "".join(f'<tr><th scope="row">{e(f["name"])}</th><td>{badge(f["status"])}</td><td class="n">{e(f["note"])}</td></tr>' for f in items)
        + "</tbody></table>"
        for g, items in groups.items()
    )
    body = page_hero("What's live", "Exactly what you can use today, what's in testing and what's coming.", "What's live") + f"""
<section class="section zone-day"><div class="wrap">
  <h2 class="visually-hidden">What the labels mean</h2>
  <div class="blocks" style="margin-bottom:2rem">
    <div><h3>{badge('live')}</h3><p>Available to everyone now.</p></div>
    <div><h3>{badge('beta')}</h3><p>Working, and being tested with early users. May change.</p></div>
    <div><h3>{badge('soon')}</h3><p>Planned. Not available yet.</p></div>
  </div>
  {tables}
</div></section>"""
    return Page("/status/", "What's live", "See which ASKODOX features are live, in beta or coming soon.", body, crumb="What's live")


def legal_page(path: str, title: str, desc: str, inner: str, cfg: dict) -> Page:
    body = page_hero(title, f"Effective {cfg['site']['policies_effective_date']}.", title) + f'<section class="section zone-day"><div class="wrap prose">{inner}</div></section>'
    return Page(path, title, desc, body, crumb=title, priority="0.3")


def privacy(cfg: dict) -> Page:
    p = cfg["contact"]["privacy_email"]
    name = e(cfg["site"]["legal_name"])
    addr = cfg["site"].get("legal_address")
    inner = f"""
<p class="lead">This policy explains what information ASKODOX collects, why, who it's shared with and the choices you have. It covers the askodox.com website and the ASKODOX app.</p>
<h2>Who we are</h2>
<p>ASKODOX is operated by {name}{', ' + e(addr) if addr else ''}. For any privacy question or request, email <a href="mailto:{e(p)}">{e(p)}</a>.</p>
<h2>Information we collect</h2>
<h3>On this website</h3>
<ul>
<li><strong>Server logs.</strong> Like most websites, our hosting provider records technical information such as IP address, browser type, pages requested and time, to keep the site secure and working.</li>
<li><strong>What you send us.</strong> If you email us, including through the forms on this site (which open your own email app), we receive what you write and your email address.</li>
<li>This website does not use advertising cookies or third-party analytics. See the <a href="/cookies/">Cookie policy</a>.</li>
</ul>
<h3>In the ASKODOX app</h3>
<ul>
<li><strong>Account.</strong> Your phone number, used to sign in with a one-time code, and any name or profile details you add.</li>
<li><strong>Your conversations.</strong> What you type or say to ASKODOX, and photos or files you choose to share, so it can understand and answer your request.</li>
<li><strong>Location.</strong> Your device location only when you allow it, used to find nearby options. Others see your general area, never your exact location.</li>
<li><strong>Listings, requests and orders.</strong> What you list, the requests you send or receive, and their status.</li>
<li><strong>Device and notifications.</strong> Basic device information and, if you allow notifications, a notification token.</li>
</ul>
<h2>How we use it</h2>
<ul>
<li>To understand your requests and find relevant options, people and information.</li>
<li>To send requests to sellers or providers you choose, and share contact details only after a request is accepted.</li>
<li>To keep ASKODOX secure, prevent abuse and fix problems.</li>
<li>To provide support and respond to you.</li>
<li>To improve ASKODOX.</li>
</ul>
<p>We don't sell your personal information.</p>
<h2>Who we share it with</h2>
<ul>
<li><strong>Other users</strong>, only as described above: a request and your general area before acceptance, and contact details after acceptance.</li>
<li><strong>Service providers</strong> that run parts of ASKODOX for us, such as cloud hosting, AI language and speech processing, web search, maps and places, and email. They process information only to provide their service to us.</li>
<li><strong>Authorities</strong>, when the law requires it.</li>
</ul>
<p>Some of these providers may process information in other countries. We use providers that protect information appropriately.</p>
<h2 id="your-rights">Your choices and rights</h2>
<ul>
<li><strong>Access and download</strong> your data from the Privacy screen in the app, or by email.</li>
<li><strong>Delete</strong> your account and data from the app, or by email. Records of orders you made with another person may remain on their side.</li>
<li><strong>Location and notifications</strong> can be turned off at any time in your phone's settings.</li>
<li>Depending on where you live, you may have further rights, such as correcting your data or objecting to some uses. Email <a href="mailto:{e(p)}">{e(p)}</a> and we'll respond.</li>
</ul>
<h2>How long we keep it</h2>
<p>We keep information while your account is active and as long as needed for the purposes above. When you delete your account, we delete or anonymise your information unless we need to keep some of it to meet legal obligations or resolve disputes.</p>
<h2>Children</h2>
<p>ASKODOX is not intended for children under 13, or under the minimum age required where you live.</p>
<h2>Security</h2>
<p>We use reasonable technical and organisational measures to protect your information. No system is perfectly secure, so please keep your phone and one-time codes safe.</p>
<h2>Changes</h2>
<p>We'll update this page when our practices change and show the new effective date. For significant changes, we'll let you know in the app.</p>
"""
    return legal_page("/privacy/", "Privacy policy", "How ASKODOX collects, uses and protects your information, and the choices and rights you have.", inner, cfg)


def terms(cfg: dict) -> Page:
    name = e(cfg["site"]["legal_name"])
    inner = f"""
<p class="lead">These terms apply when you use the askodox.com website or the ASKODOX app. By using ASKODOX you agree to them.</p>
<h2>What ASKODOX is</h2>
<p>ASKODOX helps people discover products, services, people and information, and connect with each other. Unless we clearly say otherwise, ASKODOX is not the seller or provider of the products and services you find, and is not a party to agreements between users.</p>
<h2>Beta features</h2>
<p>Features marked Beta are still being tested and may change, be interrupted or be removed. Features marked Coming soon are not available yet.</p>
<h2>Your account</h2>
<ul><li>Give accurate information and keep your phone and one-time codes secure.</li><li>You're responsible for activity on your account.</li><li>You must be old enough to use ASKODOX where you live.</li></ul>
<h2>Using ASKODOX responsibly</h2>
<p>You agree not to:</p>
<ul><li>List or request anything illegal, dangerous, counterfeit or prohibited where you are.</li><li>Mislead, harass, threaten or defraud anyone.</li><li>Misuse other people's contact details or use them for spam.</li><li>Interfere with, scrape or try to break ASKODOX or its security.</li></ul>
<p>We may remove content or suspend accounts that break these terms.</p>
<h2>Sellers and service providers</h2>
<p>If you list products or services, you're responsible for accurate descriptions, fair pricing, having the right to sell and delivering what you promise, and for complying with laws that apply to you, including tax and consumer law.</p>
<h2>Buyers and customers</h2>
<p>Check items and providers before you pay. Payment is made directly to the seller or provider unless ASKODOX clearly offers otherwise.</p>
<h2>AI answers</h2>
<p>ASKODOX uses AI to understand requests and suggest options. Answers can be incomplete or wrong. Prices from the web are marked unverified. ASKODOX does not give professional legal, medical or financial advice; consult a qualified professional for those.</p>
<h2>Third-party links and partners</h2>
<p>ASKODOX may show links to other websites and, once approved, partner or affiliate offers. We're not responsible for third-party sites. See the <a href="/affiliate-disclosure/">Affiliate disclosure</a>.</p>
<h2>Our content</h2>
<p>The ASKODOX name, logo, design and software belong to {name}. You keep ownership of what you post, and give us permission to use it to run and improve ASKODOX.</p>
<h2>Liability</h2>
<p>ASKODOX is provided "as is". To the extent the law allows, we're not liable for losses arising from dealings between users or from relying on AI answers. Nothing in these terms limits rights you have under consumer laws that can't be excluded.</p>
<h2>Changes and contact</h2>
<p>We may update these terms and will show the new effective date here. Questions: {mail(cfg, 'general_email')}.</p>
"""
    return legal_page("/terms/", "Terms and conditions", "The terms for using the ASKODOX website and app.", inner, cfg)


def cookies(cfg: dict) -> Page:
    inner = f"""
<p class="lead">This website does not use advertising cookies, tracking pixels or third-party analytics.</p>
<h2>What we store on your device</h2>
<p>askodox.com doesn't set cookies today. Fonts and code are served from our own domain. If we later store a preference on your device, such as your chosen language, it will be used only for that purpose.</p>
<h2>Server logs</h2>
<p>Our hosting provider keeps standard server logs for security and reliability. These aren't cookies. See the <a href="/privacy/">Privacy policy</a>.</p>
<h2>If this changes</h2>
<p>If we ever add analytics or other non-essential cookies, we'll update this page first and, where required, ask for your consent before setting them.</p>
<p>Questions: {mail(cfg, 'privacy_email')}.</p>
"""
    return legal_page("/cookies/", "Cookie policy", "askodox.com does not use advertising cookies or third-party analytics. Learn what is stored and how that could change.", inner, cfg)


def affiliate(cfg: dict) -> Page:
    active = [l for l in cfg["links"] if l.get("status") == "active" and l.get("approved") and l.get("url") and l.get("affiliate")]
    current = ("<ul>" + "".join(f"<li>{e(l['partner'])}: {e(l['programme'])}</li>" for l in active) + "</ul>") if active else "<p><strong>As of today, ASKODOX does not participate in any affiliate programme and has no active commercial partnerships.</strong> This page will list programmes as they're approved.</p>"
    amazon = "<p>When ASKODOX joins the Amazon Associates programme, this statement applies: <em>As an Amazon Associate, ASKODOX earns from qualifying purchases.</em></p>"
    inner = f"""
<p class="lead">ASKODOX may earn a commission when you buy through some links. Here's how that works and how we keep recommendations honest.</p>
<h2>Current programmes</h2>
{current}
<h2>How affiliate links work</h2>
<p>An affiliate link tells a store that you came from ASKODOX. If you buy something, the store may pay ASKODOX a commission. You don't pay more because of it.</p>
<h2>Our rules</h2>
<ul>
<li>Affiliate and partner links are always labelled where they appear.</li>
<li>They never decide which option ASKODOX recommends. Recommendations are based on what fits your request.</li>
<li>We show nearby and non-partner options alongside partner ones whenever they fit.</li>
<li>We never say we're a partner of a company unless we have an approved agreement.</li>
</ul>
<h2>Specific programmes</h2>
{amazon}
<p>Questions: {mail(cfg, 'partners_email')}.</p>
"""
    return legal_page("/affiliate-disclosure/", "Affiliate disclosure", "How affiliate and partner links work on ASKODOX, which programmes are active and how recommendations stay independent.", inner, cfg)


def accessibility(cfg: dict) -> Page:
    inner = f"""
<p class="lead">We want everyone to be able to use ASKODOX, whatever their abilities, device or connection.</p>
<h2>What we do</h2>
<ul><li>We aim to meet WCAG 2.2 level AA on this website.</li><li>A highly legible typeface, strong colour contrast and visible keyboard focus.</li><li>Everything works with a keyboard and screen reader, and without animation if you've asked your device to reduce motion.</li><li>Pages work on slow connections and small screens.</li><li>In the app, you can ask by voice and hear answers read aloud.</li></ul>
<h2>Known limitations</h2>
<p>The website is in English only for now. Translations are planned.</p>
<h2>Tell us</h2>
<p>If something is hard to use, email {mail(cfg, 'support_email')} and we'll fix it.</p>
"""
    return legal_page("/accessibility/", "Accessibility", "ASKODOX's commitment to accessibility and how to report a barrier.", inner, cfg)


def not_found(cfg: dict) -> Page:
    body = f"""<section class="not-found zone-deep"><div>
<askodox-companion state="thinking" aria-hidden="true"></askodox-companion>
<h1 style="font-size:var(--ax-step-4)">That page isn't here</h1>
<p class="muted" style="margin:1rem auto 2rem;max-width:30rem">The link may be old or mistyped. Try the home page, or ask us for help.</p>
<div class="btn-row" style="justify-content:center"><a class="btn btn-primary" href="/">Go to home</a><a class="btn btn-ghost" href="/support/">Help center</a></div>
</div></section>"""
    return Page("/404/", "Page not found", "This page could not be found.", body, in_sitemap=False)


def all_pages(cfg: dict) -> list[Page]:
    return [home(cfg), about(cfg), how_it_works(cfg), discover(cfg), sellers(cfg), providers(cfg), deals(cfg), videos(cfg),
            app_page(cfg), join(cfg), partners(cfg), support(cfg), faq(cfg), contact(cfg), report(cfg), trust(cfg), status(cfg),
            privacy(cfg), terms(cfg), cookies(cfg), affiliate(cfg), accessibility(cfg), not_found(cfg)]
