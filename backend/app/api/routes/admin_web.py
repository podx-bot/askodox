"""Owner-facing ASKODOX Admin Command Center web shell."""
from fastapi import APIRouter
from fastapi.responses import HTMLResponse

router = APIRouter(tags=["admin-web"])

PAGE = r'''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>ASKODOX Command Center</title>
<style>
:root{font-family:Inter,system-ui,sans-serif;color:#172033;background:#f5f7fb}*{box-sizing:border-box}body{margin:0}
header{background:#111827;color:white;padding:18px 22px;display:flex;gap:14px;align-items:center;justify-content:space-between}
.brand{font-weight:800;font-size:20px}.sub{font-size:12px;color:#b8c2d6}.wrap{max-width:1200px;margin:auto;padding:18px}
.login,.card{background:white;border:1px solid #e2e8f0;border-radius:16px;padding:16px;box-shadow:0 3px 12px #0f172a0d}
.login{display:flex;gap:10px;margin-bottom:16px}.login input{flex:1}
input,button,select{border:1px solid #cbd5e1;border-radius:10px;padding:10px 12px}button{background:#111827;color:white;cursor:pointer}
nav{display:flex;gap:8px;overflow:auto;margin:14px 0}nav button{white-space:nowrap;background:white;color:#334155}.active{background:#2563eb!important;color:white!important}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:12px}.metric b{display:block;font-size:26px;margin-top:6px}
.panel{display:none}.panel.show{display:block}table{width:100%;border-collapse:collapse;font-size:13px}th,td{text-align:left;border-bottom:1px solid #edf2f7;padding:9px;vertical-align:top}
.status{padding:4px 8px;border-radius:99px;background:#eef2ff}.error{color:#b91c1c}.ok{color:#15803d}
@media(max-width:650px){.login{flex-direction:column}.wrap{padding:10px}table{display:block;overflow:auto}}
</style></head><body>
<header><div><div class="brand">ASKODOX Command Center</div><div class="sub">Control · Wiring · AI · Analytics · Staff · System Health</div></div><div id="who">Not signed in</div></header>
<div class="wrap">
<div class="login"><input id="key" type="password" placeholder="Owner Admin Key"><button onclick="signIn()">Owner Sign in</button><span id="msg"></span></div>
<nav id="nav"></nav><main id="main"></main>
</div>
<script>
const tabs=[
["Overview","overview"],["Users","users"],["Requests","requests"],["Orders","orders"],["Listings","listings"],
["Categories","categories"],["Support","escalations"],["No Match","no-match"],["Notifications","notifications"],
["Flow traces","traces"],["Demand gaps","demand-gaps"],["API usage","api-usage"],["Returns & disputes","returns"],["Offers","growth/offers"],["Rewards","growth/rewards"],["Referrals","growth/referrals"],["Plans","growth/plans"],["Subscriptions","growth/subscriptions"],["Catalog drafts","growth/catalog-drafts"],["Staff","staff"],["Integrations","integrations"],["System Health","health"],["Analytics","analytics"],["Audit","audit"]
];
let key=sessionStorage.getItem("askodox_admin_key")||""; document.querySelector("#key").value=key;
const esc=x=>String(x??"").replace(/[&<>"]/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"}[c]));
async function api(path){let r=await fetch("/admin/cc/"+path,{headers:{"X-ASKODOX-Admin-Key":key}});if(!r.ok)throw new Error((await r.text())||r.status);return r.json()}
function nav(){document.querySelector("#nav").innerHTML=tabs.map((t,i)=>'<button onclick="loadTab(\''+t[1]+'\',this)" class="'+(i===0?"active":"")+'">'+t[0]+'</button>').join("")}
function table(items,all,open){if(!items?.length)return '<div class="card">No records yet.</div>';let cols=Object.keys(items[0]).slice(0,all?99:10);return '<div class="card" style="overflow:auto"><table><thead><tr>'+cols.map(c=>'<th>'+esc(c)+'</th>').join("")+'</tr></thead><tbody>'+items.map(r=>'<tr'+(open?' style="cursor:pointer" onclick="'+open+'('+Number(r.id)+')"':'')+'>'+cols.map(c=>'<td>'+esc(typeof r[c]==="object"?JSON.stringify(r[c]):r[c])+'</td>').join("")+'</tr>').join("")+'</tbody></table></div>'}
function overview(d){let p=d.participants||{};let vals=[["Buyers",p.buyers||0],["Sellers",p.sellers||0],["Providers",p.service_providers||0],["Active requests",d.requests?.active||0],["Active listings",d.listings?.active||0],["Support open",d.support_open||0],["No match",d.no_match_open||0],["Unread alerts",d.unread_notifications||0]];return '<div class="grid">'+vals.map(x=>'<div class="card metric">'+x[0]+'<b>'+esc(x[1])+'</b></div>').join("")+'</div>'}
async function loadTab(path,btn){document.querySelectorAll("nav button").forEach(b=>b.classList.remove("active"));if(btn)btn.classList.add("active");let m=document.querySelector("#main");m.innerHTML='<div class="card">Loading real data…</div>';try{let d=await api(path);m.innerHTML=path==="overview"?overview(d):path==="traces"?'<div class="card">Click a trace for every step (sources, filtered reasons, fallback, auth gate, seller request, escalation, timeline).</div>'+table(d.items,true,"traceDetail"):table(d.items||Object.entries(d).map(([k,v])=>({section:k,value:typeof v==="object"?JSON.stringify(v):v})))}catch(e){m.innerHTML='<div class="card error">Could not load: '+esc(e.message)+'</div>'}}
async function traceDetail(id){let m=document.querySelector("#main");try{let d=await api("traces/"+id);m.innerHTML='<div class="card"><button onclick="loadTab(\'traces\')">← All traces</button></div>'+table(Object.entries(d).map(([k,v])=>({field:k,value:typeof v==="object"?JSON.stringify(v):v})),true)}catch(e){m.innerHTML='<div class="card error">Could not load: '+esc(e.message)+'</div>'}}
async function signIn(){key=document.querySelector("#key").value.trim();sessionStorage.setItem("askodox_admin_key",key);try{let d=await api("me");document.querySelector("#who").textContent=d.name+" · "+d.role;document.querySelector("#msg").innerHTML='<span class="ok">Connected</span>';loadTab("overview",document.querySelector("nav button"))}catch(e){document.querySelector("#msg").innerHTML='<span class="error">Sign-in failed</span>'}}
nav(); if(key)signIn(); else loadTab("overview",document.querySelector("nav button"));
</script></body></html>'''

@router.get("/admin", response_class=HTMLResponse, include_in_schema=False)
@router.get("/admin/", response_class=HTMLResponse, include_in_schema=False)
def admin_web() -> HTMLResponse:
    return HTMLResponse(PAGE)
