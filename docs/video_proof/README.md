# Real video content proof

Generated 2026-10-06T16:51:37Z by `.github/workflows/video-real-content-proof.yml` (run 37498522040).

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
| vehicle | en | 1 | [Tata Nexon Top Model Fearless Plus PS 2026 ❣️/ NEXON Top Mo…](https://www.youtube.com/watch?v=KjJanS7xNAI) | Sunil Autocar | yes (official YouTube embed) | Creator's opinion -- not verified by ASKODOX | yes | yes | tata nexon near me → 6 (deals, nearby_external, surplus) |
| service | en | 1 | [Urban Company AC Service / Spilit AC Cleaning Advance Foamj…](https://www.youtube.com/watch?v=qPF6hbFHCUc) | KP Vlogs & Review | yes (official YouTube embed) | Creator's opinion -- not verified by ASKODOX | yes | yes | ac service near me → 5 (nearby_external) |
| home-service | en | 1 | [Great Plumbing Trick To Fix Pvc Pipe Joint #shortvideo #sho…](https://www.youtube.com/watch?v=Bvxkrv7t4Dw) | vijay xyz tricks | yes (official YouTube embed) | Creator's opinion -- not verified by ASKODOX | yes | yes | plumbing repair service near me → 5 (nearby_external) |
| food | en | 1 | [₹450 vs ₹800 vs ₹1200 Hyderabadi Biryani In Mumbai!! 🤔](https://www.youtube.com/watch?v=NYNr1X8Qokw) | DCT EATS | yes (official YouTube embed) | Creator's opinion -- not verified by ASKODOX | yes | yes | hyderabadi biryani near me → 6 (deals, nearby_external) |
| travel | en | 1 | [Top 10 Places in Araku Valley 🌴🌊❤✨ #araku](https://www.youtube.com/watch?v=IaaAlzSxqwA) | Ramya Random Tales | yes (official YouTube embed) | Creator's opinion -- not verified by ASKODOX | yes | yes | araku valley trip reviews → 6 (deals, nearby_external) |
| used-item | en | 1 | [How To Check & Buy Used Classic 350 - How To Buy 2nd Hand R…](https://www.youtube.com/watch?v=GW-rCk-eAoU) | Bindass Singh | yes (official YouTube embed) | Creator's opinion -- not verified by ASKODOX | yes | yes | used royal enfield classic 350 near me → 6 (deals, nearby_external, used) |
| deal | en | 1 | [iPhone 15 / Long Term Review / Best iPhone? / Next Sale Kin…](https://www.youtube.com/watch?v=LtaCjbudjpQ) | CallMeShazzam TECH | yes (official YouTube embed) | Creator's opinion -- not verified by ASKODOX | yes | yes | iphone 15 offers → 6 (deals, nearby_external, surplus, used) |
| service-te | te | 1 | [Urban Company AC Service / Spilit AC Cleaning Advance Foamj…](https://www.youtube.com/watch?v=qPF6hbFHCUc) | KP Vlogs & Review | yes (official YouTube embed) | Creator's opinion -- not verified by ASKODOX | yes | yes | ac service near me → 5 (nearby_external) |

## Conversations (real AI answers)

### electronics (en) -- "Samsung 43 inch TV review videos"

**Video:** I Bought All 43" TVs | Best 43 Inch TV in Amazon Great Indian Festival & Flipkart Big Billion Days -- Udrawat (https://www.youtube.com/watch?v=ddTpAyeDQ4I)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: I Bought All 43" TVs | Best 43 Inch TV in Amazon Great Indian Festival & Flipkart Big Billion Days / 🔥 Best 43-Inch TVs to Buy in 2026! / Flipkart Big Billion Days Sale aur Amazon Great Indian Festival Sale ke time agar aap ek best 43-inch TV buy karne ka plan kar rahe hain, to ye video aapke liye …  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "I Bought All 43" TVs | Best 43 Inch TV in Amazon Great Indian Festival & Flipkart Big Billion Days"

**ASKODOX AI (production):** This video by creator Udrawat covers recommendations for the best 43-inch TVs across different budget ranges during the Amazon Great Indian Festival and Flipkart Big Billion Days sales. Please note, these are creator opinions and are Not verified by ASKODOX. Specific details like pricing, ratings, or exact TV specs are not provided by the source.

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** Let me check real sellers, shops and online options near you.  
**This branch:** Let me check real sellers, shops and online options near you. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "samsung 43 inch tv near me" → Croma - Benz Circle [nearby_external]; Samsung 43-inch TVs Price List in India (September 2026) [deals]; Shop Samsung 43 Inch TVs Online Best Deals & Prices in India [deals]; Samsung 43 Inch Smart Tv - Buy Samsung 43 Inch Smart Tv online at Best Prices in India | Flipkart.com [online]

### electronics-te (te) -- "శామ్‌సంగ్ 43 అంగుళాల టీవీ రివ్యూ వీడియో"

**Video:** I Bought All 43" TVs | Best 43 Inch TV in Amazon Great Indian Festival & Flipkart Big Billion Days -- Udrawat (https://www.youtube.com/watch?v=ddTpAyeDQ4I)

**ASKODOX explain (branch):** ఈ వీడియోను నేను చూడలేదు/విశ్లేషించలేదు. శీర్షిక, క్రియేటర్ ఇచ్చిన వివరణ, ఛానల్ మాత్రమే తెలుసు.  
Quoted from source: I Bought All 43" TVs | Best 43 Inch TV in Amazon Great Indian Festival & Flipkart Big Billion Days / 🔥 Best 43-Inch TVs to Buy in 2026! / Flipkart Big Billion Days Sale aur Amazon Great Indian Festival Sale ke time agar aap ek best 43-inch TV buy karne ka plan kar rahe hain, to ye video aapke liye …  
Label: Creator's opinion -- not verified by ASKODOX

**User:** "I Bought All 43" TVs | Best 43 Inch TV in Amazon Great Indian Festival & Flipkart Big Billion Days" గురించి చెప్పండి: ధర, దూరం, నాణ్యత, అందుబాటు, రివ్యూలు

**ASKODOX AI (production):** ఈ వీడియో 'I Bought All 43" TVs | Best 43 Inch TV in Amazon Great Indian Festival & Flipkart Big Billion Days' గురించి వివరాలు: దీని క్రియేటర్ Udrawat. అందులో ఉన్న విషయాలు వారి సొంత అభిప్రాయాలు మాత్రమే, ASKODOX ద్వారా ధృవీకరించబడలేదు. లభ్యమైన సమాచారం: • ధర: అందించబడలేదు (Not verified) • దూరం: అందించబడలేదు (Not verified) • నాణ్యత / క్వాలిటీ: అందించబడలేదు (Not verified) • అందుబాటు (Stock): అందించబడలేదు (Not verified) • రివ్యూలు / రేటింగ్: అందించబడలేదు (Not verified)

**User (follow-up, same conversation):** ఇది చిన్న గదికి సరిపోతుందా?

**ASKODOX AI:** చిన్న గదికి 43 అంగుళాల టీవీ సాధారణంగా కాస్త పెద్దదిగా అనిపించవచ్చు. సాధారణంగా చిన్న గదులకు 32 అంగుళాల టీవీ సరిపోతుంది, కానీ చూడటానికి కనీసం 5 నుండి 6 అడుగుల దూరం ఉంటే ఇది కూడా అనుకూలంగా ఉంటుంది.

**Next step:** "samsung 43 inch tv offers" → Croma - Benz Circle [nearby_external]; Samsung 43-inch TVs Price List in India (September 2026) [deals]; Shop Samsung 43 Inch TVs Online Best Deals & Prices in India [deals]; Samsung 43 Inch Smart Tv - Buy Samsung 43 Inch Smart Tv online at Best Prices in India | Flipkart.com [online]

### phone (en) -- "Redmi Note 13 Pro review video"

**Video:** Redmi Note 13 Pro is here - Let's Check! -- Gyan Therapy (https://www.youtube.com/watch?v=kGG04jkdjxY)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: Redmi Note 13 Pro is here - Let's Check! / Redmi Note 13, Redmi Note 13 Pro and Redmi Note 13 Pro+ launched in India. / Redmi Note 13 Pro comes with Snapdragon 7s Gen 2 Processor, 200MP triple camera with 5100mAh Battery with 67W Charging from Xiaomi. / Here is my Redmi Note 13 Pro Unboxing and Ini…  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "Redmi Note 13 Pro is here - Let's Check!"

**ASKODOX AI (production):** According to the video details from Gyan Therapy, 'Redmi Note 13 Pro is here - Let's Check!' is an unboxing and initial impression video. It highlights that the phone features a Snapdragon 7s Gen 2 processor, a 200MP triple camera, and a 5100mAh battery with 67W fast charging. Please note, these details reflect the creator's opinion and are not verified by ASKODOX. Information regarding price, ratings, distance, and stock availability was not provided by the source.

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** Let me check real sellers, shops and online options near you.  
**This branch:** Let me check real sellers, shops and online options near you. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "redmi note 13 pro offers" → Happi Mobiles Vijayawada Bandar Road [nearby_external]; Buy Old Used Xiaomi Redmi Note 13 Pro 4G Phones Under ... [used]; Open Box Store [surplus]; Redmi Note 13 5G, Note 13 Pro 5G, Note 13 Pro+ 5G goes on sale on Vijay Sales - Times of India [deals]

### vehicle (en) -- "Tata Nexon review video"

**Video:** Tata Nexon Top Model Fearless Plus PS 2026 ❣️| NEXON Top Model Detailed Review 💪| -- Sunil Autocar (https://www.youtube.com/watch?v=KjJanS7xNAI)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: Tata Nexon Top Model Fearless Plus PS 2026 ❣️| NEXON Top Model Detailed Review 💪| / Tata Nexon Top Model Fearless Plus PS 2026 ❣️| NEXON Top Model Detailed Review 💪| / All New Tata Nexon Apne Segment ki behtreen Features Loaded Suv Car hai Is Video me Tata Nexon ke Top Model Fearless Plus Ps ka Rev…  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "Tata Nexon Top Model Fearless Plus PS 2026 ❣️| NEXON Top Model Detailed Review 💪|"

**ASKODOX AI (production):** This video by Sunil Autocar features a detailed review of the Tata Nexon Top Model Fearless Plus PS (2026), highlighting its interior, exterior, and segment-loaded features. Please note that these are the creator's opinions and are not verified by ASKODOX. Specific details like price, stock availability, and ratings are not provided by the source.

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

**ASKODOX AI (production):** This video is by KP Vlogs & Review, representing the creator's personal opinion which is not verified by ASKODOX. Details such as price, ratings, distance, and availability were not provided by the source.

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

**ASKODOX AI (production):** This video is by 'vijay xyz tricks' with the title 'Great Plumbing Trick To Fix Pvc Pipe Joint #shortvideo #shorts #shortsfeed'. Please note that the contents or opinions in the video are the creator's opinion and not verified by ASKODOX. Details like price, rating, reviews, stock, and distance are not provided.

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

**ASKODOX AI (production):** This video by DCT EATS features a comparison of authentic Hyderabadi mutton biryani in Mumbai across three price points (₹450, ₹800, and ₹1200) from Bikkgane Biryani, Biryani By Kilo, and Lit, alongside Sahil from Headbanger Eats. Please note that this reflects the creator's opinion and is not verified by ASKODOX. Specific details such as ratings, exact prices per item, distance, and availability are not provided in the source.

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** Let me check real sellers, shops and online options near you.  
**This branch:** Let me check real sellers, shops and online options near you. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "hyderabadi biryani near me" → The Kazus Royal Dum Biryani [nearby_external]; Best Hyderabadi Biryani Restaurants In Vijayawada 2025 | Order Online [deals]; Order Online – HYDERABAD BIRYANI POINT [online]; Buy Haldiram's Hyderabadi Biryani Online at Best Price of Rs 100 - bigbasket [online]

### travel (en) -- "Araku valley trip review video"

**Video:** Top 10 Places in Araku Valley 🌴🌊❤✨ #araku -- Ramya Random Tales (https://www.youtube.com/watch?v=IaaAlzSxqwA)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: Top 10 Places in Araku Valley 🌴🌊❤✨ #araku / Top 10 places you must visit in Araku. / Watch till end, give it a like & please do subscribe to the Channel. / Rana Jilleda waterfalls is ❤🤌 / Galikonda View point is Overrated 🚶‍♀️  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "Top 10 Places in Araku Valley 🌴🌊❤✨ #araku"

**ASKODOX AI (production):** According to the details provided by creator Ramya Random Tales (creator's opinion, not verified by ASKODOX), the video highlights Rana Jilleda Waterfalls as a favorite spot, mentions Galikonda Viewpoint is overrated, and recommends skipping Katika Waterfalls if traveling with kids or elderly people. Specific details such as full lists, prices, distances, and ratings are not provided in the source description.

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

**ASKODOX AI (production):** This video, titled "How To Check & Buy Used Classic 350," is by creator Bindass Singh. Specific details like price, rating, reviews, distance, and stock availability are not provided in the listing. Please note that the content reflects the creator's opinion and is not verified by ASKODOX.

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

**ASKODOX AI (production):** This video is a long-term review of the iPhone 15 by CallMeShazzam TECH, presenting the creator's opinion, which is not verified by ASKODOX. It features Malayalam audio with English subtitles. Specific details like price, rating, reviews, stock, and specifications are not provided in the source.

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

**ASKODOX AI (production):** KP Vlogs & Review ఛానెల్ అందించిన వివరాలలో ఈ Urban Company AC సర్వీస్ యొక్క ధర, దూరం, నాణ్యత, అందుబాటు మరియు రివ్యూలకు సంబంధించిన స్పష్టమైన వివరాలు అందుబాటులో లేవు (Not verified). ఇవి ఆ క్రియేటర్ అభిప్రాయం మాత్రమే.

**User (follow-up, same conversation):** ఇది చిన్న గదికి సరిపోతుందా?

**ASKODOX AI:** చిన్న గదికి Split AC సరిపోతుందో లేదో తెలియాలంటే టన్నుల సామర్థ్యం (Tonnage) అవసరం, కానీ ఇక్కడ ఇచ్చే వివరాలలో ఆ సమాచారం లేదు (Not verified).

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
