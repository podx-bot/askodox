import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/order_repository.dart';

// Added 2026-09-15 (round 5) alongside the real order-placement backend --
// see docs/ASKODOX_EXECUTION_TRACKER.md. Before this, an order was purely a
// local UI animation with nowhere for a buyer or seller to ever see it
// again. These two screens are deliberately simple, read-only lists (no
// accept/reject actions yet) mirroring DealInboxScreen's style
// (features/deals/presentation/deal_screens.dart) -- closing the exact gap
// the product owner reported: a real order that neither side could find
// afterwards.

bool _te(BuildContext context) =>
    Localizations.localeOf(context).languageCode == 'te';
String _t(BuildContext context, String en, String te) => _te(context) ? te : en;

// Updated 2026-09-16 (round 8): PLACED now reads "Requested" everywhere --
// not "Placed" -- because tapping the buyer-facing button no longer closes
// a deal by itself; it only sends a request the seller must still accept.
// Rewritten to use _t() consistently for both languages (previously English
// fell back to a raw enum-derived string while only Telugu had real
// wording).
String _statusLabel(BuildContext context, String raw) {
  final value = raw.toUpperCase();
  return switch (value) {
    'PLACED' => _t(context, 'Requested', 'అభ్యర్థించారు'),
    'ACCEPTED' => _t(context, 'Accepted', 'ఆమోదించబడింది'),
    'REJECTED' => _t(context, 'Declined', 'తిరస్కరించబడింది'),
    'FULFILLED' => _t(context, 'Completed', 'పూర్తైంది'),
    'CANCELLED' => _t(context, 'Cancelled', 'రద్దు చేయబడింది'),
    _ => raw.replaceAll('_', ' '),
  };
}

Color _statusColor(String raw) => switch (raw.toUpperCase()) {
      'ACCEPTED' || 'FULFILLED' => const Color(0xFF1B8A3B),
      'REJECTED' || 'CANCELLED' => const Color(0xFFB3261E),
      _ => const Color(0xFF9A7B00),
    };

class MyOrdersScreen extends ConsumerStatefulWidget {
  const MyOrdersScreen({super.key});

  @override
  ConsumerState<MyOrdersScreen> createState() => _MyOrdersScreenState();
}

class _MyOrdersScreenState extends ConsumerState<MyOrdersScreen> {
  Future<List<Order>>? _future;

  void _reload() {
    setState(() {
      _future = ref.read(orderRepositoryProvider).myOrders();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= ref.read(orderRepositoryProvider).myOrders();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_t(context, 'My orders', 'నా ఆర్డర్లు')),
        actions: [
          IconButton(
              onPressed: _reload,
              icon: const Icon(Icons.refresh),
              tooltip: _t(context, 'Refresh', 'రిఫ్రెష్'))
        ],
      ),
      body: FutureBuilder<List<Order>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _OrdersErrorState(
                message: '${snapshot.error}', onRetry: _reload);
          }
          final orders = snapshot.data ?? const <Order>[];
          if (orders.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _t(context, 'You have not sent any requests yet.',
                      'మీరు ఇంకా ఎలాంటి అభ్యర్థనలు పంపలేదు.'),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView.separated(
              padding: const EdgeInsets.all(14),
              itemCount: orders.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) => _OrderCard(
                  order: orders[index], isSeller: false, onChanged: _reload),
            ),
          );
        },
      ),
    );
  }
}

class IncomingOrdersScreen extends ConsumerStatefulWidget {
  const IncomingOrdersScreen({super.key});

  @override
  ConsumerState<IncomingOrdersScreen> createState() =>
      _IncomingOrdersScreenState();
}

class _IncomingOrdersScreenState extends ConsumerState<IncomingOrdersScreen> {
  Future<List<Order>>? _future;

  void _reload() {
    setState(() {
      _future = ref.read(orderRepositoryProvider).incomingOrders();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= ref.read(orderRepositoryProvider).incomingOrders();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_t(context, 'Incoming orders', 'వచ్చిన ఆర్డర్లు')),
        actions: [
          IconButton(
              onPressed: _reload,
              icon: const Icon(Icons.refresh),
              tooltip: _t(context, 'Refresh', 'రిఫ్రెష్'))
        ],
      ),
      body: FutureBuilder<List<Order>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _OrdersErrorState(
                message: '${snapshot.error}', onRetry: _reload);
          }
          final orders = snapshot.data ?? const <Order>[];
          if (orders.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _t(
                    context,
                    'No requests yet. Once a buyer sends a request for one of your listings, it will show up here.',
                    'ఇంకా అభ్యర్థనలు లేవు. మీ లిస్టింగ్‌లలో ఏదైనా ఒకటి కొనుగోలుదారు అభ్యర్థిస్తే అది ఇక్కడ కనిపిస్తుంది.',
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView.separated(
              padding: const EdgeInsets.all(14),
              itemCount: orders.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) => _OrderCard(
                  order: orders[index], isSeller: true, onChanged: _reload),
            ),
          );
        },
      ),
    );
  }
}

// Updated 2026-09-16 (round 8). Converted from a plain StatelessWidget to a
// ConsumerStatefulWidget so it can call respondToOrder() itself and show a
// small in-flight/error state around that call -- mirroring how other
// action buttons in this app behave (e.g. deal_screens.dart's accept/decline
// pattern). `onChanged` lets the parent screen refresh its list after a
// successful accept/decline, without this card needing to know how its
// parent loads data.
class _OrderCard extends ConsumerStatefulWidget {
  const _OrderCard(
      {required this.order, required this.isSeller, this.onChanged});
  final Order order;
  final bool isSeller;
  final VoidCallback? onChanged;

  @override
  ConsumerState<_OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends ConsumerState<_OrderCard> {
  bool _responding = false;
  String? _actionError;

  Future<void> _respond(String status) async {
    setState(() {
      _responding = true;
      _actionError = null;
    });
    final result = await ref
        .read(orderRepositoryProvider)
        .respondToOrder(orderId: widget.order.id, status: status);
    if (!mounted) return;
    setState(() => _responding = false);
    if (result.success) {
      widget.onChanged?.call();
    } else {
      setState(() => _actionError = result.message ??
          _t(context, 'Unable to update this request.',
              'ఈ అభ్యర్థనను నవీకరించడం సాధ్యం కాలేదు.'));
    }
  }

  void _copyContact(String phone) {
    Clipboard.setData(ClipboardData(text: phone));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(_t(context, 'Number copied: $phone',
          'నంబర్ కాపీ చేయబడింది: $phone')),
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final isSeller = widget.isSeller;
    final amount = order.totalAmount ?? order.price;
    final amountLabel = amount == null ? null : '₹${amount.toStringAsFixed(0)}';
    final quantity = order.quantity;
    final quantityLabel = quantity == null
        ? null
        : '${quantity.toStringAsFixed(quantity == quantity.roundToDouble() ? 0 : 2)}${order.unit != null ? ' ${order.unit}' : ''}';
    final statusColor = _statusColor(order.status);
    final status = order.status.toUpperCase();
    // Added 2026-09-16 (round 8). See order_contact_visibility.py: the
    // backend only fills in the *other* party's contact once the order is
    // ACCEPTED/FULFILLED -- so whichever of these is non-null here is
    // already safe to show.
    final contact = isSeller ? order.buyerContact : order.sellerContact;
    final canRespond = isSeller && status == 'PLACED';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE1E8F2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text(order.productTitle,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 15))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
                color: statusColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10)),
            child: Text(_statusLabel(context, order.status),
                style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 11)),
          ),
        ]),
        const SizedBox(height: 6),
        Wrap(spacing: 10, runSpacing: 4, children: [
          if (quantityLabel != null)
            Text(quantityLabel,
                style: const TextStyle(
                    color: Color(0xFF667085),
                    fontWeight: FontWeight.w600,
                    fontSize: 13)),
          if (amountLabel != null)
            Text(amountLabel,
                style: const TextStyle(
                    color: Color(0xFF10204A),
                    fontWeight: FontWeight.w800,
                    fontSize: 13)),
        ]),
        if (order.createdAt != null) ...[
          const SizedBox(height: 4),
          Text('${order.createdAt!.toLocal()}'.split('.').first,
              style: const TextStyle(
                  color: Color(0xFF9AA4B2),
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ],
        if (order.buyerNote != null && order.buyerNote!.trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            isSeller
                ? _t(context, 'Buyer note: ${order.buyerNote}',
                    'కొనుగోలుదారు గమనిక: ${order.buyerNote}')
                : order.buyerNote!,
            style: const TextStyle(
                color: Color(0xFF475467),
                fontSize: 12.5,
                fontStyle: FontStyle.italic),
          ),
        ],
        // Added 2026-09-16 (round 8): contact only ever appears once the
        // backend itself has revealed it -- there is no client-side
        // override, so this row simply reflects what accepting unlocked.
        if (contact != null) ...[
          const SizedBox(height: 10),
          InkWell(
            onTap: () => _copyContact(contact),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6EE),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.call, size: 16, color: Color(0xFF1B8A3B)),
                const SizedBox(width: 8),
                Text(
                  isSeller
                      ? _t(context, 'Buyer: $contact', 'కొనుగోలుదారు: $contact')
                      : _t(context, 'Seller: $contact', 'విక్రేత: $contact'),
                  style: const TextStyle(
                      color: Color(0xFF1B8A3B),
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.copy, size: 14, color: Color(0xFF1B8A3B)),
              ]),
            ),
          ),
        ],
        // Added 2026-09-16 (round 8): the actual Accept/Decline step this
        // whole round exists to add -- see Master Architecture Point 13.
        // Only the seller sees these, and only while the request is still
        // PLACED (i.e. neither accepted nor declined yet).
        if (canRespond) ...[
          const SizedBox(height: 10),
          if (_actionError != null) ...[
            Text(_actionError!,
                style: const TextStyle(
                    color: Color(0xFFB3261E),
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
          ],
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _responding ? null : () => _respond('REJECTED'),
                child: Text(_t(context, 'Decline', 'తిరస్కరించు')),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: _responding ? null : () => _respond('ACCEPTED'),
                child: _responding
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(_t(context, 'Accept', 'ఆమోదించు')),
              ),
            ),
          ]),
        ],
      ]),
    );
  }
}

class _OrdersErrorState extends StatelessWidget {
  const _OrdersErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off, size: 42),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.tonal(
                onPressed: onRetry,
                child: Text(_t(context, 'Retry', 'మళ్లీ ప్రయత్నించండి'))),
          ]),
        ),
      );
}
