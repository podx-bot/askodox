import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../application/seller_providers.dart';
import '../domain/entities/seller_models.dart';

class SellerRequestsScreen extends ConsumerWidget {
  const SellerRequestsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(sellerProvider);
    final nearby = state.requests.where((request) => !request.isSellerSubmitted).toList();
    final te = Localizations.localeOf(context).languageCode == 'te';
    String t(String en, String telugu) => te ? telugu : en;
    return Scaffold(appBar: AppBar(title: Text(t('Customer requests', 'కస్టమర్ రిక్వెస్టులు'))), body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1000), child: nearby.isEmpty ? Center(child: Text(t('No nearby requests right now', 'ప్రస్తుతం దగ్గరలో రిక్వెస్టులు లేవు'))) : ListView.separated(padding: const EdgeInsets.all(20), itemCount: nearby.length, separatorBuilder: (_, __) => const SizedBox(height: 12), itemBuilder: (context, index) {
      final request = nearby[index];
      final responded = state.responses.any((item) => item.requestId == request.id);
      return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ListTile(contentPadding: EdgeInsets.zero, leading: CircleAvatar(radius: 28, child: Text(request.icon, style: const TextStyle(fontSize: 24))), title: Text(request.productName, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)), subtitle: Text(te ? '${request.interestedBuyers} మంది ఆసక్తి చూపించారు  •  ${request.radiusKm.toStringAsFixed(0)} కి.మీ లోపల' : '${request.interestedBuyers} interested buyers  •  Within ${request.radiusKm.toStringAsFixed(0)} km')),
        Wrap(spacing: 8, runSpacing: 8, children: [Chip(avatar: const Icon(Icons.schedule, size: 18), label: Text(te ? '${DateFormat.MMMd().format(request.expiresAt)} వరకు' : 'Expires ${DateFormat.MMMd().format(request.expiresAt)}')), if (request.targetPrice != null) Chip(avatar: const Icon(Icons.sell_outlined, size: 18), label: Text('${t('Target', 'టార్గెట్')} ₹${request.targetPrice!.toStringAsFixed(0)}'))]),
        const SizedBox(height: 10),
        if (responded) Row(children: [const Icon(Icons.check_circle, color: Colors.green), const SizedBox(width: 8), Text(t('Response submitted', 'రెస్పాన్స్ పంపబడింది'))]) else Wrap(spacing: 8, children: [FilledButton(onPressed: () => _responseSheet(context, ref, request, te), child: Text(t('Available', 'అందుబాటులో ఉంది'))), OutlinedButton(onPressed: () => ref.read(sellerProvider.notifier).respond(SellerResponse(requestId: request.id, isAvailable: false)), child: Text(t('Not available', 'అందుబాటులో లేదు')))]),
      ])));
    }))));
  }

  Future<void> _responseSheet(BuildContext context, WidgetRef ref, ProductRequest request, bool te) async {
    String t(String en, String telugu) => te ? telugu : en;
    final price = TextEditingController(); final stock = TextEditingController(); final offer = TextEditingController();
    final submit = await showModalBottomSheet<bool>(context: context, isScrollControlled: true, builder: (context) => Padding(padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.viewInsetsOf(context).bottom + 20), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [Text(te ? '${request.productName} కోసం స్పందించండి' : 'Respond for ${request.productName}', style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 16), TextField(controller: price, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: t('Your price (₹)', 'మీ ధర (₹)'))), const SizedBox(height: 12), TextField(controller: stock, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: t('Available stock', 'అందుబాటులో స్టాక్'))), const SizedBox(height: 12), TextField(controller: offer, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: t('Optional offer price (₹)', 'ఐచ్చిక ఆఫర్ ధర (₹)'))), const SizedBox(height: 20), FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(t('Submit response', 'రెస్పాన్స్ పంపండి')))])));
    final amount = double.tryParse(price.text); final quantity = int.tryParse(stock.text);
    if (submit == true && amount != null && amount > 0 && quantity != null && quantity >= 0) await ref.read(sellerProvider.notifier).respond(SellerResponse(requestId: request.id, isAvailable: true, price: amount, stock: quantity, offerPrice: double.tryParse(offer.text)));
    price.dispose(); stock.dispose(); offer.dispose();
  }
}
