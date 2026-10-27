"""ONE map of the Command Center console (/admin/console).

Main heading -> category -> page, each page exactly once (no duplicates).
Owner rule (2026-10-27): every name and guide line is ONE mixed Telugu-English
text, the way the team speaks ("Payment స్థితి", "Orders చూడండి") -- business /
tech words stay English, actions / status / warnings in simple Telugu. Never an
English line plus a Telugu copy of it. The console draws its sidebar, the home
grid, the section grids, the breadcrumbs, the page search and the per-page guide
from this list only.

A page is either a console view (``view``, drawn by a JS function of the same
name, gated by ``perm``) or a schema resource (``res``; its permission comes
from the platform schema). ``tests/test_admin_console_nav.py`` checks that
every console view and every schema resource is listed exactly once.
"""
from __future__ import annotations

from typing import Any, Dict, List


def _v(view: str, perm: str, label: str, what: str, do: str) -> Dict[str, str]:
    return {"id": view, "perm": perm, "label": label, "what": what, "do": do}


def _r(res: str, label: str, what: str, do: str) -> Dict[str, str]:
    return {"id": "r:" + res, "res": res, "label": label, "what": what, "do": do}


def _cat(label: str, items: List[Dict[str, str]]) -> Dict[str, Any]:
    return {"label": label, "items": items}


NAV: List[Dict[str, Any]] = [
    {"id": "today", "icon": "⭐", "color": "#5b3df5", "label": "ఈరోజు పని",
     "what": "ఇక్కడ మొదలుపెట్టండి: ఇప్పుడు మీరు చూడాల్సినవి.",
     "cats": [
         _cat("ఇక్కడ మొదలుపెట్టండి", [
             _v("dashboard", "overview:view", "Dashboard",
                "మొత్తం platform live లెక్కలు: కొనేవాళ్ళు, అమ్మేవాళ్ళు, requests, ఆదాయం, alerts.",
                "ముందు Alerts card చూడండి; ప్రతి warning కి ఇచ్చిన పేజీ open చేయండి."),
             _v("workqueue", "overview:view", "నా Work Queue",
                "నిజమైన records నుండి లెక్కించిన మీ పని: ఎరుపు = వెంటనే, orange = త్వరలో.",
                "ఎరుపు వాటితో మొదలుపెట్టండి. 'ఇది వివరించు' నొక్కితే ఏమైంది, ఎందుకు, ఏం చేయాలో చెబుతుంది."),
             _v("approvals", "approvals:view", "Approval కోసం ఆగినవి",
                "జరగడానికి ముందు owner / manager OK కోసం ఆగి ఉన్న మార్పులు.",
                "ఒక్కొక్కటి open చేసి, మార్పు చదివి, Approve లేదా Reject చేయండి."),
             _v("assistant", "overview:view", "Admin Assistant ని అడగండి",
                "English లేదా తెలుగులో అడగండి; సమాధానాలు record అయిన డేటా నుండే వస్తాయి.",
                "'ఏవి review కావాలి?' లాంటి ప్రశ్న type చేయండి. command screen మాత్రమే తెరుస్తుంది; మీరు confirm చేయకుండా ఏదీ save కాదు."),
         ]),
     ]},
    {"id": "insights", "icon": "📊", "color": "#0e9384", "label": "Analytics & సూచనలు",
     "what": "లెక్కలు, trends, ఏది ఎందుకు పెరిగింది / తగ్గింది.",
     "cats": [
         _cat("లెక్కలు", [
             _v("analytics", "analytics:view", "Analytics",
                "రోజు, category, ఊరు వారీగా searches, requests, orders మరియు funnel.",
                "పైన days / category / place ఎంచుకోండి. రెండు funnel steps మధ్య పెద్ద తగ్గుదల = అక్కడ జనం వదిలేస్తున్నారు."),
             _v("outcomes", "analytics:view", "Outcomes & లోటులు",
                "Customers అడిగినా మనం ఇవ్వలేకపోయినవి.",
                "ఆ లోటుల కోసం sellers ని పిలవండి లేదా catalogue లో items చేర్చండి."),
             _v("eadash", "early_access:view", "Early Access Dashboard",
                "Testers app ఎలా వాడుతున్నారు, వాళ్ళ feedback, app errors.",
                "కొత్త feedback రోజూ చదవండి; మళ్ళీ మళ్ళీ వచ్చే errors ని incidents పేజీలో చూడండి."),
             _v("events", "analytics:view", "Events వరుస",
                "ఇటీవలి platform events వరుస (search, request, order...).",
                "ఒక flow నిజంగా జరిగిందో లేదో చూడటానికి; మామూలుగా Analytics పేజీ చాలు."),
         ]),
         _cat("AI సూచనలు", [
             _v("insights", "insights:view", "AI సూచనలు",
                "తీవ్రత, నమ్మకం, కారణం కావచ్చు, ఏం చేయాలి — ఇవన్నీ ఉన్న సూచనలు.",
                "ముందు HIGH వాటిపై పని చేయండి. 'Possible reason' నిరూపణ కాదు - evidence చూడండి."),
             _v("demand", "demand:view", "Demand సమాచారం",
                "ఊరు, budget వారీగా జనం ఎక్కువగా వెతికేవి, ఏ sellers కి alert వెళ్ళింది.",
                "Demand ఎక్కువ, sellers తక్కువ ఉన్నవి చూసి sellers ని పిలవండి."),
             _r("demand_alert_rules", "Demand Alert Rules",
                "Demand alert ఎప్పుడు, ఎవరికి వెళ్ళాలి (cooldown, రోజుకు max తో).",
                "Rule స్ తక్కువగా, స్పష్టంగా ఉంచండి; మార్చాక Demand intelligence చూడండి."),
         ]),
         _cat("Search ఫలితాలు", [
             _v("resultdiag", "requests:view", "Results పరిశీలన",
                "ఒక search లో result ఎందుకు వచ్చింది / రాలేదు: sources, filters, ranking.",
                "Customer మాటలు type చేయండి; 'rejected' లో ఏది ఎందుకు తీసేశారో చూడండి."),
         ]),
     ]},
    {"id": "money", "icon": "💰", "color": "#039855", "label": "డబ్బు & Payments",
     "what": "ఆదాయం, చెల్లింపులు, commissions, rewards, plans.",
     "cats": [
         _cat("Revenue", [
             _v("revcmd", "revenue:view", "Revenue Command Center",
                "Partner, source వారీగా confirmed + paid ఆదాయం, 'ఎందుకు పెరిగింది / తగ్గింది' తో.",
                "CONFIRMED వాటిని నమ్మండి; POSSIBLE వాటిని check చేసి తర్వాతే పని చేయండి."),
             _v("ledger", "finance:view", "Revenue Ledger",
                "Record అయిన ప్రతి ఆదాయ entry, కొత్తది ముందు. Entries ఎప్పుడూ మార్చబడవు.",
                "తప్పు ఉంటే సరిచేసే entry వేయండి, delete చేయకండి."),
             _v("transactions", "finance:view", "అన్ని Transactions",
                "అన్ని డబ్బు లావాదేవీలు ఒకే list లో: orders, refunds, settlements.",
                "State తో filter చేయండి; FAILED / DISPUTED వాటిని follow-up చేయండి."),
         ]),
         _cat("Payments", [
             _v("payments", "payments:view", "Payment స్థితి",
                "Customer చెల్లింపులు, gateway నుండి వచ్చిన నిజమైన స్థితి.",
                "PAID అంటేనే డబ్బు వచ్చింది. QR చూపించడం payment కాదు."),
             _v("billingadmin", "growth:view", "Billing, Gateways & Push",
                "Razorpay / Cashfree setup, TEST లేదా LIVE mode, push settings.",
                "Key మార్చిన ప్రతిసారీ gateway check చేయండి. LIVE కి owner server approval కావాలి."),
             _v("aicredits", "growth:view", "AI Credits",
                "Pay-as-you-go AI: charging switch, ఒక్కో AI వాడకానికి రేటు (paise), రోజుకు ఉచిత వాడకాలు, ledger totals.",
                "నిజమైన AI + GST + gateway ఖర్చు చూశాకే రేట్లు పెట్టండి. Packs ని Plans లో (audience ai_credits) sale లో పెట్టండి."),
         ]),
         _cat("Commissions & Rewards", [
             _v("commissions", "commissions:view", "Commission Dashboard",
                "Affiliate commissions: expected, confirmed, paid. Clicks ని sales గా లెక్కించం.",
                "Partner reports / postbacks import చేయండి; OVERDUE వాటిని follow-up చేయండి."),
             _v("rewards", "rewards:view", "Rewards Ledger",
                "Customer rewards: పని పూర్తయ్యాకే వస్తాయి, approval తర్వాతే pay.",
                "Approve చేసి, నిజంగా pay చేశాకే PAID పెట్టండి."),
         ]),
         _cat("Plans", [
             _v("plansadmin", "growth:view", "Plans & ధరలు",
                "Buyers, sellers, partners కోసం subscription plans.",
                "Live pricing ఆన్ చేసినప్పుడే paid plans అమ్మకానికి వస్తాయి."),
             _r("subscription_promos", "Subscription ఆఫర్లు",
                "Plans పై discounts, trial offers.",
                "Start / end తేదీలు పెట్టండి; గడువు అయిపోతే అదే ఆగిపోతుంది."),
             _v("radioadmin", "growth:view", "Travel Radio (Test మాత్రమే)",
                "Travel Radio add-on అంతర్గత test; అమ్మకానికి లేదు.",
                "Testers కి PROMOTIONAL passes మాత్రమే ఇవ్వండి."),
         ]),
     ]},
    {"id": "growth", "icon": "📣", "color": "#dd2590", "label": "Growth & Offers",
     "what": "Ads, offers, referrals, affiliate links — అన్నీ ఇక్కడే.",
     "cats": [
         _cat("Ads & Campaigns", [
             _v("sponsored", "sponsored:view", "Sponsored Campaigns",
                "Results లో చూపించే paid ads, budget మరియు reach తో.",
                "Budget, end date చూడండి; clicks రాని campaign ని pause చేయండి."),
             _r("promotion_campaigns", "Targeted Promotions",
                "ఎంచుకున్న users గుంపుకు సందేశాలు (role, ఊరు, ఆసక్తి వారీగా).",
                "Audience చిన్నగా, సంబంధితంగా ఉంచండి; users వీటిని ఆపేయగలరు."),
         ]),
         _cat("Offers", [
             _v("benefits", "growth:view", "Offers & Coupons",
                "Customers కి చూపించే verified offers, cashback, Scratch & Reveal.",
                "బయటి offer చూపించాలంటే దాని source link, verified తేదీ కావాలి."),
             _r("merchant_offers", "Shop ఆఫర్లు",
                "Sellers / shops తమ items కోసం పెట్టిన offers.",
                "కొత్తవి review చేయండి; తప్పుదారి పట్టించే ధరలను reject చేయండి."),
         ]),
         _cat("Referrals", [
             _v("referrals", "growth:view", "Referrals",
                "ఎవరు ఎవరిని పిలిచారు, ఏ invites నిజమైన users అయ్యాయి.",
                "ఒకే నంబర్ నుండి చాలా invites ఉంటే - దుర్వినియోగం కావచ్చు."),
             _r("referral_credit_rules", "Referral Credit Rules",
                "ఒక invite కి ఎంత credit, ఎప్పుడు వస్తుంది.",
                "కొత్త invites కే rule మార్చండి; పాతవి వాటి rule తోనే ఉంటాయి."),
         ]),
         _cat("Affiliate Links", [
             _r("affiliate_programs", "Affiliate Programs",
                "మనకు commission ఇచ్చే partner programs (Amazon, Flipkart...).",
                "ప్రతి program commission నిబంధనలు, status update గా ఉంచండి."),
             _r("affiliate_links", "Affiliate Links",
                "Partner products కి tracked links.",
                "చేర్చాక link test చేయండి; పని చేయని link = నష్టం."),
             _r("smart_links", "Smart Links",
                "జనాన్ని app కు, deal కు లేదా పేజీకి పంపే tracked links.",
                "ఒక campaign కి ఒక smart link వాడండి, అప్పుడు పోల్చవచ్చు."),
         ]),
     ]},
    {"id": "catalogue", "icon": "🛍️", "color": "#f79009", "label": "Catalogue & Sources",
     "what": "Items, categories, listings, results ఎక్కడ నుండి వస్తాయి.",
     "cats": [
         _cat("Items చేర్చండి", [
             _v("smartentry", "overview:view", "Smart Entry (Links పేస్ట్ చేయండి)",
                "Links లేదా CSV paste చేయండి; forms ready అవుతాయి, ఏదీ దానంతట అదే save కాదు.",
                "REVIEW / MISSING ఉన్న ప్రతి field check చేసి, drafts గా import చేయండి."),
             _v("affhub", "affiliate_products:create", "Affiliate Product Hub",
                "Marketplace products ని preview చేసి import చేయండి, ప్రతి field కి source తో.",
                "Commission పేజీ నుండి తీసుకోము; program నిబంధనల నుండి మీరే నమోదు చేయండి."),
             _r("entry_templates", "Entry Templates",
                "Items త్వరగా చేర్చడానికి ready form layouts (structure మాత్రమే).",
                "తరచుగా వచ్చే item రకానికి ఒక template పెట్టండి."),
         ]),
         _cat("Items & Listings", [
             _v("affproducts", "affiliate_products:view", "Affiliate Products",
                "సిబ్బంది తయారుచేసిన items: DRAFT -> REVIEW -> LIVE.",
                "LIVE items మాత్రమే customers కి కనిపిస్తాయి. Live కి ముందు లేని ధరలు సరిచేయండి."),
             _r("listing_reviews", "Listing Review",
                "Review కోసం ఆపిన seller listings (contact details, links, repeats).",
                "సరిగ్గా ఉన్నవి approve చేయండి; rule స్ తప్పినవి reject చేయండి."),
             _r("prohibited_terms", "నిషేధిత పదాలు (Listings)",
                "Listing ని ఆపే పదాలు (చట్టవిరుద్ధ / ప్రమాదకర items).",
                "ఎప్పుడూ తప్పు అయిన పదమే చేర్చండి, మంచి sellers ఆగిపోకుండా."),
         ]),
         _cat("Categories", [
             _r("taxonomy_nodes", "Category చెట్టు",
                "Category చెట్టు: ప్రధాన category -> సబ్ category -> item రకం.",
                "సరైన parent కింద child చేర్చండి; సామర్థ్యాలు చెట్టు కిందకు వెళ్తాయి."),
             _r("catalog_templates", "Catalogue Templates",
                "ప్రతి shop రకానికి item కోసం ఏ వివరాలు నింపాలి (size, colour, weight...).",
                "Field పేర్లు simple గా ఉంచండి; app వాటిని sellers కి boxes గా చూపిస్తుంది."),
         ]),
         _cat("Results ఎక్కడ నుండి", [
             _v("affsources", "affiliate_products:view", "Affiliate Sources",
                "Item store ని నింపే marketplace adapters, feeds.",
                "ERROR లో ఉన్న source దాని items ని update చేయదు; health చూడండి."),
             _r("sources", "Sources",
                "Results వచ్చే అన్ని చోట్లు (feeds, JSON search, site search, APIs).",
                "కొత్త source ఇక్కడే చేర్చండి - ప్రతి source కి code అవసరం లేదు."),
             _v("sourcehealth", "sources:view", "Source ఆరోగ్యం",
                "ఏ sources సమాధానం ఇస్తున్నాయి, fail అవుతున్నాయి, slow గా ఉన్నాయి.",
                "Fail అవుతున్న source ని సరిచేయండి లేదా pause చేయండి; మిగతావి పని చేస్తాయి."),
             _r("result_orchestration", "Results క్రమం",
                "ఏ result sections ముందు, ఒక్కోదానిలో ఎన్ని rows.",
                "ఒకసారి ఒక్కటే మార్చి Result diagnostics చూడండి."),
         ]),
     ]},
    {"id": "ai", "icon": "🧠", "color": "#7a5af8", "label": "AI Assistant & జవాబులు",
     "what": "AI customers ని ఏమి అడుగుతుంది, తనంతట తాను ఎలా జవాబిస్తుంది.",
     "cats": [
         _cat("Advisor ప్రశ్నలు", [
             _r("advisor_categories", "Advisor Categories",
                "Advisor కి తెలిసిన categories, అడగాల్సిన వివరాలతో.",
                "నిజంగా అవసరమైన వివరాలనే required గా పెట్టండి."),
             _r("advisor_questions", "Advisor ప్రశ్నలు",
                "ప్రతి follow-up ప్రశ్న మాటలు (en / te).",
                "చిన్న, స్నేహపూర్వక ప్రశ్నలు - ఒక్కో ప్రశ్నలో ఒక్కటే అడగండి."),
             _r("advisor_rules", "Advisor సలహా Rules",
                "ఒక సందర్భంలో assistant ఇచ్చే సలహా (ఉదా: warranty చూడండి).",
                "ప్రతి rule సాధారణంగా ఉంచండి - ఒక్కో product కి కాదు."),
         ]),
         _cat("Auto జవాబులు", [
             _r("auto_response_rules", "Auto జవాబులు",
                "Sellers chats లో తనంతట తాను పంపే approved FAQ సమాధానాలు.",
                "ఎప్పుడూ నిజమైన సమాధానాలనే approve చేయండి."),
             _v("socialdm", "autoresponse:view", "Social Auto-DM",
                "Facebook / Instagram సందేశాలకు Auto సమాధానాలు (Meta setup కావాలి).",
                "నిజమైన page కలిపే ముందు 'simulate' తో test చేయండి."),
             _r("social_dm_accounts", "Social DM Accounts",
                "కలిపిన Facebook / Instagram pages (tokens చూపించబడవు).",
                "వ్యాపారానిది కాని page ని disconnect చేయండి."),
             _r("greeting_templates", "పలకరింపులు & Texts",
                "Assistant వాడే పలకరింపులు, స్థిర మాటలు.",
                "ప్రతి మాటకూ English, తెలుగు రెండూ రాయండి."),
         ]),
         _cat("Screen Guide", [
             _v("screenguide", "companion:view", "Screen Guide వాడకం",
                "App లో guide వాడకం: మొదలైన, పూర్తైన walkthroughs, అడిగిన ప్రశ్నలు.",
                "మధ్యలో ఆపేసే walkthrough కి స్పష్టమైన steps కావాలి."),
         ]),
     ]},
    {"id": "content", "icon": "🎬", "color": "#e04f16", "label": "Videos & Content",
     "what": "Videos, creators, reviews, వార్తలు.",
     "cats": [
         _cat("Videos", [
             _r("videos", "Videos",
                "Results లో, content పేజీలో చూపించే videos.",
                "Titles స్పష్టంగా ఉంచండి; report అయిన videos pause చేయండి."),
             _v("videoreports", "content:view", "Video Reports",
                "తప్పు / ప్రమాదకరం అని users report చేసిన videos.",
                "ప్రతి report చూసి, నిజమైతే video దాచండి."),
             _v("discovered", "content:view", "దొరికిన Videos",
                "Automatic గా దొరికిన videos; approval తర్వాతే చూపిస్తాం.",
                "ఉపయోగపడేవి approve చేయండి, మిగతావి reject చేయండి."),
         ]),
         _cat("Creators & Reviews", [
             _r("creators", "Creators & Influencers",
                "ASKODOX / partners కోసం videos చేసేవాళ్ళు.",
                "Contact, agreement status update గా ఉంచండి."),
             _r("video_sources", "Video Sources",
                "Videos వచ్చే channels / feeds.",
                "తప్పు videos తెచ్చే source ని pause చేయండి."),
             _r("reviews", "Reviews",
                "Sellers, items పై customer reviews.",
                "నకిలీ / తిట్ల reviews దాచండి; నిజమైనవి ఎప్పుడూ మార్చకండి."),
         ]),
     ]},
    {"id": "people", "icon": "👥", "color": "#1570ef", "label": "Customers, Staff & Partners",
     "what": "Customers, support, ధృవీకరణ, delivery partners, సిబ్బంది.",
     "cats": [
         _cat("Customers", [
             _v("accounts", "users:view", "Users & Accounts",
                "Sign up అయిన ప్రతి account, role, status తో (నంబర్లు దాచబడతాయి).",
                "స్పష్టమైన కారణంతోనే block చేయండి; audit log లో నమోదవుతుంది."),
             _v("support", "support:view", "Support Tickets",
                "Customers చెప్పిన సమస్యలు.",
                "పాతవాటికి ముందు జవాబివ్వండి; పరిష్కారం అయ్యాకే close చేయండి."),
             _r("feedback_reports", "Feedback & సమస్యలు",
                "App నుండి వచ్చిన feedback (వ్యక్తిగత వివరాలు దాచబడతాయి).",
                "ఒకేలాంటివి కలపండి; నిజమైన bugs ని staff tasks గా మార్చండి."),
             _r("early_access", "Early Access Testers",
                "కొత్త features ముందుగా వాడటానికి పిలిచిన testers.",
                "కొద్దిమందిని ఒకసారి పిలవండి; వాళ్ళ feedback చదవండి."),
         ]),
         _cat("KYC & Verification", [
             _v("kycqueue", "kyc:view", "KYC Review",
                "సిబ్బంది ధృవీకరణ కోసం ఆగిన business / professional documents.",
                "Document లో నిజంగా ఉన్నదే verify చేయండి; AI చదవడం verify కాదు."),
             _r("role_verifications", "Role ధృవీకరణ",
                "Seller / partner / provider నిజంగా వాళ్ళేనా అని check.",
                "Evidence రాసి approve చేయండి; అస్పష్టంగా ఉంటే correction అడగండి."),
         ]),
         _cat("Delivery & Rides", [
             _v("mobility", "delivery:view", "Mobility సారాంశం",
                "Rides, parcels, deliveries - వాటి నిజమైన స్థితి.",
                "NEEDS_PARTNER అంటే దగ్గర approved partner లేరు - partners ని చేర్చండి."),
             _r("delivery_partners", "Delivery Partners",
                "Apply చేసిన drivers / riders, documents status తో.",
                "Documents check చేశాకే approve చేయండి."),
             _r("mobility_services", "Mobility Services & ఛార్జీలు",
                "Ride / parcel services, ఛార్జీలు (ధరలు ఇక్కడ నుండే).",
                "ఒక service, ఊరికి ఒకే ACTIVE row ఉంచండి."),
         ]),
         _cat("Staff", [
             _v("staff", "staff:manage", "Staff & Roles",
                "సిబ్బంది, వాళ్ళ పాత్రలు, అనుమతులు.",
                "పనికి సరిపడా చిన్న role ఇవ్వండి; వెళ్ళిపోయినవాళ్ళని వెంటనే తీసేయండి."),
             _r("staff_tasks", "Staff పనులు",
                "సిబ్బందికి ఇచ్చిన పనులు, గడువు తేదీలతో.",
                "ఒక పనికి ఒకే బాధ్యుడు; అయ్యాక close చేయండి."),
             _v("workspace", "workspace:view", "Staff Workspace తెరవండి",
                "సిబ్బంది రోజువారీ simple screen (అవే అనుమతులు).",
                "పూర్తి console అవసరం లేని సిబ్బందికి ఇది ఇవ్వండి."),
         ]),
     ]},
    {"id": "messages", "icon": "🔔", "color": "#c11574", "label": "Messages & Notifications",
     "what": "Notifications, e-mail, ఏది చేరింది.",
     "cats": [
         _cat("Notifications & E-mail", [
             _r("notification_templates", "Notification Templates",
                "ప్రతి notification మాటలు (en / te).",
                "చిన్నగా ఉంచండి; వ్యక్తిగత వివరాలు మాటల్లో పెట్టకండి."),
             _r("notification_rules", "Notification Rules",
                "Notification ఎప్పుడు, ఎవరికి వెళ్తుంది.",
                "ఒకే విషయం రోజుకు రెండుసార్లు పంపకండి."),
             _v("outbox", "integrations:view", "Messages చేరాయా?",
                "పంపిన ప్రతి సందేశం - చేరిందా, fail అయిందా.",
                "ఒక channel నుండి చాలా FAILED = ఆ integration check చేయండి."),
             _r("email_roles", "Domain & E-mail Roles",
                "ఏ @askodox.com address దేనికి (support, billing...).",
                "ప్రతి address కి ఒకే బాధ్యుడు."),
         ]),
     ]},
    {"id": "system", "icon": "⚙️", "color": "#475467", "label": "System ఆరోగ్యం & Settings",
     "what": "అన్నీ పని చేస్తున్నాయా? connections, settings, tests, records.",
     "cats": [
         _cat("System ఆరోగ్యం", [
             _v("incidents", "health:view", "Incidents & చర్యలు (AI)",
                "Live system లో దొరికిన సమస్యలు: ఏమైంది, ఎందుకు, ఏం చేయాలి.",
                "'ఎందుకు', 'ఏం చేయాలి' చదవండి. మార్పులకు approval కావాలి; కారణం provider జవాబుతోనే నిర్ధారణ."),
             _v("apibilling", "health:view", "API Health & Billing",
                "ప్రతి paid API: పని చేస్తోందా, వాడకం, provider చెప్తే balance.",
                "QUOTA EXHAUSTED = ఆ provider account లో recharge చేయండి (ASKODOX బయట)."),
             _v("readiness", "integrations:view", "Integration సిద్ధత",
                "ప్రతి బయటి service live check: LIVE, NEEDS CONFIGURATION, ERROR.",
                "Key సరిచేశాక 'Check' నొక్కి నిజంగా పని చేస్తోందో చూడండి."),
             _v("selfheal", "selfheal:view", "Auto Repair",
                "Automatic గా ప్రయత్నించిన fixes, నిజంగా కోలుకుందా.",
                "APPLIED అంటే కోలుకున్నట్టు కాదు - VERIFIED చూడండి."),
         ]),
         _cat("Connections", [
             _v("wizard", "integrations:view", "Integration Setup Wizard",
                "కొత్త బయటి service ని step by step setup.",
                "Steps వరుసగా చేయండి; keys server లోనే ఉంటాయి."),
             _v("integrations", "integrations:view", "Integrations",
                "కలిపిన అన్ని services, వాటి settings.",
                "ఒకసారి ఒక్క సర్వీసే మార్చి, Readiness లో check చేయండి."),
         ]),
         _cat("Settings", [
             _v("setup", "config:view", "ASKODOX Setup చెక్‌లిస్ట్",
                "Owner checklist: ఏది setup అయింది, ఏది ఇంకా లేదు.",
                "ముందు ఎరుపు వాటిని పూర్తి చేయండి."),
             _r("platform_settings", "Platform Settings",
                "Platform వాడే పరిమిత విలువలు (limits, timings).",
                "అనుమతించిన పరిధి బయటి విలువలు తిరస్కరించబడతాయి."),
             _v("flags", "config:view", "Feature Flags (On / Off)",
                "కొత్త app లేకుండా features ఆన్ / ఆఫ్.",
                "పని చేయని feature ని ముందు ఇక్కడ ఆఫ్ చేసి, తర్వాత సరిచేయండి."),
             _r("flag_rollouts", "Feature Flag Targeting",
                "ఒక feature ముందు కొంతమందికే (role, category, %).",
                "చిన్నగా (5-10%) మొదలుపెట్టి, errors రాకపోతే పెంచండి."),
             _v("cfgbundle", "config:view", "Settings Import / Export",
                "Staging, production మధ్య settings ఒకే file గా కాపీ.",
                "ఏదైనా import చేసే ముందు export backup తీసుకోండి."),
         ]),
         _cat("Testing & Records", [
             _r("qa_checks", "Phone Test / QA Center",
                "నిజమైన phone checks: phone లో proof తో test అయ్యేవరకు CODE READY.",
                "Screenshot / video evidence ఉంటేనే PHONE VERIFIED పెట్టండి."),
             _v("audit", "audit:view", "Audit Log",
                "ఎవరు, ఏమి, ఎప్పుడు మార్చారు. దీన్ని మార్చలేం.",
                "ఒక మార్పుని వెతకడానికి staff పేరు / record తో search చేయండి."),
         ]),
     ]},
]


def views() -> List[str]:
    return [i["id"] for s in NAV for c in s["cats"] for i in c["items"] if "res" not in i]


def resources() -> List[str]:
    return [i["res"] for s in NAV for c in s["cats"] for i in c["items"] if "res" in i]
