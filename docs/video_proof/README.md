# Real video content proof

Generated 2026-09-30T12:31:09Z by `.github/workflows/video-real-content-proof.yml` (run 36714834307).

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
| used-item | en | 1 | [Royal Enfield Classic 350 tested - YouTube](https://www.youtube.com/watch?v=C_4YStQscrc) | bikerdood1100 | yes (official YouTube embed) | Creator's opinion -- not verified by ASKODOX | yes | yes | used royal enfield classic 350 near me → 6 (deals, used) |
| deal | en | 1 | [iPhone 15 in 2026 - worth it? (Review) - YouTube](https://www.youtube.com/watch?v=DJ5BkFUoKxg) | 91Tech | yes (official YouTube embed) | Creator's opinion -- not verified by ASKODOX | yes | yes | iphone 15 offers → 6 (deals, surplus, used) |
| service-te | te | 1 | [Urban Company AC Service Vs Nobroker AC Service 2025 / Whic…](https://www.youtube.com/watch?v=KOYoiZG5_3E) | Crazyy Unboxing | yes (official YouTube embed) | Creator's opinion -- not verified by ASKODOX | yes | yes | ac service near me → 4 () |

## Conversations (real AI answers)

### electronics (en) -- "Samsung 43 inch TV review videos"

**Video:** Samsung 43 Inch Crystal UHD 4K Vision AI TV Review [2026] | 30W Speakers, HDR, Tizen OS - YouTube -- Udrawat (https://www.youtube.com/watch?v=cgQhFuIFREs)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: Samsung 43 Inch Crystal UHD 4K Vision AI TV Review [2026] | 30W Speakers, HDR, Tizen OS - YouTube / Samsung Crystal43": https://link.amazon/B03sWYNpr [Amazon]50": https://link.amazon/B0i2g7kKa [Amazon]55": https://link.amazon/B00Enb8SH [Amazon]65": https://  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "Samsung 43 Inch Crystal UHD 4K Vision AI TV Review [2026] | 30W Speakers, HDR, Tizen OS - YouTube"

**ASKODOX AI (production):** This video by Udrawat reviews the Samsung 43 Inch Crystal UHD 4K Vision AI TV [2026], featuring 30W speakers, HDR support, and Tizen OS. Please note that these are the creator's opinions and not verified by ASKODOX. Specific details like price, stock, and ratings are not provided by the source.

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** Yes, it is generally considered a good budget 4K TV for its display quality and 30W sound output. Would you like me to help you find nearby electronics stores in Vijayawada or check online availability?  
**This branch:** Let me check real sellers, shops and online options near you -- the results appear below. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "samsung 43 inch tv near me" → samsung 43 inches tv | Used TV & DVD & Multimedia in Bangalore | Electronics & Appliances Quikr Bazaar Bangalore [used]; Samsung 43-inch TVs Price List in India (September 2026) [deals]; Second Hand TV - Old TV Latest Price, Manufacturers & Suppliers [used]; Buy Refurbished / Used TV & DVD in Vijayawada | Second Hand TV / Television For Sale Online | QuikrBazaar [used]

### electronics-te (te) -- "శామ్‌సంగ్ 43 అంగుళాల టీవీ రివ్యూ వీడియో"

**Video:** Samsung 43 Inch Crystal UHD 4K Vision AI TV Review [2026] | 30W Speakers, HDR, Tizen OS - YouTube -- Udrawat (https://www.youtube.com/watch?v=cgQhFuIFREs)

**ASKODOX explain (branch):** ఈ వీడియోను నేను చూడలేదు/విశ్లేషించలేదు. శీర్షిక, క్రియేటర్ ఇచ్చిన వివరణ, ఛానల్ మాత్రమే తెలుసు.  
Quoted from source: Samsung 43 Inch Crystal UHD 4K Vision AI TV Review [2026] | 30W Speakers, HDR, Tizen OS - YouTube / Samsung Crystal43": https://link.amazon/B03sWYNpr [Amazon]50": https://link.amazon/B0i2g7kKa [Amazon]55": https://link.amazon/B00Enb8SH [Amazon]65": https://  
Label: Creator's opinion -- not verified by ASKODOX

**User:** "Samsung 43 Inch Crystal UHD 4K Vision AI TV Review [2026] | 30W Speakers, HDR, Tizen OS - YouTube" గురించి చెప్పండి: ధర, దూరం, నాణ్యత, అందుబాటు, రివ్యూలు

**ASKODOX AI (production):** ఈ వీడియో శామ్‌సంగ్ 43 ఇంచ్ క్రిస్టల్ UHD 4K విజన్ AI TV రివ్యూ గురించి డ్రియేటర్ Udrawat గారి అభిప్రాయం సూచిస్తుంది (ఇది ASKODOX ద్వారా ధృవీకరించబడలేదు). లభించిన వివరాల ప్రకారం ధర, దూరం, అందుబాటు మరియు రివ్యూలకు సంబంధించిన సమాచారం అందుబాటులో లేదు.

**User (follow-up, same conversation):** ఇది చిన్న గదికి సరిపోతుందా?

**ASKODOX AI:** అవును, 43 అంగుళాల TV చిన్న నుండి రకంబోలా గదికి (సుమారు 8-10 అడుగుల వీక్షణ దూరానికి) సరిగ్గా సరిపోతుంది.

**Next step:** "samsung 43 inch tv offers" → samsung 43 inches tv | Used TV & DVD & Multimedia in Bangalore | Electronics & Appliances Quikr Bazaar Bangalore [used]; Samsung 43-inch TVs Price List in India (September 2026) [deals]; Second Hand TV - Old TV Latest Price, Manufacturers & Suppliers [used]; Buy Refurbished / Used TV & DVD in Vijayawada | Second Hand TV / Television For Sale Online | QuikrBazaar [used]

### phone (en) -- "Redmi Note 13 Pro review video"

**Video:** Redmi Note 13 Pro Review - Not again! - YouTube -- Izzi Boye (https://www.youtube.com/watch?v=i2FYVv-qa4w)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: Redmi Note 13 Pro Review - Not again! - YouTube / Redmi Note 13 Pro 4G Unboxing and Review **AI PDF Editors with OCR: UPDF - Save 71% Now: https://bit.ly/3UZCRky **Try UPDF AI: https://bit.ly/3IijQSB Redmi N...  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "Redmi Note 13 Pro Review - Not again! - YouTube"

**ASKODOX AI (production):** This video by Izzi Boye is titled 'Redmi Note 13 Pro Review - Not again!' and features a 4G unboxing and review. Please note that this reflects the creator's personal opinion and has not been verified by ASKODOX. Specific details such as price, ratings, and full specifications were not provided in the source.

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** The Redmi Note 13 Pro offers strong display and camera performance for its segment, making it a solid choice if those are your priorities. You can check local electronics retailers like Sangeetha Gadgets, Poorvika, or Bajaj Electronics in Vijayawada, or order it online via Mi.com, Amazon, or Flipkart.  
**This branch:** Let me check real sellers, shops and online options near you -- the results appear below. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "redmi note 13 pro offers" → Buy Old Used Xiaomi Redmi Note 13 Pro 4G Phones Under ... [used]; Open Box Store [surplus]; Redmi Note 13 5G, Note 13 Pro 5G, Note 13 Pro+ 5G goes on sale on Vijay Sales - Times of India [deals]; Buy Refurbished and Second Hand Xiaomi Redmi Note 13 Pro 5G Online at Cashify Store [used]

### vehicle (en) -- "Tata Nexon review video"

**Video:** Tata Nexon 3000 Km Long Term Review: 3 Reasons to Buy, 3 Reasons to Avoid - YouTube -- carandbike (https://www.youtube.com/watch?v=PC-ztrSrDMo)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: Tata Nexon 3000 Km Long Term Review: 3 Reasons to Buy, 3 Reasons to Avoid - YouTube / Our long term Tata Nexon finally went back and after spending 3 months at the car&bike garage we have understood why the subcompact SUV is so much talked abo...  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "Tata Nexon 3000 Km Long Term Review: 3 Reasons to Buy, 3 Reasons to Avoid - YouTube"

**ASKODOX AI (production):** This video by carandbike covers a 3-month, 3000 km long-term review of the Tata Nexon, discussing three reasons to buy and three reasons to avoid it. Please note that this reflects the creator's opinion and is not verified by ASKODOX. Specific details like vehicle price, ratings, or specifications are not provided in the source.

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** The Tata Nexon is widely appreciated for its 5-star safety rating, strong build quality, and feature-packed interior, though some users report minor tech glitches and inconsistent service center experiences. In Vijayawada, you can test drive and buy it at authorized Tata Motors showrooms like Jasper Tata or Lakshmi Tata.  
**This branch:** Let me check real sellers, shops and online options near you -- the results appear below. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "tata nexon near me" → Tata NEXON Used Cars in Vijayawada | Second Hand Tata NEXON Cars in Vijayawada - Cars24 [used]; Tata Nexon On Road Price in Vijayawada (2026) – ₹8.63 lakh Onwards | Autocar India [surplus]; Tata Nexon May 2026 Offers in Vijayawada - Latest Discount & EMI Offers [deals]; 7+ Used Tata Nexon Cars in Vijayawada - Second Hand Tata Nexon Cars in Vijayawada [used]

### service (en) -- "AC service video"

**Video:** Urban Company AC Service Vs Nobroker AC Service 2025 | Which is Best?? - YouTube -- Crazyy Unboxing (https://www.youtube.com/watch?v=KOYoiZG5_3E)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: Urban Company AC Service Vs Nobroker AC Service 2025 | Which is Best?? - YouTube / Urban Company Vs NoBroker AC Service 🧹❄️ | Full Honest Review | Kaun Jeeta?Bhaiyon aur behno! / 🤭Garmi aayi nahi, AC ki yaad aa gayi!Isliye humne kiya Urban ...  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "Urban Company AC Service Vs Nobroker AC Service 2025 | Which is Best?? - YouTube"

**ASKODOX AI (production):** The video 'Urban Company AC Service Vs Nobroker AC Service 2025 | Which is Best??' by Crazyy Unboxing provides the creator's honest review comparing both AC services. Note that this reflects the creator's opinion and is not verified by ASKODOX. Specific details like exact prices, ratings, or current availability are not provided by the source.

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** Both services offer doorstep AC maintenance, but quality depends on the local technician. Would you like to book an AC service through ASKODOX or compare local pricing first?  
**This branch:** Let me check real sellers, shops and online options near you -- the results appear below. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "ac service near me" → Professional AC service & repair experts in Vijayawada, India [online]; Split AC Services in Vijayawada [online]; Top AC Service in Vijayawada, Best AC Repair Service in Vijayawada | Sulekha Vijayawada [online]; Top AC Repair Services in Vijayawada - AC Installation - Servicing - Justdial [online]

### food (en) -- "Hyderabadi biryani review video"

**Video:** Hyderabadi Chicken Biryani | Chicken Biryani Recipe | Resaturant Hyderabadi Chicken Biryani - YouTube -- Ashus Delicacies (https://www.youtube.com/watch?v=1Nb0khRXiJk)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: Hyderabadi Chicken Biryani | Chicken Biryani Recipe | Resaturant Hyderabadi Chicken Biryani - YouTube / #chickenbiryani #chickenbiriyani #biryani Hyderabadi Chicken Biryani | Chicken Biryani Recipe | Resaturant Hyderabadi Chicken BiryaniIngredients:Chicken – 1....  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "Hyderabadi Chicken Biryani | Chicken Biryani Recipe | Resaturant Hyderabadi Chicken Biryani - YouTube"

**ASKODOX AI (production):** This video by Ashus Delicacies is titled 'Hyderabadi Chicken Biryani | Chicken Biryani Recipe | Resaturant Hyderabadi Chicken Biryani'. The description lists basic ingredients like chicken, but please note that this recipe and method reflect the creator's opinion and have not been verified by ASKODOX. Specific details such as full preparation steps, ratings, or reviews are not provided in the source metadata.

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** Are you looking to buy cooked Hyderabadi chicken biryani from a restaurant, or ingredients/masala to make this specific recipe at home?  
**This branch:** Let me check real sellers, shops and online options near you -- the results appear below. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "hyderabadi biryani near me" → Biryani - Used Kitchen & Other Appliances for sale in India | OLX [used]; Biryani Blues | Order Authentic Hyderabadi Dum Biryani Online [deals]; Order The Biryani Life Hyderabadi & Lucknowi Biryani Online in Vijayawada from EatSure [online]; Order Online – HYDERABAD BIRYANI POINT [online]

### travel (en) -- "Araku valley trip review video"

**Video:** Ultimate Araku Valley Travel Guide: Top Things to Do and See - YouTube -- Let's Discover India (https://www.youtube.com/watch?v=NWiBFTd5aD0)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: Ultimate Araku Valley Travel Guide: Top Things to Do and See - YouTube / Discover the Hidden Gems of Araku Valley: Borra Caves & Anantagiri Waterfalls 🌄Join us on an unforgettable journey to the picturesque landscapes of Araku Va...  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "Ultimate Araku Valley Travel Guide: Top Things to Do and See - YouTube"

**ASKODOX AI (production):** This travel guide by Let's Discover India covers highlights like the Borra Caves and Anantagiri Waterfalls. Note that these details reflect the creator's opinion and are not verified by ASKODOX. Specific details such as ratings, reviews, or full video transcript are not provided by the source.

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** The travel guide is a YouTube video, so it's free to watch online. You can view it directly on YouTube to see if the itinerary works for you.  
**This branch:** Let me check real sellers, shops and online options near you -- the results appear below. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "araku valley trip reviews" → Araku Valley Tour Packages from Vijayawada, Flat 20% Off - Book at Lowest Price [deals]; 5 Araku Valley Tour Packages at ₹6785 pp - Book Online with 20% Off [deals]; Araku Valley Tour Packages from Vijayawada | Araku Valley Packages from Vijayawada | Araku Valley Honeymoon Packages from Vijayawada | Araku Valley Holiday Pack [deals]; Vijayawada To Araku Valley Trains | Book From 6 Trains, Timetable, Fare [online]

### used-item (en) -- "used Royal Enfield Classic 350 review video"

**Video:** Royal Enfield Classic 350 tested - YouTube -- bikerdood1100 (https://www.youtube.com/watch?v=C_4YStQscrc)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: Royal Enfield Classic 350 tested - YouTube / This time I take a quick spin on Royal Enfield Classic 350.Is it a good replacement for my old Bullet?  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "Royal Enfield Classic 350 tested - YouTube"

**ASKODOX AI (production):** The video titled 'Royal Enfield Classic 350 tested' by creator bikerdood1100 features a quick spin on the Classic 350 to see if it's a good replacement for an older Bullet. Please note that this is the creator's personal opinion and not verified by ASKODOX. Specific details such as price, ratings, reviews, or specifications were not provided in the source.

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** The Royal Enfield Classic 350 offers strong resale value and refined performance. You can check local used bike dealerships or trusted multi-brand pre-owned two-wheeler outlets in Vijayawada.  
**This branch:** Let me check real sellers, shops and online options near you -- the results appear below. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "used royal enfield classic 350 near me" → 13 Used Royal Enfield Classic in Vijayawada. Buy from Owners and Dealers - Bikes4Sale [used]; 9 Used Royal Enfield Classic 350 Bikes in Vijayawada - Buy & Sell Second Hand Bikes [deals]; Royal Enfield Classic 350 price in Vijayawada - September 2026 on road price of Classic 350 in Vijayawada [deals]; Used Royal Enfield Classic 350 Bikes in Vijayawada - Second Hand Royal Enfield Classic 350 Bikes for Sale in Vijayawada [used]

### deal (en) -- "iPhone 15 offer review video"

**Video:** iPhone 15 in 2026 - worth it? (Review) - YouTube -- 91Tech (https://www.youtube.com/watch?v=DJ5BkFUoKxg)

**ASKODOX explain (branch):** I haven't watched or analyzed this video. I only know its title, the description the creator wrote and the channel.  
Quoted from source: iPhone 15 in 2026 - worth it? (Review) - YouTube / Already over 2 years old and discontinued only recently, the iPhone 15 & 15 Plus are solid midrange smartphones that include modern features like USB-C and t...  
Label: Creator's opinion -- not verified by ASKODOX

**User:** Tell me more about "iPhone 15 in 2026 - worth it? (Review) - YouTube"

**ASKODOX AI (production):** The video 'iPhone 15 in 2026 - worth it?' by 91Tech discusses the iPhone 15 & 15 Plus as solid midrange smartphones with modern features like USB-C, noting they were discontinued recently. Please note this is the creator's opinion and not verified by ASKODOX. Specific details like price, stock, and ratings were not provided by the source.

**User (follow-up, same conversation):** Is it worth buying, and where can I get it here?

**Production (main) AI:** The iPhone 15 offers a great balance of performance, USB-C, and modern cameras, making it worth buying if priced well. In Vijayawada, you can check availability at Apple Authorised Resellers like Aptronix or Imagine, as well as Reliance Digital or Croma.  
**This branch:** Let me check real sellers, shops and online options near you -- the results appear below. (action `find_local`: the real options below are the answer; shop names never come from the AI's memory)

**Next step:** "iphone 15 offers" → Buy & Sell Second Hand iPhones in Vijayawada, Used Apple Mobile Phones in Vijayawada | OLX [used]; Vijay Sales Open Box Sale Starts On iPhones, iPads, and More Gadgets; See Details - Times Bull [surplus]; iPhone 15 is available for less than Rs 35,000 on Vijay Sales, here is how the deal works - India Today [deals]; Buy & Sell Second Hand Iphone in Vijayawada, Used Mobiles in Vijayawada | OLX [used]

### service-te (te) -- "ఏసీ సర్వీస్ వీడియో"

**Video:** Urban Company AC Service Vs Nobroker AC Service 2025 | Which is Best?? - YouTube -- Crazyy Unboxing (https://www.youtube.com/watch?v=KOYoiZG5_3E)

**ASKODOX explain (branch):** ఈ వీడియోను నేను చూడలేదు/విశ్లేషించలేదు. శీర్షిక, క్రియేటర్ ఇచ్చిన వివరణ, ఛానల్ మాత్రమే తెలుసు.  
Quoted from source: Urban Company AC Service Vs Nobroker AC Service 2025 | Which is Best?? - YouTube / Urban Company Vs NoBroker AC Service 🧹❄️ | Full Honest Review | Kaun Jeeta?Bhaiyon aur behno! / 🤭Garmi aayi nahi, AC ki yaad aa gayi!Isliye humne kiya Urban ...  
Label: Creator's opinion -- not verified by ASKODOX

**User:** "Urban Company AC Service Vs Nobroker AC Service 2025 | Which is Best?? - YouTube" గురించి చెప్పండి: ధర, దూరం, నాణ్యత, అందుబాటు, రివ్యూలు

**ASKODOX AI (production):** ఈ వీడియో అర్బన్ కంపెనీ మరియు నోబ్రోకర్ ఏసీ సర్వీసుల మధ్య పోలిక మరియు రివ్యూ గురించి చర్చిస్తుంది. ఇది 'Crazyy Unboxing' ఛానెల్ వారి వ్యక్తిగత అభిప్రాయం మాత్రమే. ఈ వీడియో వివరాల్లో ధర, దూరం, అందుబాటు మరియు రివ్యూల సమాచారం సరిగ్గా ఇవ్వబడలేదు.

**User (follow-up, same conversation):** ఇది చిన్న గదికి సరిపోతుందా?

**ASKODOX AI:** చిన్న గదికి (సుమారు 100-120 చదరపు అడుగులు) 1 టన్ను ఏసీ సరిగ్గా సరిపోతుంది. మీరు సర్వీసింగ్ కోసం చూస్తున్నారా లేదా క్రొత్త ఏసీ బుక్ చేయాలనుకుంటున్నారా?

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
