# Real video content proof

Generated 2026-10-08T09:01:53Z by `.github/workflows/video-real-content-proof.yml` (run 37753368380).

* Video rows: **real**, from production's live web video search (Brave) -- replayed into this branch's pipeline, which adds references, YouTube oEmbed checks (live network), linking and disclosures.
* AI answers: **real**, from the production assistant (`/api/in-app/assistant`) given exactly what the app sends (question + grounding from this branch's explain).
* Next-step options: **real**, from production's discovery for the step's text.
* Service cases: production (main) does not search videos for service needs, so their real video rows come from a product-category source query for the same subject; this branch runs them as service needs.
* YouTube Data API: needs_configuration (no YOUTUBE_API_KEY in this run).

| Case | Lang | Videos | Top video | Channel | Plays in app | Disclosure | AI answer | Follow-up | Next step → options |
|---|---|---|---|---|---|---|---|---|---|
| electronics | en | 1 | [Best 43 Inch TV 2026 ⚡ Best Smart TV 43 Inch 2026 ⚡Flipkart…](https://www.youtube.com/watch?v=yDD-7v3U8Ig) | Dealfixkaro | yes (official YouTube embed) | Creator's opinion -- not verified by ASKODOX | yes | yes | samsung 43 inch tv near me → 6 (deals, nearby_external) |
| electronics-te | te | 1 | [Best 43 Inch TV 2026 ⚡ Best Smart TV 43 Inch 2026 ⚡Flipkart…](https://www.youtube.com/watch?v=yDD-7v3U8Ig) | Dealfixkaro | yes (official YouTube embed) | Creator's opinion -- not verified by ASKODOX | yes | yes | samsung 43 inch tv offers → 6 (deals, nearby_external) |
| phone | en | 1 | [Redmi Note 13 Pro is here - Let's Check!](https://www.youtube.com/watch?v=kGG04jkdjxY) | Gyan Therapy | yes (official YouTube embed) | Creator's opinion -- not verified by ASKODOX | yes | yes | redmi note 13 pro offers → 6 (deals, nearby_external, surplus, used) |
| vehicle | en | 1 | [Tata Nexon Cons: What You Need to Know Before Buying](https://www.youtube.com/watch?v=77aOlpHhpOw) | TheAutoBharat | yes (official YouTube embed) | Creator's opinion -- not verified by ASKODOX | yes | yes | tata nexon near me → 6 (deals, nearby_external, surplus) |
| service | en | 1 | [Urban Company AC Service / Spilit AC Cleaning Advance Foamj…](https://www.youtube.com/watch?v=qPF6hbFHCUc) | KP Vlogs & Review | yes (official YouTube embed) | Creator's opinion -- not verified by ASKODOX | yes | yes | ac service near me → 5 (nearby_external) |
| home-service | en | 1 | [Great Plumbing Trick To Fix Pvc Pipe Joint #shortvideo #sho…](https://www.youtube.com/watch?v=Bvxkrv7t4Dw) | vijay xyz tricks | yes (official YouTube embed) | Creator's opinion -- not verified by ASKODOX | yes | yes | plumbing repair service near me → 5 (nearby_external) |
| food | en | 1 | [₹450 vs ₹800 vs ₹1200 Hyderabadi Biryani In Mumbai!! 🤔](https://www.youtube.com/watch?v=NYNr1X8Qokw) | DCT EATS | yes (official YouTube embed) | Creator's opinion -- not verified by ASKODOX | yes | yes | hyderabadi biryani near me → 6 (deals, nearby_external) |
| travel | en | 1 | [Araku Valley Full Tour / Things to do in Araku Valley / Pla…](https://www.youtube.com/watch?v=rMd5DUP04RE) | Travel Matcha | yes (official YouTube embed) | Creator's opinion -- not verified by ASKODOX | yes | yes | araku valley trip reviews → 6 (deals, nearby_external) |
| used-item | en | 1 | [Used Royal Enfield Classic 350🏍️ – Best Deals in Gobichetti…](https://www.youtube.com/watch?v=ilhNFpIoY70) | Engine Thagaval | yes (official YouTube embed) | Creator's opinion -- not verified by ASKODOX | yes | yes | used royal enfield classic 350 near me → 6 (deals, nearby_external, used) |
| deal | en | 1 | [iPhone 15 / Long Term Review / Best iPhone? / Next Sale Kin…](https://www.youtube.com/watch?v=LtaCjbudjpQ) | CallMeShazzam TECH | yes (official YouTube embed) | Creator's opinion -- not verified by ASKODOX | yes | yes | iphone 15 offers → 6 (deals, nearby_external, surplus, used) |
| service-te | te | 1 | [Urban Company AC Service / Spilit AC Cleaning Advance Foamj…](https://www.youtube.com/watch?v=qPF6hbFHCUc) | KP Vlogs & Review | yes (official YouTube embed) | Creator's opinion -- not verified by ASKODOX | no (fallback) | yes | ac service near me → 5 (nearby_external) |

## Conversations (real AI answers)

### electronics (en) -- "Samsung 43 inch TV review videos"

**Video:** Best 43 Inch TV 2026 ⚡ Best Smart TV 43 Inch 2026 ⚡Flipkart & Amazon TV Deals -- Dealfixkaro (https://www.youtube.com/watch?v=yDD-7v3U8Ig)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: Best 43 Inch TV 2026 ⚡ Best Smart TV 43 Inch 2026 ⚡Flipkart & Amazon TV Deals / Best 43 Inch TV 2026 ⚡ Best Smart TV 43 Inch 2026 ⚡Flipkart & Amazon TV Deals / Looking for the Best 43 Inch TV in 2026? / In this video, I have covered some of the best 43 inch Smart TVs 2026 that you can consider duri…  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "Best 43 Inch TV 2026 ⚡ Best Smart TV 43 Inch 2026 ⚡Flipkart & Amazon TV Deals"

**ASKODOX AI (production):** This video by Dealfixkaro covers top 43-inch Smart TV options available during major sales on Flipkart and Amazon. Please note that these are the creator's opinions and are not verified by ASKODOX. Specific details such as price, ratings, and stock are not provided by the source.

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** Let me check real sellers, shops and online options near you.  
**This branch:** Let me check real sellers, shops and online options near you. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "samsung 43 inch tv near me" → Croma - Benz Circle [nearby_external]; Samsung 43-inch TVs Price List in India (October 2026) [deals]; Shop Samsung 43 Inch TVs Online Best Deals & Prices in India [deals]; Samsung 43 Inch Smart Tv - Buy Samsung 43 Inch Smart Tv online at Best Prices in India | Flipkart.com [deals]

### electronics-te (te) -- "శామ్‌సంగ్ 43 అంగుళాల టీవీ రివ్యూ వీడియో"

**Video:** Best 43 Inch TV 2026 ⚡ Best Smart TV 43 Inch 2026 ⚡Flipkart & Amazon TV Deals -- Dealfixkaro (https://www.youtube.com/watch?v=yDD-7v3U8Ig)

**ASKODOX explain (branch):** ఈ వీడియోను నేను చూడలేదు/విశ్లేషించలేదు. శీర్షిక, క్రియేటర్ ఇచ్చిన వివరణ, ఛానల్ మాత్రమే తెలుసు.  
Quoted from source: Best 43 Inch TV 2026 ⚡ Best Smart TV 43 Inch 2026 ⚡Flipkart & Amazon TV Deals / Best 43 Inch TV 2026 ⚡ Best Smart TV 43 Inch 2026 ⚡Flipkart & Amazon TV Deals / Looking for the Best 43 Inch TV in 2026? / In this video, I have covered some of the best 43 inch Smart TVs 2026 that you can consider duri…  
Label: Creator's opinion -- not verified by ASKODOX

**User:** "Best 43 Inch TV 2026 ⚡ Best Smart TV 43 Inch 2026 ⚡Flipkart & Amazon TV Deals" గురించి చెప్పండి: ధర, దూరం, నాణ్యత, అందుబాటు, రివ్యూలు

**ASKODOX AI (production):** ఈ వీడియో 43 అంగుళాల స్మార్ట్ టీవీ ఆఫర్లు మరియు సేల్స్ గురించి Dealfixkaro యొక్క స్వంత అభిప్రాయాలను కవర్ చేస్తుంది (ఇది ASKODOX ద్వారా ధృవీకరించబడలేదు). అయితే, ఈ వీడియో ఆధారంగా ధర, దూరం, నాణ్యత, అందుబాటు మరియు రివ్యూలకు సంబంధించిన వివరాలు (Not verified) అందుబాటులో లేవు.

**User (follow-up, same conversation):** ఇది చిన్న గదికి సరిపోతుందా?

**ASKODOX AI:** 43 అంగుళాల టీవీకి కనీసం 5 నుండి 6 అడుగుల వీక్షణ దూరం ఉండాలి. మీ గది చిన్నదైతే, చూసేటప్పుడు కళ్ళపై ఒత్తిడి పడకుండా ఉండటానికి ఈ దూరం సరిపోతుందో లేదో సరిచూసుకోండి.

**Next step:** "samsung 43 inch tv offers" → Croma - Benz Circle [nearby_external]; Samsung 43-inch TVs Price List in India (October 2026) [deals]; Shop Samsung 43 Inch TVs Online Best Deals & Prices in India [deals]; Samsung 43 Inch Smart Tv - Buy Samsung 43 Inch Smart Tv online at Best Prices in India | Flipkart.com [deals]

### phone (en) -- "Redmi Note 13 Pro review video"

**Video:** Redmi Note 13 Pro is here - Let's Check! -- Gyan Therapy (https://www.youtube.com/watch?v=kGG04jkdjxY)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: Redmi Note 13 Pro is here - Let's Check! / Redmi Note 13, Redmi Note 13 Pro and Redmi Note 13 Pro+ launched in India. / Redmi Note 13 Pro comes with Snapdragon 7s Gen 2 Processor, 200MP triple camera with 5100mAh Battery with 67W Charging from Xiaomi. / Here is my Redmi Note 13 Pro Unboxing and Ini…  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "Redmi Note 13 Pro is here - Let's Check!"

**ASKODOX AI (production):** This video by Gyan Therapy is an unboxing and initial impressions look at the Redmi Note 13 Pro. Based on the video description, it highlights features such as the Snapdragon 7s Gen 2 Processor, a 200MP triple camera setup, and a 5100mAh battery with 67W fast charging. Please note that these are the creator's opinions and details from their description, which are not verified by ASKODOX. Specific details like price, stock availability, and user ratings were not provided by the source.

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** Let me check real sellers, shops and online options near you.  
**This branch:** Let me check real sellers, shops and online options near you. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "redmi note 13 pro offers" → Happi Mobiles Vijayawada Bandar Road [nearby_external]; Buy Old Used Xiaomi Redmi Note 13 Pro 4G Phones Under ... [used]; Open Box Store [surplus]; Redmi Note 13 5G, Note 13 Pro 5G, Note 13 Pro+ 5G goes on sale on Vijay Sales - Times of India [deals]

### vehicle (en) -- "Tata Nexon review video"

**Video:** Tata Nexon Cons: What You Need to Know Before Buying -- TheAutoBharat (https://www.youtube.com/watch?v=77aOlpHhpOw)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: Tata Nexon Cons: What You Need to Know Before Buying / Tata Nexon Cons: What You Need to Know Before Buying / Tata Nexon Cons / Thinking of buying the Tata Nexon? / Before you make a decision, it's important to know the potential drawbacks of this popular compact SUV.  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "Tata Nexon Cons: What You Need to Know Before Buying"

**ASKODOX AI (production):** This video from creator TheAutoBharat is titled 'Tata Nexon Cons: What You Need to Know Before Buying' and discusses potential drawbacks to consider before buying the compact SUV. Please note that this reflects the creator's opinion and is not verified by ASKODOX. Specific details like price, rating, and stock availability are not provided by the source.

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

**ASKODOX AI (production):** This video is titled 'Urban Company AC Service | Spilit AC Cleaning Advance Foamjet Technology | AC Cleaning Service |' created by KP Vlogs & Review. Please note that the content reflects the creator's opinion and is not verified by ASKODOX. Specific details such as price, rating, and customer reviews are not provided by the source.

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** Let me check real sellers, shops and online options near you.  
**This branch:** Let me check real sellers, shops and online options near you. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "ac service near me" → SML AC SERVICES / ELECTRICAL WORKS [nearby_external]; Professional AC service & repair experts in Vijayawada, India [online]; Split AC Services in Vijayawada [online]; ️ AC Repair Services in Vijayawada [online]

### home-service (en) -- "kitchen sink plumbing repair video"

**Video:** Great Plumbing Trick To Fix Pvc Pipe Joint #shortvideo #shorts #shortsfeed -- vijay xyz tricks  (https://www.youtube.com/watch?v=Bvxkrv7t4Dw)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: Great Plumbing Trick To Fix Pvc Pipe Joint #shortvideo #shorts #shortsfeed / Great Plumbing Trick To Fix Pvc Pipe Joint #shortvideo #shorts #shortsfeed / thanks for watching video  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "Great Plumbing Trick To Fix Pvc Pipe Joint #shortvideo #shorts #shortsfeed"

**ASKODOX AI (production):** This video titled 'Great Plumbing Trick To Fix Pvc Pipe Joint' is from the creator 'vijay xyz tricks' (this is the creator's opinion, not verified by ASKODOX). Specific details such as price, stock, or ratings are not provided. Since the video content has not been analyzed, I cannot verify the exact steps or results shown.

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** Let me check real sellers, shops and online options near you.  
**This branch:** Let me check real sellers, shops and online options near you. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "plumbing repair service near me" → Amulya Plumbing & Sanitary Services [nearby_external]; Expert Plumbers in Vijaywada | Reliable & Affordable [online]; Plumber in India | Book Trusted Plumbing Services at Home | Urban Company [online]; Plumbers @7065012902 Vijayawada - Mannubhai.com [online]

### food (en) -- "Hyderabadi biryani review video"

**Video:** ₹450 vs ₹800 vs ₹1200 Hyderabadi Biryani In Mumbai!! 🤔 -- DCT EATS (https://www.youtube.com/watch?v=NYNr1X8Qokw)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: ₹450 vs ₹800 vs ₹1200 Hyderabadi Biryani In Mumbai!! 🤔 / Can we find authentic Hyderabadi mutton biryani in Mumbai? / Sahil from Headbanger Eats and I ordered three versions from different restaurants to compare what we get at three very different price points. / First up was Bikkgane Biryani, foll…  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "₹450 vs ₹800 vs ₹1200 Hyderabadi Biryani In Mumbai!! 🤔"

**ASKODOX AI (production):** This video by creator DCT EATS compares authentic Hyderabadi mutton biryani in Mumbai across three price tiers: ₹450, ₹800, and ₹1200. In the video, the host is joined by Sahil from Headbanger Eats to compare orders from three restaurants: Bikkgane Biryani, Biryani By Kilo, and Lit. Please note that specific ratings, reviews, and detailed price breakdowns are not provided by the source, and creator opinions are not verified by ASKODOX.

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** Let me check real sellers, shops and online options near you.  
**This branch:** Let me check real sellers, shops and online options near you. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "hyderabadi biryani near me" → The Kazus Royal Dum Biryani [nearby_external]; Best Hyderabadi Biryani Restaurants In Vijayawada 2025 | Order Online [deals]; Order Online – HYDERABAD BIRYANI POINT [online]; Buy Haldiram's Hyderabadi Biryani Online at Best Price of Rs 100 - bigbasket [online]

### travel (en) -- "Araku valley trip review video"

**Video:** Araku Valley Full Tour | Things to do in Araku Valley | Places to Visit in Araku -- Travel Matcha (https://www.youtube.com/watch?v=rMd5DUP04RE)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: Araku Valley Full Tour | Things to do in Araku Valley | Places to Visit in Araku / in This video we are giving out a full itinerary for Araku Valley, / Araku Valley is Andhra Pradesh’s Hidden Gem! / Imagine waking up to mist-covered hills, walking through lush coffee plantations, exploring ancient …  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "Araku Valley Full Tour | Things to do in Araku Valley | Places to Visit in Araku"

**ASKODOX AI (production):** According to Travel Matcha's video description, it provides a full tour itinerary for Araku Valley, covering key places to visit, things to do, coffee plantations, and ancient caves. Please note that this is the creator's opinion and not verified by ASKODOX. Additional details such as full ratings or reviews are not provided by the source.

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** Let me check real sellers, shops and online options near you. What specific type of trip or package are you looking for, and what is your budget?  
**This branch:** Let me check real sellers, shops and online options near you. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "araku valley trip reviews" → Akkanna Madanna Caves [nearby_external]; Araku Valley Tour Packages From Vijayawada – Vijayawada To Araku Valley Packages | TT [deals]; 5 Araku Valley Tour Packages at ₹6785 pp - Book Online with 20% Off [deals]; Araku Valley Tour Packages from Vijayawada | Araku Valley Packages from Vijayawada | Araku Valley Honeymoon Packages from Vijayawada | Araku Valley Holiday Pack [deals]

### used-item (en) -- "used Royal Enfield Classic 350 review video"

**Video:** Used Royal Enfield Classic 350🏍️ – Best Deals in Gobichettipalayam | Engine Thagaval #royalenfield -- Engine Thagaval  (https://www.youtube.com/watch?v=ilhNFpIoY70)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: Used Royal Enfield Classic 350🏍️ – Best Deals in Gobichettipalayam | Engine Thagaval #royalenfield / Royal Enfield Classic 350 – FOR SALE! / Single-owner / well-maintained condition. / Classic Royal Enfield design with smooth BS6 engine—perfect for city rides and highway cruising. / 📍 Location: /12…  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "Used Royal Enfield Classic 350🏍️ – Best Deals in Gobichettipalayam | Engine Thagaval #royalenfield"

**ASKODOX AI (production):** Based on the video details provided by Engine Thagaval (creator's opinion, not verified by ASKODOX), this is a single-owner, well-maintained Royal Enfield Classic 350 with a smooth BS6 engine, located at Sathy Athani Main Road, Gobichettipalayam, Tamil Nadu. Details such as price, mileage, exact year, and current availability are not provided in the listing.

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

**ASKODOX AI (production):** This video is a long-term review of the iPhone 15 by CallMeShazzam TECH, presented in Malayalam with English subtitles. Please note that the contents reflect the creator's opinion and are not verified by ASKODOX. Specific details like price, rating, and specs for this video are not provided.

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

**ASKODOX AI (production):** 

**User (follow-up, same conversation):** ఇది చిన్న గదికి సరిపోతుందా?

**ASKODOX AI:** ఆన్‌లైన్ ఆప్షన్ల వివరాల ప్రకారం గది పరిమాణానికి సంబంధించిన సమాచారం 'Not verified'. సాధారణంగా 1 టన్ను ఏసీ 100-120 చదరపు అడుగుల చిన్న గదికి సరిపోతుంది.

**Next step:** "ac service near me" → SML AC SERVICES / ELECTRICAL WORKS [nearby_external]; Professional AC service & repair experts in Vijayawada, India [online]; Split AC Services in Vijayawada [online]; ️ AC Repair Services in Vijayawada [online]

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
