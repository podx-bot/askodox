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
  '/profile': _H('Profile', 'ప్రొఫైల్', [
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
  '/radio': _H('Travel Radio', 'ట్రావెల్ రేడియో', [
    'Hear short updates about the places on your route.',
  ], [
    'మీ దారిలోని ప్రదేశాల గురించి చిన్న అప్‌డేట్స్ వినండి.',
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
  '/me/ai-credits': _H('AI Credits', 'AI క్రెడిట్స్', [
    'Your AI Credits balance and what each AI use costs (only when charging is on).',
    'Recharge opens Razorpay; credits are added only after Razorpay confirms the payment.',
    'Credits are only for ASKODOX AI — not cash, not transferable, never used to pay a seller.',
  ], [
    'మీ AI Credits బ్యాలెన్స్, ఒక్కో AI వాడకానికి ఎంత (charging on అయినప్పుడే).',
    'రీఛార్జ్ Razorpay తెరుస్తుంది; Razorpay confirm చేశాకే credits చేరతాయి.',
    'Credits ASKODOX AI కి మాత్రమే — cash కాదు, వేరేవాళ్ళకు పంపలేరు, seller కి కట్టడానికి వాడరు.',
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
  '/pos/:id/payment-alerts': _H('Payment voice alerts', 'పేమెంట్ వాయిస్ అలర్ట్స్', [
    'Turn on alerts for the shop, then "Turn on" notification access and switch ASKODOX on in Android settings.',
    'Press "Speaker test" — connect a Bluetooth speaker first if you want the voice there.',
    'Every payment notification is listed with its time, app, voice status and "unverified" — check big amounts in your bank.',
  ], [
    'షాపుకు అలర్ట్స్ ఆన్ చేసి, నోటిఫికేషన్ యాక్సెస్ "ఆన్ చేయండి" నొక్కి Android సెట్టింగ్స్‌లో ASKODOX ఆన్ చేయండి.',
    '"స్పీకర్ టెస్ట్" నొక్కండి — బ్లూటూత్ స్పీకర్‌లో కావాలంటే ముందు దాన్ని కనెక్ట్ చేయండి.',
    'ప్రతి పేమెంట్ నోటిఫికేషన్ సమయం, యాప్, వాయిస్ స్థితితో "నిర్ధారించలేదు" అని కనిపిస్తుంది — పెద్ద మొత్తాలు బ్యాంకులో చూసుకోండి.',
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
  '/pos/:id/customers/:cid': _H('Customer account', 'కస్టమర్ ఖాతా', [
    'Received money? Tap "Received".',
    'Shop advance: every change waits for the customer\'s approval in their app.',
  ], [
    'డబ్బు వచ్చిందా? "జమ" నొక్కండి.',
    'షాప్ అడ్వాన్స్: ప్రతి మార్పుకీ కస్టమర్ తమ యాప్‌లో ఆమోదించాలి.',
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
    'Count the cash, enter it, and close the day.',
    'Match UPI / card totals with your bank statement.',
  ], [
    'క్యాష్ లెక్కించి నమోదు చేసి రోజు ముగించండి.',
    'UPI / కార్డ్ మొత్తాలను బ్యాంక్ స్టేట్‌మెంట్‌తో పోల్చండి.',
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
