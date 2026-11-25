import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../pos/data/pos_repository.dart';
import '../../pos/presentation/pos_common.dart';
import '../../pos/presentation/pos_home_screen.dart' show AskodoxPosSetupForm;
import 'step_kit.dart';

/// Owner 2026-11-25 (3-step design, batch 34): "which shop?" pages — `/pos` (shop billing) and `/crm` (Business CRM).
/// Top = ONE question (which shop?), middle = ONE list of my shops (tap = open it), bottom = ONE big button (add a shop).
/// [jumpIfOne] opens the only shop at once (CRM did that before). Old pages stay at `?full=1`.
class AskodoxShopChooserStepsScreen extends ConsumerStatefulWidget {
  const AskodoxShopChooserStepsScreen({
    super.key,
    required this.titleEn,
    required this.titleTe,
    required this.openRoute,
    required this.fullRoute,
    this.jumpIfOne = false,
  });

  final String titleEn;
  final String titleTe;

  /// Where a shop row goes: `/pos/<id>` or `/pos/<id>/crm`.
  final String Function(String businessId) openRoute;
  final String fullRoute;
  final bool jumpIfOne;

  @override
  ConsumerState<AskodoxShopChooserStepsScreen> createState() => _ShopChooserStepsState();
}

class _ShopChooserStepsState extends ConsumerState<AskodoxShopChooserStepsScreen> {
  List<AskodoxJson>? _shops;
  Object? _error;
  bool _jumped = false;

  bool get _te => askodoxPosTe(context);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final shops = await ref.read(askodoxPosRepositoryProvider).businesses();
      if (!mounted) return;
      setState(() {
        _shops = shops;
        _error = null;
      });
      if (widget.jumpIfOne && shops.length == 1 && !_jumped) {
        _jumped = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) context.replace(widget.openRoute('${shops.first['id']}'));
        });
      }
    } catch (e) {
      if (mounted && _shops == null) setState(() => _error = e);
    }
  }

  Future<void> _addShop() async {
    final te = _te;
    final created = await Navigator.of(context).push<String>(MaterialPageRoute<String>(
      builder: (page) => Scaffold(
        appBar: AppBar(title: Text(te ? 'కొత్త షాపు' : 'New shop')),
        body: AskodoxPosSetupForm(onCreated: (id) => Navigator.of(page).pop(id)),
      ),
    ));
    if (!mounted) return;
    await _load();
    if (created != null && created.isNotEmpty && mounted) unawaited(context.push(widget.openRoute(created)));
  }

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final title = te ? widget.titleTe : widget.titleEn;
    final more = [
      AskodoxStepMore('askodoxShopChooserStepsFull', te ? 'పాత పేజీ' : 'Old page', Icons.menu_book_rounded,
          () => context.push(widget.fullRoute)),
    ];
    if (_error != null) return AskodoxStepScaffold(title: title, more: more, body: AskodoxPosError(error: _error!, onRetry: _load));
    final shops = _shops;
    if (shops == null) return AskodoxStepScaffold(title: title, more: more, body: const Center(child: CircularProgressIndicator()));
    return AskodoxStepScaffold(
      key: const Key('askodoxShopChooserSteps'),
      title: title,
      question: shops.isEmpty ? (te ? 'మీ షాపు ఇంకా లేదు' : 'No shop yet') : (te ? 'ఏ షాపు?' : 'Which shop?'),
      hint: shops.isEmpty
          ? (te ? 'కింద బటన్ నొక్కి పేరు, రాష్ట్రం ఇవ్వండి' : 'Tap the button below and give the name and state')
          : null,
      more: more,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
          for (final s in shops)
            AskodoxStepPersonRow(
              key: ValueKey('askodoxShopChooserStepsShop-${s['id']}'),
              name: '${s['name'] ?? ''}',
              sub: '${s['my_role'] ?? s['role'] ?? ''}',
              amount: '›',
              amountColor: askodoxStepGreen,
              onTap: () => context.push(widget.openRoute('${s['id']}')),
            ),
        ]),
      ),
      bottom: AskodoxStepBottom(
        buttonKey: const Key('askodoxShopChooserStepsAdd'),
        label: shops.isEmpty ? (te ? 'నా షాపు చేర్చు' : 'Add my shop') : (te ? 'ఇంకో షాపు చేర్చు' : 'Add another shop'),
        icon: Icons.add_business_outlined,
        outline: shops.isNotEmpty,
        onPressed: _addShop,
      ),
    );
  }
}
