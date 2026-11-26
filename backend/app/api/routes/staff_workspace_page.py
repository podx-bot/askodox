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
let PVID=null;
function pickVideo(input,note){const f=input.files&&input.files[0];PVID=null;if(!f){note.textContent="";return}
 const url=URL.createObjectURL(f);const v=document.createElement("video");v.preload="metadata";
 v.onloadedmetadata=()=>{const sec=v.duration;URL.revokeObjectURL(url);
  if(!isFinite(sec)||sec>60){note.textContent="✗ వీడియో 60 సెకన్ల లోపే ఉండాలి (చిన్నది ఎంచుకోండి)";input.value="";PVID=null}
  else{PVID=f;note.textContent="✓ "+Math.round(sec)+" సెకన్లు -- save చేసినప్పుడు upload అవుతుంది"}};
 v.onerror=()=>{URL.revokeObjectURL(url);note.textContent="✗ ఈ వీడియో చదవలేం (MP4 / WebM ఎంచుకోండి)";input.value="";PVID=null};
 v.src=url}
async function attachVideo(itemId,en,te,ta){if(!PVID||!itemId)return null;const fd=new FormData();
 fd.append("file",PVID,PVID.name);fd.append("description",en||"");fd.append("description_te",te||"");fd.append("description_ta",ta||"");
 return api("/admin/cc/workspace/items/"+itemId+"/video","POST",fd,true)}
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
const TABS=[["add","Add"],["studio","🎥 Studio"],["finance","💼 Finance"],["review","Review"],["items","My items"],["reels","🎬 Videos"],["tasks","Tasks"],["support","Support"],["feedback","Feedback"],["demand","Demand"],["sources","Sources"],["analytics","Stats"]];
async function start(){try{ME=await api("/admin/cc/workspace/me")}catch(e){if(e.message!=="signed out")signin(e.message);return}
 $("#who").textContent=ME.name+" · "+ME.role;$("#out").style.display="inline-block";
 const tabs=TABS.filter(([k])=>k==="finance"?(ME.item_types||[]).includes("financial_offer"):ME.sections[(k==="reels"||k==="studio")?"items":k]);if(!tabs.find(t=>t[0]===TAB))TAB=(tabs[0]||["add"])[0];
 $("#nav").innerHTML=tabs.map(([k,l])=>`<button data-t="${k}" class="${k===TAB?"on":""}">${l}${ME.counts[k]?` (${ME.counts[k]})`:""}</button>`).join("");
 $("#nav").style.display="flex";$("#nav").querySelectorAll("button").forEach(b=>b.onclick=()=>{TAB=b.dataset.t;start()});
 try{await ({add,studio,finance,review,items,reels,tasks,support,feedback,demand,sources,analytics})[TAB]()}catch(e){if(e.message!=="signed out")M.innerHTML=`<div class="card bad">${esc(e.message)}</div>`}}
$("#out").onclick=()=>{setCred(null);signin()};
const FIELDS=[["title","Title"],["price","Current price (₹)"],["mrp","Original price / MRP (₹)"],["brand","Brand"],["seller","Seller / merchant"],["category","Category"],["image_url","Main image URL"],["description","Description","ta"],["location","Location / city"],["coverage","Coverage (cities / pincodes)"],["offer_text","Offer / coupon text"],["expires_at","Offer ends (YYYY-MM-DD)"],["affiliate_url","Commission link (affiliate / deep link)"],["verified_commission_rate","Commission % (partner agreed)"],["canonical_url","Canonical URL"],["product_id","Product id (ASIN / pid)"]];
async function add(){const types=ME.item_types;M.innerHTML=`<div class="card"><div class="row"><button class="p" id="m_link">🔗 For your reference (Meesho / Amazon / Flipkart / Wishlink…)</button><button class="s" id="m_own">🏷️ Own / Brand product</button></div>
 <p class="mut" style="margin:8px 0 0">4 steps: లింక్ పెట్టండి → ఫోటోలు పెట్టండి → "ఫోటోల నుంచి నింపు" + ధర → Publish. వీడియో, DM జవాబులు, Facebook / Instagram / YouTube టెక్స్ట్ ఆటోమేటిక్‌గా తయారవుతాయి.</p></div>
 <details class="card"><summary class="mut">పాత పద్ధతి: లింక్ నుంచి పేజీ చదువు (store పేజీ ఓపెన్ అయితేనే)</summary><div id="linkcard"><h3 style="margin-top:0">Paste one link</h3>
 <div class="row"><select id="itype">${types.map(t=>`<option ${PREFILL.type===t?"selected":""}>${t}</option>`).join("")}</select></div>
 <input id="url" type="url" placeholder="https://..." value="${esc(PREFILL.url||"")}">
 <div class="row"><button class="s" id="paste">Paste</button><button class="p" id="fetch">Fetch details</button></div><div id="res"></div></div></details>
 <div class="card" id="bulkcard"><h3 style="margin-top:0">Many links</h3><textarea id="bulk" rows="4" placeholder="One link per line (up to 50)"></textarea><button class="s" id="bulkgo">Check links</button><div id="bulkres"></div></div>`;
 $("#m_own").onclick=()=>ownForm();$("#m_link").onclick=()=>affForm();
 $("#paste").onclick=async()=>{try{$("#url").value=await navigator.clipboard.readText()}catch(e){toast("Long-press the box and paste")}};
 $("#fetch").onclick=()=>fetchOne(firstLink($("#url").value),$("#itype").value);
 $("#bulkgo").onclick=async()=>{try{const d=await api("/admin/cc/workspace/import/bulk","POST",{urls:($("#bulk").value.match(/https:\/\/[^\s"'<>]+/g)||[]),item_type:$("#itype").value});
  $("#bulkres").innerHTML=d.items.map((r,i)=>`<div class="item"><div class="grow"><b>${esc((r.fields||{}).title||r.url)}</b><div class="mut">${esc((r.source||{}).name||"")} ${r.duplicates&&r.duplicates.length?`<span class="warn">· already added (#${r.duplicates[0].id})</span>`:""}${r.ok?"":` <span class="bad">${esc(r.error)}</span>`}</div></div>${r.ok&&!(r.duplicates||[]).length?`<button class="s" data-u="${esc(r.url)}">Add</button>`:""}</div>`).join("");
  $("#bulkres").querySelectorAll("button").forEach(b=>b.onclick=()=>fetchOne(b.dataset.u,$("#itype").value))}catch(e){toast(e.message)}};
 if(PREFILL.url){const u=PREFILL.url;PREFILL={};fetchOne(u,$("#itype").value)}}
// Owner 2026-11-04: paste a link -> everything fills by itself. Only Title, Price and the
// AI description are shown; the rest waits under "More details".
// The phone reads with two readers at once (up to ~50 s); PHONE_ERR says why it could not.
const READS={};let PHONE_ERR=null;window.askodoxPageRead=(id,r)=>{const f=READS[id];if(f){delete READS[id];PHONE_ERR=r&&r.ok?null:String((r&&r.error)||"no answer");f(r&&r.ok?r:null)}};
function readOnPhone(url){PHONE_ERR=null;if(!window.AskodoxPageReader)return Promise.resolve(null);
 return new Promise(res=>{const id=String(Date.now())+Math.random();READS[id]=res;
  setTimeout(()=>{if(READS[id]){delete READS[id];PHONE_ERR="timeout";res(null)}},60000);
  try{AskodoxPageReader.postMessage(JSON.stringify({id,url}))}catch(e){delete READS[id];PHONE_ERR="channel";res(null)}})}
// Commission link / % only for staff with those grants (the server refuses them otherwise).
const MYFIELDS=()=>FIELDS.filter(([k])=>(k!=="affiliate_url"||ME.can_link)&&(k!=="verified_commission_rate"||ME.can_commission));
const MAIN_FIELDS=["title","price","description","affiliate_url","verified_commission_rate"];
// Shared text ("Check this on Meesho https://...") -> just the link.
// A screenshot -> a JPEG of at most 1600 px (phones save 3-4 MB PNGs).
function shrinkShot(file){return new Promise((res,rej)=>{const img=new Image();img.onload=()=>{const k=Math.min(1,1600/Math.max(img.width,img.height));
 const c=document.createElement("canvas");c.width=Math.round(img.width*k);c.height=Math.round(img.height*k);c.getContext("2d").drawImage(img,0,0,c.width,c.height);
 URL.revokeObjectURL(img.src);res({data:c.toDataURL("image/jpeg",0.85),mime:"image/jpeg"})};img.onerror=()=>rej(new Error("Not a picture / ఇది ఫోటో కాదు"));img.src=URL.createObjectURL(file)})}
function firstLink(t){const m=String(t||"").match(/https:\/\/[^\s"'<>]+/);return m?m[0]:String(t||"").trim()}
// Owner 2026-11-20: rating / review screenshots -> a short honest summary (read on the server, nothing saved) that
// the AI video uses; the 30-second video makes itself after saving and waits in 🎬 Videos for Approve.
function reviewBlock(p){return `<label>⭐ Rating / review screenshots (optional, 4 వరకు) / రేటింగ్, రివ్యూ screenshots</label>
 <div class="row"><label class="s btn">⭐ Add screenshots<input id="${p}revshot" type="file" accept="image/*" multiple hidden></label></div><div class="mut" id="${p}revnote"></div>
 <label style="display:flex;gap:8px;align-items:center;margin:8px 0"><input type="checkbox" id="${p}aivid" style="width:auto;margin:0"> 🎬 30 సెకన్ల AI వీడియో కూడా చేయి (కావాలంటే మాత్రమే టిక్ చేయండి)</label>
 <span class="mut">AI ప్రజెంటర్ + తెలుగు వాయిస్ + రివ్యూల సారాంశం. తయారయ్యాక 🎬 Videos లో Approve చేస్తేనే users కి కనిపిస్తుంది.</span>`}
function bindReviews(p,holder){const el=$("#"+p+"revshot");if(!el)return;el.onchange=async e=>{const files=[...e.target.files].slice(0,4);if(!files.length)return;
 const note=$("#"+p+"revnote");note.textContent="⭐ రివ్యూలు చదువుతోంది…";
 try{const images=await Promise.all(files.map(shrinkShot));const r=await api("/admin/cc/workspace/reviews/read","POST",{images});holder.reviews=r.reviews||{};
  const v=holder.reviews,st=v.stars;note.innerHTML=`✓ ${v.rating?`<b>${esc(v.rating)} ★</b> `:""}${v.ratings_count?esc(v.ratings_count)+" ratings ":""}${v.reviews_count?"· "+esc(v.reviews_count)+" reviews":""}
   ${st?`<br>5★ ${st["5"]} · 4★ ${st["4"]} · 3★ ${st["3"]} · 2★ ${st["2"]} · 1★ ${st["1"]}`:""}
   ${(v.good||[]).length?`<br>👍 ${(v.good||[]).map(esc).join(", ")}`:""}${(v.bad||[]).length?`<br>⚠️ ${(v.bad||[]).map(esc).join(", ")}`:""}`}
 catch(err){note.textContent=err.message}}}
async function startAiVideo(itemId,reviews,store){try{const r=await api(`/admin/cc/workspace/items/${itemId}/ai-video`,"POST",{reviews:reviews||{},store:store||""});
 toast(`🎬 వీడియో తయారవుతోంది (${r.photos} photos, ఒక నిమిషం) -- 🎬 Videos లో చూడండి`);return r}catch(e){toast("Video: "+e.message);return null}}
// Owner 2026-11-20: affiliate product in 4 steps -- the link is never opened; name / description come from the photos;
// staff type the price; saving makes the video, the DM answers and the social texts.
const STORES=[["Meesho",/meesho|msho\./],["Amazon",/amazon|amzn\./],["Flipkart",/flipkart|fkrt\./],["Myntra",/myntra/],["AJIO",/ajio/],["Nykaa",/nykaa/],["Other",/./]];
async function affForm(){let photos=[];const RV={reviews:{}};
 M.innerHTML=`<div class="card"><h3 style="margin-top:0">🔗 For your reference</h3>
 <label>1. Commission / affiliate link *</label><div class="row"><input id="a_link" type="url" placeholder="https://..."><button class="s" id="a_paste" style="flex:0 0 90px">Paste</button></div>
 <label>Store</label><select id="a_store">${STORES.map(([n])=>`<option>${n}</option>`).join("")}</select>
 <label>2. Product photos * (store యాప్ నుంచి డౌన్‌లోడ్ చేసినవి / camera)</label><div class="thumbs" id="a_thumbs"></div>
 <div class="row"><label class="s btn">🖼️ Gallery<input id="a_gal" type="file" accept="image/*" multiple hidden></label><label class="s btn">📷 Camera<input id="a_cam" type="file" accept="image/*" capture="environment" hidden></label></div>
 ${reviewBlock("a_")}
 <div class="row" style="margin-top:10px"><button class="p" id="a_fill">✨ 3. ఫోటోల నుంచి నింపు</button></div><span class="mut" id="a_fillnote"></span>
 <label>Product name *</label><input id="a_title">
 <div class="row"><div><label>Price ₹ * (మీరే పెట్టండి)</label><input id="a_price" inputmode="decimal"></div><div><label>MRP ₹</label><input id="a_mrp" inputmode="decimal"></div></div>
 <div class="row"><div><label>Category (search కోసం)</label><input id="a_cat" placeholder="saree blouse"></div><div><label>Brand</label><input id="a_brand"></div></div>
 <label>Sizes (కామాలతో)</label><input id="a_sizes" placeholder="S, M, L, XL">
 <label>Description (రంగు, మెటీరియల్, features -- search లో ఇవే వస్తాయి)</label><textarea id="a_desc" rows="6"></textarea>
 ${ME.can_commission?`<label>Commission % (optional)</label><input id="a_rate" inputmode="decimal">`:""}
 <div id="a_err" class="bad" style="margin:8px 0"></div>
 <div class="row"><button class="s" id="a_back">← Back</button><button class="s" id="a_draft">Save draft</button><button class="p" id="a_submit">4. ${ME.can_publish?"Publish":"Submit"}</button></div></div>`;
 const thumbs=()=>{$("#a_thumbs").innerHTML=photos.length?photos.map(p=>`<img src="${esc(p)}">`).join(""):`<span class="mut">ఇంకా ఫోటోలు లేవు</span>`};thumbs();
 const store=()=>{const v=$("#a_link").value.toLowerCase();const hit=STORES.find(([n,re])=>re.test(v));if(hit&&v)$("#a_store").value=hit[0]};
 $("#a_link").oninput=store;$("#a_back").onclick=()=>add();bindReviews("a_",RV);
 $("#a_paste").onclick=async()=>{try{$("#a_link").value=firstLink(await navigator.clipboard.readText());store()}catch(e){toast("Long-press the box and paste")}};
 const addPhotos=async e=>{for(const file of e.target.files){const fd=new FormData();fd.append("file",file);
  try{const u=await api("/admin/cc/workspace/uploads","POST",fd,true);photos.push(u.url);thumbs()}catch(err){toast(err.message)}}};
 $("#a_gal").onchange=addPhotos;$("#a_cam").onchange=addPhotos;
 $("#a_fill").onclick=async()=>{if(!photos.length){$("#a_fillnote").textContent="ముందు ఫోటోలు పెట్టండి (step 2)";return}
  $("#a_fillnote").textContent="✨ ఫోటోలు చదువుతోంది…";try{const r=await api("/admin/cc/workspace/fill-from-photos","POST",{photos});const f=r.fields||{};
   if(f.title&&!$("#a_title").value.trim())$("#a_title").value=f.title;if(f.description)$("#a_desc").value=f.description;
   if(f.category&&!$("#a_cat").value.trim())$("#a_cat").value=f.category;if(f.brand&&!$("#a_brand").value.trim())$("#a_brand").value=f.brand;
   if(f.sizes&&f.sizes.length&&!$("#a_sizes").value.trim())$("#a_sizes").value=f.sizes.join(", ");
   $("#a_fillnote").textContent="✓ ఫోటోల నుంచి నిండింది -- చదివి, ధర పెట్టండి";$("#a_price").focus()}catch(e){$("#a_fillnote").textContent=e.message}};
 const num=v=>{const n=parseFloat(String(v).replace(/[^0-9.]/g,""));return isNaN(n)?null:n};
 const save=async action=>{const link=firstLink($("#a_link").value),title=$("#a_title").value.trim(),price=num($("#a_price").value);const err=$("#a_err");
  const miss=!link.startsWith("https://")?["a_link","1. https:// తో మొదలయ్యే లింక్ పెట్టండి"]:!photos.length?["a_gal","2. కనీసం ఒక్క ఫోటో పెట్టండి"]:!title?["a_title","Product name ఖాళీగా ఉంది -- \"ఫోటోల నుంచి నింపు\" నొక్కండి లేదా రాయండి"]:(action!=="draft"&&price==null)?["a_price","ధర (₹) పెట్టండి"]:null;
  if(miss){err.textContent="⚠️ "+miss[1];const el=$("#"+miss[0]);if(el&&el.focus)el.focus();if(el&&el.scrollIntoView)el.scrollIntoView({block:"center"});return}
  err.textContent="";const fields={title,original_product_url:link,images:photos,image_url:photos[0]};
  if(ME.can_link)fields.affiliate_url=link;if(price!=null)fields.price=price;if(num($("#a_mrp").value)!=null)fields.mrp=num($("#a_mrp").value);
  if($("#a_desc").value.trim())fields.description=$("#a_desc").value.trim();
  if($("#a_cat").value.trim())fields.category=$("#a_cat").value.trim();if($("#a_brand").value.trim())fields.brand=$("#a_brand").value.trim();
  const sizes=$("#a_sizes").value.split(",").map(x=>x.trim()).filter(Boolean);if(sizes.length)fields.variants=sizes;
  if($("#a_rate")&&num($("#a_rate").value)!=null)fields.verified_commission_rate=num($("#a_rate").value);
  toast("Saving… / save అవుతోంది…");
  try{const r=await api("/admin/cc/workspace/items","POST",{item_type:"product",fields,action});
   if(r.item&&action!=="draft"&&$("#a_aivid")&&$("#a_aivid").checked){await startAiVideo(r.item.id,RV.reviews,$("#a_store").value);TAB="reels";start();return}
   toast(r.review_status==="LIVE"?"Published":r.review_status==="DRAFT"?"Draft saved":"Sent for review");TAB="items";start()}catch(e){err.textContent="⚠️ "+e.message}};
 $("#a_draft").onclick=()=>save("draft");$("#a_submit").onclick=()=>save("submit")}
async function fetchOne(url,type){url=firstLink(url);const box=$("#res")||M;box.innerHTML=`<p class="mut">Reading the page… (up to a minute) / page చదువుతోంది… (ఒక నిమిషం వరకు)</p>`;
 let d,page=null;try{page=await readOnPhone(url);
  d=await api("/admin/cc/workspace/import","POST",page?{url,item_type:type,html:page.html,final_url:page.final_url}:{url,item_type:type,phone_error:PHONE_ERR})}catch(e){box.innerHTML=`<p class="bad">${esc(e.message)}</p>`;return}
 if(d.ok===false){box.innerHTML=`<p class="bad">${esc(d.error||"This link could not be read")}</p>`;return}
 const f=d.fields||{},st=d.field_status||{},dup=(d.duplicates||[]);let photos=[...new Set([...(f.images||[]),...(f.image_url?[f.image_url]:[])])].slice(0,8);
 const field=([k,l,ta])=>`<label>${l} ${st[k]==="fetched"?'<span class="ok">· from page</span>':""}</label>${ta?`<textarea id="f_${k}" rows="${k==="description"?6:3}">${esc(f[k]||"")}</textarea>`:`<input id="f_${k}" value="${esc(f[k]??"")}">`}`;
 const ok=d.status==="ok";
 box.innerHTML=`<p><span class="badge">${esc((d.source||{}).name||"Unknown source")}</span> <span class="${ok?"ok":"mut"}">${ok?"✓ Details filled -- check and save / వివరాలు నిండాయి -- చూసి save చేయండి":esc(d.note||"")}</span></p>
 ${dup.length?`<p class="warn">Already in ASKODOX: ${dup.map(x=>`#${x.id} ${esc(x.title)} (${esc(x.review_status)})`).join(", ")}</p>`:""}
 <div class="row"><label class="${ok?"s":"p"} btn" id="shotbtn">📸 Screenshot తో నింపు / Fill from screenshot<input id="shot" type="file" accept="image/*" multiple hidden></label></div><span class="mut" id="shotnote">${ok?"":"Store app లో product screenshot తీసి ఇక్కడ పెట్టండి -- పేరు, ధర, sizes నిండుతాయి."}</span>
 <label>Photos</label><div class="thumbs" id="thumbs"></div>
 <div class="row"><label class="s btn">📷 Camera<input id="photo" type="file" accept="image/*" capture="environment" hidden></label><label class="s btn">🖼️ Gallery<input id="photos" type="file" accept="image/*" multiple hidden></label></div>
 ${MYFIELDS().filter(([k])=>MAIN_FIELDS.includes(k)).map(field).join("")}
 <span class="mut" id="aidescnote"></span>
 <details style="margin:6px 0 10px"><summary class="mut">More details (optional) / మరిన్ని వివరాలు</summary>
 ${MYFIELDS().filter(([k])=>!MAIN_FIELDS.includes(k)).map(field).join("")}
 <label>Stock</label><select id="f_stock"><option>UNKNOWN</option><option ${d.suggested_stock==="IN_STOCK"?"selected":""}>IN_STOCK</option><option ${d.suggested_stock==="OUT_OF_STOCK"?"selected":""}>OUT_OF_STOCK</option></select>
 <div class="row"><button class="s" id="aidesc">✨ AI తో description మళ్లీ రాయి</button></div></details>
 ${reviewBlock("s_")}
 <label>Own video instead (optional, 60 సెకన్ల లోపు) / మీ సొంత వీడియో (ఐచ్ఛికం)</label><input type="file" id="pvid" accept="video/mp4,video/webm,video/quicktime"><span class="mut" id="vidnote"></span>
 <p class="mut">Description ఇంగ్లీష్‌లో రాస్తే చాలు -- వీడియో చూసేవారి భాషలోకి (తెలుగు, తమిళ్, హిందీ...) ఆటోమేటిక్‌గా మారుతుంది.</p>
 <div class="row" style="margin-top:10px"><button class="s" id="draft">Save draft</button><button class="p" id="submit">${ME.can_publish?"Publish":"Submit for review"}</button></div>`;
 const thumbs=()=>{$("#thumbs").innerHTML=photos.length?photos.map(p=>`<img src="${esc(p)}">`).join(""):`<span class="mut">No photos yet -- add from camera / gallery</span>`};thumbs();
 const addPhotos=async e=>{for(const file of e.target.files){const fd=new FormData();fd.append("file",file);
  try{const u=await api("/admin/cc/workspace/uploads","POST",fd,true);photos.push(u.url);thumbs()}catch(err){toast(err.message)}}};
 $("#photo").onchange=addPhotos;$("#photos").onchange=addPhotos;
 // Owner 2026-11-18: a store link that will not open -> a screenshot of the product fills the boxes (empty ones only).
 $("#shot").onchange=async e=>{const files=[...e.target.files].slice(0,3);if(!files.length)return;$("#shotnote").textContent="📸 screenshot చదువుతోంది…";
  try{const images=await Promise.all(files.map(shrinkShot));const r=await api("/admin/cc/workspace/read-screenshot","POST",{images});
   const g=r.fields||{};let n=0;if(g.variants&&g.variants.length&&!g.description)g.description="Sizes: "+g.variants.join(", ");
   ["title","price","mrp","seller","brand","category","description"].forEach(k=>{const el=$("#f_"+k);if(el&&g[k]!=null&&!el.value.trim()){el.value=g[k];n++}});
   $("#shotnote").textContent=n?`✓ ${n} boxes filled from the screenshot -- check and save / screenshot నుంచి నిండాయి -- చూసి save చేయండి`:"Boxes already filled / ఇప్పటికే నిండి ఉన్నాయి";
   if(n&&$("#f_description")&&!$("#f_description").value.trim())describe()}catch(err){$("#shotnote").textContent=err.message}};
 $("#pvid").onchange=e=>pickVideo(e.target,$("#vidnote"));const RV={reviews:{}};bindReviews("s_",RV);
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
   if(PVID&&r.item){try{await attachVideo(r.item.id,fields.description,"","")}catch(e){toast("Video: "+e.message)}}
   else if(r.item&&$("#s_aivid")&&$("#s_aivid").checked&&action!=="draft"){await startAiVideo(r.item.id,RV.reviews);TAB="reels";start();return}
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
 ${ME.can_link?`<label>Commission link (if the brand gave one)</label><input id="o_aff" type="url" placeholder="https://...">`:""}
 ${ME.can_commission?`<div class="row"><div><label>Commission %</label><input id="o_rate" inputmode="decimal" placeholder="e.g. 10"></div></div>`:""}
 <label>Offer / coupon for buyers (optional)</label><input id="o_offer" placeholder="e.g. coupon ASKO10 -- 10% off">
 ${reviewBlock("o_")}
 <label>Own video instead (optional, 60 సెకన్ల లోపు) / మీ సొంత వీడియో (ఐచ్ఛికం)</label><input type="file" id="o_pvid" accept="video/mp4,video/webm,video/quicktime"><span class="mut" id="o_vidnote"></span>
 <p class="mut">Description ఇంగ్లీష్‌లో రాస్తే చాలు -- వీడియో చూసేవారి భాషలోకి (తెలుగు, తమిళ్, హిందీ...) ఆటోమేటిక్‌గా మారుతుంది.</p>
 <div class="row" style="margin-top:10px"><button class="s" id="o_back">← Back</button><button class="s" id="o_draft">Save draft</button><button class="p" id="o_submit">${ME.can_publish?"Publish":"Submit for review"}</button></div>
 <p class="mut">Promote it to users: Command Center → Growth → Promotions (campaign with review, consent and caps). / Users కి promote: Command Center → Growth → Promotions.</p></div>`;
 const thumbs=()=>{$("#o_thumbs").innerHTML=photos.length?photos.map(p=>`<img src="${esc(p)}">`).join(""):`<span class="mut">No photos yet</span>`};thumbs();
 const addPhotos=async e=>{for(const file of e.target.files){const fd=new FormData();fd.append("file",file);
  try{const u=await api("/admin/cc/workspace/uploads","POST",fd,true);photos.push(u.url);thumbs()}catch(err){toast(err.message)}}};
 $("#o_cam").onchange=addPhotos;$("#o_gal").onchange=addPhotos;$("#o_back").onclick=()=>add();const ORV={reviews:{}};bindReviews("o_",ORV);
 $("#o_copy").onclick=async()=>{const url=firstLink($("#o_page").value);if(!url)return;toast("Reading the brand page…");
  try{const page=await readOnPhone(url);const d=await api("/admin/cc/workspace/import","POST",page?{url,item_type:"product",html:page.html,final_url:page.final_url}:{url,item_type:"product",phone_error:PHONE_ERR});
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
   if(PVID&&r.item){try{await attachVideo(r.item.id,fields.description,"","")}catch(e){toast("Video: "+e.message)}}
   else if(r.item&&$("#o_aivid")&&$("#o_aivid").checked&&action!=="draft"){await startAiVideo(r.item.id,ORV.reviews);TAB="reels";start();return}
   let msg=r.review_status==="LIVE"?"Published -- search లో photos తో వస్తుంది":r.review_status==="DRAFT"?"Draft saved":"Sent for review";
   toast(msg);TAB="items";start()}catch(e){toast(e.message)}};
 $("#o_pvid").onchange=e=>pickVideo(e.target,$("#o_vidnote"));
 $("#o_draft").onclick=()=>save("draft");$("#o_submit").onclick=()=>save("submit")}
function itemRow(i,btns,extra){return `<div class="item">${i.image_url?`<img src="${esc(i.image_url)}" alt="">`:""}<div class="grow"><b>${esc(i.title)}</b>
 <div class="mut">${esc(i.item_type)} · ${esc(i.platform_name)} · <span class="badge">${esc(i.review_status)}</span> ${i.price!=null?"₹"+esc(i.price):""} ${i.stock_status==="OUT_OF_STOCK"?'<span class="bad">out of stock</span>':""}</div>
 ${i.review_note?`<div class="mut">Note: ${esc(i.review_note)}</div>`:""}<div class="row" style="margin-top:6px">${btns.map(([a,l])=>`<button class="s" data-a="${a}" data-id="${i.id}">${l}</button>`).join("")}${extra||""}</div></div></div>`}
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
 M.innerHTML=`<div class="card"><h3 style="margin-top:0">🎬 Videos (${d.items.length})</h3>${d.items.map(r=>`<div class="item"><div class="grow"><b>${esc(r.title)}</b>
  <div class="mut">${label[r.reel_status]||esc(r.reel_status)} · <span class="badge">${esc(r.status)}</span>${r.price_shown?" · "+esc(r.price_shown):""}${r.ai?` · AI${r.voice_path&&r.voice_path!=="none"?" · voice "+esc(r.voice_path):" · no voice"}`:""}${r.reason?` · <span class="bad">${esc(r.reason)}</span>`:""}</div>
  ${(r.script||[]).length?`<details><summary class="mut">Script చూడండి</summary><ol class="mut">${r.script.map(l=>`<li>${esc(l)}</li>`).join("")}</ol></details>`:""}
  <div id="v_${esc(r.video_id)}"></div><div id="sh_${esc(r.video_id)}"></div><div class="row" style="margin-top:6px">${r.reel_status==="READY"?`<button class="s" data-play="${esc(r.video_id)}">▶ Play</button><button class="s" data-share="${esc(r.video_id)}">📤 షేర్ / DM జవాబులు</button>`:""}
  ${d.can_publish&&r.status==="PENDING_REVIEW"?`<button class="p" data-rv="approve" data-id="${esc(r.video_id)}">Approve -- users చూస్తారు</button><button class="s" data-rv="reject" data-id="${esc(r.video_id)}">Reject</button>`:""}</div></div></div>`).join("")
  ||'<p class="mut">ఇంకా వీడియోలు లేవు. Product add చేసేటప్పుడు "🎬 30 సెకన్ల AI వీడియో" tick ఉంచండి, లేదా My items లో 🎬 AI వీడియో నొక్కండి.</p>'}
  ${d.items.some(r=>r.reel_status==="MAKING")?'<button class="s" id="rrefresh">↻ Refresh</button>':""}</div>`;
 if($("#rrefresh"))$("#rrefresh").onclick=()=>reels();
 M.querySelectorAll("button[data-play]").forEach(b=>b.onclick=async()=>{b.disabled=true;b.textContent="Loading…";
  try{const c=cred()||{},h={};if(c.session)h["X-ASKODOX-Staff-Session"]=c.session;if(c.token)h["X-ASKODOX-Staff-Token"]=c.token;if(c.bearer)h["Authorization"]="Bearer "+c.bearer;
   const r=await fetch(`/admin/cc/workspace/reels/${b.dataset.play}/file`,{headers:h});if(!r.ok)throw new Error("Could not load the reel ("+r.status+")");
   const url=URL.createObjectURL(await r.blob());$("#v_"+b.dataset.play).innerHTML=`<video src="${url}" controls playsinline style="width:100%;max-width:320px;border-radius:12px;margin-top:8px"></video>`;b.remove()}
  catch(e){toast(e.message);b.disabled=false;b.textContent="▶ Play"}});
 M.querySelectorAll("button[data-share]").forEach(b=>b.onclick=async()=>{const box=$("#sh_"+b.dataset.share);
  if(box.innerHTML){box.innerHTML="";return}box.innerHTML='<p class="mut">లోడ్ అవుతోంది…</p>';
  try{const d=await api(`/admin/cc/workspace/reels/${b.dataset.share}/share`);const t=d.texts;let n=0;const blocks=[];
   const block=(label,text,rows)=>{const id="cp"+(n++);blocks.push(id);return `<label>${label}</label><textarea id="${id}" rows="${rows||5}" readonly>${esc(text)}</textarea><button class="s" data-copy="${id}">📋 కాపీ</button>`};
   const ck=d.clicks||{},cnt=s=>`${(ck[s]||{}).view||0} చూశారు / ${(ck[s]||{}).buy||0} కొనడానికి వెళ్లారు`;
   box.innerHTML=`<div class="card" style="margin-top:8px">
    ${d.public_video?`<a class="s btn" href="${esc(d.public_video)}" download target="_blank" rel="noopener">⬇️ వీడియో డౌన్‌లోడ్</a>`:'<p class="mut">⬇️ Approve చేశాక వీడియో డౌన్‌లోడ్ వస్తుంది.</p>'}
    ${block("ASKODOX లింక్ (పోస్ట్‌లో ఇదే పెట్టండి)",t.link,1)}
    <h4>Facebook</h4>${block("పోస్ట్ టెక్స్ట్",t.facebook.text,8)}<a class="s btn" href="https://www.facebook.com/" target="_blank" rel="noopener">Facebook తెరువు</a><div class="mut">${cnt("fb")}</div>
    <h4>Instagram</h4>${block("క్యాప్షన్ (Instagram లో లింక్ నొక్కలేరు -- బయోలో "+esc(t.shop)+" పెట్టండి)",t.instagram.text,8)}<a class="s btn" href="https://www.instagram.com/" target="_blank" rel="noopener">Instagram తెరువు</a><div class="mut">${cnt("ig")}</div>
    <h4>YouTube Shorts</h4>${block("టైటిల్",t.youtube.title,2)}${block("వివరణ (Shorts లో లింక్ నొక్కలేరు -- ఛానెల్ ప్రొఫైల్‌లో "+esc(t.shop)+")",t.youtube.text,8)}<a class="s btn" href="https://studio.youtube.com/" target="_blank" rel="noopener">YouTube Studio తెరువు</a><div class="mut">${cnt("yt")}</div>
    ${t.whatsapp?`<h4>WhatsApp status</h4>${block("Status టెక్స్ట్ (Meesho కి Share & Earn లింక్ మాత్రమే -- మీరే పెట్టాలి)",t.whatsapp.text,7)}<a class="s btn" href="https://wa.me/" target="_blank" rel="noopener">WhatsApp తెరువు</a>`:""}
    <h4>DM లో అడిగితే -- రెడీ జవాబులు</h4>${(d.faq||[]).map(f=>block(esc(f.q),f.a,3)).join("")||'<p class="mut">జవాబులు ఇంకా లేవు.</p>'}</div>`;
   box.querySelectorAll("button[data-copy]").forEach(c=>c.onclick=async()=>{const el=$("#"+c.dataset.copy);
    try{await navigator.clipboard.writeText(el.value)}catch(e){el.removeAttribute("readonly");el.select();document.execCommand("copy");el.setAttribute("readonly","")}
    toast("కాపీ అయింది ✓")})}catch(e){box.innerHTML=`<p class="bad">${esc(e.message)}</p>`}});
 M.querySelectorAll("button[data-rv]").forEach(b=>b.onclick=async()=>{try{const r=await api(`/admin/cc/workspace/reels/${b.dataset.id}/review`,"POST",{action:b.dataset.rv});
  toast(r.status==="ACTIVE"?"Approved -- users ఇప్పుడు చూస్తారు":"Rejected");reels()}catch(e){toast(e.message)}})}
// ASKODOX Studio (owner 2026-11-21): bought to shoot -> shot -> posted -> return. Return deadline = delivery + days.
const STG=[["bought","కొన్నాం"],["delivered","వచ్చింది"],["shot","షూట్"],["edited","ఎడిట్"],["posted","పోస్ట్"]];
const BK={today:["#fdecea","#b42318","ఈరోజే return"],tomorrow:["#fdf1e3","#a05a00","రేపు ఆఖరు"],time:["#e7f5ee","#0f7b43",""]};
let SF="all";
async function studio(){const d=await api("/admin/cc/workspace/studio");const s=d.summary;
 const chip=(k,l,n)=>`<button class="${SF===k?"p":"s"}" data-sf="${k}">${l}${n!=null?" "+n:""}</button>`;
 const show=d.purchases.filter(p=>SF==="all"?true:SF==="shoot"?["bought","delivered"].includes(p.stage):SF==="post"?["shot","edited"].includes(p.stage):SF==="return"?(p.bucket==="today"||p.bucket==="tomorrow"||["sent","picked"].includes(p.refund_status)):SF==="closed"?["returned","kept"].includes(p.stage):true);
 const tile=(n,bg,fg,l)=>`<div style="background:${bg};border-radius:12px;padding:10px;flex:1"><div style="font-size:22px;font-weight:700;color:${fg}">${n}</div><div style="font-size:12px;color:${fg}">${l}</div></div>`;
 const act={delivered:["📦 వచ్చింది","stage","delivered"],shot:["🎥 షూట్ చేశాను","stage","shot"],edited:["✂️ ఎడిట్ అయింది","stage","edited"],posted:["📤 పోస్ట్ చేశాను","stage","posted"],return:["↩️ Return పంపండి","ret",""],refund:["💰 Refund స్థితి","ret",""],keep:["📌 ఉంచుకుంటాం","keep",""]};
 const card=p=>{const b=BK[p.bucket];const left=p.days_left==null?"":p.days_left<0?"గడువు దాటింది":p.days_left===0?"ఈరోజే return":p.days_left===1?"రేపు ఆఖరు":p.days_left+" రోజులు";
  const si=["returned","kept"].includes(p.stage)?5:STG.findIndex(x=>x[0]===p.stage);const a=act[p.next_action];
  const warn=[p.warnings.includes("keep")?"⚠️ Return లేదు -- ఇది ఉంచుకోవాల్సిందే":"",p.warnings.includes("not_whitelisted")?"⚠️ Whitelisted కాని అకౌంట్":"",p.warnings.includes("no_delivery_date")?"Delivery తేదీ పెట్టండి (వచ్చాక)":""].filter(Boolean);
  return `<div class="card"><div class="row" style="align-items:flex-start"><div class="grow"><b>${esc(p.title)}</b><div class="mut">${esc(p.store)} · ₹${esc(String(p.paid))}${p.pack!=="single"?" · "+esc(p.pack)+" ("+p.pack_count+")":""} · ${p.stage==="returned"?"Return అయింది":p.stage==="kept"?"ఉంచుకున్నాం":esc((STG.find(x=>x[0]===p.stage)||["",""])[1])}${p.account_label?" · "+esc(p.account_label):""}${d.all_staff?" · "+esc(p.created_by):""}</div></div>
   ${left?`<span class="badge" style="background:${b?b[0]:"#fff"};color:${b?b[1]:"inherit"};border:0;font-weight:600">${left}</span>`:""}</div>
   <div style="display:grid;grid-template-columns:repeat(5,1fr);gap:4px;margin:8px 0">${STG.map((x,i)=>`<div title="${x[1]}" style="height:5px;border-radius:3px;background:${i<=si?"#3b4bd8":"#e3e6ee"}"></div>`).join("")}</div>
   ${warn.map(w=>`<div class="mut" style="color:#a05a00">${w}</div>`).join("")}
   ${p.return_deadline?`<div class="mut">Return ఆఖరు: ${esc(p.return_deadline)}</div>`:""}${p.refund_status?`<div class="mut">Refund: ${esc({sent:"పంపాం",picked:"Pickup అయింది",refunded:"డబ్బు వచ్చింది"}[p.refund_status])}${p.return_id?" · "+esc(p.return_id):""}</div>`:""}
   <div id="sx_${p.id}"></div>
   ${!["returned","kept"].includes(p.stage)?`<div class="row" style="margin-top:6px"><button class="s" data-vid="${p.id}">🎬 వీడియో${p.edit_status==="READY"?" ✓":p.video_file?" ·":""}</button></div><div id="sv_${p.id}"></div>`:""}
   ${a?`<div class="row" style="margin-top:6px"><button class="${p.bucket==="today"?"p":"s"}" data-sa="${a[1]}" data-st="${a[2]}" data-id="${p.id}">${a[0]}</button>${a[1]!=="keep"&&!["sent","picked"].includes(p.refund_status)?`<button class="s" data-sa="keep" data-id="${p.id}">📌 ఉంచుకుంటాం</button>`:""}</div>`:""}</div>`};
 M.innerHTML=`<div class="card"><h3 style="margin:0 0 6px">🎥 Studio</h3><div class="mut">కొన్నాం → వచ్చింది → షూట్ → ఎడిట్ → పోస్ట్ → Return</div>
  <div class="row" style="margin-top:10px;gap:8px">${tile(s.today,"#fdecea","#b42318","ఈరోజే return")}${tile(s.tomorrow,"#fdf1e3","#a05a00","రేపు ఆఖరు")}${tile(s.time,"#e7f5ee","#0f7b43","సమయం ఉంది")}</div>
  <button class="p" id="st_new" style="width:100%;margin-top:10px">＋ కొత్త ప్రోడక్ట్ కొన్నాను</button>
  <div class="row" style="margin-top:8px"><button class="s" id="st_money">💰 లెక్కలు</button><button class="s" id="st_unlock">🔓 Unlock</button><button class="s" id="st_yt">▶️ YouTube</button></div>
  <div class="row" style="margin-top:10px;flex-wrap:wrap">${chip("all","అన్నీ",s.open)}${chip("shoot","షూట్ కావాలి",s.need_shoot)}${chip("post","పోస్ట్",s.need_post)}${chip("return","Return",null)}${chip("closed","ముగిసినవి",null)}</div>
  ${d.all_staff?`<div class="mut" style="margin-top:6px">ఖర్చు (ఉంచుకున్నవి + return ఫీజు): ₹${esc(String(s.spent))}</div>`:""}</div>
  <div id="st_form"></div>${show.map(card).join("")||'<p class="mut">ఇక్కడ ఏమీ లేదు.</p>'}
  ${d.all_staff?`<div class="card"><h4 style="margin-top:0">కొనే అకౌంట్లు (whitelisted?)</h4>${d.accounts.map(a=>`<div class="mut">${esc(a.store)} · ${esc(a.label)} · ${a.whitelisted?"✅ whitelisted":"⚠️ కాదు"}</div>`).join("")||'<p class="mut">ఇంకా లేవు</p>'}
   <div class="row"><select id="ac_store">${d.stores.map(x=>`<option>${esc(x)}</option>`).join("")}</select><input id="ac_label" placeholder="పేరు / నంబర్ చివరి 4"><label style="display:flex;gap:6px;align-items:center"><input type="checkbox" id="ac_wl" style="width:auto;margin:0"> whitelisted</label><button class="s" id="ac_save">Save</button></div></div>`:""}`;
 M.querySelectorAll("button[data-sf]").forEach(b=>b.onclick=()=>{SF=b.dataset.sf;studio()});
 M.querySelectorAll("button[data-vid]").forEach(b=>b.onclick=()=>{const box=$("#sv_"+b.dataset.vid);if(box.innerHTML){box.innerHTML="";return}studioVideo(b.dataset.vid)});
 if($("#ac_save"))$("#ac_save").onclick=async()=>{try{await api("/admin/cc/workspace/studio/accounts","POST",{store:$("#ac_store").value,label:$("#ac_label").value,whitelisted:$("#ac_wl").checked});toast("Saved");studio()}catch(e){toast(e.message)}};
 $("#st_new").onclick=()=>buyForm(d);$("#st_money").onclick=()=>studioMoney();$("#st_unlock").onclick=()=>studioUnlocks();$("#st_yt").onclick=()=>studioYouTube();
 M.querySelectorAll("button[data-sa]").forEach(b=>b.onclick=async()=>{const id=b.dataset.id,box=$("#sx_"+id);
  if(b.dataset.sa==="stage"){if(b.dataset.st==="delivered"){box.innerHTML=`<label>Delivery తేదీ</label><input type="date" id="dv_${id}" value="${d.today}"><button class="p" id="dvok_${id}">Save</button>`;
    $("#dvok_"+id).onclick=async()=>{try{await api(`/admin/cc/workspace/studio/purchases/${id}/stage`,"POST",{stage:"delivered",delivery_date:$("#dv_"+id).value});studio()}catch(e){toast(e.message)}};return}
   try{await api(`/admin/cc/workspace/studio/purchases/${id}/stage`,"POST",{stage:b.dataset.st});toast("✓");studio()}catch(e){toast(e.message)}return}
  if(b.dataset.sa==="keep"){box.innerHTML=`<label>ఎందుకు ఉంచుకుంటాం?</label><select id="kp_${id}"><option value="studio">స్టూడియో కోసం</option><option value="giveaway">Giveaway</option><option value="no_return">Return లేదు / exchange మాత్రమే</option><option value="late">గడువు దాటింది</option></select><button class="p" id="kpok_${id}">ఉంచుకుంటాం -- ఖర్చులో లెక్క</button>`;
   $("#kpok_"+id).onclick=async()=>{try{await api(`/admin/cc/workspace/studio/purchases/${id}/keep`,"POST",{reason:$("#kp_"+id).value});studio()}catch(e){toast(e.message)}};return}
  const p=d.purchases.find(x=>String(x.id)===id)||{};
  box.innerHTML=`<div class="mut">${esc(p.store)} యాప్ → My Orders → ఈ ఆర్డర్ → Return. తర్వాత ఇక్కడ రాయండి.</div>
   <label>Return ID</label><input id="rt_id_${id}" value="${esc(p.return_id||"")}" placeholder="RT-…"><div class="row"><div><label>Pickup తేదీ</label><input type="date" id="rt_pk_${id}" value="${esc(p.pickup_date||"")}"></div><div><label>Return ఫీజు ₹ ${p.store==="Flipkart"?"(₹30 వరకు)":""}</label><input id="rt_fee_${id}" inputmode="decimal" value="${p.return_fee||""}"></div></div>
   <label>Refund స్థితి</label><select id="rt_st_${id}"><option value="sent">పంపాం</option><option value="picked" ${p.refund_status==="picked"?"selected":""}>Pickup అయింది</option><option value="refunded">డబ్బు వచ్చింది</option></select>
   <button class="p" id="rtok_${id}">Save</button>`;
  $("#rtok_"+id).onclick=async()=>{try{await api(`/admin/cc/workspace/studio/purchases/${id}/return`,"POST",{return_id:$("#rt_id_"+id).value,pickup_date:$("#rt_pk_"+id).value,fee:$("#rt_fee_"+id).value,refund_status:$("#rt_st_"+id).value});toast("✓");studio()}catch(e){toast(e.message)}}})}
// Studio round 2: shoot -> ASKODOX edit -> checklist -> publish -> posts (owner 2026-11-21)
async function studioVideo(id){const box=$("#sv_"+id);let p;try{p=(await api(`/admin/cc/workspace/studio/purchases/${id}`)).purchase}catch(e){box.innerHTML=`<div class="bad">${esc(e.message)}</div>`;return}
 const op=p.edit_options||{},ck=p.checklist,cap=p.captions;let n=0;
 const block=(label,text,rows)=>{const bid="sc"+id+"_"+(n++);return `<label>${label}</label><textarea id="${bid}" rows="${rows||5}" readonly>${esc(text)}</textarea><button class="s" data-scopy="${bid}">📋 కాపీ</button>`};
 const posts=p.posts||{},pf=[["instagram","Instagram","https://www.instagram.com/"],["facebook","Facebook","https://www.facebook.com/"],["youtube","YouTube Shorts","https://studio.youtube.com/"],["whatsapp","WhatsApp status","https://wa.me/"]];
 const ticks=ck.items.filter(i=>i.check==="tick");
 box.innerHTML=`<div class="card" style="margin-top:8px;background:#f6f7fb">
  <h4 style="margin-top:0">1. షూట్ (${esc(p.tips.kind)})</h4><ul style="margin:0 0 6px 18px;padding:0">${[...p.tips.tips,...p.tips.common].map(t=>`<li class="mut">${esc(t)}</li>`).join("")}</ul>
  ${p.video_url?`<video data-auth="${esc(p.video_url)}" controls playsinline style="width:100%;max-height:360px;background:#000;border-radius:10px"></video><div class="mut">${p.video_seconds} సెకన్లు · మళ్లీ షూట్ చేస్తే కొత్తది upload చేయండి</div>`:""}
  <label>📱 ఫోన్ వీడియో (నిలువు, 60 సెకన్ల లోపు)</label><input type="file" id="svf_${id}" accept="video/*"><div id="svu_${id}" class="mut"></div>
  <h4>2. ఈరోజు ధర + checklist</h4>
  <label>ఈరోజు ${esc(p.store)} యాప్‌లో ఉన్న ధర ₹ (వీడియోలో ఇదే వస్తుంది)</label><input id="svp_${id}" inputmode="decimal" value="${p.show_price||""}">
  ${ticks.map(t=>`<label style="display:flex;gap:8px;align-items:center"><input type="checkbox" class="svt_${id}" data-k="${esc(t.id)}" ${t.ok?"checked":""} style="width:auto;margin:0"> ${esc(t.label)}</label>`).join("")}
  <button class="s" id="svc_${id}">Save</button>
  <div style="margin-top:6px">${ck.items.map(i=>`<div class="mut">${i.ok?"✅":"❌"} ${esc(i.label)}</div>`).join("")}</div>
  <h4>3. ASKODOX ఎడిట్</h4>
  <div class="row"><div><label>వాయిస్</label><select id="svv_${id}">${[["female","ఆడ"],["male","మగ"],["none","వాయిస్ వద్దు"]].map(([k,l])=>`<option value="${k}" ${op.voice===k?"selected":""}>${l}</option>`).join("")}</select></div>
   <div><label>భాష</label><select id="svl_${id}">${[["te","తెలుగు"],["hi","हिंदी"],["en","English"]].map(([k,l])=>`<option value="${k}" ${op.language===k?"selected":""}>${l}</option>`).join("")}</select></div></div>
  <label style="display:flex;gap:8px;align-items:center"><input type="checkbox" id="svpr_${id}" ${op.presenter===""?"":"checked"} style="width:auto;margin:0"> బొమ్మ గైడ్ (presenter) చూపించు</label>
  <label>మీ మాట (ఐచ్ఛికం -- నిజమైనదే, హామీలు వద్దు)</label><input id="svo_${id}" maxlength="200" value="${esc(op.line||"")}" placeholder="ఉదా. పట్టీల మీద చిన్న మువ్వలు ఉన్నాయి">
  <div class="mut">వాయిస్: ${p.script.map(l=>esc(l.text)).join(" ")}</div>
  <button class="p" id="sve_${id}" ${p.edit_status==="MAKING"?"disabled":""}>${p.edit_status==="MAKING"?"⏳ తయారవుతోంది…":p.edit_status==="READY"?"✂️ మళ్లీ ఎడిట్":"✂️ ASKODOX ఎడిట్"}</button>
  ${p.edit_status==="FAILED"?`<div class="bad">ఎడిట్ కాలేదు (${esc(p.edit_reason)}). మళ్లీ ప్రయత్నించండి.</div>`:""}${p.edit_status==="PRICE_CHANGED"?`<div class="bad">ధర మారింది -- మళ్లీ ఎడిట్ చేయండి (ధర లైన్ మాత్రమే కొత్తగా రికార్డ్ అవుతుంది)</div>`:""}
  ${p.edited_url&&p.edit_status==="READY"?`<video data-auth="${esc(p.edited_url)}" controls playsinline style="width:100%;max-height:420px;background:#000;border-radius:10px;margin-top:6px"></video>`:""}
  ${p.download_url?`<a class="s btn" href="${esc(p.download_url)}" download target="_blank" rel="noopener">⬇️ వీడియో డౌన్‌లోడ్</a>`:p.edit_status==="READY"?'<div class="mut">⬇️ Publish అయ్యాక డౌన్‌లోడ్ లింక్ వస్తుంది</div>':""}
  <h4>4. Publish</h4><div class="bad" id="svpe_${id}"></div><button class="p" id="svpub_${id}">${p.published_at?"✅ Publish అయింది":"🚀 Publish"}</button>
  ${p.published_at?`<h4>5. షేర్ + పోస్ట్ లింక్</h4>${pf.map(([k,l,u])=>`<div style="margin-top:8px"><b>${l}</b>${k==="youtube"?block("టైటిల్",cap.youtube.title,2):""}${block("టెక్స్ట్",cap[k].text,6)}<a class="s btn" href="${u}" target="_blank" rel="noopener">${l} తెరువు</a>
    <div class="row"><input id="svpl_${id}_${k}" placeholder="${k==="whatsapp"?"(ఐచ్ఛికం)":"పోస్ట్ లింక్ https://…"}" value="${esc((posts[k]||{}).url||"")}"><button class="s" data-post="${k}">${posts[k]?"✅":"పోస్ట్ చేశాను"}</button></div>${k==="youtube"&&ME.can_publish&&!posts[k]?`<div class="row"><select id="svyp_${id}"><option value="private">Private</option><option value="unlisted">Unlisted</option><option value="public">Public</option></select><button class="p" id="svyt_${id}">▶️ ASKODOX channel కి పంపు</button></div><div class="bad" id="svye_${id}"></div>`:""}</div>`).join("")}`:""}
 </div>`;
 box.querySelectorAll("video[data-auth]").forEach(async v=>{try{const c=cred()||{},h={};if(c.session)h["X-ASKODOX-Staff-Session"]=c.session;if(c.token)h["X-ASKODOX-Staff-Token"]=c.token;if(c.bearer)h["Authorization"]="Bearer "+c.bearer;
  const r=await fetch(v.dataset.auth,{headers:h});if(r.ok)v.src=URL.createObjectURL(await r.blob())}catch(e){}});
 box.querySelectorAll("button[data-scopy]").forEach(b=>b.onclick=()=>{const t=$("#"+b.dataset.scopy);t.select();try{navigator.clipboard.writeText(t.value)}catch(e){document.execCommand("copy")}toast("కాపీ అయింది")});
 $("#svf_"+id).onchange=async e=>{const f=e.target.files[0];if(!f)return;const v=document.createElement("video");v.preload="metadata";
  const ok=await new Promise(r=>{v.onloadedmetadata=()=>r(v.duration<=61&&v.videoHeight>=v.videoWidth);v.onerror=()=>r(true);v.src=URL.createObjectURL(f)});
  if(!ok){$("#svu_"+id).textContent="⚠️ నిలువుగా, 60 సెకన్ల లోపు వీడియో కావాలి";return}
  $("#svu_"+id).textContent="⏳ upload అవుతోంది…";const fd=new FormData();fd.append("file",f);
  try{await api(`/admin/cc/workspace/studio/purchases/${id}/video`,"POST",fd,true);toast("వీడియో వచ్చింది ✓");studioVideo(id)}catch(e2){$("#svu_"+id).textContent="⚠️ "+e2.message}};
 $("#svc_"+id).onclick=async()=>{const t={};box.querySelectorAll(".svt_"+id).forEach(x=>t[x.dataset.k]=x.checked);
  try{await api(`/admin/cc/workspace/studio/purchases/${id}/checks`,"POST",{ticks:t,show_price:$("#svp_"+id).value});toast("Saved ✓");studioVideo(id)}catch(e){toast(e.message)}};
 $("#sve_"+id).onclick=async()=>{try{await api(`/admin/cc/workspace/studio/purchases/${id}/edit`,"POST",{voice:$("#svv_"+id).value,language:$("#svl_"+id).value,presenter:$("#svpr_"+id).checked,line:$("#svo_"+id).value});
  toast("✂️ తయారవుతోంది…");const poll=async k=>{const q=(await api(`/admin/cc/workspace/studio/purchases/${id}`)).purchase;if(q.edit_status==="MAKING"&&k<60){setTimeout(()=>poll(k+1),5000);return}studioVideo(id)};poll(0)}catch(e){toast(e.message)}};
 $("#svpub_"+id).onclick=async()=>{if(p.published_at)return;try{await api(`/admin/cc/workspace/studio/purchases/${id}/publish`,"POST");toast("🚀 Publish ✓");studioVideo(id)}catch(e){$("#svpe_"+id).textContent="⚠️ "+e.message}};
 const ytb=$("#svyt_"+id);if(ytb)ytb.onclick=async()=>{ytb.disabled=true;ytb.textContent="⏳ పంపుతోంది…";try{await api(`/admin/cc/workspace/studio/purchases/${id}/youtube`,"POST",{privacy:$("#svyp_"+id).value});toast("▶️ YouTube ✓");studioVideo(id)}catch(e){ytb.disabled=false;ytb.textContent="▶️ ASKODOX channel కి పంపు";$("#svye_"+id).textContent="⚠️ "+e.message}};
 box.querySelectorAll("button[data-post]").forEach(b=>b.onclick=async()=>{const k=b.dataset.post;
  try{await api(`/admin/cc/workspace/studio/purchases/${id}/posted`,"POST",{platform:k,url:$(`#svpl_${id}_${k}`).value.trim()});toast("✓");studioVideo(id)}catch(e){toast(e.message)}})}
// ASKODOX's own YouTube channel: connect once (publisher), then a published Studio video goes there in one tap.
async function studioYouTube(){const box=$("#st_form");let d;try{d=await api("/admin/cc/workspace/youtube")}catch(e){box.innerHTML=`<div class="card bad">${esc(e.message)}</div>`;return}
 box.innerHTML=`<div class="card"><h3 style="margin-top:0">▶️ ASKODOX YouTube channel</h3>
  ${d.connected?`<div>✅ Connect అయింది: <b>${esc(d.channel_title)}</b></div>`:`<div class="mut">${d.configured?"ఇంకా connect కాలేదు.":"Railway లో YOUTUBE_OAUTH_CLIENT_ID / SECRET పెట్టాలి."}</div>`}
  <div class="mut" style="margin-top:6px">ASKODOX సొంత channel మాత్రమే. Studio లో Publish అయిన వీడియోలు ఇక్కడి నుంచి channel కి వెళ్తాయి. YouTube audit అయ్యే వరకు అవి Private గానే ఉంటాయి.</div>
  <div class="bad" id="yt_err"></div>
  ${ME.can_publish?`<div class="row" style="margin-top:8px">${d.connected?'<button class="s" id="yt_off">Disconnect</button>':""}<button class="p" id="yt_on" ${d.configured?"":"disabled"}>${d.connected?"మళ్లీ Connect":"Google తో Connect"}</button></div>`:""}
  ${d.uploads.length?`<h4>పంపిన వీడియోలు</h4>${d.uploads.map(u=>`<div style="border-top:1px solid var(--line);padding:6px 0"><a href="${esc(u.url)}" target="_blank" rel="noopener">${esc(u.url)}</a> <span class="mut">${esc(u.privacy)} · ${esc(u.created_at.slice(0,10))}</span></div>`).join("")}`:""}</div>`;
 const on=$("#yt_on");if(on)on.onclick=async()=>{try{const r=await api("/admin/cc/workspace/youtube/connect","POST");$("#yt_err").innerHTML=`<a class="p btn" href="${esc(r.url)}" target="_blank" rel="noopener">Google sign-in తెరువు (${r.minutes} ని.)</a><div class="mut">Google ఈ sign-in ని Chrome లోనే ఒప్పుకుంటుంది -- app లోపల తెరుచుకోకపోతే లింక్ ని నొక్కి పట్టి Chrome లో తెరవండి.</div>`}catch(e){$("#yt_err").textContent="⚠️ "+e.message}};
 const off=$("#yt_off");if(off)off.onclick=async()=>{try{await api("/admin/cc/workspace/youtube/disconnect","POST");toast("Disconnect ✓");studioYouTube()}catch(e){$("#yt_err").textContent="⚠️ "+e.message}}}
// Studio round 3: commission typed from the dashboards (no API), month totals, best kinds, unlock progress.
const RS=v=>"₹"+Number(v||0).toLocaleString("en-IN",{maximumFractionDigits:2});
async function studioMoney(month){const box=$("#st_form");let d;try{d=await api("/admin/cc/workspace/studio/money"+(month?"?month="+encodeURIComponent(month):""))}catch(e){box.innerHTML=`<div class="card bad">${esc(e.message)}</div>`;return}
 const t=d.totals;
 box.innerHTML=`<div class="card"><div class="row"><h4 class="grow" style="margin:0">💰 లెక్కలు</h4><input type="month" id="mn_m" value="${esc(d.month)}" style="width:auto"><button class="s" id="mn_x">✕</button></div>
  <div class="row" style="gap:8px;margin-top:8px;flex-wrap:wrap">${[["Confirm కమిషన్",t.confirmed,"#0f7b43"],["Pending",t.pending,"#a05a00"],["ఖర్చు",t.cost,"#b42318"],["లాభం",t.profit,t.profit<0?"#b42318":"#0f7b43"]].map(([l,v,c])=>`<div style="flex:1;min-width:120px;background:#fff;border:1px solid var(--line);border-radius:12px;padding:10px"><div style="font-size:20px;font-weight:700;color:${c}">${RS(v)}</div><div class="mut">${l}</div></div>`).join("")}</div>
  <div class="mut" style="margin-top:6px">ఆర్డర్లు ${t.orders} · returns ${t.returns}${t.stuck?` · refund రావాల్సింది ${RS(t.stuck)}`:""}${d.last_entry?` · చివరి entry ${esc(d.last_entry.slice(0,10))}`:""}</div>
  <div class="mut">ఖర్చు = ఉంచుకున్నవి + return ఫీజు + కొత్త వాయిస్ లైన్లు. ASKODOX పెట్టుబడి కలపలేదు. కమిషన్ owner ఖాతాకే.</div>
  ${d.best_kinds.length?`<h4>బాగా అమ్ముడయ్యే రకాలు</h4>${d.best_kinds.slice(0,6).map(k=>`<div class="mut">${esc(k.kind)} -- ${k.orders} ఆర్డర్లు · ${RS(k.confirmed)} · ${k.products} ప్రోడక్ట్‌లు</div>`).join("")}`:""}
  <h4>ప్రోడక్ట్ వారీగా</h4>${d.products.map(p=>`<div style="border-top:1px solid var(--line);padding:6px 0"><b>${esc(p.title)}</b> <span class="mut">${esc(p.store)}${d.all_staff?" · "+esc(p.created_by):""}</span>
   <div class="mut">ఖర్చు ${RS(p.cost)} · ఆర్డర్లు ${p.orders} · returns ${p.returns} · confirm ${RS(p.confirmed)} · pending ${RS(p.pending)} · లాభం ${RS(p.profit)}</div></div>`).join("")||'<p class="mut">ఈ నెల ఏమీ లేదు</p>'}
  ${d.can_enter?`<h4>Dashboard నుంచి రాయండి (Wishlink / Meesho కి API లేదు)</h4>
   <label>ప్రోడక్ట్</label><select id="mn_p"><option value="0">అన్నీ కలిపి (ప్రోడక్ట్ వారీగా కాదు)</option>${d.products.map(p=>`<option value="${p.id}">${esc(p.title.slice(0,50))}</option>`).join("")}</select>
   <div class="row"><div><label>Source</label><select id="mn_s">${d.sources.map(x=>`<option>${esc(x)}</option>`).join("")}</select></div><div><label>ఆర్డర్లు</label><input id="mn_o" inputmode="numeric" value="0"></div><div><label>Returns</label><input id="mn_r" inputmode="numeric" value="0"></div></div>
   <div class="row"><div><label>Confirm కమిషన్ ₹</label><input id="mn_c" inputmode="decimal"></div><div><label>Pending ₹</label><input id="mn_pe" inputmode="decimal"></div></div>
   <label>Note</label><input id="mn_n" maxlength="200"><div class="mut">అదే నెల, అదే source మళ్లీ రాస్తే పాతది మారుతుంది.</div><div class="bad" id="mn_e"></div><button class="p" id="mn_save">Save</button>`:'<p class="mut">కమిషన్ owner మాత్రమే రాస్తారు.</p>'}</div>`;
 $("#mn_x").onclick=()=>{box.innerHTML=""};$("#mn_m").onchange=()=>studioMoney($("#mn_m").value);
 if($("#mn_save"))$("#mn_save").onclick=async()=>{try{await api("/admin/cc/workspace/studio/earnings","POST",{purchase_id:+$("#mn_p").value,source:$("#mn_s").value,month:d.month,orders:+($("#mn_o").value||0),returns:+($("#mn_r").value||0),confirmed:$("#mn_c").value,pending:$("#mn_pe").value,note:$("#mn_n").value});toast("Saved ✓");studioMoney(d.month)}catch(e){$("#mn_e").textContent="⚠️ "+e.message}};
 box.scrollIntoView&&box.scrollIntoView({block:"start"})}
async function studioUnlocks(){const box=$("#st_form");let d;try{d=await api("/admin/cc/workspace/studio/unlocks")}catch(e){box.innerHTML=`<div class="card bad">${esc(e.message)}</div>`;return}
 box.innerHTML=`<div class="card"><div class="row"><h4 class="grow" style="margin:0">🔓 Unlock progress</h4><button class="s" id="ul_x">✕</button></div>
  ${d.unlocks.map(u=>`<div style="border-top:1px solid var(--line);padding:8px 0"><b>${u.done?"✅ ":""}${esc(u.label)}</b>
   <div style="height:8px;background:#e3e6ee;border-radius:4px;margin:6px 0"><div style="height:8px;width:${u.percent}%;background:${u.done?"#0f7b43":"#3b4bd8"};border-radius:4px"></div></div>
   <div class="mut">${u.kind==="yes"?(u.value>=1?"అవును":"ఇంకా కాదు"):u.kind==="rupees"?RS(u.value)+" / "+RS(u.target):u.value+" / "+u.target}${u.hint?" · "+esc(u.hint):""}${u.updated_at?" · "+esc(u.updated_at.slice(0,10)):""}</div>
   ${d.can_edit?`<div class="row">${u.kind==="yes"?`<select id="ul_${u.key}"><option value="0">ఇంకా కాదు</option><option value="1" ${u.value>=1?"selected":""}>అవును</option></select>`:`<input id="ul_${u.key}" inputmode="decimal" value="${u.value}">`}<button class="s" data-ul="${u.key}">Save</button></div>`:""}</div>`).join("")}</div>`;
 $("#ul_x").onclick=()=>{box.innerHTML=""};
 box.querySelectorAll("button[data-ul]").forEach(b=>b.onclick=async()=>{try{await api("/admin/cc/workspace/studio/unlocks","POST",{key:b.dataset.ul,value:$("#ul_"+b.dataset.ul).value});toast("Saved ✓");studioUnlocks()}catch(e){toast(e.message)}});
 box.scrollIntoView&&box.scrollIntoView({block:"start"})}
function buyForm(d){let store="Meesho",opt="return";const box=$("#st_form");
 const accts=()=>d.accounts.filter(a=>a.store===store);
 const draw=()=>{box.innerHTML=`<div class="card"><h4 style="margin-top:0">కొత్త కొనుగోలు</h4>
  <label>ఏ store లో కొన్నాం?</label><div class="row" style="flex-wrap:wrap">${d.stores.map(x=>`<button class="${x===store?"p":"s"}" data-bs="${esc(x)}">${esc(x)}</button>`).join("")}</div>
  <label>కొన్న అకౌంట్</label><select id="bf_acct"><option value="">-- ఎంచుకోండి --</option>${accts().map(a=>`<option value="${a.id}" data-wl="${a.whitelisted}">${esc(a.label)}${a.whitelisted?" ✅":" ⚠️"}</option>`).join("")}</select><div id="bf_wl" class="mut"></div>
  <label>ప్రోడక్ట్ పేరు *</label><input id="bf_title">
  <div class="row"><div><label>చెల్లించిన ధర ₹</label><input id="bf_paid" inputmode="decimal"></div><div><label>ప్యాక్</label><select id="bf_pack"><option value="single">1</option><option value="pair">జత</option><option value="combo">Combo</option></select></div></div>
  <div class="row"><div><label>ఆర్డర్ తేదీ</label><input type="date" id="bf_od" value="${d.today}"></div><div><label>Delivery తేదీ</label><input type="date" id="bf_dd"></div></div>
  <label>ప్రోడక్ట్ పేజీలో Return ఆప్షన్</label><div class="row">${[["return","Return ఉంది"],["exchange","Exchange మాత్రమే"],["none","Return లేదు"]].map(([k,l])=>`<button class="${k===opt?"p":"s"}" data-bo="${k}">${l}</button>`).join("")}</div>
  ${opt==="return"?`<label>Return రోజులు (పేజీలో ఉన్నది)</label><input id="bf_days" inputmode="numeric" value="7"><div class="mut" id="bf_dl"></div>`:`<div class="bad">⚠️ ఇది ఉంచుకోవాల్సిందే -- return కాదు</div>`}
  <label>Affiliate లింక్ (Wishlink / Creator Club) -- Instagram / Facebook / YouTube కి</label><input id="bf_aff" type="url" placeholder="https://...">
  ${store==="Meesho"?`<label>Meesho Share &amp; Earn లింక్ -- WhatsApp కి మాత్రమే</label><input id="bf_se" type="url" placeholder="https://...">`:""}
  <div class="bad" id="bf_err"></div><div class="row"><button class="s" id="bf_cancel">Cancel</button><button class="p" id="bf_save">Save · షూట్ లిస్ట్‌లో పెట్టు</button></div>
  <div class="mut">Return గడువుకి 1 రోజు ముందు, గడువు రోజు ఉదయం push reminder వస్తుంది.</div></div>`;
  box.querySelectorAll("button[data-bs]").forEach(b=>b.onclick=()=>{store=b.dataset.bs;draw()});
  box.querySelectorAll("button[data-bo]").forEach(b=>b.onclick=()=>{opt=b.dataset.bo;draw()});
  const wl=()=>{const o=$("#bf_acct").selectedOptions[0];$("#bf_wl").textContent=!o||!o.value?"":o.dataset.wl==="1"?"✅ Whitelisted అకౌంట్":"⚠️ Whitelisted కాని అకౌంట్ -- return / payout రక్షణ ఉండకపోవచ్చు"};$("#bf_acct").onchange=wl;
  const dl=()=>{if(!$("#bf_dl"))return;const dd=$("#bf_dd").value,n=parseInt($("#bf_days").value||"0");if(!dd||!n){$("#bf_dl").textContent="Delivery తేదీ పెడితే return ఆఖరు తేదీ ఆటోమేటిక్‌గా వస్తుంది";return}
   const t=new Date(dd+"T00:00:00");t.setDate(t.getDate()+n);$("#bf_dl").textContent="Return ఆఖరు తేదీ: "+t.toISOString().slice(0,10)};
  $("#bf_dd").onchange=dl;if($("#bf_days"))$("#bf_days").oninput=dl;dl();
  $("#bf_cancel").onclick=()=>{box.innerHTML=""};
  $("#bf_save").onclick=async()=>{const body={title:$("#bf_title").value.trim(),store,account_id:$("#bf_acct").value?+$("#bf_acct").value:null,paid:$("#bf_paid").value,pack:$("#bf_pack").value,
   order_date:$("#bf_od").value,delivery_date:$("#bf_dd").value,return_option:opt,return_days:opt==="return"?parseInt($("#bf_days").value||"0"):0,affiliate_link:$("#bf_aff").value.trim(),share_earn_link:$("#bf_se")?$("#bf_se").value.trim():""};
   if(!body.title){$("#bf_err").textContent="⚠️ ప్రోడక్ట్ పేరు పెట్టండి";return}
   try{await api("/admin/cc/workspace/studio/purchases","POST",body);toast("Saved ✓");SF="all";studio()}catch(e){$("#bf_err").textContent="⚠️ "+e.message}}};
 draw();box.scrollIntoView&&box.scrollIntoView({block:"start"})}
// Finance items (owner 2026-11-25): the company's own PDF / photos -> AI points + answers with page numbers -> staff
// check -> customers ask; "not in the document" -> the customer may ask for a call (their yes first).
const FKINDS=[["insurance","🛡️ Insurance"],["loan","🏦 Loan"],["credit_card","💳 Credit card"],["other","Other"]];let FVIEW="items";
async function finance(){const top=`<div class="card"><div class="row"><button class="${FVIEW==="items"?"p":"s"}" id="fn_items">📄 Items</button><button class="${FVIEW==="calls"?"p":"s"}" id="fn_calls">📞 Call backs</button></div></div>`;
 if(FVIEW==="calls"){const d=await api("/admin/cc/workspace/finance-callbacks");const done=await api("/admin/cc/workspace/finance-callbacks?status=done");
  const when={now:"ఇప్పుడే",evening:"సాయంత్రం",tomorrow:"రేపు"};
  M.innerHTML=top+`<div class="card"><h3 style="margin-top:0">📞 కాల్ చేయాల్సినవి (${d.callbacks.length})</h3><p class="mut">Customer "అవును, కాల్ చేయండి" అన్నవే ఇక్కడ ఉంటాయి. నంబర్ "నంబర్ చూపించు" నొక్కినప్పుడే కనిపిస్తుంది (ఎవరు చూశారో record అవుతుంది). సలహా ఇవ్వకండి -- కంపెనీ చెప్పిందే చెప్పండి.</p>
  ${d.callbacks.map(c=>`<div class="item"><div class="grow"><b>${esc(c.title)}</b><div class="mut">${esc(c.customer)} · ${esc(when[c.when]||c.when)}</div><div>❓ ${esc(c.question||"(ప్రశ్న రాయలేదు)")}</div>
   <div class="row"><button class="s" data-fnum="${c.id}">📱 నంబర్ చూపించు</button><span id="fnum_${c.id}"></span></div>
   <label>కాల్‌లో చెప్పిన జవాబు (రాస్తే తర్వాతి customer కి యాప్‌లోనే వస్తుంది)</label><textarea id="fans_${c.id}" rows="2"></textarea>
   <div class="row"><select id="fout_${c.id}"><option value="answered">జవాబు చెప్పాం</option><option value="deal">తీసుకుంటానన్నారు</option><option value="not_interested">వద్దన్నారు</option><option value="no_answer">ఫోన్ ఎత్తలేదు</option></select><button class="p" data-fclose="${c.id}">✓ అయిపోయింది</button></div></div></div>`).join("")||'<p class="mut">ఇప్పుడు ఎవరూ లేరు.</p>'}</div>
  <div class="card"><h3 style="margin-top:0">అయిపోయినవి</h3>${done.callbacks.slice(-20).reverse().map(c=>`<div class="mut">${esc(c.title)} · ${esc(c.customer)} · ${esc(c.outcome)}</div>`).join("")||'<p class="mut">--</p>'}</div>`;
  M.querySelectorAll("button[data-fnum]").forEach(b=>b.onclick=async()=>{try{const r=await api(`/admin/cc/workspace/finance-callbacks/${b.dataset.fnum}/reveal`,"POST");$("#fnum_"+b.dataset.fnum).innerHTML=`<a href="tel:+91${esc(r.phone)}"><b>${esc(r.phone)}</b></a>`}catch(e){toast(e.message)}});
  M.querySelectorAll("button[data-fclose]").forEach(b=>b.onclick=async()=>{const id=b.dataset.fclose;try{await api(`/admin/cc/workspace/finance-callbacks/${id}/close`,"POST",{outcome:$("#fout_"+id).value,answer:$("#fans_"+id).value});toast("✓");finance()}catch(e){toast(e.message)}});
 }else{const d=await api("/admin/cc/workspace/items?item_type=financial_offer");
  M.innerHTML=top+`<div class="card"><h3 style="margin-top:0">➕ కొత్త Finance item</h3>
  <label>రకం</label><select id="fn_kind">${FKINDS.map(([k,l])=>`<option value="${k}">${l}</option>`).join("")}</select>
  <label>పేరు * (ఉదా: కంపెనీ + plan పేరు)</label><input id="fn_title">
  <label>Commission / affiliate link * (మేం ఓపెన్ చేయం)</label><input id="fn_link" type="url" placeholder="https://...">
  <label>చిన్న వివరణ</label><textarea id="fn_desc" rows="2"></textarea>
  <button class="p" id="fn_save">Save → documents పెట్టండి</button><div class="bad" id="fn_err"></div></div>
  <div class="card"><h3 style="margin-top:0">Finance items</h3>${d.items.map(i=>`<div class="item"><div class="grow"><b>${esc(i.title)}</b><div class="mut">${esc(i.review_status)}</div><div class="row"><button class="s" data-fopen="${i.id}">📄 Documents / జవాబులు</button>${i.review_status==="DRAFT"?`<button class="s" data-fpub="${i.id}">${ME.can_publish?"🚀 Publish":"Submit"}</button>`:""}</div><div id="fbox_${i.id}"></div></div></div>`).join("")||'<p class="mut">ఇంకా ఏమీ లేవు.</p>'}</div>`;
  $("#fn_save").onclick=async()=>{const t=$("#fn_title").value.trim(),l=firstLink($("#fn_link").value);if(!t||!l.startsWith("https://")){$("#fn_err").textContent="⚠️ పేరు, https లింక్ రెండూ కావాలి";return}
   try{const r=await api("/admin/cc/workspace/items","POST",{item_type:"financial_offer",action:"draft",fields:{title:t,platform:"other",original_product_url:l,affiliate_url:l,description:$("#fn_desc").value.trim()}});
    await api(`/admin/cc/workspace/finance/${r.item.id}/kind`,"PUT",{kind:$("#fn_kind").value});toast("Saved ✓");await finance();financeItem(r.item.id)}catch(e){$("#fn_err").textContent="⚠️ "+e.message}};
  M.querySelectorAll("button[data-fopen]").forEach(b=>b.onclick=()=>{const box=$("#fbox_"+b.dataset.fopen);if(box.innerHTML){box.innerHTML="";return}financeItem(b.dataset.fopen)});
  M.querySelectorAll("button[data-fpub]").forEach(b=>b.onclick=async()=>{try{const v=await api(`/admin/cc/workspace/finance/${b.dataset.fpub}`);if(!v.checked){toast("ముందు documents పెట్టి, AI జవాబులు చూసి ✓ చేయండి");financeItem(b.dataset.fpub);return}
   await api(`/admin/cc/workspace/items/${b.dataset.fpub}/review`,"POST",{action:"submit"});toast("✓");finance()}catch(e){toast(e.message)}})}
 $("#fn_items").onclick=()=>{FVIEW="items";finance()};$("#fn_calls").onclick=()=>{FVIEW="calls";finance()}}
async function financeItem(id,v){const box=$("#fbox_"+id);if(!box)return;try{v=v||await api(`/admin/cc/workspace/finance/${id}`)}catch(e){box.innerHTML=`<div class="bad">${esc(e.message)}</div>`;return}
 box.innerHTML=`<div class="card"><b>1. కంపెనీ documents</b> <span class="mut">(brochure / policy wording / premium chart -- PDF లేదా ఫోటో, 8 వరకు)</span>
 ${v.documents.map(d=>`<div class="row"><span class="grow">📄 ${esc(d.name)} <span class="mut">· ${d.pages} పేజీలు</span></span><button class="s" data-fdel="${d.id}" style="flex:0 0 70px">తీసేయ్</button></div>`).join("")||'<p class="mut">ఇంకా పెట్టలేదు.</p>'}
 <div class="row"><label class="s btn">📎 PDF / ఫోటో పెట్టు<input id="fdoc_${id}" type="file" accept="application/pdf,image/*" hidden></label><span class="mut" id="fdn_${id}"></span></div>
 <b>2. AI చదివింది</b> ${v.checked?'<span class="badge">✓ చూశారు -- customers కి కనిపిస్తుంది</span>':'<span class="warn">ఇంకా మీరు చూడలేదు -- customers కి కనిపించదు</span>'}
 <div class="row"><button class="s" id="fst_${id}">✨ Documents చదువు (ముఖ్య points + జవాబులు)</button></div>
 <label>ముఖ్య points (ఒక్కో లైన్ ఒక point; తప్పు ఉంటే సరిచేయండి)</label><textarea id="fpt_${id}" rows="5">${esc(v.points.join("\n"))}</textarea>
 ${v.qa.map(q=>`<div class="item"><div class="grow"><b>❓ ${esc(q.question)}</b><div>${esc(q.answer)}</div><div class="mut">${q.source==="executive"?"📞 executive చెప్పింది":`📄 ${esc(q.document)} · పేజీ ${q.page}`}</div></div><label class="mut" style="flex:0 0 70px"><input type="checkbox" data-fqa="${q.id}"> తప్పు</label></div>`).join("")}
 <div class="row"><button class="p" id="fok_${id}">✓ 3. నేను చూశాను -- సరిగ్గా ఉంది</button></div>
 ${v.not_answered.length?`<b>Customers అడిగి, document లో దొరకనివి</b>${v.not_answered.map(m=>`<div class="mut">❓ ${esc(m.question)} · ${m.times}×</div>`).join("")}`:""}</div>`;
 $("#fdoc_"+id).onchange=async e=>{const f=e.target.files[0];if(!f)return;$("#fdn_"+id).textContent="చదువుతోంది…";const fd=new FormData();fd.append("file",f,f.name);
  try{financeItem(id,await api(`/admin/cc/workspace/finance/${id}/documents`,"POST",fd,true));toast("Document వచ్చింది ✓")}catch(e2){$("#fdn_"+id).textContent="⚠️ "+e2.message}};
 box.querySelectorAll("button[data-fdel]").forEach(b=>b.onclick=async()=>{try{financeItem(id,await api(`/admin/cc/workspace/finance/${id}/documents/${b.dataset.fdel}`,"DELETE"))}catch(e){toast(e.message)}});
 $("#fst_"+id).onclick=async()=>{$("#fst_"+id).textContent="చదువుతోంది… (ఒక నిమిషం వరకు)";try{financeItem(id,await api(`/admin/cc/workspace/finance/${id}/study`,"POST"));toast("చదివింది ✓ -- ఒకసారి చూడండి")}catch(e){toast(e.message);financeItem(id)}};
 $("#fok_"+id).onclick=async()=>{const bad=[...box.querySelectorAll("input[data-fqa]:checked")].map(x=>x.dataset.fqa);
  try{financeItem(id,await api(`/admin/cc/workspace/finance/${id}/confirm`,"POST",{points:$("#fpt_"+id).value.split("\n").map(x=>x.trim()).filter(Boolean).slice(0,6),remove_qa:bad}));toast("✓ customers కి కనిపిస్తుంది")}catch(e){toast(e.message)}}}
async function review(){const d=await api("/admin/cc/workspace/items?status=NEEDS_REVIEW");
 M.innerHTML=`<div class="card"><h3 style="margin-top:0">Waiting for review (${d.items.length})</h3>${d.items.map(i=>itemRow(i,[["approve","Approve & publish"],["reject","Send back"]])).join("")||'<p class="mut">Nothing waiting.</p>'}</div>`;bindReview()}
async function items(){const d=await api("/admin/cc/workspace/items?mine=true");ITEMS={};d.items.forEach(i=>ITEMS[i.id]=i);
 const acts=i=>({DRAFT:[["submit",ME.can_publish?"Publish":"Submit"]],LIVE:[["pause","Pause"],["expire","Expire"]],PAUSED:ME.can_publish?[["resume","Resume"]]:[]}[i.review_status]||[]);
 const edit=i=>`<button class="s" data-edit="${i.id}">✏️ Edit</button><button class="s" data-edit="${i.id}" data-vid="1">🎥 Video</button><button class="s" data-aivid="${i.id}">🎬 AI వీడియో</button>`;
 const live=d.items.filter(i=>i.review_status==="LIVE");
 M.innerHTML=`${live.length>=2?`<div class="card"><h3 style="margin-top:0">🎞️ Collection వీడియో (2-5 ప్రోడక్ట్‌లు ఒకే వీడియోలో)</h3>
  <div class="mut">పైన ASKODOX, మీ టైటిల్, ప్రతి ప్రోడక్ట్ ఫోటోలు + పేరు + ధర, వాయిస్. ఏ store అయినా (Meesho, Wishlink, Amazon…) కలపవచ్చు.</div>
  ${live.map(i=>`<label style="display:flex;gap:8px;align-items:center;margin:6px 0"><input type="checkbox" class="cv_pick" value="${i.id}" style="width:auto;margin:0"> ${esc((i.title||"").slice(0,60))}${i.price?` · ₹${esc(String(i.price))}`:' · <span class="bad">ధర లేదు</span>'}</label>`).join("")}
  <label>Title (English, వీడియో పైన వస్తుంది)</label><input id="cv_theme" placeholder="TOP WINTER FINDS">
  <div class="row">${["TOP FINDS","TOP WINTER FINDS","UNDER ₹299","FESTIVE FINDS","NEW ARRIVALS"].map(t=>`<button class="s" data-theme="${esc(t)}">${esc(t)}</button>`).join("")}</div>
  <div class="row"><div><label>వాయిస్ భాష</label><select id="cv_lang"><option value="te">తెలుగు</option><option value="hi">हिंदी</option><option value="en">English</option></select></div>
  <div><label>వాయిస్</label><select id="cv_gender"><option value="female">ఆడ</option><option value="male">మగ</option><option value="none">వాయిస్ వద్దు</option></select></div></div>
  <div id="cv_err" class="bad"></div><button class="p" id="cv_make">🎞️ వీడియో తయారు చేయి</button></div>`:""}
 <div class="card"><h3 style="margin-top:0">My items</h3>${d.items.map(i=>itemRow(i,acts(i),edit(i))).join("")||'<p class="mut">Nothing yet -- add a link.</p>'}</div>`;bindReview();bindEdit();
 M.querySelectorAll("button[data-theme]").forEach(b=>b.onclick=()=>{$("#cv_theme").value=b.dataset.theme});
 if($("#cv_make"))$("#cv_make").onclick=async()=>{const ids=[...M.querySelectorAll(".cv_pick:checked")].map(x=>+x.value);const err=$("#cv_err");
  if(ids.length<2||ids.length>5){err.textContent="⚠️ 2 నుంచి 5 ప్రోడక్ట్‌లు టిక్ చేయండి";return}err.textContent="";const g=$("#cv_gender").value;
  $("#cv_make").disabled=true;try{await api("/admin/cc/workspace/collections/ai-video","POST",{item_ids:ids,theme:$("#cv_theme").value.trim(),
   language:$("#cv_lang").value,voice:g!=="none",gender:g==="none"?"female":g});toast("🎞️ తయారవుతోంది -- Videos లో చూడండి");TAB="reels";start()}
  catch(e){err.textContent="⚠️ "+e.message;$("#cv_make").disabled=false}};
 M.querySelectorAll("button[data-aivid]").forEach(b=>b.onclick=async()=>{b.disabled=true;if(await startAiVideo(b.dataset.aivid,{})){TAB="reels";start()}else b.disabled=false})}
// Owner 2026-11-06: edit a saved item (inline -- Android WebView has no prompt()) and add a video later.
let ITEMS={};
// ONE click listener on the main area (event delegation): it keeps working even if
// the list is drawn again, and every tap shows something (owner 2026-11-06: form never came).
let EDIT_BOUND=false;
function bindEdit(){if(EDIT_BOUND)return;EDIT_BOUND=true;
 document.addEventListener("click",ev=>{const b=ev.target&&ev.target.closest?ev.target.closest("button[data-edit]"):null;if(!b)return;
  ev.preventDefault();toast("✏️ Edit తెరుస్తోంది…");
  try{openEdit(b)}catch(e){toast("Edit: "+e.message)}},true)}
async function editItem(id){let i=ITEMS[id];if(i)return i;
 const d=await api("/admin/cc/workspace/items?mine=true");d.items.forEach(x=>ITEMS[x.id]=x);return ITEMS[id]}
async function openEdit(b){const old=document.getElementById("editbox");if(old)old.remove();
 const i=await editItem(b.dataset.edit);if(!i){toast("Item not found -- open My items again");return}
 const v=x=>x==null?"":esc(String(x));const box=document.createElement("div");box.className="card";box.style.marginTop="8px";
 box.innerHTML=`<label>Title / పేరు</label><input id="e_title" value="${v(i.title)}">
 <label>Price ₹ / ధర</label><input id="e_price" inputmode="decimal" value="${v(i.price)}">
 <label>MRP ₹</label><input id="e_mrp" inputmode="decimal" value="${v(i.mrp)}">
 <label>Description</label><textarea id="e_desc" rows="3">${v(i.description)}</textarea>
 ${ME.can_link?`<label>Commission link (optional / ఐచ్ఛికం)</label><input id="e_aff" value="${v(i.affiliate_url)}">`:""}
 ${ME.can_commission?`<label>Commission % (optional / ఐచ్ఛికం)</label><input id="e_rate" inputmode="decimal" value="${v(i.verified_commission_rate)}">`:""}
 <label>Stock</label><select id="e_stock">${["UNKNOWN","IN_STOCK","OUT_OF_STOCK"].map(s=>`<option ${i.stock_status===s?"selected":""}>${s}</option>`).join("")}</select>
 <label>Product video (optional, 60 సెకన్ల లోపు) / వీడియో</label><input type="file" id="e_vid" accept="video/mp4,video/webm,video/quicktime"><span class="mut" id="e_vidnote"></span>
 <p class="mut">Description ఇంగ్లీష్‌లో రాస్తే చాలు -- చూసేవారి భాషలోకి ఆటోమేటిక్‌గా మారుతుంది.</p>
 <div class="row"><button class="s" id="e_cancel">Cancel</button><button class="p" id="e_save">Save</button></div>`;
 box.id="editbox";const row=b.closest(".item");if(row&&row.after)row.after(box);else M.prepend(box);PVID=null;
 box.querySelector("#e_vid").onchange=e=>pickVideo(e.target,box.querySelector("#e_vidnote"));
 if(b.dataset.vid){const v=box.querySelector("#e_vid");v.scrollIntoView({block:"center"});try{v.click()}catch(e){}}else box.scrollIntoView({block:"start"});
 box.querySelector("#e_cancel").onclick=()=>items();
 box.querySelector("#e_save").onclick=async()=>{const q=s=>box.querySelector(s),f={title:q("#e_title").value.trim(),description:q("#e_desc").value.trim()};
  const num=x=>x.trim()===""?null:Number(x.trim().replace(/[₹,]/g,""));f.price=num(q("#e_price").value);f.mrp=num(q("#e_mrp").value);
  if(q("#e_aff"))f.affiliate_url=q("#e_aff").value.trim();if(q("#e_rate"))f.verified_commission_rate=q("#e_rate").value.trim();
  q("#e_save").disabled=true;q("#e_save").textContent="Saving…";
  try{const r=await api(`/admin/cc/workspace/items/${i.id}`,"PATCH",{fields:f,stock_status:q("#e_stock").value});
   if(PVID){try{await attachVideo(i.id,f.description,"","");toast("Saved + video uploaded")}catch(e){toast("Saved. Video: "+e.message)}}
   else toast(r.item.review_status==="NEEDS_REVIEW"?"Saved -- review కి వెళ్లింది":"Saved");items()}
  catch(e){toast(e.message);q("#e_save").disabled=false;q("#e_save").textContent="Save"}}}

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
