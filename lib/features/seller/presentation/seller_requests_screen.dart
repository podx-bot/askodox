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
    final nearby = state.requests
        .where((request) => !request.isSellerSubmitted)
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Customer requests')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: nearby.isEmpty
              ? const Center(child: Text('No nearby requests right now'))
              : ListView.separated(
                  key: const Key('sellerRequestsList'),
                  padding: const EdgeInsets.all(20),
                  itemCount: nearby.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final request = nearby[index];
                    final responded = state.responses
                        .any((item) => item.requestId == request.id);
                    return Card(
                      key: Key('sellerRequest-${request.id}'),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: CircleAvatar(
                                radius: 28,
                                child: Text(
                                  request.icon,
                                  style: const TextStyle(fontSize: 24),
                                ),
                              ),
                              title: Text(
                                request.productName,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text(
                                '${request.interestedBuyers} interested buyers  •  Within ${request.radiusKm.toStringAsFixed(0)} km',
                              ),
                            ),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                Chip(
                                  avatar: const Icon(Icons.schedule, size: 18),
                                  label: Text(
                                    'Expires ${DateFormat.MMMd().format(request.expiresAt)}',
                                  ),
                                ),
                                if (request.targetPrice != null)
                                  Chip(
                                    avatar: const Icon(
                                      Icons.sell_outlined,
                                      size: 18,
                                    ),
                                    label: Text(
                                      'Target ₹${request.targetPrice!.toStringAsFixed(0)}',
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            if (responded)
                              Row(
                                key: Key(
                                  'sellerRequestResponded-${request.id}',
                                ),
                                children: const [
                                  Icon(Icons.check_circle, color: Colors.green),
                                  SizedBox(width: 8),
                                  Text('Response submitted'),
                                ],
                              )
                            else
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  FilledButton(
                                    key: Key(
                                      'sellerRequestAvailable-${request.id}',
                                    ),
                                    onPressed: () =>
                                        _responseSheet(context, ref, request),
                                    child: const Text('Available'),
                                  ),
                                  OutlinedButton(
                                    key: Key(
                                      'sellerRequestUnavailable-${request.id}',
                                    ),
                                    onPressed: () async {
                                      await ref
                                          .read(sellerProvider.notifier)
                                          .respond(
                                            SellerResponse(
                                              requestId: request.id,
                                              isAvailable: false,
                                            ),
                                          );
                                    },
                                    child: const Text('Not available'),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }

  Future<void> _responseSheet(
    BuildContext context,
    WidgetRef ref,
    ProductRequest request,
  ) async {
    final price = TextEditingController();
    final stock = TextEditingController();
    final offer = TextEditingController();

    final submit = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          key: const Key('sellerRequestResponseSheet'),
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.viewInsetsOf(sheetContext).bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Respond for ${request.productName}',
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('sellerRequestPrice'),
                controller: price,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Your price (₹)'),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('sellerRequestStock'),
                controller: stock,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Available stock'),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('sellerRequestOffer'),
                controller: offer,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) {
                  FocusScope.of(sheetContext).unfocus();
                },
                decoration: const InputDecoration(
                  labelText: 'Optional offer price (₹)',
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                key: const Key('sellerRequestSubmit'),
                onPressed: () {
                  FocusScope.of(sheetContext).unfocus();
                  Navigator.pop(sheetContext, true);
                },
                child: const Text('Submit response'),
              ),
            ],
          ),
        ),
      ),
    );

    if (submit == true) {
      final amount = double.tryParse(price.text.trim());
      final quantity = int.tryParse(stock.text.trim());
      final offerText = offer.text.trim();
      final offerAmount = offerText.isEmpty ? null : double.tryParse(offerText);
      final validOffer = offerAmount == null || offerAmount > 0;

      if (amount != null &&
          amount > 0 &&
          quantity != null &&
          quantity >= 0 &&
          validOffer) {
        await ref.read(sellerProvider.notifier).respond(
              SellerResponse(
                requestId: request.id,
                isAvailable: true,
                price: amount,
                stock: quantity,
                offerPrice: offerAmount,
              ),
            );
      } else if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Enter a valid price and available stock.'),
          ),
        );
      }
    }

    price.dispose();
    stock.dispose();
    offer.dispose();
  }
}
