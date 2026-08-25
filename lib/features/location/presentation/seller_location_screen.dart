import 'package:flutter/material.dart';
import '../domain/geo_models.dart';

class SellerLocationScreen extends StatefulWidget {
  const SellerLocationScreen({super.key});
  @override
  State<SellerLocationScreen> createState() => _SellerLocationScreenState();
}

class _SellerLocationScreenState extends State<SellerLocationScreen> {
  final lat = TextEditingController(text: '17.4170');
  final lng = TextEditingController(text: '78.4370');
  final landmark = TextEditingController();
  String? error;
  bool confirmed = false, public = true, hideExact = false;
  double radius = 5;

  bool get te => Localizations.localeOf(context).languageCode == 'te';
  String t(String en, String telugu) => te ? telugu : en;

  @override
  void dispose() { lat.dispose(); lng.dispose(); landmark.dispose(); super.dispose(); }

  void validate() {
    final p = GeoPoint(double.tryParse(lat.text) ?? double.nan, double.tryParse(lng.text) ?? double.nan);
    setState(() {
      if (lat.text.isEmpty || lng.text.isEmpty) {
        error = t('Shop coordinates are required', 'షాప్ కోఆర్డినేట్లు అవసరం');
      } else if (!p.latitude.isFinite || p.latitude < -90 || p.latitude > 90) {
        error = t('Enter a valid latitude from -90 to 90', '-90 నుంచి 90 మధ్య సరైన అక్షాంశం నమోదు చేయండి');
      } else if (!p.longitude.isFinite || p.longitude < -180 || p.longitude > 180) {
        error = t('Enter a valid longitude from -180 to 180', '-180 నుంచి 180 మధ్య సరైన రేఖాంశం నమోదు చేయండి');
      } else {
        error = null;
        confirmed = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(t('Shop location', 'షాప్ లొకేషన్'))),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      Text(t('Set the public location buyers use to discover your shop. Customer home addresses are never shown.', 'కస్టమర్లు మీ షాప్‌ను కనుగొనడానికి ఉపయోగించే పబ్లిక్ లొకేషన్‌ను సెట్ చేయండి. కస్టమర్ ఇంటి చిరునామాలు ఎప్పుడూ చూపించబడవు.')),
      const SizedBox(height: 16),
      Container(height: 180, decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(20)), child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.store_mall_directory, size: 54), Text(t('Adjust map pin placeholder', 'మ్యాప్ పిన్‌ను సర్దండి'))]))),
      Row(children: [Expanded(child: TextField(controller: lat, decoration: InputDecoration(labelText: t('Latitude', 'అక్షాంశం')))), const SizedBox(width: 12), Expanded(child: TextField(controller: lng, decoration: InputDecoration(labelText: t('Longitude', 'రేఖాంశం'))))]),
      TextField(controller: landmark, decoration: InputDecoration(labelText: t('Nearby landmark', 'దగ్గరలోని ల్యాండ్‌మార్క్'))),
      Text(te ? 'సర్వీస్ పరిధి: ${radius.toStringAsFixed(0)} కి.మీ' : 'Service radius: ${radius.toStringAsFixed(0)} km'),
      Slider(value: radius, min: 1, max: 50, divisions: 49, onChanged: (v) => setState(() => radius = v)),
      SwitchListTile(value: public, onChanged: (v) => setState(() => public = v), title: Text(t('Public shop location', 'పబ్లిక్ షాప్ లొకేషన్'))),
      SwitchListTile(value: hideExact, onChanged: (v) => setState(() => hideExact = v), title: Text(t('Hide exact location until buyer opens shop', 'కస్టమర్ షాప్ ఓపెన్ చేసే వరకు ఖచ్చితమైన లొకేషన్‌ను దాచండి')), subtitle: Text(t('Show an approximate location in discovery results.', 'డిస్కవరీ ఫలితాల్లో సుమారు లొకేషన్‌ను మాత్రమే చూపించండి.'))),
      if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      FilledButton.icon(onPressed: validate, icon: const Icon(Icons.check), label: Text(t('Confirm shop location', 'షాప్ లొకేషన్ నిర్ధారించండి'))),
      if (confirmed) Card(color: Theme.of(context).colorScheme.primaryContainer, child: ListTile(leading: const Icon(Icons.verified), title: Text(t('Location confirmed', 'లొకేషన్ నిర్ధారించబడింది')), subtitle: Text(t('Your shop now appears in mock nearby results.', 'మీ షాప్ ఇప్పుడు nearby ఫలితాల్లో కనిపిస్తుంది.')))),
      OutlinedButton(onPressed: () => showDialog(context: context, builder: (_) => AlertDialog(title: Text(t('Buyer preview', 'కస్టమర్ ప్రివ్యూ')), content: Text(t('Buyers see an approximate marker, verification, trust score, products and offers.', 'కస్టమర్లు సుమారు మ్యాప్ మార్కర్, వెరిఫికేషన్, ట్రస్ట్ స్కోర్, ఉత్పత్తులు మరియు ఆఫర్లను చూస్తారు.')), actions: const [CloseButton()])), child: Text(t('Preview how buyers see the shop', 'కస్టమర్లు షాప్‌ను ఎలా చూస్తారో ప్రివ్యూ చేయండి'))),
      Text(t('Address-distance validation will be enabled when a geocoding provider is connected.', 'జియోకోడింగ్ ప్రొవైడర్ కనెక్ట్ అయిన తర్వాత చిరునామా-దూరం వెరిఫికేషన్ యాక్టివ్ అవుతుంది.')),
    ]),
  );
}
