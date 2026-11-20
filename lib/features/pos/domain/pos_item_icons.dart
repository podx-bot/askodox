/// Owner 2026-11-20: an item without its own photo shows a picture that fits its NAME instead of a bare letter.
/// Free (emoji drawn by the phone itself, no AI picture cost), any shop type, English / Telugu / Hindi words.
/// First match wins, so a dish ("chicken biryani") is checked before its main ingredient ("chicken").
library;

const List<(List<String>, String)> _askodoxItemIconRules = [
  // dishes / ready food
  (['biryani', 'బిర్యానీ', 'బిరియాని', 'बिरयानी', 'pulao', 'పులావ్', 'fried rice', 'ఫ్రైడ్ రైస్', 'meals', 'భోజనం', 'thali'], '🍛'),
  (['pizza', 'పిజ్జా'], '🍕'),
  (['burger', 'బర్గర్'], '🍔'),
  (['sandwich', 'శాండ్‌విచ్'], '🥪'),
  (['noodle', 'నూడుల్', 'chowmein', 'hakka', 'maggi'], '🍜'),
  (['manchurian', 'మంచూరియన్', 'chilli', 'చిల్లీ', '65', 'kurma', 'కుర్మా', 'curry', 'కూర', 'masala', 'మసాలా', 'gravy', 'fry', 'ఫ్రై', 'sabzi', 'सब्जी'], '🥘'),
  (['soup', 'సూప్', 'rasam', 'రసం', 'sambar', 'సాంబార్'], '🍲'),
  (['salad', 'సలాడ్'], '🥗'),
  (['dosa', 'దోశ', 'దోసె', 'uttapam', 'pesarattu', 'పెసరట్టు'], '🫓'),
  (['idli', 'ఇడ్లీ', 'ఇడ్లి', 'vada', 'వడ', 'upma', 'ఉప్మా', 'pongal', 'పొంగల్', 'puri', 'పూరి', 'poori'], '🍘'),
  (['roti', 'రోటీ', 'chapati', 'చపాతీ', 'naan', 'నాన్', 'paratha', 'పరోటా', 'parotta', 'kulcha', 'phulka', 'रोटी'], '🫓'),
  (['samosa', 'సమోసా', 'puff', 'పఫ్', 'pakoda', 'పకోడీ', 'bajji', 'బజ్జీ', 'mirchi', 'cutlet', 'kachori', 'snack'], '🥟'),
  (['french fries', 'fries', 'ఫ్రైస్', 'chips', 'చిప్స్'], '🍟'),
  (['roast', 'రోస్ట్', 'tandoori', 'తందూరి', 'kebab', 'కబాబ్', 'tikka', 'టిక్కా', 'grill', 'joint', 'leg piece', 'lollipop', 'wings', 'shawarma'], '🍗'),
  (['cake', 'కేక్', 'pastry', 'పేస్ట్రీ', 'brownie'], '🍰'),
  (['ice cream', 'ఐస్ క్రీమ్', 'icecream', 'kulfi', 'కుల్ఫీ', 'sundae', 'falooda', 'ఫలూదా'], '🍨'),
  (['sweet', 'స్వీట్', 'laddu', 'లడ్డు', 'jalebi', 'జిలేబీ', 'halwa', 'హల్వా', 'gulab', 'kaju', 'barfi', 'mysore pak', 'మిఠాయి', 'मिठाई'], '🍬'),
  (['chocolate', 'చాక్లెట్', 'candy'], '🍫'),
  (['biscuit', 'బిస్కెట్', 'cookie'], '🍪'),
  (['bread', 'బ్రెడ్', 'bun', 'బన్'], '🍞'),
  // drinks
  (['tea', 'టీ', 'chai', 'చాయ్', 'चाय'], '🍵'),
  (['coffee', 'కాఫీ', 'कॉफी'], '☕'),
  (['juice', 'జ్యూస్', 'lassi', 'లస్సీ', 'milkshake', 'shake', 'షేక్', 'mojito', 'lime', 'నిమ్మ', 'soda', 'సోడా'], '🧃'),
  (['cool drink', 'కూల్ డ్రింక్', 'coke', 'pepsi', 'sprite', 'thums', 'fanta', 'maaza', 'frooti', 'cola'], '🥤'),
  (['water', 'నీళ్ళు', 'నీరు', 'bisleri', 'पानी'], '💧'),
  (['beer', 'బీర్'], '🍺'),
  // meat, fish, eggs, dairy
  (['chicken', 'చికెన్', 'కోడి', 'murgh', 'चिकन'], '🍗'),
  (['mutton', 'మటన్', 'goat', 'మేక', 'lamb', 'keema', 'కీమా', 'मटन'], '🍖'),
  (['prawn', 'రొయ్య', 'shrimp', 'crab', 'పీత'], '🦐'),
  (['fish', 'చేప', 'చేపల', 'fillet', 'మత్స్య', 'मछली'], '🐟'),
  (['egg', 'eggs', 'గుడ్డు', 'గుడ్లు', 'omelette', 'ఆమ్లెట్', 'अंडा'], '🥚'),
  (['paneer', 'panneer', 'పనీర్', 'cheese', 'చీజ్'], '🧀'),
  (['milk', 'పాలు', 'दूध'], '🥛'),
  (['curd', 'పెరుగు', 'dahi', 'yogurt', 'butter milk', 'buttermilk', 'మజ్జిగ', 'ghee', 'నెయ్యి', 'butter', 'వెన్న'], '🥛'),
  // grocery
  (['rice', 'బియ్యం', 'అన్నం', 'चावल'], '🍚'),
  (['dal', 'దాల్', 'pappu', 'పప్పు', 'కంది', 'పెసలు', 'మినప', 'lentil', 'chana', 'శనగ', 'दाल'], '🫘'),
  (['atta', 'ఆటా', 'flour', 'పిండి', 'maida', 'మైదా', 'rava', 'రవ్వ', 'sooji', 'besan', 'आटा'], '🌾'),
  (['oil', 'నూనె', 'तेल'], '🫒'),
  (['sugar', 'చక్కెర', 'పంచదార', 'jaggery', 'బెల్లం', 'चीनी'], '🧂'),
  (['salt', 'ఉప్పు', 'नमक', 'spice', 'మసాలా పొడి', 'chilli powder', 'కారం', 'turmeric', 'పసుపు', 'jeera', 'జీలకర్ర'], '🧂'),
  (['onion', 'ఉల్లి', 'प्याज'], '🧅'),
  (['tomato', 'టమాట', 'టమోటా', 'टमाटर'], '🍅'),
  (['potato', 'బంగాళ', 'aloo', 'ఆలూ', 'आलू'], '🥔'),
  (['garlic', 'వెల్లుల్లి', 'ginger', 'అల్లం'], '🧄'),
  (['corn', 'మొక్కజొన్న', 'బేబీ కార్న్'], '🌽'),
  (['carrot', 'క్యారెట్'], '🥕'),
  (['brinjal', 'వంకాయ', 'eggplant'], '🍆'),
  (['chilli', 'మిర్చి', 'మిరప'], '🌶️'),
  (['vegetable', 'కూరగాయ', 'leafy', 'ఆకు', 'palak', 'పాలకూర', 'cabbage', 'beans', 'బీన్స్', 'सब्जी'], '🥬'),
  (['banana', 'అరటి', 'केला'], '🍌'),
  (['mango', 'మామిడి', 'आम'], '🥭'),
  (['apple', 'ఆపిల్', 'सेब'], '🍎'),
  (['orange', 'నారింజ', 'బత్తాయి', 'mosambi'], '🍊'),
  (['grape', 'ద్రాక్ష'], '🍇'),
  (['watermelon', 'పుచ్చ'], '🍉'),
  (['coconut', 'కొబ్బరి', 'नारियल'], '🥥'),
  (['fruit', 'పండు', 'పండ్లు', 'फल'], '🍎'),
  (['dry fruit', 'cashew', 'జీడిపప్పు', 'almond', 'బాదం', 'nuts', 'groundnut', 'వేరుశనగ', 'peanut'], '🥜'),
  // pharmacy / personal care
  (['tablet', 'టాబ్లెట్', 'capsule', 'మాత్ర', 'medicine', 'మందు', 'दवा'], '💊'),
  (['syrup', 'సిరప్', 'tonic'], '🧴'),
  (['bandage', 'బ్యాండేజ్', 'plaster', 'cotton', 'దూది'], '🩹'),
  (['soap', 'సబ్బు', 'shampoo', 'షాంపూ', 'cream', 'క్రీమ్', 'lotion', 'powder', 'పౌడర్', 'face wash', 'paste', 'పేస్ట్', 'brush', 'బ్రష్'], '🧴'),
  (['perfume', 'సెంట్', 'deo', 'attar'], '🌸'),
  // clothes, footwear, home
  (['saree', 'చీర', 'साड़ी', 'dress', 'కుర్తా', 'kurti', 'lehenga'], '👗'),
  (['shirt', 'షర్ట్', 't-shirt', 'tshirt'], '👕'),
  (['pant', 'ప్యాంట్', 'jeans', 'జీన్స్', 'trouser', 'lungi', 'లుంగీ', 'dhoti', 'పంచె'], '👖'),
  (['shoe', 'షూ', 'chappal', 'చెప్పు', 'sandal', 'slipper', 'జోళ్ళు'], '👟'),
  (['bag', 'బ్యాగ్', 'purse'], '👜'),
  (['watch', 'వాచ్'], '⌚'),
  (['gold', 'బంగారం', 'silver', 'వెండి', 'ring', 'ఉంగరం', 'chain', 'గొలుసు', 'jewel', 'నగ'], '💍'),
  (['flower', 'పూలు', 'పువ్వు', 'garland', 'దండ', 'rose'], '💐'),
  // electronics, hardware, stationery
  (['mobile', 'మొబైల్', 'phone', 'ఫోన్', 'smartphone'], '📱'),
  (['charger', 'ఛార్జర్', 'cable', 'కేబుల్', 'adapter', 'wire', 'వైర్'], '🔌'),
  (['battery', 'బ్యాటరీ', 'cell'], '🔋'),
  (['bulb', 'బల్బ్', 'led', 'light', 'లైట్', 'tube'], '💡'),
  (['earphone', 'headphone', 'ఇయర్‌ఫోన్', 'speaker', 'స్పీకర్'], '🎧'),
  (['laptop', 'computer', 'కంప్యూటర్', 'mouse', 'keyboard'], '💻'),
  (['tv', 'టీవీ', 'television'], '📺'),
  (['fan', 'ఫ్యాన్', 'cooler', 'కూలర్'], '🌀'),
  (['pen', 'పెన్', 'pencil', 'పెన్సిల్', 'marker'], '🖊️'),
  (['book', 'పుస్తకం', 'notebook', 'నోట్ బుక్', 'note book'], '📒'),
  (['paper', 'పేపర్', 'xerox', 'జిరాక్స్', 'print', 'ప్రింట్'], '📄'),
  (['cement', 'సిమెంట్', 'brick', 'ఇటుక', 'sand', 'ఇసుక', 'steel', 'paint', 'పెయింట్', 'pipe', 'పైప్'], '🧱'),
  (['tool', 'hammer', 'screw', 'nail', 'మేకు', 'spanner'], '🔧'),
  (['toy', 'బొమ్మ', 'ball', 'బంతి', 'బ్యాట్'], '🧸'),
  (['petrol', 'diesel', 'fuel', 'పెట్రోల్'], '⛽'),
  (['service', 'సర్వీస్', 'repair', 'రిపేర్', 'cutting', 'కటింగ్', 'haircut', 'shave', 'facial', 'wash'], '🛠️'),
  (['gas', 'గ్యాస్', 'cylinder', 'సిలిండర్'], '🔥'),
  (['ticket', 'టికెట్'], '🎟️'),
];

String _askodoxIconNorm(String s) => ' ${s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9ఀ-౿ऀ-ॿ]+'), ' ')} ';

/// The picture for an item: the first rule whose word appears in the item's name (any language), else a shopping
/// bag. Latin words match the start of a word ("chickens" -> chicken; three letters or fewer only whole words);
/// Indian scripts match inside a word.
String askodoxItemIcon(String name, {String? nameTe, String? category}) {
  final text = _askodoxIconNorm('$name ${nameTe ?? ''} ${category ?? ''}');
  for (final rule in _askodoxItemIconRules) {
    for (final word in rule.$1) {
      final w = word.toLowerCase();
      final latin = RegExp(r'^[a-z0-9 \-]+$').hasMatch(w);
      final key = w.replaceAll('-', ' ');
      // short words ("pen", "tea", "dal") only as a whole word, so "penne" or "teak" never match
      final hit = !latin ? text.contains(w) : (key.length <= 3 ? text.contains(' $key ') : text.contains(' $key'));
      if (hit) return rule.$2;
    }
  }
  return '🛍️';
}
