import 'package:flutter/material.dart';
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

String _statusLabel(BuildContext context, String raw) {
  final value = raw.toUpperCase();
  if (!_te(context)) return value.replaceAll('_', ' ');
  return switch (value) {
    'PLACED' => 'ప్లేస్ చేయబడింది',
    'ACCEPTED' => 'ఆమోదించబడింది',
    'REJECTED' => 'తిరస్కరించబడింది',
    'FULFILLED' => 'పూర్తైంది',
    'CANCELLED' => 'రద్దు చేయబడింది',
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
                  _t(context, 'You have not placed any orders yet.',
                      'మీరు ఇంకా ఎలాంటి ఆర్డర్లు పెట్టలేదు.'),
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
              itemBuilder: (context, index) =>
                  _OrderCard(order: orders[index], isSeller: false),
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
                    'No orders yet. Once a buyer orders one of your listings, it will show up here.',
                    'ఇంకా ఆర్డర్లు లేవు. మీ లిస్టింగ్‌లలో ఏదైనా ఒకటి కొనుగోలుదారు ఆర్డర్ చేస్తే అది ఇక్కడ కనిపిస్తుంది.',
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
              itemBuilder: (context, index) =>
                  _OrderCard(order: orders[index], isSeller: true),
            ),
          );
        },
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order, required this.isSeller});
  final Order order;
  final bool isSeller;

  @override
  Widget build(BuildContext context) {
    final amount = order.totalAmount ?? order.price;
    final amountLabel = amount == null ? null : '₹${amount.toStringAsFixed(0)}';
    final quantity = order.quantity;
    final quantityLabel = quantity == null
        ? null
        : '${quantity.toStringAsFixed(quantity == quantity.roundToDouble() ? 0 : 2)}${order.unit != null ? ' ${order.unit}' : ''}';
    final statusColor = _statusColor(order.status);
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
