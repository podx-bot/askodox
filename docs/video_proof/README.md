# Real video content proof

Generated 2026-10-09T01:35:12Z by `.github/workflows/video-real-content-proof.yml` (run 37870149503).

* Video rows: **real**, from production's live web video search (Brave) -- replayed into this branch's pipeline, which adds references, YouTube oEmbed checks (live network), linking and disclosures.
* AI answers: **real**, from the production assistant (`/api/in-app/assistant`) given exactly what the app sends (question + grounding from this branch's explain).
* Next-step options: **real**, from production's discovery for the step's text.
* Service cases: production (main) does not search videos for service needs, so their real video rows come from a product-category source query for the same subject; this branch runs them as service needs.
* YouTube Data API: needs_configuration (no YOUTUBE_API_KEY in this run).

| Case | Lang | Videos | Top video | Channel | Plays in app | Disclosure | AI answer | Follow-up | Next step → options |
|---|---|---|---|---|---|---|---|---|---|
| electronics | en | 1 | [I bought ALL the Best 43-inch TV under 30K! - Flipkart Big …](https://www.youtube.com/watch?v=T09U8CUH5Jw) | TechTraveller Blend | yes (official YouTube embed) | Creator's opinion -- not verified by ASKODOX | yes | yes | samsung 43 inch tv near me → 4 (deals, nearby_external) |
| electronics-te | te | 1 | [I bought ALL the Best 43-inch TV under 30K! - Flipkart Big …](https://www.youtube.com/watch?v=T09U8CUH5Jw) | TechTraveller Blend | yes (official YouTube embed) | Creator's opinion -- not verified by ASKODOX | yes | yes | samsung 43 inch tv offers → 6 (deals, nearby_external) |
| phone | en | 1 | [Redmi Note 13 Pro is here - Let's Check!](https://www.youtube.com/watch?v=kGG04jkdjxY) | Gyan Therapy | yes (official YouTube embed) | Creator's opinion -- not verified by ASKODOX | yes | yes | redmi note 13 pro offers → 6 (deals, nearby_external, surplus, used) |
| vehicle | en | 1 | [LAUNCH DATA ✅ Tata Nexon Facelift / Next Gen / NVH खत्म / B…](https://www.youtube.com/watch?v=udv2P4GxqjE) | Moto-Wanderer | yes (official YouTube embed) | Creator's opinion -- not verified by ASKODOX | yes | no (fallback) | tata nexon near me → 4 (deals, nearby_external, surplus) |
| service | en | 1 | [Urban Company AC Service / Spilit AC Cleaning Advance Foamj…](https://www.youtube.com/watch?v=qPF6hbFHCUc) | KP Vlogs & Review | yes (official YouTube embed) | Creator's opinion -- not verified by ASKODOX | yes | yes | ac service near me → 1 (nearby_external) |
| home-service | en | 1 | [Great Plumbing Trick To Fix Pvc Pipe Joint #shortvideo #sho…](https://www.youtube.com/watch?v=Bvxkrv7t4Dw) | vijay xyz tricks | yes (official YouTube embed) | Creator's opinion -- not verified by ASKODOX | yes | yes | plumbing repair service near me → 1 (nearby_external) |
| food | en | 1 | [₹450 vs ₹800 vs ₹1200 Hyderabadi Biryani In Mumbai!! 🤔](https://www.youtube.com/watch?v=NYNr1X8Qokw) | DCT EATS | yes (official YouTube embed) | Creator's opinion -- not verified by ASKODOX | yes | yes | hyderabadi biryani near me → 2 (deals, nearby_external) |
| travel | en | 1 | [Araku Valley Full Tour / Things to do in Araku Valley / Pla…](https://www.youtube.com/watch?v=rMd5DUP04RE) | Travel Matcha | yes (official YouTube embed) | Creator's opinion -- not verified by ASKODOX | yes | yes | araku valley trip reviews → 6 (deals, nearby_external) |
| used-item | en | 1 | [How To Check & Buy Used Classic 350 - How To Buy 2nd Hand R…](https://www.youtube.com/watch?v=GW-rCk-eAoU) | Bindass Singh | yes (official YouTube embed) | Creator's opinion -- not verified by ASKODOX | yes | yes | used royal enfield classic 350 near me → 4 (deals, nearby_external, used) |
| deal | en | 1 | [iPhone 15 / Long Term Review / Best iPhone? / Next Sale Kin…](https://www.youtube.com/watch?v=LtaCjbudjpQ) | CallMeShazzam TECH | yes (official YouTube embed) | Creator's opinion -- not verified by ASKODOX | yes | yes | iphone 15 offers → 6 (deals, nearby_external, surplus, used) |
| service-te | te | 1 | [Urban Company AC Service / Spilit AC Cleaning Advance Foamj…](https://www.youtube.com/watch?v=qPF6hbFHCUc) | KP Vlogs & Review | yes (official YouTube embed) | Creator's opinion -- not verified by ASKODOX | yes | yes | ac service near me → 1 (nearby_external) |

## Conversations (real AI answers)

### electronics (en) -- "Samsung 43 inch TV review videos"

**Video:** I bought ALL the Best 43-inch TV under 30K! - Flipkart Big Billion Days -- TechTraveller Blend (https://www.youtube.com/watch?v=T09U8CUH5Jw)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: I bought ALL the Best 43-inch TV under 30K! - Flipkart Big Billion Days / I bought ALL the best 43-inch TVs under 30K! / - Flipkart Big Billion Days / ==================================== / Looking for the absolute BEST 32-inch Smart TV?  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "I bought ALL the Best 43-inch TV under 30K! - Flipkart Big Billion Days"

**ASKODOX AI (production):** Based on the available information for the video **"I bought ALL the Best 43-inch TV under 30K! - Flipkart Big Billion Days"** by creator **TechTraveller Blend**: - **Source**: TechTraveller Blend (Creator's opinion — not verified by ASKODOX) - **Price**: Not provided - **Rating / Reviews**: Not provided - **Stock / Availability**: Not provided Note: The description text mentions comparing 32-inch Smart TVs from brands like Samsung, LG, Motorola, Realme, and Xiaomi (Mi), though the title references 43-inch TVs under ₹30,000. Specific video contents, tested specs, and exact prices are not provided by the source.

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** Let me check real sellers, shops and online options near you.  
**This branch:** Let me check real sellers, shops and online options near you. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "samsung 43 inch tv near me" → Reliance Digital [nearby_external]; Samsung 43-inch TVs Price List in India (October 2026) [deals]; Shop Samsung 43 Inch TVs Online Best Deals & Prices in India [deals]; Samsung 43 Inch Smart Tv - Buy Samsung 43 Inch Smart Tv online at Best Prices in India | Flipkart.com [deals]

### electronics-te (te) -- "శామ్‌సంగ్ 43 అంగుళాల టీవీ రివ్యూ వీడియో"

**Video:** I bought ALL the Best 43-inch TV under 30K! - Flipkart Big Billion Days -- TechTraveller Blend (https://www.youtube.com/watch?v=T09U8CUH5Jw)

**ASKODOX explain (branch):** ఈ వీడియోను నేను చూడలేదు/విశ్లేషించలేదు. శీర్షిక, క్రియేటర్ ఇచ్చిన వివరణ, ఛానల్ మాత్రమే తెలుసు.  
Quoted from source: I bought ALL the Best 43-inch TV under 30K! - Flipkart Big Billion Days / I bought ALL the best 43-inch TVs under 30K! / - Flipkart Big Billion Days / ==================================== / Looking for the absolute BEST 32-inch Smart TV?  
Label: Creator's opinion -- not verified by ASKODOX

**User:** "I bought ALL the Best 43-inch TV under 30K! - Flipkart Big Billion Days" గురించి చెప్పండి: ధర, దూరం, నాణ్యత, అందుబాటు, రివ్యూలు

**ASKODOX AI (production):** ఈ వీడియో ద్వారా ధర, దూరం, నాణ్యత, అందుబాటు మరియు రివ్యూలకు సంబంధించిన వివరాలు **పరిశీలించబడలేదు (Not verified)**. వీడియో వివరణలో ఇచ్చిన వివరాల ప్రకారం: - **ధర:** అందుబాటులో లేదు (Not provided) - **దూరం:** అందుబాటులో లేదు (Not provided) - **నాణ్యత / రివ్యూలు:** పరిశీలించబడలేదు, ఇది TechTraveller Blend క్రియేటర్ అభిప్రాయం మాత్రమే. - **అందుబాటు:** అందుబాటులో లేదు (Not provided) మీకు నిర్దిష్ట టీవీ మోడల్ వివరాలు లేదా స్థానిక షాపుల ధరలు కావాలంటే చెప్పండి, వెతికి చెప్తాను.

**User (follow-up, same conversation):** ఇది చిన్న గదికి సరిపోతుందా?

**ASKODOX AI:** చిన్న గదికి (ఉదాహరణకు 10x10 అడుగులు) 43 అంగుళాల టీవీ కాస్త పెద్దదిగా అనిపించవచ్చు. సాధారణంగా 43 ఇంచుల టీవీ చూడటానికి **6 నుండి 8 అడుగుల దూరం** ఉండాలి. - మీ గదిలో చూసే దూరం 6 అడుగుల కంటే తక్కువ ఉంటే 32 ఇంచుల టీవీ సరిపోతుంది. - 6 నుండి 8 అడుగుల దూరం ఉంటే 43 ఇంచుల టీవీ చాలా బాగుంటుంది. మీ గదిలో టీవీకి, మీరు కూర్చునే చోటికి ఎంత దూరం ఉందో చెప్పగలరా?

**Next step:** "samsung 43 inch tv offers" → Reliance Digital [nearby_external]; Samsung 43-inch TVs Price List in India (October 2026) [deals]; Shop Samsung 43 Inch TVs Online Best Deals & Prices in India [deals]; Samsung 43 Inch Smart Tv - Buy Samsung 43 Inch Smart Tv online at Best Prices in India | Flipkart.com [deals]

### phone (en) -- "Redmi Note 13 Pro review video"

**Video:** Redmi Note 13 Pro is here - Let's Check! -- Gyan Therapy (https://www.youtube.com/watch?v=kGG04jkdjxY)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: Redmi Note 13 Pro is here - Let's Check! / Redmi Note 13, Redmi Note 13 Pro and Redmi Note 13 Pro+ launched in India. / Redmi Note 13 Pro comes with Snapdragon 7s Gen 2 Processor, 200MP triple camera with 5100mAh Battery with 67W Charging from Xiaomi. / Here is my Redmi Note 13 Pro Unboxing and Ini…  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "Redmi Note 13 Pro is here - Let's Check!"

**ASKODOX AI (production):** This video by creator **Gyan Therapy** is an unboxing and initial impressions look at the Redmi Note 13 Pro. Here are the details provided from the video description: - **Processor:** Snapdragon 7s Gen 2 - **Camera:** 200MP triple camera setup - **Battery & Charging:** 5100mAh battery with 67W fast charging *Note: Creator opinions are not verified by ASKODOX. Specific details such as price, user ratings, and current availability are not provided in the video source.*

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** Let me check real sellers, shops and online options near you.  
**This branch:** Let me check real sellers, shops and online options near you. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "redmi note 13 pro offers" → Happi Mobiles Vijayawada Bandar Road [nearby_external]; Buy Old Used Xiaomi Redmi Note 13 Pro 4G Phones Under ... [used]; Open Box Store [surplus]; Redmi Note 13 5G, Note 13 Pro 5G, Note 13 Pro+ 5G goes on sale on Vijay Sales - Times of India [deals]

### vehicle (en) -- "Tata Nexon review video"

**Video:** LAUNCH DATA ✅ Tata Nexon Facelift / Next Gen  | NVH खत्म | Big Tyre | Big Size | Full New Looks 😍 -- Moto-Wanderer (https://www.youtube.com/watch?v=udv2P4GxqjE)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: LAUNCH DATA ✅ Tata Nexon Facelift / Next Gen | NVH खत्म | Big Tyre | Big Size | Full New Looks 😍 / तहलका SUV 😎 Tata Nexon Facelift / Nexon Next Gen / Garuda , पर 1 लाख Discount 🤔 खत्म Maruti Brezza / Tata Nexon Smart Pure Creative Accomplish Base to Top Model / Your Queries: / Tata Nexon Facelift  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "LAUNCH DATA ✅ Tata Nexon Facelift / Next Gen  | NVH खत्म | Big Tyre | Big Size | Full New Looks 😍"

**ASKODOX AI (production):** Based on the video listing provided by **Moto-Wanderer**: - **Title:** LAUNCH DATA ✅ Tata Nexon Facelift / Next Gen | NVH खत्म | Big Tyre | Big Size | Full New Looks 😍 - **Price:** Not provided by the source - **Rating / Reviews:** Not provided by the source - **Availability:** Not provided by the source *Note:* The video content itself was not analyzed, and the points highlighted in the title reflect the creator's opinion, which is **not verified by ASKODOX**. If you'd like details on specific features, trim levels (Smart, Pure, Creative, Accomplish), or official specifications for the Tata Nexon, let me know!

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:**   
**This branch:** Let me check real sellers, shops and online options near you. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "tata nexon near me" → Tata Motors Commercial Vehicle Dealer - Sahni Auto Private Limited [nearby_external]; Tata Nexon On Road Price in Vijayawada (2026) – ₹8.63 lakh Onwards | Autocar India [surplus]; Tata Nexon price in Vijayawada | Tata Nexon on road Price 2026 | Times Drive [deals]; Tata Nexon Price in Vijayawada-August 2026 Nexon On Road Price [deals]

### service (en) -- "AC service video"

**Video:** Urban Company AC Service | Spilit AC Cleaning Advance Foamjet Technology | AC Cleaning Service | -- KP Vlogs & Review (https://www.youtube.com/watch?v=qPF6hbFHCUc)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: Urban Company AC Service | Spilit AC Cleaning Advance Foamjet Technology | AC Cleaning Service | / #urbancompany #acservice #airconditioner #urbanclap #splitacservice #acservice2025 #summeracservice #kpvlogsandreview #honestreview #affordableservice #watchbeforehire #newtechnology #shortsyoutube #y…  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "Urban Company AC Service | Spilit AC Cleaning Advance Foamjet Technology | AC Cleaning Service |"

**ASKODOX AI (production):** Based on the video listed by **KP Vlogs & Review**: - **Title**: Urban Company AC Service | Spilit AC Cleaning Advance Foamjet Technology | AC Cleaning Service | - **Creator Opinion**: The creator provides an honest review and vlog about using Urban Company's Foamjet technology for Split AC cleaning (this is the creator's personal opinion, not verified by ASKODOX). - **Details**: Price, rating, reviews, and availability are **Not verified** (not provided by the source). **About Foamjet AC Cleaning Technology:** Foamjet cleaning uses high-pressure foam spray to penetrate deep into the condenser and evaporator coils of a Split AC. It removes stubborn dirt, mold, and heavy dust better than normal water washing, improving cooling efficiency and airflow. Would you like me to help find local AC servicing or cleaning providers near Vijayawada?

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

**ASKODOX AI (production):** Based on the provided details for **"Great Plumbing Trick To Fix Pvc Pipe Joint #shortvideo #shorts #shortsfeed"** by creator *vijay xyz tricks*: - **Source/Creator:** vijay xyz tricks (Creator's opinion — not verified by ASKODOX) - **Price:** Not provided - **Distance / Availability:** Not provided - **Rating / Reviews:** Not provided Since the video content itself has not been analyzed, specific details or steps shown in the video are not available beyond the title and creator description. If you need help fixing a leaking or loose PVC pipe joint directly, I can explain standard methods like applying PVC solvent cement or using a temporary sealant/tape. Let me know what issue you are facing with your PVC joint!

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

**ASKODOX AI (production):** This video by DCT EATS explores whether authentic Hyderabadi mutton biryani is available in Mumbai by comparing three price points (₹450, ₹800, and ₹1200) from Bikkgane Biryani, Biryani By Kilo, and Lit, featuring Sahil from Headbanger Eats (Creator's opinion — not verified by ASKODOX). Here are the details provided for this video: - **Price / Distance / Rating / Reviews**: Not provided by the source. - **Featured Places**: Bikkgane Biryani, Biryani By Kilo, Lit. Since specific details like exact ratings, viewer reviews, or prices are not provided, let me know if you would like me to search for more videos or comparisons!

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** Let me check real sellers, shops and online options near you.  
**This branch:** Let me check real sellers, shops and online options near you. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "hyderabadi biryani near me" → Bismillah Paradise Biryani [nearby_external]; Best Hyderabadi Biryani Restaurants In Vijayawada 2025 | Order Online [deals]

### travel (en) -- "Araku valley trip review video"

**Video:** Araku Valley Full Tour | Things to do in Araku Valley | Places to Visit in Araku -- Travel Matcha (https://www.youtube.com/watch?v=rMd5DUP04RE)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: Araku Valley Full Tour | Things to do in Araku Valley | Places to Visit in Araku / in This video we are giving out a full itinerary for Araku Valley, / Araku Valley is Andhra Pradesh’s Hidden Gem! / Imagine waking up to mist-covered hills, walking through lush coffee plantations, exploring ancient …  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "Araku Valley Full Tour | Things to do in Araku Valley | Places to Visit in Araku"

**ASKODOX AI (production):** Based on the details provided for **"Araku Valley Full Tour | Things to do in Araku Valley | Places to Visit in Araku"** by Travel Matcha (creator's opinion, not verified by ASKODOX): - **Content:** The video offers a complete trip itinerary for Araku Valley, highlighting mist-covered hills, coffee plantations, ancient caves, and local food. - **Pricing:** Not provided - **Ratings / Reviews:** Not provided - **Distance / Location details:** Not provided *Note: Specific facts like prices or detailed reviews are not provided by the source.*

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** Let me check real sellers, shops and online options near you.  
**This branch:** Let me check real sellers, shops and online options near you. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "araku valley trip reviews" → Akkanna Madanna Caves [nearby_external]; Araku Valley Tour Packages From Vijayawada – Vijayawada To Araku Valley Packages | TT [deals]; 5 Araku Valley Tour Packages at ₹6785 pp - Book Online with 20% Off [deals]; Araku Valley Tour Packages from Vijayawada | Araku Valley Packages from Vijayawada | Araku Valley Honeymoon Packages from Vijayawada | Araku Valley Holiday Pack [deals]

### used-item (en) -- "used Royal Enfield Classic 350 review video"

**Video:** How To Check & Buy Used Classic 350 - How To Buy 2nd Hand Royal Enfield Classic 350 -- Bindass Singh (https://www.youtube.com/watch?v=GW-rCk-eAoU)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: How To Check & Buy Used Classic 350 - How To Buy 2nd Hand Royal Enfield Classic 350 / How To Check And Buy Old Royal Enfield Classic 350.How To Buy Used Royal Enfield.How To Buy Second Hand Bullet.How To Buy 2nd Hand Royal Enfield Bullet or Classic.Purani Royal Enfield Classic 350cc Kaise Kya Kya C…  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "How To Check & Buy Used Classic 350 - How To Buy 2nd Hand Royal Enfield Classic 350"

**ASKODOX AI (production):** This video by creator **Bindass Singh** covers practical tips on how to inspect and purchase a second-hand Royal Enfield Classic 350. Key points from the listed video details: - **Content focus**: Covers inspection steps, what to check before buying, and buying guidance for a used Classic 350. - **Source/Creator**: Bindass Singh (creator's opinion, not verified by ASKODOX). - **Details not provided**: Specific vehicle specs, pricing, seller location, stock, and condition ratings are **Not verified** in the video listing details. **General pre-purchase checklist for a used Classic 350**: - **Engine & Mechanicals**: Check for oil leaks around the head/sump, unusual tappet noise, and smoke from the exhaust. - **Frame & Alignment**: Inspect for frame rust, bend, or crash damage near the chassis down-tubes. - **Service History & Legal**: Verify RC transfer status, active insurance, and NOC i…

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

**ASKODOX AI (production):** This is a video titled **iPhone 15 | Long Term Review | Best iPhone? | Next Sale King? | Malayalam with Eng Sub** by creator **CallMeShazzam TECH**. Here are the details provided from the listing: - **Creator:** CallMeShazzam TECH (creator's opinion, not verified by ASKODOX) - **Language:** Malayalam with English subtitles - **Price:** Not provided - **Rating / Reviews:** Not provided - **Stock / Availability:** Not provided Since the video content itself has not been analyzed, specific specs, opinions, or conclusions discussed in the video are not provided.

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** Let me check real sellers, shops and online options near you.  
**This branch:** Let me check real sellers, shops and online options near you. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "iphone 15 offers" → MasterPhone [nearby_external]; Buy Second Hand Apple iPhone 15 Phone Under ₹23000 in Vijayawada | Best Prices – ORUphones [used]; Apple Open Box [surplus]; iPhone 15 is available for less than Rs 35,000 on Vijay Sales, here is how the deal works - India Today [deals]

### service-te (te) -- "ఏసీ సర్వీస్ వీడియో"

**Video:** Urban Company AC Service | Spilit AC Cleaning Advance Foamjet Technology | AC Cleaning Service | -- KP Vlogs & Review (https://www.youtube.com/watch?v=qPF6hbFHCUc)

**ASKODOX explain (branch):** ఈ వీడియోను నేను చూడలేదు/విశ్లేషించలేదు. శీర్షిక, క్రియేటర్ ఇచ్చిన వివరణ, ఛానల్ మాత్రమే తెలుసు.  
Quoted from source: Urban Company AC Service | Spilit AC Cleaning Advance Foamjet Technology | AC Cleaning Service | / #urbancompany #acservice #airconditioner #urbanclap #splitacservice #acservice2025 #summeracservice #kpvlogsandreview #honestreview #affordableservice #watchbeforehire #newtechnology #shortsyoutube #y…  
Label: Creator's opinion -- not verified by ASKODOX

**User:** "Urban Company AC Service | Spilit AC Cleaning Advance Foamjet Technology | AC Cleaning Service |" గురించి చెప్పండి: ధర, దూరం, నాణ్యత, అందుబాటు, రివ్యూలు

**ASKODOX AI (production):** ఈ వీడియో 'Urban Company AC Service (Advance Foamjet Technology)' గురించి KP Vlogs & Review వారి అభిప్రాయం మాత్రమే, ఇది ASKODOX ద్వారా ధృవీకరించబడలేదు. వీడియో వివరాల ప్రకారం: - **ధర:** అందుబాటులో లేదు (Not verified) - **దూరం:** అందుబాటులో లేదు (Not verified) - **నాణ్యత / రివ్యూలు:** నాట్ వెరిఫైడ్ (వీడియో క్రియేటర్ అభిప్రాయం మాత్రమే, సారాంశం వివరించబడలేదు) - **అందుబాటు:** అందుబాటులో లేదు (Not verified) ధర మరియు ఇతర అధికారిక వివరాలు కావాలంటే సర్వీస్ ప్రొవైడర్‌ను అడిగి తెలుసుకోవచ్చు.

**User (follow-up, same conversation):** ఇది చిన్న గదికి సరిపోతుందా?

**ASKODOX AI:** సాధారణంగా ఏసీ సర్వీసింగ్ (ఫైమ్ జెట్ ಕ್లీనింగ్) అనేది గది పరిమాణంతో సంబంధం లేకుండా, మీ ఏసీ పనితీరు మరియు చల్లదనాన్ని పెంచడానికి ఉపయోగపడుతుంది. మీ గది చిన్నదైనా (100 చ.అడుగుల లోపు), ఉన్న ఏసీ సరిగ్గా చల్లబరచడానికి మరియు శుభ్రంగా ఉండటానికి ఈ సర్వీస్ సరిపోతుంది. మీరు మీ చిన్న గదికి కొత్త ఏసీ లేదా సర్వీస్ బుక్ చేసుకోవాలనుకుంటున్నారా?

**Next step:** "ac service near me" → SML AC SERVICES / ELECTRICAL WORKS [nearby_external]

## Attribution (branch Command Center)

Video funnel: video_impression 11, video_open 11, video_watch_start 11, video_watch_complete 0, video_ask 11, video_product_click 4, video_service_click 3, video_local_search 4, video_affiliate_click 0, video_contact 0, lead 0, order 0, conversion 0

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
