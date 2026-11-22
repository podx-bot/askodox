import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../pos/data/pos_payment_alerts.dart';
import '../pos/data/pos_repository.dart' show AskodoxJson;
import '../pos/domain/money_ledger.dart';
import '../pos/presentation/money_screens.dart' show AskodoxDuesScreen;
import 'payment_voice_sheet.dart';

/// `/payment-voice[?shop=<id>]`: the Payment voice folder as its own page, so a Home chat shortcut can open it
/// (owner 2026-11-22: any page can sit above the chat).
class AskodoxPaymentVoiceScreen extends StatelessWidget {
  const AskodoxPaymentVoiceScreen({super.key, this.shop});
  final String? shop;

  @override
  Widget build(BuildContext context) {
    final te = Localizations.localeOf(context).languageCode == 'te';
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'పేమెంట్ వాయిస్' : 'Payment voice')),
      body: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: AskodoxPaymentVoiceSheet(businessId: (shop ?? '').isEmpty ? null : shop, inSheet: false),
      ),
    );
  }
}

/// `/me/dues`: "Coming up" (EMI, current bill, rent ...) with this phone's own payments for the suggestions.
class AskodoxMyDuesRouteScreen extends ConsumerStatefulWidget {
  const AskodoxMyDuesRouteScreen({super.key});

  @override
  ConsumerState<AskodoxMyDuesRouteScreen> createState() => _AskodoxMyDuesRouteScreenState();
}

class _AskodoxMyDuesRouteScreenState extends ConsumerState<AskodoxMyDuesRouteScreen> {
  List<AskodoxJson> _events = const [];
  List<AskodoxMoneyItem> _items = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    List<AskodoxJson> events = const [];
    AskodoxMyPhoneAlerts? m;
    try {
      events = await ref.read(askodoxPaymentAlertsBridgeProvider).localEvents();
    } catch (_) {}
    try {
      m = await AskodoxMyPhoneAlerts.load();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _events = events;
      _items = askodoxItemsFromPhone(events, m?.places ?? const [], m?.assigned ?? const {}, m?.links ?? const {});
    });
  }

  @override
  Widget build(BuildContext context) => AskodoxDuesScreen(phoneEvents: _events, items: _items);
}
