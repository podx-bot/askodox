import json,time,urllib.request
U="https://podx-ai-connect-production-3279.up.railway.app/api/in-app/assistant/stream"
caps=["suggestions","answer_card","app_actions","auto_open"]
qs=[("te","నేటి బంగారం ధర ఎంత"),("te","విజయవాడలో biryani"),("hi","आज सोने का भाव क्या है"),("te","హలో"),("te","SIP మంచిదా FD మంచిదా")]
for loc,q in qs:
    body=json.dumps({"message":q,"locale":loc,"history":[],"capabilities":caps}).encode()
    r=urllib.request.Request(U,data=body,headers={"Content-Type":"application/json"})
    t0=time.time();first=None;hold=None;tot=0
    with urllib.request.urlopen(r,timeout=90) as f:
        for line in f:
            d=json.loads(line)
            if d["type"]=="hold": hold=(round(time.time()-t0,2),d["text"])
            elif d["type"]=="delta" and first is None: first=round(time.time()-t0,2)
            elif d["type"]=="final": tot=round(time.time()-t0,2)
    print(f"{q[:24]:26} hold={hold} first_text={first} total={tot}")
    time.sleep(3)
