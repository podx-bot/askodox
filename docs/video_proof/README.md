# Real video content proof

Generated 2026-10-01T13:13:05Z by `.github/workflows/video-real-content-proof.yml` (run 36866579347).

* Video rows: **real**, from production's live web video search (Brave) -- replayed into this branch's pipeline, which adds references, YouTube oEmbed checks (live network), linking and disclosures.
* AI answers: **real**, from the production assistant (`/api/in-app/assistant`) given exactly what the app sends (question + grounding from this branch's explain).
* Next-step options: **real**, from production's discovery for the step's text.
* Service cases: production (main) does not search videos for service needs, so their real video rows come from a product-category source query for the same subject; this branch runs them as service needs.
* YouTube Data API: needs_configuration (no YOUTUBE_API_KEY in this run).

| Case | Lang | Videos | Top video | Channel | Plays in app | Disclosure | AI answer | Follow-up | Next step → options |
|---|---|---|---|---|---|---|---|---|---|
| electronics | en | 1 | [Samsung 43 Inch Crystal UHD 4K Vision AI TV Review [2026] /…](https://www.youtube.com/watch?v=cgQhFuIFREs) | Udrawat | yes (official YouTube embed) | Creator's opinion -- not verified by ASKODOX | yes | yes | samsung 43 inch tv near me → 6 (deals, used) |
| electronics-te | te | 1 | [Samsung 43 Inch Crystal UHD 4K Vision AI TV Review [2026] /…](https://www.youtube.com/watch?v=cgQhFuIFREs) | Udrawat | yes (official YouTube embed) | Creator's opinion -- not verified by ASKODOX | yes | yes | samsung 43 inch tv offers → 6 (deals, used) |
| phone | en | 1 | [Redmi Note 13 Pro Review - Not again! - YouTube](https://www.youtube.com/watch?v=i2FYVv-qa4w) | Izzi Boye | yes (official YouTube embed) | Creator's opinion -- not verified by ASKODOX | yes | yes | redmi note 13 pro offers → 6 (deals, surplus, used) |
| vehicle | en | 1 | [Tata Nexon 3000 Km Long Term Review: 3 Reasons to Buy, 3 Re…](https://www.youtube.com/watch?v=PC-ztrSrDMo) | carandbike | yes (official YouTube embed) | Creator's opinion -- not verified by ASKODOX | yes | yes | tata nexon near me → 6 (deals, surplus, used) |
| service | en | 1 | [Urban Company AC Service Vs Nobroker AC Service 2025 / Whic…](https://www.youtube.com/watch?v=KOYoiZG5_3E) | Crazyy Unboxing | yes (official YouTube embed) | Creator's opinion -- not verified by ASKODOX | yes | yes | ac service near me → 4 () |
| home-service | en | 1 | [Real Plumber Ultimate Plumbing Maintenance Guide - YouTube](https://www.youtube.com/watch?v=2FrfA6qNn0U) | Roger Wakefield Plumbing Educ… | yes (official YouTube embed) | Creator's opinion -- not verified by ASKODOX | yes | yes | plumbing repair service near me → 4 () |
| food | en | 1 | [Hyderabadi Chicken Biryani / Chicken Biryani Recipe / Resat…](https://www.youtube.com/watch?v=1Nb0khRXiJk) | Ashus Delicacies | yes (official YouTube embed) | Creator's opinion -- not verified by ASKODOX | yes | yes | hyderabadi biryani near me → 5 (used) |
| travel | en | 1 | [Ultimate Araku Valley Travel Guide: Top Things to Do and Se…](https://www.youtube.com/watch?v=NWiBFTd5aD0) | Let's Discover India | yes (official YouTube embed) | Creator's opinion -- not verified by ASKODOX | yes | yes | araku valley trip reviews → 6 (deals) |
| used-item | en | 1 | [The Truth About the Royal Enfield Classic 350 (2025 Review)…](https://www.youtube.com/watch?v=88rgLE_eNJk) | Jack Brock | yes (official YouTube embed) | Creator's opinion -- not verified by ASKODOX | yes | yes | used royal enfield classic 350 near me → 6 (deals, used) |
| deal | en | 1 | [iPhone 15 in 2026 - worth it? (Review) - YouTube](https://www.youtube.com/watch?v=DJ5BkFUoKxg) | 91Tech | yes (official YouTube embed) | Creator's opinion -- not verified by ASKODOX | yes | yes | iphone 15 offers → 6 (deals, surplus, used) |
| service-te | te | 1 | [Urban Company AC Service Vs Nobroker AC Service 2025 / Whic…](https://www.youtube.com/watch?v=KOYoiZG5_3E) | Crazyy Unboxing | yes (official YouTube embed) | Creator's opinion -- not verified by ASKODOX | yes | yes | ac service near me → 4 () |

## Conversations (real AI answers)

### electronics (en) -- "Samsung 43 inch TV review videos"

**Video:** Samsung 43 Inch Crystal UHD 4K Vision AI TV Review [2026] | 30W Speakers, HDR, Tizen OS - YouTube -- Udrawat (https://www.youtube.com/watch?v=cgQhFuIFREs)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: Samsung 43 Inch Crystal UHD 4K Vision AI TV Review [2026] | 30W Speakers, HDR, Tizen OS - YouTube / Samsung Crystal43": https://link.amazon/B03sWYNpr [Amazon]50": https://link.amazon/B0i2g7kKa [Amazon]55": https://link.amazon/B00Enb8SH [Amazon]65": https://  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "Samsung 43 Inch Crystal UHD 4K Vision AI TV Review [2026] | 30W Speakers, HDR, Tizen OS - YouTube"

**ASKODOX AI (production):** The video titled "Samsung 43 Inch Crystal UHD 4K Vision AI TV Review [2026]" by Udrawat mentions features like 30W Speakers, HDR, and Tizen OS. Please note that this is the creator's opinion and not verified by ASKODOX. Specific details such as price, stock availability, ratings, and full specifications are not provided by the source.

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** The Samsung 43-inch Crystal UHD 4K TV generally offers good value for its Vision AI features, HDR support, and 30W speakers. You can check local electronics retailers like Reliance Digital, Bajaj Electronics, or Croma in Vijayawada, or order online via Amazon or Flipkart.  
**This branch:** Let me check real sellers, shops and online options near you -- the results appear below. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "samsung 43 inch tv near me" → samsung 43 inches tv | Used TV & DVD & Multimedia in Bangalore | Electronics & Appliances Quikr Bazaar Bangalore [used]; Samsung 43-inch TVs Price List in India (September 2026) [deals]; Second Hand TV - Old TV Latest Price, Manufacturers & Suppliers [used]; Buy Refurbished / Used TV & DVD in Vijayawada | Second Hand TV / Television For Sale Online | QuikrBazaar [used]

### electronics-te (te) -- "శామ్‌సంగ్ 43 అంగుళాల టీవీ రివ్యూ వీడియో"

**Video:** Samsung 43 Inch Crystal UHD 4K Vision AI TV Review [2026] | 30W Speakers, HDR, Tizen OS - YouTube -- Udrawat (https://www.youtube.com/watch?v=cgQhFuIFREs)

**ASKODOX explain (branch):** ఈ వీడియోను నేను చూడలేదు/విశ్లేషించలేదు. శీర్షిక, క్రియేటర్ ఇచ్చిన వివరణ, ఛానల్ మాత్రమే తెలుసు.  
Quoted from source: Samsung 43 Inch Crystal UHD 4K Vision AI TV Review [2026] | 30W Speakers, HDR, Tizen OS - YouTube / Samsung Crystal43": https://link.amazon/B03sWYNpr [Amazon]50": https://link.amazon/B0i2g7kKa [Amazon]55": https://link.amazon/B00Enb8SH [Amazon]65": https://  
Label: Creator's opinion -- not verified by ASKODOX

**User:** "Samsung 43 Inch Crystal UHD 4K Vision AI TV Review [2026] | 30W Speakers, HDR, Tizen OS - YouTube" గురించి చెప్పండి: ధర, దూరం, నాణ్యత, అందుబాటు, రివ్యూలు

**ASKODOX AI (production):** Samsung 43 Inch Crystal UHD 4K Vision AI TV గురించి ధర, నాణ్యత, అందుబాటు మరియు రివ్యూల సమాచారం అందించిన వివరాల్లో అందుబాటులో లేదు (not provided). ఈ వీడియో Creator Udrawat అభిప్రాయం ప్రకారం అందించబడింది, ఇది ASKODOX ద్వారా ధృవీకరించబడలేదు.

**User (follow-up, same conversation):** ఇది చిన్న గదికి సరిపోతుందా?

**ASKODOX AI:** అవును, 43 అంగుళాల టీవీ చిన్న లేదా మధ్యస్థ పరిమాణం గల గదికి సరిగ్గా సరిపోతుంది. సాధారణంగా 5 నుండి 8 అడుగుల వీక్షణ దూరం ఉంటే ఇది చాలా బాగుంటుంది.

**Next step:** "samsung 43 inch tv offers" → samsung 43 inches tv | Used TV & DVD & Multimedia in Bangalore | Electronics & Appliances Quikr Bazaar Bangalore [used]; Samsung 43-inch TVs Price List in India (September 2026) [deals]; Second Hand TV - Old TV Latest Price, Manufacturers & Suppliers [used]; Buy Refurbished / Used TV & DVD in Vijayawada | Second Hand TV / Television For Sale Online | QuikrBazaar [used]

### phone (en) -- "Redmi Note 13 Pro review video"

**Video:** Redmi Note 13 Pro Review - Not again! - YouTube -- Izzi Boye (https://www.youtube.com/watch?v=i2FYVv-qa4w)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: Redmi Note 13 Pro Review - Not again! - YouTube / Redmi Note 13 Pro 4G Unboxing and Review **AI PDF Editors with OCR: UPDF - Save 71% Now: https://bit.ly/3UZCRky **Try UPDF AI: https://bit.ly/3IijQSB Redmi N...  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "Redmi Note 13 Pro Review - Not again! - YouTube"

**ASKODOX AI (production):** The video 'Redmi Note 13 Pro Review - Not again!' is a 4G unboxing and review by creator Izzi Boye. Please note that this is the creator's opinion and is not verified by ASKODOX. Specific details such as price, specifications, ratings, or stock are not provided in the source metadata.

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** It depends on your priorities—the Redmi Note 13 Pro offers a great display and main camera, though performance and software updates vary by variant. You can find it at local electronics stores in Vijayawada like Mi Homes, Reliance Digital, or Bajaj Electronics. Which specific storage or color variant are you looking for?  
**This branch:** Let me check real sellers, shops and online options near you -- the results appear below. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "redmi note 13 pro offers" → Buy Old Used Xiaomi Redmi Note 13 Pro 4G Phones Under ... [used]; Open Box Store [surplus]; Redmi Note 13 5G, Note 13 Pro 5G, Note 13 Pro+ 5G goes on sale on Vijay Sales - Times of India [deals]; Buy Refurbished and Second Hand Xiaomi Redmi Note 13 Pro 5G Online at Cashify Store [used]

### vehicle (en) -- "Tata Nexon review video"

**Video:** Tata Nexon 3000 Km Long Term Review: 3 Reasons to Buy, 3 Reasons to Avoid - YouTube -- carandbike (https://www.youtube.com/watch?v=PC-ztrSrDMo)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: Tata Nexon 3000 Km Long Term Review: 3 Reasons to Buy, 3 Reasons to Avoid - YouTube / Our long term Tata Nexon finally went back and after spending 3 months at the car&bike garage we have understood why the subcompact SUV is so much talked abo...  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "Tata Nexon 3000 Km Long Term Review: 3 Reasons to Buy, 3 Reasons to Avoid - YouTube"

**ASKODOX AI (production):** This video by carandbike shares the creator's opinion on their 3-month long-term experience (3,000 km) with the Tata Nexon, highlighting 3 reasons to buy and 3 reasons to avoid. Please note this reflects the creator's opinion and is not verified by ASKODOX. Specific details like vehicle price, ratings, or specifications are not provided in the source.

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** The Tata Nexon offers strong safety, good build quality, and feature-rich trims, though some users note occasional software glitches or service variations. In Vijayawada, you can check it out at authorized Tata Motors showrooms like Jasper Tata or Lakshmi Tata.  
**This branch:** Let me check real sellers, shops and online options near you -- the results appear below. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "tata nexon near me" → Tata NEXON Used Cars in Vijayawada | Second Hand Tata NEXON Cars in Vijayawada - Cars24 [used]; Tata Nexon On Road Price in Vijayawada (2026) – ₹8.63 lakh Onwards | Autocar India [surplus]; Tata Nexon May 2026 Offers in Vijayawada - Latest Discount & EMI Offers [deals]; 7+ Used Tata Nexon Cars in Vijayawada - Second Hand Tata Nexon Cars in Vijayawada [used]

### service (en) -- "AC service video"

**Video:** Urban Company AC Service Vs Nobroker AC Service 2025 | Which is Best?? - YouTube -- Crazyy Unboxing (https://www.youtube.com/watch?v=KOYoiZG5_3E)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: Urban Company AC Service Vs Nobroker AC Service 2025 | Which is Best?? - YouTube / Urban Company Vs NoBroker AC Service 🧹❄️ | Full Honest Review | Kaun Jeeta?Bhaiyon aur behno! / 🤭Garmi aayi nahi, AC ki yaad aa gayi!Isliye humne kiya Urban ...  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "Urban Company AC Service Vs Nobroker AC Service 2025 | Which is Best?? - YouTube"

**ASKODOX AI (production):** This video by 'Crazyy Unboxing' compares Urban Company and NoBroker AC servicing to see which is better. Please note that this reflects the creator's personal opinion and is not verified by ASKODOX. Specific details like pricing, ratings, or detailed specs are not provided in the source metadata.

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** AC servicing depends on your specific needs: Urban Company often offers standardized multi-point checks, while NoBroker provides competitive localized pricing. You can book authorized AC technicians directly through ASKODOX here in Vijayawada. What type of AC service do you need?  
**This branch:** Let me check real sellers, shops and online options near you -- the results appear below. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "ac service near me" → Professional AC service & repair experts in Vijayawada, India [online]; Split AC Services in Vijayawada [online]; Top AC Service in Vijayawada, Best AC Repair Service in Vijayawada | Sulekha Vijayawada [online]; Top AC Repair Services in Vijayawada - AC Installation - Servicing - Justdial [online]

### home-service (en) -- "kitchen sink plumbing repair video"

**Video:** Real Plumber Ultimate Plumbing Maintenance Guide - YouTube -- Roger Wakefield Plumbing Education (https://www.youtube.com/watch?v=2FrfA6qNn0U)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: Real Plumber Ultimate Plumbing Maintenance Guide - YouTube / Real Plumber Ultimate Plumbing Maintenance GuideThis is the ultimate annual plumbing maintenance checklist—straight from a real plumber. / In this video, I wal...  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "Real Plumber Ultimate Plumbing Maintenance Guide - YouTube"

**ASKODOX AI (production):** The video 'Real Plumber Ultimate Plumbing Maintenance Guide' by Roger Wakefield Plumbing Education provides an annual plumbing maintenance checklist based on the creator's opinion, which is not verified by ASKODOX. Details like price, rating, reviews, and specific specifications are not provided by the source. Would you like help finding a professional plumber in Vijayawada instead?

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** As a DIY maintenance video guide, it is useful for basic maintenance tips, but for complex kitchen sink plumbing repairs, hiring a local specialist is recommended. Would you like me to help you find and book a professional plumber in Vijayawada?  
**This branch:** Let me check real sellers, shops and online options near you -- the results appear below. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "plumbing repair service near me" → Book Plumber Repair Service Vijayawada Service On Wheel:Ph-8237611222 / 8087911222 [online]; Plumber in India | Book Trusted Plumbing Services at Home | Urban Company [online]; Plumbing services near me in Vijayawada [online]; Plumbers @7065012902 Vijayawada - Mannubhai.com [online]

### food (en) -- "Hyderabadi biryani review video"

**Video:** Hyderabadi Chicken Biryani | Chicken Biryani Recipe | Resaturant Hyderabadi Chicken Biryani - YouTube -- Ashus Delicacies (https://www.youtube.com/watch?v=1Nb0khRXiJk)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: Hyderabadi Chicken Biryani | Chicken Biryani Recipe | Resaturant Hyderabadi Chicken Biryani - YouTube / #chickenbiryani #chickenbiriyani #biryani Hyderabadi Chicken Biryani | Chicken Biryani Recipe | Resaturant Hyderabadi Chicken BiryaniIngredients:Chicken – 1....  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "Hyderabadi Chicken Biryani | Chicken Biryani Recipe | Resaturant Hyderabadi Chicken Biryani - YouTube"

**ASKODOX AI (production):** The video 'Hyderabadi Chicken Biryani | Chicken Biryani Recipe | Resaturant Hyderabadi Chicken Biryani' is by Ashus Delicacies. Note that this represents the creator's opinion and recipe, not verified facts by ASKODOX. Details like price, rating, reviews, and full specifications are not provided by the source. Would you like me to share a general Hyderabadi Chicken Biryani recipe or help you find biryani places in Vijayawada?

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** That video is a cooking recipe by Ashus Delicacies, not a product review. If you'd like to try authentic Hyderabadi Chicken Biryani, I can suggest popular top-rated restaurants serving it right here in Vijayawada.  
**This branch:** Let me check real sellers, shops and online options near you -- the results appear below. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "hyderabadi biryani near me" → Biryani - Used Kitchen & Other Appliances for sale in India | OLX [used]; Order Online – HYDERABAD BIRYANI POINT [online]; Order The Biryani Life Hyderabadi & Lucknowi Biryani Online in Vijayawada from EatSure [online]; Order Biryani Near Me Vijayawada [online]

### travel (en) -- "Araku valley trip review video"

**Video:** Ultimate Araku Valley Travel Guide: Top Things to Do and See - YouTube -- Let's Discover India (https://www.youtube.com/watch?v=NWiBFTd5aD0)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: Ultimate Araku Valley Travel Guide: Top Things to Do and See - YouTube / Discover the Hidden Gems of Araku Valley: Borra Caves & Anantagiri Waterfalls 🌄Join us on an unforgettable journey to the picturesque landscapes of Araku Va...  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "Ultimate Araku Valley Travel Guide: Top Things to Do and See - YouTube"

**ASKODOX AI (production):** This video by Let's Discover India covers top things to do in Araku Valley, including Borra Caves and Anantagiri Waterfalls. Please note that this reflects the creator's opinion and is not verified by ASKODOX. Specific details such as ratings, reviews, or distance are not provided by the source.

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** The travel guide video is free to watch on YouTube and is great for planning your itinerary. If you are asking about booking a local tour package from Vijayawada, please let me know your preferred dates or budget.  
**This branch:** Let me check real sellers, shops and online options near you -- the results appear below. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "araku valley trip reviews" → Araku Valley Tour Packages from Vijayawada, Flat 20% Off - Book at Lowest Price [deals]; 5 Araku Valley Tour Packages at ₹6785 pp - Book Online with 20% Off [deals]; Araku Valley Tour Packages from Vijayawada | Araku Valley Packages from Vijayawada | Araku Valley Honeymoon Packages from Vijayawada | Araku Valley Holiday Pack [deals]; Vijayawada To Araku Valley Trains | Book From 6 Trains, Timetable, Fare [online]

### used-item (en) -- "used Royal Enfield Classic 350 review video"

**Video:** The Truth About the Royal Enfield Classic 350 (2025 Review) - YouTube -- Jack Brock (https://www.youtube.com/watch?v=88rgLE_eNJk)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: The Truth About the Royal Enfield Classic 350 (2025 Review) - YouTube / I’m getting sick of over produced 20 minute motorcycle reviews that spend more time showing off cinematic shots than actually talking about the bike.  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "The Truth About the Royal Enfield Classic 350 (2025 Review) - YouTube"

**ASKODOX AI (production):** The video titled "The Truth About the Royal Enfield Classic 350 (2025 Review)" is created by Jack Brock. The creator mentions being tired of over-produced reviews and aims to focus directly on the bike rather than cinematic shots. Please note that this reflects the creator's opinion and is not verified by ASKODOX. Specific details like price, rating, reviews, and specifications are not provided in the source.

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** The Royal Enfield Classic 350 offers refined performance, classic styling, and lower vibrations, making it a great choice for daily commuting and cruising. You can find new models at official Royal Enfield showrooms in Vijayawada or explore local pre-owned dealerships and platforms like OLX for used options. Are you looking for a new or used bike?  
**This branch:** Let me check real sellers, shops and online options near you -- the results appear below. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "used royal enfield classic 350 near me" → 13 Used Royal Enfield Classic in Vijayawada. Buy from Owners and Dealers - Bikes4Sale [used]; 9 Used Royal Enfield Classic 350 Bikes in Vijayawada - Buy & Sell Second Hand Bikes [deals]; Royal Enfield Classic 350 price in Vijayawada - September 2026 on road price of Classic 350 in Vijayawada [deals]; Used Royal Enfield Classic 350 Bikes in Vijayawada - Second Hand Royal Enfield Classic 350 Bikes for Sale in Vijayawada [used]

### deal (en) -- "iPhone 15 offer review video"

**Video:** iPhone 15 in 2026 - worth it? (Review) - YouTube -- 91Tech (https://www.youtube.com/watch?v=DJ5BkFUoKxg)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: iPhone 15 in 2026 - worth it? (Review) - YouTube / Already over 2 years old and discontinued only recently, the iPhone 15 & 15 Plus are solid midrange smartphones that include modern features like USB-C and t...  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "iPhone 15 in 2026 - worth it? (Review) - YouTube"

**ASKODOX AI (production):** This video by 91Tech gives their personal opinion on whether the iPhone 15 is still worth buying in 2026. They describe it as a solid midrange option featuring modern additions like USB-C, though note it is over 2 years old and recently discontinued. Please note this reflects the creator's view and is not verified by ASKODOX. Specific details like price, stock availability, or user ratings are not provided in the source.

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** The iPhone 15 remains a strong option with its USB-C port, Dynamic Island, and reliable performance. You can check availability at local electronics retailers like Croma, Reliance Digital, or authorized Apple resellers in Vijayawada.  
**This branch:** Let me check real sellers, shops and online options near you -- the results appear below. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "iphone 15 offers" → Buy & Sell Second Hand iPhones in Vijayawada, Used Apple Mobile Phones in Vijayawada | OLX [used]; Apple Open Box [surplus]; iPhone 15 is available for less than Rs 35,000 on Vijay Sales, here is how the deal works - India Today [deals]; Buy & Sell Second Hand Iphone in Vijayawada, Used Mobiles in Vijayawada | OLX [used]

### service-te (te) -- "ఏసీ సర్వీస్ వీడియో"

**Video:** Urban Company AC Service Vs Nobroker AC Service 2025 | Which is Best?? - YouTube -- Crazyy Unboxing (https://www.youtube.com/watch?v=KOYoiZG5_3E)

**ASKODOX explain (branch):** ఈ వీడియోను నేను చూడలేదు/విశ్లేషించలేదు. శీర్షిక, క్రియేటర్ ఇచ్చిన వివరణ, ఛానల్ మాత్రమే తెలుసు.  
Quoted from source: Urban Company AC Service Vs Nobroker AC Service 2025 | Which is Best?? - YouTube / Urban Company Vs NoBroker AC Service 🧹❄️ | Full Honest Review | Kaun Jeeta?Bhaiyon aur behno! / 🤭Garmi aayi nahi, AC ki yaad aa gayi!Isliye humne kiya Urban ...  
Label: Creator's opinion -- not verified by ASKODOX

**User:** "Urban Company AC Service Vs Nobroker AC Service 2025 | Which is Best?? - YouTube" గురించి చెప్పండి: ధర, దూరం, నాణ్యత, అందుబాటు, రివ్యూలు

**ASKODOX AI (production):** ఈ యూట్యూబ్ వీడియో (Crazyy Unboxing ఛానల్) అర్బన్ కంపెనీ మరియు నోబ్రోకర్ AC సర్వీస్‌ల మధ్య పోలిక మరియు రివ్యూ గురించి చర్చిస్తుంది. అయితే, సదరు సోర్స్ నుండి ధర, దూరం, నాణ్యత, అందుబాటు మరియు రివ్యూల వివరాలు ప్రత్యేకంగా లభించలేదు (not provided). ఇది క్రియేటర్ వ్యక్తిగత అభిప్రాయం మాత్రమే.

**User (follow-up, same conversation):** ఇది చిన్న గదికి సరిపోతుందా?

**ASKODOX AI:** అవును, చిన్న గదికి (సుమారు 100-120 చదరపు అడుగులు) 1 టన్ను AC సరిగ్గా సరిపోతుంది. మీకు AC సర్వీసింగ్ కావాలా లేదా కొత్త AC కొనడానికి వివరాలు కావాలా?

**Next step:** "ac service near me" → Professional AC service & repair experts in Vijayawada, India [online]; Split AC Services in Vijayawada [online]; Top AC Service in Vijayawada, Best AC Repair Service in Vijayawada | Sulekha Vijayawada [online]; Top AC Repair Services in Vijayawada - AC Installation - Servicing - Justdial [online]

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
