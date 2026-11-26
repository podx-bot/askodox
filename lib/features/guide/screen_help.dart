/// "What do I do here?" for EVERY screen: one press of the guide button shows
/// this screen's purpose and the steps, in English or Telugu, plus "Show me on
/// the screen" when a walkthrough flow exists for it. Keyed by the router's
/// path pattern (e.g. `/pos/:id/items`). A guard test fails when a screen
/// route has neither help here nor a reason in [askodoxScreenHelpExempt].
library;

class AskodoxScreenHelp {
  const AskodoxScreenHelp(this.titleEn, this.titleTe, this.stepsEn, this.stepsTe);
  final String titleEn;
  final String titleTe;
  final List<String> stepsEn;
  final List<String> stepsTe;

  String title(bool te) => te ? titleTe : titleEn;
  List<String> steps(bool te) => te ? stepsTe : stepsEn;
}

typedef _H = AskodoxScreenHelp;

/// Screens that intentionally have no guide button (with the reason).
const askodoxScreenHelpExempt = <String, String>{
  '/my-shop/sale': 'finds the shop and opens that tool page (which has its own help)',
  '/my-shop/payment-alerts': 'finds the shop and opens that tool page (which has its own help)',
  '/my-shop/collect': 'finds the shop and opens that tool page (which has its own help)',
  '/my-shop/orders': 'finds the shop and opens that tool page (which has its own help)',
  '/my-shop/tables': 'finds the shop and opens that tool page (which has its own help)',
  '/my-shop/kitchen': 'finds the shop and opens that tool page (which has its own help)',
  '/my-shop/items': 'finds the shop and opens that tool page (which has its own help)',
  '/my-shop/suppliers': 'finds the shop and opens that tool page (which has its own help)',
  '/my-shop/expiry': 'finds the shop and opens that tool page (which has its own help)',
  '/my-shop/customers': 'finds the shop and opens that tool page (which has its own help)',
  '/my-shop/dues': 'finds the shop and opens that tool page (which has its own help)',
  '/my-shop/agents': 'finds the shop and opens that tool page (which has its own help)',
  '/my-shop/bills': 'finds the shop and opens that tool page (which has its own help)',
  '/my-shop/day': 'finds the shop and opens that tool page (which has its own help)',
  '/my-shop/gst': 'finds the shop and opens that tool page (which has its own help)',
  '/my-shop/staff': 'finds the shop and opens that tool page (which has its own help)',
  '/my-shop/printer': 'finds the shop and opens that tool page (which has its own help)',
  '/my-shop/advance': 'finds the shop and opens that tool page (which has its own help)',
  '/my-shop/selfshop': 'finds the shop and opens that tool page (which has its own help)',
  '/onboarding': 'sign-up has its own step-by-step screen (private: number / OTP)',
  '/auth/session-expired': 'message-only screen',
  '/account-status': 'message-only screen',
  '/forbidden': 'message-only screen',
  '/product-not-found': 'message-only screen',
  '/developer': 'developer tool, not shown to customers',
  '/developer/feedback': 'developer tool, not shown to customers',
  '/sync-status': 'developer tool, not shown to customers',
  '/conflict/:id': 'developer tool, not shown to customers',
  '/storage-usage': 'developer tool, not shown to customers',
  '/performance-monitor': 'developer tool, not shown to customers',
  '/alert-simulator': 'developer tool, not shown to customers',
  '/companion-lab': 'developer tool, not shown to customers',
  '/companion-performance': 'developer tool, not shown to customers',
  '/settings/diagnostics': 'development builds only',
  '/admin': 'staff console (every /admin/... page)',
};

const askodoxScreenHelp = <String, AskodoxScreenHelp>{
  // ------------------------------------------------------------- main shell
  '/': _H('Home — ask ASKODOX', 'హోమ్ — ASKODOX ని అడగండి', [
    'Type or speak what you need (buy, sell, a service, a job, a ride).',
    'Answer the one question ASKODOX asks, or say "show me".',
    'Each answer is one card: the big line on top is the answer (🔊 reads it); tap the big tabs for more, swipe the cards sideways.',
    'Tap a button under the answer (e.g. "Money is gone") — its next step opens inside the same card.',
    'Sent a photo of an SMS? The colour bar shows the risk; money / sender / link are coloured, and one button opens your own bank / UPI app.',
    'Results appear above the chat: tap a card to send a request or open it.',
    'Examples: "Sona masoori rice 25 kg under 1500 near me" · "AC repair at home tomorrow" · "I want to sell my old scooter".',
  ], [
    'మీకు ఏం కావాలో టైప్ చేయండి లేదా మాట్లాడండి (కొనడం, అమ్మడం, సర్వీస్, ఉద్యోగం, రైడ్).',
    'ASKODOX అడిగే ఒక్క ప్రశ్నకు జవాబు ఇవ్వండి, లేదా "చూపించు" అనండి.',
    'ప్రతి జవాబు ఒకే కార్డ్: పైన పెద్ద లైన్ = జవాబు (🔊 నొక్కితే వినిపిస్తుంది); పెద్ద tabs నొక్కి ఇంకా చూడండి, కార్డ్‌లను పక్కకి జరపండి.',
    'జవాబు కింద button నొక్కండి (ఉదా: "డబ్బు పోయింది") — తర్వాత ఏం చేయాలో అదే కార్డ్‌లో వస్తుంది.',
    'SMS ఫోటో పంపారా? రంగుల గీత ప్రమాదం చెబుతుంది; డబ్బు / పంపినవారు / link రంగుల్లో, ఒక్క button తో మీ bank / UPI app తెరుచుకుంటుంది.',
    'ఫలితాలు చాట్ పైన వస్తాయి: కార్డ్ నొక్కి రిక్వెస్ట్ పంపండి లేదా తెరవండి.',
    'ఉదాహరణలు: "దగ్గరలో 1500 లోపు సోనా మసూరి బియ్యం 25 కిలో" · "రేపు ఇంటికి AC రిపేర్" · "నా పాత స్కూటర్ అమ్మాలి".',
  ]),
  '/watchlist': _H('History', 'చరిత్ర', [
    'Your earlier conversations and saved options are here.',
    'Tap one to continue where you stopped.',
  ], [
    'మీ పాత సంభాషణలు, సేవ్ చేసినవి ఇక్కడ ఉంటాయి.',
    'ఒకదాన్ని నొక్కితే ఆపిన చోటు నుండి కొనసాగించవచ్చు.',
  ]),
  '/updates': _H('Updates', 'అప్‌డేట్స్', [
    'Replies to your requests, orders and alerts arrive here.',
    'Tap an update to open the request or order it belongs to.',
  ], [
    'మీ రిక్వెస్ట్‌లకు జవాబులు, ఆర్డర్లు, అలర్ట్‌లు ఇక్కడ వస్తాయి.',
    'అప్‌డేట్ నొక్కితే దానికి సంబంధించిన రిక్వెస్ట్ / ఆర్డర్ తెరుచుకుంటుంది.',
  ]),
  '/profile': _H('Tools', 'టూల్స్', [
    'Say or type what you need in the box at the top (for example "notifications" or "my shop") — it finds it.',
    'Three tabs: Me (shopping, rides, tools, roles), Business (bills, items, enquiries, videos), Settings.',
    'Things you opened recently show first, under "Recent".',
  ], [
    'పైన బాక్స్‌లో మీకు ఏం కావాలో చెప్పండి లేదా టైప్ చేయండి (ఉదా: "నోటిఫికేషన్లు", "నా షాప్") — అదే వెతికి చూపిస్తుంది.',
    'మూడు ట్యాబ్‌లు: నేను (కొనుగోళ్లు, రైడ్స్, టూల్స్, పాత్రలు), వ్యాపారం (బిల్లులు, సరుకులు, ఎంక్వైరీలు, వీడియోలు), సెట్టింగ్స్.',
    'ఇటీవల తెరిచినవి "ఇటీవల" కింద ముందే కనిపిస్తాయి.',
  ]),
  '/location': _H('Your location', 'మీ లొకేషన్', [
    'Allow location, or search and pick a place by hand.',
    'Nearby results use this place; a place you pick stays until you change it.',
  ], [
    'లొకేషన్ అనుమతి ఇవ్వండి, లేదా ప్రదేశాన్ని వెతికి ఎంచుకోండి.',
    'దగ్గరి ఫలితాలు ఈ ప్రదేశం ఆధారంగా వస్తాయి; మీరు ఎంచుకున్నది మార్చే వరకు ఉంటుంది.',
  ]),
  '/product/:id': _H('Item details', 'వస్తువు వివరాలు', [
    'Check the price, seller and what is verified.',
    'Use the button at the bottom to send a request to the seller.',
  ], [
    'ధర, అమ్మేవారు, ఏది నిర్ధారించబడిందో చూడండి.',
    'కింద బటన్‌తో అమ్మేవారికి రిక్వెస్ట్ పంపండి.',
  ]),
  '/settings/notifications': _H('Notifications', 'నోటిఫికేషన్లు', [
    'Turn each kind of notification on or off.',
    'Changes save at once.',
  ], [
    'ఒక్కో రకం నోటిఫికేషన్‌ని ఆన్ / ఆఫ్ చేయండి.',
    'మార్పులు వెంటనే సేవ్ అవుతాయి.',
  ]),
  '/companion/screen-guide': _H('Screen guide', 'స్క్రీన్ గైడ్', [
    'Pick a task; ASKODOX points at each button on the real screen.',
  ], [
    'ఒక పని ఎంచుకోండి; ASKODOX అసలు స్క్రీన్‌పై ప్రతి బటన్‌ను చూపిస్తుంది.',
  ]),
  '/deals': _H('Requests', 'రిక్వెస్ట్‌లు', [
    'Requests you sent and received are listed here.',
    'Open one to chat, accept or close it.',
  ], [
    'మీరు పంపిన, మీకు వచ్చిన రిక్వెస్ట్‌లు ఇక్కడ ఉంటాయి.',
    'ఒకటి తెరిచి చాట్ చేయండి, అంగీకరించండి లేదా మూసివేయండి.',
  ]),
  '/deal/:requestId': _H('Request', 'రిక్వెస్ట్', [
    'Chat with the other person about this request.',
    'Contact details are shared only after the request is accepted.',
  ], [
    'ఈ రిక్వెస్ట్ గురించి అవతలి వ్యక్తితో చాట్ చేయండి.',
    'రిక్వెస్ట్ అంగీకరించాకే కాంటాక్ట్ వివరాలు కనిపిస్తాయి.',
  ]),
  '/orders/mine': _H('My orders', 'నా ఆర్డర్లు', [
    'Orders you placed and their status.',
    'Confirm "received" when the order reaches you.',
  ], [
    'మీరు చేసిన ఆర్డర్లు, వాటి స్థితి.',
    'ఆర్డర్ మీకు చేరాక "అందింది" అని నిర్ధారించండి.',
  ]),
  '/orders/incoming': _H('Incoming orders', 'వచ్చిన ఆర్డర్లు', [
    'Orders customers sent you.',
    'Accept or decline each one, then move it forward step by step.',
  ], [
    'కస్టమర్లు మీకు పంపిన ఆర్డర్లు.',
    'ఒక్కోదాన్ని అంగీకరించండి / తిరస్కరించండి, తర్వాత దశలవారీగా ముందుకు తీసుకెళ్ళండి.',
  ]),
  '/opportunities': _H('Opportunities', 'అవకాశాలు', [
    'Real customer demand near you that matches what you sell.',
    'Open one to see what customers asked for.',
  ], [
    'మీరు అమ్మే వాటికి సరిపోయే దగ్గరి కస్టమర్ డిమాండ్.',
    'ఒకటి తెరిచి కస్టమర్లు ఏం అడిగారో చూడండి.',
  ]),
  '/profile/memory': _H('What ASKODOX remembers', 'ASKODOX గుర్తుంచుకున్నవి', [
    'See, correct or delete what ASKODOX remembers about your needs.',
    'Turn memory off with the switch at the top.',
  ], [
    'మీ అవసరాల గురించి ASKODOX గుర్తుంచుకున్నవి చూడండి, సరిచేయండి, తొలగించండి.',
    'పైన స్విచ్‌తో మెమరీని ఆఫ్ చేయవచ్చు.',
  ]),
  '/profile/roles': _H('My roles', 'నా పాత్రలు', [
    'Choose what you do on ASKODOX: buy, sell, give or take services.',
    'Your tools in Profile follow these roles.',
  ], [
    'ASKODOX లో మీరు ఏం చేస్తారో ఎంచుకోండి: కొనడం, అమ్మడం, సర్వీస్ ఇవ్వడం / తీసుకోవడం.',
    'ప్రొఫైల్‌లో మీ టూల్స్ ఈ పాత్రల ప్రకారం వస్తాయి.',
  ]),
  '/business': _H('My Business', 'నా బిజినెస్', [
    'Everything for your business in one place: listings, orders, billing (POS), promotions.',
    'Tap a tile to open it.',
  ], [
    'మీ బిజినెస్‌కి కావలసినవన్నీ ఒకే చోట: లిస్టింగ్స్, ఆర్డర్లు, బిల్లింగ్ (POS), ప్రమోషన్లు.',
    'టైల్ నొక్కి తెరవండి.',
  ]),
  '/business/promotions': _H('Promotions', 'ప్రమోషన్లు', [
    'Create an offer for your listings and choose when it runs.',
  ], [
    'మీ లిస్టింగ్స్‌కి ఆఫర్ తయారు చేసి, అది ఎప్పుడు నడవాలో ఎంచుకోండి.',
  ]),
  '/business/creations': _H('Creations', 'క్రియేషన్స్', [
    'Make posters and posts for your business from your own details.',
  ], [
    'మీ వివరాలతో మీ బిజినెస్‌కి పోస్టర్లు, పోస్ట్‌లు తయారు చేయండి.',
  ]),
  '/business/automation': _H('Automation', 'ఆటోమేషన్', [
    'Set approved answers and hours so customers get replies when you are busy.',
  ], [
    'ఆమోదించిన జవాబులు, సమయాలు పెట్టండి — మీరు బిజీగా ఉన్నప్పుడు కస్టమర్లకు జవాబులు వెళ్తాయి.',
  ]),
  '/listings/mine': _H('My listings', 'నా లిస్టింగ్స్', [
    'Add what you sell with a price; customers find it in ASKODOX search.',
    'Edit price or stock, or take a listing down.',
  ], [
    'మీరు అమ్మేవి ధరతో చేర్చండి; కస్టమర్లు ASKODOX సెర్చ్‌లో చూస్తారు.',
    'ధర / స్టాక్ మార్చండి, లేదా లిస్టింగ్ తీసేయండి.',
  ]),
  '/privacy': _H('Privacy', 'ప్రైవసీ', [
    'Download your data or delete your account.',
    'Deleting signs you out on every phone.',
  ], [
    'మీ డేటా డౌన్‌లోడ్ చేయండి లేదా ఖాతా తొలగించండి.',
    'తొలగిస్తే అన్ని ఫోన్లలో సైన్ అవుట్ అవుతుంది.',
  ]),
  '/videos/native': _H('Videos', 'వీడియోలు', [
    'Upload a video of your product or service and publish it.',
    'Customers can ask questions about it.',
  ], [
    'మీ ప్రొడక్ట్ / సర్వీస్ వీడియో అప్‌లోడ్ చేసి పబ్లిష్ చేయండి.',
    'కస్టమర్లు దాని గురించి ప్రశ్నలు అడగవచ్చు.',
  ]),
  '/radio': _H('Radio', 'రేడియో', [
    'Hear short updates about the places on your route.',
    'Town news: type any town and hear its latest real headlines.',
    'It runs on your AI Credits -- no separate package; nothing found = nothing charged.',
  ], [
    'మీ దారిలోని ప్రదేశాల గురించి చిన్న అప్‌డేట్స్ వినండి.',
    'ఊరి వార్తలు: ఏ ఊరి పేరు రాసినా ఆ ఊరి తాజా నిజమైన వార్తలు వినిపిస్తాయి.',
    'మీ AI Credits తోనే పనిచేస్తుంది -- వేరే ప్యాకేజ్ లేదు; ఏమీ దొరకకపోతే ఏమీ కట్ కాదు.',
  ]),
  '/talk': _H('Talk', 'చర్చ', [
    'Search a topic or start one, then talk with others about it.',
    'Nobody knows who anybody is; rude words become **** and contacts are hidden.',
    'Reading is free; hearing a message read aloud uses AI Credits.',
  ], [
    'ఒక విషయం వెతకండి లేదా కొత్తది మొదలుపెట్టండి, తర్వాత ఇతరులతో దాని మీద మాట్లాడండి.',
    'ఎవరు ఎవరో ఎవరికీ తెలియదు; బూతులు **** అవుతాయి, నంబర్లు దాచేస్తాం.',
    'చదవడం ఉచితం; message ని వినాలంటే AI Credits ఖర్చవుతాయి.',
  ]),
  '/talk/:id': _H('Discussion', 'చర్చ', [
    'Write or speak your message; it is checked before others see it.',
    'Tap the speaker to hear a message (AI Credits); ⋮ to Report or Block.',
  ], [
    'మీ మాట రాయండి లేదా మాట్లాడండి; ఇతరులు చూసే ముందు చెక్ అవుతుంది.',
    'మాట వినడానికి స్పీకర్ నొక్కండి (AI Credits); Report / Block కి ⋮ నొక్కండి.',
  ]),
  '/plans': _H('Plans', 'ప్లాన్లు', [
    'Compare plans and what each includes.',
    'Paid plans show a Pay button only when payments are live.',
  ], [
    'ప్లాన్లు, ఒక్కోదానిలో ఏముందో పోల్చండి.',
    'పేమెంట్లు లైవ్‌లో ఉన్నప్పుడే పే బటన్ కనిపిస్తుంది.',
  ]),
  '/verification': _H('Verification', 'వెరిఫికేషన్', [
    'Give consent, then add the business document asked for.',
    'Staff check it; the status shows here.',
  ], [
    'ముందు అనుమతి ఇవ్వండి, తర్వాత అడిగిన బిజినెస్ డాక్యుమెంట్ చేర్చండి.',
    'స్టాఫ్ చెక్ చేస్తారు; స్థితి ఇక్కడ కనిపిస్తుంది.',
  ]),
  '/mobility': _H('Rides & parcels', 'రైడ్స్ & పార్సెల్స్', [
    'Choose ride or parcel, set pickup and drop on the map.',
    'Send the request; you see the partner only after one accepts.',
  ], [
    'రైడ్ లేదా పార్సెల్ ఎంచుకోండి, మ్యాప్‌లో పికప్, డ్రాప్ పెట్టండి.',
    'రిక్వెస్ట్ పంపండి; పార్ట్నర్ అంగీకరించాకే వివరాలు కనిపిస్తాయి.',
  ]),
  '/me/ideas': _H('Ideas & suggestions', 'సలహాలు & సూచనలు', [
    'Choose what it is about, then say it with the mic or type it.',
    'Tap Send. Our team reads every idea. Never write phone numbers, OTPs or card numbers.',
  ], [
    'దేని గురించో ఎంచుకోండి, మైక్‌తో చెప్పండి లేదా రాయండి.',
    'పంపు నొక్కండి. మా టీమ్ ప్రతి ఐడియా చదువుతుంది. ఫోన్ నంబర్, OTP, కార్డ్ నంబర్లు రాయకండి.',
  ]),
  '/notices/new': _H('Send a notification', 'నోటిఫికేషన్ పంపండి', [
    'Write the subject, tap AI design (or add your photo), check the heading and offer.',
    'Choose who gets it: your shop followers, people within 1-10 km, or both. The count and price show below; tap Send.',
  ], [
    'సబ్జెక్ట్ రాయండి, AI డిజైన్ నొక్కండి (లేదా మీ ఫోటో పెట్టండి), హెడ్డింగ్, ఆఫర్ చూసుకోండి.',
    'ఎవరికో ఎంచుకోండి: ఫాలోవర్స్, 1-10 కి.మీ లోపు వాళ్ళు, లేదా రెండూ. ఎంతమంది, ఎంత ఖర్చో కింద కనిపిస్తుంది; పంపండి నొక్కండి.',
  ]),
  '/notice/:id': _H('Offer', 'ఆఫర్', [
    'A shop or person near you sent this. Tap See the shop to open it.',
    'Don\'t want these? Turn "Offers" off in Settings → Notifications.',
  ], [
    'మీ దగ్గర షాప్ / వ్యక్తి పంపారు. షాప్ చూడండి నొక్కితే తెరుచుకుంటుంది.',
    'ఇవి వద్దా? సెట్టింగ్స్ → నోటిఫికేషన్స్‌లో "ఆఫర్లు" ఆపేయండి.',
  ]),
  '/beta-feedback': _H('Report a problem', 'సమస్య చెప్పండి', [
    'Write what went wrong; add a screenshot if you like.',
    'Diagnostics are sent only if you allow it.',
  ], [
    'ఏం తప్పు జరిగిందో రాయండి; కావాలంటే స్క్రీన్‌షాట్ చేర్చండి.',
    'మీరు అనుమతిస్తేనే డయాగ్నస్టిక్స్ పంపుతాం.',
  ]),
  '/pos/:id/collect': _H('Collect by UPI', 'UPI తో కట్టించుకోండి', [
    'Type the amount and press "Show QR" — the customer scans it with any UPI app and pays the shop directly.',
    'When a payment notification with the same amount arrives, it is marked — check your bank app.',
    'Press "Money received" only after you have checked. ASKODOX never holds the money.',
  ], [
    'మొత్తం టైప్ చేసి "QR చూపించు" నొక్కండి — కస్టమర్ ఏ UPI యాప్‌తో అయినా స్కాన్ చేసి నేరుగా షాపుకి కడతారు.',
    'అదే మొత్తం పేమెంట్ నోటిఫికేషన్ వస్తే గుర్తు పెడుతుంది — బ్యాంక్ యాప్‌లో చూసుకోండి.',
    'చూసుకున్నాకే "డబ్బు అందింది" నొక్కండి. ASKODOX డబ్బు పట్టుకోదు.',
  ]),
  '/me/business': _H('My business', 'నా బిజినెస్', [
    'First time: type your business name and choose your State.',
    'Then everything lives in 6 coloured groups: Orders, Bills & money, Menu & items, Staff, Customers & shop page, Settings.',
    'The three big buttons are the every-day ones: make a bill, orders, show the QR.',
    'Tap the shop card to switch shop or open / pause / close it. Or say what to do in the ASK bar at the bottom.',
  ], [
    'మొదటిసారి: మీ బిజినెస్ పేరు రాసి, రాష్ట్రం ఎంచుకోండి.',
    'తర్వాత అన్నీ 6 రంగుల విభాగాల్లో: ఆర్డర్లు, బిల్లులు & డబ్బు, మెనూ & ఐటమ్స్, సిబ్బంది, కస్టమర్లు & షాప్ పేజీ, సెట్టింగ్స్.',
    'మూడు పెద్ద బటన్లు రోజూ వాడేవి: బిల్లు చేయి, ఆర్డర్లు, QR చూపు.',
    'షాప్ కార్డ్ నొక్కితే షాప్ మార్చవచ్చు, తెరవ / ఆపవచ్చు. లేదా కింద ASK బార్‌లో ఏం చేయాలో చెప్పండి.',
  ]),
  '/biz/:id': _H('My business', 'నా బిజినెస్', [
    'Today at the top, then the every-day buttons, then the 6 groups.',
    'Say anything in the ASK bar: "how much did we sell today?", "chicken 65 off".',
  ], [
    'పైన ఈ రోజు లెక్క, తర్వాత రోజూ వాడే బటన్లు, తర్వాత 6 విభాగాలు.',
    'ASK బార్‌లో ఏదైనా చెప్పండి: "ఈ రోజు ఎంత అమ్మాం?", "చికెన్ 65 ఆఫ్ చెయ్యి".',
  ]),
  '/biz/:id/:group': _H('Business group', 'బిజినెస్ విభాగం', [
    'The path at the top shows where you are. Today\'s numbers first.',
    '"Every day" buttons first, "Set once" buttons after, history at the bottom.',
    'Say what to do in the ASK bar — a change is shown first and happens only after ✓.',
  ], [
    'పైన దారి మీరు ఎక్కడ ఉన్నారో చూపిస్తుంది. ముందు ఈ రోజు అంకెలు.',
    'ముందు "రోజూ వాడేవి" బటన్లు, తర్వాత "ఒకసారి సెట్ చేసేవి", కింద చరిత్ర.',
    'ASK బార్‌లో ఏం చేయాలో చెప్పండి — మార్పు ముందు చూపించి, ✓ నొక్కాకే చేస్తుంది.',
  ]),
  '/biz/:id/money/cashbook': _H('Cashbook', 'క్యాష్‌బుక్', [
    'The number on top is what is left this month. Tap "Write an entry", choose money in or out, type the amount.',
    'Tap a line to remove a wrong one — Undo brings it back. Other months and the old page: ⋮ at the top.',
  ], [
    'పైన ఉన్న నంబర్ ఈ నెల మిగిలింది. "ఎంట్రీ రాయి" నొక్కి, ఆదాయం / ఖర్చు ఎంచుకుని, మొత్తం రాయండి.',
    'తప్పు వరుస నొక్కి తీసేయండి — "వెనక్కి" తో మళ్ళీ వస్తుంది. ఇతర నెలలు, పాత పేజీ: పైన ⋮.',
  ]),
  '/biz/:id/money/dues': _H('Dues', 'బాకీలు', [
    'Three steps. 1: tap who paid (the total owed is on top; say or type a name). 2: type how much — "all" is ready; cash or online.',
    '3: done — the money goes on their oldest bills first; send the receipt on WhatsApp. Reminders: the button at the bottom.',
  ], [
    'మూడు స్టెప్స్. 1: ఎవరు కట్టారో నొక్కండి (పైన మొత్తం బాకీ; పేరు చెప్పండి / టైప్). 2: ఎంత ఇచ్చారు — "మొత్తం" ముందే ఉంటుంది; క్యాష్ / ఆన్‌లైన్.',
    '3: అయింది — డబ్బు పాత బిల్లులకు ముందు జమ; రసీదు WhatsApp కి. గుర్తులు పంపడం: కింద బటన్.',
  ]),
  '/biz/:id/money/history': _H('Bill history', 'బిల్లుల చరిత్ర', [
    'The number on top is the total of the bills below. Search by bill or phone number; "Change day" picks the days.',
    'Cash / online / baaki / cancelled filters are in the old page (⋮).',
  ], [
    'పైన నంబర్ కింద ఉన్న బిల్లుల మొత్తం. బిల్ / ఫోన్ నంబర్‌తో వెతకండి; "రోజు మార్చు" తో రోజులు ఎంచుకోండి.',
    'క్యాష్ / ఆన్‌లైన్ / బాకీ / రద్దు ఫిల్టర్లు పాత పేజీలో (⋮).',
  ]),
  '/biz/:id/reports': _H('Reports', 'రిపోర్ట్స్', [
    'The number on top is the sales of the day you chose. Problems below say what to do.',
    'Tap "Change day" for today, yesterday, 7 or 30 days. ⋮ has Listen and the full report with bars.',
  ], [
    'పైన నంబర్ మీరు ఎంచుకున్న రోజు అమ్మకం. కింద సమస్యలు, ఏం చేయాలో ఉంటాయి.',
    '"రోజు మార్చు" నొక్కి ఈ రోజు, నిన్న, 7 లేదా 30 రోజులు ఎంచుకోండి. ⋮ లో వినండి, బార్లతో పూర్తి రిపోర్ట్.',
  ]),
  '/biz/:id/reports/day': _H('Day report', 'రోజు రిపోర్ట్', [
    'The report of that day (from the night notification): the sales on top, then the problems with what to do.',
    'The three-dots menu has Listen and the full old report.',
  ], [
    'ఆ రోజు రిపోర్ట్ (రాత్రి నోటిఫికేషన్ నుంచి): పైన అమ్మకం, తర్వాత సమస్యలు, ఏం చేయాలో.',
    'మూడు చుక్కల మెనూలో వినండి, పూర్తి పాత రిపోర్ట్ ఉన్నాయి.',
  ]),
  '/biz/:id/reports/settings': _H('Night report', 'రాత్రి రిపోర్ట్', [
    'Two steps. 1: send the report every night? Yes or no. 2: choose the time.',
    'It goes to you and to the manager / accountant who can see reports.',
  ], [
    'రెండు స్టెప్స్. 1: ప్రతి రాత్రి రిపోర్ట్ పంపాలా? అవును / వద్దు. 2: టైం ఎంచుకోండి.',
    'మీకు, రిపోర్ట్స్ చూడగలిగే మేనేజర్ / అకౌంటెంట్‌కి వెళ్తుంది.',
  ]),
  '/biz/:id/staff': _H('Staff & attendance', 'సిబ్బంది & హాజరు', [
    'Who came today and when. Tap a person for their month, salary and advance.',
    'Check in, tasks, the shop-phone attendance and salary are the big buttons.',
  ], [
    'ఈ రోజు ఎవరు ఎప్పుడు వచ్చారు. పేరు నొక్కితే వారి నెల, జీతం, అడ్వాన్స్.',
    'హాజరు వేయి, పనులు, షాప్ ఫోన్ హాజరు, జీతాలు — పెద్ద బటన్లు.',
  ]),
  '/biz/:id/staff/today': _H("Today's attendance", 'ఈ రోజు హాజరు', [
    'The number on top is who is here today. Each row shows when they came and a mark: P, A, OT or leave.',
    'Tap a person, then one big button: Present, Absent, Overtime (pick the hours) or Leave.',
    'The big button at the bottom is your own check in / out. Shop phone attendance and setup are in the three-dot menu.',
  ], [
    'పైన సంఖ్య ఈ రోజు ఎంతమంది వచ్చారు. ప్రతి వరుసలో ఎప్పుడు వచ్చారు, ఒక గుర్తు: P, A, OT లేదా సెలవు.',
    'ఒకరిని నొక్కి, ఒక పెద్ద బటన్: వచ్చారు, రాలేదు, ఎక్కువ గంటలు (గంటలు ఎంచుకోండి) లేదా సెలవు.',
    'కింద పెద్ద బటన్ మీ హాజరు వేయడానికి. షాప్ ఫోన్ హాజరు, సెటప్ మూడు చుక్కల మెనూలో.',
  ]),
  '/biz/:id/staff/checkin': _H('Check in / out', 'హాజరు వేయి', [
    'Three steps. 1: tap the big round button ("I am in", later "I am leaving"). 2: your phone asks for its own fingerprint / face / PIN.',
    '3: done — the time and how far you are from the shop. No phone lock? It takes a selfie. Half day / leave: the words under the button.',
  ], [
    'మూడు స్టెప్స్. 1: పెద్ద గుండ్రటి బటన్ నొక్కండి ("వచ్చాను", తర్వాత "వెళ్తున్నా"). 2: మీ ఫోన్ వేలిముద్ర / ముఖం / PIN అడుగుతుంది.',
    '3: అయింది — టైం, షాప్ నుంచి దూరం. ఫోన్ లాక్ లేకపోతే సెల్ఫీ. హాఫ్ డే / సెలవు: బటన్ కింద మాటలు.',
  ]),
  '/biz/:id/staff/kiosk': _H('Shop phone attendance', 'షాప్ ఫోన్ హాజరు', [
    'For people without a phone: tap the name, then in or out, then a front-camera photo.',
    'Only the owner / manager see the photos; they are deleted after 90 days.',
  ], [
    'ఫోన్ లేనివారికి: పేరు నొక్కి, వచ్చాను / వెళ్తున్నా, తర్వాత ముందు కెమెరా ఫోటో.',
    'ఫోటోలు ఓనర్ / మేనేజర్‌కి మాత్రమే; 90 రోజుల తర్వాత తీసేస్తాం.',
  ]),
  '/biz/:id/staff/person/:ref': _H('One staff member', 'ఒక సిబ్బంది', [
    'The number on top is the salary to give this month. Tap a day to change it: present, absent, overtime or leave.',
    'The bottom button gives an advance or a bonus (1 how much, 2 saved). Salary settings and other months: ⋮.',
  ], [
    'పైన నంబర్ ఈ నెల ఇవ్వాల్సిన జీతం. రోజు నొక్కి మార్చండి: వచ్చారు, రాలేదు, OT, సెలవు.',
    'కింద బటన్‌తో అడ్వాన్స్ లేదా బోనస్ (1 ఎంత, 2 సేవ్). జీతం సెట్టింగ్, ఇతర నెలలు: ⋮.',
  ]),
  '/biz/:id/staff/salary': _H('Salary', 'జీతాలు', [
    'The number on top is the salaries you still have to give this month, worked out from attendance.',
    'The big button marks the first person as given and writes it into the cashbook as salary. Tap a person for their month.',
  ], [
    'పైన సంఖ్య ఈ నెల ఇంకా ఇవ్వాల్సిన జీతాలు, హాజరు నుంచి లెక్క.',
    'పెద్ద బటన్ మొదటి వ్యక్తికి ఇచ్చినట్టు గుర్తించి క్యాష్‌బుక్‌లో జీతంగా రాస్తుంది. ఒకరిని నొక్కితే వారి నెల.',
  ]),
  '/biz/:id/staff/tasks': _H('Tasks', 'పనులు', [
    'Give a task to a person — their phone rings. They tick it when done.',
    'Late tasks show in red and in the night report.',
  ], [
    'ఒకరికి పని ఇవ్వండి — వారి ఫోన్ మోగుతుంది. అయ్యాక వారు ✓ పెడతారు.',
    'ఆలస్యమైన పనులు ఎరుపులో, రాత్రి రిపోర్ట్‌లో కనిపిస్తాయి.',
  ]),
  '/biz/:id/staff/setup': _H('Attendance setup', 'హాజరు సెటప్', [
    "Tap a row to change it: the method (each person's phone, the shop phone, or both), work hours, lateness allowed, how near the shop counts, no-cheating switches, shop holidays.",
    'The big button sets the shop location: stand in the shop and tap it once. A fake-GPS app is never taken as the shop.',
  ], [
    'ఒక వరుస నొక్కి మార్చండి: పద్ధతి (ప్రతి ఒక్కరి ఫోన్, షాప్ ఫోన్, లేదా రెండూ), పని టైం, ఆలస్యం ఓకే, షాప్‌కి ఎంత దగ్గర, మోసం రాకుండా స్విచ్‌లు, షాప్ సెలవులు.',
    'పెద్ద బటన్ షాప్ లొకేషన్ పెడుతుంది: షాప్ లో నిలబడి ఒక్కసారి నొక్కండి. నకిలీ GPS యాప్ ఉంటే షాప్ గా తీసుకోదు.',
  ]),
  '/biz/:id/menu': _H('Menu & items', 'మెనూ & ఐటమ్స్', [
    'The number on top is how many items you have. Tap a section to see its items; search finds an item by name or number in every section.',
    'The big button adds items. Sort with AI, menu photo and the old page are in the three-dots menu.',
  ], [
    'పైన ఉన్న సంఖ్య మీ ఐటమ్స్. విభాగం నొక్కితే దాని ఐటమ్స్; వెతుకుడు అన్ని విభాగాల్లో పేరు / నంబర్‌తో వెతుకుతుంది.',
    'పెద్ద బటన్ ఐటమ్స్ చేరుస్తుంది. AI తో సర్దు, మెనూ ఫోటో, పాత పేజీ మూడు చుక్కల మెనూలో ఉన్నాయి.',
  ]),
  '/biz/:id/menu/sort': _H('Sort with AI', 'AI తో సర్దు', [
    'AI reads the item names in parts at the same time — it can take a minute or two.',
    'Open a section to move an item. Nothing changes until you tap Save.',
  ], [
    'AI ఐటమ్ పేర్లను భాగాలుగా ఒకేసారి చదువుతుంది — 1–2 నిమిషాలు పట్టవచ్చు.',
    'విభాగం తెరిచి ఐటమ్ మార్చవచ్చు. సేవ్ నొక్కే వరకు ఏదీ మారదు.',
  ]),
  '/biz/:id/menu/section/:name': _H('One section', 'ఒక విభాగం', [
    'Each item shows its price and whether it is out today; tap one to open it (price, on / off, details).',
    'The three-dots menu shows only what is out today, or opens the old page with veg / non-veg and most-sold filters.',
  ], [
    'ప్రతి ఐటమ్ ధర, ఈ రోజు లేదా అనేది చూపిస్తుంది; నొక్కితే ఆ ఐటమ్ తెరుచుకుంటుంది (ధర, ఆన్ / ఆఫ్, వివరాలు).',
    'మూడు చుక్కల మెనూలో ఈ రోజు లేనివి మాత్రమే చూడవచ్చు, లేదా వెజ్ / నాన్-వెజ్, ఎక్కువ అమ్మినవి చిప్స్ ఉన్న పాత పేజీ తెరవవచ్చు.',
  ]),
  '/biz/:id/menu/item/:pid': _H('One item', 'ఒక ఐటమ్', [
    'Tap a button to change the price, today\'s switch, the veg mark or the section.',
    'GST, HSN, stock and the photo are under "GST, photo & details".',
  ], [
    'ధర, ఈ రోజు స్విచ్, వెజ్ గుర్తు, విభాగం మార్చడానికి బటన్ నొక్కండి.',
    'GST, HSN, స్టాక్, ఫోటో "GST, ఫోటో & వివరాలు" లో.',
  ]),
  '/me/business/:id/profile': _H('Business details', 'బిజినెస్ వివరాలు', [
    'Fill the four ★ boxes: what you sell, about, address, open hours.',
    'The rest is optional: WhatsApp, website, social pages, offers, delivery. Tap Save.',
    'ASKODOX checks the details before the shop shows as verified.',
  ], [
    '★ ఉన్న నాలుగు బాక్సులు నింపండి: ఏం అమ్ముతారు, బిజినెస్ గురించి, అడ్రస్, తెరిచి ఉండే సమయం.',
    'మిగతావి మీ ఇష్టం: వాట్సాప్, వెబ్‌సైట్, సోషల్ పేజీలు, ఆఫర్లు, డెలివరీ. సేవ్ నొక్కండి.',
    'ASKODOX వివరాలు చూసిన తర్వాతే షాప్ వెరిఫైడ్ గా కనిపిస్తుంది.',
  ]),
  '/me/business/:id/bill': _H('Bill', 'బిల్లు', [
    'Three steps. 1: tap what they took (tap again = more, hold = type the weight; no items yet = type the amount).',
    '2: tap how they paid — cash, online (your QR shows) or due (name + pay date). 3: done — WhatsApp or print.',
    'Or press the mic: "12 number 2, UPI". GST, advance and editing a bill are in ⋮ → full bill page.',
  ], [
    'మూడు స్టెప్స్. 1: ఏం ఇచ్చారో నొక్కండి (మళ్ళీ నొక్కితే ఇంకా, పట్టుకుంటే బరువు టైప్; ఐటమ్స్ లేకపోతే మొత్తం టైప్).',
    '2: ఎలా కట్టారో నొక్కండి — క్యాష్, ఆన్‌లైన్ (మీ QR వస్తుంది), బాకీ (పేరు + కట్టే రోజు). 3: అయింది — WhatsApp లేదా ప్రింట్.',
    'లేదా మైక్ నొక్కి చెప్పండి: "12 నంబర్ 2, UPI". GST, అడ్వాన్స్, బిల్లు మార్పు ⋮ → పూర్తి బిల్లు పేజీలో.',
  ]),
  '/me/following': _H('Shops I follow', 'నేను ఫాలో చేస్తున్న షాప్‌లు', [
    'Shops you follow appear here. Tap one to see it and its updates.',
    'Following is free and anyone can do it; a shop owner can follow other shops too.',
  ], [
    'మీరు ఫాలో చేసే షాప్‌లు ఇక్కడ ఉంటాయి. ఒకదాన్ని నొక్కి, దాని వివరాలు చూడండి.',
    'ఫాలో చేయడం ఉచితం. ఎవరైనా చేయవచ్చు; షాప్ యజమాని ఇతర షాప్‌లనూ ఫాలో చేయవచ్చు.',
  ]),
  '/shops/:id/post': _H("Today's post", 'ఈ రోజు పోస్ట్', [
    'Write one line in Telugu or English. The picture shows your shop name and ASKODOX.',
    'One post a day. Followers of your shop see it in their shop updates.',
  ], [
    'ఒక లైన్ తెలుగులో లేదా English లో రాయండి. చిత్రంలో మీ షాప్ పేరు, ASKODOX ఉంటాయి.',
    'రోజుకు ఒక్క పోస్ట్. మీ షాప్‌ను ఫాలో చేసేవారికి షాప్ అప్‌డేట్స్‌లో కనిపిస్తుంది.',
  ]),
  '/me/shop-feed': _H('Shop updates', 'షాప్ అప్‌డేట్స్', [
    'Pictures from the shops you follow. Share sends the picture and its caption.',
    'The ASKODOX line is part of the picture, so it stays when shared.',
  ], [
    'మీరు ఫాలో చేసే షాప్‌ల చిత్రాలు. షేర్ చేస్తే చిత్రం, క్యాప్షన్ వెళ్తాయి.',
    'ASKODOX లైన్ చిత్రంలోనే ఉంటుంది, షేర్ చేసినా అలాగే ఉంటుంది.',
  ]),
  '/me/ai-credits': _H('AI Credits', 'AI క్రెడిట్స్', [
    'Your AI Credits balance and what each AI use costs (only when charging is on).',
    'Recharge opens Razorpay; credits are added only after Razorpay confirms the payment.',
    'Credits are only for ASKODOX AI — not cash, not transferable, never used to pay a seller.',
  ], [
    'మీ AI Credits బ్యాలెన్స్, ఒక్కో AI వాడకానికి ఎంత (charging on అయినప్పుడే).',
    'రీఛార్జ్ Razorpay తెరుస్తుంది; Razorpay confirm చేశాకే credits చేరతాయి.',
    'Credits ASKODOX AI కి మాత్రమే — cash కాదు, వేరేవాళ్ళకు పంపలేరు, seller కి కట్టడానికి వాడరు.',
  ]),
  '/me/payments': _H('Money', 'మనీ', [
    'Today shows the payments your phone heard and how many times it spoke them.',
    'These totals come from phone notifications, not the bank — check big amounts in your bank app.',
    'Show my QR and My accounts open your own UPI / bank; Alerts switches the voice on.',
  ], [
    'ఈ రోజు ఫోన్ విన్న పేమెంట్లు, ఎన్నిసార్లు మాట్లాడిందో కనిపిస్తుంది.',
    'ఈ లెక్క ఫోన్ నోటిఫికేషన్ల నుంచి, బ్యాంక్ నుంచి కాదు — పెద్ద మొత్తాలు బ్యాంక్ యాప్‌లో చూసుకోండి.',
    '"నా QR చూపించు", "నా ఖాతాలు" మీ UPI / బ్యాంక్ తెరుస్తాయి; "అలర్ట్స్" వాయిస్ ఆన్ చేస్తుంది.',
  ]),
  '/money-home': _H('Money', 'మనీ', [
    'Buyer side = your own money (this month in / out); Seller side = the shop\'s money (today, dues, new orders). They never mix.',
    'Every page is an icon with its name. Press and hold to arrange: it sits wherever you drop it (the others shift), to the edge = the next screen. A folder: press, hold, let go → "Put in a folder".',
    '"−" hides a page (never deleted); "Hidden" brings it back; "Reset" puts the screen back as it came. Payment voice: tap a line to switch what the phone says, ▶ to hear it.',
  ], [
    'కొను వైపు = మీ సొంత డబ్బు (ఈ నెల వచ్చింది / పోయింది); అమ్ము వైపు = షాప్ డబ్బు (ఈ రోజు, బాకీ, కొత్త ఆర్డర్లు). రెండూ కలవవు.',
    'ప్రతి పేజీ ఒక ఐకాన్, కింద పేరు. పట్టుకుని లాగండి: ఎక్కడ వదిలితే అక్కడే కూర్చుంటుంది (మిగతావి జరుగుతాయి), అంచుకి లాగితే తర్వాతి స్క్రీన్. ఫోల్డర్: నొక్కి పట్టి వదలండి → "ఫోల్డర్‌లో పెట్టు".',
    '"−" పేజీని దాచుతుంది (తొలగించదు); "దాచినవి" లో తిరిగి పెట్టండి; "మొదటిలా" మొదట ఉన్నట్టు పెడుతుంది. పేమెంట్ వాయిస్: వరుస నొక్కి ఆన్ / ఆఫ్, ▶ తో వినండి.',
  ]),
  // Owner 2026-11-23: the కొను / అమ్ము page (bottom bar): everything of the side that is not money.
  '/mode': _H('Buy / Sell page', 'కొను / అమ్ము పేజీ', [
    'Tap కొను (Buy) or అమ్ము (Sell) on the bottom bar: that side\'s page opens. Money stays under "Money".',
    'Buy page: orders, shops you follow, shop updates. Shop page: orders, items, staff, customers, settings.',
    'Search at the top finds any page of this side. Press and hold a page to arrange it, like a phone.',
  ], [
    'కింద కొను లేదా అమ్ము నొక్కితే ఆ వైపు పేజీ తెరుచుకుంటుంది. డబ్బు "మనీ" లోనే ఉంటుంది.',
    'కొను పేజీ: ఆర్డర్లు, ఫాలో షాప్‌లు, షాప్ అప్‌డేట్స్. షాప్ పేజీ: ఆర్డర్లు, ఐటమ్స్, సిబ్బంది, కస్టమర్లు, సెట్టింగ్స్.',
    'పైన వెతికితే ఈ వైపు ఏ పేజీ అయినా దొరుకుతుంది. పేజీని పట్టుకుని ఫోన్ లాగా సర్దుకోవచ్చు.',
  ]),
  '/payment-voice': _H('Payment voice', 'పేమెంట్ వాయిస్', [
    'Tap a line to switch what the phone says out loud: money received, sent, bill / EMI paid, refund, cashback, pending, failed, bill due, autopay, money asked.',
    '▶ plays the exact words. The "looks fake" warning is always on — a fake message is never counted as money.',
  ], [
    'ఫోన్ ఏం చెప్పాలో వరుస నొక్కి ఆన్ / ఆఫ్ చేయండి: డబ్బు వచ్చింది, పంపారు, బిల్లు / EMI కట్టారు, రీఫండ్, క్యాష్‌బ్యాక్, పెండింగ్, ఫెయిల్, బిల్లు కట్టాలి, ఆటోపే, డబ్బు అడిగారు.',
    '▶ నొక్కితే అవే మాటలు వినిపిస్తాయి. "ఫేక్‌లా ఉంది" హెచ్చరిక ఎప్పుడూ ఆన్ — ఫేక్ మెసేజ్ డబ్బుగా లెక్కలోకి రాదు.',
  ]),
  '/me/dues': _H('Coming up', 'కట్టాల్సినవి', [
    'The number on top is what is due this week. The big button adds EMI, current bill, rent, recharge with the date; the phone says them 2 days before and on the day.',
    'Bills that came by SMS and payments that look like an EMI are at the top of the list — tap one to add it or say "Not this".',
    'Tap a due: Paid, Edit or Delete (asks once). The old page is in ⋮.',
  ], [
    'పైన నంబర్ = ఈ వారం కట్టాల్సింది. పెద్ద బటన్ EMI, కరెంట్ బిల్, అద్దె, రీఛార్జ్ తేదీతో జోడిస్తుంది; గడువుకు 2 రోజుల ముందు, ఆ రోజు ఫోన్ చెప్తుంది.',
    'SMS లో వచ్చిన బిల్లులు, EMI లా ఉన్న పేమెంట్లు list పైన ఉంటాయి — నొక్కి జోడించండి లేదా "ఇది కాదు" అనండి.',
    'ఒకదాన్ని నొక్కితే: కట్టాను, మార్చు, తొలగించు (ఒకసారి అడుగుతుంది). పాత పేజీ ⋮ లో.',
  ]),
  '/money': _H('My money', 'నా డబ్బు', [
    'Every payment, bill and account in one list: switch between your own money and each shop at the top.',
    'When a payment matches a bill, tap "Yes, join" -- nothing is joined without your tap. Tap a row to set what it was for.',
    'Upcoming payments: add EMI, current bill, rent, recharge; the phone says them 2 days before and on the day.',
  ], [
    'ప్రతి పేమెంట్, బిల్లు, ఖాతా ఒకే లిస్ట్‌లో: పైన మీ సొంతం / ప్రతి షాప్ మధ్య మారండి.',
    'పేమెంట్ ఒక బిల్‌కి సరిపోతే "అవును, జత చేయి" నొక్కండి — మీరు నొక్కకుండా ఏదీ జత అవ్వదు. వరుస నొక్కి "దేనికి" పెట్టండి.',
    'రాబోయే చెల్లింపులు: EMI, కరెంట్ బిల్, అద్దె, రీఛార్జ్ జోడించండి; గడువుకు 2 రోజుల ముందు, ఆ రోజు ఫోన్ చెప్తుంది.',
  ]),
  '/me/bills': _H('My bills', 'నా బిల్లులు', [
    'The number on top is what is left to pay on the bills shops sent to your number. Tap a bill to see it.',
    'Pay by UPI opens your UPI app with the amount filled in; the money goes straight to the shop. Not today? Tell the shop the date.',
    'After paying, tap "I have paid" so the shop checks and closes the bill. Paid bills are in the three-dots menu.',
  ], [
    'పైన ఉన్న సంఖ్య షాపులు మీ నంబర్‌కి పంపిన బిల్లుల్లో ఇంకా కట్టాల్సింది. బిల్లు నొక్కి చూడండి.',
    '"UPI లో కట్టు" నొక్కితే మొత్తం నిండిన UPI యాప్ తెరుచుకుంటుంది; డబ్బు నేరుగా షాప్‌కి వెళ్తుంది. ఇవాళ కాదా? షాప్‌కి తేదీ చెప్పండి.',
    'కట్టాక "కట్టేశాను" నొక్కితే షాప్ చూసి బిల్లు ముగిస్తుంది. కట్టినవి మూడు చుక్కల మెనూలో ఉన్నాయి.',
  ]),
  '/bills/:id': _H('Bill history', 'బిల్లుల హిస్టరీ', [
    'The number on top is the total of the bills below. Search by bill or phone number; the big button changes the days.',
    'Pending only, Paid and Remind / send (customer\'s ASKODOX app or WhatsApp) are in the old page (⋮).',
  ], [
    'పైన నంబర్ కింద ఉన్న బిల్లుల మొత్తం. బిల్ / ఫోన్ నంబర్‌తో వెతకండి; పెద్ద బటన్ రోజులు మారుస్తుంది.',
    '"బాకీ మాత్రమే", "కట్టారు", "గుర్తు చేయి / పంపు" (కస్టమర్ ASKODOX యాప్ / WhatsApp) పాత పేజీలో (⋮).',
  ]),
  '/me/payments/phone': _H('My phone payments', 'నా ఫోన్ పేమెంట్లు', [
    'Switch it on, then allow notification access for ASKODOX once.',
    'My apps / SMS: add or remove the apps and bank SMS you want read; rename or delete any of them.',
    'My accounts names the bank accounts; History lists every credit and debit — each row can be deleted.',
    'A bill, recharge, EMI or premium you paid shows as ONE payment that went out (the bank "Bill Paid" SMS, the app message and the company receipt join into one); a bill that only CAME is a note or an upcoming payment, never money paid.',
  ], [
    'ఆన్ చేసి, ASKODOX కి నోటిఫికేషన్ యాక్సెస్ ఒకసారి ఇవ్వండి.',
    'నా యాప్‌లు / SMS: మీకు కావలసిన యాప్‌లు, బ్యాంక్ SMS జోడించండి లేదా తీసేయండి; ఏదైనా పేరు మార్చవచ్చు, తొలగించవచ్చు.',
    'నా ఖాతాలు లో బ్యాంక్ ఖాతాలకు పేరు పెట్టండి; హిస్టరీ లో ప్రతి క్రెడిట్ / డెబిట్ ఉంటుంది — ప్రతి వరుస తొలగించవచ్చు.',
    'మీరు కట్టిన బిల్, రీఛార్జ్, EMI, ప్రీమియం ఒకే "వెళ్ళిన" పేమెంట్‌గా కనిపిస్తుంది (బ్యాంక్ "Bill Paid" SMS, యాప్ message, కంపెనీ రసీదు ఒకటిగా కలుస్తాయి); బిల్ వచ్చింది మాత్రమే అయితే అది నోట్ లేదా రాబోయే పేమెంట్ — కట్టిన డబ్బు కాదు.',
  ]),
  '/me/payment-methods': _H('My payment methods', 'నా పేమెంట్ పద్ధతులు', [
    'On top: the QR customers scan (your default UPI). Share or copy it from ⋮.',
    'The big button adds a UPI QR from ANY app or bank — pick its photo or photograph it — or type the UPI ID, or a bank account.',
    'Tap a saved one to make it the default or remove it (asks once). Bank numbers are stored encrypted; money goes straight to you.',
  ], [
    'పైన: కస్టమర్ స్కాన్ చేసే QR (మీ ముఖ్యమైన UPI). ⋮ లో షేర్ / కాపీ.',
    'పెద్ద బటన్: ఏ యాప్ / బ్యాంక్ UPI QR అయినా — ఫోటో ఎంచుకోండి లేదా తీయండి — లేదా UPI ID టైప్, లేదా బ్యాంక్ ఖాతా.',
    'సేవ్ చేసినదాన్ని నొక్కితే ముఖ్యమైనదిగా చేయొచ్చు లేదా తీసేయొచ్చు (ఒకసారి అడుగుతుంది). బ్యాంక్ నంబర్ ఎన్‌క్రిప్ట్; డబ్బు నేరుగా మీకే.',
  ]),
  '/me/payment-alerts': _H('Payment sound alerts', 'పేమెంట్ సౌండ్ అలర్ట్', [
    'Give your shop / business name and state once, then press "Start".',
    'With one shop, its alert page opens straight away; with several, pick the shop here.',
    'Staff, who hears it, voice and history are all on the shop\'s alert page.',
  ], [
    'మీ షాప్ పేరు, రాష్ట్రం ఒకసారి ఇచ్చి "మొదలుపెట్టు" నొక్కండి.',
    'ఒకే షాప్ ఉంటే దాని అలర్ట్ పేజీ నేరుగా తెరుచుకుంటుంది; ఎక్కువ ఉంటే ఇక్కడ షాప్ ఎంచుకోండి.',
    'సిబ్బంది, ఎవరు వింటారు, వాయిస్, హిస్టరీ — అన్నీ షాప్ అలర్ట్ పేజీలోనే.',
  ]),
  '/me/payment-alerts/:id': _H('Payment alerts', 'పేమెంట్ అలర్ట్స్', [
    'Do the setup card at the top first, one step at a time.',
    'Each row opens its own page: 1 This phone, 2 Who hears it, 3 Settings, 4 History.',
    'Big amounts: always check your bank app — alerts only say "received".',
  ], [
    'ముందు పైన ఉన్న సెటప్ కార్డ్ ఒక్కో అడుగు పూర్తి చేయండి.',
    'ప్రతి వరుస దాని పేజీ తెరుస్తుంది: 1 ఈ ఫోన్, 2 ఎవరు వింటారు, 3 సెట్టింగ్స్, 4 హిస్టరీ.',
    'పెద్ద మొత్తాలు ఎప్పుడూ బ్యాంక్ యాప్‌లో చూసుకోండి — అలర్ట్ "అందింది" అని మాత్రమే చెబుతుంది.',
  ]),
  '/me/payment-alerts/:id/:view': _H('Payment alerts — one part', 'పేమెంట్ అలర్ట్స్ — ఒక భాగం', [
    'This page is one part of Payment alerts; the back arrow returns to the list of parts.',
    'Status & tests switches alerts on and tests the speaker; Who hears it and Staff choose the people.',
    'Voice & quiet time sets the voice; Payment history lists every alert — check big amounts in your bank app.',
  ], [
    'ఈ పేజీ పేమెంట్ అలర్ట్స్‌లో ఒక భాగం; వెనక బాణం భాగాల జాబితాకు తీసుకెళ్తుంది.',
    'స్థితి & టెస్ట్ లో అలర్ట్స్ ఆన్ చేసి స్పీకర్ టెస్ట్ చేయండి; ఎవరు వింటారు, సిబ్బంది లో మనుషులను ఎంచుకోండి.',
    'వాయిస్ & నిశ్శబ్ద సమయం లో గొంతు; పేమెంట్ హిస్టరీ లో అన్ని అలర్ట్స్ — పెద్ద మొత్తాలు బ్యాంక్ యాప్‌లో చూసుకోండి.',
  ]),
  '/pos/:id/payment-alerts': _H('Payment alerts', 'పేమెంట్ అలర్ట్స్', [
    'Turn on alerts for the shop, then "Turn on" notification access and switch ASKODOX on in Android settings.',
    'Press "Speaker test" — connect a Bluetooth speaker first if you want the voice there.',
    'Every payment notification is listed with its time, app, voice status and "received" — check big amounts in your bank app.',
  ], [
    'షాపుకు అలర్ట్స్ ఆన్ చేసి, నోటిఫికేషన్ యాక్సెస్ "ఆన్ చేయండి" నొక్కి Android సెట్టింగ్స్‌లో ASKODOX ఆన్ చేయండి.',
    '"స్పీకర్ టెస్ట్" నొక్కండి — బ్లూటూత్ స్పీకర్‌లో కావాలంటే ముందు దాన్ని కనెక్ట్ చేయండి.',
    'ప్రతి పేమెంట్ నోటిఫికేషన్ సమయం, యాప్, వాయిస్ స్థితితో "అందింది" అని కనిపిస్తుంది — పెద్ద మొత్తాలు బ్యాంక్ యాప్‌లో చూసుకోండి.',
  ]),
  '/pos/:id/selfshop': _H('Self-shopping', 'సెల్ఫ్ షాపింగ్', [
    'The big number is today\'s entry code — show it at the entrance (the QR poster is in the ⋮ menu). It changes every day.',
    'The list shows who is shopping now; tap a list to open its exit check.',
    'Tap the big button and type the 4-digit exit code from the customer\'s phone. While it is off, the big button turns it on.',
  ], [
    'పెద్ద అంకె ఈ రోజు ప్రవేశ కోడ్ — ద్వారం దగ్గర చూపించండి (QR పోస్టర్ ⋮ మెనూలో ఉంది). అది రోజూ మారుతుంది.',
    'ఇప్పుడు ఎవరు షాపింగ్ చేస్తున్నారో లిస్ట్‌లో ఉంటుంది; లిస్ట్ నొక్కితే ఎగ్జిట్ చెక్ తెరుచుకుంటుంది.',
    'పెద్ద బటన్ నొక్కి కస్టమర్ ఫోన్‌లోని 4 అంకెల ఎగ్జిట్ కోడ్ రాయండి. ఆఫ్‌లో ఉంటే పెద్ద బటన్ ఆన్ చేస్తుంది.',
  ]),
  '/pos/:id/selfshop/:sid': _H('Exit check', 'ఎగ్జిట్ చెక్', [
    'On top is the total; below is the customer\'s list. Tap an item to take it off (it asks once).',
    'Ask the customer to lay all items with barcodes facing up and tap the big button: ONE photo is compared with the list.',
    'Check "not seen" items and quantities above one by hand; the big button then becomes Bill & take payment.',
  ], [
    'పైన మొత్తం, కింద కస్టమర్ లిస్ట్ ఉంటాయి. సరుకు నొక్కితే లిస్ట్ నుండి తీసేయవచ్చు (ఒకసారి అడుగుతుంది).',
    'కస్టమర్‌ని సరుకులు బార్‌కోడ్‌లు పైకి కనిపించేలా పెట్టమని పెద్ద బటన్ నొక్కండి: ఒకే ఫోటోను లిస్ట్‌తో పోలుస్తుంది.',
    '"కనబడలేదు" అన్నవి, ఒకటి కంటే ఎక్కువ ఉన్నవి చేతితో చూడండి; తర్వాత పెద్ద బటన్ "బిల్లు & చెల్లింపు" అవుతుంది.',
  ]),
  '/shop-scan': _H('Scan & shop', 'స్కాన్ చేసి కొనండి', [
    'Tap the big button and photograph the QR at the shop entrance (typing the 6-digit code is in the ⋮ menu).',
    'Tap Scan barcode for each item — it joins your list with the shop\'s price. Tap an item for one less / one more.',
    'Tap Checkout at the end of the list, show the big exit code at the counter, and pay there.',
  ], [
    'పెద్ద బటన్ నొక్కి షాప్ ద్వారం దగ్గర QR ఫోటో తీయండి (6 అంకెల కోడ్ రాయడం ⋮ మెనూలో ఉంది).',
    'ప్రతి సరుకుకి "బార్‌కోడ్ స్కాన్" నొక్కండి — షాప్ ధరతో మీ లిస్ట్‌లో చేరుతుంది. సరుకు నొక్కితే ఒకటి తగ్గించు / పెంచు.',
    'లిస్ట్ చివర "చెకౌట్" నొక్కి, కౌంటర్‌లో పెద్ద ఎగ్జిట్ కోడ్ చూపించి, అక్కడ డబ్బు ఇవ్వండి.',
  ]),
  '/me/shop-advances': _H('Shop advances', 'షాప్ అడ్వాన్సులు', [
    'Advances shops recorded for your number are listed here.',
    'Approve only what you really paid or agreed; tap "No" otherwise.',
    'ASKODOX keeps the record only — the money is with the shop.',
  ], [
    'షాప్‌లు మీ నంబర్‌కి నమోదు చేసిన అడ్వాన్సులు ఇక్కడ ఉంటాయి.',
    'మీరు నిజంగా ఇచ్చిన / ఒప్పుకున్నవి మాత్రమే ఆమోదించండి; లేదంటే "కాదు" నొక్కండి.',
    'ASKODOX రికార్డు మాత్రమే ఉంచుతుంది — డబ్బు షాప్ దగ్గర ఉంటుంది.',
  ]),
  // ------------------------------------------------------------- work mode
  '/work': _H('Work Mode', 'వర్క్ మోడ్', [
    'Pick a job, then walk: every step your phone counts does a little of that job.',
    '7,000 steps = one full work day. Jobs follow the real order, in half the real time.',
    'No points or prizes. Use "Add by hand" for treadmill steps; Sunday is a rest day.',
  ], [
    'ఒక పని ఎంచుకుని నడవండి: ఫోన్ లెక్కించే ప్రతి అడుగుతో ఆ పని కొంచెం జరుగుతుంది.',
    '7,000 అడుగులు = ఒక రోజు పూర్తి పని. పని అసలు క్రమంలో, నిజ సమయంలో సగంలో జరుగుతుంది.',
    'పాయింట్లు, బహుమతులు లేవు. ట్రెడ్‌మిల్ అడుగులకు "చేతితో నమోదు" వాడండి; ఆదివారం విశ్రాంతి.',
  ]),
  '/work/seva': _H('Seva / meditation', 'సేవ / ధ్యానం', [
    'Optional. Choose a practice and a time, then tap Start in a walking break.',
    'Only the minutes are kept on your phone; your choice is never stored.',
  ], [
    'ఐచ్ఛికం. ఒక పద్ధతి, సమయం ఎంచుకుని నడక విరామంలో "మొదలు" నొక్కండి.',
    'నిమిషాలు మాత్రమే మీ ఫోన్‌లో ఉంటాయి; మీ ఎంపిక ఎక్కడా నిల్వ చేయము.',
  ]),
  // ------------------------------------------------------------- smart tools
  '/tools': _H('Smart Tools', 'స్మార్ట్ టూల్స్', [
    'Tap a tool to open it. Faded tiles are not built yet — tap to see what they need.',
    'Results are estimates, never certified measurements.',
  ], [
    'టూల్ నొక్కి తెరవండి. మసకగా ఉన్నవి ఇంకా తయారు కాలేదు — నొక్కితే ఏం కావాలో చెబుతుంది.',
    'ఫలితాలు అంచనాలు మాత్రమే, సర్టిఫైడ్ కొలతలు కావు.',
  ]),
  '/tools/level': _H('Level', 'లెవెల్', [
    'Lay the phone flat (or on its edge) on the surface.',
    'The bubble is centred when the surface is level. Use "Zero here" for a case bump.',
  ], [
    'ఫోన్‌ని ఉపరితలంపై చదునుగా (లేదా అంచుపై) పెట్టండి.',
    'బుడగ మధ్యలో ఉంటే సమంగా ఉంది. కేస్ ఎత్తు ఉంటే "ఇక్కడ సున్నా" వాడండి.',
  ]),
  '/tools/compass': _H('Compass', 'దిక్సూచి', [
    'Hold the phone flat, away from metal and electronics.',
    'It shows magnetic north, not true north.',
  ], [
    'ఫోన్‌ని చదునుగా, లోహం / ఎలక్ట్రానిక్స్‌కి దూరంగా పట్టుకోండి.',
    'ఇది అయస్కాంత ఉత్తరం చూపిస్తుంది, నిజమైన ఉత్తరం కాదు.',
  ]),
  '/tools/measure-photo': _H('Measure from a photo', 'ఫోటోతో కొలత', [
    'Put an A4 sheet or bank card flat beside the object and take a straight photo.',
    'Tap the reference\'s two ends, then the object\'s two ends.',
  ], [
    'A4 పేపర్ లేదా బ్యాంక్ కార్డ్ వస్తువు పక్కనే చదునుగా పెట్టి నేరుగా ఫోటో తీయండి.',
    'రిఫరెన్స్ రెండు చివర్లు, తర్వాత వస్తువు రెండు చివర్లు నొక్కండి.',
  ]),
  '/tools/protractor': _H('Protractor', 'ప్రొట్రాక్టర్', [
    'Take a straight photo of the angle.',
    'Tap the corner first, then one point on each arm.',
  ], [
    'కోణాన్ని నేరుగా ఫోటో తీయండి.',
    'ముందు మూల నొక్కండి, తర్వాత ఒక్కో భుజంపై ఒక చోట.',
  ]),
  '/tools/magnifier': _H('Magnifier', 'మాగ్నిఫైయర్', [
    'Take a close photo of the small print.',
    'Pinch or use 2x / 4x / 8x to zoom; Contrast makes faint text darker.',
  ], [
    'చిన్న అక్షరాలకు దగ్గరగా ఫోటో తీయండి.',
    'వేళ్లతో లేదా 2x / 4x / 8x తో జూమ్ చేయండి; కాంట్రాస్ట్ మసక అక్షరాలను ముదురుగా చేస్తుంది.',
  ]),
  '/tools/light': _H('Light meter', 'వెలుతురు కొలత', [
    'Point the front of the phone at the light and tap Measure (or Live).',
  ], [
    'ఫోన్ ముందు భాగాన్ని వెలుతురు వైపు పెట్టి "కొలువు" (లేదా లైవ్) నొక్కండి.',
  ]),
  '/tools/sound': _H('Sound level', 'శబ్ద స్థాయి', [
    'Tap Measure; allow the microphone the first time.',
    'For an approximate dB, calibrate once next to a real sound meter.',
  ], [
    '"కొలువు" నొక్కండి; మొదటిసారి మైక్ అనుమతి ఇవ్వండి.',
    'అంచనా dB కోసం నిజమైన సౌండ్ మీటర్ పక్కన ఒకసారి సరిచేయండి.',
  ]),
  '/tools/vehicle-report': _H('Vehicle report', 'వాహన రిపోర్ట్', [
    'Take one photo of each side: front, rear, left, right.',
    'Tap Inspect, read the report, then share the PDF.',
    'It is not a roadworthiness certificate.',
  ], [
    'ఒక్కో వైపు ఒక ఫోటో: ముందు, వెనుక, ఎడమ, కుడి.',
    '"పరిశీలించు" నొక్కి రిపోర్ట్ చదవండి, తర్వాత PDF షేర్ చేయండి.',
    'ఇది రోడ్ యోగ్యత సర్టిఫికెట్ కాదు.',
  ]),
  '/tools/inspect': _H('AI photo inspection', 'AI ఫోటో పరిశీలన', [
    'Choose what you are checking, add photos, choose Quick / Deep / Expert.',
    'The report separates what was seen, what is likely and what a photo cannot tell.',
  ], [
    'ఏం చెక్ చేస్తున్నారో ఎంచుకోండి, ఫోటోలు చేర్చండి, Quick / Deep / Expert ఎంచుకోండి.',
    'కనిపించింది, అవకాశం ఉన్నది, ఫోటోతో చెప్పలేనిది రిపోర్ట్ వేరుగా చెబుతుంది.',
  ]),
  '/tools/calc/:id': _H('Calculator', 'లెక్కల టూల్', [
    'Fill in the sizes; the estimate appears as you type.',
    'Read the assumptions under the result.',
  ], [
    'కొలతలు నింపండి; టైప్ చేస్తుండగానే అంచనా వస్తుంది.',
    'ఫలితం కింద ఉన్న అంచనాల ఆధారాలు చదవండి.',
  ]),
  '/me/finance': _H('Personal Finance', 'Personal Finance (నా డబ్బు)', [
    'Personal Tax Assistant: income tax (new vs old regime) and GST estimates from the published rules.',
    'Smart Tricks and scam checklists help with money decisions; your shop advances, payment methods and AI Credits are here too.',
    'Estimates only: confirm with a chartered accountant or the official portal before filing.',
  ], [
    'Personal Tax Assistant: published rules నుండి income tax (new vs old regime), GST అంచనాలు.',
    'Smart Tricks, మోసాల checklists డబ్బు నిర్ణయాలకు సహాయం; మీ shop advances, payment methods, AI Credits కూడా ఇక్కడే.',
    'అంచనాలు మాత్రమే: file చేసే ముందు CA తో లేదా official portal లో confirm చేసుకోండి.',
  ]),
  '/intel/tax': _H('Income tax estimate', 'ఆదాయపు పన్ను అంచనా', [
    'Enter your income and deductions; compare new vs old regime.',
    'Confirm with a chartered accountant before filing.',
  ], [
    'మీ ఆదాయం, మినహాయింపులు నింపండి; కొత్త vs పాత విధానం పోల్చండి.',
    'ఫైల్ చేసే ముందు CA తో నిర్ధారించుకోండి.',
  ]),
  '/intel/gst': _H('GST tool', 'జీఎస్టీ టూల్', [
    'Check if you need GST registration, composition limits, or GST on an amount.',
  ], [
    'GST రిజిస్ట్రేషన్ కావాలా, కంపోజిషన్ పరిమితులు, ఒక మొత్తంపై GST చూడండి.',
  ]),
  '/intel/fraud': _H('Scam checklists', 'మోసాల చెక్‌లిస్టులు', [
    'Pick the kind of scam to see the warning signs and where to report.',
  ], [
    'మోసం రకం ఎంచుకుంటే హెచ్చరిక గుర్తులు, ఎక్కడ ఫిర్యాదు చేయాలో చూపిస్తుంది.',
  ]),
  '/intel/fraud/:id': _H('Scam checklist', 'మోసాల చెక్‌లిస్ట్', [
    'Go through the signs; if money was lost, report on 1930 / cybercrime.gov.in at once.',
  ], [
    'గుర్తులు చూడండి; డబ్బు పోతే వెంటనే 1930 / cybercrime.gov.in లో ఫిర్యాదు చేయండి.',
  ]),
  '/intel/tricks': _H('Smart Tricks', 'స్మార్ట్ ట్రిక్స్', [
    'Pick a calculator (buy vs rent, repair vs replace, bulk, unit price) and fill it in.',
  ], [
    'ఒక లెక్క ఎంచుకోండి (కొనడం vs అద్దె, రిపేర్ vs కొత్తది, బల్క్, యూనిట్ ధర) నింపండి.',
  ]),
  '/devices': _H('My devices', 'నా పరికరాలు', [
    'Bluetooth devices you added are listed here; tap one to see live readings.',
  ], [
    'మీరు చేర్చిన బ్లూటూత్ పరికరాలు ఇక్కడ ఉంటాయి; ఒకటి నొక్కితే లైవ్ రీడింగ్ చూపిస్తుంది.',
  ]),
  '/devices/add': _H('Add a device', 'పరికరం చేర్చు', [
    'Turn the device on, tap Scan, then pick it from the list.',
    'Only standard Bluetooth devices show readings.',
  ], [
    'పరికరం ఆన్ చేసి "స్కాన్" నొక్కండి, లిస్ట్‌లో నుండి ఎంచుకోండి.',
    'స్టాండర్డ్ బ్లూటూత్ పరికరాలు మాత్రమే రీడింగ్ చూపిస్తాయి.',
  ]),
  '/devices/compatibility': _H('Which devices work', 'ఏ పరికరాలు పనిచేస్తాయి', [
    'See which kinds of devices ASKODOX can read and which it cannot.',
  ], [
    'ASKODOX ఏ రకం పరికరాలను చదవగలదో, ఏవి చదవలేదో చూడండి.',
  ]),
  '/devices/live': _H('Live reading', 'లైవ్ రీడింగ్', [
    'Keep the device close; readings update as it sends them.',
  ], [
    'పరికరాన్ని దగ్గరగా ఉంచండి; అది పంపినప్పుడల్లా రీడింగ్ మారుతుంది.',
  ]),
  '/ptt': _H('Push-to-talk', 'వాకీ-టాకీ', [
    'Create a channel or join one with its code.',
    'Both phones need internet.',
  ], [
    'ఛానల్ తయారు చేయండి లేదా కోడ్‌తో చేరండి.',
    'రెండు ఫోన్లకూ ఇంటర్నెట్ కావాలి.',
  ]),
  '/ptt/:id': _H('Talk', 'మాట్లాడండి', [
    'Hold the big button while you talk; release to let others reply.',
  ], [
    'మాట్లాడేటప్పుడు పెద్ద బటన్ నొక్కి పట్టుకోండి; వదిలితే ఇతరులు మాట్లాడవచ్చు.',
  ]),
  // ------------------------------------------------------------------- POS
  '/pos': _H('Shop billing', 'షాప్ బిల్లింగ్', [
    'Which shop? Tap your shop to open it. The big button adds a shop (name, GST type, State).',
  ], [
    'ఏ షాపు? మీ షాపు నొక్కి తెరవండి. పెద్ద బటన్ కొత్త షాపు చేరుస్తుంది (పేరు, GST రకం, రాష్ట్రం).',
  ]),
  '/pos/:id': _H('Shop dashboard', 'షాప్ డ్యాష్‌బోర్డ్', [
    'Counter bill to sell; Stock & barcodes to add what you sell.',
    'Customer list for dues; Close the day at night.',
  ], [
    'అమ్మడానికి "కౌంటర్ బిల్లు"; అమ్మేవి చేర్చడానికి "స్టాక్ & బార్‌కోడ్".',
    'బాకీలకు "కస్టమర్ల లిస్ట్"; రాత్రి "రోజు ముగింపు".',
  ]),
  '/pos/:id/sale': _H('Counter bill', 'కౌంటర్ బిల్లు', [
    'Tap items (or scan a barcode photo) to add them.',
    'Tap Pay, add how the customer paid, then Issue.',
  ], [
    'సరుకులు నొక్కి చేర్చండి (లేదా బార్‌కోడ్ ఫోటో స్కాన్ చేయండి).',
    '"పే" నొక్కి కస్టమర్ ఎలా కట్టారో చేర్చి "ఇష్యూ" నొక్కండి.',
  ]),
  '/pos/:id/items': _H('Stock & barcodes', 'స్టాక్ & బార్‌కోడ్', [
    'The number on top is how many items you have. Search the list and tap an item to open it. The big button adds an item.',
    'Ready list, combo offers, where to sell (POS / Online / Both) and the old page with offer / stock switches are in the menu ⋮.',
  ], [
    'పైన నంబర్ మీ సరుకుల సంఖ్య. లిస్ట్‌లో వెతికి, సరుకు నొక్కితే తెరుచుకుంటుంది. పెద్ద బటన్ సరుకు చేరుస్తుంది.',
    'రెడీ లిస్ట్, కాంబో ఆఫర్లు, ఎక్కడ అమ్మాలి (POS / ఆన్‌లైన్ / రెండూ), ఆఫర్ / స్టాక్ ఉన్న పాత పేజీ ⋮ మెనూలో.',
  ]),
  '/pos/:id/catalogue': _H('Ready list', 'రెడీ లిస్ట్', [
    '1 Pick a group of items. 2 Tap the items you sell (a tick stays when you go back for another group).',
    '3 Type YOUR price for each (size, and GST % if registered) and tap Add — items already in your shop are skipped.',
    'Kind of business (which ready list you get) is in ⋮. We never add brands or prices.',
  ], [
    '1 సరుకుల రకం ఎంచుకోండి. 2 మీరు అమ్మేవి నొక్కండి (వేరే రకం కోసం వెనక్కి వెళ్ళినా టిక్ ఉంటుంది).',
    '3 ప్రతి దానికీ మీ ధర రాయండి (సైజు, GST ఉంటే GST %), "చేర్చు" నొక్కండి — షాప్‌లో ఇప్పటికే ఉన్నవి వదిలేస్తాం.',
    'వ్యాపార రకం (ఏ రెడీ లిస్ట్ రావాలి) ⋮ లో ఉంది. బ్రాండ్‌లు, ధరలు మేము పెట్టము.',
  ]),
  '/pos/:id/item/:pid': _H('Item details', 'సరుకు వివరాలు', [
    'The number on top = required details still missing. Tap a detail (size, colour, brand …) to pick or type it; the sheet says what to write.',
    'What the item name already says is filled for you — check those, then tap Save.',
    '"Fill from my words", the online price, rates by quantity, photo and units are in ⋮.',
  ], [
    'పైన నంబర్ = ఇంకా కావాల్సిన తప్పనిసరి వివరాలు. వివరం (సైజు, రంగు, బ్రాండ్ …) నొక్కి ఎంచుకోండి / రాయండి; ఏం రాయాలో అక్కడే చెబుతుంది.',
    'సరుకు పేరులో ఉన్నవి ఆటోగా నిండుతాయి — సరిచూసి "సేవ్" నొక్కండి.',
    '"నా మాటలతో నింపు", ఆన్‌లైన్ ధర, రేట్లు, ఫోటో, యూనిట్లు ⋮ లో ఉన్నాయి.',
  ]),
  '/pos/:id/customers': _H('Customer list', 'కస్టమర్ల లిస్ట్', [
    'The number on top is what customers owe you. Tap a customer for bills and payments.',
    'The big button adds a customer in 3 steps: name, phone, done. Search a name above the list.',
  ], [
    'పైన సంఖ్య కస్టమర్ల నుంచి మీకు రావాల్సింది. కస్టమర్ నొక్కితే బిల్లులు, చెల్లింపులు.',
    'పెద్ద బటన్ 3 స్టెప్స్‌లో కస్టమర్‌ని చేరుస్తుంది: పేరు, ఫోన్, అయింది. లిస్ట్ పైన పేరు వెతకవచ్చు.',
  ]),
  '/pos/:id/dues': _H('Baaki reminders', 'బాకీ గుర్తులు', [
    'The number on top is the baaki to collect. Tap "Remind next" -- WhatsApp opens with the message and pay link ready.',
    'Tap a name for a new pay date. Customers on ASKODOX are reminded in the app by themselves.',
    'Where it is offered, the owner can turn on "Automatic WhatsApp" in the ⋮ menu: the others get the reminder by itself, once a day.',
  ], [
    'పైన నంబర్ రావాల్సిన బాకీ. "తర్వాతి వారికి గుర్తు చేయి" నొక్కండి — మెసేజ్, పే లింక్‌తో WhatsApp తెరుచుకుంటుంది.',
    'పేరు నొక్కి కొత్త తేదీ పెట్టండి. ASKODOX ఉన్న కస్టమర్లకు యాప్‌లో తానే గుర్తు చేస్తాం.',
    'అందుబాటులో ఉన్నచోట ఓనర్ ⋮ మెనూలో "ఆటోమేటిక్ WhatsApp" ఆన్ చేయొచ్చు: మిగతావారికి రోజుకి ఒకసారి గుర్తు దానంతట అదే వెళ్తుంది.',
  ]),
  '/pos/:id/customers/:cid': _H('Customer account', 'కస్టమర్ ఖాతా', [
    'The number on top is the baaki to collect. Money came? Tap "Money received": 1 how much, 2 how paid, 3 done.',
    'Shop advance: every change waits for the customer\'s approval in their app. Other months and the old page: ⋮.',
  ], [
    'పైన నంబర్ రావాల్సిన బాకీ. డబ్బు వచ్చిందా? "డబ్బు వచ్చింది" నొక్కండి: 1 ఎంత, 2 ఎలా, 3 అయింది.',
    'షాప్ అడ్వాన్స్: ప్రతి మార్పుకీ కస్టమర్ తమ యాప్‌లో ఆమోదించాలి. ఇతర నెలలు, పాత పేజీ: ⋮.',
  ]),
  '/crm': _H('Business CRM', 'Business CRM', [
    'Opens the CRM of your shop (with more than one shop, tap the shop).',
    'No shop yet? The big button adds it: the CRM works on your shop customers, bills and staff.',
  ], [
    'మీ shop CRM తెరుస్తుంది (ఒకటి కంటే ఎక్కువ shops ఉంటే shop నొక్కండి).',
    'Shop ఇంకా లేదా? పెద్ద బటన్ చేరుస్తుంది: CRM మీ shop customers, bills, staff మీదే పని చేస్తుంది.',
  ]),
  '/pos/:id/agents': _H('AI agents', 'AI Agents', [
    'Only the agents your role allows: owner, sales, support, finance, inventory, HR, tax.',
    'Answers come from your shop records. Money, stock, complaint closing and staff changes are only proposed; an owner / manager approves them here.',
  ], [
    'మీ role కి అనుమతి ఉన్న agents మాత్రమే: owner, sales, support, finance, inventory, HR, tax.',
    'జవాబులు shop records నుండే. డబ్బు, stock, complaint close, staff మార్పులు propose మాత్రమే; owner / manager ఇక్కడ approve చేయాలి.',
  ]),
  '/pos/:id/agents/:agent': _H('Agent', 'Agent', [
    'Ask a question or read today\'s summary; "Facts used" shows exactly what the AI read.',
    'Tap a suggestion to do it; sensitive ones go for approval first.',
  ], [
    'ప్రశ్న అడగండి లేదా ఈరోజు summary చదవండి; "వాడిన facts" లో AI ఏం చదివిందో కనిపిస్తుంది.',
    'Suggestion నొక్కితే చేస్తుంది; sensitive వాటికి ముందు approval కావాలి.',
  ]),
  '/me/agent': _H('My helper', 'నా సహాయకుడు', [
    'Ask in your words or with the mic: what you owe, shop advances waiting for you, your saved ways to be paid.',
    'It answers from your own records only and never pays, approves or messages anyone. Shop advances are in ⋮.',
  ], [
    'మీ మాటల్లో లేదా మైక్‌తో అడగండి: ఎవరికి ఎంత బాకీ, మీ కోసం ఆగిన shop advances, మీ payment methods.',
    'మీ records నుండి మాత్రమే చెబుతుంది; మీ తరఫున pay / approve చేయదు, ఎవరికీ పంపదు. Shop advances ⋮ లో.',
  ]),
  '/pos/:id/deliveries': _H('Send delivery', 'డెలివరీ పంపు', [
    'Say it in one line: "Uyyuru to Param, one cake, collect 250" — the job card fills itself (≈ km / minutes too).',
    'Choose who goes: green = free first, orange = on a job, red = busy / off. Ask everyone free or one person.',
    'Answers come back: now / 10 / 20 / 30 min / can\'t. Tap "Give" — or switch on "first \'now\' gets it".',
    'Every job has the shop order number (#12): cash, your UPI QR, the day report and complaints use it.',
  ], [
    'ఒక్క లైన్ లో చెప్పండి: "ఉయ్యూరు నుంచి పారం కి కేక్ డెలివరీ, 250 రూపాయలు" — job card దానంతట అదే నిండుతుంది (≈ km / నిమిషాలు కూడా).',
    'ఎవరు వెళ్ళాలో ఎంచుకోండి: ఆకుపచ్చ = ఖాళీ (ముందు), ఆరెంజ్ = పనిలో, ఎరుపు = బిజీ / ఆఫ్. ఖాళీగా ఉన్న అందరినీ లేదా ఒక్కరిని అడగండి.',
    'జవాబులు వస్తాయి: వెంటనే / 10 / 20 / 30 ని. / కుదరదు. "ఇవ్వు" నొక్కండి — లేదా "వెంటనే అన్న మొదటివాళ్ళకి" switch ఆన్ చేయండి.',
    'ప్రతి పనికీ షాప్ ఆర్డర్ నంబర్ (#12): క్యాష్, మీ UPI QR, రోజు రిపోర్ట్, ఫిర్యాదులు అన్నీ దానితోనే.',
  ]),
    '/me/deliveries': _H('My delivery work', 'నా డెలివరీ పని', [
    'Top: your colour. Tap free / on a job / off. Not changed for 3 hours = grey; after 11 PM = red.',
    'The list: the job you are on first, then the shops asking you. Tap one to answer "I\'ll come now", 10 / 20 / 30 min or can\'t.',
    'On a job: Directions opens Google Maps; UPI / QR shows the SHOP OWNER\'s QR with the amount. Tap how it was paid when done.',
    'The big button opens the first job. The old page is in the menu (three dots).',
  ], [
    'పైన మీ రంగు. ఖాళీ / పనిలో / ఆఫ్ నొక్కండి. 3 గంటలు మార్చకపోతే బూడిద; రాత్రి 11 తర్వాత ఎరుపు.',
    'లిస్ట్: మీరు ఉన్న పని ముందు, తర్వాత అడుగుతున్న షాపులు. ఒకటి నొక్కి "వెంటనే వస్తా", 10 / 20 / 30 ని. లేదా "కుదరదు" చెప్పండి.',
    'పనిలో: "దారి చూపించు" Google Maps తెరుస్తుంది; UPI / QR = షాప్ ఓనర్ QR. అయ్యాక డబ్బు ఎలా వచ్చిందో నొక్కండి.',
    'పెద్ద బటన్ మొదటి పనిని తెరుస్తుంది. పాత పేజీ మెనూ (మూడు చుక్కలు) లో ఉంది.',
  ]),
  '/pos/:id/team': _H('Workers & team', 'పని వాళ్ళు & టీమ్', [
    'The number on top is the people in your team. Tap a person to call them.',
    'The big button finds new workers (old page). Documents, monthly posting and registration are there too.',
  ], [
    'పైన సంఖ్య మీ టీమ్‌లో ఉన్నవాళ్ళు. ఒకరిని నొక్కితే కాల్ చేయవచ్చు.',
    'పెద్ద బటన్ కొత్త పని వాళ్ళని వెతుకుతుంది (పాత పేజీ). పత్రాలు, నెలవారీ పోస్టింగ్, రిజిస్ట్రేషన్ కూడా అక్కడే.',
  ]),
  '/me/family-list': _H('Family shopping list', 'ఇంటి షాపింగ్ లిస్ట్', [
    'One list for the whole home. The big number = things still needed.',
    'Tap the mic and say "sugar, milk, soap" or tap Add. Tap a thing when it is bought; ⋮ on a row = edit, not now, delete.',
    'Add family by their mobile number; they see the same list and get a notification when something is added. ⋮ on top finds the things nearby.',
  ], [
    'ఇంటి మొత్తానికి ఒకే లిస్ట్. పెద్ద సంఖ్య = ఇంకా కావాల్సినవి.',
    'మైక్ నొక్కి "చక్కెర, పాలు, సబ్బు" అని చెప్పండి లేదా చేర్చు నొక్కండి. కొన్నాక ఆ వస్తువుని నొక్కండి; వరుసలో ⋮ = మార్చు, ఇప్పుడు వద్దు, తీసేయి.',
    'ఇంట్లో వాళ్ళని మొబైల్ నంబర్‌తో చేర్చండి; వాళ్ళకీ అదే లిస్ట్ కనిపిస్తుంది, ఏదైనా చేర్చితే నోటిఫికేషన్ వస్తుంది. పైన ⋮ దగ్గర్లో ఎక్కడ దొరుకుతాయో చూపిస్తుంది.',
  ]),
  '/guide-session': _H('Getting to know you', 'మీ గురించి తెలుసుకోవడం', [
    'Pick how much time you have; any amount is fine and the rest waits for later.',
    'Answer by typing or the mic. "I did not understand" or "Why do you ask?" explains again in other words. Skip anything you do not want to tell.',
    'Details are kept only if you allow it, never given or sold, and ⋮ > "Delete what I told" removes them all.',
  ], [
    'మీ దగ్గర ఎంత టైం ఉందో ఎంచుకోండి; ఎంతైనా సరే, మిగతాది తర్వాత కొనసాగుతుంది.',
    'టైప్ చేసి లేదా మైక్ తో చెప్పండి. "అర్థం కాలేదు" లేదా "ఎందుకు అడుగుతున్నారు?" నొక్కితే వేరే మాటల్లో మళ్ళీ చెప్తాను. చెప్పడం ఇష్టం లేనిది వదిలేయండి.',
    'మీరు అనుమతిస్తేనే వివరాలు ఉంటాయి, ఎవరికీ ఇవ్వము, అమ్మము. ⋮ > "నేను చెప్పినవి తొలగించు" తో అన్నీ పోతాయి.',
  ]),
  '/phone-health': _H('Phone health', 'ఫోన్ ఆరోగ్యం', [
    'ASKODOX checks only its own settings on this phone: notifications, battery limit, autostart, payment voice permission, voice.',
    'A red or orange line: tap "Open that page" and do what the bold line says for your phone. Come back and it turns green by itself.',
    'Still a problem? "Send a report" sends only the phone maker, app version and these lines, and only when you press Send.',
  ], [
    'ASKODOX ఈ ఫోన్ లో తన సొంత settings మాత్రమే చూస్తుంది: నోటిఫికేషన్లు, బ్యాటరీ పరిమితి, autostart, payment voice అనుమతి, voice.',
    'ఎరుపు లేదా నారింజ లైన్: "ఆ page తెరువు" నొక్కి, మీ ఫోన్ కి bold లో చెప్పింది చేయండి. వెనక్కి వస్తే అదే ఆకుపచ్చ అవుతుంది.',
    'ఇంకా సమస్య ఉందా? "report పంపు" నొక్కితే ఫోన్ కంపెనీ పేరు, app వెర్షన్, ఈ లైన్లు మాత్రమే వెళ్తాయి. మీరు "పంపు" నొక్కితేనే.',
  ]),
  '/pos/:id/automations': _H('ASKODOX noticed', 'ASKODOX గమనించింది', [
    'Running low: items at their low mark, grouped by the supplier you last bought them from. "Make an order draft" only makes a draft in Purchase orders; you check and send it.',
    'Regulars not seen: customers who used to come often. Change the message, then "Open in WhatsApp" and send it yourself.',
    'Every card has "Not now" and "Do not show again". ASKODOX never orders, pays or messages by itself.',
  ], [
    'Stock తక్కువ: low mark కి చేరిన ఐటమ్స్, చివరిగా కొన్న supplier వారీగా. "Order draft చేయి" నొక్కితే Purchase orders లో draft మాత్రమే తయారవుతుంది; మీరు చూసి పంపాలి.',
    'రాని regular customers: ముందు తరచూ వచ్చినవాళ్ళు. Message మార్చుకుని "WhatsApp లో తెరువు" నొక్కి మీరే పంపండి.',
    'ప్రతి card కి "వద్దు", "ఇక చూపించకు" ఉంటాయి. ASKODOX తనంతట order, payment, message ఏదీ చేయదు.',
  ]),
  '/pos/:id/prices': _H('Change prices at once', 'ధరలు ఒకేసారి మార్చు', [
    'Step 1: all items, some sections, or tick the items.',
    'Step 2: up or down by % or ₹, or one price for all; choose rounding.',
    'Step 3: see every old → new price, then tap ✓. Old bills keep their prices; quantity rates, pack prices and a separate online price are not changed.',
  ], [
    'స్టెప్ 1: అన్ని ఐటమ్స్, కొన్ని విభాగాలు, లేదా టిక్ చేసినవి.',
    'స్టెప్ 2: % లేదా ₹ పెంచు / తగ్గించు, లేదా అన్నిటికీ ఒకే ధర; రౌండ్ ఎంచుకోండి.',
    'స్టెప్ 3: ప్రతి పాత → కొత్త ధర చూసి ✓ నొక్కండి. పాత బిల్లులు మారవు; క్వాంటిటీ రేట్లు, ప్యాక్ ధరలు, వేరే ఆన్‌లైన్ ధర మారవు.',
  ]),
  '/me/branches': _H('All my branches', 'నా అన్ని శాఖలు', [
    'On top: today\'s sales of all your linked branches together.',
    'The list: each branch with its bills and sales. Tap one to take it out of the link (asks once).',
    'The big button links your own shops: tick two or more. Delivery people of linked branches work as one pool; each branch keeps its own bills and GST.',
  ], [
    'పైన: లింక్ చేసిన అన్ని శాఖల ఈ రోజు సేల్స్ కలిపి.',
    'లిస్ట్: ప్రతి శాఖ బిల్లులు, సేల్స్ తో. ఒకటి నొక్కితే లింక్ నుంచి తీసేయొచ్చు (ఒకసారి అడుగుతుంది).',
    'పెద్ద బటన్ మీ సొంత షాపులను లింక్ చేస్తుంది: రెండు లేదా ఎక్కువ టిక్ చేయండి. లింక్ అయిన శాఖల delivery వాళ్ళు అందరూ కలిసి; ప్రతి శాఖకి దాని బిల్లులు, GST విడివిడిగా.',
  ]),
  '/me/work': _H('I want work', 'నేను పని చేస్తా', [
    'No card yet: pick the work you do, then your name, town and 18+. Businesses see your card, never your number.',
    'The big number = things waiting for your answer: work offered, your jobs, invites. The big button opens the first one.',
    'Tap a row: Take / No, Job done, Money received, Join / No, documents code or Leave. Saying No while free is a minus point.',
    'Your card + independent badge, your documents and the old page are in ⋮.',
  ], [
    'కార్డ్ లేకపోతే: మీరు చేసే పని ఎంచుకోండి, తర్వాత పేరు, ఊరు, 18+. Businesses కి కార్డ్ మాత్రమే, నంబర్ కాదు.',
    'పెద్ద నంబర్ = మీ జవాబు కోసం ఎదురుచూస్తున్నవి: పని, మీ పనులు, ఆహ్వానాలు. పెద్ద బటన్ మొదటిది తెరుస్తుంది.',
    'వరుస నొక్కండి: వెళ్తా / కుదరదు, పని అయింది, డబ్బు అందింది, చేరుతా / వద్దు, documents కోడ్ లేదా వదిలేయి. ఖాళీగా ఉండి కుదరదంటే మైనస్ పాయింట్.',
    'మీ కార్డ్ + స్వతంత్రుడు badge, documents, పాత పేజీ ⋮ లో ఉన్నాయి.',
  ]),
  '/hire': _H('Hire a worker', 'పని వాళ్ళు కావాలి', [
    'Your bookings are in one list; the big button "I need a worker" starts a new one.',
    '3 steps: what work -> where and when -> through whom (a business with its price, or an independent worker). Tap one to book.',
    'The worker\'s name and number come after booking. Tap a booking to rate it after the work (once) or to send a complaint.',
  ], [
    'మీ బుకింగ్స్ ఒకే list లో; పెద్ద బటన్ "పని వాళ్ళు కావాలి" కొత్తది మొదలుపెడుతుంది.',
    '3 స్టెప్స్: ఏ పని -> ఎక్కడ, ఎప్పుడు -> ఎవరి ద్వారా (ధరతో business, లేదా స్వతంత్రుడు). నొక్కితే బుక్.',
    'బుక్ అయ్యాక పని వాళ్ళ పేరు, నంబర్ వస్తాయి. పని అయ్యాక బుకింగ్ నొక్కి రేటింగ్ (ఒక్కసారే) లేదా ఫిర్యాదు.',
  ]),
  '/pos/:id/crm': _H('Enquiries', 'ఎంక్వైరీలు', [
    'The number on top is open enquiries. Tap one to follow up, quote or turn it into a customer.',
    'The big button adds a new enquiry. Quotations, complaints and reports are in the three-dot menu (old page).',
  ], [
    'పైన సంఖ్య తెరిచి ఉన్న ఎంక్వైరీలు. ఒకటి నొక్కి ఫాలోఅప్, కొటేషన్ లేదా కస్టమర్‌గా మార్చండి.',
    'పెద్ద బటన్ కొత్త ఎంక్వైరీ చేరుస్తుంది. కొటేషన్లు, ఫిర్యాదులు, రిపోర్ట్స్ మూడు చుక్కల మెనూలో (పాత పేజీ).',
  ]),
  '/pos/:id/crm/leads': _H('Leads & enquiries', 'Leads & Enquiries', [
    'Open enquiries on top, one list; tap a lead to work on it. A link with a stage filter opens the old filtered list.',
  ], [
    'పైన open enquiries, ఒకే list; lead నొక్కి పని చేయండి. Stage filter ఉన్న link పాత list తెరుస్తుంది.',
  ]),
  '/pos/:id/crm/lead/:lid': _H('Lead', 'Lead వివరాలు', [
    'The number on top is what it is worth; below are follow-ups and what happened.',
    'The big button moves the stage forward (Won can point to the real bill). Lost, notes, follow-up, quotation, assign and customer are in the menu ⋮.',
  ], [
    'పైన నంబర్ దీని విలువ; కింద ఫాలో-అప్‌లు, జరిగినవి.',
    'పెద్ద బటన్ స్టేజ్‌ని ముందుకు జరుపుతుంది (Won కి అసలు బిల్లు ఎంచుకోవచ్చు). Lost, నోట్స్, ఫాలో-అప్, కొటేషన్, అసైన్, కస్టమర్ ⋮ మెనూలో.',
  ]),
  '/pos/:id/crm/complaint/:cid': _H('Complaint', 'Complaint', [
    'The complaint is on top. The big button moves it to the next status; Resolved / Closed need how it was solved.',
    'Reminder, the bill and the customer history are in the menu ⋮.',
  ], [
    'పైన ఫిర్యాదు. పెద్ద బటన్ తర్వాతి స్టేటస్‌కి మారుస్తుంది; Resolved / Closed కి ఎలా పరిష్కరించారో రాయాలి.',
    'రిమైండర్, బిల్లు, కస్టమర్ హిస్టరీ ⋮ మెనూలో.',
  ]),
  '/pos/:id/crm/customer/:cid': _H('Customer history', 'Customer history', [
    'On top: how much this customer bought. Below: their bills, leads and complaints; tap one to open it.',
    'The big button opens their account / dues. A new lead or complaint is in the menu ⋮.',
  ], [
    'పైన: ఈ కస్టమర్ ఎంత కొన్నారు. కింద: బిల్లులు, leads, ఫిర్యాదులు; నొక్కితే తెరుచుకుంటుంది.',
    'పెద్ద బటన్ వారి ఖాతా / బాకీ తెరుస్తుంది. కొత్త lead / ఫిర్యాదు ⋮ మెనూలో.',
  ]),
  '/pos/:id/invoices': _H('Bills', 'బిల్లులు', [
    'The number on top is the total of your bills. Search by number or name; tap one to print, share, or make a credit note.',
  ], [
    'పైన నంబర్ మీ బిల్లుల మొత్తం. నంబర్ / పేరుతో వెతకండి; ఒకటి నొక్కి ప్రింట్, షేర్ లేదా క్రెడిట్ నోట్.',
  ]),
  '/pos/:id/invoice/:iid': _H('Bill', 'బిల్లు', [
    'The total is on top and the bill below. The big button is Next bill (right after billing) or Share PDF.',
    'Print, return (credit note) and cancel are in the menu ⋮. Issued bills are never edited.',
  ], [
    'పైన మొత్తం, కింద బిల్లు. పెద్ద బటన్: తర్వాతి బిల్లు (బిల్లు చేసిన వెంటనే) లేదా PDF షేర్.',
    'ప్రింట్, వాపసు (క్రెడిట్ నోట్), రద్దు ⋮ మెనూలో. ఇష్యూ చేసిన బిల్లు ఎప్పుడూ మార్చబడదు.',
  ]),
  '/pos/:id/day': _H('Close the day', 'రోజు ముగింపు', [
    'Three steps. 1: is today\'s online money right? Compare with your bank app (a difference -> today\'s bills).',
    '2: type the cash in the drawer — "should be" and the difference show live. 3: done — today\'s sales; send on WhatsApp.',
    'Closing is final; it asks once before closing.',
  ], [
    'మూడు స్టెప్స్. 1: ఈ రోజు ఆన్‌లైన్ డబ్బు సరేనా? బ్యాంక్ యాప్‌తో పోల్చండి (తేడా ఉంటే ఈ రోజు బిల్లులు).',
    '2: డ్రాయర్‌లో క్యాష్ టైప్ చేయండి — "ఉండాల్సింది", తేడా వెంటనే కనిపిస్తాయి. 3: అయింది — ఈ రోజు అమ్మకం; WhatsApp కి పంపండి.',
    'ముగించిన తర్వాత మార్చలేం; ముగించే ముందు ఒకసారి అడుగుతుంది.',
  ]),
  '/pos/:id/link': _H('My shop link', 'నా షాప్ లింక్', [
    'Three steps. 1: choose what your free page shows — menu + prices, call, directions, your own UPI, an offer line.',
    '2: pick a colour and a short English name: askodox.com/s/<name>. 3: done — send it on WhatsApp, copy it or print the QR poster.',
    'Customers order from the page without the app (name + phone): the order comes into your Live orders; WhatsApp is a backup. Money goes to your own UPI. Only the owner makes or changes the link (⋮).',
  ], [
    'మూడు స్టెప్స్. 1: మీ ఉచిత పేజీలో ఏమి చూపించాలో ఎంచుకోండి — మెనూ + ధరలు, కాల్, దారి, మీ సొంత UPI, ఆఫర్ లైన్.',
    '2: రంగు, English లో చిన్న పేరు ఎంచుకోండి: askodox.com/s/<పేరు>. 3: అయింది — WhatsApp లో పంపండి, కాపీ చేయండి లేదా QR పోస్టర్ ప్రింట్ చేయండి.',
    'యాప్ లేని కస్టమర్ కూడా పేజీ నుండి (పేరు + ఫోన్) ఆర్డర్ చేస్తారు: ఆర్డర్ మీ Live orders లోకి వస్తుంది; WhatsApp బ్యాకప్. డబ్బు మీ సొంత UPI కే. లింక్ తయారు / మార్చడం ఓనర్ మాత్రమే (⋮).',
  ]),
  '/pos/:id/gst': _H('GST report', 'GST రిపోర్ట్', [
    'The number on top is the GST of the month; below it is split by rate. "Change month" picks another month.',
    'It is not a filed return. HSN and B2B / B2C are in the old page (⋮).',
  ], [
    'పైన నంబర్ ఈ నెల GST; కింద రేటు వారీగా. "నెల మార్చు" తో వేరే నెల చూడండి.',
    'ఇది ఫైల్ చేసిన రిటర్న్ కాదు. HSN, B2B / B2C పాత పేజీలో (⋮).',
  ]),
  '/pos/:id/staff': _H('Staff & roles', 'సిబ్బంది & పాత్రలు', [
    'The number on top is how many people accept orders. Tap a person to pause, change their job or remove them. The big button adds a person: number, then job.',
    'What each person may open (ticks) is on the old page in the menu ⋮.',
  ], [
    'పైన నంబర్ ఆర్డర్లు ఒప్పుకునేవారి సంఖ్య. వ్యక్తిని నొక్కితే ఆపడం, పని మార్చడం, తీసేయడం. పెద్ద బటన్ వ్యక్తిని చేరుస్తుంది: నంబర్, తర్వాత పని.',
    'ఎవరు ఏవి తెరవచ్చు (టిక్స్) ⋮ మెనూలోని పాత పేజీలో ఉంది.',
  ]),
  '/order-desk/enter': _H('Order at a shop / table', 'షాప్ / టేబుల్ ఆర్డర్', [
    'The big button photographs the QR on the shop or table; or search the shop by its name. The menu opens.',
    'A QR from the gallery and typing the code printed under the QR are in ⋮.',
    'Your earlier orders are listed here: tap one to follow it, or "Again" to order the same.',
  ], [
    'పెద్ద బటన్ షాప్ లేదా టేబుల్ మీది QR ఫోటో తీస్తుంది; లేదా షాప్ పేరు వెతకండి. మెనూ తెరుచుకుంటుంది.',
    'గ్యాలరీ నుంచి QR, QR కింద ఉన్న కోడ్ టైప్ చేయడం ⋮ లో ఉన్నాయి.',
    'మీ పాత ఆర్డర్లు ఇక్కడ కనిపిస్తాయి: నొక్కి ఫాలో చేయండి, లేదా "మళ్ళీ" నొక్కి అదే ఆర్డర్ చేయండి.',
  ]),
  '/order-desk': _H('Menu & order', 'మెనూ & ఆర్డర్', [
    'Tap an item to add one (tap again for more; press and hold for one less or a note) — or tap the mic and say it (2 chicken biryani).',
    'The big button moves on: choose dine in, takeaway or delivery. Delivery needs an address or a map pin.',
    'Check the total and tap Send order. You pay the shop directly; ASKODOX never holds the money.',
  ], [
    'ఐటమ్ నొక్కితే ఒకటి చేరుతుంది (మళ్ళీ నొక్కితే ఇంకొకటి; నొక్కి పట్టుకుంటే తగ్గించు / నోట్) — లేదా మైక్ నొక్కి చెప్పండి (2 చికెన్ బిర్యానీ).',
    'పెద్ద బటన్ ముందుకు తీసుకెళ్తుంది: ఇక్కడే తింటారా, పార్సిల్ లేదా డెలివరీనా ఎంచుకోండి. డెలివరీకి అడ్రస్ లేదా మ్యాప్ పిన్ కావాలి.',
    'మొత్తం చూసి "ఆర్డర్ పంపు" నొక్కండి. డబ్బు నేరుగా షాప్‌కే; ASKODOX డబ్బు పట్టుకోదు.',
  ]),
  '/order-desk/track/:oid': _H('My order', 'నా ఆర్డర్', [
    'On top: where your order is now. Below: each step with its time, then your items and the bill.',
    'The big button: how you will pay (cash, or the shop\'s UPI once billed) — or Rate it when it is done.',
    'Cancel (only before the shop accepts), Call the shop and the shop page are in ⋮. Eating here? "Need something?" is under the bill.',
  ], [
    'పైన: మీ ఆర్డర్ ఇప్పుడు ఎక్కడుందో. కింద: ప్రతి దశ సమయంతో, తర్వాత మీ ఐటమ్స్, బిల్లు.',
    'పెద్ద బటన్: ఎలా కడతారు (క్యాష్, లేదా బిల్లు రాగానే షాప్ UPI) — అయిపోయాక రేటింగ్.',
    'రద్దు (షాప్ ఒప్పుకోకముందే), షాప్‌కి కాల్, షాప్ పేజీ ⋮ లో. ఇక్కడ తింటుంటే "ఏమైనా కావాలా?" బిల్లు కింద ఉంది.',
  ]),
  '/shops/:id/book': _H('Book', 'బుక్ చేయండి', [
    'Choose the day, the time (or how many nights) and how many people, then "Show what is free".',
    'Tap what you want and give your name: it is booked at once and the shop is told. Pay the shop directly.',
  ], [
    'రోజు, సమయం (లేదా ఎన్ని రాత్రులు), ఎంత మంది ఎంచుకుని "ఖాళీ ఉన్నవి చూపించు" నొక్కండి.',
    'కావలసింది నొక్కి పేరు ఇవ్వండి: వెంటనే బుక్ అవుతుంది, షాప్‌కి తెలుస్తుంది. డబ్బు షాప్‌కే నేరుగా కట్టండి.',
  ]),
  '/finance/:id': _H('Finance offer', 'ఫైనాన్స్ ఆఫర్', [
    'Type or say your doubt, or tap a ready question. The answer comes only from the company\'s own document, with the page number.',
    'If it is not in the document, we say so. Tap "Yes, call me" only if you want our executive to call; you can cancel it.',
  ], [
    'మీ సందేహం రాయండి లేదా చెప్పండి, లేదా సిద్ధంగా ఉన్న ప్రశ్న నొక్కండి. జవాబు కంపెనీ document నుంచి మాత్రమే, పేజీ నంబర్‌తో వస్తుంది.',
    'Document లో లేకపోతే లేదని చెప్తాం. మా ఎగ్జిక్యూటివ్ కాల్ చేయాలంటేనే "అవును, కాల్ చేయండి" నొక్కండి; రద్దు కూడా చేయవచ్చు.',
  ]),
  '/try-on': _H('Try it', 'ట్రై చేసి చూడు', [
    'On me: your photo + the item\'s photo (dress, chappal, frame, hairstyle). In my home: a photo of the room / table / wall + the item.',
    'Tap "Show me": one AI picture in 30-60 seconds, marked as an AI picture. Share it, or Report a bad one.',
  ], [
    'నా మీద: మీ ఫోటో + వస్తువు ఫోటో (డ్రెస్, చెప్పులు, ఫ్రేమ్, హెయిర్ స్టైల్). నా ఇంట్లో: గది / టేబుల్ / గోడ ఫోటో + వస్తువు.',
    '"చూపించు" నొక్కండి: 30-60 సెకన్లలో ఒక AI చిత్రం, AI అని గుర్తుతో. షేర్ చేయండి, బాగోలేకపోతే రిపోర్ట్ చేయండి.',
  ]),
  '/me/bookings': _H('My bookings', 'నా బుకింగ్స్', [
    'Every room, chair, slot or hall you booked. Cancel one that has not started yet.',
  ], [
    'మీరు బుక్ చేసిన రూమ్‌లు, కుర్చీలు, సమయాలు, హాల్స్. ఇంకా మొదలు కానిది రద్దు చేయొచ్చు.',
  ]),
  '/me/jobs': _H('My jobs', 'నా జాబ్స్', [
    'What you gave a shop to repair, stitch or make: its token, where it is, and what is left to pay.',
  ], [
    'రిపేర్ / కుట్టడం / తయారు కోసం షాప్‌కి ఇచ్చినవి: టోకెన్, ఎక్కడి వరకు వచ్చింది, ఇంకా ఎంత కట్టాలి.',
  ]),
  '/me/monthly': _H('My monthly plans', 'నా నెలవారీ', [
    'Plans you pay every month (milk, tuition, gym, PG) and what is left to pay this month.',
  ], [
    'ప్రతి నెల కట్టేవి (పాలు, ట్యూషన్, జిమ్, PG), ఈ నెల ఇంకా ఎంత కట్టాలి.',
  ]),
  '/biz/:id/bookings': _H('Bookings', 'బుకింగ్స్', [
    'The big number is today\'s bookings. Tap a booking: arrived, done, no show, cancelled, or UPI QR to collect.',
    'New bookings and what can be booked (rooms by day, chairs / OP by time) are on the old page in the top ⋮.',
  ], [
    'పెద్ద నంబర్ = ఈ రోజు బుకింగ్స్. బుకింగ్ నొక్కండి: వచ్చారు, అయిపోయింది, రాలేదు, రద్దు, లేదా డబ్బు కోసం UPI QR.',
    'కొత్త బుకింగ్, బుక్ చేసేవి (రూమ్‌లు రోజుల ప్రకారం, కుర్చీలు / OP సమయం ప్రకారం) పైన ⋮ లోని పాత పేజీలో.',
  ]),
  '/biz/:id/jobs': _H('Job cards', 'జాబ్ కార్డ్స్', [
    '"New job" = 3 steps: what came in, the estimate, done (you get a token number).',
    'Tap a job: Working / Ready / Delivered, or UPI QR to take the balance or an advance (money goes to the owner\'s UPI).',
  ], [
    '"కొత్త జాబ్" = 3 స్టెప్స్: ఏం వచ్చింది, అంచనా, అయింది (టోకెన్ నంబర్ వస్తుంది).',
    'జాబ్ నొక్కండి: పని జరుగుతోంది / రెడీ / ఇచ్చేశాం, లేదా మిగతా డబ్బు, అడ్వాన్స్ కోసం UPI QR (డబ్బు ఓనర్ UPI కే).',
  ]),
  '/biz/:id/monthly': _H('Monthly members', 'నెలవారీ సభ్యులు', [
    'The big number is what is still to come this month. Tap who paid, type how much, done.',
    'New members, plans, pause or stop are on the old page in the top ⋮. UPI QR is in ⋮ on the amount step.',
  ], [
    'పెద్ద నంబర్ = ఈ నెల ఇంకా రావాల్సింది. ఎవరు కట్టారో నొక్కండి, ఎంతో రాయండి, అయింది.',
    'కొత్త సభ్యులు, ప్లాన్లు, ఆపడం పైన ⋮ లోని పాత పేజీలో. UPI QR మొత్తం స్టెప్ లో ⋮ లో.',
  ]),
  '/shops/:id': _H('Shop page', 'షాప్ పేజీ', [
    'Photos, rating, hours, address and the shop\'s own Instagram / Facebook / YouTube links.',
    'Follow to get the shop\'s news in ASKODOX. Following on other apps you tap there yourself.',
    'Items show stars only. After you have bought here you can write one review of the shop with up to 3 photos; the owner can reply.',
  ], [
    'ఫోటోలు, రేటింగ్, సమయం, అడ్రస్, షాప్ వాళ్ళ ఇన్‌స్టాగ్రామ్ / ఫేస్‌బుక్ / యూట్యూబ్ లింకులు.',
    'ఫాలో నొక్కితే షాప్ వార్తలు ASKODOX లో వస్తాయి. ఇతర యాప్‌లలో ఫాలో మీరే అక్కడ నొక్కాలి.',
    'ఐటమ్స్‌కి నక్షత్రాలు మాత్రమే. ఇక్కడ కొన్న తర్వాత షాప్ గురించి ఒక రివ్యూ (3 ఫోటోల వరకు) రాయవచ్చు; ఓనర్ జవాబు ఇవ్వవచ్చు.',
  ]),
  '/desk/:id': _H('Incoming orders', 'వచ్చిన ఆర్డర్లు', [
    'The number on top is new orders waiting for you; new ones come first in the list.',
    'Tap an order: Accept or Reject, then the big button moves it one step (the customer is told).',
    'Bill it with cash, UPI or later. Delivery orders ask who takes it.',
    'New order opens the counter bill; Menu, Sales, QR and alerts are in the three-dot menu.',
  ], [
    'పైన ఉన్న సంఖ్య మీ కోసం వేచి ఉన్న కొత్త ఆర్డర్లు; కొత్తవి లిస్ట్‌లో ముందు ఉంటాయి.',
    'ఆర్డర్ నొక్కండి: అంగీకరించు లేదా వద్దు, తర్వాత పెద్ద బటన్ ఒక్క స్టెప్ ముందుకు తీసుకెళ్తుంది (కస్టమర్‌కి తెలుస్తుంది).',
    'క్యాష్, UPI లేదా తర్వాత అని బిల్లు చేయండి. డెలివరీ ఆర్డర్‌కి ఎవరు తీసుకెళ్తారో అడుగుతుంది.',
    'కొత్త ఆర్డర్ కౌంటర్ బిల్లు తెరుస్తుంది; మెనూ, అమ్మకాలు, QR, అలర్ట్స్ మూడు చుక్కల మెనూలో ఉన్నాయి.',
  ]),
  '/desk/:id/menu': _H('Menu', 'మెనూ', [
    'The number on top is how many items are on your menu. Tap an item: finished for today (comes back tomorrow), today only, change name or price, remove.',
    'The big button adds items: say or type them with prices (Idli 30), check the list, then Save. Nothing is saved before you check.',
    'Menu photos, shelf photos, AI sections and the full edit are in the old page, in the three-dots menu.',
  ], [
    'పైన ఉన్న సంఖ్య మీ మెనూలో ఎన్ని ఐటమ్స్ ఉన్నాయో. ఐటమ్ నొక్కండి: ఈ రోజు అయిపోయింది (రేపు మళ్ళీ వస్తుంది), ఈ రోజు మాత్రమే, పేరు / రేటు మార్చు, తీసేయి.',
    'పెద్ద బటన్ ఐటమ్స్ చేరుస్తుంది: రేటుతో చెప్పండి లేదా రాయండి (ఇడ్లీ 30), లిస్ట్ చూసి Save. చూసే వరకు ఏదీ సేవ్ కాదు.',
    'మెనూ ఫోటోలు, షెల్ఫ్ ఫోటోలు, AI తో విభాగాలు, పూర్తి మార్పు పాత పేజీలో, మూడు చుక్కల మెనూలో ఉన్నాయి.',
  ]),
  '/desk/:id/settings': _H('Order alerts', 'ఆర్డర్ అలర్ట్స్', [
    'Four steps of an order (new, kitchen, ready, delivery): tap one and choose who is told. Nobody chosen = the people of that role.',
    'The big button opens Staff, where you add people with a phone number and a role.',
    'The menu (three dots) has what a table can ask for (water, gravy, the bill), your welcome and thank-you words, and the old page.',
  ], [
    'ఆర్డర్ నాలుగు స్టెప్స్ (కొత్త, వంటగది, సిద్ధం, డెలివరీ): ఒకటి నొక్కి ఎవరికి చెప్పాలో ఎంచుకోండి. ఎవరినీ ఎంచుకోకపోతే ఆ పాత్ర ఉన్నవాళ్ళకి.',
    'పెద్ద బటన్ సిబ్బంది పేజీ తెరుస్తుంది; అక్కడ ఫోన్ నంబర్, పాత్రతో మనుషులను చేర్చండి.',
    'మూడు చుక్కల మెనూలో టేబుల్ దగ్గర అడిగేవి (నీళ్లు, గ్రేవీ, బిల్), స్వాగతం / ధన్యవాదాల మాటలు, పాత పేజీ ఉన్నాయి.',
  ]),
  '/desk/:id/sales': _H('Sales', 'అమ్మకాలు', [
    'The number on top is the sales of today, this week or this month ("Change period"); below: how it was paid and best sellers.',
    'All numbers come from the bills you made. Cancelled bills are not counted.',
  ], [
    'పైన నంబర్ ఈరోజు / ఈ వారం / ఈ నెల అమ్మకం ("కాలం మార్చు"); కింద ఎలా చెల్లించారు, ఎక్కువ అమ్మినవి.',
    'అన్ని లెక్కలు మీరు చేసిన బిల్లుల నుంచే. రద్దు చేసిన బిల్లులు లెక్కలో లేవు.',
  ]),
  '/desk/:id/qr': _H('Shop / table QR', 'షాప్ / టేబుల్ QR', [
    'The shop QR is on top; tap a table to see its own QR. Print them and stick one on each table and one at the shop door.',
    'The big button sends the order code to your customers on WhatsApp. More tables and Copy are in the menu ⋮.',
  ], [
    'పైన షాప్ QR; టేబుల్ నొక్కితే దాని QR. ప్రింట్ చేసి ప్రతి టేబుల్ మీద, షాప్ గుమ్మం దగ్గర అతికించండి.',
    'పెద్ద బటన్ ఆర్డర్ కోడ్‌ని కస్టమర్లకు WhatsApp లో పంపుతుంది. ఇంకా టేబుల్స్, కాపీ ⋮ మెనూలో.',
  ]),
  '/pos/:id/tables': _H('Tables', 'టేబుల్స్', [
    'The number on top is busy tables. Tap a green (free) table to start an order, an orange one to open its order.',
    'The big button is Takeaway. Add a table and reservations are in the three-dot menu.',
  ], [
    'పైన సంఖ్య నిండిన టేబుల్స్. ఆకుపచ్చ (ఖాళీ) టేబుల్ నొక్కితే ఆర్డర్ మొదలవుతుంది, నారింజ నొక్కితే ఆ ఆర్డర్ తెరుచుకుంటుంది.',
    'పెద్ద బటన్ పార్సెల్. టేబుల్ చేర్చడం, రిజర్వేషన్లు మూడు చుక్కల మెనూలో ఉన్నాయి.',
  ]),
  '/pos/:id/order/:oid': _H('Table order', 'టేబుల్ ఆర్డర్', [
    '3 steps: 1 Add items (search the menu, quantity + note) -> 2 Send to kitchen -> 3 Bill. The big button is always the next step.',
    'Tap an item to take it out; an item already in the kitchen needs a reason (manager).',
    'Move table, Close without a bill and billing only some items (old page) are in ⋮.',
  ], [
    '3 స్టెప్స్: 1 ఐటమ్స్ జోడించు (మెనూలో వెతికి, సంఖ్య + నోట్) -> 2 వంటగదికి పంపు -> 3 బిల్లు. పెద్ద బటన్ ఎప్పుడూ తర్వాతి స్టెప్.',
    'ఐటమ్ నొక్కితే తీసేయొచ్చు; వంటగదికి వెళ్ళినదానికి కారణం కావాలి (మేనేజర్).',
    'టేబుల్ మార్చు, బిల్లు లేకుండా మూసేయి, కొన్ని ఐటమ్స్ మాత్రమే బిల్లు (పాత పేజీ) ⋮ లో.',
  ]),
  '/pos/:id/kitchen': _H('Kitchen (KOT)', 'వంటగది KOT', [
    'The number on top is new tickets. Tap a ticket to see the items, then the big button: Ready, then Served.',
  ], [
    'పైన సంఖ్య కొత్త టికెట్లు. టికెట్ నొక్కి ఐటమ్స్ చూసి, పెద్ద బటన్: రెడీ, తర్వాత వడ్డించాం.',
  ]),
  '/pos/:id/printer': _H('Printer', 'ప్రింటర్', [
    'The top shows the printer in use. The big button does a test print, or finds a printer when you have none.',
    'Finding one: choose how it connects (Bluetooth search, Paired in phone settings, or USB with an OTG cable), then tap your printer in the list.',
    'The menu (three dots) has another printer, the paper size (58 / 80 mm) and the old page.',
  ], [
    'పైన వాడుతున్న ప్రింటర్ కనిపిస్తుంది. పెద్ద బటన్ టెస్ట్ ప్రింట్ చేస్తుంది; ప్రింటర్ లేకపోతే వెతుకుతుంది.',
    'వెతకడం: ఎలా కనెక్ట్ అయిందో ఎంచుకోండి (బ్లూటూత్ వెతుకు, ఫోన్ సెట్టింగ్స్‌లో జత చేసినవి, లేదా OTG కేబుల్‌తో USB), తర్వాత లిస్ట్‌లో మీ ప్రింటర్ నొక్కండి.',
    'మూడు చుక్కల మెనూలో వేరే ప్రింటర్, పేపర్ సైజు (58 / 80 mm), పాత పేజీ ఉన్నాయి.',
  ]),
  '/pos/:id/advance': _H('Shop advance', 'షాప్ అడ్వాన్స్', [
    'Read the terms, tick to accept, set the limit and turn it on.',
    'ASKODOX keeps the record only; the money stays with you.',
  ], [
    'నిబంధనలు చదివి టిక్ చేసి, పరిమితి పెట్టి ఆన్ చేయండి.',
    'ASKODOX రికార్డు మాత్రమే ఉంచుతుంది; డబ్బు మీ దగ్గరే ఉంటుంది.',
  ]),
  '/pos/:id/suppliers': _H('Purchases', 'కొనుగోళ్లు', [
    'The number on top is what you owe suppliers. Tap a supplier for bills and payments.',
    'The big button records a purchase bill. New supplier is in the three-dot menu (old page).',
  ], [
    'పైన సంఖ్య సప్లయర్లకు మీరు ఇవ్వాల్సింది. సప్లయర్ నొక్కితే బిల్లులు, చెల్లింపులు.',
    'పెద్ద బటన్ కొనుగోలు బిల్లు నమోదు చేస్తుంది. కొత్త సప్లయర్ మూడు చుక్కల మెనూలో (పాత పేజీ).',
  ]),
  '/pos/:id/suppliers/:sid': _H('Supplier', 'సప్లయర్', [
    'The number on top is what you owe this supplier, with the month\'s lines. Paid them? Tap "Paid": 1 how much, 2 how paid, 3 done.',
    'Other months and the purchase bills list: ⋮ (old page).',
  ], [
    'పైన నంబర్ ఈ సప్లయర్‌కి ఇవ్వాల్సింది, ఈ నెల వరుసలతో. చెల్లించారా? "చెల్లించాం" నొక్కండి: 1 ఎంత, 2 ఎలా, 3 అయింది.',
    'ఇతర నెలలు, కొనుగోలు బిల్లుల జాబితా: ⋮ (పాత పేజీ).',
  ]),
  '/pos/:id/purchase/new': _H('Record a purchase bill', 'కొనుగోలు బిల్లు నమోదు', [
    '1 Pick the supplier (or photograph the bill — everything fills by itself). 2 The bill number, and the printed total to check.',
    '3 Add each item that came: tap a line for quantity, cost before GST, GST %, pack, batch / expiry or serials. The number on top checks against the printed total.',
  ], [
    '1 సప్లయర్ ఎంచుకోండి (లేదా బిల్లు ఫోటో — అన్నీ దానంతట అదే నిండుతాయి). 2 బిల్లు నంబర్, సరిచూడటానికి బిల్లుపై మొత్తం.',
    '3 వచ్చిన ప్రతి సరుకు చేర్చండి: లైన్ నొక్కి పరిమాణం, GST ముందు ధర, GST %, ప్యాక్, బ్యాచ్ / ఎక్స్‌పైరీ, సీరియల్స్. పైన నంబర్ బిల్లు మొత్తంతో సరిచూస్తుంది.',
  ]),
  '/pos/:id/purchase-orders': _H('Purchase orders', 'కొనుగోలు ఆర్డర్లు', [
    'The number on top is the orders waiting for goods. Tap "New order" to make one; tap an order to send it or receive the goods (in parts if needed).',
  ], [
    'పైన నంబర్ సరుకు రావాల్సిన ఆర్డర్లు. "కొత్త ఆర్డర్" నొక్కి ఆర్డర్ చేయండి; ఆర్డర్ నొక్కి పంపండి లేదా సరుకు తీసుకోండి (కొంచెం కొంచెం అయినా).',
  ]),
  '/pos/:id/stock-report': _H('Expiry & stock value', 'ఎక్స్‌పైరీ & స్టాక్ విలువ', [
    'The number on top is your stock value at cost; below are the batches expiring in 60 days.',
    'The bottom button finds a serial / IMEI.',
  ], [
    'పైన నంబర్ ఖర్చు ధరలో స్టాక్ విలువ; కింద 60 రోజుల్లో ఎక్స్‌పైర్ అయ్యే బ్యాచ్‌లు.',
    'కింద బటన్‌తో సీరియల్ / IMEI వెతకండి.',
  ]),
};

/// The help for a router path pattern ('/pos/:id/items'), or null.
AskodoxScreenHelp? askodoxScreenHelpFor(String pattern) => askodoxScreenHelp[pattern];

/// True when a screen deliberately has no guide button.
bool askodoxScreenHelpIsExempt(String pattern) =>
    askodoxScreenHelpExempt.containsKey(pattern) || pattern.startsWith('/admin');
