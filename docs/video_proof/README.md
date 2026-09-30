# Real video content proof

Generated 2026-09-30T06:16:08Z by `.github/workflows/video-real-content-proof.yml` (run 36677053441).

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
| home-service | en | 0 (production gave 1) | — | — | — | — | — | — | — |
| food | en | 1 | [Hyderabadi Chicken Biryani / Chicken Biryani Recipe / Resat…](https://www.youtube.com/watch?v=1Nb0khRXiJk) | Ashus Delicacies | yes (official YouTube embed) | Creator's opinion -- not verified by ASKODOX | yes | yes | hyderabadi biryani near me → 5 (deals, used) |
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

**ASKODOX AI (production):** Based on the video title from Udrawat, this 2026 review covers the Samsung 43 Inch Crystal UHD 4K Vision AI TV featuring 30W speakers, HDR support, and Tizen OS. Please note this is the creator's opinion and has not been verified by ASKODOX. Specific facts like price, rating, and stock availability are not provided by the source.

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** It offers good 4K display quality, Tizen OS, and 30W audio for a solid entry-level smart TV experience. Would you like me to help check local electronics store options or search for current deals?  
**This branch:** Let me check real sellers, shops and online options near you -- the results appear below. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "samsung 43 inch tv near me" → samsung 43 inches tv | Used TV & DVD & Multimedia in Bangalore | Electronics & Appliances Quikr Bazaar Bangalore [used]; Samsung 43-inch TVs Price List in India (September 2026) [deals]; Second Hand TV - Old TV Latest Price, Manufacturers & Suppliers [used]; Buy Refurbished / Used TV & DVD in Vijayawada | Second Hand TV / Television For Sale Online | QuikrBazaar [used]

### electronics-te (te) -- "శామ్‌సంగ్ 43 అంగుళాల టీవీ రివ్యూ వీడియో"

**Video:** Samsung 43 Inch Crystal UHD 4K Vision AI TV Review [2026] | 30W Speakers, HDR, Tizen OS - YouTube -- Udrawat (https://www.youtube.com/watch?v=cgQhFuIFREs)

**ASKODOX explain (branch):** ఈ వీడియోను నేను చూడలేదు/విశ్లేషించలేదు. శీర్షిక, క్రియేటర్ ఇచ్చిన వివరణ, ఛానల్ మాత్రమే తెలుసు.  
Quoted from source: Samsung 43 Inch Crystal UHD 4K Vision AI TV Review [2026] | 30W Speakers, HDR, Tizen OS - YouTube / Samsung Crystal43": https://link.amazon/B03sWYNpr [Amazon]50": https://link.amazon/B0i2g7kKa [Amazon]55": https://link.amazon/B00Enb8SH [Amazon]65": https://  
Label: Creator's opinion -- not verified by ASKODOX

**User:** "Samsung 43 Inch Crystal UHD 4K Vision AI TV Review [2026] | 30W Speakers, HDR, Tizen OS - YouTube" గురించి చెప్పండి: ధర, దూరం, నాణ్యత, అందుబాటు, రివ్యూలు

**ASKODOX AI (production):** ఈ Samsung 43 Inch Crystal UHD 4K TV గురించి మీరు అడిగిన ధర, దూరం, అందుబాటు మరియు రివ్యూల వివరాలు ప్రస్తుత వనరు (Udrawat) ద్వారా లభించలేదు. వీడియో టైటిల్ ప్రకారం ఇందులో 30W స్పీకర్లు, HDR, Tizen OS ఉన్నాయి, પરંતુ ఇది క్రియేటర్ అభిప్రాయం మాత్రమే. మీకు ఖచ్చితమైన ధర మరియు అందుబాటు వివరాలు కావాలంటే అమ్మకందారుడిని లేదా షాప్‌ను సంప్రదించి సమాచారం కనుక్కోమంటారా?

**User (follow-up, same conversation):** ఇది చిన్న గదికి సరిపోతుందా?

**ASKODOX AI:** 43 అంగుళాల టీవీకి సుమారు 4 నుండి 6 అడుగుల వీక్షణ దూరం సరిపోతుంది. మీ చిన్న గదిలో అంత దూరం ఉంటే ఇది చాలా బాగా సరిపోతుంది.

**Next step:** "samsung 43 inch tv offers" → samsung 43 inches tv | Used TV & DVD & Multimedia in Bangalore | Electronics & Appliances Quikr Bazaar Bangalore [used]; Samsung 43-inch TVs Price List in India (September 2026) [deals]; Second Hand TV - Old TV Latest Price, Manufacturers & Suppliers [used]; Buy Refurbished / Used TV & DVD in Vijayawada | Second Hand TV / Television For Sale Online | QuikrBazaar [used]

### phone (en) -- "Redmi Note 13 Pro review video"

**Video:** Redmi Note 13 Pro Review - Not again! - YouTube -- Izzi Boye (https://www.youtube.com/watch?v=i2FYVv-qa4w)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: Redmi Note 13 Pro Review - Not again! - YouTube / Redmi Note 13 Pro 4G Unboxing and Review **AI PDF Editors with OCR: UPDF - Save 71% Now: https://bit.ly/3UZCRky **Try UPDF AI: https://bit.ly/3IijQSB Redmi N...  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "Redmi Note 13 Pro Review - Not again! - YouTube"

**ASKODOX AI (production):** This video by creator Izzi Boye is titled "Redmi Note 13 Pro Review - Not again! - YouTube" and covers a 4G unboxing and review of the Redmi Note 13 Pro. Please note that this reflects the creator's personal opinion and is not verified by ASKODOX. Specific details such as price, ratings, availability, or full specifications are not provided by the source.

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** The video highlights creator Izzi Boye's hands-on thoughts, but whether it's worth buying depends on if you want the 4G or 5G version. You can check local electronics stores or online sellers around Vijayawada for local stock.  
**This branch:** Let me check real sellers, shops and online options near you -- the results appear below. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "redmi note 13 pro offers" → Buy Old Used Xiaomi Redmi Note 13 Pro 4G Phones Under ... [used]; Open Box Store [surplus]; Redmi Note 13 5G, Note 13 Pro 5G, Note 13 Pro+ 5G goes on sale on Vijay Sales - Times of India [deals]; Buy Refurbished and Second Hand Xiaomi Redmi Note 13 Pro 5G Online at Cashify Store [used]

### vehicle (en) -- "Tata Nexon review video"

**Video:** Tata Nexon 3000 Km Long Term Review: 3 Reasons to Buy, 3 Reasons to Avoid - YouTube -- carandbike (https://www.youtube.com/watch?v=PC-ztrSrDMo)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: Tata Nexon 3000 Km Long Term Review: 3 Reasons to Buy, 3 Reasons to Avoid - YouTube / Our long term Tata Nexon finally went back and after spending 3 months at the car&bike garage we have understood why the subcompact SUV is so much talked abo...  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "Tata Nexon 3000 Km Long Term Review: 3 Reasons to Buy, 3 Reasons to Avoid - YouTube"

**ASKODOX AI (production):** The video titled 'Tata Nexon 3000 Km Long Term Review: 3 Reasons to Buy, 3 Reasons to Avoid' by carandbike shares the creator's opinion after testing the subcompact SUV over 3 months and 3,000 km. Please note that this reflects carandbike's subjective review and is not verified by ASKODOX. Specific details like pricing, ratings, or full specifications were not provided with this video source.

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** The Tata Nexon is generally considered a solid, feature-rich subcompact SUV with a 5-star safety rating, though performance can vary by variant. To check availability and local pricing in Vijayawada, are you looking for a specific variant or fuel type (Petrol/Diesel/EV)?  
**This branch:** Let me check real sellers, shops and online options near you -- the results appear below. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "tata nexon near me" → Tata NEXON Used Cars in Vijayawada | Second Hand Tata NEXON Cars in Vijayawada - Cars24 [used]; Tata Nexon On Road Price in Vijayawada (2026) – ₹8.63 lakh Onwards | Autocar India [surplus]; Tata Nexon May 2026 Offers in Vijayawada - Latest Discount & EMI Offers [deals]; 7+ Used Tata Nexon Cars in Vijayawada - Second Hand Tata Nexon Cars in Vijayawada [used]

### service (en) -- "AC service video"

**Video:** Urban Company AC Service Vs Nobroker AC Service 2025 | Which is Best?? - YouTube -- Crazyy Unboxing (https://www.youtube.com/watch?v=KOYoiZG5_3E)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: Urban Company AC Service Vs Nobroker AC Service 2025 | Which is Best?? - YouTube / Urban Company Vs NoBroker AC Service 🧹❄️ | Full Honest Review | Kaun Jeeta?Bhaiyon aur behno! / 🤭Garmi aayi nahi, AC ki yaad aa gayi!Isliye humne kiya Urban ...  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "Urban Company AC Service Vs Nobroker AC Service 2025 | Which is Best?? - YouTube"

**ASKODOX AI (production):** This video by Crazyy Unboxing compares Urban Company and NoBroker AC services in an honest review format. Please note that these are the creator's opinions and are not verified by ASKODOX. Specific details like prices, ratings, or availability are not provided in the source.

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** Yes, both offer reliable AC servicing, and you can book through the Urban Company or NoBroker apps directly in Vijayawada. Would you like me to find local AC service specialists instead?  
**This branch:** Let me check real sellers, shops and online options near you -- the results appear below. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "ac service near me" → Professional AC service & repair experts in Vijayawada, India [online]; Split AC Services in Vijayawada [online]; Top AC Service in Vijayawada, Best AC Repair Service in Vijayawada | Sulekha Vijayawada [online]; Top AC Repair Services in Vijayawada - AC Installation - Servicing - Justdial [online]

### food (en) -- "Hyderabadi biryani review video"

**Video:** Hyderabadi Chicken Biryani | Chicken Biryani Recipe | Resaturant Hyderabadi Chicken Biryani - YouTube -- Ashus Delicacies (https://www.youtube.com/watch?v=1Nb0khRXiJk)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: Hyderabadi Chicken Biryani | Chicken Biryani Recipe | Resaturant Hyderabadi Chicken Biryani - YouTube / #chickenbiryani #chickenbiriyani #biryani Hyderabadi Chicken Biryani | Chicken Biryani Recipe | Resaturant Hyderabadi Chicken BiryaniIngredients:Chicken – 1....  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "Hyderabadi Chicken Biryani | Chicken Biryani Recipe | Resaturant Hyderabadi Chicken Biryani - YouTube"

**ASKODOX AI (production):** This video by Ashus Delicacies shows a recipe for Hyderabadi Chicken Biryani, listing ingredients like chicken. Please note, this reflects the creator's opinion and is not verified by ASKODOX. Specific details like ratings or reviews are not provided by the source.

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** As it is a cooking recipe video, there is nothing to buy directly. You can find the ingredients at any local grocery store or supermarket in Vijayawada to prepare it at home.  
**This branch:** Let me check real sellers, shops and online options near you -- the results appear below. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "hyderabadi biryani near me" → Biryani - Used Kitchen & Other Appliances for sale in India | OLX [used]; Biryani Blues | Order Authentic Hyderabadi Dum Biryani Online [deals]; Order The Biryani Life Hyderabadi & Lucknowi Biryani Online in Vijayawada from EatSure [online]; Order Online – HYDERABAD BIRYANI POINT [online]

### travel (en) -- "Araku valley trip review video"

**Video:** Ultimate Araku Valley Travel Guide: Top Things to Do and See - YouTube -- Let's Discover India (https://www.youtube.com/watch?v=NWiBFTd5aD0)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: Ultimate Araku Valley Travel Guide: Top Things to Do and See - YouTube / Discover the Hidden Gems of Araku Valley: Borra Caves & Anantagiri Waterfalls 🌄Join us on an unforgettable journey to the picturesque landscapes of Araku Va...  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "Ultimate Araku Valley Travel Guide: Top Things to Do and See - YouTube"

**ASKODOX AI (production):** According to the video 'Ultimate Araku Valley Travel Guide: Top Things to Do and See' by Let's Discover India, it covers hidden gems of Araku Valley, including Borra Caves and Anantagiri Waterfalls. Please note that this reflects the creator's opinion and is not verified by ASKODOX. Specific details like ratings or reviews are not provided by the source.

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** The video provides a helpful overview of Araku Valley highlights like Borra Caves and Anantagiri Waterfalls. You can watch it directly on YouTube to see if it suits your travel plans.  
**This branch:** Let me check real sellers, shops and online options near you -- the results appear below. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "araku valley trip reviews" → Araku Valley Tour Packages from Vijayawada, Flat 20% Off - Book at Lowest Price [deals]; 5 Araku Valley Tour Packages at ₹6785 pp - Book Online with 20% Off [deals]; Araku Valley Tour Packages from Vijayawada | Araku Valley Packages from Vijayawada | Araku Valley Honeymoon Packages from Vijayawada | Araku Valley Holiday Pack [deals]; Vijayawada To Araku Valley Trains | Book From 6 Trains, Timetable, Fare [online]

### used-item (en) -- "used Royal Enfield Classic 350 review video"

**Video:** The Truth About the Royal Enfield Classic 350 (2025 Review) - YouTube -- Jack Brock (https://www.youtube.com/watch?v=88rgLE_eNJk)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: The Truth About the Royal Enfield Classic 350 (2025 Review) - YouTube / I’m getting sick of over produced 20 minute motorcycle reviews that spend more time showing off cinematic shots than actually talking about the bike.  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "The Truth About the Royal Enfield Classic 350 (2025 Review) - YouTube"

**ASKODOX AI (production):** The video 'The Truth About the Royal Enfield Classic 350 (2025 Review)' is created by Jack Brock. According to the description, it focuses on a direct, practical review without over-produced cinematic shots. Please note that these are the creator's opinions and have not been verified by ASKODOX. Specific details like price, rating, reviews, and detailed motorcycle specifications were not provided in the source.

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** The Classic 350 is generally well-regarded for its refined engine and comfortable ride compared to older models. In Vijayawada, you can find used Royal Enfield bikes at local pre-owned two-wheeler dealerships or online platforms like OLX.  
**This branch:** Let me check real sellers, shops and online options near you -- the results appear below. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "used royal enfield classic 350 near me" → 13 Used Royal Enfield Classic in Vijayawada. Buy from Owners and Dealers - Bikes4Sale [used]; 9 Used Royal Enfield Classic 350 Bikes in Vijayawada - Buy & Sell Second Hand Bikes [deals]; Royal Enfield Classic 350 price in Vijayawada - September 2026 on road price of Classic 350 in Vijayawada [deals]; Used Royal Enfield Classic 350 Bikes in Vijayawada - Second Hand Royal Enfield Classic 350 Bikes for Sale in Vijayawada [used]

### deal (en) -- "iPhone 15 offer review video"

**Video:** iPhone 15 in 2026 - worth it? (Review) - YouTube -- 91Tech (https://www.youtube.com/watch?v=DJ5BkFUoKxg)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: iPhone 15 in 2026 - worth it? (Review) - YouTube / Already over 2 years old and discontinued only recently, the iPhone 15 & 15 Plus are solid midrange smartphones that include modern features like USB-C and t...  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "iPhone 15 in 2026 - worth it? (Review) - YouTube"

**ASKODOX AI (production):** Based on the description from 91Tech, the video discusses whether the iPhone 15 is still worth buying in 2026, noting it as a solid midrange option with features like USB-C, though recently discontinued. Please note this is the creator's opinion and not verified by ASKODOX. Specific details like current price, rating, and stock are not provided by the source. Would you like me to look up specifications or current prices for the iPhone 15?

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** The iPhone 15 remains a solid choice with its A16 Bionic chip, USB-C port, and reliable cameras, though high refresh rate displays are missing. In Vijayawada, you can check availability at authorized Apple resellers like Imagine or Aptronix, or major electronics stores like Reliance Digital.  
**This branch:** Let me check real sellers, shops and online options near you -- the results appear below. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "iphone 15 offers" → Buy & Sell Second Hand iPhones in Vijayawada, Used Apple Mobile Phones in Vijayawada | OLX [used]; Apple Open Box [surplus]; iPhone 15 is available for less than Rs 35,000 on Vijay Sales, here is how the deal works - India Today [deals]; Buy & Sell Second Hand Iphone in Vijayawada, Used Mobiles in Vijayawada | OLX [used]

### service-te (te) -- "ఏసీ సర్వీస్ వీడియో"

**Video:** Urban Company AC Service Vs Nobroker AC Service 2025 | Which is Best?? - YouTube -- Crazyy Unboxing (https://www.youtube.com/watch?v=KOYoiZG5_3E)

**ASKODOX explain (branch):** ఈ వీడియోను నేను చూడలేదు/విశ్లేషించలేదు. శీర్షిక, క్రియేటర్ ఇచ్చిన వివరణ, ఛానల్ మాత్రమే తెలుసు.  
Quoted from source: Urban Company AC Service Vs Nobroker AC Service 2025 | Which is Best?? - YouTube / Urban Company Vs NoBroker AC Service 🧹❄️ | Full Honest Review | Kaun Jeeta?Bhaiyon aur behno! / 🤭Garmi aayi nahi, AC ki yaad aa gayi!Isliye humne kiya Urban ...  
Label: Creator's opinion -- not verified by ASKODOX

**User:** "Urban Company AC Service Vs Nobroker AC Service 2025 | Which is Best?? - YouTube" గురించి చెప్పండి: ధర, దూరం, నాణ్యత, అందుబాటు, రివ్యూలు

**ASKODOX AI (production):** Urban Company మరియు NoBroker AC సర్వీస్‌ల పోలిక వీడియో (Crazyy Unboxing ద్వారా) శీర్షిక ఆధారంగా లభించింది. అయితే, వీటి ధర, దూరం, నాణ్యత, అందుబాటు మరియు రివ్యూలకు సంబంధించిన స్పష్టమైన వివరాలు అందించబడలేదు. ఇది క్రియేటర్ యొక్క వ్యక్తిగత అభిప్రాయం మాత్రమే, ASKODOX ద్వారా ధృవీకరించబడలేదు.

**User (follow-up, same conversation):** ఇది చిన్న గదికి సరిపోతుందా?

**ASKODOX AI:** చిన్న గదికి (సుమారు 100-120 చదరపు అడుగులు) 1 టన్ను AC సరిగ్గా సరిపోతుంది. మీరు ఏ బ్రాండ్ లేదా మోడల్ చూస్తున్నారో చెబితే మరిన్ని వివరాలు అందిస్తాను.

**Next step:** "ac service near me" → Professional AC service & repair experts in Vijayawada, India [online]; Split AC Services in Vijayawada [online]; Top AC Service in Vijayawada, Best AC Repair Service in Vijayawada | Sulekha Vijayawada [online]; Top AC Repair Services in Vijayawada - AC Installation - Servicing - Justdial [online]

## Attribution (branch Command Center)

Video funnel: video_impression 10, video_open 10, video_watch_start 10, video_watch_complete 0, video_ask 10, video_product_click 4, video_service_click 2, video_local_search 4, video_affiliate_click 0, video_contact 0, lead 0, order 0, conversion 0

Commerce funnel: search 11, impression 0, result_view 0, click 10, claim 0, lead 0, order 0, payment 0, redemption 0, conversion 0, commission 0

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
