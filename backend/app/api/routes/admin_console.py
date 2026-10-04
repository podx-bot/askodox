"""ASKODOX Command Center console (premium SaaS shell).

One self-contained page at /admin/console. It holds no secrets and no data:
everything comes from the existing, permission-checked /admin/cc APIs with
the owner key or a staff token (kept in sessionStorage for the tab only).
Resource pages are generated from /admin/cc/platform/schema, so every
platform resource gets the same controls: add, edit, view, delete, lifecycle
actions, duplicate, archive/restore, search, filter, sort, export and audit
history. The older /admin page stays available.
"""
from fastapi import APIRouter
from fastapi.responses import HTMLResponse

router = APIRouter(tags=["admin-console"])

PAGE = r'''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>ASKODOX Console</title><link rel="icon" href="data:,">
<style>
:root{--bg:#f4f6fb;--panel:#fff;--ink:#101828;--muted:#667085;--line:#e4e7ec;--brand:#5b3df5;--brand2:#7a5af8;
--side:#0f1629;--side2:#1a2340;--ok:#067647;--okbg:#dcfae6;--warn:#b54708;--warnbg:#fef0c7;--bad:#b42318;--badbg:#fee4e2;
--info:#175cd3;--infobg:#d1e9ff;--grey:#475467;--greybg:#f2f4f7;font-family:Inter,system-ui,-apple-system,Segoe UI,Roboto,sans-serif;color:var(--ink)}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){--bg:#0b1020;--panel:#121a2e;--ink:#e6e9f2;--muted:#98a2b3;--line:#253050;
--greybg:#1d2742;--okbg:#0b3b24;--warnbg:#4a2a06;--badbg:#4a1210;--infobg:#0b2a55}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink)}
.app{display:grid;grid-template-columns:248px 1fr;min-height:100vh}
aside{background:var(--side);color:#cfd6e6;padding:18px 12px;position:sticky;top:0;height:100vh;overflow:auto}
.logo{display:flex;align-items:center;gap:10px;padding:4px 10px 18px;color:#fff;font-weight:800;font-size:17px;letter-spacing:.2px}
.logo i{width:30px;height:30px;border-radius:9px;background:linear-gradient(135deg,var(--brand),#22c1ee);display:inline-block}
.grp{font-size:11px;text-transform:uppercase;letter-spacing:.8px;color:#7d89a8;padding:14px 10px 6px}
aside a{display:flex;align-items:center;justify-content:space-between;padding:8px 10px;border-radius:8px;color:#cfd6e6;text-decoration:none;font-size:14px;cursor:pointer}
aside a:hover{background:var(--side2);color:#fff}aside a.on{background:var(--brand);color:#fff}
aside a .n{font-size:11px;background:#ffffff22;border-radius:99px;padding:1px 7px}
main{min-width:0}
.top{display:flex;align-items:center;gap:12px;padding:12px 22px;background:var(--panel);border-bottom:1px solid var(--line);position:sticky;top:0;z-index:5}
.top .search{flex:1;position:relative}.top input.q{width:100%;max-width:520px;padding:9px 12px 9px 34px;border-radius:10px;border:1px solid var(--line);background:var(--bg);color:var(--ink)}
.top .search:before{content:"⌕";position:absolute;left:12px;top:6px;color:var(--muted);font-size:17px}
.hits{position:absolute;top:42px;left:0;width:520px;max-width:100%;background:var(--panel);border:1px solid var(--line);border-radius:12px;box-shadow:0 12px 40px #0002;display:none;max-height:60vh;overflow:auto}
.hits div{padding:9px 12px;border-bottom:1px solid var(--line);cursor:pointer;font-size:13px}.hits div:hover{background:var(--greybg)}
.who{font-size:13px;color:var(--muted);white-space:nowrap}
.page{padding:22px;max-width:1320px}
h1{font-size:22px;margin:0 0 4px}.sub{color:var(--muted);font-size:13px;margin-bottom:18px}
.kpis{display:grid;grid-template-columns:repeat(auto-fit,minmax(170px,1fr));gap:12px;margin-bottom:16px}
.kpi,.card{background:var(--panel);border:1px solid var(--line);border-radius:14px;padding:14px 16px;box-shadow:0 1px 2px #1018280d}
.kpi .l{font-size:12px;color:var(--muted)}.kpi .v{font-size:24px;font-weight:800;margin-top:6px}.kpi .s{font-size:12px;color:var(--muted);margin-top:2px}
.cols{display:grid;grid-template-columns:repeat(auto-fit,minmax(360px,1fr));gap:14px}
.card h3{margin:0 0 10px;font-size:14px}
.badge{display:inline-flex;align-items:center;gap:5px;font-size:11.5px;font-weight:700;padding:3px 9px;border-radius:99px;background:var(--greybg);color:var(--grey);white-space:nowrap}
.badge:before{content:"";width:6px;height:6px;border-radius:99px;background:currentColor}
.b-ok{background:var(--okbg);color:var(--ok)}.b-warn{background:var(--warnbg);color:var(--warn)}.b-bad{background:var(--badbg);color:var(--bad)}.b-info{background:var(--infobg);color:var(--info)}
.bar{display:flex;flex-wrap:wrap;gap:8px;align-items:center;margin-bottom:12px}
input,select,textarea{font:inherit;border:1px solid var(--line);border-radius:9px;padding:8px 10px;background:var(--panel);color:var(--ink)}
textarea{width:100%;min-height:80px}
button{font:inherit;font-weight:600;border:1px solid var(--line);background:var(--panel);color:var(--ink);border-radius:9px;padding:8px 12px;cursor:pointer}
button.p{background:var(--brand);border-color:var(--brand);color:#fff}button.d{color:var(--bad)}button:disabled{opacity:.5;cursor:default}
table{width:100%;border-collapse:collapse;font-size:13px}th{font-size:11.5px;text-transform:uppercase;letter-spacing:.4px;color:var(--muted);text-align:left;padding:9px 10px;border-bottom:1px solid var(--line);cursor:pointer;white-space:nowrap}
td{padding:10px;border-bottom:1px solid var(--line);vertical-align:top}tr.r:hover td{background:var(--greybg);cursor:pointer}
.tbl{background:var(--panel);border:1px solid var(--line);border-radius:14px;overflow:auto}
.empty{padding:28px;text-align:center;color:var(--muted)}
.drawer{position:fixed;top:0;right:0;width:min(560px,100%);height:100vh;background:var(--panel);border-left:1px solid var(--line);box-shadow:-20px 0 60px #0003;z-index:20;display:none;flex-direction:column}
.drawer.show{display:flex}.dh{padding:16px 18px;border-bottom:1px solid var(--line);display:flex;justify-content:space-between;align-items:center;gap:8px}
.db{padding:16px 18px;overflow:auto;flex:1}.df{padding:12px 18px;border-top:1px solid var(--line);display:flex;flex-wrap:wrap;gap:8px}
.f{display:flex;flex-direction:column;gap:5px;margin-bottom:12px;font-size:12.5px;color:var(--muted)}.f input,.f select,.f textarea{color:var(--ink);font-size:14px}
.f .req{color:var(--bad)}.err{color:var(--bad);font-size:13px;margin:6px 0}.okm{color:var(--ok);font-size:13px}
.funnel .row{display:grid;grid-template-columns:150px 1fr 60px;gap:8px;align-items:center;font-size:12.5px;margin:5px 0}
.funnel .track{background:var(--greybg);border-radius:6px;height:12px;overflow:hidden}.funnel .fill{height:12px;background:linear-gradient(90deg,var(--brand),var(--brand2));border-radius:6px}
.login{max-width:420px;margin:12vh auto;background:var(--panel);border:1px solid var(--line);border-radius:16px;padding:24px}
.login h2{margin:0 0 6px}.login input{width:100%;margin:8px 0}
.hist{font-size:12.5px;border-left:2px solid var(--line);padding-left:12px}.hist div{margin-bottom:10px}
.mono{font-family:ui-monospace,Menlo,monospace;font-size:12px}.muted{color:var(--muted)}.right{margin-left:auto}
.menu{display:none}
@media(max-width:900px){#env,.who{display:none}.hits{width:92vw}.app{grid-template-columns:1fr}aside{position:fixed;left:-260px;width:248px;z-index:30;transition:left .2s}aside.open{left:0}.menu{display:inline-block}.page{padding:14px}}
</style></head><body>
<div id="login" class="login" style="display:none">
  <h2>ASKODOX Console</h2><div class="muted">Sign in with the owner admin key or your staff token.</div>
  <input id="cred" type="password" placeholder="Admin key or staff token (stf_...)" autocomplete="off">
  <button class="p" onclick="signIn()">Sign in</button> <span id="lerr" class="err"></span>
</div>
<div id="app" class="app" style="display:none">
  <aside id="side"></aside>
  <main>
    <div class="top">
      <button class="menu" onclick="document.querySelector('#side').classList.toggle('open')">☰</button>
      <div class="search"><input class="q" id="q" placeholder="Search programs, links, offers, videos, payments…" oninput="globalSearch(this.value)"><div class="hits" id="hits"></div></div>
      <span id="env"></span><span class="who" id="who"></span><button onclick="signOut()">Sign out</button>
    </div>
    <div class="page" id="page"></div>
  </main>
</div>
<div class="drawer" id="drawer"><div class="dh"><b id="dt"></b><button onclick="closeDrawer()">✕</button></div><div class="db" id="db"></div><div class="df" id="df"></div></div>
<script>
let CRED=sessionStorage.getItem("askodox_console")||"", ME=null, SCHEMA=null, VIEW="dashboard", STATE={};
const esc=x=>String(x??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
const hdr=()=>CRED.startsWith("stf_")?{"X-ASKODOX-Staff-Token":CRED}:{"X-ASKODOX-Admin-Key":CRED};
async function call(path,method="GET",body){const r=await fetch(path.startsWith("/")?path:"/admin/cc/"+path,{method,headers:{...hdr(),...(body!==undefined?{"Content-Type":"application/json"}:{})},body:body===undefined?undefined:JSON.stringify(body)});
  const t=await r.text();let d;try{d=t?JSON.parse(t):{}}catch(e){d=t}if(!r.ok)throw new Error(typeof d==="object"&&d.detail?(typeof d.detail==="string"?d.detail:JSON.stringify(d.detail)):(t||r.status));return d}
const can=p=>ME&&ME.permissions.includes(p);
function badge(s){s=String(s??"");const u=s.toUpperCase();let c="";
  if(["IN_STOCK","AFFILIATE","ACTIVE","LIVE","APPROVED","PAID","CONFIRMED","SETTLED","REDEEMED","RESOLVED","MET","OK","SENT","ENABLED","VERIFIED","ON_TRACK","GREEN","EXECUTED","ON"].includes(u))c="b-ok";
  else if(["PENDING_REVIEW","PENDING","TEST","SCHEDULED","EXPECTED","DUE_SOON","IN_PROGRESS","CREATED","CLAIMED","LOCKED","PARTIALLY_REFUNDED","WAITING_FOR_USER","DRAFT","OPEN","ORANGE","PENDING_APPROVAL","PROPOSED","APPROVAL","POSSIBLE","DEGRADED","CONFIGURED"].includes(u))c="b-warn";
  else if(["OUT_OF_STOCK","DISABLED","ERROR","FAILED","REJECTED","DISPUTED","OVERDUE","BREACHED","REVERSED","BLOCKED","URGENT","CRITICAL","RED","ALERTED","OWNER ONLY","PRIVACY_PAUSED","CHECK_FAILED"].includes(u))c="b-bad";
  else if(["UNKNOWN","ORGANIC","COMMISSION UNKNOWN","NEEDS_CONFIGURATION","AVAILABLE","HIGH","INFO"].includes(u))c="b-info";
  return '<span class="badge '+c+'">'+esc(s.replace(/_/g," "))+'</span>'}
const money=v=>{if(v==null)return "—";const n=Number(v);return "₹"+n.toLocaleString("en-IN",Number.isInteger(n)?{}:{minimumFractionDigits:2,maximumFractionDigits:2})};
const when=v=>v?new Date(v).toLocaleString():"—";

/* ------------------------------------------------------------ navigation -- */
function navModel(){const r=n=>({id:"r:"+n,label:(SCHEMA.resources.find(x=>x.name===n)||{}).label||n,perm:(SCHEMA.resources.find(x=>x.name===n)||{}).permission+":view"});
  return [["Overview",[{id:"dashboard",label:"Dashboard",perm:"overview:view"},{id:"analytics",label:"Analytics",perm:"analytics:view"},{id:"outcomes",label:"Outcomes & gaps",perm:"analytics:view"},{id:"insights",label:"AI insights",perm:"insights:view"},{id:"revcmd",label:"Revenue command center",perm:"revenue:view"}]],
  ["Growth & ads",[{id:"sponsored",label:"Sponsored campaigns",perm:"sponsored:view"},r("affiliate_programs"),r("affiliate_links"),r("smart_links"),{id:"benefits",label:"Offers & coupons",perm:"growth:view"},r("merchant_offers"),{id:"referrals",label:"Referrals",perm:"growth:view"},r("promotion_campaigns")]],
  ["Advisor & demand",[{id:"demand",label:"Demand intelligence",perm:"demand:view"},r("demand_alert_rules"),r("advisor_categories"),r("advisor_questions"),r("advisor_rules"),{id:"assistant",label:"Admin assistant",perm:"overview:view"},{id:"workqueue",label:"My work queue",perm:"overview:view"}]],
  ["Affiliate catalog",[{id:"affproducts",label:"Affiliate products",perm:"affiliate_products:view"},{id:"affsources",label:"Affiliate sources",perm:"affiliate_products:view"}]],
  ["Content",[r("videos"),{id:"discovered",label:"Discovered videos",perm:"content:view"},r("creators"),r("video_sources"),r("reviews")]],
  ["Money",[{id:"payments",label:"Payments",perm:"payments:view"},{id:"ledger",label:"Revenue ledger",perm:"finance:view"},{id:"rewards",label:"Rewards ledger",perm:"rewards:view"},{id:"transactions",label:"Transactions",perm:"finance:view"},r("subscription_promos")]],
  ["Customers",[{id:"support",label:"Support tickets",perm:"support:view"},{id:"accounts",label:"Users & accounts",perm:"users:view"},r("listing_reviews"),r("prohibited_terms"),r("notification_templates"),r("notification_rules")]],
  ["System",[{id:"readiness",label:"Integration readiness",perm:"integrations:view"},{id:"integrations",label:"Integrations",perm:"integrations:view"},{id:"outbox",label:"Message deliveries",perm:"integrations:view"},{id:"flags",label:"Feature flags",perm:"config:view"},r("flag_rollouts"),{id:"cfgbundle",label:"Config import / export",perm:"config:view"},{id:"staff",label:"Staff & roles",perm:"staff:manage"},{id:"approvals",label:"Approvals",perm:"approvals:view"},{id:"selfheal",label:"Self-healing",perm:"selfheal:view"},{id:"audit",label:"Audit log",perm:"audit:view"},{id:"events",label:"Event stream",perm:"analytics:view"}]],
  ["Owner setup",[{id:"setup",label:"ASKODOX setup",perm:"config:view"},r("qa_checks"),r("email_roles"),r("referral_credit_rules"),r("greeting_templates"),r("delivery_partners"),r("platform_settings"),r("auto_response_rules"),{id:"socialdm",label:"Social auto-DM",perm:"autoresponse:view"},r("social_dm_accounts")]],
  ["AI Companion",[{id:"screenguide",label:"Screen Guide",perm:"companion:view"}]]]}
function renderNav(){const counts=STATE.pending||{};document.querySelector("#side").innerHTML='<div class="logo"><i></i>ASKODOX</div>'+navModel().map(([g,items])=>{const vis=items.filter(i=>can(i.perm));
  return vis.length?'<div class="grp">'+g+'</div>'+vis.map(i=>'<a class="'+(VIEW===i.id?"on":"")+'" onclick="go(\''+i.id+'\')">'+esc(i.label)+(counts[i.id]?'<span class="n">'+counts[i.id]+'</span>':'')+'</a>').join(""):""}).join("")+'<div class="grp">Legacy</div><a href="/admin">Classic admin</a>'}
function go(id){VIEW=id;location.hash=id;closeDrawer();document.querySelector("#side").classList.remove("open");renderNav();render()}
async function render(){const p=document.querySelector("#page");p.innerHTML='<div class="muted">Loading…</div>';
  try{if(VIEW.startsWith("r:"))return await resourcePage(VIEW.slice(2));const f={dashboard,analytics,insights,sponsored,benefits,referrals,payments,ledger,rewards,transactions,support,accounts,integrations,flags,staff,audit,events,readiness,outbox,discovered,approvals,selfheal,revcmd,screenguide,setup,affproducts,affsources,demand,workqueue,assistant,cfgbundle,outcomes,socialdm}[VIEW];await (f||dashboard)()}
  catch(e){p.innerHTML='<div class="card err">Could not load: '+esc(e.message)+'</div>'}}

/* ---------------------------------------------------------------- auth -- */
async function signIn(){CRED=document.querySelector("#cred").value.trim()||CRED;try{await boot();sessionStorage.setItem("askodox_console",CRED)}catch(e){document.querySelector("#lerr").textContent="Sign-in failed: "+e.message;document.querySelector("#login").style.display="block";document.querySelector("#app").style.display="none"}}
function signOut(){sessionStorage.removeItem("askodox_console");CRED="";location.reload()}
async function boot(){ME=await call("me");SCHEMA=(await call("platform/schema"));document.querySelector("#login").style.display="none";document.querySelector("#app").style.display="grid";
  document.querySelector("#who").textContent=ME.name+" · "+String(ME.role).replace(/_/g," ");
  try{if(can("integrations:view")){const ig=(await call("platform/integrations")).items.filter(i=>i.group==="payments"&&!i.internal&&i.provider!=="sandbox_gateway");
      const live=ig.filter(i=>i.status==="LIVE").length,test=ig.filter(i=>i.status==="TEST").length;
      document.querySelector("#env").innerHTML=live?badge("Gateways LIVE"):test?badge("Gateways TEST"):'<span title="Only direct payments (COD / cash / direct UPI) work until a gateway is configured">'+badge("NEEDS CONFIGURATION")+'</span>'}
    const d=await call("platform/dashboard");STATE.dash=d;
    STATE.pending={};for(const [res,by] of Object.entries(d.resources))if(by.PENDING_REVIEW)STATE.pending["r:"+res]=by.PENDING_REVIEW}catch(e){}
  VIEW=(location.hash||"#dashboard").slice(1);renderNav();render()}

/* ------------------------------------------------------------ search -- */
let st;function globalSearch(q){clearTimeout(st);const h=document.querySelector("#hits");if(q.trim().length<2){h.style.display="none";return}
  st=setTimeout(async()=>{try{const d=await call("platform/search?q="+encodeURIComponent(q));h.innerHTML=d.items.length?d.items.map(i=>'<div onclick="openHit(\''+i.resource+'\',\''+esc(i.id)+'\')"><b>'+esc(i.name)+'</b> <span class="muted">'+esc(i.resource_label)+'</span> '+badge(i.status)+'</div>').join(""):'<div class="muted">No matches</div>';h.style.display="block"}catch(e){}},220)}
function openHit(res,id){document.querySelector("#hits").style.display="none";if(res==="payments"){go("payments");return}VIEW="r:"+res;renderNav();resourcePage(res).then(()=>openRecord(res,id))}
document.addEventListener("click",e=>{if(!e.target.closest(".search"))document.querySelector("#hits").style.display="none"});

/* --------------------------------------------------------- dashboard -- */
async function dashboard(){const [o,d]=await Promise.all([can("overview:view")?call("overview").catch(()=>({})):{},call("platform/dashboard")]);STATE.dash=d;
  const p=o.participants||{},rev=d.revenue||{},i=d.integrations||{};const k=(l,v,s)=>'<div class="kpi"><div class="l">'+l+'</div><div class="v">'+v+'</div><div class="s">'+(s||"")+'</div></div>';
  const fmax=Math.max(1,...d.funnel.map(s=>s.count));
  document.querySelector("#page").innerHTML='<h1>Dashboard</h1><div class="sub">Live state of the platform. Nothing here is estimated or invented.</div><div class="kpis">'+
   k("Buyers",p.buyers??"—")+k("Sellers",p.sellers??"—")+k("Active requests",o.requests?.active??"—")+k("Pending review",d.pending_review,"across all resources")+
   (d.revenue?k("Revenue confirmed",money((rev.by_state||{}).CONFIRMED||0),"paid "+money((rev.by_state||{}).PAID||0)):"")+k("Support open",o.support_open??"—")+
   k("Integrations",(i.LIVE||0)+" live",(i.NEEDS_CONFIGURATION||0)+" need configuration")+k("Alerts",d.alerts.length,"last 7 days")+'</div>'+
   '<div class="cols"><div class="card"><h3>Conversion funnel (30 days)</h3><div class="funnel">'+d.funnel.map(s=>'<div class="row"><span>'+esc(s.step.replace(/_/g," "))+'</span><div class="track"><div class="fill" style="width:'+(s.count/fmax*100)+'%"></div></div><b>'+s.count+'</b></div>').join("")+'</div></div>'+
   '<div class="card"><h3>Alerts & suggestions</h3>'+(d.alerts.length?d.alerts.map(a=>'<div style="margin-bottom:10px">'+badge(a.severity)+' <b>'+esc(a.title)+'</b><div class="muted">'+esc(a.suggestion||"")+'</div></div>').join(""):'<div class="muted">No warnings.</div>')+'</div>'+
   '<div class="card"><h3>Integrations</h3>'+Object.entries(i).map(([s,n])=>'<div style="display:flex;justify-content:space-between;margin:6px 0">'+badge(s)+'<b>'+n+'</b></div>').join("")+'<button onclick="go(\'integrations\')">Manage integrations</button></div>'+
   (d.payments==null?'':'<div class="card"><h3>Payments by state</h3>'+(Object.keys(d.payments||{}).length?Object.entries(d.payments).map(([s,v])=>'<div style="display:flex;justify-content:space-between;margin:6px 0">'+badge(s)+'<b>'+money(v)+'</b></div>').join(""):'<div class="muted">No payments yet.</div>')+'</div>')+'</div>'}

/* ---------------------------------------------- schema-driven resources -- */
const R=n=>SCHEMA.resources.find(r=>r.name===n);
async function resourcePage(name){const res=R(name);const s=STATE[name]||(STATE[name]={q:"",status:"",archived:false,sort:"-updated_at",f:{}});
  const qs=new URLSearchParams({q:s.q,status:s.status,archived:s.archived,sort:s.sort,...Object.fromEntries(Object.entries(s.f).filter(([k,v])=>v).map(([k,v])=>["f_"+k,v]))});
  const d=await call("platform/r/"+name+"?"+qs);const cols=res.fields.filter(f=>f.list_column&&f.name!==res.name_field).slice(0,4);const manage=can(res.permission+":manage");
  const filt=res.fields.filter(f=>f.filter);
  document.querySelector("#page").innerHTML='<h1>'+esc(res.label)+'</h1><div class="sub">'+esc(res.description||"")+(res.flag?' · feature flag <span class="mono">'+esc(res.flag)+'</span>':'')+'</div>'+
   '<div class="bar"><input placeholder="Search…" value="'+esc(s.q)+'" onchange="STATE[\''+name+'\'].q=this.value;resourcePage(\''+name+'\')">'+
   '<select onchange="STATE[\''+name+'\'].status=this.value;resourcePage(\''+name+'\')"><option value="">All statuses</option>'+res.statuses.map(x=>'<option '+(s.status===x?"selected":"")+'>'+x+'</option>').join("")+'</select>'+
   filt.map(f=>f.options.length?'<select onchange="STATE[\''+name+'\'].f.'+f.name+'=this.value;resourcePage(\''+name+'\')"><option value="">'+esc(f.label)+': any</option>'+f.options.map(o=>'<option '+(s.f[f.name]===o?"selected":"")+'>'+esc(o)+'</option>').join("")+'</select>':'<input placeholder="'+esc(f.label)+'" value="'+esc(s.f[f.name]||"")+'" onchange="STATE[\''+name+'\'].f.'+f.name+'=this.value;resourcePage(\''+name+'\')">').join("")+
   '<label class="muted"><input type="checkbox" '+(s.archived?"checked":"")+' onchange="STATE[\''+name+'\'].archived=this.checked;resourcePage(\''+name+'\')"> Archived</label>'+
   '<span class="right"></span>'+(can("analytics:export")?'<button onclick="exportCsv(\''+name+'\')">Export CSV</button>':'')+(manage?'<button class="p" onclick="openForm(\''+name+'\')">+ New</button>':'')+'</div>'+
   '<div class="tbl">'+(d.items.length?'<table><thead><tr>'+['name',...cols.map(c=>c.name),'status','updated_at'].map(c=>'<th onclick="sortBy(\''+name+'\',\''+c+'\')">'+esc(c==="name"?"Name":c==="updated_at"?"Updated":(res.fields.find(f=>f.name===c)||{}).label||c)+(s.sort.replace("-","")===c?(s.sort.startsWith("-")?" ↓":" ↑"):"")+'</th>').join("")+'</tr></thead><tbody>'+
     d.items.map(it=>'<tr class="r" onclick="openRecord(\''+name+'\',\''+esc(it.id)+'\')"><td><b>'+esc(it.name)+'</b><div class="muted mono">'+esc(it.id)+'</div></td>'+cols.map(c=>'<td>'+cell(it.data[c.name],c)+'</td>').join("")+'<td>'+badge(it.status)+(it.archived?' '+badge("archived"):'')+'</td><td class="muted">'+when(it.updated_at)+'</td></tr>').join("")+'</tbody></table>'
     :'<div class="empty">Nothing here yet.'+(manage?' Use <b>+ New</b> to add the first one.':'')+'</div>')+'</div>'}
function cell(v,f){if(v==null||v==="")return '<span class="muted">—</span>';if(Array.isArray(v))return esc(v.join(", "));if(typeof v==="boolean")return v?badge("yes"):'<span class="muted">no</span>';if(f&&f.kind==="url")return '<a href="'+esc(v)+'" target="_blank" rel="noopener">'+esc(String(v).slice(0,40))+'</a>';return esc(typeof v==="object"?JSON.stringify(v):v)}
function sortBy(n,c){const s=STATE[n];s.sort=s.sort===c?"-"+c:c;resourcePage(n)}
async function exportCsv(n){const r=await fetch("/admin/cc/platform/r/"+n+"/export.csv",{headers:hdr()});if(!r.ok){alert(await r.text());return}const a=document.createElement("a");a.href=URL.createObjectURL(await r.blob());a.download="askodox-"+n+".csv";a.click()}
function input(f,v){const id="fld_"+f.name,val=v??"",req=f.required?' <span class="req">*</span>':'';
  let el;if(f.kind==="enum")el='<select id="'+id+'"><option value=""></option>'+f.options.map(o=>'<option '+(val===o?"selected":"")+'>'+esc(o)+'</option>').join("")+'</select>';
  else if(f.kind==="bool")el='<select id="'+id+'"><option value="false">No</option><option value="true" '+(val===true?"selected":"")+'>Yes</option></select>';
  else if(f.kind==="longtext")el='<textarea id="'+id+'">'+esc(val)+'</textarea>';
  else if(f.kind==="json")el='<textarea id="'+id+'" class="mono">'+esc(val&&Object.keys(val).length?JSON.stringify(val,null,1):"")+'</textarea>';
  else if(f.kind==="list")el='<input id="'+id+'" value="'+esc(Array.isArray(val)?val.join(", "):val)+'" placeholder="comma separated">';
  else el='<input id="'+id+'" type="'+(f.kind==="number"||f.kind==="int"?"number":f.kind==="date"?"text":"text")+'" value="'+esc(val)+'" placeholder="'+(f.kind==="date"?"YYYY-MM-DD":f.kind==="url"?"https://…":f.kind==="deeplink"?"app://… or https://…":"")+'">';
  return '<label class="f">'+esc(f.label)+req+el+'</label>'}
function readForm(res,partial){const out={};for(const f of res.fields){const el=document.querySelector("#fld_"+f.name);if(!el)continue;let v=el.value;
  if(f.kind==="list")v=v.split(",").map(x=>x.trim()).filter(Boolean);else if(f.kind==="bool")v=v==="true";else if(f.kind==="json"){try{v=v.trim()?JSON.parse(v):{}}catch(e){throw new Error(f.label+": invalid JSON")}}
  else if((f.kind==="number"||f.kind==="int")&&v!=="")v=Number(v);else if(v==="")v=null;out[f.name]=v}return out}
function openForm(name,rec){const res=R(name);drawer((rec?"Edit ":"New ")+res.label.replace(/s$/,""),res.fields.map(f=>input(f,rec?rec.data[f.name]:undefined)).join("")+'<div id="ferr" class="err"></div>',
  '<button class="p" onclick="saveForm(\''+name+'\','+(rec?'\''+esc(rec.id)+'\','+rec.version:'null,null')+')">Save</button><button onclick="closeDrawer()">Cancel</button>')}
async function saveForm(name,id,version){const res=R(name);try{const data=readForm(res);const r=id?await call("platform/r/"+name+"/"+id,"PATCH",{data,version}):await call("platform/r/"+name,"POST",{data});await resourcePage(name);openRecord(name,r.id)}catch(e){document.querySelector("#ferr").textContent=e.message}}
async function openRecord(name,id){const res=R(name);const [rec,h]=await Promise.all([call("platform/r/"+name+"/"+id),call("platform/r/"+name+"/"+id+"/history")]);const manage=can(res.permission+":manage");
  const hide={feature:rec.data.featured===true,unfeature:rec.data.featured!==true,verify:rec.data.verified===true,unverify:rec.data.verified!==true,enable:rec.status==="ACTIVE",disable:rec.status==="DISABLED"};
  const acts=res.actions.filter(a=>!rec.archived&&!hide[a.name]&&(!a.from_status.length||a.from_status.includes(rec.status))&&(a.manage?manage:true));
  drawer(rec.name,'<div style="margin-bottom:12px">'+badge(rec.status)+(rec.archived?' '+badge("archived"):'')+' <span class="muted mono">'+esc(rec.id)+' · v'+rec.version+'</span></div>'+
   (rec.data.health?'<div class="card" style="margin-bottom:12px"><b>Link health</b> '+badge(rec.data.health.state)+'<div class="muted">'+when(rec.data.health.checked_at)+'</div>'+rec.data.health.results.map(r=>'<div class="mono">'+esc(r.kind)+' → '+esc(r.status)+'</div>').join("")+'</div>':'')+
   '<table>'+res.fields.map(f=>'<tr><td class="muted" style="width:40%">'+esc(f.label)+'</td><td>'+cell(rec.data[f.name],f)+'</td></tr>').join("")+'</table>'+
   '<h3 style="margin:18px 0 8px;font-size:14px">Audit history</h3><div class="hist">'+h.items.map(x=>'<div><b>'+esc(x.action)+'</b> by '+esc(x.actor)+' <span class="muted">'+when(x.at)+'</span>'+(x.from_status!==x.to_status&&x.to_status?'<div>'+badge(x.from_status||"—")+' → '+badge(x.to_status)+'</div>':'')+'</div>').join("")+'</div><div id="ferr" class="err"></div><div id="aout"></div>',
   (manage?'<button class="p" onclick=\'editRecord("'+name+'","'+esc(rec.id)+'")\'>Edit</button>':'')+acts.map(a=>'<button onclick="doAction(\''+name+'\',\''+esc(rec.id)+'\',\''+a.name+'\','+a.confirm+')">'+esc(a.label)+'</button>').join("")+
   (manage?'<button onclick="doAction(\''+name+'\',\''+esc(rec.id)+'\',\'duplicate\',false)">Duplicate</button><button onclick="doAction(\''+name+'\',\''+esc(rec.id)+'\',\''+(rec.archived?"restore":"archive")+'\',false)">'+(rec.archived?"Restore":"Archive")+'</button><button class="d" onclick="delRecord(\''+name+'\',\''+esc(rec.id)+'\')">Delete</button>':''))}
async function editRecord(n,id){openForm(n,await call("platform/r/"+n+"/"+id))}
async function doAction(n,id,a,conf){if(conf&&!confirm("Confirm: "+a+"?"))return;let params={};if(a==="schedule"){const s=prompt("Start date (YYYY-MM-DD)");if(!s)return;params.start=s}
  if(a==="preview"){const v=prompt("Sample values as JSON",'{"name":"Ravi","order":"A1"}');try{params.values=JSON.parse(v||"{}")}catch(e){}}
  try{const r=await call("platform/r/"+n+"/"+id+"/actions/"+a,"POST",{params,confirm:true});await resourcePage(n);await openRecord(n,r.id||id);if(r.result)document.querySelector("#aout").innerHTML='<div class="card mono">'+esc(JSON.stringify(r.result,null,1))+'</div>'}catch(e){document.querySelector("#ferr").textContent=e.message}}
async function delRecord(n,id){if(!confirm("Delete permanently? Archive keeps history."))return;try{await call("platform/r/"+n+"/"+id+"?confirm=true","DELETE");closeDrawer();resourcePage(n)}catch(e){document.querySelector("#ferr").textContent=e.message}}
function drawer(t,b,f){document.querySelector("#dt").textContent=t;document.querySelector("#db").innerHTML=b;document.querySelector("#df").innerHTML=f||"";document.querySelector("#drawer").classList.add("show")}
function closeDrawer(){document.querySelector("#drawer").classList.remove("show")}

/* ------------------------------------------------------ table helper -- */
function grid(items,cols,onclick){if(!items||!items.length)return '<div class="tbl"><div class="empty">Nothing here yet.</div></div>';
  return '<div class="tbl"><table><thead><tr>'+cols.map(c=>'<th>'+esc(c[1])+'</th>').join("")+'</tr></thead><tbody>'+items.map((it,i)=>'<tr class="'+(onclick?"r":"")+'" '+(onclick?'onclick="'+onclick+'('+i+')"':'')+'>'+cols.map(c=>'<td>'+(c[2]?c[2](it[c[0]],it):cell(it[c[0]]))+'</td>').join("")+'</tr>').join("")+'</tbody></table></div>'}
const head=(t,s,extra)=>'<h1>'+t+'</h1><div class="sub">'+s+'</div>'+(extra?'<div class="bar">'+extra+'</div>':'');

/* ------------------------------------------------------------ sponsored -- */
async function sponsored(){const d=await call("sponsored");STATE.sp=d.campaigns;const m=can("sponsored:manage");
  document.querySelector("#page").innerHTML=head("Sponsored campaigns","Paid placements are labelled and always shown after organic results; untargeted ads are never served.",m?'<button class="p" onclick="spForm()">+ New campaign</button>':'')+
  grid(d.campaigns,[["name","Campaign"],["kind","Kind"],["status","Status",badge],["label","Label"],["stats","Impr.",s=>s.impressions],["stats","Clicks",s=>s.clicks],["stats","CTR",s=>s.ctr==null?"—":s.ctr+"%"],["stats","Leads/Orders",s=>s.leads+" / "+s.orders],["stats","Spend",s=>money(s.spend)],["budget","Budget",money]],"spOpen")}
function spForm(c){const F=[["advertiser_id","Advertiser id"],["name","Name"],["kind","Kind"],["title","Title"],["subtitle","Subtitle"],["destination_url","Destination (https)"],["deep_link","Deep link"],["tracking_url","Tracking URL (https)"],["image_url","Image URL"],["categories","Categories (comma)"],["keywords","Keywords (comma)"],["locations","Locations (comma)"],["radius_km","Radius km"],["language","Language (en/te…)"],["audience","Audience"],["objective","Objective"],["format","Format"],["starts_at","Start"],["ends_at","End"],["budget","Total budget ₹"],["daily_budget","Daily budget ₹"],["cost_per_click","Cost per click ₹"],["cost_per_thousand","Cost per 1000 ₹"],["max_impressions","Max impressions"],["max_clicks","Max clicks"],["priority","Priority"]];
  drawer(c?"Edit campaign":"New campaign",F.map(([k,l])=>'<label class="f">'+l+'<input id="sp_'+k+'" value="'+esc(c?(Array.isArray(c[k])?c[k].join(", "):c[k]??""):"")+'"></label>').join("")+'<div id="ferr" class="err"></div>',
  '<button class="p" onclick="spSave('+(c?c.id:"null")+')">Save</button>')}
async function spSave(id){const body={};document.querySelectorAll("[id^=sp_]").forEach(e=>{const k=e.id.slice(3);let v=e.value.trim();if(["categories","keywords","locations"].includes(k))v=v?v.split(",").map(x=>x.trim()):[];if(v!=="")body[k]=v});
  try{id?await call("sponsored/campaigns/"+id,"PATCH",body):await call("sponsored/campaigns","POST",body);closeDrawer();sponsored()}catch(e){document.querySelector("#ferr").textContent=e.message}}
function spOpen(i){const c=STATE.sp[i],m=can("sponsored:manage");drawer(c.name,'<div>'+badge(c.status)+(c.archived?' '+badge("archived"):'')+'</div><table>'+Object.entries(c).filter(([k])=>k!=="stats").map(([k,v])=>'<tr><td class="muted">'+esc(k)+'</td><td>'+cell(v)+'</td></tr>').join("")+'</table><h3>Performance</h3><table>'+Object.entries(c.stats).map(([k,v])=>'<tr><td class="muted">'+esc(k)+'</td><td>'+esc(v??"—")+'</td></tr>').join("")+'</table><div id="ferr" class="err"></div>',
  m?['APPROVED','PAUSED','DISABLED'].map(s=>'<button onclick="spAct('+c.id+',\'status\',\''+s+'\')">'+(s==="APPROVED"?"Approve":s==="PAUSED"?"Pause":"Disable")+'</button>').join("")+'<button onclick=\'spForm(STATE.sp['+i+'])\'>Edit</button><button onclick="spAct('+c.id+',\'duplicate\')">Duplicate</button><button onclick="spAct('+c.id+',\''+(c.archived?"restore":"archive")+'\')">'+(c.archived?"Restore":"Archive")+'</button>':'')}
async function spAct(id,a,s){try{a==="status"?await call("sponsored/campaigns/"+id+"/status","POST",{status:s}):await call("sponsored/campaigns/"+id+"/"+a,"POST");closeDrawer();sponsored()}catch(e){document.querySelector("#ferr").textContent=e.message}}

/* ------------------------------------------------- offers / referrals -- */
async function benefits(){const d=await call("benefits");STATE.bf=d.items;document.querySelector("#page").innerHTML=head("Offers & coupons","Bank / card / UPI and partner offers go live only with a source URL and verification — never invented.")+
  grid(d.items,[["name","Offer"],["offer_type","Type"],["active","Live",v=>v?badge("ACTIVE"):badge("off")],["eligibility","Customers"],["claims","Claims"],["redemptions","Redeemed"],["coupons_available","Codes left"],["verified_at","Verified",when]],"bfOpen")}
async function bfOpen(i){const c=STATE.bf[i];const r=await call("benefits/"+c.id+"/report");const m=can("growth:manage");
  drawer(c.name,'<h3>Usage</h3><table>'+Object.entries(r.usage).map(([k,v])=>'<tr><td class="muted">'+esc(k)+'</td><td>'+cell(v)+'</td></tr>').join("")+'</table><h3>Definition</h3><table>'+Object.entries(c).map(([k,v])=>'<tr><td class="muted">'+esc(k)+'</td><td>'+cell(v)+'</td></tr>').join("")+'</table><div id="ferr" class="err"></div>',
  m?'<button onclick="bfAct('+c.id+',\'active\','+(!c.active)+')">'+(c.active?"Pause":"Activate")+'</button><button onclick="bfAct('+c.id+',\'clone\')">Clone</button><button onclick="bfAct('+c.id+',\''+(c.archived?"restore":"archive")+'\')">'+(c.archived?"Restore":"Archive")+'</button>':'')}
async function bfAct(id,a,v){try{if(a==="active")await call("benefits/"+id,"PATCH",{active:v});else if(a==="clone")await call("benefits/"+id+"/clone","POST");else await call("benefits/"+id+"/archive"+(a==="restore"?"?restore=true":""),"POST");closeDrawer();benefits()}catch(e){document.querySelector("#ferr").textContent=e.message}}
async function referrals(){const d=await call("growth/referrals");document.querySelector("#page").innerHTML=head("Referrals","One credit per person, no self or circular referrals, daily invite cap. Bursts are flagged for review.")+
  grid(d.items,[["code","Code"],["referrer_user_id","Referrer"],["category","Category"],["area","Area"],["status","Status",badge],["review","Review",v=>v?badge("REVIEW")+" "+esc(v):""],["created_at","Created",when]])}

/* ------------------------------------------------------------- money -- */
async function payments(){const d=await call("platform/payments");STATE.pay=d.items;const rc=d.reconciliation;const m=can("payments:manage");
  document.querySelector("#page").innerHTML=head("Payments","Direct methods (COD, cash, direct UPI) work today. Gateways stay unavailable until configured in Integrations. Card data is never stored.",m?'<button class="p" onclick="payForm()">+ Record payment</button>':'')+
  '<div class="kpis">'+Object.entries(rc.totals_by_state||{}).map(([s,v])=>'<div class="kpi"><div class="l">'+badge(s)+'</div><div class="v">'+money(v)+'</div></div>').join("")+'<div class="kpi"><div class="l">Needs attention</div><div class="v">'+(rc.issues||[]).length+'</div></div></div>'+
  grid(d.items,[["id","Payment"],["order_ref","Order"],["method","Method"],["provider","Provider"],["amount","Amount",money],["refunded_amount","Refunded",money],["status","Status",badge],["updated_at","Updated",when]],"payOpen")}
function payForm(){drawer("Record payment",'<label class="f">Idempotency key<input id="p_k" value="pay-'+Date.now()+'"></label><label class="f">Method<select id="p_m">'+SCHEMA.payment_methods.map(x=>'<option>'+x+'</option>').join("")+'</select></label><label class="f">Amount ₹<input id="p_a" type="number"></label><label class="f">Order ref<input id="p_o"></label><label class="f">Provider (gateway methods)<input id="p_p" placeholder="razorpay / cashfree / …"></label><div id="ferr" class="err"></div>',
  '<button class="p" onclick="paySave()">Create</button>')}
async function paySave(){const v=s=>document.querySelector(s).value;try{await call("platform/payments","POST",{idempotency_key:v("#p_k"),method:v("#p_m"),amount:Number(v("#p_a")),order_ref:v("#p_o")||null,provider:v("#p_p")||null});closeDrawer();payments()}catch(e){document.querySelector("#ferr").textContent=e.message}}
function payOpen(i){const p=STATE.pay[i],m=can("payments:manage");drawer(p.id,'<table>'+Object.entries(p).map(([k,v])=>'<tr><td class="muted">'+esc(k)+'</td><td>'+cell(v)+'</td></tr>').join("")+'</table><div id="ferr" class="err"></div>',
  m?[["confirm","Mark received"],["refund","Refund"],["settle","Settle"],["cancel","Cancel"],["fail","Mark failed"],["dispute","Dispute"]].concat(p.provider==="sandbox_gateway"?[["simulate_paid","Sandbox: simulate paid"],["simulate_failed","Sandbox: simulate failed"]]:[]).map(([a,l])=>'<button onclick="payAct(\''+p.id+'\',\''+a+'\')">'+l+'</button>').join(""):'')}
async function payAct(id,a){const body={confirm:true};if(a==="refund"){const x=prompt("Refund amount (empty = full)");if(x===null)return;if(x)body.amount=Number(x)}if(a==="settle"||a==="confirm"){const x=prompt(a==="settle"?"Settlement reference":"Payment reference (optional)");if(x===null)return;body.reference=x}
  if(!["confirm","settle"].includes(a)&&!confirm("Confirm "+a+"?"))return;try{await call("platform/payments/"+id+"/"+a,"POST",body);closeDrawer();payments()}catch(e){document.querySelector("#ferr").textContent=e.message}}
async function ledger(){const d=await call("platform/ledger");STATE.lg=d.items;const s=d.summary;document.querySelector("#page").innerHTML=head("Revenue ledger","Expected → Pending → Confirmed → Paid (or Rejected / Reversed). Confirmed and paid are real revenue; expected is not.",can("finance:manage")?'<button class="p" onclick="lgForm()">+ Add entry</button>':'')+
  '<div class="kpis">'+Object.entries(s.by_state||{}).map(([k,v])=>'<div class="kpi"><div class="l">'+badge(k)+'</div><div class="v">'+money(v)+'</div></div>').join("")+'</div>'+
  grid(d.items,[["kind","Kind"],["amount","Amount",money],["state","State",badge],["partner_id","Partner"],["campaign_id","Campaign"],["order_ref","Order"],["note","Note"],["updated_at","Updated",when]],"lgOpen")}
function lgForm(){drawer("Add ledger entry",'<label class="f">Idempotency key<input id="l_k" value="led-'+Date.now()+'"></label><label class="f">Kind<select id="l_t">'+SCHEMA.ledger_kinds.map(x=>'<option>'+x+'</option>').join("")+'</select></label><label class="f">Amount ₹<input id="l_a" type="number"></label><label class="f">State<select id="l_s">'+SCHEMA.ledger_states.map(x=>'<option>'+x+'</option>').join("")+'</select></label><label class="f">Note<input id="l_n"></label><div id="ferr" class="err"></div>','<button class="p" onclick="lgSave()">Add</button>')}
async function lgSave(){const v=s=>document.querySelector(s).value;try{await call("platform/ledger","POST",{idempotency_key:v("#l_k"),kind:v("#l_t"),amount:Number(v("#l_a")),state:v("#l_s"),note:v("#l_n")});closeDrawer();ledger()}catch(e){document.querySelector("#ferr").textContent=e.message}}
function lgOpen(i){const e=STATE.lg[i];drawer(e.kind,'<table>'+Object.entries(e).map(([k,v])=>'<tr><td class="muted">'+esc(k)+'</td><td>'+cell(v)+'</td></tr>').join("")+'</table><div id="ferr" class="err"></div>',can("finance:manage")?SCHEMA.ledger_states.map(s=>'<button onclick="lgState(\''+e.id+'\',\''+s+'\')">'+s+'</button>').join(""):'')}
async function lgState(id,s){if(["PAID","REVERSED"].includes(s)&&!confirm("Mark "+s+"?"))return;try{await call("platform/ledger/"+id+"/state","POST",{state:s,confirm:true});closeDrawer();ledger()}catch(e){document.querySelector("#ferr").textContent=e.message}}
async function rewards(){const d=await call("platform/rewards");STATE.rw=d.items;document.querySelector("#page").innerHTML=head("Rewards ledger","Cashback, points, merchant and referral rewards with their full state history.")+
  '<div class="kpis">'+Object.entries(d.by_state).map(([k,v])=>'<div class="kpi"><div class="l">'+badge(k)+'</div><div class="v">'+v+'</div></div>').join("")+'</div>'+
  grid(d.items,[["title","Reward"],["reward_type","Type"],["amount","Amount",money],["points","Points"],["state","State",badge],["source","Source"],["expires_at","Expires",when]],"rwOpen")}
function rwOpen(i){const r=STATE.rw[i];drawer(r.title||r.reward_type,'<table>'+Object.entries(r).filter(([k])=>k!=="idempotency_key").map(([k,v])=>'<tr><td class="muted">'+esc(k)+'</td><td>'+cell(v)+'</td></tr>').join("")+'</table><div id="ferr" class="err"></div>',can("rewards:manage")?["AVAILABLE","LOCKED","REDEEMED","EXPIRED","REVERSED"].map(s=>'<button onclick="rwState(\''+r.id+'\',\''+s+'\')">'+s+'</button>').join(""):'')}
async function rwState(id,s){try{await call("platform/rewards/"+id+"/state","POST",{state:s,confirm:true});closeDrawer();rewards()}catch(e){document.querySelector("#ferr").textContent=e.message}}
async function transactions(){const s=STATE.tx||(STATE.tx={kind:"",status:"",q:""});const d=await call("platform/transactions?"+new URLSearchParams(s));
  document.querySelector("#page").innerHTML=head("Transaction center","Payments, refunds, settlements, commissions, rewards, conversions and orders in one place.",'<input placeholder="Search" value="'+esc(s.q)+'" onchange="STATE.tx.q=this.value;transactions()"><select onchange="STATE.tx.kind=this.value;transactions()"><option value="">All kinds</option>'+d.kinds.map(k=>'<option '+(s.kind===k?"selected":"")+'>'+k+'</option>').join("")+'</select>')+
  grid(d.items,[["kind","Kind"],["id","Id"],["amount","Amount",money],["status","Status",badge],["ref","Reference"],["party","Party"],["at","When",when]])}

/* ---------------------------------------------------------- customers -- */
async function support(){const s=STATE.sup||(STATE.sup={status:"",priority:"",sla:"",q:""});const d=await call("escalations?"+new URLSearchParams(s));STATE.tk=d.items;
  document.querySelector("#page").innerHTML=head("Support tickets","SLA: urgent 2 h · high 8 h · normal 24 h · low 72 h. Requesters are masked.",
   ['status','priority','sla'].map(k=>'<select onchange="STATE.sup.'+k+'=this.value;support()"><option value="">'+k+': any</option>'+({status:["OPEN","IN_PROGRESS","WAITING_FOR_USER","RESOLVED","CLOSED"],priority:["URGENT","HIGH","NORMAL","LOW"],sla:["ON_TRACK","DUE_SOON","OVERDUE","MET","BREACHED"]}[k]).map(o=>'<option '+(s[k]===o?"selected":"")+'>'+o+'</option>').join("")+'</select>').join("")+Object.entries(d.sla_summary||{}).map(([k,v])=>badge(k)+' '+v).join(" ")+'<input placeholder="Search tickets" value="'+esc(s.q)+'" onchange="STATE.sup.q=this.value;support()">')+
  grid(d.items,[["id","#"],["issue","Issue",v=>esc(String(v).slice(0,70))],["handoff","Request",h=>esc(((h&&h.request)||"—").slice(0,50))],["category","Category"],["priority","Priority",badge],["channel","Channel"],["status","Status",badge],["sla_state","SLA",badge],["assigned_to","Assigned"],["created_at","Opened",when]],"tkOpen")}
async function tkOpen(i){const t=await call("escalations/"+STATE.tk[i].id);const m=can("support:manage");
  const hf=t.handoff||{};drawer("Ticket #"+t.id,'<div>'+badge(t.status)+' '+badge(t.priority)+' '+badge(t.sla_state)+' <span class="muted">'+esc(t.channel)+' · due '+when(t.sla_due_at)+'</span></div><p>'+esc(t.issue)+'</p>'+
   '<div class="card" style="margin-bottom:10px"><b>Handoff summary</b><p>'+esc(hf.summary||"—")+'</p><table>'+[["Request",hf.request],["Request category",hf.request_category],["Previous actions",(hf.previous_actions||[]).join("; ")],["Deal / order status",hf.status],["Role",hf.role],["Language",hf.language],["Last messages",(hf.last_messages||[]).join(" | ")],["Next step",hf.suggested_next_step]].map(([k,v])=>'<tr><td class="muted">'+k+'</td><td>'+esc(v||"—")+'</td></tr>').join("")+'</table></div><table>'+[["Requester",t.requester],["Category",t.category],["Assigned",t.assigned_to],["First response",when(t.first_response_at)],["Resolved",when(t.resolved_at)],["Resolution",t.resolution_note],["Attachments",(t.attachments||[]).join(", ")]].map(([k,v])=>'<tr><td class="muted">'+k+'</td><td>'+esc(v??"—")+'</td></tr>').join("")+'</table>'+
   (m?'<h3>Update</h3><label class="f">Status<select id="t_s"><option value=""></option>'+["OPEN","IN_PROGRESS","WAITING_FOR_USER","RESOLVED","CLOSED"].map(x=>'<option>'+x+'</option>').join("")+'</select></label><label class="f">Priority<select id="t_p"><option value=""></option>'+["URGENT","HIGH","NORMAL","LOW"].map(x=>'<option>'+x+'</option>').join("")+'</select></label><label class="f">Assign to<input id="t_a" value="'+esc(t.assigned_to||"")+'"></label><label class="f">Internal note<textarea id="t_n"></textarea></label><label class="f">Resolution note<textarea id="t_r"></textarea></label>':'')+
   '<h3>Conversation</h3><div class="hist">'+(t.thread||[]).map(m=>'<div class="'+(m.kind==="note"?"muted":"")+'"><b>'+esc(m.kind==="note"?"Internal note":m.from)+'</b> <span class="muted">'+when(m.at)+'</span><div>'+esc(m.body)+'</div></div>').join("")+'</div>'+
   (can("support:edit")?'<h3>Reply to customer</h3><label class="f">Message (the customer sees this in the app)<textarea id="t_reply"></textarea></label><label class="f">Then<select id="t_after"><option value="WAITING_FOR_USER">Waiting for customer</option><option value="IN_PROGRESS">Keep in progress</option><option value="RESOLVED">Resolve</option></select></label><button class="p" onclick="tkReply('+t.id+','+i+')">Send reply</button> <button onclick="tkEsc('+t.id+','+i+')">Escalate</button> '+(["RESOLVED","CLOSED"].includes(t.status)?'<button onclick="tkReopen('+t.id+','+i+')">Reopen</button>':''):'')+
   '<h3>History</h3><div class="hist">'+t.history.map(h=>'<div><b>'+esc(h.action)+'</b> by '+esc(h.actor)+' <span class="muted">'+when(h.at)+'</span><div class="mono muted">'+esc(JSON.stringify(h.detail))+'</div></div>').join("")+'</div><div id="ferr" class="err"></div>',
   m?'<button class="p" onclick="tkSave('+t.id+','+i+')">Save</button>':'')}
async function tkSave(id,i){const v=s=>document.querySelector(s).value.trim();const b={confirm:true};if(v("#t_s"))b.status=v("#t_s");if(v("#t_p"))b.priority=v("#t_p");if(v("#t_a"))b.assigned_to=v("#t_a");if(v("#t_n"))b.note=v("#t_n");if(v("#t_r"))b.resolution_note=v("#t_r");
  try{await call("escalations/"+id,"PATCH",b);await support();tkOpen(i)}catch(e){document.querySelector("#ferr").textContent=e.message}}
async function tkReply(id,i){const m=document.querySelector("#t_reply").value.trim();if(!m)return;try{await call("escalations/"+id+"/reply","POST",{message:m,status:document.querySelector("#t_after").value});await support();tkOpen(i)}catch(e){document.querySelector("#ferr").textContent=e.message}}
async function tkEsc(id,i){const r=prompt("Why escalate?");if(!r)return;try{await call("escalations/"+id+"/escalate","POST",{reason:r});await support();tkOpen(i)}catch(e){document.querySelector("#ferr").textContent=e.message}}
async function tkReopen(id,i){try{await call("escalations/"+id+"/reopen","POST");await support();tkOpen(i)}catch(e){document.querySelector("#ferr").textContent=e.message}}
async function accounts(){const [u,st]=await Promise.all([call("users"),call("platform/accounts/user")]);const s={};st.items.forEach(x=>s[x.subject_ref]=x);STATE.us=u.items;
  document.querySelector("#page").innerHTML=head("Users & accounts","Contact details stay masked. Blocking signs the person out everywhere at once.")+
  grid(u.items.map(x=>({...x,state:s[x.user_ref]||{}})),[["user","User"],["role","Role"],["business_name","Business"],["active_listings","Listings"],["state","Verified",v=>v.verified?badge("VERIFIED"):""],["state","Access",v=>v.blocked?badge("BLOCKED"):badge("ACTIVE")]],"usOpen")}
function usOpen(i){const u=STATE.us[i],m=can("users:manage");drawer(u.user,'<table>'+Object.entries(u).map(([k,v])=>'<tr><td class="muted">'+esc(k)+'</td><td>'+cell(v)+'</td></tr>').join("")+'</table><label class="f">Note<input id="u_n"></label><div id="ferr" class="err"></div>',
  m?[["blocked",true,"Block"],["blocked",false,"Unblock"],["verified",true,"Verify"],["verified",false,"Unverify"]].map(([k,v,l])=>'<button '+(l==="Block"?'class="d"':'')+' onclick="usSet(\''+u.user_ref+'\',\''+k+'\','+v+')">'+l+'</button>').join(""):'')}
async function usSet(ref,k,v){if(k==="blocked"&&v&&!confirm("Block this account? All sessions stop."))return;try{await call("platform/accounts/user/"+ref,"POST",{[k]:v,confirm:true,note:document.querySelector("#u_n").value});closeDrawer();accounts()}catch(e){document.querySelector("#ferr").textContent=e.message}}

/* ------------------------------------------------------------- system -- */
function envHint(x){const n=[];x.missing.forEach(k=>{const e=(x.env_vars||{})[k];if(e)n.push(e);((x.env_aliases||{})[k]||[]).forEach(a=>n.push(a))});return n.length?"<br>Railway variable: "+n.map(esc).join(" or "):""}
async function integrations(){const d=await call("platform/integrations");STATE.ig=d.items;const groups={};d.items.forEach(x=>(groups[x.group]=groups[x.group]||[]).push(x));const rt=d.runtime||{};
  document.querySelector("#page").innerHTML=head("Integrations","Secrets are encrypted and write-only; nothing is marked LIVE until a live check passes.")+
  '<div class="card" style="margin-bottom:10px"><b>This console reads the '+esc(rt.environment||"local")+' environment</b>'+(rt.service?' · service '+esc(rt.service):'')+(rt.branch?' · branch '+esc(rt.branch):'')+(rt.commit?' · commit '+esc(rt.commit):'')+'<div class="muted">Deployment variables are per Railway environment: a key set on production is not visible here unless this is production.</div></div>'+
  Object.entries(groups).map(([g,items])=>'<h3 style="margin:18px 0 8px;text-transform:capitalize">'+esc(g)+'</h3><div class="cols">'+items.map(x=>'<div class="card"><div style="display:flex;justify-content:space-between;align-items:center"><b>'+esc(x.label)+'</b>'+badge(x.status)+'</div><div class="muted" style="margin:6px 0">'+(x.internal?"Built in":(x.available===false?"Not available in this environment":(x.missing.length?"Missing: "+esc(x.missing.join(", "))+envHint(x):"Configured · "+esc(x.mode||""))+(x.readiness?" · "+esc(x.readiness):"")+(x.status==="MOCK"?" · mock: nothing leaves ASKODOX":"")+((x.warnings||[]).length?'<br><span style="color:#b45309">⚠ '+x.warnings.map(esc).join("<br>⚠ ")+'</span>':"")+(Object.keys(x.sources||{}).length?"<br>Set: "+Object.entries(x.sources).map(([k,v])=>esc(k)+" ("+(v==="environment"?"deployment variable":"Command Center")+")").join(", "):"")))+(x.last_check_at?'<br>Last check '+when(x.last_check_at)+' '+esc(x.last_check_detail||""):'')+'</div>'+(can("integrations:manage")&&!x.internal?'<button onclick="igForm(\''+x.provider+'\')">Configure</button> <button onclick="igCheck(\''+x.provider+'\')">Check</button>'+(["whatsapp_cloud","sms","email","fcm_push"].includes(x.provider)?' <button onclick="igTest(\''+x.provider+'\')">Test send</button>':''):'')+'</div>').join("")+'</div>').join("")}
function igForm(p){const x=STATE.ig.find(i=>i.provider===p);const env=x.env_vars||{};
  const fld=(k,secret)=>'<label class="f">'+esc(k)+(x.required.includes(k)?' *':' <span class="muted">(optional)</span>')+(x.sources&&x.sources[k]?' <span class="muted">— set via '+(x.sources[k]==="environment"?"deployment variable "+esc(env[k]||""):"Command Center")+(secret?"; leave empty to keep":"")+'</span>':(env[k]?' <span class="muted">— or Railway variable '+esc(env[k])+'</span>':''))+'<input id="ig_'+k+'" data-kind="'+(secret?"secret":"config")+'" type="'+(secret?"password":"text")+'" value="'+(secret?"":esc(x.config[k]||""))+'" autocomplete="off"></label>';
  drawer("Configure "+x.label,'<div class="muted">Secret values are write-only: never shown again, never logged. Mock mode needs no credentials and never contacts the provider.</div>'+
  x.secret_names.map(k=>fld(k,true)).join("")+x.config_keys.map(k=>fld(k,false)).join("")+
  '<label class="f">Mode<select id="ig_mode">'+["mock","test","live"].map(m=>'<option '+(x.mode===m?"selected":"")+'>'+m+'</option>').join("")+'</select></label><label class="f">Enabled<select id="ig_en"><option value="true" '+(x.enabled?"selected":"")+'>Yes</option><option value="false" '+(!x.enabled?"selected":"")+'>No</option></select></label><div class="muted">LIVE needs mode "live" and a passed Check.</div><div id="ferr" class="err"></div>','<button class="p" onclick="igSave(\''+p+'\')">Save</button>')}
async function igSave(p){const config={},secrets={};document.querySelectorAll("[id^=ig_][data-kind]").forEach(e=>{if(!e.value)return;(e.dataset.kind==="secret"?secrets:config)[e.id.slice(3)]=e.value});
  try{await call("platform/integrations/"+p,"PUT",{enabled:document.querySelector("#ig_en").value==="true",mode:document.querySelector("#ig_mode").value,config,secrets});closeDrawer();integrations()}catch(e){document.querySelector("#ferr").textContent=e.message}}
async function igTest(p){const to=prompt(p==="email"?"Send a test e-mail to (your own address)":p==="fcm_push"?"Send a test push to user id (app-phone-…)":"Send a test message to (your own mobile, e.g. 98XXXXXXXX)");if(!to)return;
  try{const r=await call("platform/integrations/"+p+"/test-send","POST",{to});alert(r.status+(r.error?" — "+r.error:"")+" · to "+r.to_masked)}catch(e){alert(e.message)}}
async function igCheck(p){try{const r=await call("platform/integrations/"+p+"/check","POST");alert(r.note||("Status: "+r.status));integrations()}catch(e){alert(e.message)}}
async function readiness(){const d=await call("platform/readiness");const yn=v=>v===true?badge("YES"):v===false?badge("NO"):'<span class="muted">tests</span>';
  document.querySelector("#page").innerHTML=head("Integration readiness","Computed from live state ("+esc(d.environment)+"). LIVE needs real credentials and a passed live check; a mock delivery proves the wiring only.")+
  grid(d.items,[["integration","Integration"],["health","Health",(v,r)=>badge(v)+'<div class="muted" style="font-size:12px">'+esc(r.health_reason||"")+'</div>'],["status","Status",badge],["backend_ready","Backend",yn],["admin_control_ready","Admin control",yn],["mock_verified","Mock verified",yn],["real_credential_required","Credential still needed",yn],["providers","Providers",v=>v.map(p=>esc(p.label)+" "+badge(p.status)+(p.missing.length?' <span class="muted">needs '+esc(p.missing.join(", "))+'</span>':'')).join("<br>")]])}
async function outbox(){const d=await call("platform/outbox");document.querySelector("#page").innerHTML=head("Message deliveries","Every WhatsApp / SMS / e-mail / push attempt: MOCK_DELIVERED never left ASKODOX; SKIPPED_* was never sent; recipients are masked.")+
  '<div class="kpis">'+Object.entries(d.summary||{}).map(([c,st])=>'<div class="kpi"><div class="l">'+esc(c)+'</div><div class="v" style="font-size:14px">'+Object.entries(st).map(([k,v])=>esc(k)+": "+v).join("<br>")+'</div></div>').join("")+'</div>'+
  (Object.keys(d.opt_outs||{}).length?'<div class="muted">Customers opted out: '+Object.entries(d.opt_outs).map(([c,n])=>esc(c)+" "+n).join(", ")+'</div>':'')+
  grid(d.items,[["created_at","When",when],["channel","Channel"],["provider","Provider"],["status","Status",badge],["delivery_status","Receipt"],["attempts","Tries"],["to_masked","To"],["event","Event"],["title","Title"],["error","Error"]])}
async function discovered(){const d=await call("platform/web-videos");STATE.wv=d.items;const m=can("content:manage");
  document.querySelector("#page").innerHTML=head("Discovered videos","Real videos found through search. Send one to Pending Review to link it to products, sellers, creators or an affiliate link -- nothing changes for customers until it is approved.")+
  grid(d.items,[["title","Title"],["platform","Platform"],["creator","Channel"],["products","Products",v=>esc((v||[]).join(", "))],["embeddable","Plays in app",v=>v===false?"no":v?"yes":"?"],["last_seen","Last seen",when],["ref","",(r,v)=>v.in_review_queue?badge("IN_REVIEW_QUEUE"):(m?'<button onclick="promote(\''+r+'\')">Send to review</button>':'')]])}
async function promote(ref){try{await call("platform/web-videos/"+ref+"/promote","POST",{});discovered()}catch(e){alert(e.message)}}
async function flags(){const d=await call("config");document.querySelector("#page").innerHTML=head("Feature flags","Every module can be switched off without a release. Switching off needs confirmation and is audited.")+
  grid(d.flags,[["key","Flag",v=>'<span class="mono">'+esc(v)+'</span>'],["description","What it controls"],["enabled","State",v=>v?badge("ENABLED"):badge("DISABLED")],["updated_by","Changed by"],["key","",(k,f)=>can("config:manage")?'<button onclick="flagSet(\''+k+'\','+(!f.enabled)+')">'+(f.enabled?"Switch off":"Switch on")+'</button>':""]])+
  '<div class="card" style="margin-top:14px"><h3>Test targeting</h3><div class="muted">Global flag = master switch; "Feature flag targeting" rules narrow it by category / role / platform / location / %.</div>'+
  '<input id="ft_c" placeholder="category (e.g. footwear)"><input id="ft_r" placeholder="role (buyer, seller…)"><input id="ft_p" placeholder="platform (android, web)"><input id="ft_l" placeholder="location"><input id="ft_s" placeholder="person id (for %)"><button class="p" onclick="flagTest()">Evaluate</button><div id="ft_out"></div></div>'}
async function flagTest(){const v=id=>document.querySelector(id).value.trim();const out=document.querySelector("#ft_out");
  try{const r=await call("flags/evaluate","POST",{category:v("#ft_c"),role:v("#ft_r"),platform:v("#ft_p"),location:v("#ft_l"),subject:v("#ft_s")});
   out.innerHTML='<div class="muted">'+r.rules+' active targeting rule(s)</div>'+grid(Object.entries(r.flags).map(([k,x])=>({key:k,enabled:x.enabled,reason:x.reason})),[["key","Flag",v=>'<span class="mono">'+esc(v)+'</span>'],["enabled","Here",v=>v?badge("ENABLED"):badge("DISABLED")],["reason","Why"]])}catch(e){out.innerHTML='<div class="err">'+esc(e.message)+'</div>'}}
async function flagSet(k,v){if(!v&&!confirm("Switch off "+k+"?"))return;try{await call("config/"+k,"PUT",{enabled:v,confirm:true});flags()}catch(e){alert(e.message)}}
async function staff(){const d=await call("staff");document.querySelector("#page").innerHTML=head("Staff & roles","Staff get a one-time token. A manager can only grant permissions they hold.",'<input id="s_n" placeholder="Name"><select id="s_r">'+Object.keys(d.roles).map(r=>'<option>'+r+'</option>').join("")+'</select><button class="p" onclick="staffAdd()">+ Add staff</button><span id="s_out" class="okm"></span>')+
  grid(d.items,[["name","Name"],["role","Role"],["active","Active",v=>v?badge("ACTIVE"):badge("DISABLED")],["permissions","Permissions",v=>'<span class="muted">'+esc((v||[]).length)+'</span>'],["created_at","Added",when]],"stOpen")+'<h3 style="margin-top:18px">Role presets</h3>'+grid(Object.entries(d.roles).map(([r,p])=>({role:r,permissions:p.join(", ")})),[["role","Role"],["permissions","Permissions"]])}
function stOpen(i){STATE.stSel=i;call("staff").then(d=>{const st=d.items[i];STATE.stData=d;drawer(st.name,'<div>'+badge(st.role)+' '+(st.active?badge("ACTIVE"):badge("DISABLED"))+'</div><label class="f">Grant (comma-separated)<input id="st_g"></label><label class="f">Revoke (comma-separated)<input id="st_r"></label><label class="f">Reason<input id="st_why"></label><div id="st_adv"></div><div id="ferr" class="err"></div><h3>Permissions</h3><div class="mono muted">'+esc(st.permissions.join(", "))+'</div>',
  '<button onclick="stAdvise('+st.id+')">Check risk</button><button class="p" onclick="stSave('+st.id+')">Save</button>')})}
const stList=id=>document.querySelector(id).value.split(",").map(x=>x.trim()).filter(Boolean);
async function stAdvise(id){try{const a=await call("staff/advise","POST",{staff_id:id,grant:stList("#st_g"),revoke:stList("#st_r")});document.querySelector("#st_adv").innerHTML='<div class="card">'+badge(a.risk)+' Permission Safety Advisor'+a.warnings.map(w=>'<div>'+badge(w.level)+' '+esc(w.message)+'</div>').join("")+(a.needs_approval.length?'<div class="muted">Needs Owner approval: '+esc(a.needs_approval.join(", "))+'</div>':'')+(a.cannot_grant.length?'<div class="err">You cannot grant: '+esc(a.cannot_grant.join(", "))+'</div>':'')+'</div>'}catch(e){document.querySelector("#ferr").textContent=e.message}}
async function stSave(id){try{const r=await call("staff/"+id,"PATCH",{grant:stList("#st_g"),revoke:stList("#st_r"),reason:document.querySelector("#st_why").value});closeDrawer();await staff();if(r.approval)alert(r.approval.message)}catch(e){document.querySelector("#ferr").textContent=e.message}}
async function staffAdd(){try{const r=await call("staff","POST",{name:document.querySelector("#s_n").value,role:document.querySelector("#s_r").value});await staff();document.querySelector("#s_out").textContent="Token (shown once): "+r.token}catch(e){alert(e.message)}}
async function audit(){const f=STATE.au||(STATE.au={risk:"",q:"",days:"0"});const d=await call("audit?limit=300&"+new URLSearchParams(f));document.querySelector("#page").innerHTML=head("Audit log","Append-only: who, role, what, target, when, result and risk. Secret values are never stored; nobody can edit this log.",'<select onchange="STATE.au.risk=this.value;audit()"><option value="">risk: any</option>'+["GREEN","ORANGE","RED"].map(x=>'<option '+(f.risk===x?"selected":"")+'>'+x+'</option>').join("")+'</select><input placeholder="Search" value="'+esc(f.q)+'" onchange="STATE.au.q=this.value;audit()">'+(can("audit:export")?'<button onclick="auExport()">Export CSV</button>':''))+grid(d.items,[["created_at","When",when],["actor","Who"],["actor_role","Role"],["action","Action"],["entity_type","Entity"],["entity_id","Target"],["risk","Risk",badge],["result","Result",badge],["before","Old",v=>'<span class="mono muted">'+esc(JSON.stringify(v)).slice(0,120)+'</span>'],["after","New",v=>'<span class="mono muted">'+esc(JSON.stringify(v)).slice(0,120)+'</span>'],["reason","Note"]])}
async function auExport(){const r=await fetch("/admin/cc/audit/export.csv",{headers:hdr()});if(!r.ok){alert("Export failed: "+r.status);return}const b=await r.blob();const a=document.createElement("a");a.href=URL.createObjectURL(b);a.download="askodox-audit.csv";a.click()}
async function events(){const f=STATE.ev||(STATE.ev={event:"",category:"",q:"",days:"7"});const d=await call("platform/events?limit=300&"+new URLSearchParams(f));document.querySelector("#page").innerHTML=head("Event stream","The whole journey with the specific category ASKODOX detected (domain kept separately).",'<select onchange="STATE.ev.event=this.value;events()"><option value="">event: any</option>'+(d.events||[]).map(x=>'<option '+(f.event===x?"selected":"")+'>'+x+'</option>').join("")+'</select><input placeholder="Category" value="'+esc(f.category)+'" onchange="STATE.ev.category=this.value;events()"><input placeholder="Search" value="'+esc(f.q)+'" onchange="STATE.ev.q=this.value;events()"><select onchange="STATE.ev.days=this.value;events()">'+[["1","24 h"],["7","7 days"],["30","30 days"],["0","All"]].map(([v,l])=>'<option value="'+v+'" '+(f.days===v?"selected":"")+'>'+l+'</option>').join("")+'</select>')+grid(d.items,[["at","When",when],["event","Event"],["category","Category"],["subcategory","Subcategory"],["domain","Domain"],["intent","Intent"],["location","Location"],["campaign_id","Campaign"],["click_id","Click"],["value","Value",money],["source","Source"]])}
async function analytics(){const s=STATE.an||(STATE.an={days:30,category:"",location:""});const d=await call("platform/analytics?"+new URLSearchParams(s));const bar=(rows)=>{const mx=Math.max(1,...rows.map(r=>r.count));return '<div class="funnel">'+rows.map(r=>'<div class="row"><span>'+esc(r.step.replace(/_/g," "))+'</span><div class="track"><div class="fill" style="width:'+(r.count/mx*100)+'%"></div></div><b>'+r.count+'</b></div>').join("")+'</div>'};
  document.querySelector("#page").innerHTML=head("Analytics","Filter by period, category and location. Counts come from recorded events only.",'<select onchange="STATE.an.days=this.value;analytics()">'+[7,30,90,365].map(x=>'<option '+(s.days==x?"selected":"")+' value="'+x+'">Last '+x+' days</option>').join("")+'</select><input placeholder="Category" value="'+esc(s.category)+'" onchange="STATE.an.category=this.value;analytics()"><input placeholder="Location" value="'+esc(s.location)+'" onchange="STATE.an.location=this.value;analytics()">')+
  '<div class="kpis"><div class="kpi"><div class="l">Searches</div><div class="v">'+d.searches+'</div></div><div class="kpi"><div class="l">No match</div><div class="v">'+d.no_match+'</div></div><div class="kpi"><div class="l">Active users (24 h)</div><div class="v">'+d.daily_active_users+'</div></div><div class="kpi"><div class="l">Coupon claims / redeemed</div><div class="v">'+d.coupon_claims+' / '+d.coupon_redemptions+'</div></div></div>'+
  '<div class="cols"><div class="card"><h3>Commerce funnel</h3>'+bar(d.funnel)+'</div><div class="card"><h3>Video funnel</h3>'+bar(d.video_funnel)+'</div></div>'}
async function insights(){const d=await call("platform/insights");document.querySelector("#page").innerHTML=head("AI insights",esc(d.note))+'<div class="cols">'+d.items.map(i=>'<div class="card">'+badge(i.severity)+' '+badge(i.confidence||"")+' <b>'+esc(i.observation||i.title)+'</b>'+(i.possible_reason?'<div style="margin-top:6px"><span class="muted">Possible reason:</span> '+esc(i.possible_reason)+'</div>':'')+(i.recommended_action||i.suggestion?'<div style="margin-top:6px"><span class="muted">Recommended:</span> '+esc(i.recommended_action||i.suggestion)+'</div>':'')+(i.impact?'<div style="margin-top:6px"><span class="muted">Impact:</span> '+esc(i.impact)+'</div>':'')+'<div class="mono muted" style="margin-top:6px">'+esc(i.evidence?JSON.stringify(i.evidence):"")+'</div></div>').join("")+'</div>'}

/* ------------------------------------------------------------ approvals -- */
async function approvals(){const f=STATE.ap||(STATE.ap={status:"PENDING"});const d=await call("approvals?"+new URLSearchParams(f));STATE.apItems=d.items;
  document.querySelector("#page").innerHTML=head("Approvals","ORANGE changes need a second person; RED changes need the Owner / Super Admin. Nobody approves their own request.",'<select onchange="STATE.ap.status=this.value;approvals()">'+["PENDING","EXECUTED","REJECTED","FAILED","CANCELLED",""].map(x=>'<option value="'+x+'" '+(f.status===x?"selected":"")+'>'+(x||"all")+'</option>').join("")+'</select>')+
  grid(d.items,[["id","#"],["risk","Risk",badge],["action","Action"],["target","Target"],["requested_by","Requested by"],["requested_at","When",when],["status","Status",badge],["decided_by","Decided by"]],"apOpen")}
function apOpen(i){const a=STATE.apItems[i];drawer("Approval #"+a.id,'<div>'+badge(a.risk)+' '+badge(a.status)+'</div><table>'+[["Action",a.action],["Target",a.target],["Reason",a.reason],["Requested by",a.requested_by+" ("+(a.requested_role||"")+")"],["Requested",when(a.requested_at)],["Decided by",a.decided_by],["Note",a.decision_note]].map(([k,v])=>'<tr><td class="muted">'+k+'</td><td>'+esc(v??"—")+'</td></tr>').join("")+'</table><h3>Current → proposed</h3><div class="mono">'+esc(JSON.stringify(a.old))+'<br>→ '+esc(JSON.stringify(a.proposed))+'</div>'+(a.result?'<h3>Result</h3><div class="mono">'+esc(JSON.stringify(a.result))+'</div>':'')+'<label class="f">Note<input id="ap_n"></label><div id="ferr" class="err"></div>',
  a.status==="PENDING"&&can("approvals:approve")?'<button class="p" onclick="apDecide('+a.id+',true,\''+a.risk+'\')">Approve</button><button class="d" onclick="apDecide('+a.id+',false)">Reject</button>':'')}
async function apDecide(id,ok,risk){if(ok&&risk==="RED"&&!confirm("Approve a RED change? It is applied immediately."))return;try{await call("approvals/"+id+"/"+(ok?"approve":"reject"),"POST",{note:document.querySelector("#ap_n").value,confirm:true});closeDrawer();approvals()}catch(e){document.querySelector("#ferr").textContent=e.message}}

/* ---------------------------------------------------------- self-heal -- */
async function selfheal(){const d=await call("selfheal");STATE.sh=d.items;const m=can("selfheal:manage"),st=d.settings;
  document.querySelector("#page").innerHTML=head("Self-healing","GREEN: safe, temporary and reversible (auto only when switched on). ORANGE: proposed, a person approves. RED (payments, refunds, credentials, security, permissions, deploys, privacy, ledgers, deletions): never automated — Owner alert only.",(m?'<button class="p" onclick="shScan()">Scan now</button>':'')+' Self-healing '+badge(st.enabled?"ON":"OFF")+' · GREEN auto '+badge(st.green_auto?"ON":"OFF")+' · ORANGE '+badge("APPROVAL")+' · RED '+badge("OWNER ONLY")+' <span class="muted">(switch in Feature flags: selfheal.enabled, selfheal.green_auto)</span>')+
  (d.bypassed_sources.length?'<div class="card">Bypassed now: '+d.bypassed_sources.map(esc).join(", ")+'</div>':'')+
  grid(d.items,[["created_at","When",when],["risk","Risk",badge],["issue","Issue"],["action","Action"],["status","Status",badge],["result","Result"],["expires_at","Until",when]],"shOpen")}
function shOpen(i){const x=STATE.sh[i],m=can("selfheal:manage");drawer("Issue #"+x.id,'<div>'+badge(x.risk)+' '+badge(x.status)+'</div><table>'+[["Issue",x.issue],["Action",x.action+" "+(x.target||"")],["Reason",x.reason],["Result",x.result],["Rollback",x.rollback],["Evidence",JSON.stringify(x.evidence)],["Approval",x.approval_id]].map(([k,v])=>'<tr><td class="muted">'+k+'</td><td>'+esc(v??"—")+'</td></tr>').join("")+'</table><div id="ferr" class="err"></div>',
  m?(x.risk==="GREEN"&&x.status==="PROPOSED"?'<button class="p" onclick="shDo('+x.id+',\'apply\')">Apply</button>':'')+(x.status==="APPLIED"?'<button onclick="shDo('+x.id+',\'rollback\')">Rollback</button>':''):'')}
async function shDo(id,what){try{await call("selfheal/"+id+"/"+what,"POST");closeDrawer();selfheal()}catch(e){document.querySelector("#ferr").textContent=e.message}}
async function shScan(){try{const r=await call("selfheal/scan","POST");await selfheal();if(r.ran===false)alert(r.reason)}catch(e){alert(e.message)}}

/* ---------------------------------------------------- revenue command -- */
async function revcmd(){const f=STATE.rc||(STATE.rc={period:"30d",start:"",end:""});const d=await call("platform/revenue-command?"+new URLSearchParams(f));const t=d.totals;
  document.querySelector("#page").innerHTML=head("Revenue command center","Only recorded revenue, each record counted once. Expected / pending are not revenue until confirmed; customer payments to merchants are GMV.",'<select onchange="STATE.rc.period=this.value;revcmd()">'+[["today","Today"],["7d","7 days"],["30d","30 days"],["month","This month"],["custom","Custom"]].map(([v,l])=>'<option value="'+v+'" '+(f.period===v?"selected":"")+'>'+l+'</option>').join("")+'</select>'+(f.period==="custom"?'<input type="date" value="'+esc(f.start)+'" onchange="STATE.rc.start=this.value"><input type="date" value="'+esc(f.end)+'" onchange="STATE.rc.end=this.value"><button onclick="revcmd()">Apply</button>':''))+
  '<div class="kpis">'+[["Gross (confirmed + paid)",t.gross],["Net",t.net],["Expected",t.expected],["Pending",t.pending],["Confirmed",t.confirmed],["Paid",t.paid],["Refunds / reversals",t.refund],["Reward cost",t.reward_cost],["GMV (merchant payments)",d.gmv_customer_payments]].map(([l,v])=>'<div class="kpi"><div class="l">'+l+'</div><div class="v">'+money(v)+'</div></div>').join("")+'</div>'+
  '<h3>By source</h3>'+grid(Object.entries(d.by_source).map(([k,v])=>({source:k,...v})).filter(x=>x.expected_total||x.refund),[["source","Source"],["expected","Expected",money],["pending","Pending",money],["confirmed","Confirmed",money],["paid","Paid",money],["refund","Refund",money],["gross","Gross",money]])+
  ["campaign","merchant","affiliate","category","location"].map(k=>'<h3>By '+k+'</h3>'+grid(d.breakdowns[k],[["key",k],["gross","Gross",money],["expected","Expected",money],["refund","Refund",money]])).join("")+
  '<h3>Reconciliation</h3><div class="card">'+(d.reconciliation.issues.length?d.reconciliation.issues.map(x=>'<div>'+badge("ERROR")+' '+esc(x.ledger_id+": "+x.issue)+'</div>').join(""):badge("OK")+' '+d.reconciliation.checked+' ledger entries checked')+(d.duplicates_skipped.length?'<div class="muted">Counted once: '+d.duplicates_skipped.length+' duplicate record(s)</div>':'')+'</div><div class="muted">'+d.notes.map(esc).join("<br>")+'</div>'}

/* -------------------------------------------------------- screen guide -- */
async function screenguide(){const d=await call("companion/screen-guide");const s=d.stats;const kv=o=>Object.entries(o||{}).map(([k,v])=>esc(k)+': <b>'+v+'</b>').join(" · ")||"—";
  document.querySelector("#page").innerHTML=head("AI Companion — Screen Guide","Aggregate counts only: no screenshots, screen text or personal content ever reach the Command Center.",'Feature '+badge(d.enabled?"ON":"OFF")+' <span class="muted">(flag '+esc(d.flag)+')</span> · AI model '+badge(d.model_configured?"OK":"RULES ONLY"))+
  '<div class="kpis">'+[["Sessions (30 d)",s.sessions_started],["Active now",s.active_sessions],["Completed",s.successes],["Abandoned",s.abandoned],["Failed",s.failures],["Resumes after pause",s.resumes]].map(([l,v])=>'<div class="kpi"><div class="l">'+l+'</div><div class="v">'+v+'</div></div>').join("")+'</div>'+
  '<div class="cols">'+[["Privacy pauses / blocks",s.privacy_pauses],["Failure points",s.failure_points],["Languages",s.languages],["Task categories",s.categories],["Steps (model / rules)",s.steps]].map(([l,v])=>'<div class="card"><h3>'+l+'</h3>'+kv(v)+'</div>').join("")+'<div class="card"><h3>Permission health</h3>'+Object.entries(s.permission_health||{}).map(([k,v])=>esc(k)+': '+kv(v)).join("<br>")+'</div></div>'+
  '<div class="card"><h3>Privacy</h3>'+d.privacy.map(esc).join("<br>")+'</div>'}

async function setup(){const d=await call("owner/setup");const kv=o=>Object.entries(o||{}).map(([k,v])=>esc(k)+': <b>'+esc(String(v))+'</b>').join("<br>")||"—";
  document.querySelector("#page").innerHTML=head("ASKODOX setup","What is configured, what is not, and what only the Owner can do. Environment: "+esc(d.environment),can("config:manage")&&d.environment!=="production"?'<button class="btn" id="seed">Load staging test defaults</button>':'<span class="muted">Staging defaults: not available here</span>')+
  '<div class="cols"><div class="card"><h3>Domain &amp; e-mail roles</h3>'+(d.email_roles.map(e=>esc(e.role)+': '+esc(e.address)+' · '+esc(e.mode)+' · '+badge(e.status)+(e.verified_on?' · verified '+esc(e.verified_on):' · <span class="muted">not verified</span>')).join("<br>")||"None yet — add them under Domain &amp; e-mail roles.")+'</div>'+
  '<div class="card"><h3>Phone-test findings</h3>'+kv(d.qa)+'</div><div class="card"><h3>Owner OS switches</h3>'+Object.entries(d.flags).map(([k,v])=>esc(k)+' '+badge(v?"ON":"OFF")).join("<br>")+'<br><span class="muted">Change in Feature flags (approval rules apply).</span></div>'+
  '<div class="card"><h3>Referral credit rule</h3>'+(d.credit_rule?esc(d.credit_rule):'<span class="muted">No ACTIVE rule — referrals earn no credits.</span>')+'</div>'+
  '<div class="card"><h3>Integrations</h3>'+d.integrations.map(i=>esc(i.key)+' '+badge(i.status)).join("<br>")+'</div></div>';
  const b=document.querySelector("#seed");if(b)b.onclick=async()=>{const r=await call("owner/seed-staging","POST",{});alert("Created: "+JSON.stringify(r.created));setup()}}

/* ------------------------------------------- affiliate product manager -- */
const AFP={meesho:"Meesho",amazon:"Amazon",flipkart:"Flipkart",wishlink:"Wishlink",other:"Other"};
function afWhy(ev){return (ev.reasons||[]).map(r=>r.replace(/_/g," ")).join(", ")}
async function affproducts(){const s=STATE.af||(STATE.af={q:"",platform:"",stock:"",commission:"",state:""});
  const d=await call("affiliate-products?"+new URLSearchParams(s));STATE.afcan=d.can;const sm=d.summary;
  const sel=(k,opts,label)=>'<select onchange="STATE.af.'+k+'=this.value;affproducts()"><option value="">'+label+': any</option>'+opts.map(o=>'<option '+(s[k]===o?"selected":"")+'>'+o+'</option>').join("")+'</select>';
  const k=(l,v)=>'<div class="kpi"><div class="l">'+l+'</div><div class="v">'+v+'</div></div>';
  document.querySelector("#page").innerHTML=head("Affiliate products","Staff-managed Meesho / Amazon / Flipkart / Wishlink products. Out of stock = not recommended; commission ACTIVE + affiliate link = monetized link, otherwise the normal (organic) link.",
   '<input placeholder="Search…" value="'+esc(s.q)+'" onchange="STATE.af.q=this.value;affproducts()">'+sel("platform",Object.keys(AFP),"Source")+sel("stock",["IN_STOCK","OUT_OF_STOCK","UNKNOWN"],"Stock")+sel("commission",["ACTIVE","INACTIVE","UNKNOWN"],"Commission")+sel("state",["ACTIVE","DISABLED"],"Result")+
   '<span class="right"></span>'+(d.can.bulk_import?'<button onclick="affBulk()">Bulk / feed import</button>':'')+(d.can.create?'<button class="p" onclick="affForm()">+ Add product</button>':''))+
   '<div class="kpis">'+k("Products",sm.total)+k("Shown in results",sm.eligible)+k("Out of stock",sm.out_of_stock)+k("Commission active",sm.commission_active)+k("Affiliate-routed",sm.affiliate_routed)+'</div>'+
   '<div class="tbl">'+(d.items.length?'<table><thead><tr><th>Product</th><th>Price</th><th>Stock</th><th>Commission</th><th>Link</th><th>Result</th><th>Last checked</th></tr></thead><tbody>'+
   d.items.map(i=>'<tr class="r" onclick="affOpen('+i.id+')"><td>'+(i.image_url?'<img src="'+esc(i.image_url)+'" style="width:34px;height:34px;object-fit:cover;border-radius:6px;vertical-align:middle;margin-right:8px">':'')+'<b>'+esc(i.title)+'</b><div class="muted">'+esc(i.platform_name)+(i.seller?' · '+esc(i.seller):'')+(i.sponsored?' · sponsored':'')+'</div></td>'+
    '<td>'+money(i.price)+(i.mrp?'<div class="muted"><s>'+money(i.mrp)+'</s>'+(i.discount_percent?' '+i.discount_percent+'% off':'')+'</div>':'')+'</td><td>'+badge(i.stock_status)+'</td><td>'+badge(i.commission_status)+'</td><td>'+badge(i.eligibility.link)+'<div class="muted">routes '+i.eligibility.routing+'</div></td>'+
    '<td>'+badge(i.eligibility.state)+'<div class="muted">'+esc(afWhy(i.eligibility))+'</div></td><td class="muted">'+when(i.eligibility.last_checked)+'<div>'+esc(i.stock_check_source||i.commission_check_source||"")+'</div></td></tr>').join("")+'</tbody></table>'
   :'<div class="empty">No products yet.'+(d.can.create?' Use <b>+ Add product</b> or <b>Bulk / feed import</b>.':'')+'</div>')+'</div>'}
async function affApi(id){try{const r=await call("affiliate-products/"+id+"/api-refresh","POST");
  alert(r.applied?"Updated from the marketplace API":(r.mock?"MOCK answer (preview only, nothing saved): "+(r.fields||{}).title:(r.error||r.reason||"Not available")));if(r.applied)affOpen(id)}catch(e){alert(e.message)}}
async function affOpen(id){const d=await call("affiliate-products/"+id),i=d.item,c=STATE.afcan||{},ev=i.eligibility;
  const row=(l,v)=>'<tr><td class="muted" style="width:38%">'+l+'</td><td>'+v+'</td></tr>';
  const link=u=>u?'<a href="'+esc(u)+'" target="_blank" rel="noopener">'+esc(String(u).slice(0,48))+'</a>':'<span class="muted">—</span>';
  const st=(kind,val)=>'<button onclick="affState('+id+',\''+kind+'\',\''+val+'\')">'+val.replace(/_/g," ")+'</button>';
  drawer(i.title,'<div style="margin-bottom:10px">'+badge(ev.state)+' '+badge(i.stock_status)+' '+badge("commission "+i.commission_status)+' '+badge(ev.link)+'</div>'+
   (ev.reasons.length?'<div class="card err">Not shown in results: '+esc(afWhy(ev))+'</div>':'')+
   '<div class="muted" style="margin:6px 0 12px">Opens via the <b>'+ev.routing+'</b> link'+(ev.routing_reasons.length?' ('+esc(ev.routing_reasons.join(", ").replace(/_/g," "))+')':'')+'.</div>'+
   (i.images.length?'<div style="display:flex;gap:6px;overflow:auto;margin-bottom:10px">'+i.images.map(u=>'<img src="'+esc(u)+'" style="height:70px;border-radius:8px">').join("")+'</div>':'')+
   '<table>'+row("Source",esc(i.platform_name))+row("Normal URL",link(i.original_product_url))+row("Affiliate URL",link(i.affiliate_url))+row("Price",money(i.price)+(i.mrp?' · MRP '+money(i.mrp):''))+
   row("Category",esc(i.category)+(i.subcategory?' / '+esc(i.subcategory):''))+row("Sizes / variants",esc(i.variants.join(", "))||"—")+row("Seller",esc(i.seller)||"—")+row("Location / availability",esc([i.location,i.availability].filter(Boolean).join(" · "))||"—")+
   row("Stock checked",when(i.stock_checked_at)+' '+esc(i.stock_check_source))+row("Commission checked",when(i.commission_checked_at)+' '+esc(i.commission_check_source)+(i.verified_commission_rate!=null?' · '+i.verified_commission_rate+'%':''))+
   row("Description",esc(i.description)||"—")+row("Added by",esc(i.created_by)+' · '+when(i.created_at))+'</table>'+
   (c.stock?'<h3 style="margin:14px 0 6px;font-size:14px">Stock</h3>'+["IN_STOCK","OUT_OF_STOCK","UNKNOWN"].map(v=>st("stock",v)).join("")+(["amazon","flipkart"].includes(i.platform)?' <button onclick="affApi('+id+')">Refresh from marketplace API</button>':''):'')+
   (c.commission?'<h3 style="margin:14px 0 6px;font-size:14px">Commission</h3>'+["ACTIVE","INACTIVE","UNKNOWN"].map(v=>st("commission",v)).join(""):'')+
   '<h3 style="margin:18px 0 8px;font-size:14px">History</h3><div class="hist">'+d.history.map(h=>'<div><b>'+esc(h.action)+'</b> by '+esc(h.actor)+' <span class="muted">'+when(h.at)+' · '+esc(h.check_source)+'</span><div class="muted mono">'+esc(Object.entries(h.changes).filter(([k,v])=>v&&typeof v==="object"&&"to" in v).map(([k,v])=>k+": "+(v.from??"—")+" → "+(v.to??"—")).join("; "))+'</div></div>').join("")+'</div><div id="ferr" class="err"></div>',
   (c.edit?'<button class="p" onclick="affForm('+id+')">Edit</button><button onclick="affToggle('+id+','+(i.active?"'disable'":"'enable'")+')">'+(i.active?"Disable":"Enable")+'</button>':'')+(c.delete?'<button class="d" onclick="affDelete('+id+')">Delete</button>':''))}
async function affState(id,kind,val){try{await call("affiliate-products/"+id+"/"+kind,"POST",{status:val});await affproducts();await affOpen(id)}catch(e){document.querySelector("#ferr").textContent=e.message}}
async function affToggle(id,a){try{await call("affiliate-products/"+id+"/"+a,"POST",{});await affproducts();await affOpen(id)}catch(e){document.querySelector("#ferr").textContent=e.message}}
async function affDelete(id){if(!confirm("Delete this product? It stops showing; its history is kept."))return;try{await call("affiliate-products/"+id+"?confirm=true","DELETE");closeDrawer();affproducts()}catch(e){document.querySelector("#ferr").textContent=e.message}}
const AFF_FIELDS=[["original_product_url","Normal product URL *"],["platform","Source"],["title","Product name *"],["affiliate_url","Affiliate URL / deep link"],["images","Image URLs (comma separated)"],["price","Current price (₹)"],["mrp","Original price / MRP (₹)"],["category","Category"],["subcategory","Subcategory"],["description","Description"],["variants","Sizes / variants (comma separated)"],["seller","Seller"],["brand","Brand"],["product_id","Marketplace product ID"],["canonical_url","Canonical URL"],["location","Location"],["availability","Availability (e.g. All India)"],["sponsored","Sponsored"],["stock_status","Stock"],["commission_status","Commission"]];
async function affForm(id){const c=STATE.afcan||{};const i=id?(await call("affiliate-products/"+id)).item:{};
  const f=([k,l])=>{const v=i[k];let el;
    if(k==="platform")el='<select id="af_platform">'+Object.entries(AFP).map(([p,n])=>'<option value="'+p+'" '+(v===p?"selected":"")+'>'+n+'</option>').join("")+'</select>';
    else if(k==="sponsored")el='<select id="af_sponsored"><option value="false">No</option><option value="true" '+(v?"selected":"")+'>Yes</option></select>';
    else if(k==="stock_status"){if(!c.stock||id)return "";el='<select id="af_stock_status"><option>UNKNOWN</option><option>IN_STOCK</option><option>OUT_OF_STOCK</option></select>'}
    else if(k==="commission_status"){if(!c.commission||id)return "";el='<select id="af_commission_status"><option>UNKNOWN</option><option>ACTIVE</option><option>INACTIVE</option></select>'}
    else if(k==="description")el='<textarea id="af_description">'+esc(v||"")+'</textarea>';
    else el='<input id="af_'+k+'" value="'+esc(Array.isArray(v)?v.join(", "):(v??""))+'"'+(k==="affiliate_url"&&!c.links?' disabled title="Needs the affiliate_products:links permission"':'')+'>';
    return '<label class="f">'+l+el+'</label>'};
  drawer(id?"Edit product":"Add product",(id?'':'<div class="muted" style="margin-bottom:8px">Paste the product page URL and press <b>Fetch details</b>: name, images and price are read from the page\'s own metadata where the site allows it. Always check them.</div><button onclick="affExtract()">Fetch details</button><div id="af_note" class="muted" style="margin:6px 0"></div>')+AFF_FIELDS.map(f).join("")+'<div id="ferr" class="err"></div>',
   '<button class="p" onclick="affSave('+(id||0)+')">Save</button><button onclick="closeDrawer()">Cancel</button>')}
async function affExtract(){const url=document.querySelector("#af_original_product_url").value.trim();const n=document.querySelector("#af_note");n.textContent="Reading the page…";
  try{const r=await call("affiliate-products/extract","POST",{url});const fl=r.fields||{};
    for(const [k,v] of Object.entries(fl)){const el=document.querySelector("#af_"+k);if(el&&v!=null&&v!==""&&!el.disabled)el.value=Array.isArray(v)?v.join(", "):v}
    const ss=document.querySelector("#af_stock_status");if(ss&&r.suggested_stock)ss.value=r.suggested_stock;n.textContent=r.note+(r.found.length?" Found: "+r.found.join(", "):"");
    const fs=r.field_status||{};document.querySelectorAll(".af_manual").forEach(x=>x.remove());
    for(const [k,st] of Object.entries(fs)){const el=document.querySelector("#af_"+(k==="images"?"images":k));if(el&&st==="manual_entry_required"&&!el.value)el.insertAdjacentHTML("afterend",'<span class="af_manual err" style="font-size:12px">Manual entry required</span>')}}catch(e){n.textContent=e.message}}
async function affSave(id){const out={};for(const [k] of AFF_FIELDS){const el=document.querySelector("#af_"+k);if(!el||el.disabled)continue;let v=el.value.trim();
    if(k==="images"||k==="variants")v=v?v.split(",").map(x=>x.trim()).filter(Boolean):[];else if(k==="price"||k==="mrp")v=v===""?null:Number(v);else if(k==="sponsored")v=v==="true";else if(v==="")v=null;
    if(!id&&(v===null||(Array.isArray(v)&&!v.length)))continue;out[k]=v}
  try{const r=id?await call("affiliate-products/"+id,"PATCH",out):await call("affiliate-products","POST",out);await affproducts();affOpen(r.item.id)}catch(e){document.querySelector("#ferr").textContent=e.message}}
function affBulk(){const c=STATE.afcan||{};drawer("Bulk / feed import",'<div class="muted">CSV with a header row, e.g.<div class="mono">platform,title,url,affiliate_url,price,original_price,category,stock,commission,image</div>'+
   '<b>Add / update</b> creates or edits products. <b>Status feed</b> only updates stock / commission / price of products already in the catalog (from a trusted partner feed) and never creates any. Stock, commission and affiliate-link columns need their own permissions.</div>'+
   '<label class="f">Mode<select id="ab_mode"><option value="upsert">Add / update products</option><option value="status">Status feed (stock / commission / price)</option></select></label>'+
   '<label class="f">Check source<select id="ab_src"><option value="manual">Manual (staff)</option><option value="feed">Trusted feed</option></select></label>'+
   '<label class="f">CSV<textarea id="ab_csv" class="mono" style="min-height:180px"></textarea></label><div id="ab_out"></div><div id="ferr" class="err"></div>',
   '<button onclick="affBulkRun(true)">Check (dry run)</button><button class="p" onclick="affBulkRun(false)">Import</button><button onclick="closeDrawer()">Close</button>')}
async function affBulkRun(dry){try{const r=await call("affiliate-products/bulk","POST",{csv:document.querySelector("#ab_csv").value,mode:document.querySelector("#ab_mode").value,check_source:document.querySelector("#ab_src").value,dry_run:dry});
  document.querySelector("#ab_out").innerHTML='<div class="card"><b>'+(dry?"Dry run: ":"")+r.ok+' ok, '+r.failed+' failed</b>'+r.results.filter(x=>!x.ok).map(x=>'<div class="err">Row '+(x.row+1)+': '+esc(x.error)+'</div>').join("")+'</div>';if(!dry)affproducts()}catch(e){document.querySelector("#ferr").textContent=e.message}}
async function affsources(){const d=await call("affiliate-sources");const manage=can("affiliate:manage")||can("integrations:manage");
  const yn=(p,k,v)=>manage?'<select onchange="affSrc(\''+p+'\',\''+k+'\',this.value===\'true\')"><option value="true" '+(v?"selected":"")+'>On</option><option value="false" '+(!v?"selected":"")+'>Off</option></select>':badge(v?"ON":"OFF");
  const pick=(p,k,v,opts)=>manage?'<select onchange="affSrc(\''+p+'\',\''+k+'\',this.value)">'+opts.map(o=>'<option '+(v===o?"selected":"")+'>'+o+'</option>').join("")+'</select>':badge(v);
  document.querySelector("#page").innerHTML=head("Affiliate sources","One place per provider: organic results, affiliate monetization, data mode, commission state and health. Credentials are never shown here.")+
   '<div class="card muted" style="margin-bottom:12px">'+esc(d.notes.organic)+'<br>'+esc(d.notes.api)+'<div style="margin-top:8px">Product APIs: '+Object.values(d.apis||{}).map(a=>'<span title="'+esc(a.reason)+'">'+esc(a.platform)+' '+badge(a.status)+'</span>').join(" ")+'</div></div>'+
   '<div class="tbl"><table><thead><tr><th>Source</th><th>Organic results</th><th>Affiliate monetization</th><th>Mode</th><th>Commission (source)</th><th>Health</th><th>Catalog</th><th>Tracking / API</th></tr></thead><tbody>'+
   d.items.map(s=>'<tr><td><b>'+esc(s.name)+'</b><div class="muted">'+(s.organic_search?"web search + staff catalog":"staff catalog only")+'</div></td><td>'+yn(s.platform,"organic_enabled",s.organic_enabled)+'</td><td>'+yn(s.platform,"monetization_enabled",s.monetization_enabled)+'</td>'+
    '<td>'+pick(s.platform,"mode",s.mode,["manual","feed","api"])+'</td><td>'+pick(s.platform,"commission_state",s.commission_state,["UNKNOWN","ACTIVE","INACTIVE"])+'</td>'+
    '<td>'+badge(s.health.status)+'<div class="muted">'+(s.health.method?esc(s.health.method)+' · ':'')+'last ok '+when(s.health.last_success_at)+'</div><div class="muted">checked '+when(s.health.last_check_at)+'</div></td>'+
    '<td>'+s.catalog.products+' products<div class="muted">'+s.catalog.eligible+' shown · '+s.catalog.out_of_stock+' out of stock · '+s.catalog.affiliate_routed+' affiliate</div></td>'+
    '<td class="muted">'+[s.tracking_template_set?"tracking template":"",s.deep_link_set?"deep link":"",s.api_enabled?"API on":"",s.callback_enabled?"callbacks on":"",s.has_credentials?"credentials stored":""].filter(Boolean).join(", ")+'</td></tr>').join("")+'</tbody></table></div>'+
   '<div class="muted" style="margin-top:10px">Staff permissions: '+esc(d.items[0].staff_permissions.join(", "))+'. Grant them in Staff &amp; roles (preset <b>affiliate_catalog_staff</b>).</div>'}
async function affSrc(p,k,v){try{await call("affiliate-sources/"+p,"PUT",{[k]:v});affsources()}catch(e){alert(e.message);affsources()}}

/* ------------------------------------------- demand intelligence / ops -- */
async function demand(){const s=STATE.dm||(STATE.dm={days:7,category:"",area:""});
  const [d,o]=await Promise.all([call("demand/insights?"+new URLSearchParams(s)),call("demand/opportunities")]);STATE.dmo=o.items;
  const k=(l,v,x)=>'<div class="kpi"><div class="l">'+l+'</div><div class="v">'+v+'</div><div class="s">'+(x||"")+'</div></div>';
  const list=(rows,f)=>rows.length?'<table>'+rows.map(f).join("")+'</table>':'<div class="muted">Nothing recorded in this period.</div>';
  const notify=can("demand:notify");
  document.querySelector("#page").innerHTML=head("Demand intelligence","What customers search for, what they fail to find, and which registered sellers could serve it. Recorded events only -- nothing estimated.",
   '<select onchange="STATE.dm.days=this.value;demand()">'+[1,7,30,90].map(n=>'<option '+(String(s.days)===String(n)?"selected":"")+' value="'+n+'">'+(n===1?"Today":n+" days")+'</option>').join("")+'</select><input placeholder="Category" value="'+esc(s.category)+'" onchange="STATE.dm.category=this.value;demand()"><input placeholder="Area" value="'+esc(s.area)+'" onchange="STATE.dm.area=this.value;demand()">'+
   (notify?'<span class="right"></span><button onclick="demandRun()">Run all active rules</button>':''))+
   '<div class="kpis">'+k("Searches",d.totals.searches,"previous period "+d.totals.previous_searches)+k("Distinct needs",d.totals.distinct_needs)+k("No result",d.totals.no_result_searches,"rate "+Math.round(d.rates.no_result_rate*100)+"%")+k("No local supply",d.totals.no_local_supply_searches)+k("Requests / search",d.rates.request_per_search)+k("Accept / request",d.rates.accept_per_request)+'</div>'+
   '<div class="cols"><div class="card"><h3>Most searched</h3>'+list(d.top_searches,t=>'<tr><td>'+esc(t.subject)+'</td><td><b>'+t.count+'</b></td><td class="muted">'+(t.no_local_supply?t.no_local_supply+' without local supply':'')+'</td><td class="muted">'+esc(Object.keys(t.budget_bands).join(", "))+'</td></tr>')+'</div>'+
   '<div class="card"><h3>Unmet demand</h3>'+list(d.unmet,t=>'<tr><td>'+esc(t.subject)+'</td><td><b>'+t.count+'</b></td><td class="muted">'+Math.round(t.share_no_local*100)+'% no local</td></tr>')+'</div>'+
   '<div class="card"><h3>Rising</h3>'+list(d.rising,t=>'<tr><td>'+esc(t.subject)+'</td><td><b>'+t.now+'</b></td><td class="muted">'+(t.change_pct==null?"new":"+"+t.change_pct+"%")+'</td></tr>')+'</div>'+
   '<div class="card"><h3>By area</h3>'+list(d.by_area,t=>'<tr><td>'+esc(t.area)+'</td><td><b>'+t.count+'</b></td></tr>')+'</div>'+
   '<div class="card"><h3>Funnel</h3>'+list(Object.entries(d.funnel),([e,n])=>'<tr><td>'+esc(e.replace(/_/g," "))+'</td><td><b>'+n+'</b></td></tr>')+'</div></div>'+
   '<h3 style="margin:18px 0 8px">Opportunities (from ACTIVE demand alert rules)</h3>'+(o.note?'<div class="card muted">'+esc(o.note)+' <a onclick="go(\'r:demand_alert_rules\')">Demand alert rules</a></div>':'')+
   '<div class="tbl">'+(o.items.length?'<table><thead><tr><th>Need</th><th>Area</th><th>Searches</th><th>Budget</th><th>Local results</th><th>Rule</th><th></th></tr></thead><tbody>'+
   o.items.map((x,i)=>'<tr><td><b>'+esc(x.subject)+'</b></td><td>'+esc(x.area||"—")+'</td><td>'+x.searches+'</td><td>'+esc(x.budget_band||"—")+'</td><td>'+x.local_results_median+'</td><td class="muted">'+esc(x.rule)+'</td><td><button onclick="demandPreview('+i+')">Who &amp; why</button></td></tr>').join("")+'</tbody></table>':'<div class="empty">No demand passes the rule thresholds right now.</div>')+'</div>'}
async function demandPreview(i){const x=STATE.dmo[i];const p=await call("demand/opportunities/preview","POST",{rule_id:x.rule_id,opportunity_key:x.key});
  drawer(x.subject+(x.area?" · "+x.area:""),'<div class="muted">'+x.searches+' searches · budget '+esc(x.budget_band||"—")+' · rule '+esc(x.rule)+'</div>'+
   '<h3 style="margin:14px 0 6px;font-size:14px">Would be alerted ('+p.eligible.length+')</h3>'+(p.eligible.length?p.eligible.map(e=>'<div class="card" style="margin-bottom:6px"><b class="mono">'+esc(e.recipient)+'</b> score '+e.score+'<ul>'+e.reasons.map(r=>'<li>'+esc(r)+'</li>').join("")+'</ul></div>').join(""):'<div class="muted">Nobody eligible -- consider recruiting sellers for this need.</div>')+
   '<h3 style="margin:14px 0 6px;font-size:14px">Not alerted ('+p.excluded.length+')</h3>'+p.excluded.map(e=>'<div class="mono">'+esc(e.recipient)+' -- '+esc(e.reason)+'</div>').join("")+'<div id="ferr" class="err"></div>',
   (can("demand:notify")&&p.eligible.length?'<button class="p" onclick="demandNotify('+i+')">Alert '+p.eligible.length+' seller(s)</button>':'')+'<button onclick="closeDrawer()">Close</button>')}
async function demandNotify(i){const x=STATE.dmo[i];if(!confirm("Send an in-app opportunity to the eligible sellers? Customers' identities are never shared."))return;
  try{const r=await call("demand/opportunities/notify","POST",{rule_id:x.rule_id,opportunity_key:x.key,confirm:true});alert("Sent to "+r.sent+" seller(s)"+(r.note?"\n"+r.note:""));closeDrawer();demand()}catch(e){document.querySelector("#ferr").textContent=e.message}}
async function demandRun(){if(!confirm("Evaluate every ACTIVE demand rule now and alert matching sellers?"))return;try{const r=await call("demand/run","POST",{confirm:true});alert(r.rules+" rule(s), "+r.opportunities+" opportunit(ies), "+r.sent+" alert(s) sent");demand()}catch(e){alert(e.message)}}
async function cfgbundle(){const d=await call("config-bundle/resources");const snaps=await call("config-bundle/snapshots");STATE.cfg=null;
  document.querySelector("#page").innerHTML=head("Config import / export","Move Command Center configuration between environments. Preview validates every record and shows what changes; applying stores a snapshot you can roll back. Secrets are never exported.")+
   '<div class="card"><h3>Export</h3>'+d.resources.map(r=>'<label style="display:inline-block;margin:4px 10px 4px 0"><input type="checkbox" class="cb_r" value="'+r.name+'" '+(r.can_export?"checked":"disabled")+'> '+esc(r.label)+'</label>').join("")+
   '<label style="display:block;margin:6px 0"><input type="checkbox" id="cb_f" checked> Feature flag states</label><button class="p" onclick="cfgExport()">Download bundle</button>'+
   '<div class="muted">Never exported: '+esc(d.never_exported.join(", "))+'</div></div>'+
   '<div class="card" style="margin-top:12px"><h3>Import</h3><input type="file" id="cb_file" accept=".json,application/json"><textarea id="cb_txt" rows="5" style="width:100%" placeholder="…or paste a bundle here"></textarea><button onclick="cfgPreview()">Preview</button><div id="cb_out"></div></div>'+
   '<h3 style="margin-top:14px">Applied imports</h3>'+grid(snaps.items,[["created_at","When",when],["actor","Who"],["kind","Kind"],["reason","Reason"],["applied","Changes",a=>esc(JSON.stringify(a.summary||{}))+' · flags '+((a.flags||[]).length)],["rolled_back_at","Rolled back",v=>v?when(v):"—"],["id","",(id,x)=>!x.rolled_back_at&&can("config:manage")?'<button onclick="cfgRollback(\''+id+'\')">Roll back</button>':""]]);
  document.querySelector("#cb_file").addEventListener("change",async e=>{const f=e.target.files[0];if(f)document.querySelector("#cb_txt").value=await f.text()})}
async function cfgExport(){const names=[...document.querySelectorAll(".cb_r:checked")].map(x=>x.value);try{const b=await call("config-bundle/export","POST",{resources:names,include_flags:document.querySelector("#cb_f").checked});
  const a=document.createElement("a");a.href=URL.createObjectURL(new Blob([JSON.stringify(b,null,2)],{type:"application/json"}));a.download="askodox-config-"+b.exported_at.slice(0,10)+".json";a.click()}catch(e){alert(e.message)}}
async function cfgPreview(){const out=document.querySelector("#cb_out");let bundle;try{bundle=JSON.parse(document.querySelector("#cb_txt").value)}catch(e){out.innerHTML='<div class="err">Not valid JSON</div>';return}
  try{const p=await call("config-bundle/preview","POST",{bundle});STATE.cfg=bundle;
   out.innerHTML='<div>'+(p.valid?badge("VALID"):badge("INVALID"))+' create '+p.summary.create+' · update '+p.summary.update+' · unchanged '+p.summary.unchanged+' · invalid '+p.summary.invalid+'</div>'+
    (p.errors.length?'<div class="err">'+p.errors.map(esc).join("<br>")+'</div>':'')+(p.conflicts.length?'<div class="err"><b>Conflicts</b> (changed here after export):<br>'+p.conflicts.map(esc).join("<br>")+'</div>':'')+
    Object.entries(p.resources).map(([n,rows])=>'<div><b>'+esc(n)+'</b> '+rows.filter(r=>r.op!=="unchanged").map(r=>badge(r.op)+' '+esc(r.name||r.id||"")+(r.changed_fields?' <span class="muted">('+esc(r.changed_fields.join(", "))+')</span>':'')+(r.error?' <span class="err">'+esc(r.error)+'</span>':'')).join(" · ")+'</div>').join("")+
    (p.flags.length?'<div><b>Flags</b> '+p.flags.map(f=>esc(f.key)+': '+f.from+' → '+f.to).join(" · ")+'</div>':'')+(p.needs_owner.length?'<div class="muted">Owner only: '+esc(p.needs_owner.join(", "))+'</div>':'')+
    (p.valid&&can("config:manage")?'<input id="cb_reason" placeholder="Reason"><label><input type="checkbox" id="cb_conf"> apply despite conflicts</label><button class="p" onclick="cfgApply()">Apply</button>':'')}catch(e){out.innerHTML='<div class="err">'+esc(e.message)+'</div>'}}
async function cfgApply(){if(!confirm("Apply this configuration? A snapshot is stored so it can be rolled back."))return;try{const r=await call("config-bundle/apply","POST",{bundle:STATE.cfg,confirm:true,allow_conflicts:document.querySelector("#cb_conf").checked,reason:document.querySelector("#cb_reason").value});alert("Applied. Snapshot "+r.snapshot_id);cfgbundle()}catch(e){alert(e.message)}}
async function cfgRollback(id){if(!confirm("Roll back this import? Changed records are restored, records it created are archived."))return;try{const r=await call("config-bundle/rollback/"+id,"POST",{confirm:true});alert("Restored "+r.restored+", archived "+r.archived+", flags "+r.flags);cfgbundle()}catch(e){alert(e.message)}}
async function socialdm(){const d=await call("social-dm");const m=can("autoresponse:manage");
  document.querySelector("#page").innerHTML=head("Social auto-DM","Facebook / Instagram DMs answered by the business's approved auto-response rule. Nothing reaches Meta unless the channel is LIVE (or being tested) and the account has a token; mock mode records replies only.")+
   '<div class="card"><h3>Channels</h3>'+Object.entries(d.channels).map(([c,v])=>'<div style="margin:6px 0"><b>'+esc(c)+'</b> '+badge(v.status)+' <span class="muted">'+esc(v.reason)+'</span></div>').join("")+'<div class="muted">Webhook: '+esc(d.webhook)+' · recent: '+esc(JSON.stringify(d.recent))+'</div></div>'+
   '<div class="tbl"><table><thead><tr><th>Account</th><th>Channel</th><th>Business</th><th>Status</th><th>Page token</th></tr></thead><tbody>'+
   (d.accounts.length?d.accounts.map(a=>'<tr><td><b>'+esc(a.name)+'</b><div class="muted">'+esc(a.account_id)+'</div></td><td>'+esc(a.channel)+'</td><td>'+esc(a.business_ref)+'</td><td>'+badge(a.status)+'</td><td>'+badge(a.token_set?"SET":"NOT SET")+(m?' <button onclick="dmToken(\''+esc(a.channel)+'\',\''+esc(a.account_id)+'\')">Set token</button>':'')+'</td></tr>').join(""):'<tr><td colspan="5" class="empty">No linked accounts. Add one under Social auto-DM accounts.</td></tr>')+'</tbody></table></div>'+
   (m?'<div class="card"><h3>Simulate a DM (mock delivery, never contacts Meta)</h3><select id="dm_ch"><option>facebook</option><option>instagram</option></select> <input id="dm_acc" placeholder="Page / account id"> <input id="dm_text" placeholder="Customer message" style="width:40%"> <button class="p" onclick="dmSim()">Run</button><pre id="dm_out" class="muted" style="white-space:pre-wrap"></pre></div>':'')}
async function dmToken(ch,acc){const t=prompt("Page access token for "+ch+" "+acc+" (stored encrypted, never shown again)");if(!t)return;
  try{await call("social-dm/token","PUT",{channel:ch,account_id:acc,token:t});alert("Token saved");socialdm()}catch(e){alert(e.message)}}
async function dmSim(){try{const r=await call("social-dm/simulate","POST",{channel:document.querySelector("#dm_ch").value,account_id:document.querySelector("#dm_acc").value,text:document.querySelector("#dm_text").value});
  document.querySelector("#dm_out").textContent=JSON.stringify(r.results,null,1)}catch(e){alert(e.message)}}
async function outcomes(){const f=STATE.oc||(STATE.oc={days:"30",category:"",location:"",source:"",role:""});const d=await call("platform/analytics/outcomes?"+new URLSearchParams(f));
  const inp=(k,ph)=>'<input placeholder="'+ph+'" value="'+esc(f[k])+'" onchange="STATE.oc.'+k+'=this.value;outcomes()">';
  const kv=o=>Object.entries(o||{}).map(([k,v])=>'<div><span class="muted">'+esc(k.replace(/_/g," "))+'</span> <b>'+esc(typeof v==="object"&&v!==null?JSON.stringify(v):v??"—")+'</b></div>').join("");
  const top=(t,rows)=>'<div class="card"><h3>'+t+'</h3>'+((rows||[]).length?rows.map(([k,v])=>'<div>'+esc(k)+' <b>'+v+'</b></div>').join(""):'<div class="muted">None recorded</div>')+'</div>';
  document.querySelector("#page").innerHTML=head("Outcomes & gaps",esc(d.basis),'<select onchange="STATE.oc.days=this.value;outcomes()">'+["7","30","90","365"].map(x=>'<option '+(f.days===x?"selected":"")+'>'+x+'</option>').join("")+'</select> days'+inp("category","category")+inp("location","location")+inp("source","source (segment)")+inp("role","role"))+
   '<div class="cards" style="display:grid;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));gap:12px">'+
   '<div class="card"><h3>Demand</h3>'+kv({searches:d.demand.searches,no_result_searches:d.demand.no_result_searches,no_local_supply:d.demand.no_local_supply})+'</div>'+
   '<div class="card"><h3>Funnel</h3>'+d.funnel.map(s=>'<div>'+esc(s.step.replace(/_/g," "))+' <b>'+s.count+'</b></div>').join("")+'</div>'+
   top("Supply gaps (no local seller)",d.supply_gaps)+top("Failed / no-result searches",d.failed_searches)+top("Top categories",d.demand.by_category)+top("Top locations",d.demand.by_location)+
   '<div class="card"><h3>Source performance</h3>'+kv(d.source_performance.results)+'<div class="muted">clicks</div>'+kv(d.source_performance.clicks)+'</div>'+
   '<div class="card"><h3>Organic vs affiliate</h3>'+kv(d.organic_vs_affiliate)+'</div>'+
   '<div class="card"><h3>Seller response</h3>'+kv({accepted:d.seller_response.accepted,declined:d.seller_response.declined,acceptance_rate:d.seller_response.acceptance_rate})+top("Rejection reasons",d.seller_response.rejection_reasons)+'</div>'+
   '<div class="card"><h3>Opportunities</h3>'+kv(d.opportunities.by_status||{})+kv({unfulfilled:d.opportunities.unfulfilled})+'</div>'+
   '<div class="card"><h3>Advisor</h3>'+kv({questions_asked:d.advisor.questions_asked})+kv(d.advisor.by_field)+'</div>'+
   '<div class="card"><h3>Video</h3>'+kv(d.video)+'</div><div class="card"><h3>Offers</h3>'+kv(d.offers)+'</div>'+
   '<div class="card"><h3>Operations</h3>'+kv({escalations:d.escalations,stock_changes:d.stock_changes,commission_changes:d.commission_changes})+kv(d.auto_responses)+'</div>'+
   '<div class="card"><h3>Integration health</h3>'+Object.entries(d.integration_health||{}).map(([k,v])=>badge(k)+' '+v).join("<br>")+'</div></div>'}
async function workqueue(){const d=await call("staff/work-queue");
  document.querySelector("#page").innerHTML=head("My work queue","Only the work your role permits, with what to do, why, and when it is done.")+
   (d.items.length?d.items.map(i=>'<div class="card" style="margin-bottom:10px"><div style="display:flex;justify-content:space-between"><b>'+esc(i.title)+'</b><b>'+i.count+'</b></div><div><b>Do:</b> '+esc(i.what_to_do)+'</div><div class="muted"><b>Why:</b> '+esc(i.why)+' · <b>Done when:</b> '+esc(i.done_when)+'</div>'+(i.count?'<a href="'+esc(i.where)+'">Open</a>':'')+'</div>').join(""):'<div class="empty">Nothing in your queue.</div>')}
async function assistant(){document.querySelector("#page").innerHTML=head("Admin assistant","Answers from recorded ASKODOX data only: what was observed, what might explain it (unverified), and what to do.",
   '<input id="as_q" style="min-width:320px" placeholder="e.g. Which categories have unmet demand?"><button class="p" onclick="assistantAsk()">Ask</button>')+
   '<div class="muted" style="margin-bottom:10px">Try: what increased today? · which sellers are not responding? · which products are out of stock? · which integrations are failing? · what should staff work on today?</div><div id="as_out"></div>';
  document.querySelector("#as_q").addEventListener("keydown",e=>{if(e.key==="Enter")assistantAsk()})}
async function assistantAsk(){const q=document.querySelector("#as_q").value.trim();if(!q)return;const out=document.querySelector("#as_out");out.innerHTML='<div class="muted">Checking the data…</div>';
  try{const r=await call("assistant/ask","POST",{question:q});const sec=(t,rows)=>rows&&rows.length?'<div><b>'+t+'</b><ul>'+rows.map(x=>'<li>'+esc(x)+'</li>').join("")+'</ul></div>':'';
   out.innerHTML=r.answers.map(a=>'<div class="card" style="margin-bottom:10px"><h3>'+esc(a.topic.replace(/_/g," "))+'</h3>'+sec("Observed",a.observed)+sec("Might explain it (unverified)",a.likely)+sec("Recommended",a.actions)+'</div>').join("")+'<div class="muted">'+esc(r.basis)+'</div>'}catch(e){out.innerHTML='<div class="err">'+esc(e.message)+'</div>'}}

window.addEventListener("hashchange",()=>{const h=location.hash.slice(1);if(h&&h!==VIEW&&ME){VIEW=h;renderNav();render()}});
if(CRED)signIn();else document.querySelector("#login").style.display="block";
document.querySelector("#cred").addEventListener("keydown",e=>{if(e.key==="Enter")signIn()});
</script></body></html>'''


@router.get("/admin/console", response_class=HTMLResponse, include_in_schema=False)
def admin_console() -> HTMLResponse:
    return HTMLResponse(PAGE, headers={
        "Cache-Control": "no-store", "X-Frame-Options": "DENY", "Referrer-Policy": "no-referrer",
        "X-Content-Type-Options": "nosniff",
        # Inline code is the page itself (no third-party scripts); data only
        # from this origin; never framed (clickjacking).
        "Content-Security-Policy": "default-src 'self'; script-src 'self' 'unsafe-inline'; "
                                   "style-src 'self' 'unsafe-inline'; img-src 'self' https: data:; "
                                   "connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; "
                                   "form-action 'self'; object-src 'none'",
        "Permissions-Policy": "camera=(), microphone=(), geolocation=()"})
