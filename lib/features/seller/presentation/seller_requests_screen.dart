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
    return Scaffold(appBar: AppBar(title: const Text('Customer requests')), body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1000), child: nearby.isEmpty ? const Center(child: Text('No nearby requests right now')) : ListView.separated(padding: const EdgeInsets.all(20), itemCount: nearby.length, separatorBuilder: (_, __) => const SizedBox(height: 12), itemBuilder: (context, index) {
      final request = nearby[index];
      final responded = state.responses.any((item) => item.requestId == request.id);
      return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ListTile(contentPadding: EdgeInsets.zero, leading: CircleAvatar(radius: 28, child: Text(request.icon, style: const TextStyle(fontSize: 24))), title: Text(request.productName, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)), subtitle: Text('${request.interestedBuyers} interested buyers  •  Within ${request.radiusKm.toStringAsFixed(0)} km')),
        Wrap(spacing: 8, runSpacing: 8, children: [Chip(avatar: const Icon(Icons.schedule, size: 18), label: Text('Expires ${DateFormat.MMMd().format(request.expiresAt)}')), if (request.targetPrice != null) Chip(avatar: const Icon(Icons.sell_outlined, size: 18), label: Text('Target ₹${request.targetPrice!.toStringAsFixed(0)}'))]),
        const SizedBox(height: 10),
        if (responded) const Row(children: [Icon(Icons.check_circle, color: Colors.green), SizedBox(width: 8), Text('Response submitted')]) else Wrap(spacing: 8, children: [FilledButton(onPressed: () => _responseSheet(context, ref, request), child: const Text('Available')), OutlinedButton(onPressed: () => ref.read(sellerProvider.notifier).respond(SellerResponse(requestId: request.id, isAvailable: false)), child: const Text('Not available'))]),
      ])));
    }))));
  }

  Future<void> _responseSheet(BuildContext context, WidgetRef ref, ProductRequest request) async {
    final price = TextEditingController(); final stock = TextEditingController(); final offer = TextEditingController();
    final submit = await showModalBottomSheet<bool>(context: context, isScrollControlled: true, builder: (context) => Padding(padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.viewInsetsOf(context).bottom + 20), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [Text('Respond for ${request.productName}', style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 16), TextField(controller: price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Your price (₹)')), const SizedBox(height: 12), TextField(controller: stock, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Available stock')), const SizedBox(height: 12), TextField(controller: offer, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Optional offer price (₹)')), const SizedBox(height: 20), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Submit response'))])));
    final amount = double.tryParse(price.text); final quantity = int.tryParse(stock.text);
    if (submit == true && amount != null && amount > 0 && quantity != null && quantity >= 0) await ref.read(sellerProvider.notifier).respond(SellerResponse(requestId: request.id, isAvailable: true, price: amount, stock: quantity, offerPrice: double.tryParse(offer.text)));
    price.dispose(); stock.dispose(); offer.dispose();
  }
}
