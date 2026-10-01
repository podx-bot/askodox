# Real video content proof

Generated 2026-10-01T11:56:35Z by `.github/workflows/video-real-content-proof.yml` (run 36858098374).

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

**ASKODOX AI (production):** The video titled 'Samsung 43 Inch Crystal UHD 4K Vision AI TV Review [2026]' by Udrawat mentions features like 30W Speakers, HDR, and Tizen OS, but please note that this is the creator's opinion and not verified by ASKODOX. Specific facts such as price, ratings, and stock availability are not provided by the source.

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** The Samsung 43-inch Crystal UHD TV offers good value with its 30W speakers, HDR, and Tizen OS for everyday viewing. You can check local electronics stores like Reliance Digital or Bajaj Electronics in Vijayawada, or order online via major e-commerce platforms.  
**This branch:** Let me check real sellers, shops and online options near you -- the results appear below. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "samsung 43 inch tv near me" → samsung 43 inches tv | Used TV & DVD & Multimedia in Bangalore | Electronics & Appliances Quikr Bazaar Bangalore [used]; Samsung 43-inch TVs Price List in India (September 2026) [deals]; Second Hand TV - Old TV Latest Price, Manufacturers & Suppliers [used]; Buy Refurbished / Used TV & DVD in Vijayawada | Second Hand TV / Television For Sale Online | QuikrBazaar [used]

### electronics-te (te) -- "శామ్‌సంగ్ 43 అంగుళాల టీవీ రివ్యూ వీడియో"

**Video:** Samsung 43 Inch Crystal UHD 4K Vision AI TV Review [2026] | 30W Speakers, HDR, Tizen OS - YouTube -- Udrawat (https://www.youtube.com/watch?v=cgQhFuIFREs)

**ASKODOX explain (branch):** ఈ వీడియోను నేను చూడలేదు/విశ్లేషించలేదు. శీర్షిక, క్రియేటర్ ఇచ్చిన వివరణ, ఛానల్ మాత్రమే తెలుసు.  
Quoted from source: Samsung 43 Inch Crystal UHD 4K Vision AI TV Review [2026] | 30W Speakers, HDR, Tizen OS - YouTube / Samsung Crystal43": https://link.amazon/B03sWYNpr [Amazon]50": https://link.amazon/B0i2g7kKa [Amazon]55": https://link.amazon/B00Enb8SH [Amazon]65": https://  
Label: Creator's opinion -- not verified by ASKODOX

**User:** "Samsung 43 Inch Crystal UHD 4K Vision AI TV Review [2026] | 30W Speakers, HDR, Tizen OS - YouTube" గురించి చెప్పండి: ధర, దూరం, నాణ్యత, అందుబాటు, రివ్యూలు

**ASKODOX AI (production):** ఈ Samsung 43 Inch Crystal UHD 4K TV గురించి యూట్యూబర్ Udrawat వారి వీడియో ఆధారంగా సమాచారం ఉంది (ఇది వారి వ్యక్తిగత అభిప్రాయం మాత్రమే, ASKODOX ద్వారా ధృవీకరించబడలేదు). ప్రసుత్తం ఈ మోడల్ యొక్క ధర, అందుబాటు, నాణ్యత (రివ్యూ వివరాలు), మరియు దూరం సంబంధించిన వివరాలు లభ్యం కాలేదు. మీకు వివరాలు కావాలంటే విక్రేతను అడిగి తెలుసుకోగలము.

**User (follow-up, same conversation):** ఇది చిన్న గదికి సరిపోతుందా?

**ASKODOX AI:** అవును, 43 అంగుళాల టీవీ చిన్న లేదా మధ్యస్థ పరిమాణంలో ఉన్న గదికి (సుమారు 8 నుండి 10 అడుగుల వీక్షణ దూరానికి) చాలా బాగా సరిపోతుంది.

**Next step:** "samsung 43 inch tv offers" → samsung 43 inches tv | Used TV & DVD & Multimedia in Bangalore | Electronics & Appliances Quikr Bazaar Bangalore [used]; Samsung 43-inch TVs Price List in India (September 2026) [deals]; Second Hand TV - Old TV Latest Price, Manufacturers & Suppliers [used]; Buy Refurbished / Used TV & DVD in Vijayawada | Second Hand TV / Television For Sale Online | QuikrBazaar [used]

### phone (en) -- "Redmi Note 13 Pro review video"

**Video:** Redmi Note 13 Pro Review - Not again! - YouTube -- Izzi Boye (https://www.youtube.com/watch?v=i2FYVv-qa4w)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: Redmi Note 13 Pro Review - Not again! - YouTube / Redmi Note 13 Pro 4G Unboxing and Review **AI PDF Editors with OCR: UPDF - Save 71% Now: https://bit.ly/3UZCRky **Try UPDF AI: https://bit.ly/3IijQSB Redmi N...  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "Redmi Note 13 Pro Review - Not again! - YouTube"

**ASKODOX AI (production):** The video titled "Redmi Note 13 Pro Review - Not again!" is created by Izzi Boye and covers a 4G unboxing and review. Please note that this is the creator's personal opinion and has not been verified by ASKODOX. Details such as price, ratings, stock, and full specifications are not provided in the source metadata.

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** It offers good value for its camera and display, but performance depends on whether you get the 4G or 5G model. You can check for availability at local mobile stores in Vijayawada or online platforms like Mi Store and Flipkart. Which variant or color are you looking for?  
**This branch:** Let me check real sellers, shops and online options near you -- the results appear below. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "redmi note 13 pro offers" → Buy Old Used Xiaomi Redmi Note 13 Pro 4G Phones Under ... [used]; Open Box Store [surplus]; Redmi Note 13 5G, Note 13 Pro 5G, Note 13 Pro+ 5G goes on sale on Vijay Sales - Times of India [deals]; Buy Refurbished and Second Hand Xiaomi Redmi Note 13 Pro 5G Online at Cashify Store [used]

### vehicle (en) -- "Tata Nexon review video"

**Video:** Tata Nexon 3000 Km Long Term Review: 3 Reasons to Buy, 3 Reasons to Avoid - YouTube -- carandbike (https://www.youtube.com/watch?v=PC-ztrSrDMo)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: Tata Nexon 3000 Km Long Term Review: 3 Reasons to Buy, 3 Reasons to Avoid - YouTube / Our long term Tata Nexon finally went back and after spending 3 months at the car&bike garage we have understood why the subcompact SUV is so much talked abo...  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "Tata Nexon 3000 Km Long Term Review: 3 Reasons to Buy, 3 Reasons to Avoid - YouTube"

**ASKODOX AI (production):** This video by carandbike shares their creator opinion from a 3-month long-term test of the Tata Nexon. Note that these points reflect the creator's opinion and are not verified by ASKODOX. Specific details like price, ratings, and exact specifications were not provided with this source.

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** The Nexon offers strong safety, good ride quality, and feature-rich variants, though some users report inconsistent service experiences and infotainment glitches. You can check it out at Tata Motors dealerships in Vijayawada like Select Motors or Jasper Tata.  
**This branch:** Let me check real sellers, shops and online options near you -- the results appear below. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "tata nexon near me" → Tata NEXON Used Cars in Vijayawada | Second Hand Tata NEXON Cars in Vijayawada - Cars24 [used]; Tata Nexon On Road Price in Vijayawada (2026) – ₹8.63 lakh Onwards | Autocar India [surplus]; Tata Nexon May 2026 Offers in Vijayawada - Latest Discount & EMI Offers [deals]; 7+ Used Tata Nexon Cars in Vijayawada - Second Hand Tata Nexon Cars in Vijayawada [used]

### service (en) -- "AC service video"

**Video:** Urban Company AC Service Vs Nobroker AC Service 2025 | Which is Best?? - YouTube -- Crazyy Unboxing (https://www.youtube.com/watch?v=KOYoiZG5_3E)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: Urban Company AC Service Vs Nobroker AC Service 2025 | Which is Best?? - YouTube / Urban Company Vs NoBroker AC Service 🧹❄️ | Full Honest Review | Kaun Jeeta?Bhaiyon aur behno! / 🤭Garmi aayi nahi, AC ki yaad aa gayi!Isliye humne kiya Urban ...  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "Urban Company AC Service Vs Nobroker AC Service 2025 | Which is Best?? - YouTube"

**ASKODOX AI (production):** This video, titled 'Urban Company AC Service Vs Nobroker AC Service 2025 | Which is Best??', is a review by creator Crazyy Unboxing comparing the AC services of Urban Company and NoBroker. Please note that this is the creator's opinion and is not verified by ASKODOX. Specific details like pricing, ratings, or detailed service breakdowns are not provided in the source description.

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** The video compares pricing, service quality, and technician experience between Urban Company and NoBroker to help you decide. You can book both services directly through their official apps or websites in Vijayawada.  
**This branch:** Let me check real sellers, shops and online options near you -- the results appear below. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "ac service near me" → Professional AC service & repair experts in Vijayawada, India [online]; Split AC Services in Vijayawada [online]; Top AC Service in Vijayawada, Best AC Repair Service in Vijayawada | Sulekha Vijayawada [online]; Top AC Repair Services in Vijayawada - AC Installation - Servicing - Justdial [online]

### home-service (en) -- "kitchen sink plumbing repair video"

**Video:** Real Plumber Ultimate Plumbing Maintenance Guide - YouTube -- Roger Wakefield Plumbing Education (https://www.youtube.com/watch?v=2FrfA6qNn0U)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: Real Plumber Ultimate Plumbing Maintenance Guide - YouTube / Real Plumber Ultimate Plumbing Maintenance GuideThis is the ultimate annual plumbing maintenance checklist—straight from a real plumber. / In this video, I wal...  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "Real Plumber Ultimate Plumbing Maintenance Guide - YouTube"

**ASKODOX AI (production):** This video, titled "Real Plumber Ultimate Plumbing Maintenance Guide", is an annual plumbing maintenance checklist provided by Roger Wakefield Plumbing Education. Please note that this reflects the creator's opinion and is not verified by ASKODOX. Specific details such as price, ratings, or reviews are not provided by the source.

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** It depends on whether you prefer a comprehensive DIY video guide. For local hands-on help, would you like to hire a professional plumber in Vijayawada instead?  
**This branch:** Let me check real sellers, shops and online options near you -- the results appear below. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "plumbing repair service near me" → Book Plumber Repair Service Vijayawada Service On Wheel:Ph-8237611222 / 8087911222 [online]; Plumber in India | Book Trusted Plumbing Services at Home | Urban Company [online]; Plumbing services near me in Vijayawada [online]; Plumbers @7065012902 Vijayawada - Mannubhai.com [online]

### food (en) -- "Hyderabadi biryani review video"

**Video:** Hyderabadi Chicken Biryani | Chicken Biryani Recipe | Resaturant Hyderabadi Chicken Biryani - YouTube -- Ashus Delicacies (https://www.youtube.com/watch?v=1Nb0khRXiJk)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: Hyderabadi Chicken Biryani | Chicken Biryani Recipe | Resaturant Hyderabadi Chicken Biryani - YouTube / #chickenbiryani #chickenbiriyani #biryani Hyderabadi Chicken Biryani | Chicken Biryani Recipe | Resaturant Hyderabadi Chicken BiryaniIngredients:Chicken – 1....  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "Hyderabadi Chicken Biryani | Chicken Biryani Recipe | Resaturant Hyderabadi Chicken Biryani - YouTube"

**ASKODOX AI (production):** This video, titled 'Hyderabadi Chicken Biryani | Chicken Biryani Recipe | Resaturant Hyderabadi Chicken Biryani', is by Ashus Delicacies. Please note this is the creator's opinion and not verified by ASKODOX. The description lists ingredients starting with 'Chicken – 1...', but detailed specs, step-by-step instructions, ratings, and reviews are not provided in the source metadata.

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** This video is a recipe tutorial by Ashus Delicacies showing how to cook Hyderabadi Chicken Biryani at home, rather than a review of a specific restaurant or product. If you'd like to order biryani in Vijayawada instead, I can help you find top-rated local restaurants.  
**This branch:** Let me check real sellers, shops and online options near you -- the results appear below. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "hyderabadi biryani near me" → Biryani - Used Kitchen & Other Appliances for sale in India | OLX [used]; Order Online – HYDERABAD BIRYANI POINT [online]; Order The Biryani Life Hyderabadi & Lucknowi Biryani Online in Vijayawada from EatSure [online]; Order Biryani Near Me Vijayawada [online]

### travel (en) -- "Araku valley trip review video"

**Video:** Ultimate Araku Valley Travel Guide: Top Things to Do and See - YouTube -- Let's Discover India (https://www.youtube.com/watch?v=NWiBFTd5aD0)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: Ultimate Araku Valley Travel Guide: Top Things to Do and See - YouTube / Discover the Hidden Gems of Araku Valley: Borra Caves & Anantagiri Waterfalls 🌄Join us on an unforgettable journey to the picturesque landscapes of Araku Va...  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "Ultimate Araku Valley Travel Guide: Top Things to Do and See - YouTube"

**ASKODOX AI (production):** This video by Let's Discover India is titled 'Ultimate Araku Valley Travel Guide: Top Things to Do and See'. According to its description, it covers places like Borra Caves and Anantagiri Waterfalls. Please note, this is the creator's opinion and not verified by ASKODOX as the video content itself has not been analyzed. Details like price, rating, and distance are not provided.

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** Could you please clarify what specific product, item, or service you are asking about?  
**This branch:** Let me check real sellers, shops and online options near you -- the results appear below. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "araku valley trip reviews" → Araku Valley Tour Packages from Vijayawada, Flat 20% Off - Book at Lowest Price [deals]; 5 Araku Valley Tour Packages at ₹6785 pp - Book Online with 20% Off [deals]; Araku Valley Tour Packages from Vijayawada | Araku Valley Packages from Vijayawada | Araku Valley Honeymoon Packages from Vijayawada | Araku Valley Holiday Pack [deals]; Vijayawada To Araku Valley Trains | Book From 6 Trains, Timetable, Fare [online]

### used-item (en) -- "used Royal Enfield Classic 350 review video"

**Video:** The Truth About the Royal Enfield Classic 350 (2025 Review) - YouTube -- Jack Brock (https://www.youtube.com/watch?v=88rgLE_eNJk)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: The Truth About the Royal Enfield Classic 350 (2025 Review) - YouTube / I’m getting sick of over produced 20 minute motorcycle reviews that spend more time showing off cinematic shots than actually talking about the bike.  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "The Truth About the Royal Enfield Classic 350 (2025 Review) - YouTube"

**ASKODOX AI (production):** According to the video description by Jack Brock, this 2025 review focuses on a direct, honest talk about the Royal Enfield Classic 350, avoiding over-produced cinematic shots. Please note that this reflects the creator's opinion and is not verified by ASKODOX. Details like price, rating, and specifications are not provided by the source.

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** The Classic 350 is generally well-regarded for its refined engine, comfortable riding posture, and classic styling, making it a great cruiser for daily commuting and touring. You can check out local pre-owned bike dealerships or official Royal Enfield showrooms in Vijayawada for test rides and availability.  
**This branch:** Let me check real sellers, shops and online options near you -- the results appear below. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "used royal enfield classic 350 near me" → 13 Used Royal Enfield Classic in Vijayawada. Buy from Owners and Dealers - Bikes4Sale [used]; 9 Used Royal Enfield Classic 350 Bikes in Vijayawada - Buy & Sell Second Hand Bikes [deals]; Royal Enfield Classic 350 price in Vijayawada - September 2026 on road price of Classic 350 in Vijayawada [deals]; Used Royal Enfield Classic 350 Bikes in Vijayawada - Second Hand Royal Enfield Classic 350 Bikes for Sale in Vijayawada [used]

### deal (en) -- "iPhone 15 offer review video"

**Video:** iPhone 15 in 2026 - worth it? (Review) - YouTube -- 91Tech (https://www.youtube.com/watch?v=DJ5BkFUoKxg)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: iPhone 15 in 2026 - worth it? (Review) - YouTube / Already over 2 years old and discontinued only recently, the iPhone 15 & 15 Plus are solid midrange smartphones that include modern features like USB-C and t...  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "iPhone 15 in 2026 - worth it? (Review) - YouTube"

**ASKODOX AI (production):** This video by 91Tech covers whether the iPhone 15 is still worth buying in 2026. Note that this reflects the creator's opinion and is not verified by ASKODOX. According to the video description, the iPhone 15 and 15 Plus are solid midrange smartphones featuring USB-C, though they are now over 2 years old and were discontinued recently. Please note that details like price, stock availability, ratings, and exact specifications are not provided by the source.

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** The iPhone 15 offers a great display, strong performance, and USB-C, making it a solid choice if found at a good discount. You can check local electronics stores like Reliance Digital, Bajaj Electronics, or Poorvika in Vijayawada for stock and deals.  
**This branch:** Let me check real sellers, shops and online options near you -- the results appear below. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "iphone 15 offers" → Buy & Sell Second Hand iPhones in Vijayawada, Used Apple Mobile Phones in Vijayawada | OLX [used]; Apple Open Box [surplus]; iPhone 15 is available for less than Rs 35,000 on Vijay Sales, here is how the deal works - India Today [deals]; Buy & Sell Second Hand Iphone in Vijayawada, Used Mobiles in Vijayawada | OLX [used]

### service-te (te) -- "ఏసీ సర్వీస్ వీడియో"

**Video:** Urban Company AC Service Vs Nobroker AC Service 2025 | Which is Best?? - YouTube -- Crazyy Unboxing (https://www.youtube.com/watch?v=KOYoiZG5_3E)

**ASKODOX explain (branch):** ఈ వీడియోను నేను చూడలేదు/విశ్లేషించలేదు. శీర్షిక, క్రియేటర్ ఇచ్చిన వివరణ, ఛానల్ మాత్రమే తెలుసు.  
Quoted from source: Urban Company AC Service Vs Nobroker AC Service 2025 | Which is Best?? - YouTube / Urban Company Vs NoBroker AC Service 🧹❄️ | Full Honest Review | Kaun Jeeta?Bhaiyon aur behno! / 🤭Garmi aayi nahi, AC ki yaad aa gayi!Isliye humne kiya Urban ...  
Label: Creator's opinion -- not verified by ASKODOX

**User:** "Urban Company AC Service Vs Nobroker AC Service 2025 | Which is Best?? - YouTube" గురించి చెప్పండి: ధర, దూరం, నాణ్యత, అందుబాటు, రివ్యూలు

**ASKODOX AI (production):** ఈ వీడియో 'Urban Company vs NoBroker AC Service' పోలిక గురించి 'Crazyy Unboxing' ఛానెల్ వారి అభిప్రాయం. వీడియోలో ధర, నాణ్యత, రివ్యూలు మరియు అందుబాటు గురించిన వివరాలు అందించబడలేదు.

**User (follow-up, same conversation):** ఇది చిన్న గదికి సరిపోతుందా?

**ASKODOX AI:** చిన్న గదికి (సుమారు 100-120 చదరపు అడుగులు) 1 టన్ను AC లేదా సర్వీసింగ్ సరిగ్గా సరిపోతుంది. మీరు ఏ బ్రాండ్ లేదా మోడల్ AC గురించి తెలుసుకోవాలనుకుంటున్నారు?

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
