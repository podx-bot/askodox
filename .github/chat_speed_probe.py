import json,time,sys,urllib.request
U="https://podx-ai-connect-production-3279.up.railway.app/api/in-app/assistant/stream"
caps=["suggestions","answer_card","app_actions","auto_open"]
qs=[("te","దగ్గర్లో biryani కావాలి"),("en","biryani nearby"),("en","biryani in Hyderabad"),("te","విజయవాడలో biryani")]
qsy=[("te","హలో"),("te","హలో"),("te","5 లక్షల home loan కి EMI ఎంత అవుతుంది 20 years"),("te","mutual fund లో SIP మంచిదా FD మంచిదా"),("te","విజయవాడలో మంచి biryani ఎక్కడ"),("te","నేటి బంగారం ధర ఎంత")]
for loc,q in qs:
    body=json.dumps({"message":q,"locale":loc,"history":[],"capabilities":caps}).encode()
    r=urllib.request.Request(U,data=body,headers={"Content-Type":"application/json"})
    t0=time.time();first=None;txt=""
    with urllib.request.urlopen(r,timeout=90) as f:
        for line in f:
            d=json.loads(line)
            if d["type"]=="delta":
                if first is None: first=time.time()-t0
                txt+=d["text"]
            elif d["type"]=="final":
                dec=d["decision"];tot=time.time()-t0
    print(f"{q[:30]:32} first={first and round(first,2)} total={round(tot,2)} card={bool(dec.get('card'))} reply={dec['reply'][:160]!r} ent={dec.get('entities')} mode={dec.get('mode')} tr={dec.get('transactional')} ready={dec.get('search_ready')}")
    time.sleep(3)
