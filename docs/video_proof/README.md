# Real video content proof

Generated 2026-10-08T17:30:49Z by `.github/workflows/video-real-content-proof.yml` (run 37816596460).

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

**ASKODOX AI (production):** Based on the details provided by **TechWay7.0** for the **Samsung 43" UA43F5600FUXXL** (2026 model): - **Display & Picture:** 43-inch Full HD display featuring PurColor technology for enhanced color expression. - **Smart Features:** Includes Samsung Smart TV functionality, a picture quality test, and sound quality evaluation. - **Design:** Features a refreshed 2026 build and design aesthetics. *Note:* The exact price, rating, reviews, stock availability, and distance are **not provided** by the source (TechWay7.0's opinion, not verified by ASKODOX).

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** Let me check real sellers, shops and online options near you.  
**This branch:** Let me check real sellers, shops and online options near you. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "samsung 43 inch tv near me" → Reliance Digital [nearby_external]; Samsung 43-inch TVs Price List in India (October 2026) [deals]; Shop Samsung 43 Inch TVs Online Best Deals & Prices in India [deals]; Samsung 43 Inch Smart Tv - Buy Samsung 43 Inch Smart Tv online at Best Prices in India | Flipkart.com [deals]

### electronics-te (te) -- "శామ్‌సంగ్ 43 అంగుళాల టీవీ రివ్యూ వీడియో"

**Video:** Samsung 43" Pure Color Full HD 2026 😱 | UA43F5600FUXXL Unboxing & True Review | ₹2X,XXX? -- TechWay7.0 (https://www.youtube.com/watch?v=vJQK7mzFTK8)

**ASKODOX explain (branch):** ఈ వీడియోను నేను చూడలేదు/విశ్లేషించలేదు. శీర్షిక, క్రియేటర్ ఇచ్చిన వివరణ, ఛానల్ మాత్రమే తెలుసు.  
Quoted from source: Samsung 43" Pure Color Full HD 2026 😱 | UA43F5600FUXXL Unboxing & True Review | ₹2X,XXX? / Samsung UA43F5600 full High definition 2026 Smart tv. / Samsung का New 2026 Pure Color Full HD Smart TV / Information. / ✅ 43" Full HD Display  
Label: Creator's opinion -- not verified by ASKODOX

**User:** "Samsung 43" Pure Color Full HD 2026 😱 | UA43F5600FUXXL Unboxing & True Review | ₹2X,XXX?" గురించి చెప్పండి: ధర, దూరం, నాణ్యత, అందుబాటు, రివ్యూలు

**ASKODOX AI (production):** ఈ వీడియో **TechWay7.0** ఛానెల్ ద్వారా అందించబడింది (ఇది క్రియేటర్ అభిప్రాయం, ASKODOX ద్వారా ధృవీకరించబడలేదు): - **ధర:** అందుబాటులో లేదు ( Not verified ). - **దూరం:** వివరాలు ఇవ్వలేదు. - **నాణ్యత:** 43 ఇంచుల Full HD డిస్‌ప్లే, పిక్చర్ & సౌండ్ క్వాలిటీ టెస్ట్ మరియు Pure Color టెక్నాలజీ ఉన్నాయని పేర్కొన్నారు. - **అందుబాటు:** సమాచారం ఇవ్వలేదు. - **రివ్యూలు:** వీడియో వివరణలో స్మార్ట్ టీవీ ఫీచర్లు, డిజైన్ మరియు రియల్ ప్రైస్ రివ్యూ అని ఉంది. మీకు ఈ టీవీ స్థానిక షాపుల్లో అందుబాటు లేదా ఖచ్చితమైన ధర కావాలంటే చెప్పండి, మేము షాపు వారిని అడిగి తెలుసుకుంటాము.

**User (follow-up, same conversation):** ఇది చిన్న గదికి సరిపోతుందా?

**ASKODOX AI:** సాధారణంగా **43 ఇంచుల టీవీ** సరిగ్గా చూడటానికి **5 నుండి 7 అడుగుల దూరం** ఉండాలి. మీ చిన్న గదిలో బెడ్ లేదా సోఫా నుండి టీవీ చూసే దూరం కనీసం 5 అడుగులు ఉంటే ఇది బాగా సరిపోతుంది. ఒకవేళ చూసే దూరం 5 అడుగుల కంటే తక్కువ ఉంటే, **32 ఇంచుల టీవీ** కళ్లకు మరింత సౌకర్యవంతంగా ఉంటుంది. మీ గదిలో టీవీ చూసే దూరం సుమారు ఎన్ని అడుగులు ఉంటుంది?

**Next step:** "samsung 43 inch tv offers" → Reliance Digital [nearby_external]; Samsung 43-inch TVs Price List in India (October 2026) [deals]; Shop Samsung 43 Inch TVs Online Best Deals & Prices in India [deals]; Samsung 43 Inch Smart Tv - Buy Samsung 43 Inch Smart Tv online at Best Prices in India | Flipkart.com [deals]

### phone (en) -- "Redmi Note 13 Pro review video"

**Video:** Redmi Note 13 Pro is here - Let's Check! -- Gyan Therapy (https://www.youtube.com/watch?v=kGG04jkdjxY)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: Redmi Note 13 Pro is here - Let's Check! / Redmi Note 13, Redmi Note 13 Pro and Redmi Note 13 Pro+ launched in India. / Redmi Note 13 Pro comes with Snapdragon 7s Gen 2 Processor, 200MP triple camera with 5100mAh Battery with 67W Charging from Xiaomi. / Here is my Redmi Note 13 Pro Unboxing and Ini…  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "Redmi Note 13 Pro is here - Let's Check!"

**ASKODOX AI (production):** This video by **Gyan Therapy** is an unboxing and initial impressions review of the Redmi Note 13 Pro. Key details mentioned in the video description: - **Processor**: Snapdragon 7s Gen 2 - **Camera**: 200MP triple camera setup - **Battery & Charging**: 5100mAh battery with 67W fast charging *Note: Creator's opinion is not verified by ASKODOX. Specs like price, rating, and stock are Not verified/not provided by the source.*

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

**ASKODOX AI (production):** This video by creator Moto-Wanderer discusses the Tata Nexon Facelift (referred to as Next Gen / Garuda) and mentions potential discounts of up to ₹1 lakh while comparing its appeal against the Maruti Brezza. It covers the model lineup ranging from Smart, Pure, Creative, to Accomplish trims. - **Source**: Moto-Wanderer (Creator's opinion -- not verified by ASKODOX) - **Price**: Not provided - **Stock / Availability**: Not provided - **Rating / Reviews**: Not provided Please note that specific discount claims or comparisons represent the creator's opinion and are not verified facts.

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

**ASKODOX AI (production):** This video by creator **Lovepreet Singh** covers a DIY guide on servicing and cleaning a Daikin split AC outdoor unit at home using water cleaning techniques. - **Details from source**: Specific steps, safety precautions, tools used, and user ratings are **not provided** in the listed metadata. - **Note**: The video content represents the creator's opinion and is **not verified by ASKODOX**. If you want to perform this yourself, ensure the main power supply is completely switched off before using water, and avoid spraying high-pressure water directly into the electrical control box or fins, as bent fins reduce cooling efficiency.

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

**ASKODOX AI (production):** Based on the provided details for the video **"Great Plumbing Trick To Fix Pvc Pipe Joint #shortvideo #shorts #shortsfeed"** by creator **vijay xyz tricks**: - **Channel/Creator:** vijay xyz tricks (Creator's opinion — not verified by ASKODOX) - **Description/Notes:** "thanks for watching video" - **Price:** Not provided - **Distance:** Not provided - **Stock/Availability:** Not provided - **Rating/Reviews:** Not provided *Note:* The video content itself has not been analyzed, and detailed specifications or specific step-by-step instructions from the clip are not provided by the source.

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

**ASKODOX AI (production):** This video by **DCT EATS** (feat. Sahil from Headbanger Eats) compares three price tiers of Hyderabadi mutton biryani in Mumbai from **Bikkgane Biryani**, **Biryani By Kilo**, and **Lit**. Here are the details available from the source: - **Restaurants featured**: Bikkgane Biryani (approx. ₹450), Biryani By Kilo (approx. ₹800), and Lit (approx. ₹1200) - **Topic**: Mutton Hyderabadi Biryani taste and portion comparison across price points - **Price / Rating / Distance**: Not provided by the source (opinions reflect DCT EATS, not verified by ASKODOX) Note: The video content itself has not been analyzed beyond these listed details.

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** Let me check real sellers, shops and online options near you.  
**This branch:** Let me check real sellers, shops and online options near you. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "hyderabadi biryani near me" → Green Bucket Biryani Governorpet Vijayawada (PJ FOOD & BEVERAGES) [nearby_external]; Best Hyderabadi Biryani Restaurants In Vijayawada 2025 | Order Online [deals]

### travel (en) -- "Araku valley trip review video"

**Video:** Araku Valley Full Tour | Things to do in Araku Valley | Places to Visit in Araku -- Travel Matcha (https://www.youtube.com/watch?v=rMd5DUP04RE)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: Araku Valley Full Tour | Things to do in Araku Valley | Places to Visit in Araku / in This video we are giving out a full itinerary for Araku Valley, / Araku Valley is Andhra Pradesh’s Hidden Gem! / Imagine waking up to mist-covered hills, walking through lush coffee plantations, exploring ancient …  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "Araku Valley Full Tour | Things to do in Araku Valley | Places to Visit in Araku"

**ASKODOX AI (production):** Based on the details provided for **"Araku Valley Full Tour | Things to do in Araku Valley | Places to Visit in Araku"** by creator Travel Matcha: - **Content Overview**: The creator shares a full travel itinerary for Araku Valley, highlighting attractions like mist-covered hills, coffee plantations, ancient caves, and local cuisine. *(Note: This reflects the creator's opinion and is not verified by ASKODOX).* - **Price**: Not provided - **Distance**: Not provided - **Rating / Reviews**: Not provided - **Stock / Availability**: Not provided Specific details like entry fees, exact routes, or traveler ratings are **Not verified** as they were not provided in the source description.

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

**ASKODOX AI (production):** This video is titled **"iPhone 15 | Long Term Review | Best iPhone? | Next Sale King? | Malayalam with Eng Sub"** by **CallMeShazzam TECH**. Here are the details available from the source: - **Creator:** CallMeShazzam TECH (their opinion, not a verified fact) - **Price:** Not provided - **Rating / Reviews:** Not provided - **Stock / Availability:** Not provided - **Distance / Location:** Not provided Please note: The video content itself has not been analyzed, and specific specs or conclusions from the creator are Not verified by ASKODOX.

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

**ASKODOX AI (production):** మీరు అడిగిన **DAIKIN AC Outdoor Unit Cleaning** వీడియో ఆధారంగా వివరాలు: - **ధర (Price):** Not verified (వీడియో వివరాల్లో ధర అందుబాటులో లేదు) - **దూరం (Distance):** Not verified - **నాణ్యత & రివ్యూలు (Quality & Reviews):** Not verified (ఇది క్రියේటర్ Lovepreet Singh అభిప్రాయం మాత్రమే, ASKODOX ద్వారా ధృవీకరించబడలేదు) - **అందుబాటు (Availability):** Not verified వీడియోలో అవుట్‌డోర్ యూనిట్ వాటర్ సర్వీసింగ్ మరియు ఇంట్లో ఎలా క్లీన్ చేయాలో వివరించారు. మీకు స్థానికంగా విజయవాడలో ఏసీ సర్వీసింగ్ టెక్నీషియన్ కావాలంటే చెప్పండి, వెతికి సహాయం చేస్తాను.

**User (follow-up, same conversation):** ఇది చిన్న గదికి సరిపోతుందా?

**ASKODOX AI:** మీది ఎంత పరిమాణం ఉన్న గది? సాధారణంగా **100 చదరపు అడుగుల** లోపు ఉన్న చిన్న గదికి **0.8 టన్ నుండి 1 టన్** ఏసీ సరిపోతుంది. గది పరిమాణాన్ని బట్టి సరైన టన్ను ఏసీని ఎంచుకోవడం ద్వారా విద్యుత్ ఆదా అవుతుంది.

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
