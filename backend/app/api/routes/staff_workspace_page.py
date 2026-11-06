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
       "img-src 'self' https: data: blob:; media-src 'self' blob:; connect-src 'self'; frame-ancestors 'none'; "
       "base-uri 'none'; "
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
const $=s=>document.querySelector(s),M=$("#main");let ME=null,TAB="add",PREFILL={},PREFILL_AFF="";
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
 const tabs=TABS.filter(([k])=>ME.sections[k==="reels"?"items":k]);if(!tabs.find(t=>t[0]===TAB))TAB=(tabs[0]||["add"])[0];
 $("#nav").innerHTML=tabs.map(([k,l])=>`<button data-t="${k}" class="${k===TAB?"on":""}">${l}${ME.counts[k]?` (${ME.counts[k]})`:""}</button>`).join("");
 $("#nav").style.display="flex";$("#nav").querySelectorAll("button").forEach(b=>b.onclick=()=>{TAB=b.dataset.t;start()});
 try{await ({add,review,items,reels,tasks,support,feedback,demand,sources,analytics})[TAB]()}catch(e){if(e.message!=="signed out")M.innerHTML=`<div class="card bad">${esc(e.message)}</div>`}}
$("#out").onclick=()=>{setCred(null);signin()};
const FIELDS=[["title","Title"],["price","Current price (₹)"],["mrp","Original price / MRP (₹)"],["brand","Brand"],["seller","Seller / merchant"],["category","Category"],["image_url","Main image URL"],["description","Description","ta"],["location","Location / city"],["coverage","Coverage (cities / pincodes)"],["offer_text","Offer / coupon text"],["expires_at","Offer ends (YYYY-MM-DD)"],["affiliate_url","Commission link (optional / ఐచ్ఛికం)"],["verified_commission_rate","Commission % (optional / ఐచ్ఛికం)"],["canonical_url","Canonical URL"],["product_id","Product id (ASIN / pid)"]];
async function add(){const types=ME.item_types;M.innerHTML=`<div class="card"><div class="row"><button class="p" id="m_link">🔗 Store link (Meesho / Flipkart / Amazon)</button><button class="s" id="m_own">🏷️ Own / Brand product</button></div>
 <p class="mut" style="margin:8px 0 0">Store link = the store's own data only. Own / Brand = our photos, AI description, reel, promotions. / Store link అంటే store ఇచ్చిన data మాత్రమే. Own / Brand అంటే మన photos, AI description, reel, promotions.</p></div>
 <div class="card" id="linkcard"><h3 style="margin-top:0">Paste one link</h3>
 <div class="row"><select id="itype">${types.map(t=>`<option ${PREFILL.type===t?"selected":""}>${t}</option>`).join("")}</select></div>
 <input id="url" type="url" placeholder="https://..." value="${esc(PREFILL.url||"")}">
 <div class="row"><button class="s" id="paste">Paste</button><button class="p" id="fetch">Fetch details</button></div><div id="res"></div></div>
 <div class="card" id="bulkcard"><h3 style="margin-top:0">Many links</h3><textarea id="bulk" rows="4" placeholder="One link per line (up to 50)"></textarea><button class="s" id="bulkgo">Check links</button><div id="bulkres"></div></div>`;
 $("#m_own").onclick=()=>ownForm();$("#m_link").onclick=()=>$("#url").focus();
 $("#paste").onclick=async()=>{try{$("#url").value=await navigator.clipboard.readText()}catch(e){toast("Long-press the box and paste")}};
 $("#fetch").onclick=()=>fetchOne(firstLink($("#url").value),$("#itype").value);
 $("#bulkgo").onclick=async()=>{try{const d=await api("/admin/cc/workspace/import/bulk","POST",{urls:($("#bulk").value.match(/https:\/\/[^\s"'<>]+/g)||[]),item_type:$("#itype").value});
  $("#bulkres").innerHTML=d.items.map((r,i)=>`<div class="item"><div class="grow"><b>${esc((r.fields||{}).title||r.url)}</b><div class="mut">${esc((r.source||{}).name||"")} ${r.duplicates&&r.duplicates.length?`<span class="warn">· already added (#${r.duplicates[0].id})</span>`:""}${r.ok?"":` <span class="bad">${esc(r.error)}</span>`}</div></div>${r.ok&&!(r.duplicates||[]).length?`<button class="s" data-u="${esc(r.url)}">Add</button>`:""}</div>`).join("");
  $("#bulkres").querySelectorAll("button").forEach(b=>b.onclick=()=>fetchOne(b.dataset.u,$("#itype").value))}catch(e){toast(e.message)}};
 if(PREFILL.url){const u=PREFILL.url;PREFILL={};fetchOne(u,$("#itype").value)}}
// Owner 2026-11-04: paste a link -> everything fills by itself. Only Title, Price and the
// AI description are shown; the rest waits under "More details".
const READS={};window.askodoxPageRead=(id,r)=>{const f=READS[id];if(f){delete READS[id];f(r&&r.ok?r:null)}};
function readOnPhone(url){if(!window.AskodoxPageReader)return Promise.resolve(null);
 return new Promise(res=>{const id=String(Date.now())+Math.random();READS[id]=res;
  setTimeout(()=>{if(READS[id]){delete READS[id];res(null)}},25000);
  try{AskodoxPageReader.postMessage(JSON.stringify({id,url}))}catch(e){delete READS[id];res(null)}})}
// Commission link / % only for staff with those grants (the server refuses them otherwise).
const MYFIELDS=()=>FIELDS.filter(([k])=>(k!=="affiliate_url"||ME.can_link)&&(k!=="verified_commission_rate"||ME.can_commission));
const MAIN_FIELDS=["title","price","description","affiliate_url","verified_commission_rate"];
// Shared text ("Check this on Meesho https://...") -> just the link.
function firstLink(t){const m=String(t||"").match(/https:\/\/[^\s"'<>]+/);return m?m[0]:String(t||"").trim()}
async function fetchOne(url,type){url=firstLink(url);const box=$("#res")||M;box.innerHTML=`<p class="mut">Reading the page… / page చదువుతోంది…</p>`;
 let d,page=null;try{page=await readOnPhone(url);
  d=await api("/admin/cc/workspace/import","POST",page?{url,item_type:type,html:page.html,final_url:page.final_url}:{url,item_type:type})}catch(e){box.innerHTML=`<p class="bad">${esc(e.message)}</p>`;return}
 if(d.ok===false){box.innerHTML=`<p class="bad">${esc(d.error||"This link could not be read")}</p>`;return}
 const f=d.fields||{},st=d.field_status||{},dup=(d.duplicates||[]);let photos=[...new Set([...(f.images||[]),...(f.image_url?[f.image_url]:[])])].slice(0,8);
 const field=([k,l,ta])=>`<label>${l} ${st[k]==="fetched"?'<span class="ok">· from page</span>':""}</label>${ta?`<textarea id="f_${k}" rows="${k==="description"?6:3}">${esc(f[k]||"")}</textarea>`:`<input id="f_${k}" value="${esc(f[k]??"")}">`}`;
 const ok=d.status==="ok";
 box.innerHTML=`<p><span class="badge">${esc((d.source||{}).name||"Unknown source")}</span> <span class="${ok?"ok":"mut"}">${ok?"✓ Details filled -- check and save / వివరాలు నిండాయి -- చూసి save చేయండి":esc(d.note||"")}</span></p>
 ${dup.length?`<p class="warn">Already in ASKODOX: ${dup.map(x=>`#${x.id} ${esc(x.title)} (${esc(x.review_status)})`).join(", ")}</p>`:""}
 <label>Photos</label><div class="thumbs" id="thumbs"></div>
 <div class="row"><label class="s btn">📷 Camera<input id="photo" type="file" accept="image/*" capture="environment" hidden></label><label class="s btn">🖼️ Gallery<input id="photos" type="file" accept="image/*" multiple hidden></label></div>
 ${MYFIELDS().filter(([k])=>MAIN_FIELDS.includes(k)).map(field).join("")}
 <span class="mut" id="aidescnote"></span>
 <details style="margin:6px 0 10px"><summary class="mut">More details (optional) / మరిన్ని వివరాలు</summary>
 ${MYFIELDS().filter(([k])=>!MAIN_FIELDS.includes(k)).map(field).join("")}
 <label>Stock</label><select id="f_stock"><option>UNKNOWN</option><option ${d.suggested_stock==="IN_STOCK"?"selected":""}>IN_STOCK</option><option ${d.suggested_stock==="OUT_OF_STOCK"?"selected":""}>OUT_OF_STOCK</option></select>
 <div class="row"><button class="s" id="aidesc">✨ AI తో description మళ్లీ రాయి</button></div></details>
 <p class="mut">Store item: the store's own name, price and photos are kept as given (no AI photos / reels). / Store item: store ఇచ్చిన data మాత్రమే.</p>
 <div class="row" style="margin-top:10px"><button class="s" id="draft">Save draft</button><button class="p" id="submit">${ME.can_publish?"Publish":"Submit for review"}</button></div>`;
 const thumbs=()=>{$("#thumbs").innerHTML=photos.length?photos.map(p=>`<img src="${esc(p)}">`).join(""):`<span class="mut">No photos yet -- add from camera / gallery</span>`};thumbs();
 const addPhotos=async e=>{for(const file of e.target.files){const fd=new FormData();fd.append("file",file);
  try{const u=await api("/admin/cc/workspace/uploads","POST",fd,true);photos.push(u.url);thumbs()}catch(err){toast(err.message)}}};
 $("#photo").onchange=addPhotos;$("#photos").onchange=addPhotos;
 if(PREFILL_AFF&&$("#f_affiliate_url")&&!$("#f_affiliate_url").value){$("#f_affiliate_url").value=PREFILL_AFF;PREFILL_AFF=""}
 const describe=async()=>{const fields={};MYFIELDS().forEach(([k])=>{const v=$("#f_"+k).value.trim();if(v)fields[k]=v});if(!fields.title)return;$("#aidescnote").textContent="✨ description రాస్తోంది…";
  try{const r=await api("/admin/cc/workspace/describe","POST",{fields,photos:photos.filter(p=>p.includes("/media/staff/"))});if(!r.ok){$("#aidescnote").textContent=r.reason||"";return}
   $("#f_description").value=[r.description_en,r.description_te].filter(Boolean).join("\n\n");
   $("#aidescnote").textContent=(r.unsupported_claims||[]).length?"⚠️ check: "+r.unsupported_claims.join(", "):"✓ AI description -- చదివి save చేయండి"}catch(e){$("#aidescnote").textContent=e.message}};
 $("#aidesc").onclick=describe;
 if(ok&&!dup.length)describe(); // written automatically; staff only read it
 // Store items keep the store's own photo links (their data only).
 const ownPhotos=async()=>photos;
 const save=async action=>{const fields={original_product_url:d.url};MYFIELDS().forEach(([k])=>{const v=$("#f_"+k).value.trim();if(v)fields[k]=v});
  if(!fields.original_product_url||fields.original_product_url===d.url)fields.original_product_url=f.original_product_url||d.url;
  toast("Saving… / save అవుతోంది…");const kept=await ownPhotos();
  if(kept.length){fields.images=kept;fields.image_url=kept[0]}
  try{const r=await api("/admin/cc/workspace/items","POST",{item_type:type,fields,action,stock_status:$("#f_stock").value});
   let msg=r.review_status==="LIVE"?"Published":r.review_status==="DRAFT"?"Draft saved":"Sent for review";
   toast(msg);TAB="items";start()}catch(e){toast(e.message)}};
 $("#draft").onclick=()=>save("draft");$("#submit").onclick=()=>save("submit")}
// Own / Brand product (owner 2026-11-04): our photos (camera / gallery or copied from the brand's
// page), AI description, commission link / %, and promotions from the Command Center. No videos
// (owner 2026-11-04: video cost is more than the commission). Needs a "where to buy" link.
async function ownForm(){let photos=[];M.innerHTML=`<div class="card"><h3 style="margin-top:0">🏷️ Own / Brand product</h3>
 <label>Product name *</label><input id="o_title">
 <div class="row"><div><label>Price (₹)</label><input id="o_price" inputmode="decimal"></div><div><label>MRP (₹)</label><input id="o_mrp" inputmode="decimal"></div></div>
 <label>Brand / maker</label><input id="o_brand">
 <label>Where to buy -- brand page / WhatsApp / order form link *</label><input id="o_buy" type="url" placeholder="https://...">
 <label>Brand's own product page (optional -- copies its photos and details)</label><div class="row"><input id="o_page" type="url" placeholder="https://..."><button class="s" id="o_copy">Copy photos</button></div>
 <label>Photos</label><div class="thumbs" id="o_thumbs"></div>
 <div class="row"><label class="s btn">📷 Camera<input id="o_cam" type="file" accept="image/*" capture="environment" hidden></label><label class="s btn">🖼️ Gallery<input id="o_gal" type="file" accept="image/*" multiple hidden></label></div>
 <label>Category</label><input id="o_cat">
 <label>Description</label><textarea id="o_desc" rows="6"></textarea><div class="row"><button class="s" id="o_ai">✨ AI తో description రాయి</button></div><span class="mut" id="o_note"></span>
 ${ME.can_link?`<label>Commission link (optional / ఐచ్ఛికం)</label><input id="o_aff" type="url" placeholder="https://...">`:""}
 ${ME.can_commission?`<div class="row"><div><label>Commission % (optional / ఐచ్ఛికం)</label><input id="o_rate" inputmode="decimal" placeholder="e.g. 10"></div></div>`:""}
 <label>Offer / coupon for buyers (optional)</label><input id="o_offer" placeholder="e.g. coupon ASKO10 -- 10% off">
 <div class="row" style="margin-top:10px"><button class="s" id="o_back">← Back</button><button class="s" id="o_draft">Save draft</button><button class="p" id="o_submit">${ME.can_publish?"Publish":"Submit for review"}</button></div>
 <p class="mut">Promote it to users: Command Center → Growth → Promotions (campaign with review, consent and caps). / Users కి promote: Command Center → Growth → Promotions.</p></div>`;
 const thumbs=()=>{$("#o_thumbs").innerHTML=photos.length?photos.map(p=>`<img src="${esc(p)}">`).join(""):`<span class="mut">No photos yet</span>`};thumbs();
 const addPhotos=async e=>{for(const file of e.target.files){const fd=new FormData();fd.append("file",file);
  try{const u=await api("/admin/cc/workspace/uploads","POST",fd,true);photos.push(u.url);thumbs()}catch(err){toast(err.message)}}};
 $("#o_cam").onchange=addPhotos;$("#o_gal").onchange=addPhotos;$("#o_back").onclick=()=>add();
 $("#o_copy").onclick=async()=>{const url=firstLink($("#o_page").value);if(!url)return;toast("Reading the brand page…");
  try{const page=await readOnPhone(url);const d=await api("/admin/cc/workspace/import","POST",page?{url,item_type:"product",html:page.html,final_url:page.final_url}:{url,item_type:"product"});
   const f=d.fields||{};if(!$("#o_title").value&&f.title)$("#o_title").value=f.title;if(!$("#o_brand").value&&f.brand)$("#o_brand").value=f.brand;
   if(!$("#o_cat").value&&f.category)$("#o_cat").value=f.category;if(!$("#o_desc").value&&f.description)$("#o_desc").value=f.description;
   if(!$("#o_price").value&&f.price!=null)$("#o_price").value=f.price;if(!$("#o_mrp").value&&f.mrp!=null)$("#o_mrp").value=f.mrp;
   for(const p of (f.images||[]).slice(0,6)){try{photos.push((await api("/admin/cc/workspace/uploads/from-url","POST",{url:p})).url);thumbs()}catch(e){}}
   toast(photos.length?"Photos copied":"No photos found on that page")}catch(e){toast(e.message)}};
 $("#o_ai").onclick=async()=>{const fields={title:$("#o_title").value.trim(),brand:$("#o_brand").value.trim(),price:$("#o_price").value.trim(),category:$("#o_cat").value.trim()};
  Object.keys(fields).forEach(k=>{if(!fields[k])delete fields[k]});if(!fields.title){toast("Product name first");return}$("#o_note").textContent="✨ రాస్తోంది…";
  try{const r=await api("/admin/cc/workspace/describe","POST",{fields,photos});if(!r.ok){$("#o_note").textContent=r.reason||"";return}
   $("#o_desc").value=[r.description_en,r.description_te].filter(Boolean).join("\n\n");$("#o_note").textContent="✓ AI description -- చదివి save చేయండి"}catch(e){$("#o_note").textContent=e.message}};
 const save=async action=>{const buy=firstLink($("#o_buy").value),title=$("#o_title").value.trim();
  if(!title||!buy.startsWith("https://")){toast("Name and a https:// where-to-buy link are needed");return}
  const fields={title,original_product_url:buy,platform:"other"};if($("#o_desc").value.trim())fields.description=$("#o_desc").value.trim();
  const num=v=>{const n=parseFloat(String(v).replace(/[^0-9.]/g,""));return isNaN(n)?null:n};
  if(num($("#o_price").value)!=null)fields.price=num($("#o_price").value);if(num($("#o_mrp").value)!=null)fields.mrp=num($("#o_mrp").value);
  if($("#o_brand").value.trim()){fields.brand=$("#o_brand").value.trim();fields.seller=fields.brand}
  if($("#o_cat").value.trim())fields.category=$("#o_cat").value.trim();if($("#o_offer").value.trim())fields.offer_text=$("#o_offer").value.trim();
  if(photos.length){fields.images=photos;fields.image_url=photos[0]}
  if($("#o_aff")&&$("#o_aff").value.trim())fields.affiliate_url=firstLink($("#o_aff").value);
  if($("#o_rate")&&num($("#o_rate").value)!=null)fields.verified_commission_rate=num($("#o_rate").value);
  try{const r=await api("/admin/cc/workspace/items","POST",{item_type:"product",fields,action});
   let msg=r.review_status==="LIVE"?"Published -- search లో photos తో వస్తుంది":r.review_status==="DRAFT"?"Draft saved":"Sent for review";
   toast(msg);TAB="items";start()}catch(e){toast(e.message)}};
 $("#o_draft").onclick=()=>save("draft");$("#o_submit").onclick=()=>save("submit")}
function itemRow(i,btns){return `<div class="item">${i.image_url?`<img src="${esc(i.image_url)}" alt="">`:""}<div class="grow"><b>${esc(i.title)}</b>
 <div class="mut">${esc(i.item_type)} · ${esc(i.platform_name)} · <span class="badge">${esc(i.review_status)}</span> ${i.price!=null?"₹"+esc(i.price):""} ${i.stock_status==="OUT_OF_STOCK"?'<span class="bad">out of stock</span>':""}</div>
 ${i.review_note?`<div class="mut">Note: ${esc(i.review_note)}</div>`:""}<div class="row" style="margin-top:6px">${btns.map(([a,l])=>`<button class="s" data-a="${a}" data-id="${i.id}">${l}</button>`).join("")}</div></div></div>`}
// Android WebView shows no prompt() / confirm() dialogs: everything is inline.
function bindReel(){M.querySelectorAll("button[data-reel]").forEach(b=>b.onclick=()=>{
 const box=document.createElement("div");box.className="row";box.style.marginTop="6px";
 box.innerHTML=`<input placeholder="Reel లో చెప్పాల్సిన మాటలు (optional)"><button class="p">🎬 Make reel</button>`;b.replaceWith(box);
 box.querySelector("button").onclick=async()=>{try{const r=await api(`/admin/cc/workspace/items/${b.dataset.reel}/reel`,"POST",{voice_text:box.querySelector("input").value.trim(),seconds:30});
  toast(`Reel తయారవుతోంది (${r.photos} photos). 🎬 Reels tab లో చూడండి.`);box.innerHTML=`<span class="mut">🎬 Reel తయారవుతోంది -- Reels tab లో చూడండి</span>`}catch(e){toast(e.message)}}})}
function bindReview(){bindReel();M.querySelectorAll("button[data-a]").forEach(b=>b.onclick=async()=>{
 const send=async note=>{try{await api(`/admin/cc/workspace/items/${b.dataset.id}/review`,"POST",{action:b.dataset.a,note});toast("Done");start()}catch(e){toast(e.message)}};
 if(b.dataset.a!=="reject")return send("");
 const box=document.createElement("div");box.className="row";box.innerHTML=`<input placeholder="What needs fixing?"><button class="p">Send back</button>`;b.replaceWith(box);
 box.querySelector("button").onclick=()=>{const n=box.querySelector("input").value.trim();if(!n){toast("Write what needs fixing");return}send(n)}})}
// Owner 2026-11-04: "where do I see the ready video?" -- every reel, its state, a player, approve / reject.
async function reels(){const d=await api("/admin/cc/workspace/reels");
 const label={MAKING:"⏳ తయారవుతోంది",READY:"✓ Ready",FAILED:"✗ Failed"};
 M.innerHTML=`<div class="card"><h3 style="margin-top:0">🎬 Reels (${d.items.length})</h3>${d.items.map(r=>`<div class="item"><div class="grow"><b>${esc(r.title)}</b>
  <div class="mut">${label[r.reel_status]||esc(r.reel_status)} · <span class="badge">${esc(r.status)}</span>${r.price_shown?" · "+esc(r.price_shown):""}${r.reason?` · <span class="bad">${esc(r.reason)}</span>`:""}</div>
  <div id="v_${esc(r.video_id)}"></div><div class="row" style="margin-top:6px">${r.reel_status==="READY"?`<button class="s" data-play="${esc(r.video_id)}">▶ Play</button>`:""}
  ${d.can_publish&&r.status==="PENDING_REVIEW"?`<button class="p" data-rv="approve" data-id="${esc(r.video_id)}">Approve -- users చూస్తారు</button><button class="s" data-rv="reject" data-id="${esc(r.video_id)}">Reject</button>`:""}</div></div></div>`).join("")
  ||'<p class="mut">No reels yet. Own / Brand product save చేసేటప్పుడు "Reel కూడా తయారు చేయి" tick చేయండి, లేదా My items లో 🎬 నొక్కండి.</p>'}
  ${d.items.some(r=>r.reel_status==="MAKING")?'<button class="s" id="rrefresh">↻ Refresh</button>':""}</div>`;
 if($("#rrefresh"))$("#rrefresh").onclick=()=>reels();
 M.querySelectorAll("button[data-play]").forEach(b=>b.onclick=async()=>{b.disabled=true;b.textContent="Loading…";
  try{const c=cred()||{},h={};if(c.session)h["X-ASKODOX-Staff-Session"]=c.session;if(c.token)h["X-ASKODOX-Staff-Token"]=c.token;if(c.bearer)h["Authorization"]="Bearer "+c.bearer;
   const r=await fetch(`/admin/cc/workspace/reels/${b.dataset.play}/file`,{headers:h});if(!r.ok)throw new Error("Could not load the reel ("+r.status+")");
   const url=URL.createObjectURL(await r.blob());$("#v_"+b.dataset.play).innerHTML=`<video src="${url}" controls playsinline style="width:100%;max-width:320px;border-radius:12px;margin-top:8px"></video>`;b.remove()}
  catch(e){toast(e.message);b.disabled=false;b.textContent="▶ Play"}});
 M.querySelectorAll("button[data-rv]").forEach(b=>b.onclick=async()=>{try{const r=await api(`/admin/cc/workspace/reels/${b.dataset.id}/review`,"POST",{action:b.dataset.rv});
  toast(r.status==="ACTIVE"?"Approved -- users ఇప్పుడు చూస్తారు":"Rejected");reels()}catch(e){toast(e.message)}})}
async function review(){const d=await api("/admin/cc/workspace/items?status=NEEDS_REVIEW");
 M.innerHTML=`<div class="card"><h3 style="margin-top:0">Waiting for review (${d.items.length})</h3>${d.items.map(i=>itemRow(i,[["approve","Approve & publish"],["reject","Send back"]])).join("")||'<p class="mut">Nothing waiting.</p>'}</div>`;bindReview()}
async function items(){const d=await api("/admin/cc/workspace/items?mine=true");
 const acts=i=>({DRAFT:[["submit",ME.can_publish?"Publish":"Submit"]],LIVE:[["pause","Pause"],["expire","Expire"]],PAUSED:ME.can_publish?[["resume","Resume"]]:[]}[i.review_status]||[]);
 M.innerHTML=`<div class="card"><h3 style="margin-top:0">My items</h3>${d.items.map(i=>itemRow(i,acts(i))).join("")||'<p class="mut">Nothing yet -- add a link.</p>'}</div>`;bindReview()}
async function tasks(){const d=await api("/admin/cc/workspace/tasks");
 const links=x=>((x.evidence||{}).links||[]).map(l=>`<div class="item"><div class="grow mut">${esc(l.url.replace(/^https:\/\/(www\.)?/,"").slice(0,60))}${l.affiliate_url?' <span class="ok">· commission link</span>':""}</div><button class="s" data-add="${esc(l.url)}" data-aff="${esc(l.affiliate_url||"")}">Add</button></div>`).join("");
 const batch=ME.can_assign?`<div class="card"><h3 style="margin-top:0">Links staff కి పంచండి</h3><p class="mut">ఒక line కి ఒక product link. Commission link ఉంటే అదే line లో space తర్వాత పెట్టండి.</p>
 <textarea id="blinks" rows="5" placeholder="https://www.meesho.com/... https://commission-link..."></textarea>
 <div class="row">${(ME.team||[]).map(m=>`<label><input type="checkbox" class="bstaff" value="${esc(m.id)}"> ${esc(m.name)}</label>`).join(" ")}</div>
 <div class="row"><label>ఒక task లో <input id="bper" type="number" value="25" min="1" max="100" style="width:70px"> links</label><button class="p" id="bgo">పంచండి</button></div><div id="bres"></div></div>`:"";
 M.innerHTML=batch+`<div class="card"><h3 style="margin-top:0">My tasks</h3>${d.items.map(t=>{const x=t.data||{};return `<div class="item"><div class="grow"><b>${esc(x.title)}</b> <span class="badge">${esc((x.priority||"normal").toUpperCase())}</span> <span class="badge">${esc(t.status)}</span>
 <div class="mut">${esc(x.why||"")}</div><div>${esc(x.expected_action||"")}</div>${x.due_at?`<div class="mut">Due ${esc(x.due_at)}</div>`:""}${links(x)}
 <div class="row" style="margin-top:6px">${t.status!=="IN_PROGRESS"?`<button class="s" data-k="start" data-id="${t.id}">Start</button>`:""}<button class="p" data-k="done" data-id="${t.id}">Done</button></div></div></div>`}).join("")||'<p class="mut">No tasks for you right now.</p>'}</div>`;
 M.querySelectorAll("button[data-k]").forEach(b=>b.onclick=async()=>{try{await api(`/admin/cc/workspace/tasks/${b.dataset.id}/${b.dataset.k}`,"POST");start()}catch(e){toast(e.message)}});
 M.querySelectorAll("button[data-add]").forEach(b=>b.onclick=()=>{PREFILL={url:b.dataset.add,type:"product"};PREFILL_AFF=b.dataset.aff||"";TAB="add";start()});
 if($("#bgo"))$("#bgo").onclick=async()=>{const rows=$("#blinks").value.split("\n").map(l=>l.trim().split(/\s+/)).filter(r=>r[0]);
  const assignees=[...M.querySelectorAll(".bstaff:checked")].map(c=>c.value);
  try{const r=await api("/admin/cc/workspace/tasks/batch-links","POST",{links:rows.map(r=>r[0]),affiliate_links:rows.map(r=>r[1]||""),assignees,per_task:+$("#bper").value||25});
   $("#bres").innerHTML=`<p class="ok">${r.links} links → ${r.tasks.length} tasks (batch ${esc(r.batch)})</p>`+r.tasks.map(t=>`<div class="mut">${esc(t.assignee)}: ${t.links} links</div>`).join("")}catch(e){toast(e.message)}}}
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
