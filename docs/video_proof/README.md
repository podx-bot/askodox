# Real video content proof

Generated 2026-10-08T17:54:32Z by `.github/workflows/video-real-content-proof.yml` (run 37819657434).

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
| travel | en | 1 | [Araku Valley Full Tour / Things to do in Araku Valley / Pla…](https://www.youtube.com/watch?v=rMd5DUP04RE) | Travel Matcha | yes (official YouTube embed) | Creator's opinion -- not verified by ASKODOX | yes | no (fallback) | araku valley trip reviews → 6 (deals, nearby_external) |
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

**ASKODOX AI (production):** Based on the details provided from TechWay7.0's video on the **Samsung 43" Pure Color Full HD Smart TV (UA43F5600FUXXL, 2026 model)**: - **Features Listed:** 43-inch Full HD display, PurColor technology, Smart TV capabilities, and build/design overview. - **Testing Covered in Video:** Picture quality, sound quality, and smart features. - **Pricing & Stock:** Exact price, availability, and user ratings are **not provided** in the source listing (listed as ₹2X,XXX in the title). *Note: These details reflect the creator's video description and are not independently verified by ASKODOX.*

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

**ASKODOX AI (production):** మీరు ఎంచుకున్న ప్లాట్‌ఫారమ్‌లోని వీడియో సమాచారం ప్రకారం: - **బ్రాండ్ & మోడల్:** Samsung 43" Pure Color Full HD Smart TV (UA43F5600FUXXL, 2026 మోడల్). - **ఫీచర్లు:** Full HD డిస్‌ప్లే, Pure Color టెక్నాలజీ, స్మార్ట్ టీవీ ఫీచర్లు, సౌండ్ మరియు పిక్చర్ క్వాలిటీ టెస్ట్ ఉన్నాయని క్రియేటర్ (TechWay7.0) పేర్కొన్నారు (ఇది క్రియేటర్ అభిప్రాయం మాత్రమే, ASKODOX ద్వారా ధృవీకరించబడలేదు). - **ధర (Price):** Not verified (ఆధారంలో స్పష్టమైన ధర ఇవ్వలేదు, ₹2X,XXX అని ఉంది). - **దూరం (Distance):** Not verified. - **అందుబాటు (Stock/Availability):** Not verified. - **రివ్యూలు & నాణ్యత:** Not verified. ధర, అందుబాటు మరియు షాపు వివరాల కోసం మీరు నగరంలోని స్థానిక డీలర్లను సంప్రదించమంటారా?

**User (follow-up, same conversation):** ఇది చిన్న గదికి సరిపోతుందా?

**ASKODOX AI:** సాధారణంగా **43 అంగుళాల టీవీ** సరిగ్గా చూడటానికి **6 నుండి 8 అడుగుల దూరం** ఉండాలి. మీ గది చిన్నదైతే ఈ విషయాలు చూడండి: - **వ్యూయింగ్ డిస్టెన్స్:** మీ కూర్చునే స్థలం నుండి టీవీ స్క్రీన్ మధ్య కనీసం 6 అడుగుల దూరం ఉంటే కళ్లకు శ్రమ లేకుండా Full HD నాణ్యత బాగా కనిపిస్తుంది. - **గది పరిమాణం:** గది పరిమాణం 10x10 అడుగులు లేదా అంతకంటే ఎక్కువ ఉంటే 43 ఇంచుల టీవీ చాలా బాగా సరిపోతుంది. అంతకంటే చాలా చిన్న గది అయితే (ఉదాహరణకు 6x8 అడుగులు) 32 ఇంచుల టీవీ మరింత అనుకూలంగా ఉంటుంది. మీ గదిలో టీవీ చూసే దూరం సుమారు ఎన్ని అడుగులు ఉంటుంది?

**Next step:** "samsung 43 inch tv offers" → Croma - Benz Circle [nearby_external]; Samsung 43-inch TVs Price List in India (October 2026) [deals]; Shop Samsung 43 Inch TVs Online Best Deals & Prices in India [deals]; Samsung 43 Inch Smart Tv - Buy Samsung 43 Inch Smart Tv online at Best Prices in India | Flipkart.com [deals]

### phone (en) -- "Redmi Note 13 Pro review video"

**Video:** Redmi Note 13 Pro is here - Let's Check! -- Gyan Therapy (https://www.youtube.com/watch?v=kGG04jkdjxY)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: Redmi Note 13 Pro is here - Let's Check! / Redmi Note 13, Redmi Note 13 Pro and Redmi Note 13 Pro+ launched in India. / Redmi Note 13 Pro comes with Snapdragon 7s Gen 2 Processor, 200MP triple camera with 5100mAh Battery with 67W Charging from Xiaomi. / Here is my Redmi Note 13 Pro Unboxing and Ini…  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "Redmi Note 13 Pro is here - Let's Check!"

**ASKODOX AI (production):** This video by creator **Gyan Therapy** is an unboxing and initial impressions look at the **Redmi Note 13 Pro**. Key details listed for this option: - **Creator:** Gyan Therapy (Creator's opinion — not verified by ASKODOX) - **Key Specs Mentioned:** Snapdragon 7s Gen 2 processor, 200MP triple camera setup, 5100mAh battery with 67W charging. - **Focus:** Initial unboxing and first impressions of the Redmi Note 13 series launch in India. - **Price:** Not provided - **Ratings / Reviews:** Not provided - **Stock / Availability:** Not provided Note: The full video content has not been analyzed, and details like price or long-term performance reviews are not provided by the source.

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

**ASKODOX AI (production):** Based on the details provided by the creator **Moto-Wanderer**, this video covers the **Tata Nexon Facelift / Next Gen** across various variants (Smart, Pure, Creative, Accomplish) and discusses potential discount offers up to ₹1 lakh alongside comparisons to the Maruti Brezza. Please note: The content represents the creator's opinion and is **not verified** by ASKODOX. Specific verified details like current local pricing, ratings, or stock availability are **not provided** by the source.

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

**ASKODOX AI (production):** Based on the details provided for the video **"DAIKIN AC Outdoor Unit Cleaning"** by creator Lovepreet Singh: - **Topics Covered**: The video demonstrates how to service and water-clean a Daikin split AC outdoor unit at home. - **Price / Stock / Rating**: Not provided by the source. - **Verification**: The techniques shown reflect the creator's opinion and are **Not verified** by ASKODOX. *Note*: DIY pressure washing or cleaning of outdoor AC coils can damage delicate cooling fins or cause electrical short circuits if water gets into the junction box. If you'd like, I can help you find professional local AC service technicians in Vijayawada.

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

**ASKODOX AI (production):** Based on the video listing provided: - **Title**: Great Plumbing Trick To Fix Pvc Pipe Joint #shortvideo #shorts #shortsfeed - **Creator**: vijay xyz tricks (Creator's opinion — not verified by ASKODOX) - **Description**: thanks for watching video - **Price**: Not provided - **Rating / Reviews**: Not provided - **Distance / Availability**: Not provided *Note*: The full contents of the video have not been analyzed beyond these listed facts. If you need step-by-step guidance on how to seal or fix a leaking PVC pipe joint using standard plumbing methods (like PVC solvent cement or silicone tape), let me know!

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** Let me check real sellers, shops and online options near you.  
**This branch:** Let me check real sellers, shops and online options near you. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "plumbing repair service near me" → SS Rapid Electrical and plumbing works [nearby_external]

### food (en) -- "Hyderabadi biryani review video"

**Video:** ₹450 vs ₹800 vs ₹1200 Hyderabadi Biryani In Mumbai!! 🤔 -- DCT EATS (https://www.youtube.com/watch?v=NYNr1X8Qokw)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: ₹450 vs ₹800 vs ₹1200 Hyderabadi Biryani In Mumbai!! 🤔 / Can we find authentic Hyderabadi mutton biryani in Mumbai? / Sahil from Headbanger Eats and I ordered three versions from different restaurants to compare what we get at three very different price points. / First up was Bikkgane Biryani, foll…  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "₹450 vs ₹800 vs ₹1200 Hyderabadi Biryani In Mumbai!! 🤔"

**ASKODOX AI (production):** This video by creator **DCT EATS** (with Sahil from Headbanger Eats) compares authentic Hyderabadi mutton biryani in Mumbai across three price tiers: - **Options featured:** Bikkgane Biryani (₹450 tier), Biryani By Kilo (₹800 tier), and Lit (₹1200 tier). - **Topic:** Comparing portion, taste, and overall value at three very different price points. *Note:* Specific facts such as exact ratings, stock availability, and verified prices are **not provided** by the source. Creator opinions are not verified by ASKODOX.

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** Let me check real sellers, shops and online options near you.  
**This branch:** Let me check real sellers, shops and online options near you. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "hyderabadi biryani near me" → New Hyderabadi Bucket Briyani [nearby_external]; Best Hyderabadi Biryani Restaurants In Vijayawada 2025 | Order Online [deals]

### travel (en) -- "Araku valley trip review video"

**Video:** Araku Valley Full Tour | Things to do in Araku Valley | Places to Visit in Araku -- Travel Matcha (https://www.youtube.com/watch?v=rMd5DUP04RE)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: Araku Valley Full Tour | Things to do in Araku Valley | Places to Visit in Araku / in This video we are giving out a full itinerary for Araku Valley, / Araku Valley is Andhra Pradesh’s Hidden Gem! / Imagine waking up to mist-covered hills, walking through lush coffee plantations, exploring ancient …  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "Araku Valley Full Tour | Things to do in Araku Valley | Places to Visit in Araku"

**ASKODOX AI (production):** Based on the details provided for **"Araku Valley Full Tour | Things to do in Araku Valley | Places to Visit in Araku"** by creator Travel Matcha: - **Itinerary & Highlights:** The video covers a full itinerary including mist-covered hills, coffee plantations, ancient caves (like Borra Caves), and local food. This is the creator's opinion and not verified by ASKODOX. - **Creator:** Travel Matcha - **Price / Distance / Rating / Stock:** Not provided by the source. Let me know if you would like help planning a trip itinerary or finding transport from Vijayawada to Araku Valley!

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:**   
**This branch:** Let me check real sellers, shops and online options near you. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "araku valley trip reviews" → Akkanna Madanna Caves [nearby_external]; Araku Valley Tour Packages From Vijayawada – Vijayawada To Araku Valley Packages | TT [deals]; 5 Araku Valley Tour Packages at ₹6785 pp - Book Online with 20% Off [deals]; Araku Valley Tour Packages from Vijayawada | Araku Valley Packages from Vijayawada | Araku Valley Honeymoon Packages from Vijayawada | Araku Valley Holiday Pack [deals]

### used-item (en) -- "used Royal Enfield Classic 350 review video"

**Video:** Used Royal Enfield Classic 350🏍️ – Best Deals in Gobichettipalayam | Engine Thagaval #royalenfield -- Engine Thagaval  (https://www.youtube.com/watch?v=ilhNFpIoY70)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: Used Royal Enfield Classic 350🏍️ – Best Deals in Gobichettipalayam | Engine Thagaval #royalenfield / Royal Enfield Classic 350 – FOR SALE! / Single-owner / well-maintained condition. / Classic Royal Enfield design with smooth BS6 engine—perfect for city rides and highway cruising. / 📍 Location: /12…  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "Used Royal Enfield Classic 350🏍️ – Best Deals in Gobichettipalayam | Engine Thagaval #royalenfield"

**ASKODOX AI (production):** Based on the listing details for **Used Royal Enfield Classic 350** by Engine Thagaval: - **Condition & Specs**: Described as a single-owner, well-maintained bike with a smooth BS6 engine, suitable for city rides and highway cruising. - **Location**: 126 Sathy Athani Main Road, Punjaithuraiyampalayam, Gobichettipalayam, Tamil Nadu. - **Price**: Not provided by the source. - **Stock / Availability**: Not provided. - **Rating / Reviews**: Not provided. *Note: These details reflect the creator's opinion and listing description, not verified by ASKODOX. Price and availability are not specified.*

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

**ASKODOX AI (production):** This video by **CallMeShazzam TECH** provides a long-term review of the iPhone 15, discussing its overall value and whether it is a strong option during upcoming sales. Please note that these are the creator's opinions and are not verified by ASKODOX. Key details from the listing: - **Price:** Not provided - **Stock / Availability:** Not provided - **Rating / Reviews:** Not provided - **Language:** Malayalam with English subtitles Specific specifications, current pricing, and local availability are not provided in the video details.

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** Let me check real sellers, shops and online options near you.  
**This branch:** Let me check real sellers, shops and online options near you. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "iphone 15 offers" → MasterPhone [nearby_external]; Buy Second Hand Apple iPhone 15 Phone Under ₹23000 in Vijayawada | Best Prices – ORUphones [used]; Apple Open Box [surplus]; iPhone 15 is available for less than Rs 35,000 on Vijay Sales, here is how the deal works - India Today [deals]

### service-te (te) -- "ఏసీ సర్వీస్ వీడియో"

**Video:** DAIKIN AC Outdoor Unit Cleaning #acservice #airconcleaning #accleaning #HVAC #shortsvideo -- Lovepreet Singh (https://www.youtube.com/watch?v=7mK4-impjiE)

**ASKODOX explain (branch):** ఈ వీడియోను నేను చూడలేదు/విశ్లేషించలేదు. శీర్షిక, క్రియేటర్ ఇచ్చిన వివరణ, ఛానల్ మాత్రమే తెలుసు.  
Quoted from source: DAIKIN AC Outdoor Unit Cleaning #acservice #airconcleaning #accleaning #HVAC #shortsvideo / How to Service the DAIKIN AC Outdoor Unit of Split AC / How to Service the Outdoor Unit of a Split AC / AC outdoor unit cleaning / ac cleaning at home  
Label: Creator's opinion -- not verified by ASKODOX

**User:** "DAIKIN AC Outdoor Unit Cleaning #acservice #airconcleaning #accleaning #HVAC #shortsvideo" గురించి చెప్పండి: ధర, దూరం, నాణ్యత, అందుబాటు, రివ్యూలు

**ASKODOX AI (production):** ఈ వీడియో డైకిన్ స్ప్లిట్ ఏసీ ఔట్‌డోర్ యూనిట్ క్లీనింగ్ మరియు సర్వీస్ విధానం గురించి చూపుతుంది (క్రియేటర్ Lovepreet Singh అభిప్రాయం, ASKODOX ద్వారా ధృవీకరించబడలేదు). మీరు అడిగిన వివరాలు: - **ధర**: అందుబాటులో లేదు (Not provided) - **దూరం**: అందుబాటులో లేదు (Not provided) - **నాణ్యత / రివ్యూలు**: అందుబాటులో లేదు (Not provided) - **అందుబాటు**: అందుబాటులో లేదు (Not provided) వీడియోలో కేవలం సొంతంగా ఏసీ ఔట్‌డోర్ యూనిట్ క్లీనింగ్ ఎలా చేసుకోవాలో మార్గదర్శకం మాత్రమే ఉంది. మీకు విజయవాడలో ప్రొఫెషనల్ ఏసీ సర్వీసింగ్ టెక్నీషియన్ కావాలంటే చెప్పండి, వెతికి చూపిస్తాను.

**User (follow-up, same conversation):** ఇది చిన్న గదికి సరిపోతుందా?

**ASKODOX AI:** డైకిన్ ఏసీ ఔట్‌డోర్ యూనిట్ అనేది ఏదైనా ఏసీ సిస్టమ్‌లో భాగం మాత్రమే. ఈ వీడియో కేవలం ఔట్‌డోర్ యూనిట్ శుభ్రం చేయడం గురించే వివరిస్తుంది. చిన్న గదికి (ఉదాహరణకు **100 Sq. Ft.** లోపు) ఏసీ సరిపోతుందా అనేది ఆ ఏసీ **కెపాసిటీ (Tonnage)** పై ఆధారపడి ఉంటుంది: - చిన్న గదికి **0.8 Ton** లేదా **1 Ton** ఏసీ సరిగ్గా సరిపోతుంది. - గది పరిమాణానికి మించిన పెద్ద ఏసీ వాడితే విద్యుత్ వినియోగం ఎక్కువవుతుంది. మీ గది పరిమాణం ఎంత ఉందో తెలుపగలరా?

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
