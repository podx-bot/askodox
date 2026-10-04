"""Staff Workspace page (``/staff``): one responsive page for phone, tablet
and laptop on the SAME backend APIs and permissions as the Command Center.

Sign-in: the staff member's own OTP-verified number (``/onboarding/otp``),
a one-time code from the ASKODOX app (``#code=``), or a staff token. The
session lives in sessionStorage only. Every action is re-checked on the
server -- the page only hides what the person may not use.
"""
from __future__ import annotations

from fastapi import APIRouter
from fastapi.responses import HTMLResponse

router = APIRouter(tags=["staff-workspace"])

CSP = ("default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; "
       "img-src 'self' https: data: blob:; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; "
       "form-action 'self'")

PAGE = r"""<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta name="robots" content="noindex"><title>ASKODOX Staff</title>
<style>
:root{--bg:#f6f7fb;--card:#fff;--ink:#14161f;--mut:#5f6577;--line:#e3e6ee;--acc:#3b4bd8;--ok:#0f7b43;--warn:#a05a00;--bad:#b42318}
@media(prefers-color-scheme:dark){:root{--bg:#0f1117;--card:#181b24;--ink:#eef0f6;--mut:#a3a9ba;--line:#2a2f3c;--acc:#8e9bff;--ok:#5fd394;--warn:#f0b35a;--bad:#ff8a80}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.45 system-ui,-apple-system,Segoe UI,Roboto,sans-serif}
header{position:sticky;top:0;z-index:5;background:var(--card);border-bottom:1px solid var(--line);padding:10px 16px;display:flex;gap:10px;align-items:center}
header b{flex:1}main{max-width:900px;margin:0 auto;padding:14px 16px 90px}
nav{position:fixed;bottom:0;left:0;right:0;background:var(--card);border-top:1px solid var(--line);display:flex;overflow-x:auto;padding:6px 6px calc(6px + env(safe-area-inset-bottom))}
nav button{flex:1 0 auto;min-width:72px;background:none;border:0;color:var(--mut);padding:8px 6px;font-size:13px;border-radius:10px}
nav button.on{color:var(--acc);background:color-mix(in srgb,var(--acc) 12%,transparent);font-weight:600}
@media(min-width:900px){nav{position:static;justify-content:center;border:0;background:none}main{padding-bottom:30px}}
.card{background:var(--card);border:1px solid var(--line);border-radius:14px;padding:14px;margin:0 0 12px}
input,select,textarea{width:100%;font:inherit;color:inherit;background:var(--bg);border:1px solid var(--line);border-radius:10px;padding:10px;margin:4px 0 10px}
label{font-size:13px;color:var(--mut)}button.p,button.s{font:inherit;border-radius:10px;padding:10px 14px;border:1px solid var(--acc);cursor:pointer}
button.p{background:var(--acc);color:#fff}button.s{background:none;color:var(--acc)}.row{display:flex;gap:8px;flex-wrap:wrap}.row>*{flex:1 1 140px}
.badge{display:inline-block;font-size:12px;padding:2px 8px;border-radius:99px;border:1px solid var(--line);color:var(--mut)}
.ok{color:var(--ok)}.warn{color:var(--warn)}.bad{color:var(--bad)}.mut{color:var(--mut);font-size:13px}
.item{display:flex;gap:10px;align-items:flex-start;border-top:1px solid var(--line);padding:10px 0}.item:first-child{border:0}
.item img{width:56px;height:56px;object-fit:cover;border-radius:8px;background:var(--bg)}.grow{flex:1;min-width:0}
.thumbs{display:flex;gap:6px;flex-wrap:wrap}.thumbs img{width:64px;height:64px;object-fit:cover;border-radius:8px}
#toast{position:fixed;left:16px;right:16px;bottom:84px;margin:auto;max-width:520px;background:var(--ink);color:var(--bg);padding:10px 14px;border-radius:10px;display:none;z-index:9}
</style></head><body>
<header><b>ASKODOX Staff</b><span id="who" class="mut"></span><button class="s" id="out" style="display:none">Sign out</button></header>
<main id="main"></main><nav id="nav" style="display:none"></nav><div id="toast"></div>
<script>
const $=s=>document.querySelector(s),M=$("#main");let ME=null,TAB="add",PREFILL={};
const esc=v=>String(v??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
function toast(t){const e=$("#toast");e.textContent=t;e.style.display="block";clearTimeout(e._t);e._t=setTimeout(()=>e.style.display="none",3500)}
function cred(){try{return JSON.parse(sessionStorage.getItem("askodox_staff")||"null")}catch(e){return null}}
function setCred(c){try{c?sessionStorage.setItem("askodox_staff",JSON.stringify(c)):sessionStorage.removeItem("askodox_staff")}catch(e){}}
async function api(path,method="GET",body,raw){const c=cred()||{},h={};
 if(c.session)h["X-ASKODOX-Staff-Session"]=c.session;if(c.token)h["X-ASKODOX-Staff-Token"]=c.token;if(c.bearer)h["Authorization"]="Bearer "+c.bearer;
 if(body!==undefined&&!raw)h["Content-Type"]="application/json";
 const r=await fetch(path,{method,headers:h,body:raw?body:(body===undefined?undefined:JSON.stringify(body))});
 const t=await r.text();let d;try{d=t?JSON.parse(t):{}}catch(e){d={detail:t}}
 if(r.status===401&&!path.startsWith("/onboarding")&&!path.startsWith("/api/staff")){setCred(null);signin("Your session ended -- sign in again.");throw new Error("signed out")}
 if(!r.ok)throw new Error(typeof d.detail==="string"?d.detail:JSON.stringify(d.detail||d));return d}
function hashParams(){const p=new URLSearchParams(location.hash.slice(1));history.replaceState(null,"",location.pathname);return p}
function signin(note){$("#nav").style.display="none";$("#out").style.display="none";$("#who").textContent="";
 M.innerHTML=`<div class="card"><h2 style="margin-top:0">Staff sign-in</h2>${note?`<p class="warn">${esc(note)}</p>`:""}
 <label>Your mobile number (with country code)</label><input id="mob" inputmode="tel" placeholder="91 98xxxxxxxx">
 <button class="p" id="send">Send code on WhatsApp</button>
 <div id="otpbox" style="display:none;margin-top:12px"><label>6-digit code</label><input id="otp" inputmode="numeric" maxlength="6"><button class="p" id="verify">Sign in</button></div>
 <details style="margin-top:16px"><summary class="mut">Use a staff token instead</summary><input id="tok" placeholder="stf_..."><button class="s" id="usetok">Sign in with token</button></details></div>`;
 $("#send").onclick=async()=>{try{await api("/onboarding/otp/send","POST",{mobile:$("#mob").value});$("#otpbox").style.display="block";toast("Code sent")}catch(e){toast(e.message)}};
 $("#verify").onclick=async()=>{try{const v=await api("/onboarding/otp/verify","POST",{mobile:$("#mob").value,otp:$("#otp").value});
  setCred({bearer:v.token});const s=await api("/api/staff/session","POST");setCred({session:s.session});start()}catch(e){setCred(null);toast(e.message)}};
 $("#usetok").onclick=()=>{setCred({token:$("#tok").value.trim()});start()}}
const TABS=[["add","Add"],["review","Review"],["items","My items"],["tasks","Tasks"],["support","Support"],["feedback","Feedback"],["demand","Demand"],["sources","Sources"],["analytics","Stats"]];
async function start(){try{ME=await api("/admin/cc/workspace/me")}catch(e){if(e.message!=="signed out")signin(e.message);return}
 $("#who").textContent=ME.name+" · "+ME.role;$("#out").style.display="inline-block";
 const tabs=TABS.filter(([k])=>ME.sections[k===`items`?"items":k]);if(!tabs.find(t=>t[0]===TAB))TAB=(tabs[0]||["add"])[0];
 $("#nav").innerHTML=tabs.map(([k,l])=>`<button data-t="${k}" class="${k===TAB?"on":""}">${l}${ME.counts[k]?` (${ME.counts[k]})`:""}</button>`).join("");
 $("#nav").style.display="flex";$("#nav").querySelectorAll("button").forEach(b=>b.onclick=()=>{TAB=b.dataset.t;start()});
 try{await ({add,review,items,tasks,support,feedback,demand,sources,analytics})[TAB]()}catch(e){if(e.message!=="signed out")M.innerHTML=`<div class="card bad">${esc(e.message)}</div>`}}
$("#out").onclick=()=>{setCred(null);signin()};
const FIELDS=[["title","Title"],["price","Current price (₹)"],["mrp","Original price / MRP (₹)"],["brand","Brand"],["seller","Seller / merchant"],["category","Category"],["image_url","Main image URL"],["description","Description","ta"],["location","Location / city"],["coverage","Coverage (cities / pincodes)"],["offer_text","Offer / coupon text"],["expires_at","Offer ends (YYYY-MM-DD)"],["affiliate_url","Affiliate / deep link"],["canonical_url","Canonical URL"],["product_id","Product id (ASIN / pid)"]];
async function add(){const types=ME.item_types;M.innerHTML=`<div class="card"><h3 style="margin-top:0">Paste one link</h3>
 <div class="row"><select id="itype">${types.map(t=>`<option ${PREFILL.type===t?"selected":""}>${t}</option>`).join("")}</select></div>
 <input id="url" type="url" placeholder="https://..." value="${esc(PREFILL.url||"")}">
 <div class="row"><button class="s" id="paste">Paste</button><button class="p" id="fetch">Fetch details</button></div><div id="res"></div></div>
 <div class="card"><h3 style="margin-top:0">Many links</h3><textarea id="bulk" rows="4" placeholder="One link per line (up to 50)"></textarea><button class="s" id="bulkgo">Check links</button><div id="bulkres"></div></div>`;
 $("#paste").onclick=async()=>{try{$("#url").value=await navigator.clipboard.readText()}catch(e){toast("Long-press the box and paste")}};
 $("#fetch").onclick=()=>fetchOne($("#url").value,$("#itype").value);
 $("#bulkgo").onclick=async()=>{try{const d=await api("/admin/cc/workspace/import/bulk","POST",{urls:$("#bulk").value.split(/\s+/).filter(Boolean),item_type:$("#itype").value});
  $("#bulkres").innerHTML=d.items.map((r,i)=>`<div class="item"><div class="grow"><b>${esc((r.fields||{}).title||r.url)}</b><div class="mut">${esc((r.source||{}).name||"")} ${r.duplicates&&r.duplicates.length?`<span class="warn">· already added (#${r.duplicates[0].id})</span>`:""}${r.ok?"":` <span class="bad">${esc(r.error)}</span>`}</div></div>${r.ok&&!(r.duplicates||[]).length?`<button class="s" data-u="${esc(r.url)}">Add</button>`:""}</div>`).join("");
  $("#bulkres").querySelectorAll("button").forEach(b=>b.onclick=()=>fetchOne(b.dataset.u,$("#itype").value))}catch(e){toast(e.message)}};
 if(PREFILL.url){const u=PREFILL.url;PREFILL={};fetchOne(u,$("#itype").value)}}
async function fetchOne(url,type){const box=$("#res")||M;box.innerHTML=`<p class="mut">Reading the page…</p>`;
 let d;try{d=await api("/admin/cc/workspace/import","POST",{url,item_type:type})}catch(e){box.innerHTML=`<p class="bad">${esc(e.message)}</p>`;return}
 const f=d.fields||{},st=d.field_status||{},dup=(d.duplicates||[]);let photos=[];
 box.innerHTML=`<p><span class="badge">${esc((d.source||{}).name||"Unknown source")}</span> <span class="mut">${esc(d.note||"")}</span></p>
 ${dup.length?`<p class="warn">Already in ASKODOX: ${dup.map(x=>`#${x.id} ${esc(x.title)} (${esc(x.review_status)})`).join(", ")}</p>`:""}
 ${FIELDS.map(([k,l,ta])=>`<label>${l} ${st[k]==="fetched"?'<span class="ok">· from page</span>':st[k]?'<span class="mut">· '+esc(st[k])+"</span>":""}</label>${ta?`<textarea id="f_${k}" rows="3">${esc(f[k]||"")}</textarea>`:`<input id="f_${k}" value="${esc(f[k]??"")}">`}`).join("")}
 <label>Stock</label><select id="f_stock"><option>UNKNOWN</option><option ${d.suggested_stock==="IN_STOCK"?"selected":""}>IN_STOCK</option><option ${d.suggested_stock==="OUT_OF_STOCK"?"selected":""}>OUT_OF_STOCK</option></select>
 <label>Photos (camera / gallery)</label><input id="photo" type="file" accept="image/*" capture="environment" multiple><div class="thumbs" id="thumbs"></div>
 <div class="row" style="margin-top:10px"><button class="s" id="draft">Save draft</button><button class="p" id="submit">${ME.can_publish?"Publish":"Submit for review"}</button></div>`;
 $("#photo").onchange=async e=>{for(const file of e.target.files){const fd=new FormData();fd.append("file",file);
  try{const u=await api("/admin/cc/workspace/uploads","POST",fd,true);photos.push(u.url);$("#thumbs").innerHTML=photos.map(p=>`<img src="${esc(p)}">`).join("")}catch(err){toast(err.message)}}};
 const save=async action=>{const fields={original_product_url:d.url};FIELDS.forEach(([k])=>{const v=$("#f_"+k).value.trim();if(v)fields[k]=v});
  if(photos.length){fields.images=photos;if(!fields.image_url)fields.image_url=photos[0]}
  try{const r=await api("/admin/cc/workspace/items","POST",{item_type:type,fields,action,stock_status:$("#f_stock").value});
   toast(r.review_status==="LIVE"?"Published":r.review_status==="DRAFT"?"Draft saved":"Sent for review");TAB="items";start()}catch(e){toast(e.message)}};
 $("#draft").onclick=()=>save("draft");$("#submit").onclick=()=>save("submit")}
function itemRow(i,btns){return `<div class="item">${i.image_url?`<img src="${esc(i.image_url)}" alt="">`:""}<div class="grow"><b>${esc(i.title)}</b>
 <div class="mut">${esc(i.item_type)} · ${esc(i.platform_name)} · <span class="badge">${esc(i.review_status)}</span> ${i.price!=null?"₹"+esc(i.price):""} ${i.stock_status==="OUT_OF_STOCK"?'<span class="bad">out of stock</span>':""}</div>
 ${i.review_note?`<div class="mut">Note: ${esc(i.review_note)}</div>`:""}<div class="row" style="margin-top:6px">${btns.map(([a,l])=>`<button class="s" data-a="${a}" data-id="${i.id}">${l}</button>`).join("")}</div></div></div>`}
function bindReview(){M.querySelectorAll("button[data-a]").forEach(b=>b.onclick=async()=>{let note="";if(b.dataset.a==="reject"){note=prompt("What needs fixing?")||"";if(!note)return}
 try{await api(`/admin/cc/workspace/items/${b.dataset.id}/review`,"POST",{action:b.dataset.a,note});toast("Done");start()}catch(e){toast(e.message)}})}
async function review(){const d=await api("/admin/cc/workspace/items?status=NEEDS_REVIEW");
 M.innerHTML=`<div class="card"><h3 style="margin-top:0">Waiting for review (${d.items.length})</h3>${d.items.map(i=>itemRow(i,[["approve","Approve & publish"],["reject","Send back"]])).join("")||'<p class="mut">Nothing waiting.</p>'}</div>`;bindReview()}
async function items(){const d=await api("/admin/cc/workspace/items?mine=true");
 const acts=i=>({DRAFT:[["submit",ME.can_publish?"Publish":"Submit"]],LIVE:[["pause","Pause"],["expire","Expire"]],PAUSED:ME.can_publish?[["resume","Resume"]]:[]}[i.review_status]||[]);
 M.innerHTML=`<div class="card"><h3 style="margin-top:0">My items</h3>${d.items.map(i=>itemRow(i,acts(i))).join("")||'<p class="mut">Nothing yet -- add a link.</p>'}</div>`;bindReview()}
async function tasks(){const d=await api("/admin/cc/workspace/tasks");
 M.innerHTML=`<div class="card"><h3 style="margin-top:0">My tasks</h3>${d.items.map(t=>{const x=t.data||{};return `<div class="item"><div class="grow"><b>${esc(x.title)}</b> <span class="badge">${esc((x.priority||"normal").toUpperCase())}</span> <span class="badge">${esc(t.status)}</span>
 <div class="mut">${esc(x.why||"")}</div><div>${esc(x.expected_action||"")}</div>${x.due_at?`<div class="mut">Due ${esc(x.due_at)}</div>`:""}
 <div class="row" style="margin-top:6px">${t.status!=="IN_PROGRESS"?`<button class="s" data-k="start" data-id="${t.id}">Start</button>`:""}<button class="p" data-k="done" data-id="${t.id}">Done</button></div></div></div>`}).join("")||'<p class="mut">No tasks for you right now.</p>'}</div>`;
 M.querySelectorAll("button[data-k]").forEach(b=>b.onclick=async()=>{try{await api(`/admin/cc/workspace/tasks/${b.dataset.id}/${b.dataset.k}`,"POST");start()}catch(e){toast(e.message)}})}
async function support(){const d=await api("/admin/cc/escalations?status=");const open=d.items.filter(i=>!["RESOLVED","CLOSED"].includes(i.status));
 M.innerHTML=`<div class="card"><h3 style="margin-top:0">Support queue (${open.length})</h3>${open.map(i=>`<div class="item"><div class="grow"><b>${esc(i.subject||i.category||"Request")}</b> <span class="badge">${esc(i.priority)}</span> <span class="badge">${esc(i.sla_state)}</span>
 <div class="mut">${esc(i.requester)} · ${esc(i.status)}</div><div>${esc((i.handoff||{}).summary||i.message||"")}</div>
 <textarea id="r${i.id}" rows="2" placeholder="Reply to the customer"></textarea><button class="s" data-r="${i.id}">Send reply</button></div></div>`).join("")||'<p class="mut">No open requests.</p>'}</div>`;
 M.querySelectorAll("button[data-r]").forEach(b=>b.onclick=async()=>{const m=$("#r"+b.dataset.r).value.trim();if(!m)return;try{await api(`/admin/cc/escalations/${b.dataset.r}/reply`,"POST",{message:m});toast("Sent");start()}catch(e){toast(e.message)}})}
async function feedback(){const d=await api("/admin/cc/platform/r/feedback_reports");const open=(d.items||[]).filter(r=>["NEW","TRIAGED","IN_PROGRESS"].includes(r.status));
 M.innerHTML=`<div class="card"><h3 style="margin-top:0">Feedback & problems (${open.length})</h3>${open.map(r=>{const x=r.data||{};return `<div class="item"><div class="grow"><b>${esc(x.summary)}</b> <span class="badge">${esc(x.kind)}</span> <span class="badge">${esc(r.status)}</span>
 <div class="mut">${esc(x.feature||"")} ${esc(x.app_version||"")}</div><div>${esc(x.message||"")}</div><div class="row" style="margin-top:6px"><button class="s" data-f="triage" data-id="${r.id}">Triage</button><button class="p" data-f="resolve" data-id="${r.id}">Resolved</button></div></div></div>`}).join("")||'<p class="mut">Nothing open.</p>'}</div>`;
 M.querySelectorAll("button[data-f]").forEach(b=>b.onclick=async()=>{try{await api(`/admin/cc/platform/r/feedback_reports/${b.dataset.id}/actions/${b.dataset.f}`,"POST",{});start()}catch(e){toast(e.message)}})}
async function demand(){const d=await api("/admin/cc/demand/opportunities");
 M.innerHTML=`<div class="card"><h3 style="margin-top:0">Unmet demand</h3>${d.note?`<p class="mut">${esc(d.note)}</p>`:""}${d.items.map((o,i)=>`<div class="item"><div class="grow"><b>${esc(o.subject||o.key)}</b>
 <div class="mut">${esc(o.location||"")} ${o.searches?"· "+esc(o.searches)+" searches":""} ${o.budget_band?"· "+esc(o.budget_band):""} · rule ${esc(o.rule)}</div>
 <div class="row" style="margin-top:6px"><select id="role${i}"><option>affiliate_staff</option><option>seller_support</option><option>content_staff</option><option>demand_staff</option><option>any</option></select><button class="s" data-o="${i}">Create task</button></div></div></div>`).join("")}</div>`;
 M.querySelectorAll("button[data-o]").forEach(b=>b.onclick=async()=>{const o=d.items[+b.dataset.o];try{const r=await api("/admin/cc/workspace/tasks/from-demand","POST",{title:`Find supply: ${o.subject||o.key}`,
  why:`${o.searches||"Repeated"} searches${o.location?" in "+o.location:""} without a satisfying result (rule ${o.rule}).`,expected_action:"Add matching products / sellers or contact eligible sellers.",
  assignee_role:$("#role"+b.dataset.o).value,region:o.location||"",dedupe_key:`demand:${o.rule_id}:${o.key}`,evidence:o});toast(r.created?"Task created":"A task for this already exists")}catch(e){toast(e.message)}})}
async function sources(){const d=await api("/admin/cc/platform/r/sources");
 M.innerHTML=`<div class="card"><h3 style="margin-top:0">Sources</h3><p class="mut">Add or edit sources in the Command Center (Catalog → Sources). Health below is live.</p>${(d.items||[]).map(r=>{const x=r.data||{};return `<div class="item"><div class="grow"><b>${esc(x.name)}</b> <span class="badge">${esc(r.status)}</span> <span class="badge">${esc(x.connector)}</span><div class="mut">${esc((x.domains||[]).join(", "))}</div></div></div>`}).join("")||'<p class="mut">No sources yet.</p>'}</div>`}
async function analytics(){const d=await api("/admin/cc/workspace/analytics");
 M.innerHTML=`<div class="card"><h3 style="margin-top:0">Items</h3><p>${Object.entries(d.items.by_status).map(([k,v])=>`<span class="badge">${esc(k)} ${v}</span>`).join(" ")}</p><p>${Object.entries(d.items.by_type).map(([k,v])=>`<span class="badge">${esc(k)} ${v}</span>`).join(" ")}</p><p class="mut">Open tasks: ${d.open_tasks}</p></div>
 <div class="card"><h3 style="margin-top:0">Staff activity (30 days)</h3>${d.staff_activity_30d.map(a=>`<div class="mut">${esc(a.actor)} · ${esc(a.action)} · ${a.count}</div>`).join("")||'<p class="mut">No changes yet.</p>'}</div>
 <div class="card"><h3 style="margin-top:0">Source health</h3>${d.sources.map(s=>`<div class="mut"><b>${esc(s.name)}</b> ${esc(s.health.status)} ${s.health.last_error?'<span class="bad">'+esc(s.health.last_error)+"</span>":""}</div>`).join("")||'<p class="mut">No sources yet.</p>'}</div>`}
(async()=>{const p=hashParams();if(p.get("url"))PREFILL={url:p.get("url"),type:p.get("type")||"product"};
 if(p.get("code")){try{const s=await api("/api/staff/handoff/redeem","POST",{code:p.get("code")});setCred({session:s.session})}catch(e){signin(e.message);return}}
 cred()?start():signin()})();
</script></body></html>"""


@router.get("/staff", response_class=HTMLResponse)
def staff_page() -> HTMLResponse:
    return HTMLResponse(PAGE, headers={"Content-Security-Policy": CSP, "X-Frame-Options": "DENY",
                                       "X-Content-Type-Options": "nosniff", "Referrer-Policy": "no-referrer",
                                       "Cache-Control": "no-store"})
