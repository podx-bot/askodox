import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../location/presentation/map_pin_picker.dart';
import '../data/mobility_repository.dart';

/// Who delivers this order and where the delivery is -- shown next to the
/// order's own status, never mixed with it (a seller accepting the order is
/// not a delivery confirmation).
class AskodoxFulfilmentPanel extends ConsumerStatefulWidget {
  const AskodoxFulfilmentPanel({super.key, required this.orderId, required this.te});
  final String orderId;
  final bool te;

  @override
  ConsumerState<AskodoxFulfilmentPanel> createState() => _AskodoxFulfilmentPanelState();
}

class _AskodoxFulfilmentPanelState extends ConsumerState<AskodoxFulfilmentPanel> {
  OrderFulfilment? _value;
  String? _error;
  bool _busy = false;

  String t(String en, String te) => widget.te ? te : en;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await ref.read(mobilityRepositoryProvider).fulfilment(widget.orderId);
    if (mounted) setState(() => _value = r.data);
  }

  Future<void> _choose(String mode) async {
    Map<String, Object?>? pickup;
    Map<String, Object?>? drop;
    if (mode == 'ASKODOX_NETWORK_DRIVER') {
      final a = await AskodoxMapPinPicker.open(context, title: t('Pickup point', 'పికప్ ఎక్కడ?'));
      if (a == null || !mounted) return;
      final b = await AskodoxMapPinPicker.open(context, title: t('Drop point', 'డ్రాప్ ఎక్కడ?'));
      if (b == null || !mounted) return;
      pickup = {'label': a.label, 'latitude': a.latitude, 'longitude': a.longitude};
      drop = {'label': b.label, 'latitude': b.latitude, 'longitude': b.longitude};
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await ref.read(mobilityRepositoryProvider).setFulfilment(widget.orderId, mode, pickup: pickup, drop: drop);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r.ok) _value = r.data;
      _error = r.ok ? null : r.error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final v = _value;
    if (v == null) return const SizedBox.shrink();
    final closed = const {'CANCELLED', 'REJECTED', 'CLOSED'}.contains(v.commerceStatus.toUpperCase());
    return Padding(
      key: ValueKey('askodoxFulfilment-${widget.orderId}'),
      padding: const EdgeInsets.only(top: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.local_shipping_outlined, size: 18),
          const SizedBox(width: 6),
          Expanded(
              child: Text('${t('Delivery', 'డెలివరీ')}: ${askodoxFulfilmentLabel(v.responsibility, widget.te)}',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
          if (!closed)
            PopupMenuButton<String>(
              key: ValueKey('askodoxFulfilmentChoose-${widget.orderId}'),
              enabled: !_busy,
              tooltip: t('Who delivers?', 'ఎవరు డెలివరీ చేస్తారు?'),
              onSelected: _choose,
              itemBuilder: (_) => [
                for (final m in askodoxFulfilmentModes)
                  PopupMenuItem(value: m, child: Text(askodoxFulfilmentLabel(m, widget.te))),
              ],
              child: Text(t('Change', 'మార్చు'), style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
        ]),
        Text(askodoxDeliveryStatusLabel(v.deliveryStatus, widget.te),
            key: ValueKey('askodoxDeliveryStatus-${widget.orderId}'),
            style: const TextStyle(fontSize: 12.5, color: Color(0xFF475467))),
        if (v.jobStage.isNotEmpty) Text(v.jobStage, style: const TextStyle(fontSize: 12, color: Color(0xFF667085))),
        if (_error != null) Text(_error!, style: const TextStyle(fontSize: 12, color: Color(0xFFB3261E))),
      ]),
    );
  }
}
