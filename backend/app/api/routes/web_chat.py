"""Customer WEB chat at /chat -- the same backend the app uses, no second
engine: /api/in-app/assistant (understand + reply), /deals/discover
(results + Universal Advisor questions, guest browsing), /api/advisor/next.
Browsing never needs sign-in; sending a request / contacting a seller stays
in the app (identity is required for that).
"""
from __future__ import annotations

from fastapi import APIRouter
from fastapi.responses import HTMLResponse

router = APIRouter(tags=["web-chat"])

PAGE = r'''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>ASKODOX Chat</title>
<style>
:root{--bg:#f6f7fb;--card:#fff;--ink:#14161f;--muted:#5d6475;--line:#e3e6ee;--brand:#5b3df5;--soft:#efeafe}
@media (prefers-color-scheme:dark){:root{--bg:#0f1117;--card:#181b24;--ink:#eef0f6;--muted:#9aa1b2;--line:#2a2f3c;--brand:#9c88ff;--soft:#24203b}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.45 system-ui,-apple-system,Segoe UI,Roboto,sans-serif}
header{position:sticky;top:0;background:var(--card);border-bottom:1px solid var(--line);padding:10px 16px;display:flex;gap:8px;align-items:center;flex-wrap:wrap;z-index:2}
header b{font-size:18px;margin-right:auto}header input,header select{padding:6px 8px;border:1px solid var(--line);border-radius:8px;background:var(--bg);color:var(--ink)}
main{max-width:860px;margin:0 auto;padding:12px 16px 120px}
.msg{margin:10px 0;display:flex}.msg.me{justify-content:flex-end}.bubble{max-width:85%;padding:10px 12px;border-radius:14px;background:var(--card);border:1px solid var(--line);white-space:pre-wrap}
.me .bubble{background:var(--brand);color:#fff;border-color:transparent}
.q{background:var(--soft);border-color:transparent}.chips{display:flex;flex-wrap:wrap;gap:6px;margin-top:8px}
.chip{border:1px solid var(--brand);color:var(--brand);background:transparent;border-radius:999px;padding:4px 10px;cursor:pointer}
.group{margin:12px 0}.group h3{font-size:13px;text-transform:uppercase;letter-spacing:.04em;color:var(--muted);margin:0 0 6px}
.rail{display:flex;gap:10px;overflow-x:auto;padding-bottom:4px}.card{min-width:220px;max-width:240px;background:var(--card);border:1px solid var(--line);border-radius:12px;padding:10px;flex:0 0 auto}
.card img{width:100%;height:120px;object-fit:cover;border-radius:8px;background:var(--line)}.card .t{font-weight:700;margin:6px 0 2px;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden}
.card .s{color:var(--muted);font-size:13px}.card a{color:var(--brand);font-weight:600;text-decoration:none}
.guide{border-left:3px solid var(--brand);padding:6px 10px;margin:8px 0;background:var(--card);border-radius:6px}
footer{position:fixed;bottom:0;left:0;right:0;background:var(--card);border-top:1px solid var(--line);padding:10px 16px}
form{max-width:860px;margin:0 auto;display:flex;gap:8px}form input{flex:1;padding:12px;border:1px solid var(--line);border-radius:12px;background:var(--bg);color:var(--ink);font-size:16px}
form button{padding:0 18px;border:0;border-radius:12px;background:var(--brand);color:#fff;font-weight:700}
.note{max-width:860px;margin:6px auto 0;color:var(--muted);font-size:12px}
</style></head><body>
<header><b>ASKODOX</b><input id="loc" placeholder="Your area (e.g. Vijayawada)" aria-label="Location">
<select id="lang" aria-label="Language"><option value="en">English</option><option value="te">తెలుగు</option><option value="hi">हिन्दी</option></select></header>
<main id="log" aria-live="polite"></main>
<footer><form id="f"><input id="m" autocomplete="off" placeholder="Ask for anything -- products, services, jobs, travel…" aria-label="Message"><button>Send</button></form>
<div class="note" id="disc">Results come from ASKODOX sellers, nearby places and the web. Prices and availability are shown as found -- confirm with the seller before paying. Some links may be affiliate or sponsored; they are labelled.</div></footer>
<script>
const $=s=>document.querySelector(s),log=$("#log");
const esc=s=>String(s??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
let S={history:[],deal:null};try{S=JSON.parse(sessionStorage.getItem("askodox.web")||"null")||S}catch(e){}
try{$("#loc").value=localStorage.getItem("askodox.loc")||"";$("#lang").value=localStorage.getItem("askodox.lang")||"en"}catch(e){}
$("#loc").onchange=()=>{try{localStorage.setItem("askodox.loc",$("#loc").value)}catch(e){}};$("#lang").onchange=()=>{try{localStorage.setItem("askodox.lang",$("#lang").value)}catch(e){}};
const save=()=>{try{sessionStorage.setItem("askodox.web",JSON.stringify(S))}catch(e){}};
function add(html,me,cls){const d=document.createElement("div");d.className="msg"+(me?" me":"");d.innerHTML='<div class="bubble '+(cls||"")+'">'+html+'</div>';log.appendChild(d);window.scrollTo(0,document.body.scrollHeight);return d}
async function post(path,body){const r=await fetch(path,{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify(body)});const t=await r.text();let d;try{d=JSON.parse(t)}catch(e){d={detail:t}}if(!r.ok)throw new Error(d.detail||r.status);return d}
const ANY=["any","anything","no preference","doesn't matter","ఏదైనా","పర్వాలేదు","कोई भी"];
async function send(text){add(esc(text),true);S.history.push({role:"user",text});
  // Answer to the advisor's pending question -> fill that field, re-run discovery.
  if(S.deal&&S.deal.pending){const f=S.deal.pending;const df=S.deal.dynamic_fields;
    if(ANY.includes(text.trim().toLowerCase())){df.no_preference=[...(df.no_preference||[]),f]}else{df[f]=text}
    df.advisor_asked=[...(df.advisor_asked||[]),f];S.deal.pending=null;save();return discover(text)}
  const wait=add("…");
  try{const d=await post("/api/in-app/assistant",{message:text,locale:$("#lang").value,history:S.history.slice(-12),location:$("#loc").value});
    wait.remove();if(d.reply){add(esc(d.reply));S.history.push({role:"assistant",text:d.reply})}
    if(d.transactional||!d.reply){const e=d.entities||{};S.deal={subject:e.subject||e.item||e.product||e.service||text,category:d.domain||"",raw:text,dynamic_fields:{},pending:null};save();await discover(text)}
    else save()}catch(e){wait.remove();add("Sorry, something went wrong: "+esc(e.message))}}
async function discover(said){const dl=S.deal;const wait=add("Looking…");
  try{const body={user_id:"",raw_text:dl.raw,subject:dl.subject,category:dl.category,dynamic_fields:dl.dynamic_fields,
      trace:{query:said,language:$("#lang").value,platform:"web"}};if($("#loc").value)body.location={label:$("#loc").value};
    const d=await post("/deals/discover",body);wait.remove();const adv=d.advisor||{};
    (adv.guidance||[]).forEach(g=>add('<div class="guide"><b>'+esc(g.title)+'</b><br>'+esc(g.advice)+'</div>'));
    const q=(adv.questions||[])[0];
    if(q&&!adv.ready){dl.pending=q.field;save();ask(q);return}
    renderResults(d);if(q){dl.pending=q.field;save();ask(q,true)}}catch(e){wait.remove();add("Could not load results: "+esc(e.message))}}
function ask(q,optional){const d=add(esc(q.question)+(optional?' <span style="opacity:.7">(optional)</span>':''),false,"q");
  const chips=(q.choices||[]).concat(["Any"]);d.firstChild.insertAdjacentHTML("beforeend",'<div class="chips">'+chips.map(c=>'<button class="chip">'+esc(c)+'</button>').join("")+'</div>');
  d.querySelectorAll(".chip").forEach(b=>b.onclick=()=>send(b.textContent))}
const LABEL={local:"ASKODOX sellers near you",nearby:"Nearby places",online:"Online",marketplace:"Marketplaces",affiliate:"Partner offers",sponsored:"Sponsored",videos:"Videos & reviews",used:"Used",deals:"Deals & offers"};
function renderResults(d){const m=d.matches||[];if(!m.length){add("No results yet for this. Try adding your area or a few more details.");return}
  const groups={};m.forEach(x=>{const g=x.segment||x.source||"other";(groups[g]=groups[g]||[]).push(x)});
  const html=Object.entries(groups).map(([g,items])=>'<div class="group"><h3>'+esc(LABEL[g]||g.replace(/_/g," "))+' ('+items.length+')</h3><div class="rail">'+items.slice(0,10).map(card).join("")+'</div></div>').join("");
  const div=document.createElement("div");div.innerHTML=html;log.appendChild(div);window.scrollTo(0,document.body.scrollHeight)}
function card(x){const url=x.destination_url||x.url||x.link||"";const safe=/^https:\/\//.test(url)?url:"";const img=/^https:\/\//.test(x.image_url||"")?x.image_url:"";
  const price=x.price!=null&&x.price!==""?"₹"+Number(x.price).toLocaleString("en-IN"):"";const tag=x.affiliate?"Affiliate":(x.sponsored||x.segment==="sponsored"?"Sponsored":"");
  return '<div class="card">'+(img?'<img loading="lazy" alt="" src="'+esc(img)+'">':'')+'<div class="t">'+esc(x.title)+'</div><div class="s">'+esc([price,x.location_label||x.source_name||"",tag].filter(Boolean).join(" · "))+'</div>'+
   (safe?'<a href="'+esc(safe)+'" target="_blank" rel="noopener nofollow">Open</a>':'<span class="s">Send a request in the ASKODOX app</span>')+'</div>'}
$("#f").onsubmit=e=>{e.preventDefault();const t=$("#m").value.trim();if(!t)return;$("#m").value="";send(t)};
if(!S.history.length)add("Hi! Tell me what you need -- I'll ask only what matters, then show local sellers, nearby places and online options.");
else S.history.slice(-10).forEach(t=>add(esc(t.text),t.role==="user"));
// Asked from the askodox.com home page ask box (?q=): ask it once.
try{const q=(new URLSearchParams(location.search).get("q")||"").trim().slice(0,500);
  if(q){history.replaceState(null,"",location.pathname);S={history:[],deal:null};save();log.innerHTML="";send(q)}}catch(e){}
</script></body></html>'''


@router.get("/chat", response_class=HTMLResponse)
def web_chat() -> HTMLResponse:
    return HTMLResponse(PAGE, headers={
        "Cache-Control": "no-cache", "X-Frame-Options": "DENY", "Referrer-Policy": "strict-origin-when-cross-origin",
        "X-Content-Type-Options": "nosniff",
        # Same-origin APIs only (works on the backend host and on askodox.com/chat).
        "Content-Security-Policy": "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' "
                                   "'unsafe-inline'; img-src 'self' https: data:; connect-src 'self'; "
                                   "frame-ancestors 'none'; base-uri 'none'; form-action 'self'"})
