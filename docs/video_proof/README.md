# Real video content proof

Generated 2026-10-05T18:17:39Z by `.github/workflows/video-real-content-proof.yml` (run 37354334923).

* Video rows: **real**, from production's live web video search (Brave) -- replayed into this branch's pipeline, which adds references, YouTube oEmbed checks (live network), linking and disclosures.
* AI answers: **real**, from the production assistant (`/api/in-app/assistant`) given exactly what the app sends (question + grounding from this branch's explain).
* Next-step options: **real**, from production's discovery for the step's text.
* Service cases: production (main) does not search videos for service needs, so their real video rows come from a product-category source query for the same subject; this branch runs them as service needs.
* YouTube Data API: needs_configuration (no YOUTUBE_API_KEY in this run).

| Case | Lang | Videos | Top video | Channel | Plays in app | Disclosure | AI answer | Follow-up | Next step → options |
|---|---|---|---|---|---|---|---|---|---|
| electronics | en | 1 | [I Bought All 43" TVs / Best 43 Inch TV in Amazon Great Indi…](https://www.youtube.com/watch?v=ddTpAyeDQ4I) | Udrawat | yes (official YouTube embed) | Creator's opinion -- not verified by ASKODOX | yes | yes | samsung 43 inch tv near me → 6 (deals, nearby_external) |
| electronics-te | te | 1 | [I Bought All 43" TVs / Best 43 Inch TV in Amazon Great Indi…](https://www.youtube.com/watch?v=ddTpAyeDQ4I) | Udrawat | yes (official YouTube embed) | Creator's opinion -- not verified by ASKODOX | yes | yes | samsung 43 inch tv offers → 6 (deals, nearby_external) |
| phone | en | 1 | [Redmi Note 13 Pro is here - Let's Check!](https://www.youtube.com/watch?v=kGG04jkdjxY) | Gyan Therapy | yes (official YouTube embed) | Creator's opinion -- not verified by ASKODOX | yes | yes | redmi note 13 pro offers → 6 (deals, nearby_external, surplus, used) |
| vehicle | en | 1 | [New Tata Nexon Pure Plus Diesel Review // Price Mileage Fea…](https://www.youtube.com/watch?v=E8eMNvr5GtM) | Mjk Cars | yes (official YouTube embed) | Creator's opinion -- not verified by ASKODOX | yes | yes | tata nexon near me → 6 (deals, nearby_external, surplus) |
| service | en | 1 | [Urban Company AC Service / Spilit AC Cleaning Advance Foamj…](https://www.youtube.com/watch?v=qPF6hbFHCUc) | KP Vlogs & Review | yes (official YouTube embed) | Creator's opinion -- not verified by ASKODOX | yes | yes | ac service near me → 5 (nearby_external) |
| home-service | en | 1 | [Which do you prefer. Plumbers putty or silicone for sealing…](https://www.youtube.com/watch?v=Ac8Arkhzgps) | My Old Plumber | yes (official YouTube embed) | Creator's opinion -- not verified by ASKODOX | yes | yes | plumbing repair service near me → 5 (nearby_external) |
| food | en | 1 | [₹450 vs ₹800 vs ₹1200 Hyderabadi Biryani In Mumbai!! 🤔](https://www.youtube.com/watch?v=NYNr1X8Qokw) | DCT EATS | yes (official YouTube embed) | Creator's opinion -- not verified by ASKODOX | yes | yes | hyderabadi biryani near me → 6 (deals, nearby_external) |
| travel | en | 1 | [Araku Valley Full Tour / Things to do in Araku Valley / Pla…](https://www.youtube.com/watch?v=rMd5DUP04RE) | Travel Matcha | yes (official YouTube embed) | Creator's opinion -- not verified by ASKODOX | yes | yes | araku valley trip reviews → 6 (deals, nearby_external) |
| used-item | en | 1 | [Royal Enfield Classic 350 (2015) / 10-Year Ownership Review…](https://www.youtube.com/watch?v=RJworx5674I) | The Motographer | yes (official YouTube embed) | Creator's opinion -- not verified by ASKODOX | yes | yes | used royal enfield classic 350 near me → 6 (deals, nearby_external, used) |
| deal | en | 1 | [iPhone 15 / Long Term Review / Best iPhone? / Next Sale Kin…](https://www.youtube.com/watch?v=LtaCjbudjpQ) | CallMeShazzam TECH | yes (official YouTube embed) | Creator's opinion -- not verified by ASKODOX | yes | yes | iphone 15 offers → 6 (deals, nearby_external, surplus, used) |
| service-te | te | 1 | [Urban Company AC Service / Spilit AC Cleaning Advance Foamj…](https://www.youtube.com/watch?v=qPF6hbFHCUc) | KP Vlogs & Review | yes (official YouTube embed) | Creator's opinion -- not verified by ASKODOX | yes | yes | ac service near me → 5 (nearby_external) |

## Conversations (real AI answers)

### electronics (en) -- "Samsung 43 inch TV review videos"

**Video:** I Bought All 43" TVs | Best 43 Inch TV in Amazon Great Indian Festival & Flipkart Big Billion Days -- Udrawat (https://www.youtube.com/watch?v=ddTpAyeDQ4I)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: I Bought All 43" TVs | Best 43 Inch TV in Amazon Great Indian Festival & Flipkart Big Billion Days / 🔥 Best 43-Inch TVs to Buy in 2026! / Flipkart Big Billion Days Sale aur Amazon Great Indian Festival Sale ke time agar aap ek best 43-inch TV buy karne ka plan kar rahe hain, to ye video aapke liye …  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "I Bought All 43" TVs | Best 43 Inch TV in Amazon Great Indian Festival & Flipkart Big Billion Days"

**ASKODOX AI (production):** Sure -- looking for real videos and reviews.

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** Let me check real sellers, shops and online options near you.  
**This branch:** Let me check real sellers, shops and online options near you. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "samsung 43 inch tv near me" → Croma - Benz Circle [nearby_external]; Samsung 43-inch TVs Price List in India (September 2026) [deals]; Shop Samsung 43 Inch TVs Online Best Deals & Prices in India [deals]; Sathya Vijayawada 2, Buy Home and Kitchen Appliances online at the best price with offers | Sathya.store [deals]

### electronics-te (te) -- "శామ్‌సంగ్ 43 అంగుళాల టీవీ రివ్యూ వీడియో"

**Video:** I Bought All 43" TVs | Best 43 Inch TV in Amazon Great Indian Festival & Flipkart Big Billion Days -- Udrawat (https://www.youtube.com/watch?v=ddTpAyeDQ4I)

**ASKODOX explain (branch):** ఈ వీడియోను నేను చూడలేదు/విశ్లేషించలేదు. శీర్షిక, క్రియేటర్ ఇచ్చిన వివరణ, ఛానల్ మాత్రమే తెలుసు.  
Quoted from source: I Bought All 43" TVs | Best 43 Inch TV in Amazon Great Indian Festival & Flipkart Big Billion Days / 🔥 Best 43-Inch TVs to Buy in 2026! / Flipkart Big Billion Days Sale aur Amazon Great Indian Festival Sale ke time agar aap ek best 43-inch TV buy karne ka plan kar rahe hain, to ye video aapke liye …  
Label: Creator's opinion -- not verified by ASKODOX

**User:** "I Bought All 43" TVs | Best 43 Inch TV in Amazon Great Indian Festival & Flipkart Big Billion Days" గురించి చెప్పండి: ధర, దూరం, నాణ్యత, అందుబాటు, రివ్యూలు

**ASKODOX AI (production):** సరే, నిజమైన వీడియోలు, రివ్యూలు వెతుకుతున్నాను.

**User (follow-up, same conversation):** ఇది చిన్న గదికి సరిపోతుందా?

**ASKODOX AI:** చిన్న గదికి 43 అంగుళాల టీవీ సరిపోతుందా లేదా అనేది గది పరిమాణం మరియు చూసే దూరంపై ఆధారపడి ఉంటుంది. సాధారణంగా 43 అంగుళాల టీవీకి 5 నుండి 6 అడుగుల దూరం ఉండటం మంచిది.

**Next step:** "samsung 43 inch tv offers" → Croma - Benz Circle [nearby_external]; Samsung 43-inch TVs Price List in India (September 2026) [deals]; Shop Samsung 43 Inch TVs Online Best Deals & Prices in India [deals]; Sathya Vijayawada 2, Buy Home and Kitchen Appliances online at the best price with offers | Sathya.store [deals]

### phone (en) -- "Redmi Note 13 Pro review video"

**Video:** Redmi Note 13 Pro is here - Let's Check! -- Gyan Therapy (https://www.youtube.com/watch?v=kGG04jkdjxY)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: Redmi Note 13 Pro is here - Let's Check! / Redmi Note 13, Redmi Note 13 Pro and Redmi Note 13 Pro+ launched in India. / Redmi Note 13 Pro comes with Snapdragon 7s Gen 2 Processor, 200MP triple camera with 5100mAh Battery with 67W Charging from Xiaomi. / Here is my Redmi Note 13 Pro Unboxing and Ini…  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "Redmi Note 13 Pro is here - Let's Check!"

**ASKODOX AI (production):** Sure -- looking for real videos and reviews.

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** Let me check real sellers, shops and online options near you.  
**This branch:** Let me check real sellers, shops and online options near you. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "redmi note 13 pro offers" → Happi Mobiles Vijayawada Bandar Road [nearby_external]; Buy Old Used Xiaomi Redmi Note 13 Pro 4G Phones Under ... [used]; Open Box Store [surplus]; Redmi Note 13 5G, Note 13 Pro 5G, Note 13 Pro+ 5G goes on sale on Vijay Sales - Times of India [deals]

### vehicle (en) -- "Tata Nexon review video"

**Video:** New Tata Nexon Pure Plus Diesel Review || Price Mileage Features || Tata Nexon Base Model Price -- Mjk Cars (https://www.youtube.com/watch?v=E8eMNvr5GtM)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: New Tata Nexon Pure Plus Diesel Review || Price Mileage Features || Tata Nexon Base Model Price / 🚗 New Tata Nexon – Complete Details & Review / Is video mein hum dekhenge New Tata Nexon ke design, exterior, interior, features, safety, comfort, performance aur overall look ke baare mein complete de…  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "New Tata Nexon Pure Plus Diesel Review || Price Mileage Features || Tata Nexon Base Model Price"

**ASKODOX AI (production):** Sure -- looking for real videos and reviews.

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** Let me check real sellers, shops and online options near you.  
**This branch:** Let me check real sellers, shops and online options near you. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "tata nexon near me" → Tata Motors Commercial Vehicle Dealer - Sahni Auto Private Limited [nearby_external]; Tata Nexon On Road Price in Vijayawada (2026) – ₹8.63 lakh Onwards | Autocar India [surplus]; Tata Nexon price in Vijayawada | Tata Nexon on road Price 2026 | Times Drive [deals]; Tata Nexon Price in Vijayawada-August 2026 Nexon On Road Price [deals]

### service (en) -- "AC service video"

**Video:** Urban Company AC Service | Spilit AC Cleaning Advance Foamjet Technology | AC Cleaning Service | -- KP Vlogs & Review (https://www.youtube.com/watch?v=qPF6hbFHCUc)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: Urban Company AC Service | Spilit AC Cleaning Advance Foamjet Technology | AC Cleaning Service | / #urbancompany #acservice #airconditioner #urbanclap #splitacservice #acservice2025 #summeracservice #kpvlogsandreview #honestreview #affordableservice #watchbeforehire #newtechnology #shortsyoutube #y…  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "Urban Company AC Service | Spilit AC Cleaning Advance Foamjet Technology | AC Cleaning Service |"

**ASKODOX AI (production):** Sure -- looking for real videos and reviews.

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** Let me check real sellers, shops and online options near you.  
**This branch:** Let me check real sellers, shops and online options near you. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "ac service near me" → SML AC SERVICES / ELECTRICAL WORKS [nearby_external]; Professional AC service & repair experts in Vijayawada, India [online]; Split AC Services in Vijayawada [online]; Top AC Service in Vijayawada, Best AC Repair Service in Vijayawada | Sulekha Vijayawada [online]

### home-service (en) -- "kitchen sink plumbing repair video"

**Video:** Which do you prefer. Plumbers putty or silicone for sealing drains. #shorts #plumbing #diy -- My Old Plumber (https://www.youtube.com/watch?v=Ac8Arkhzgps)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: Which do you prefer. Plumbers putty or silicone for sealing drains. #shorts #plumbing #diy / Which do you prefer for sealing drains — plumbers putty or silicone? / Some plumbers swear by putty. / Others prefer silicone for a stronger long-term seal. / Both have their place depending on the sink, dr…  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "Which do you prefer. Plumbers putty or silicone for sealing drains. #shorts #plumbing #diy"

**ASKODOX AI (production):** Sure -- looking for real videos and reviews.

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** Let me check real sellers, shops and online options near you.  
**This branch:** Let me check real sellers, shops and online options near you. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "plumbing repair service near me" → Amulya Plumbing & Sanitary Services [nearby_external]; Book Plumber Repair Service Vijayawada Service On Wheel:Ph-8237611222 / 8087911222 [online]; Plumbing services near me in Vijayawada [online]; Plumber in India | Book Trusted Plumbing Services at Home | Urban Company [online]

### food (en) -- "Hyderabadi biryani review video"

**Video:** ₹450 vs ₹800 vs ₹1200 Hyderabadi Biryani In Mumbai!! 🤔 -- DCT EATS (https://www.youtube.com/watch?v=NYNr1X8Qokw)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: ₹450 vs ₹800 vs ₹1200 Hyderabadi Biryani In Mumbai!! 🤔 / Can we find authentic Hyderabadi mutton biryani in Mumbai? / Sahil from Headbanger Eats and I ordered three versions from different restaurants to compare what we get at three very different price points. / First up was Bikkgane Biryani, foll…  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "₹450 vs ₹800 vs ₹1200 Hyderabadi Biryani In Mumbai!! 🤔"

**ASKODOX AI (production):** Sure -- looking for real videos and reviews.

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** Let me check real sellers, shops and online options near you.  
**This branch:** Let me check real sellers, shops and online options near you. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "hyderabadi biryani near me" → The Kazus Royal Dum Biryani [nearby_external]; Best Hyderabadi Biryani Restaurants In Vijayawada 2025 | Order Online [deals]; Buy Haldiram's Hyderabadi Biryani Online at Best Price of Rs 100 - bigbasket [online]; Order Online – HYDERABAD BIRYANI POINT [online]

### travel (en) -- "Araku valley trip review video"

**Video:** Araku Valley Full Tour | Things to do in Araku Valley | Places to Visit in Araku -- Travel Matcha (https://www.youtube.com/watch?v=rMd5DUP04RE)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: Araku Valley Full Tour | Things to do in Araku Valley | Places to Visit in Araku / in This video we are giving out a full itinerary for Araku Valley, / Araku Valley is Andhra Pradesh’s Hidden Gem! / Imagine waking up to mist-covered hills, walking through lush coffee plantations, exploring ancient …  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "Araku Valley Full Tour | Things to do in Araku Valley | Places to Visit in Araku"

**ASKODOX AI (production):** Sure -- looking for real videos and reviews.

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** Let me check real sellers, shops and online options near you.  
**This branch:** Let me check real sellers, shops and online options near you. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "araku valley trip reviews" → Akkanna Madanna Caves [nearby_external]; Araku Valley Tour Packages From Vijayawada – Vijayawada To Araku Valley Packages | TT [deals]; 5 Araku Valley Tour Packages at ₹6785 pp - Book Online with 20% Off [deals]; Araku Valley Tour Packages from Vijayawada | Araku Valley Packages from Vijayawada | Araku Valley Honeymoon Packages from Vijayawada | Araku Valley Holiday Pack [deals]

### used-item (en) -- "used Royal Enfield Classic 350 review video"

**Video:** Royal Enfield Classic 350 (2015) | 10-Year Ownership Review #bike #royalenfield #classic350 -- The Motographer  (https://www.youtube.com/watch?v=RJworx5674I)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: Royal Enfield Classic 350 (2015) | 10-Year Ownership Review #bike #royalenfield #classic350 / Welcome to *TheMotographer* — where every ride becomes a cinematic story. / I’m a rider, creator, and reviewer who captures the soul of motorcycles. / 📍 Based in Lucknow, India | Motorcycle • Cinematic • E…  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "Royal Enfield Classic 350 (2015) | 10-Year Ownership Review #bike #royalenfield #classic350"

**ASKODOX AI (production):** Sure -- looking for real videos and reviews.

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** Let me check real sellers, shops and online options near you.  
**This branch:** Let me check real sellers, shops and online options near you. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "used royal enfield classic 350 near me" → TARAK BULLET HOUSE [nearby_external]; 13 Used Royal Enfield Classic in Vijayawada. Buy from Owners and Dealers - Bikes4Sale [used]; Royal Enfield Classic 350 Price in Vijayawada-March 2026 Classic 350 On Road Price [deals]; Royal Enfield Classic 350 On Road Price In Vijayawada - 2026 Price Breakup & Offers [deals]

### deal (en) -- "iPhone 15 offer review video"

**Video:** iPhone 15 | Long Term Review | Best iPhone? | Next Sale King? | Malayalam with Eng Sub -- CallMeShazzam TECH (https://www.youtube.com/watch?v=LtaCjbudjpQ)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: iPhone 15 | Long Term Review | Best iPhone? | Next Sale King? | Malayalam with Eng Sub / Thumbnail by / https://www.instagram.com/laetitia.creatives/ / ndependently owned creative agency / Crafting transformative brands  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "iPhone 15 | Long Term Review | Best iPhone? | Next Sale King? | Malayalam with Eng Sub"

**ASKODOX AI (production):** Sure -- looking for real videos and reviews.

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

**ASKODOX AI (production):** సరే, నిజమైన వీడియోలు, రివ్యూలు వెతుకుతున్నాను.

**User (follow-up, same conversation):** ఇది చిన్న గదికి సరిపోతుందా?

**ASKODOX AI:** చిన్న గదికి ఇది సరిపోతుందో లేదో చూడటానికి మీ AC సామర్థ్యం (టన్నుల కొలత) ఎంతో చెప్తారా?

**Next step:** "ac service near me" → SML AC SERVICES / ELECTRICAL WORKS [nearby_external]; Professional AC service & repair experts in Vijayawada, India [online]; Split AC Services in Vijayawada [online]; Top AC Service in Vijayawada, Best AC Repair Service in Vijayawada | Sulekha Vijayawada [online]

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
