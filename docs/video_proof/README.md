# Real video content proof

Generated 2026-10-08T14:08:14Z by `.github/workflows/video-real-content-proof.yml` (run 37789387554).

* Video rows: **real**, from production's live web video search (Brave) -- replayed into this branch's pipeline, which adds references, YouTube oEmbed checks (live network), linking and disclosures.
* AI answers: **real**, from the production assistant (`/api/in-app/assistant`) given exactly what the app sends (question + grounding from this branch's explain).
* Next-step options: **real**, from production's discovery for the step's text.
* Service cases: production (main) does not search videos for service needs, so their real video rows come from a product-category source query for the same subject; this branch runs them as service needs.
* YouTube Data API: needs_configuration (no YOUTUBE_API_KEY in this run).

| Case | Lang | Videos | Top video | Channel | Plays in app | Disclosure | AI answer | Follow-up | Next step → options |
|---|---|---|---|---|---|---|---|---|---|
| electronics | en | 1 | [Samsung 43" Pure Color Full HD 2026 😱 / UA43F5600FUXXL Unbo…](https://www.youtube.com/watch?v=vJQK7mzFTK8) | TechWay7.0 | yes (official YouTube embed) | Creator's opinion -- not verified by ASKODOX | yes | yes | samsung 43 inch tv near me → 4 (deals, nearby_external) |
| electronics-te | te | 1 | [Samsung 43" Pure Color Full HD 2026 😱 / UA43F5600FUXXL Unbo…](https://www.youtube.com/watch?v=vJQK7mzFTK8) | TechWay7.0 | yes (official YouTube embed) | Creator's opinion -- not verified by ASKODOX | yes | yes | samsung 43 inch tv offers → 6 (deals, nearby_external) |
| phone | en | 1 | [Redmi Note 13 Pro is here - Let's Check!](https://www.youtube.com/watch?v=kGG04jkdjxY) | Gyan Therapy | yes (official YouTube embed) | Creator's opinion -- not verified by ASKODOX | yes | yes | redmi note 13 pro offers → 6 (deals, nearby_external, surplus, used) |
| vehicle | en | 1 | [तहलका SUV 😎 Tata Nexon Facelift / Nexon Next Gen / Garuda ,…](https://www.youtube.com/watch?v=udv2P4GxqjE) | Moto-Wanderer | yes (official YouTube embed) | Creator's opinion -- not verified by ASKODOX | yes | yes | tata nexon near me → 4 (deals, nearby_external, surplus) |
| service | en | 1 | [DAIKIN AC Outdoor Unit Cleaning #acservice #airconcleaning …](https://www.youtube.com/watch?v=7mK4-impjiE) | Lovepreet Singh | no -> opens in youtube | Creator's opinion -- not verified by ASKODOX | yes | yes | ac service near me → 1 (nearby_external) |
| home-service | en | 1 | [Great Plumbing Trick To Fix Pvc Pipe Joint #shortvideo #sho…](https://www.youtube.com/watch?v=Bvxkrv7t4Dw) | vijay xyz tricks | yes (official YouTube embed) | Creator's opinion -- not verified by ASKODOX | yes | yes | plumbing repair service near me → 1 (nearby_external) |
| food | en | 1 | [₹450 vs ₹800 vs ₹1200 Hyderabadi Biryani In Mumbai!! 🤔](https://www.youtube.com/watch?v=NYNr1X8Qokw) | DCT EATS | yes (official YouTube embed) | Creator's opinion -- not verified by ASKODOX | yes | yes | hyderabadi biryani near me → 2 (deals, nearby_external) |
| travel | en | 1 | [Araku Valley Full Tour / Things to do in Araku Valley / Pla…](https://www.youtube.com/watch?v=rMd5DUP04RE) | Travel Matcha | yes (official YouTube embed) | Creator's opinion -- not verified by ASKODOX | yes | yes | araku valley trip reviews → 6 (deals, nearby_external) |
| used-item | en | 1 | [Used Royal Enfield Classic 350🏍️ – Best Deals in Gobichetti…](https://www.youtube.com/watch?v=ilhNFpIoY70) | Engine Thagaval | yes (official YouTube embed) | Creator's opinion -- not verified by ASKODOX | yes | yes | used royal enfield classic 350 near me → 4 (deals, nearby_external, used) |
| deal | en | 1 | [iPhone 15 / Long Term Review / Best iPhone? / Next Sale Kin…](https://www.youtube.com/watch?v=LtaCjbudjpQ) | CallMeShazzam TECH | yes (official YouTube embed) | Creator's opinion -- not verified by ASKODOX | yes | yes | iphone 15 offers → 6 (deals, nearby_external, surplus, used) |
| service-te | te | 1 | [DAIKIN AC Outdoor Unit Cleaning #acservice #airconcleaning …](https://www.youtube.com/watch?v=7mK4-impjiE) | Lovepreet Singh | no -> opens in youtube | Creator's opinion -- not verified by ASKODOX | yes | yes | ac service near me → 1 (nearby_external) |

## Conversations (real AI answers)

### electronics (en) -- "Samsung 43 inch TV review videos"

**Video:** Samsung 43" Pure Color Full HD 2026 😱 | UA43F5600FUXXL Unboxing & True Review | ₹2X,XXX? -- TechWay7.0 (https://www.youtube.com/watch?v=vJQK7mzFTK8)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: Samsung 43" Pure Color Full HD 2026 😱 | UA43F5600FUXXL Unboxing & True Review | ₹2X,XXX? / Samsung UA43F5600 full High definition 2026 Smart tv. / Samsung का New 2026 Pure Color Full HD Smart TV / Information. / ✅ 43" Full HD Display  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "Samsung 43" Pure Color Full HD 2026 😱 | UA43F5600FUXXL Unboxing & True Review | ₹2X,XXX?"

**ASKODOX AI (production):** Based on the information provided for **Samsung 43" Pure Color Full HD Smart TV (UA43F5600FUXXL)** from TechWay7.0: - **Display:** 43-inch Full HD with PurColor technology - **Features:** Smart TV features, picture & sound quality tests, and design details covered in the video - **Price & Availability:** Not provided by the source - **Rating / Reviews:** Not provided by the source *Note: These details are based on the video creator's listing and are not verified by ASKODOX.*

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** Let me check real sellers, shops and online options near you.  
**This branch:** Let me check real sellers, shops and online options near you. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "samsung 43 inch tv near me" → Croma - Benz Circle [nearby_external]; Samsung 43-inch TVs Price List in India (October 2026) [deals]; Shop Samsung 43 Inch TVs Online Best Deals & Prices in India [deals]; Samsung 43 Inch Smart Tv - Buy Samsung 43 Inch Smart Tv online at Best Prices in India | Flipkart.com [deals]

### electronics-te (te) -- "శామ్‌సంగ్ 43 అంగుళాల టీవీ రివ్యూ వీడియో"

**Video:** Samsung 43" Pure Color Full HD 2026 😱 | UA43F5600FUXXL Unboxing & True Review | ₹2X,XXX? -- TechWay7.0 (https://www.youtube.com/watch?v=vJQK7mzFTK8)

**ASKODOX explain (branch):** ఈ వీడియోను నేను చూడలేదు/విశ్లేషించలేదు. శీర్షిక, క్రియేటర్ ఇచ్చిన వివరణ, ఛానల్ మాత్రమే తెలుసు.  
Quoted from source: Samsung 43" Pure Color Full HD 2026 😱 | UA43F5600FUXXL Unboxing & True Review | ₹2X,XXX? / Samsung UA43F5600 full High definition 2026 Smart tv. / Samsung का New 2026 Pure Color Full HD Smart TV / Information. / ✅ 43" Full HD Display  
Label: Creator's opinion -- not verified by ASKODOX

**User:** "Samsung 43" Pure Color Full HD 2026 😱 | UA43F5600FUXXL Unboxing & True Review | ₹2X,XXX?" గురించి చెప్పండి: ధర, దూరం, నాణ్యత, అందుబాటు, రివ్యూలు

**ASKODOX AI (production):** ఈ వీడియో వివరాల ప్రకారం: - **టీవీ సమాచారం:** Samsung 43 అంగుళాల Full HD Smart TV (మోడల్: UA43F5600FUXXL). ఇందులో Pure Color టెక్నాలజీ, పిక్చర్/సౌండ్ క్వాలిటీ టెస్ట్, స్మార్ట్ టీవీ ఫీచర్లు ఉన్నాయని TechWay7.0 ఛానెల్ తెలిపింది. ఇది వారి వ్యక్తిగత అభిప్రాయం మాత్రమే (ASKODOX ద్వారా నిర్ధారించబడలేదు). - **ధర:** ఖచ్చితమైన ధర వివరించబడలేదు (మూలంలో ఇవ్వలేదు). - **దూరం:** అందుబాటులో ఉన్న స్థానిక షాపుల వివరాలు లేదా దూరం ఇవ్వలేదు. - **నాణ్యత:** సృష్టికర్త అభిప్రాయం ప్రకారం మంచి డిజైన్, డిస్ప్లే మరియు సౌండ్ క్వాలిటీ ఉన్నట్లు పేర్కొన్నారు. - **అందుబాటు & రివ్యూలు:** స్టాక్ వివరాలు మరియు యూజర్ రివ్యూలు మూలంలో ఇవ్వలేదు (Not verified). ధర మరియు స్థానిక లభ్యత తెలుసుకోవడానికి షాపులను సంప్రదించమంటారా?

**User (follow-up, same conversation):** ఇది చిన్న గదికి సరిపోతుందా?

**ASKODOX AI:** సాధారణంగా **43 అంగుళాల టీవీ** చూసేందుకు **5 నుండి 7 అడుగుల దూరం** అవసరం. చిన్న గదికి సంబంధించిన ముఖ్య విషయాలు: - మీ గదిలో సోఫా లేదా మంచం నుండి టీవీ మధ్య కనీసం 5-6 అడుగుల దూరం ఉంటే 43 అంగుళాల టీవీ చాలా బాగా సరిపోతుంది. - ఒకవేళ వీక్షణ దూరం **4 అడుగుల కంటే తక్కువ** ఉంటే, కళ్లకు శ్రమగా అనిపించవచ్చు. అలాంటి పరిస్థితిలో 32 అంగుళాల టీవీ మేలు. మీ గదిలో టీవీ చూసే దూరం (Viewing distance) సుమారు ఎంత ఉంటుంది?

**Next step:** "samsung 43 inch tv offers" → Croma - Benz Circle [nearby_external]; Samsung 43-inch TVs Price List in India (October 2026) [deals]; Shop Samsung 43 Inch TVs Online Best Deals & Prices in India [deals]; Samsung 43 Inch Smart Tv - Buy Samsung 43 Inch Smart Tv online at Best Prices in India | Flipkart.com [deals]

### phone (en) -- "Redmi Note 13 Pro review video"

**Video:** Redmi Note 13 Pro is here - Let's Check! -- Gyan Therapy (https://www.youtube.com/watch?v=kGG04jkdjxY)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: Redmi Note 13 Pro is here - Let's Check! / Redmi Note 13, Redmi Note 13 Pro and Redmi Note 13 Pro+ launched in India. / Redmi Note 13 Pro comes with Snapdragon 7s Gen 2 Processor, 200MP triple camera with 5100mAh Battery with 67W Charging from Xiaomi. / Here is my Redmi Note 13 Pro Unboxing and Ini…  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "Redmi Note 13 Pro is here - Let's Check!"

**ASKODOX AI (production):** This video by creator Gyan Therapy is an unboxing and initial impression of the Redmi Note 13 Pro. Based on the video description, it highlights features like the Snapdragon 7s Gen 2 processor, a 200MP triple camera setup, and a 5100mAh battery with 67W fast charging. Please note that creator opinions are not verified by ASKODOX. Details like price, user ratings, and local availability were **not provided** in the source listing.

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** Let me check real sellers, shops and online options near you.  
**This branch:** Let me check real sellers, shops and online options near you. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "redmi note 13 pro offers" → Happi Mobiles Vijayawada Bandar Road [nearby_external]; Buy Old Used Xiaomi Redmi Note 13 Pro 4G Phones Under ... [used]; Open Box Store [surplus]; Redmi Note 13 5G, Note 13 Pro 5G, Note 13 Pro+ 5G goes on sale on Vijay Sales - Times of India [deals]

### vehicle (en) -- "Tata Nexon review video"

**Video:** तहलका SUV 😎 Tata Nexon Facelift / Nexon Next Gen / Garuda , पर 1 लाख Discount 🤔 खत्म Maruti Brezza -- Moto-Wanderer (https://www.youtube.com/watch?v=udv2P4GxqjE)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: तहलका SUV 😎 Tata Nexon Facelift / Nexon Next Gen / Garuda , पर 1 लाख Discount 🤔 खत्म Maruti Brezza / तहलका SUV 😎 Tata Nexon Facelift / Nexon Next Gen / Garuda , पर 1 लाख Discount 🤔 खत्म Maruti Brezza / Tata Nexon Smart Pure Creative Accomplish Base to Top Model / Your Queries: / Tata Nexon Facelift  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "तहलका SUV 😎 Tata Nexon Facelift / Nexon Next Gen / Garuda , पर 1 लाख Discount 🤔 खत्म Maruti Brezza"

**ASKODOX AI (production):** Based on the video title from creator **Moto-Wanderer** (creator's opinion, not verified by ASKODOX): - **Video Title:** तहलका SUV 😎 Tata Nexon Facelift / Nexon Next Gen / Garuda , पर 1 लाख Discount 🤔 खत्म Maruti Brezza - **Topics Covered:** Tata Nexon Facelift, Next Gen/Garud, variant walkaround (Smart, Pure, Creative, Accomplish base-to-top models), and claimed discount discussions. - **Price / Discount Details:** Not provided by the source. - **Stock / Availability:** Not provided by the source. - **Rating / Reviews:** Not provided by the source. *Note:* The video content itself was not analyzed, only its title and description details are available. Specific discount terms, pricing, and availability are not verified facts and depend on dealership offers in Vijayawada.

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** Let me check real sellers, shops and online options near you.  
**This branch:** Let me check real sellers, shops and online options near you. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "tata nexon near me" → Tata Motors Commercial Vehicle Dealer - Sahni Auto Private Limited [nearby_external]; Tata Nexon On Road Price in Vijayawada (2026) – ₹8.63 lakh Onwards | Autocar India [surplus]; Tata Nexon price in Vijayawada | Tata Nexon on road Price 2026 | Times Drive [deals]; Tata Nexon Price in Vijayawada-August 2026 Nexon On Road Price [deals]

### service (en) -- "AC service video"

**Video:** DAIKIN AC Outdoor Unit Cleaning #acservice #airconcleaning #accleaning #HVAC #shortsvideo -- Lovepreet Singh (https://www.youtube.com/watch?v=7mK4-impjiE)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: DAIKIN AC Outdoor Unit Cleaning #acservice #airconcleaning #accleaning #HVAC #shortsvideo / How to Service the DAIKIN AC Outdoor Unit of Split AC / How to Service the Outdoor Unit of a Split AC / AC outdoor unit cleaning / ac cleaning at home  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "DAIKIN AC Outdoor Unit Cleaning #acservice #airconcleaning #accleaning #HVAC #shortsvideo"

**ASKODOX AI (production):** Based on the details provided for the video **"DAIKIN AC Outdoor Unit Cleaning"** by creator **Lovepreet Singh**: - **Topics Covered:** Outdoor unit water cleaning, servicing Daikin split AC outdoor units at home, and general HVAC maintenance tips. - **Specific Video Details:** Price, stock, distance, and user ratings/reviews are **not provided** by the source. - **Note:** The video content reflects the creator's opinion and is **not verified by ASKODOX**. Cleaning an outdoor unit typically involves clearing dust and debris from the condenser coils and washing the outer fins with light water pressure. If you need a professional technician in Vijayawada to service your AC safely, let me know!

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** Let me check real sellers, shops and online options near you.  
**This branch:** Let me check real sellers, shops and online options near you. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "ac service near me" → SML AC SERVICES / ELECTRICAL WORKS [nearby_external]

### home-service (en) -- "kitchen sink plumbing repair video"

**Video:** Great Plumbing Trick To Fix Pvc Pipe Joint #shortvideo #shorts #shortsfeed -- vijay xyz tricks  (https://www.youtube.com/watch?v=Bvxkrv7t4Dw)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: Great Plumbing Trick To Fix Pvc Pipe Joint #shortvideo #shorts #shortsfeed / Great Plumbing Trick To Fix Pvc Pipe Joint #shortvideo #shorts #shortsfeed / thanks for watching video  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "Great Plumbing Trick To Fix Pvc Pipe Joint #shortvideo #shorts #shortsfeed"

**ASKODOX AI (production):** This short video is titled **"Great Plumbing Trick To Fix Pvc Pipe Joint"** by creator **vijay xyz tricks**. Here are the details available from the source: - **Content:** The creator shares a quick trick for fixing PVC pipe joints (Creator's opinion — not verified by ASKODOX). - **Price / Cost:** Not provided - **Ratings / Reviews:** Not provided - **Distance / Location:** Not provided Since the video content itself hasn't been full-length analyzed, I can't confirm the exact method shown. If you are dealing with a leaking PVC joint right now, common fixes involve applying PVC solvent cement or using epoxy putty/leak-repair tape for a temporary fix.

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** Let me check real sellers, shops and online options near you.  
**This branch:** Let me check real sellers, shops and online options near you. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "plumbing repair service near me" → Amulya Plumbing & Sanitary Services [nearby_external]

### food (en) -- "Hyderabadi biryani review video"

**Video:** ₹450 vs ₹800 vs ₹1200 Hyderabadi Biryani In Mumbai!! 🤔 -- DCT EATS (https://www.youtube.com/watch?v=NYNr1X8Qokw)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: ₹450 vs ₹800 vs ₹1200 Hyderabadi Biryani In Mumbai!! 🤔 / Can we find authentic Hyderabadi mutton biryani in Mumbai? / Sahil from Headbanger Eats and I ordered three versions from different restaurants to compare what we get at three very different price points. / First up was Bikkgane Biryani, foll…  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "₹450 vs ₹800 vs ₹1200 Hyderabadi Biryani In Mumbai!! 🤔"

**ASKODOX AI (production):** Based on the details provided for **"₹450 vs ₹800 vs ₹1200 Hyderabadi Biryani In Mumbai!! 🤔"** by creator **DCT EATS** (creator's opinion, not verified by ASKODOX): - **Content:** The creator and Sahil from Headbanger Eats compare three different price points of Hyderabadi mutton biryani in Mumbai. - **Featured Places:** Bikkgane Biryani (₹450 tier), Biryani By Kilo (₹800 tier), and Lit (₹1200 tier). - **Price / Ratings / Reviews:** Not provided by the source. - **Stock / Availability / Distance:** Not provided by the source.

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** Let me check real sellers, shops and online options near you.  
**This branch:** Let me check real sellers, shops and online options near you. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "hyderabadi biryani near me" → The Kazus Royal Dum Biryani [nearby_external]; Best Hyderabadi Biryani Restaurants In Vijayawada 2025 | Order Online [deals]

### travel (en) -- "Araku valley trip review video"

**Video:** Araku Valley Full Tour | Things to do in Araku Valley | Places to Visit in Araku -- Travel Matcha (https://www.youtube.com/watch?v=rMd5DUP04RE)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: Araku Valley Full Tour | Things to do in Araku Valley | Places to Visit in Araku / in This video we are giving out a full itinerary for Araku Valley, / Araku Valley is Andhra Pradesh’s Hidden Gem! / Imagine waking up to mist-covered hills, walking through lush coffee plantations, exploring ancient …  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "Araku Valley Full Tour | Things to do in Araku Valley | Places to Visit in Araku"

**ASKODOX AI (production):** Based on the video listing **"Araku Valley Full Tour | Things to do in Araku Valley | Places to Visit in Araku"** by **Travel Matcha**: - **Overview**: The video provides a full travel itinerary for Araku Valley, highlighting coffee plantations, ancient caves, mist-covered hills, and local food. - **Creator Note**: These highlights reflect the creator's opinion (*Travel Matcha*) and are **Not verified** by ASKODOX. - **Details**: Price, rating, reviews, and distance are **not provided** by the source. Would you like help planning a travel itinerary or finding transport/cab options from Vijayawada to Araku Valley?

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** Let me check real sellers, shops and online options near you.  
**This branch:** Let me check real sellers, shops and online options near you. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "araku valley trip reviews" → Akkanna Madanna Caves [nearby_external]; Araku Valley Tour Packages From Vijayawada – Vijayawada To Araku Valley Packages | TT [deals]; 5 Araku Valley Tour Packages at ₹6785 pp - Book Online with 20% Off [deals]; Araku Valley Tour Packages from Vijayawada | Araku Valley Packages from Vijayawada | Araku Valley Honeymoon Packages from Vijayawada | Araku Valley Holiday Pack [deals]

### used-item (en) -- "used Royal Enfield Classic 350 review video"

**Video:** Used Royal Enfield Classic 350🏍️ – Best Deals in Gobichettipalayam | Engine Thagaval #royalenfield -- Engine Thagaval  (https://www.youtube.com/watch?v=ilhNFpIoY70)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: Used Royal Enfield Classic 350🏍️ – Best Deals in Gobichettipalayam | Engine Thagaval #royalenfield / Royal Enfield Classic 350 – FOR SALE! / Single-owner / well-maintained condition. / Classic Royal Enfield design with smooth BS6 engine—perfect for city rides and highway cruising. / 📍 Location: /12…  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "Used Royal Enfield Classic 350🏍️ – Best Deals in Gobichettipalayam | Engine Thagaval #royalenfield"

**ASKODOX AI (production):** Got it — continuing with your saved location.

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** Let me check real sellers, shops and online options near you.  
**This branch:** Let me check real sellers, shops and online options near you. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "used royal enfield classic 350 near me" → TARAK BULLET HOUSE [nearby_external]; 13 Used Royal Enfield Classic in Vijayawada. Buy from Owners and Dealers - Bikes4Sale [used]; Royal Enfield Classic 350 Price in Vijayawada-March 2026 Classic 350 On Road Price [deals]; Royal Enfield Classic 350 price in Vijayawada | Royal Enfield Classic 350 on road Price 2026 | Times Drive [deals]

### deal (en) -- "iPhone 15 offer review video"

**Video:** iPhone 15 | Long Term Review | Best iPhone? | Next Sale King? | Malayalam with Eng Sub -- CallMeShazzam TECH (https://www.youtube.com/watch?v=LtaCjbudjpQ)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: iPhone 15 | Long Term Review | Best iPhone? | Next Sale King? | Malayalam with Eng Sub / Thumbnail by / https://www.instagram.com/laetitia.creatives/ / ndependently owned creative agency / Crafting transformative brands  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "iPhone 15 | Long Term Review | Best iPhone? | Next Sale King? | Malayalam with Eng Sub"

**ASKODOX AI (production):** This video **"iPhone 15 | Long Term Review | Best iPhone? | Next Sale King? | Malayalam with Eng Sub"** is a creator opinion review by **CallMeShazzam TECH** (not verified by ASKODOX). It covers long-term usage insights, performance, and whether it's worth buying during upcoming sales, featuring Malayalam audio with English subtitles. Key listing details from the source: - **Price:** Not provided - **Ratings / Reviews:** Not provided - **Stock / Availability:** Not provided Since specific facts like verified specs or local pricing are not provided by the source, let me know if you would like to look up current iPhone 15 deals or local availability in Vijayawada!

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** Let me check real sellers, shops and online options near you.  
**This branch:** Let me check real sellers, shops and online options near you. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "iphone 15 offers" → Happi Mobiles Vijayawada Bandar Road [nearby_external]; Buy Second Hand Apple iPhone 15 Phone Under ₹23000 in Vijayawada | Best Prices – ORUphones [used]; Apple Open Box [surplus]; iPhone 15 is available for less than Rs 35,000 on Vijay Sales, here is how the deal works - India Today [deals]

### service-te (te) -- "ఏసీ సర్వీస్ వీడియో"

**Video:** DAIKIN AC Outdoor Unit Cleaning #acservice #airconcleaning #accleaning #HVAC #shortsvideo -- Lovepreet Singh (https://www.youtube.com/watch?v=7mK4-impjiE)

**ASKODOX explain (branch):** ఈ వీడియోను నేను చూడలేదు/విశ్లేషించలేదు. శీర్షిక, క్రియేటర్ ఇచ్చిన వివరణ, ఛానల్ మాత్రమే తెలుసు.  
Quoted from source: DAIKIN AC Outdoor Unit Cleaning #acservice #airconcleaning #accleaning #HVAC #shortsvideo / How to Service the DAIKIN AC Outdoor Unit of Split AC / How to Service the Outdoor Unit of a Split AC / AC outdoor unit cleaning / ac cleaning at home  
Label: Creator's opinion -- not verified by ASKODOX

**User:** "DAIKIN AC Outdoor Unit Cleaning #acservice #airconcleaning #accleaning #HVAC #shortsvideo" గురించి చెప్పండి: ధర, దూరం, నాణ్యత, అందుబాటు, రివ్యూలు

**ASKODOX AI (production):** ఈ వీడియో 'Lovepreet Singh' అనే క్రియేటర్ రూపొందించినది. డెమో మరియు సమాచారం కోసం ఇది ఉపయోగపడుతుంది: - **ధర:** Not verified (మూలంలో పేర్కొనబడలేదు) - **దూరం:** Not verified (మూలంలో పేర్కొనబడలేదు) - **నాణ్యత / రివ్యూలు:** Not verified (మూలంలో పేర్కొనబడలేదు; ఇది క్రియేటర్ అభిప్రాయం మాత్రమే) - **అందుబాటు:** Not verified (మూలంలో పేర్కొనబడలేదు) వీడియోలో అందించిన వివరాలు ఆధారంగా మాత్రమే ఇవి చెప్పబడ్డాయి.

**User (follow-up, same conversation):** ఇది చిన్న గదికి సరిపోతుందా?

**ASKODOX AI:** సాధారణంగా చిన్న గది (సుమారు 100-120 చదరపు అడుగులు)కి **1 టన్ AC** సరిగ్గా సరిపోతుంది. బయట యూనిట్ (Outdoor Unit) శుభ్రం చేయడం వల్ల AC కూలింగ్ మరియు పనితీరు పెరుగుతుంది. మీరు ఏ సైజ్/కెపాసిటీ AC ని వాడుతున్నారు?

**Next step:** "ac service near me" → SML AC SERVICES / ELECTRICAL WORKS [nearby_external]

## Attribution (branch Command Center)

Video funnel: video_impression 11, video_open 11, video_watch_start 9, video_watch_complete 0, video_ask 11, video_product_click 4, video_service_click 3, video_local_search 4, video_affiliate_click 0, video_contact 2, lead 0, order 0, conversion 0

Commerce funnel: search 11, impression 0, result_view 0, click 11, claim 0, lead 0, order 0, payment 0, redemption 0, conversion 0, commission 0

## App renders (real rows, thumbnails and AI answers)

![electronics-te_1_search_videos.png](renders/electronics-te_1_search_videos.png)
![electronics-te_2_watch.png](renders/electronics-te_2_watch.png)
![electronics-te_3_ask_ai_answer.png](renders/electronics-te_3_ask_ai_answer.png)
![electronics-te_4_next_step_options.png](renders/electronics-te_4_next_step_options.png)
![electronics_1_search_videos.png](renders/electronics_1_search_videos.png)
![electronics_2_watch.png](renders/electronics_2_watch.png)
![electronics_3_ask_ai_answer.png](renders/electronics_3_ask_ai_answer.png)
![electronics_4_next_step_options.png](renders/electronics_4_next_step_options.png)
![service_1_search_videos.png](renders/service_1_search_videos.png)
![service_2_watch.png](renders/service_2_watch.png)
![service_3_ask_ai_answer.png](renders/service_3_ask_ai_answer.png)
![service_4_next_step_options.png](renders/service_4_next_step_options.png)
