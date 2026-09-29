# Real video content proof

Generated 2026-09-29T16:47:19Z by `.github/workflows/video-real-content-proof.yml` (run 36599793393).

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
| food | en | 1 | [HYDERABADI CHICKEN DUM BIRYANI RECIPE / हैदराबादी चिकन दम ब…](https://www.youtube.com/watch?v=kYRcu5ZWxbo) | Your Food Lab | yes (official YouTube embed) | Creator's opinion -- not verified by ASKODOX | yes | yes | hyderabadi biryani near me → 5 (deals, used) |
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

**ASKODOX AI (production):** This video by creator Udrawat (their opinion, not verified by ASKODOX) reviews the Samsung 43 Inch Crystal UHD 4K Vision AI TV [2026], featuring 30W Speakers, HDR, and Tizen OS. Details like price, rating, stock, and full specifications are not provided by the source.

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** It offers good 4K picture quality and decent 30W audio for its segment. You can check for availability at local electronics stores like Reliance Digital, Bajaj Electronics, or Vijay Sales in Vijayawada.  
**This branch:** Let me check real sellers, shops and online options near you -- the results appear below. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "samsung 43 inch tv near me" → samsung 43 inches tv | Used TV & DVD & Multimedia in Bangalore | Electronics & Appliances Quikr Bazaar Bangalore [used]; Samsung 43-inch TVs Price List in India (September 2026) [deals]; Second Hand TV - Old TV Latest Price, Manufacturers & Suppliers [used]; Buy Refurbished / Used TV & DVD in Vijayawada | Second Hand TV / Television For Sale Online | QuikrBazaar [used]

### electronics-te (te) -- "శామ్‌సంగ్ 43 అంగుళాల టీవీ రివ్యూ వీడియో"

**Video:** Samsung 43 Inch Crystal UHD 4K Vision AI TV Review [2026] | 30W Speakers, HDR, Tizen OS - YouTube -- Udrawat (https://www.youtube.com/watch?v=cgQhFuIFREs)

**ASKODOX explain (branch):** ఈ వీడియోను నేను చూడలేదు/విశ్లేషించలేదు. శీర్షిక, క్రియేటర్ ఇచ్చిన వివరణ, ఛానల్ మాత్రమే తెలుసు.  
Quoted from source: Samsung 43 Inch Crystal UHD 4K Vision AI TV Review [2026] | 30W Speakers, HDR, Tizen OS - YouTube / Samsung Crystal43": https://link.amazon/B03sWYNpr [Amazon]50": https://link.amazon/B0i2g7kKa [Amazon]55": https://link.amazon/B00Enb8SH [Amazon]65": https://  
Label: Creator's opinion -- not verified by ASKODOX

**User:** "Samsung 43 Inch Crystal UHD 4K Vision AI TV Review [2026] | 30W Speakers, HDR, Tizen OS - YouTube" గురించి చెప్పండి: ధర, దూరం, నాణ్యత, అందుబాటు, రివ్యూలు

**ASKODOX AI (production):** ఈ Samsung 43 Inch Crystal UHD 4K Vision AI TV రివ్యూ వీడియో యూట్యూబర్ Udrawat ద్వారా అందించబడింది (ఇది వారి వ్యక్తిగత అభిప్రాయం, ASKODOX ద్వారా ధృవీకరించబడలేదు). ఈ ఆప్షన్‌కి సంబంధించి ధర, దూరం, నాణ్యత/రివ్యూలు మరియు అందుబాటులో ఉన్న స్టాక్ వివరాలు అందించబడలేదు. మీకు నిర్దిష్ట వివరాలు కావాలంటే అమ్మకందారుడిని అడగమంటారా?

**User (follow-up, same conversation):** ఇది చిన్న గదికి సరిపోతుందా?

**ASKODOX AI:** అవును, 43 అంగుళాల టీవీ 8 నుండి 10 అడుగుల దూరం ఉన్న చిన్న లేదా మధ్యస్థ పరిమాణ గదికి చాలా బాగా సరిపోతుంది.

**Next step:** "samsung 43 inch tv offers" → samsung 43 inches tv | Used TV & DVD & Multimedia in Bangalore | Electronics & Appliances Quikr Bazaar Bangalore [used]; Samsung 43-inch TVs Price List in India (September 2026) [deals]; Second Hand TV - Old TV Latest Price, Manufacturers & Suppliers [used]; Buy Refurbished / Used TV & DVD in Vijayawada | Second Hand TV / Television For Sale Online | QuikrBazaar [used]

### phone (en) -- "Redmi Note 13 Pro review video"

**Video:** Redmi Note 13 Pro Review - Not again! - YouTube -- Izzi Boye (https://www.youtube.com/watch?v=i2FYVv-qa4w)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: Redmi Note 13 Pro Review - Not again! - YouTube / Redmi Note 13 Pro 4G Unboxing and Review **AI PDF Editors with OCR: UPDF - Save 71% Now: https://bit.ly/3UZCRky **Try UPDF AI: https://bit.ly/3IijQSB Redmi N...  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "Redmi Note 13 Pro Review - Not again! - YouTube"

**ASKODOX AI (production):** This video by creator Izzi Boye is titled 'Redmi Note 13 Pro Review - Not again!' and features a 4G unboxing and review. Please note that this is the creator's personal opinion and is not verified by ASKODOX. Specific details like price, ratings, stock, or full technical specifications were not provided in the source.

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** The Redmi Note 13 Pro is generally well-regarded for its display, camera, and fast charging, though performance depends on whether you get the 4G or 5G variant. You can find it locally in Vijayawada at major electronics retailers like Mi Homes, Reliance Digital, or Bajaj Electronics, as well as online on Flipkart and Amazon.  
**This branch:** Let me check real sellers, shops and online options near you -- the results appear below. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "redmi note 13 pro offers" → Buy Old Used Xiaomi Redmi Note 13 Pro 4G Phones Under ... [used]; Open Box Store [surplus]; Redmi Note 13 5G, Note 13 Pro 5G, Note 13 Pro+ 5G goes on sale on Vijay Sales - Times of India [deals]; Buy Refurbished and Second Hand Xiaomi Redmi Note 13 Pro 5G Online at Cashify Store [used]

### vehicle (en) -- "Tata Nexon review video"

**Video:** Tata Nexon 3000 Km Long Term Review: 3 Reasons to Buy, 3 Reasons to Avoid - YouTube -- carandbike (https://www.youtube.com/watch?v=PC-ztrSrDMo)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: Tata Nexon 3000 Km Long Term Review: 3 Reasons to Buy, 3 Reasons to Avoid - YouTube / Our long term Tata Nexon finally went back and after spending 3 months at the car&bike garage we have understood why the subcompact SUV is so much talked abo...  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "Tata Nexon 3000 Km Long Term Review: 3 Reasons to Buy, 3 Reasons to Avoid - YouTube"

**ASKODOX AI (production):** This video by carandbike covers their 3-month long-term review of the Tata Nexon after driving it 3,000 km, highlighting 3 reasons to buy and 3 reasons to avoid it. Please note that this reflects the creator's opinion and is not verified by ASKODOX. Specific vehicle specifications, price, and ratings are not provided in the source.

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** The Tata Nexon is generally considered a solid, feature-packed SUV with a 5-star safety rating, though some users report minor tech glitches. You can visit authorized Tata Motors showrooms in Vijayawada like Select Motors or Jasper Tata to test drive and check local offers.  
**This branch:** Let me check real sellers, shops and online options near you -- the results appear below. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "tata nexon near me" → Tata NEXON Used Cars in Vijayawada | Second Hand Tata NEXON Cars in Vijayawada - Cars24 [used]; Tata Nexon On Road Price in Vijayawada (2026) – ₹8.63 lakh Onwards | Autocar India [surplus]; Tata Nexon May 2026 Offers in Vijayawada - Latest Discount & EMI Offers [deals]; 7+ Used Tata Nexon Cars in Vijayawada - Second Hand Tata Nexon Cars in Vijayawada [used]

### service (en) -- "AC service video"

**Video:** Urban Company AC Service Vs Nobroker AC Service 2025 | Which is Best?? - YouTube -- Crazyy Unboxing (https://www.youtube.com/watch?v=KOYoiZG5_3E)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: Urban Company AC Service Vs Nobroker AC Service 2025 | Which is Best?? - YouTube / Urban Company Vs NoBroker AC Service 🧹❄️ | Full Honest Review | Kaun Jeeta?Bhaiyon aur behno! / 🤭Garmi aayi nahi, AC ki yaad aa gayi!Isliye humne kiya Urban ...  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "Urban Company AC Service Vs Nobroker AC Service 2025 | Which is Best?? - YouTube"

**ASKODOX AI (production):** This video by creator 'Crazyy Unboxing' compares Urban Company and NoBroker AC services in a full honest review to see which is best. Please note that this reflects the creator's personal opinion and is not verified by ASKODOX. Specific details like pricing, ratings, or detailed service specs were not provided in the source description.

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** Yes, both offer reliable AC servicing, though pricing and offer details vary. Since you are in Vijayawada, you can book Urban Company or NoBroker directly through their mobile apps or websites for doorstep service here.  
**This branch:** Let me check real sellers, shops and online options near you -- the results appear below. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "ac service near me" → Professional AC service & repair experts in Vijayawada, India [online]; Split AC Services in Vijayawada [online]; Top AC Service in Vijayawada, Best AC Repair Service in Vijayawada | Sulekha Vijayawada [online]; Top AC Repair Services in Vijayawada - AC Installation - Servicing - Justdial [online]

### food (en) -- "Hyderabadi biryani review video"

**Video:** HYDERABADI CHICKEN DUM BIRYANI RECIPE | हैदराबादी चिकन दम बिरयानी बनाने का तरीका | Chef Sanjyot Keer - YouTube -- Your Food Lab (https://www.youtube.com/watch?v=kYRcu5ZWxbo)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: HYDERABADI CHICKEN DUM BIRYANI RECIPE | हैदराबादी चिकन दम बिरयानी बनाने का तरीका | Chef Sanjyot Keer - YouTube / This is just the beginning of Biryanis of India.Tell me in the comments which biryani you want me to cover next. / I'll be reading every suggestion, and hopefu...  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "HYDERABADI CHICKEN DUM BIRYANI RECIPE | हैदराबादी चिकन दम बिरयानी बनाने का तरीका | Chef Sanjyot Keer - YouTube"

**ASKODOX AI (production):** This video is 'HYDERABADI CHICKEN DUM BIRYANI RECIPE' by Chef Sanjyot Keer from Your Food Lab. Please note that this reflects the creator's opinion and recipe, which is not independently verified by ASKODOX. Details like specific ingredients, preparation times, or ratings were not provided by the source. Let me know if you would like me to find other biryani recipes or details!

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** Are you looking for a specific biryani masala brand, or are you looking to order freshly made Hyderabadi biryani from a restaurant near you in Vijayawada?  
**This branch:** Let me check real sellers, shops and online options near you -- the results appear below. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "hyderabadi biryani near me" → Biryani - Used Kitchen & Other Appliances for sale in India | OLX [used]; Biryani Blues | Order Authentic Hyderabadi Dum Biryani Online [deals]; Order The Biryani Life Hyderabadi & Lucknowi Biryani Online in Vijayawada from EatSure [online]; Order Online – HYDERABAD BIRYANI POINT [online]

### travel (en) -- "Araku valley trip review video"

**Video:** Ultimate Araku Valley Travel Guide: Top Things to Do and See - YouTube -- Let's Discover India (https://www.youtube.com/watch?v=NWiBFTd5aD0)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: Ultimate Araku Valley Travel Guide: Top Things to Do and See - YouTube / Discover the Hidden Gems of Araku Valley: Borra Caves & Anantagiri Waterfalls 🌄Join us on an unforgettable journey to the picturesque landscapes of Araku Va...  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "Ultimate Araku Valley Travel Guide: Top Things to Do and See - YouTube"

**ASKODOX AI (production):** Based on the description from Let's Discover India, this video covers top attractions in Araku Valley, including Borra Caves and Anantagiri Waterfalls. Please note this reflects the creator's opinion and is not verified by ASKODOX. Details like specific ratings, reviews, or prices are not provided by the source.

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** Are you referring to a specific travel package, souvenir, or product related to the Araku Valley guide?  
**This branch:** Let me check real sellers, shops and online options near you -- the results appear below. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "araku valley trip reviews" → Araku Valley Tour Packages from Vijayawada, Flat 20% Off - Book at Lowest Price [deals]; 5 Araku Valley Tour Packages at ₹6785 pp - Book Online with 20% Off [deals]; Araku Valley Tour Packages from Vijayawada | Araku Valley Packages from Vijayawada | Araku Valley Honeymoon Packages from Vijayawada | Araku Valley Holiday Pack [deals]; Vijayawada To Araku Valley Trains | Book From 6 Trains, Timetable, Fare [online]

### used-item (en) -- "used Royal Enfield Classic 350 review video"

**Video:** The Truth About the Royal Enfield Classic 350 (2025 Review) - YouTube -- Jack Brock (https://www.youtube.com/watch?v=88rgLE_eNJk)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: The Truth About the Royal Enfield Classic 350 (2025 Review) - YouTube / I’m getting sick of over produced 20 minute motorcycle reviews that spend more time showing off cinematic shots than actually talking about the bike.  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "The Truth About the Royal Enfield Classic 350 (2025 Review) - YouTube"

**ASKODOX AI (production):** This video by Jack Brock is titled "The Truth About the Royal Enfield Classic 350 (2025 Review)". The creator mentions they are tired of over-produced reviews and want to talk directly about the bike. Please note, this reflects the creator's opinion and is not verified by ASKODOX. Specifics like price, vehicle specifications, or ratings are not provided in the source description.

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** The Classic 350 is known for its strong low-end torque, classic styling, and refined J-series engine, making it a great cruiser if you comfortable with a heavier bike. You can check local multi-brand used bike dealerships or online pre-owned bike platforms in Vijayawada.  
**This branch:** Let me check real sellers, shops and online options near you -- the results appear below. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "used royal enfield classic 350 near me" → 13 Used Royal Enfield Classic in Vijayawada. Buy from Owners and Dealers - Bikes4Sale [used]; 9 Used Royal Enfield Classic 350 Bikes in Vijayawada - Buy & Sell Second Hand Bikes [deals]; Royal Enfield Classic 350 price in Vijayawada - September 2026 on road price of Classic 350 in Vijayawada [deals]; Used Royal Enfield Classic 350 Bikes in Vijayawada - Second Hand Royal Enfield Classic 350 Bikes for Sale in Vijayawada [used]

### deal (en) -- "iPhone 15 offer review video"

**Video:** iPhone 15 in 2026 - worth it? (Review) - YouTube -- 91Tech (https://www.youtube.com/watch?v=DJ5BkFUoKxg)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: iPhone 15 in 2026 - worth it? (Review) - YouTube / Already over 2 years old and discontinued only recently, the iPhone 15 & 15 Plus are solid midrange smartphones that include modern features like USB-C and t...  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "iPhone 15 in 2026 - worth it? (Review) - YouTube"

**ASKODOX AI (production):** This video by 91Tech gives their personal creator opinion on whether the iPhone 15 is still worth buying in 2026. Note that this review is the creator's opinion and not verified by ASKODOX, and the video itself has not been analyzed. Details like exact local pricing, stock, and ratings were not provided by the source.

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** The iPhone 15 offers a great display, strong performance, and solid cameras, making it a great value. You can check availability and pricing at local electronic stores like Reliance Digital, Croma, or Aptronix in Vijayawada.  
**This branch:** Let me check real sellers, shops and online options near you -- the results appear below. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "iphone 15 offers" → Buy & Sell Second Hand iPhones in Vijayawada, Used Apple Mobile Phones in Vijayawada | OLX [used]; Apple Open Box [surplus]; iPhone 15 is available for less than Rs 35,000 on Vijay Sales, here is how the deal works - India Today [deals]; Buy & Sell Second Hand Iphone in Vijayawada, Used Mobiles in Vijayawada | OLX [used]

### service-te (te) -- "ఏసీ సర్వీస్ వీడియో"

**Video:** Urban Company AC Service Vs Nobroker AC Service 2025 | Which is Best?? - YouTube -- Crazyy Unboxing (https://www.youtube.com/watch?v=KOYoiZG5_3E)

**ASKODOX explain (branch):** ఈ వీడియోను నేను చూడలేదు/విశ్లేషించలేదు. శీర్షిక, క్రియేటర్ ఇచ్చిన వివరణ, ఛానల్ మాత్రమే తెలుసు.  
Quoted from source: Urban Company AC Service Vs Nobroker AC Service 2025 | Which is Best?? - YouTube / Urban Company Vs NoBroker AC Service 🧹❄️ | Full Honest Review | Kaun Jeeta?Bhaiyon aur behno! / 🤭Garmi aayi nahi, AC ki yaad aa gayi!Isliye humne kiya Urban ...  
Label: Creator's opinion -- not verified by ASKODOX

**User:** "Urban Company AC Service Vs Nobroker AC Service 2025 | Which is Best?? - YouTube" గురించి చెప్పండి: ధర, దూరం, నాణ్యత, అందుబాటు, రివ్యూలు

**ASKODOX AI (production):** ఈ వీడియో 'Urban Company vs NoBroker AC Service' గురించి 'Crazyy Unboxing' ఛానెల్ వారి అభిప్రాయాన్ని (రివ్యూ) తెలియజేస్తుంది. అయితే ఈ వీడియోలో చెప్పిన విషయాలు సృష్టికర్త యొక్క సొంత అభిప్రాయం మాత్రమే, ASKODOX ద్వారా ధృవీకరించబడలేదు. అలాగే వీడియో ఆధారంగా నిర్దిష్టమైన ధర, దూరం, నాణ్యత లేదా రివ్యూ వివరాలు సమాచారంలో అందించబడలేదు.

**User (follow-up, same conversation):** ఇది చిన్న గదికి సరిపోతుందా?

**ASKODOX AI:** చిన్న గదికి (సుమారు 100-120 చదరపు అడుగులు) సాధారణంగా 1 టన్ను (1 Ton) ఏసీ బాగా సరిపోతుంది. మీ గది పరిమాణాన్ని బట్టి సరైన సర్వీస్ లేదా ఏసీ సామర్థ్యాన్ని ఎంచుకోవచ్చు. మీకు నిర్దిష్టంగా ఏసీ సర్వీసింగ్ కావాలా?

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
