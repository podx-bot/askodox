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
    'Results appear above the chat: tap a card to send a request or open it.',
    'Examples: "Sona masoori rice 25 kg under 1500 near me" · "AC repair at home tomorrow" · "I want to sell my old scooter".',
  ], [
    'మీకు ఏం కావాలో టైప్ చేయండి లేదా మాట్లాడండి (కొనడం, అమ్మడం, సర్వీస్, ఉద్యోగం, రైడ్).',
    'ASKODOX అడిగే ఒక్క ప్రశ్నకు జవాబు ఇవ్వండి, లేదా "చూపించు" అనండి.',
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
  '/me/ideas': _H('Tell us your idea', 'మీ ఐడియా చెప్పండి', [
    'Choose what it is about, then say it with the mic or type it.',
    'Tap Send. Our team reads every idea. Never write phone numbers, OTPs or card numbers.',
  ], [
    'దేని గురించో ఎంచుకోండి, మైక్‌తో చెప్పండి లేదా రాయండి.',
    'పంపు నొక్కండి. మా టీమ్ ప్రతి ఐడియా చదువుతుంది. ఫోన్ నంబర్, OTP, కార్డ్ నంబర్లు రాయకండి.',
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
    'Money in from bills comes by itself, one line a day. Add other money in or out with the two big buttons.',
    'Or say it: "gas cylinder 1100 expense". Remove a wrong line with the bin — Undo brings it back.',
  ], [
    'బిల్లుల డబ్బు రోజుకు ఒక వరుసగా ఆటోగా వస్తుంది. మిగతా ఆదాయం / ఖర్చు రెండు పెద్ద బటన్లతో రాయండి.',
    'లేదా చెప్పండి: "గ్యాస్ సిలిండర్ 1100 ఖర్చు". తప్పు వరుస చెత్తబుట్టతో తీసేయండి — "వెనక్కి" తో మళ్ళీ వస్తుంది.',
  ]),
  '/biz/:id/money/dues': _H('Dues', 'బాకీలు', [
    'Three steps. 1: tap who paid (the total owed is on top; say or type a name). 2: type how much — "all" is ready; cash or online.',
    '3: done — the money goes on their oldest bills first; send the receipt on WhatsApp. Reminders: the button at the bottom.',
  ], [
    'మూడు స్టెప్స్. 1: ఎవరు కట్టారో నొక్కండి (పైన మొత్తం బాకీ; పేరు చెప్పండి / టైప్). 2: ఎంత ఇచ్చారు — "మొత్తం" ముందే ఉంటుంది; క్యాష్ / ఆన్‌లైన్.',
    '3: అయింది — డబ్బు పాత బిల్లులకు ముందు జమ; రసీదు WhatsApp కి. గుర్తులు పంపడం: కింద బటన్.',
  ]),
  '/biz/:id/money/history': _H('Bill history', 'బిల్లుల చరిత్ర', [
    'Search by bill or phone number. Choose the days, then cash / online / baaki / cancelled.',
    'Bills are grouped by day with the day\'s total.',
  ], [
    'బిల్ నంబర్ / ఫోన్ నంబర్‌తో వెతకండి. రోజులు ఎంచుకుని, క్యాష్ / ఆన్‌లైన్ / బాకీ / రద్దు ఎంచుకోండి.',
    'బిల్లులు రోజు వారీగా, ఆ రోజు మొత్తంతో.',
  ]),
  '/biz/:id/reports': _H('Reports', 'రిపోర్ట్స్', [
    'The face shows how the day went. Tap Listen to hear it.',
    'Each problem says why it happened and one thing to do; Go there opens the page to fix it.',
    'Switch to 7 or 30 days for bars of each day, weekdays, busy hours, items, spending and staff.',
  ], [
    'ముఖం చూస్తే రోజు ఎలా ఉందో తెలుస్తుంది. వినండి నొక్కితే చదివి చెబుతుంది.',
    'ప్రతి సమస్యకు కారణం, ఏం చేయాలో ఉంటుంది; అక్కడికి వెళ్ళు నొక్కితే సరిచేసే పేజీ.',
    '7 / 30 రోజులు నొక్కితే రోజూ అమ్మకం, వారం రోజులు, రద్దీ టైం, ఐటమ్స్, ఖర్చులు, సిబ్బంది బార్లలో.',
  ]),
  '/biz/:id/reports/day': _H('Day report', 'రోజు రిపోర్ట్', [
    'The report of the day in the night notification.',
    "Tap Listen to hear it; tap a problem's Go there to fix it.",
  ], [
    'రాత్రి నోటిఫికేషన్‌లో వచ్చిన రోజు రిపోర్ట్.',
    'వినండి నొక్కండి; సమస్య దగ్గర అక్కడికి వెళ్ళు నొక్కి సరిచేయండి.',
  ]),
  '/biz/:id/reports/settings': _H('Night report', 'రాత్రి రిపోర్ట్', [
    'Turn the night report on or off and choose the time.',
    'It goes to you and to the manager / accountant who can see reports.',
  ], [
    'రాత్రి రిపోర్ట్ ఆన్ / ఆఫ్, టైం ఎంచుకోండి.',
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
    'Everyone today: when they came, how (phone lock / photo / owner), and whether they were at the shop.',
    'One tap on P, A, OT or Leave changes today for that person.',
  ], [
    'ఈ రోజు అందరూ: ఎప్పుడు వచ్చారు, ఎలా వేశారు (ఫోన్ లాక్ / ఫోటో / ఓనర్), షాప్ దగ్గర ఉన్నారా.',
    'P, A, OT, సెలవు — ఒక్క నొక్కుతో ఆ వ్యక్తి ఈ రోజు మారుతుంది.',
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
    'The month as rows: one tap on P, A, OT or L changes that day.',
    'Salary is worked out below: days × rate + overtime − advance.',
  ], [
    'నెల వరుసలుగా: P, A, OT, సె ఒక్క నొక్కుతో ఆ రోజు మారుతుంది.',
    'కింద జీతం లెక్క: రోజులు × రేటు + OT − అడ్వాన్స్.',
  ]),
  '/biz/:id/staff/salary': _H('Salary', 'జీతాలు', [
    "Everyone's salary this month, worked out from attendance.",
    '"Mark given" writes it into the cashbook as salary.',
  ], [
    'హాజరు నుంచి ఈ నెల అందరి జీతం లెక్క.',
    '"ఇచ్చేశాను" నొక్కితే క్యాష్‌బుక్‌లో జీతంగా పడుతుంది.',
  ]),
  '/biz/:id/staff/tasks': _H('Tasks', 'పనులు', [
    'Give a task to a person — their phone rings. They tick it when done.',
    'Late tasks show in red and in the night report.',
  ], [
    'ఒకరికి పని ఇవ్వండి — వారి ఫోన్ మోగుతుంది. అయ్యాక వారు ✓ పెడతారు.',
    'ఆలస్యమైన పనులు ఎరుపులో, రాత్రి రిపోర్ట్‌లో కనిపిస్తాయి.',
  ]),
  '/biz/:id/staff/setup': _H('Attendance setup', 'హాజరు సెటప్', [
    "Choose: each person's own phone, the shop phone, or both.",
    'Set the start and end time, the minutes of lateness allowed and how near the shop counts.',
  ], [
    'ఎంచుకోండి: ప్రతి ఒక్కరి ఫోన్, షాప్ ఫోన్, లేదా రెండూ.',
    'మొదలు / ముగింపు సమయం, ఎన్ని నిమిషాల ఆలస్యం ఓకే, షాప్‌కి ఎంత దగ్గర — పెట్టండి.',
  ]),
  '/biz/:id/menu': _H('Menu & items', 'మెనూ & ఐటమ్స్', [
    'Add an item, read a menu photo, sort with AI, or switch off what ran out today.',
    'Search finds an item by name or number in every section. Tap a section to see its items.',
  ], [
    'ఐటమ్ చేర్చండి, మెనూ ఫోటో చదివించండి, AI తో సర్దండి, లేదా అయిపోయినవి ఆఫ్ చేయండి.',
    'వెతుకుడు అన్ని విభాగాల్లో పేరు / నంబర్‌తో వెతుకుతుంది. విభాగం నొక్కితే దాని ఐటమ్స్.',
  ]),
  '/biz/:id/menu/sort': _H('Sort with AI', 'AI తో సర్దు', [
    'AI reads the item names in parts at the same time — it can take a minute or two.',
    'Open a section to move an item. Nothing changes until you tap Save.',
  ], [
    'AI ఐటమ్ పేర్లను భాగాలుగా ఒకేసారి చదువుతుంది — 1–2 నిమిషాలు పట్టవచ్చు.',
    'విభాగం తెరిచి ఐటమ్ మార్చవచ్చు. సేవ్ నొక్కే వరకు ఏదీ మారదు.',
  ]),
  '/biz/:id/menu/section/:name': _H('One section', 'ఒక విభాగం', [
    'Each item: photo, price, how many sold today, and the switch for today.',
    'Use the chips to see only veg, non-veg, what is off, or the most sold.',
  ], [
    'ప్రతి ఐటమ్: ఫోటో, ధర, ఈ రోజు ఎన్ని అమ్మాం, ఈ రోజు స్విచ్.',
    'చిప్స్‌తో వెజ్, నాన్-వెజ్, లేనివి, ఎక్కువ అమ్మినవి మాత్రమే చూడండి.',
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
    'Every page is an icon with its name. Press and hold to arrange: drop on another = a folder, beside it = move, to the edge = the next screen.',
    '"−" hides a page (never deleted); "Hidden" brings it back; "Reset" puts the screen back as it came. Payment voice: tap a line to switch what the phone says, ▶ to hear it.',
  ], [
    'కొను వైపు = మీ సొంత డబ్బు (ఈ నెల వచ్చింది / పోయింది); అమ్ము వైపు = షాప్ డబ్బు (ఈ రోజు, బాకీ, కొత్త ఆర్డర్లు). రెండూ కలవవు.',
    'ప్రతి పేజీ ఒక ఐకాన్, కింద పేరు. పట్టుకుని లాగండి: వేరే దాని మీద వదిలితే ఫోల్డర్, పక్కన వదిలితే అక్కడికి, అంచుకి లాగితే తర్వాతి స్క్రీన్.',
    '"−" పేజీని దాచుతుంది (తొలగించదు); "దాచినవి" లో తిరిగి పెట్టండి; "మొదటిలా" మొదట ఉన్నట్టు పెడుతుంది. పేమెంట్ వాయిస్: వరుస నొక్కి ఆన్ / ఆఫ్, ▶ తో వినండి.',
  ]),
  '/payment-voice': _H('Payment voice', 'పేమెంట్ వాయిస్', [
    'Tap a line to switch what the phone says out loud: money received, sent, bill / EMI paid, refund, cashback, pending, failed, bill due, autopay, money asked.',
    '▶ plays the exact words. The "looks fake" warning is always on — a fake message is never counted as money.',
  ], [
    'ఫోన్ ఏం చెప్పాలో వరుస నొక్కి ఆన్ / ఆఫ్ చేయండి: డబ్బు వచ్చింది, పంపారు, బిల్లు / EMI కట్టారు, రీఫండ్, క్యాష్‌బ్యాక్, పెండింగ్, ఫెయిల్, బిల్లు కట్టాలి, ఆటోపే, డబ్బు అడిగారు.',
    '▶ నొక్కితే అవే మాటలు వినిపిస్తాయి. "ఫేక్‌లా ఉంది" హెచ్చరిక ఎప్పుడూ ఆన్ — ఫేక్ మెసేజ్ డబ్బుగా లెక్కలోకి రాదు.',
  ]),
  '/me/dues': _H('Coming up', 'కట్టాల్సినవి', [
    'Add EMI, current bill, rent, recharge with the date; the phone says them 2 days before and on the day.',
    'Bills that came by SMS are offered here — tap one to add it; a bill already paid is not offered.',
  ], [
    'EMI, కరెంట్ బిల్, అద్దె, రీఛార్జ్ తేదీతో జోడించండి; గడువుకు 2 రోజుల ముందు, ఆ రోజు ఫోన్ చెప్తుంది.',
    'SMS లో వచ్చిన బిల్లులు ఇక్కడ సూచనగా వస్తాయి — నొక్కితే జోడిస్తుంది; కట్టేసినవి రావు.',
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
    'Bills that shops sent to your number show here.',
    'Pay by UPI opens your UPI app with the amount filled in; the money goes straight to the shop.',
    'After paying, tap "I have paid" so the shop checks and closes the bill.',
  ], [
    'షాపులు మీ నంబర్‌కి పంపిన బిల్లులు ఇక్కడ కనిపిస్తాయి.',
    '"UPI లో కట్టు" నొక్కితే మొత్తం నిండిన UPI యాప్ తెరుచుకుంటుంది; డబ్బు నేరుగా షాప్‌కి వెళ్తుంది.',
    'కట్టాక "కట్టేశాను" నొక్కితే షాప్ చూసి బిల్లు ముగిస్తుంది.',
  ]),
  '/bills/:id': _H('Bill history', 'బిల్లుల హిస్టరీ', [
    'Every bill with how it was paid: cash, PhonePe, Google Pay, Paytm, other UPI or card.',
    'Pending only shows bills with money still to come; Paid closes one when the money arrives.',
    'Remind / send puts the bill in the customer\'s ASKODOX app, or opens WhatsApp on their number.',
  ], [
    'ప్రతి బిల్లు ఎలా కట్టారో కనిపిస్తుంది: క్యాష్, PhonePe, Google Pay, Paytm, ఇతర UPI, కార్డ్.',
    '"బాకీ మాత్రమే" లో డబ్బు రావాల్సిన బిల్లులు ఉంటాయి; డబ్బు వచ్చాక "కట్టారు" నొక్కండి.',
    '"గుర్తు చేయి / పంపు" బిల్లును కస్టమర్ ASKODOX యాప్‌లోకి, లేదా వాళ్ళ నంబర్ WhatsApp కి పంపుతుంది.',
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
    'Add your UPI QR from ANY app or bank — pick its photo or photograph it — or type the UPI ID.',
    'Buyers see these only after you accept their request; they pay you directly.',
    'Bank account numbers are stored encrypted. Make one method the default.',
  ], [
    'ఏ యాప్ / బ్యాంక్ UPI QR అయినా జోడించండి — ఫోటో ఎంచుకోండి లేదా తీయండి — లేదా UPI ID టైప్ చేయండి.',
    'మీరు అభ్యర్థనను అంగీకరించాకే కొనేవారికి ఇవి కనిపిస్తాయి; వాళ్ళు నేరుగా మీకే కడతారు.',
    'బ్యాంక్ ఖాతా నంబర్లు ఎన్‌క్రిప్ట్ చేసి దాస్తాం. ఒకదాన్ని డిఫాల్ట్ చేయండి.',
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
  '/pos/:id/payment-alerts': _H('Payment voice alerts', 'పేమెంట్ వాయిస్ అలర్ట్స్', [
    'Turn on alerts for the shop, then "Turn on" notification access and switch ASKODOX on in Android settings.',
    'Press "Speaker test" — connect a Bluetooth speaker first if you want the voice there.',
    'Every payment notification is listed with its time, app, voice status and "received" — check big amounts in your bank app.',
  ], [
    'షాపుకు అలర్ట్స్ ఆన్ చేసి, నోటిఫికేషన్ యాక్సెస్ "ఆన్ చేయండి" నొక్కి Android సెట్టింగ్స్‌లో ASKODOX ఆన్ చేయండి.',
    '"స్పీకర్ టెస్ట్" నొక్కండి — బ్లూటూత్ స్పీకర్‌లో కావాలంటే ముందు దాన్ని కనెక్ట్ చేయండి.',
    'ప్రతి పేమెంట్ నోటిఫికేషన్ సమయం, యాప్, వాయిస్ స్థితితో "అందింది" అని కనిపిస్తుంది — పెద్ద మొత్తాలు బ్యాంక్ యాప్‌లో చూసుకోండి.',
  ]),
  '/pos/:id/selfshop': _H('Self-shopping', 'సెల్ఫ్ షాపింగ్', [
    'Turn it on to let customers scan items with their own phone.',
    "Show today's code / QR at the entrance — it changes every day.",
    'At the exit, type the 4-digit exit code from the customer\'s phone to open their list.',
  ], [
    'కస్టమర్లు తమ ఫోన్‌తో సరుకులు స్కాన్ చేయడానికి ఇది ఆన్ చేయండి.',
    'ఈ రోజు కోడ్ / QR ద్వారం దగ్గర చూపించండి — అది రోజూ మారుతుంది.',
    'బయటకు వెళ్లేటప్పుడు కస్టమర్ ఫోన్‌లోని 4 అంకెల ఎగ్జిట్ కోడ్ రాసి వారి లిస్ట్ తెరవండి.',
  ]),
  '/pos/:id/selfshop/:sid': _H('Exit check', 'ఎగ్జిట్ చెక్', [
    'Ask the customer to lay all items with barcodes facing up.',
    'Take ONE photo: every barcode is read and compared with the list.',
    'Check "not seen" items and quantities above one by hand, then bill and take payment.',
  ], [
    'కస్టమర్‌ని అన్ని సరుకులు బార్‌కోడ్‌లు పైకి కనిపించేలా పెట్టమనండి.',
    'ఒకే ఫోటో తీయండి: ప్రతి బార్‌కోడ్ చదివి లిస్ట్‌తో పోలుస్తుంది.',
    '"కనబడలేదు" అన్నవి, ఒకటి కంటే ఎక్కువ ఉన్నవి చేతితో చూసి, బిల్లు చేసి డబ్బు తీసుకోండి.',
  ]),
  '/shop-scan': _H('Scan & shop', 'స్కాన్ చేసి కొనండి', [
    'Photograph the QR at the shop entrance or type its 6-digit code.',
    'Pick an item and photograph its barcode — it joins your list with the shop\'s price.',
    'Tap Checkout, show the exit code at the counter, and pay there.',
  ], [
    'షాప్ ద్వారం దగ్గర QR ఫోటో తీయండి లేదా 6 అంకెల కోడ్ రాయండి.',
    'సరుకు తీసుకుని దాని బార్‌కోడ్ ఫోటో తీయండి — షాప్ ధరతో మీ లిస్ట్‌లో చేరుతుంది.',
    '"చెకౌట్" నొక్కి, కౌంటర్‌లో ఎగ్జిట్ కోడ్ చూపించి, అక్కడ డబ్బు ఇవ్వండి.',
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
    'Open your shop, or create one (name, GST type, State).',
  ], [
    'మీ షాప్ తెరవండి, లేదా కొత్తది తయారు చేయండి (పేరు, GST రకం, రాష్ట్రం).',
  ]),
  '/pos/:id': _H('Shop dashboard', 'షాప్ డ్యాష్‌బోర్డ్', [
    'New bill to sell; Items & stock to add what you sell.',
    'Customers & credit for dues; Day close at night.',
  ], [
    'అమ్మడానికి "కొత్త బిల్లు"; అమ్మేవి చేర్చడానికి "సరుకులు & స్టాక్".',
    'బాకీలకు "కస్టమర్లు & ఖాతా"; రాత్రి "రోజు ముగింపు".',
  ]),
  '/pos/:id/sale': _H('New bill', 'కొత్త బిల్లు', [
    'Tap items (or scan a barcode photo) to add them.',
    'Tap Pay, add how the customer paid, then Issue.',
  ], [
    'సరుకులు నొక్కి చేర్చండి (లేదా బార్‌కోడ్ ఫోటో స్కాన్ చేయండి).',
    '"పే" నొక్కి కస్టమర్ ఎలా కట్టారో చేర్చి "ఇష్యూ" నొక్కండి.',
  ]),
  '/pos/:id/items': _H('Items & stock', 'సరుకులు & స్టాక్', [
    'Add an item with its price and GST; set where you sell it (POS / Online / Both).',
    'Tap an item for box / piece units; use the box icon to add stock.',
  ], [
    'ధర, GST తో సరుకు చేర్చండి; ఎక్కడ అమ్మాలో ఎంచుకోండి (POS / ఆన్‌లైన్ / రెండూ).',
    'బాక్స్ / పీస్ యూనిట్లకు సరుకు నొక్కండి; స్టాక్ చేర్చడానికి బాక్స్ ఐకాన్.',
  ]),
  '/pos/:id/catalogue': _H('Ready list', 'రెడీ లిస్ట్', [
    'Choose your kind of business at the top.',
    'Tick the items you sell, pick the size and type YOUR price (and GST % if registered).',
    'Tap "Add" — items already in your shop are skipped.',
  ], [
    'పైన మీ వ్యాపార రకం ఎంచుకోండి.',
    'మీరు అమ్మే సరుకులను టిక్ చేసి, సైజు ఎంచుకుని, మీ ధర రాయండి (GST ఉంటే GST % కూడా).',
    '"చేర్చు" నొక్కండి — మీ షాప్‌లో ఇప్పటికే ఉన్నవి వదిలేస్తాం.',
  ]),
  '/pos/:id/item/:pid': _H('Item details', 'సరుకు వివరాలు', [
    'Fill the details customers look for (size, colour, brand …). Ones marked "Needed" are required.',
    'Tap ? next to any field to see what to write, with an example.',
    'Set an online price if it differs from the shop price, then Save.',
  ], [
    'కస్టమర్లు చూసే వివరాలు నింపండి (సైజు, రంగు, బ్రాండ్ …). "కావాలి" అని ఉన్నవి తప్పనిసరి.',
    'ఏ ఫీల్డ్ పక్కనైనా ? నొక్కితే ఏం రాయాలో ఉదాహరణతో చెబుతుంది.',
    'ఆన్‌లైన్ ధర వేరుగా కావాలంటే పెట్టి, సేవ్ నొక్కండి.',
  ]),
  '/pos/:id/customers': _H('Customers & credit', 'కస్టమర్లు & ఖాతా', [
    'Add customers; tap one to see dues, statement and shop advance.',
  ], [
    'కస్టమర్లను చేర్చండి; ఒకరిని నొక్కితే బాకీ, స్టేట్‌మెంట్, షాప్ అడ్వాన్స్ కనిపిస్తాయి.',
  ]),
  '/pos/:id/dues': _H('Baaki reminders', 'బాకీ గుర్తులు', [
    'From 3 days before each pay date up to the date: tap WhatsApp next to a name -- the message and pay link are ready.',
    'A date passed? Tap a new date. Customers on ASKODOX are reminded in the app by themselves.',
  ], [
    'కట్టాల్సిన తేదీకి 3 రోజుల ముందు నుంచి ఆ రోజు వరకు: పేరు పక్కన WhatsApp నొక్కండి — మెసేజ్, పే లింక్ రెడీగా ఉంటాయి.',
    'తేదీ దాటిందా? కొత్త తేదీ నొక్కండి. ASKODOX ఉన్న కస్టమర్లకు యాప్‌లో తానే గుర్తు చేస్తాం.',
  ]),
  '/pos/:id/customers/:cid': _H('Customer account', 'కస్టమర్ ఖాతా', [
    'Received money? Tap "Received".',
    'Shop advance: every change waits for the customer\'s approval in their app.',
  ], [
    'డబ్బు వచ్చిందా? "జమ" నొక్కండి.',
    'షాప్ అడ్వాన్స్: ప్రతి మార్పుకీ కస్టమర్ తమ యాప్‌లో ఆమోదించాలి.',
  ]),
  '/crm': _H('Business CRM', 'Business CRM', [
    'Opens the CRM of your shop (pick the shop if you have more than one).',
    'No shop yet? Add it in Shop billing first: the CRM works on your shop customers, bills and staff.',
  ], [
    'మీ shop CRM తెరుస్తుంది (ఒకటి కంటే ఎక్కువ shops ఉంటే shop ఎంచుకోండి).',
    'Shop ఇంకా లేదా? ముందు Shop billing లో చేర్చండి: CRM మీ shop customers, bills, staff మీదే పని చేస్తుంది.',
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
  '/me/agent': _H('Buyer agent', 'Buyer agent', [
    'Your own records only: shop advances waiting for you and your saved ways to be paid. It never pays or approves for you.',
  ], [
    'మీ records మాత్రమే: మీ కోసం ఆగిన shop advances, మీ payment methods. మీ తరఫున pay / approve చేయదు.',
  ]),
  '/pos/:id/crm': _H('Business CRM', 'Business CRM', [
    'Today: follow-ups due, pipeline by stage, and ASKODOX requests you can save as enquiries.',
    'Tap + Add lead for a new lead or enquiry; set a follow-up and you get a reminder.',
    'Quotations are made on the bill screen ("Quotation"); here you mark them sent / accepted / rejected.',
    'Complaints: write the problem, then solve it with a note. Reports show conversion, sources and dues.',
  ], [
    'ఈరోజు: చేయాల్సిన follow-ups, stage వారీగా pipeline, ASKODOX requests ని enquiry గా save చేయవచ్చు.',
    '+ Lead చేర్చండి నొక్కి కొత్త lead / enquiry చేర్చండి; follow-up పెడితే reminder వస్తుంది.',
    'Quotation bill screen లో ("Quotation") తయారవుతుంది; ఇక్కడ పంపాం / ఒప్పుకున్నారు / వద్దన్నారు అని పెట్టండి.',
    'Complaints: సమస్య రాసి, పరిష్కారం note తో close చేయండి. Reports లో conversion, sources, బాకీలు కనిపిస్తాయి.',
  ]),
  '/pos/:id/crm/leads': _H('Leads & enquiries', 'Leads & Enquiries', [
    'Filter by stage or "Mine"; tap a lead to work on it.',
  ], [
    'Stage లేదా "నావి" తో filter చేయండి; lead నొక్కి పని చేయండి.',
  ]),
  '/pos/:id/crm/lead/:lid': _H('Lead', 'Lead వివరాలు', [
    'Move the stage as the talk goes on; Lost needs a reason, Won can point to the real bill.',
    'Call note / Note keep the history; Follow-up sets a reminder; Make quotation opens the bill screen for this lead.',
    'Save as customer adds the person to your shop customers (one customer list).',
  ], [
    'మాట్లాడినట్టు stage మార్చండి; Lost కి కారణం కావాలి, Won కి అసలు bill ఎంచుకోవచ్చు.',
    'Call note / Note history లో ఉంటాయి; Follow-up reminder పెడుతుంది; Quotation తయారు చేయండి ఈ lead కోసం bill screen తెరుస్తుంది.',
    'Customer గా save చేస్తే మీ shop customers list లో చేరతారు (ఒకే customer list).',
  ]),
  '/pos/:id/crm/complaint/:cid': _H('Complaint', 'Complaint', [
    'Change the status as you work on it; Resolved / Closed need how it was solved.',
    'Reminder sets a follow-up; the bill and the customer history open from here.',
  ], [
    'పని జరుగుతున్నట్టు status మార్చండి; Resolved / Closed కి ఎలా పరిష్కరించారో రాయాలి.',
    'Reminder follow-up పెడుతుంది; bill, customer history ఇక్కడి నుండే తెరవచ్చు.',
  ]),
  '/pos/:id/crm/customer/:cid': _H('Customer history', 'Customer history', [
    'Everything about this customer: bills, dues, leads, quotations, complaints and notes.',
    'Add a new lead or complaint for them, or open their account to record money received.',
  ], [
    'ఈ customer గురించి అన్నీ: bills, బాకీ, leads, quotations, complaints, notes.',
    'వారి కోసం కొత్త lead / complaint చేర్చండి, లేదా డబ్బు జమ కోసం account తెరవండి.',
  ]),
  '/pos/:id/invoices': _H('Bills', 'బిల్లులు', [
    'All issued bills; tap one to print, share, or make a credit note.',
  ], [
    'ఇష్యూ చేసిన బిల్లులన్నీ; ఒకటి నొక్కి ప్రింట్, షేర్ లేదా క్రెడిట్ నోట్.',
  ]),
  '/pos/:id/invoice/:iid': _H('Bill', 'బిల్లు', [
    'Print, share the PDF, return items (credit note) or cancel today\'s bill.',
    'Issued bills are never edited.',
  ], [
    'ప్రింట్, PDF షేర్, సరుకు వాపసు (క్రెడిట్ నోట్) లేదా ఈ రోజు బిల్లు రద్దు.',
    'ఇష్యూ చేసిన బిల్లు ఎప్పుడూ మార్చబడదు.',
  ]),
  '/pos/:id/day': _H('Day close', 'రోజు ముగింపు', [
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
  '/pos/:id/gst': _H('GST summary', 'GST సారాంశం', [
    'Pick the dates; share the summary or CSV with your accountant.',
    'It is not a filed return.',
  ], [
    'తేదీలు ఎంచుకోండి; సారాంశం / CSV మీ అకౌంటెంట్‌కి షేర్ చేయండి.',
    'ఇది ఫైల్ చేసిన రిటర్న్ కాదు.',
  ]),
  '/pos/:id/staff': _H('Staff & roles', 'సిబ్బంది & పాత్రలు', [
    'Add staff by phone number and choose their role.',
  ], [
    'ఫోన్ నంబర్‌తో సిబ్బందిని చేర్చి వారి పాత్ర ఎంచుకోండి.',
  ]),
  '/order-desk/enter': _H('Order at a shop / table', 'షాప్ / టేబుల్ ఆర్డర్', [
    'Photograph the QR on the shop or table, or search the shop by its name; the menu opens.',
    'The code printed under the QR can still be typed.',
    'Your earlier orders are listed here: tap one to follow it, or "Again" to order the same.',
  ], [
    'షాప్ లేదా టేబుల్ మీది QR ఫోటో తీయండి, లేదా షాప్ పేరు వెతకండి; మెనూ తెరుచుకుంటుంది.',
    'QR కింద ఉన్న కోడ్ కూడా రాయవచ్చు.',
    'మీ పాత ఆర్డర్లు ఇక్కడ కనిపిస్తాయి: నొక్కి ఫాలో చేయండి, లేదా "మళ్ళీ" నొక్కి అదే ఆర్డర్ చేయండి.',
  ]),
  '/order-desk': _H('Menu & order', 'మెనూ & ఆర్డర్', [
    'Choose dine in, takeaway or delivery. Add items with + or just say it (2 chicken biryani).',
    'Say "same as last time" to repeat your last order; say "that\'s all" to send it.',
    'Delivery needs an address or a map pin. You pay the shop directly; ASKODOX never holds the money.',
  ], [
    'ఇక్కడే తింటారా, పార్సిల్ లేదా డెలివరీనా ఎంచుకోండి. + నొక్కండి లేదా చెప్పండి (2 చికెన్ బిర్యానీ).',
    '"మునుపటిలాగే" అంటే గత ఆర్డర్ మళ్ళీ; "అంతే" అంటే ఆర్డర్ వెళ్తుంది.',
    'డెలివరీకి అడ్రస్ లేదా మ్యాప్ పిన్ కావాలి. డబ్బు నేరుగా షాప్‌కే; ASKODOX డబ్బు పట్టుకోదు.',
  ]),
  '/order-desk/track/:oid': _H('My order', 'నా ఆర్డర్', [
    'See each step live: accepted, preparing, ready, on the way.',
    'You can cancel only before the shop accepts. Pay the shop\'s UPI from the bill below.',
    'Eating here? After the shop accepts, tap "Need something?" for water, extra gravy, onions, the bill, or say it in words.',
  ], [
    'ప్రతి దశ లైవ్‌గా కనిపిస్తుంది: అంగీకరించారు, తయారవుతోంది, సిద్ధం, దారిలో.',
    'షాప్ అంగీకరించకముందే రద్దు చేయవచ్చు. కింద బిల్లు నుంచి షాప్ UPI కి కట్టండి.',
    'ఇక్కడ తింటుంటే, షాప్ అంగీకరించాక "ఏమైనా కావాలా?" లో నీళ్లు, ఎక్స్‌ట్రా గ్రేవీ, ఆనియన్స్, బిల్ నొక్కండి లేదా మాటతో చెప్పండి.',
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
  '/desk/:id': _H('Orders desk', 'ఆర్డర్స్ డెస్క్', [
    'All table, shop-QR, counter and reception orders in one place: New, Kitchen, Ready, Delivery, Done.',
    'Accept an order and switch OFF what is finished; the customer is told. Then move it step by step.',
    'Bill when it is ready (GST only if your shop has GST). Delivery orders open the map pin.',
    'An order not accepted in a minute alerts the owner.',
    'Table requests (water, extra gravy, onions, bill) show in a banner on top; tap Done when served.',
  ], [
    'టేబుల్, షాప్ QR, కౌంటర్, రిసెప్షన్ ఆర్డర్లన్నీ ఒకే చోట: కొత్త, వంటగది, సిద్ధం, డెలివరీ, పూర్తి.',
    'ఆర్డర్ అంగీకరించి అయిపోయినవాటిని OFF చేయండి; కస్టమర్‌కి తెలుస్తుంది. తర్వాత ఒక్కో దశ ముందుకు.',
    'సిద్ధమయ్యాక బిల్లు చేయండి (మీ షాప్‌కి GST ఉంటేనే GST). డెలివరీ ఆర్డర్లకు మ్యాప్ పిన్ తెరుచుకుంటుంది.',
    'నిమిషంలో అంగీకరించని ఆర్డర్ గురించి ఓనర్‌కి అలర్ట్ వెళ్తుంది.',
    'టేబుల్ అభ్యర్థనలు (నీళ్లు, గ్రేవీ, ఆనియన్స్, బిల్) పైన బ్యానర్‌లో కనిపిస్తాయి; ఇచ్చాక "అయింది" నొక్కండి.',
  ]),
  '/desk/:id/menu': _H('Menu', 'మెనూ', [
    'Say or type items with prices, tap Preview, check, then Save. Nothing is saved before you confirm.',
    'Say "today only" for a special; switch an item OFF when it is finished for today (back tomorrow).',
    'Or photograph the menu: every item and its printed price is read; fix any line, then Save.',
  ], [
    'ఐటమ్స్ ధరలతో చెప్పండి లేదా రాయండి, Preview నొక్కి చూసి, తర్వాత Save. నిర్ధారించే వరకు ఏదీ సేవ్ కాదు.',
    'స్పెషల్‌కి "ఈ రోజు మాత్రమే" అనండి; అయిపోతే ఆ ఐటమ్ OFF చేయండి (రేపు మళ్ళీ వస్తుంది).',
    'లేదా మెనూ ఫోటో తీయండి: ప్రతి ఐటమ్, అందులో ముద్రించిన రేటు చదువుతుంది; ఏదైనా సరిచేసి Save.',
  ]),
  '/desk/:id/settings': _H('Order alerts & staff', 'ఆర్డర్ అలర్ట్స్ & సిబ్బంది', [
    'Choose who is told at each step: new order, kitchen, ready, delivery. Nobody chosen = the people of that role.',
    'Add staff with their phone number and a role (cashier, kitchen, waiter, delivery). Delete anyone with the bin.',
    'Auto-confirm accepts an order at once while the shop is open, for items on today\'s menu.',
  ], [
    'ప్రతి స్టెప్ లో ఎవరికి చెప్పాలో ఎంచుకోండి: కొత్త ఆర్డర్, వంటగది, సిద్ధం, డెలివరీ. ఎవరినీ ఎంచుకోకపోతే ఆ పాత్ర ఉన్నవాళ్ళకి.',
    'సిబ్బందిని ఫోన్ నంబర్, పాత్రతో చేర్చండి (క్యాషియర్, వంటగది, వెయిటర్, డెలివరీ). చెత్తబుట్టతో తీసేయండి.',
    'ఆటో-కన్ఫర్మ్: షాప్ తెరిచి ఉంటే, ఈరోజు మెనూలోని ఐటెమ్‌ల ఆర్డర్ వెంటనే అంగీకరిస్తుంది.',
  ]),
  '/desk/:id/sales': _H('Sales', 'అమ్మకాలు', [
    'Today, this week or this month: total sales, bills, how it was paid, dues and best sellers.',
    'All numbers come from the bills you made. Cancelled bills are not counted.',
  ], [
    'ఈరోజు, ఈ వారం, ఈ నెల: మొత్తం అమ్మకం, బిల్లులు, ఎలా చెల్లించారు, బాకీ, ఎక్కువ అమ్మినవి.',
    'అన్ని లెక్కలు మీరు చేసిన బిల్లుల నుంచే. రద్దు చేసిన బిల్లులు లెక్కలో లేవు.',
  ]),
  '/desk/:id/qr': _H('Shop / table QR', 'షాప్ / టేబుల్ QR', [
    'Print these and stick one on each table and one at the shop door.',
    'A customer types the code under the QR in "Order code" and the menu opens.',
  ], [
    'వీటిని ప్రింట్ చేసి ప్రతి టేబుల్ మీద, షాప్ గుమ్మం దగ్గర అతికించండి.',
    'కస్టమర్ QR కింద కోడ్‌ని "ఆర్డర్ కోడ్" లో రాస్తే మెనూ తెరుచుకుంటుంది.',
  ]),
  '/pos/:id/tables': _H('Tables & KOT', 'టేబుల్స్ & KOT', [
    'Tap a table to open an order, add items, send the KOT, then bill.',
  ], [
    'టేబుల్ నొక్కి ఆర్డర్ తెరవండి, సరుకులు చేర్చండి, KOT పంపండి, తర్వాత బిల్లు.',
  ]),
  '/pos/:id/order/:oid': _H('Table order', 'టేబుల్ ఆర్డర్', [
    'Add items with notes, send the KOT to the kitchen, then bill the table.',
  ], [
    'నోట్స్‌తో సరుకులు చేర్చండి, KOT వంటగదికి పంపండి, తర్వాత టేబుల్ బిల్లు.',
  ]),
  '/pos/:id/kitchen': _H('Kitchen screen', 'వంటగది స్క్రీన్', [
    'New orders appear here; move each to Preparing, Ready and Served.',
  ], [
    'కొత్త ఆర్డర్లు ఇక్కడ వస్తాయి; ఒక్కోదాన్ని తయారవుతోంది, సిద్ధం, అందించాం అని మార్చండి.',
  ]),
  '/pos/:id/printer': _H('Receipt printer', 'రసీదు ప్రింటర్', [
    'Bluetooth LE: Find printer. Classic Bluetooth: pair in phone settings, then Paired. USB: connect with OTG.',
    'Pick the printer and do a test print.',
  ], [
    'బ్లూటూత్ LE: "ప్రింటర్ వెతుకు". క్లాసిక్: ఫోన్ సెట్టింగ్స్‌లో జత చేసి "జత చేసినవి". USB: OTG తో కనెక్ట్.',
    'ప్రింటర్ ఎంచుకుని టెస్ట్ ప్రింట్ చేయండి.',
  ]),
  '/pos/:id/advance': _H('Shop advance', 'షాప్ అడ్వాన్స్', [
    'Read the terms, tick to accept, set the limit and turn it on.',
    'ASKODOX keeps the record only; the money stays with you.',
  ], [
    'నిబంధనలు చదివి టిక్ చేసి, పరిమితి పెట్టి ఆన్ చేయండి.',
    'ASKODOX రికార్డు మాత్రమే ఉంచుతుంది; డబ్బు మీ దగ్గరే ఉంటుంది.',
  ]),
  '/pos/:id/suppliers': _H('Suppliers & purchases', 'సప్లయర్లు & కొనుగోళ్లు', [
    'Add suppliers; record their bills; pay them; see what you owe.',
  ], [
    'సప్లయర్లను చేర్చండి; వారి బిల్లులు నమోదు చేయండి; చెల్లించండి; బాకీ చూడండి.',
  ]),
  '/pos/:id/suppliers/:sid': _H('Supplier', 'సప్లయర్', [
    'Bills, payments and the monthly statement of this supplier.',
  ], [
    'ఈ సప్లయర్ బిల్లులు, చెల్లింపులు, నెలవారీ స్టేట్‌మెంట్.',
  ]),
  '/pos/:id/purchase/new': _H('Record a purchase bill', 'కొనుగోలు బిల్లు నమోదు', [
    'Enter the supplier\'s bill number, date and each line as printed.',
    'The total must match the printed total.',
  ], [
    'సప్లయర్ బిల్లు నంబర్, తేదీ, ప్రతి లైన్ ముద్రించినట్టే నమోదు చేయండి.',
    'మొత్తం ముద్రించిన మొత్తంతో సరిపోవాలి.',
  ]),
  '/pos/:id/purchase-orders': _H('Purchase orders', 'కొనుగోలు ఆర్డర్లు', [
    'Make an order for a supplier, send it, and receive the goods (in parts if needed).',
  ], [
    'సప్లయర్‌కి ఆర్డర్ తయారు చేసి పంపండి, సరుకు వచ్చినప్పుడు (కొంచెం కొంచెం అయినా) తీసుకోండి.',
  ]),
  '/pos/:id/stock-report': _H('Expiry & stock value', 'ఎక్స్‌పైరీ & స్టాక్ విలువ', [
    'See what expires soon and what your stock is worth at cost.',
    'Look up a serial / IMEI from the top bar.',
  ], [
    'త్వరలో ఎక్స్‌పైర్ అయ్యేవి, ఖర్చు ధరలో స్టాక్ విలువ చూడండి.',
    'పై బార్‌లో సీరియల్ / IMEI వెతకండి.',
  ]),
};

/// The help for a router path pattern ('/pos/:id/items'), or null.
AskodoxScreenHelp? askodoxScreenHelpFor(String pattern) => askodoxScreenHelp[pattern];

/// True when a screen deliberately has no guide button.
bool askodoxScreenHelpIsExempt(String pattern) =>
    askodoxScreenHelpExempt.containsKey(pattern) || pattern.startsWith('/admin');
