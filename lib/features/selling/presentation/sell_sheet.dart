import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/providers/backend_providers.dart';
import '../../../shared/smart_guide/smart_guide_bar.dart';
import '../../../shared/smart_guide/smart_guide_corrections.dart';
import '../../../shared/widgets/askodox_guided_field.dart';
import '../../../shared/widgets/askodox_mascot.dart';
import '../../growth/data/growth_repository.dart';

/// "Sell something" without leaving the screen: describe -> a DRAFT (never a
/// listing) -> review every field with the Smart Guide -> Publish only after
/// an explicit "Yes, publish". Returns the new listing id, or null.
Future<int?> showAskodoxSellSheet(BuildContext context) => showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => const AskodoxSellSheet(),
    );

/// Stock as typed ("12", "0", empty) -> the stock status the listing stores.
String askodoxStockStatus(String typed) {
  final n = int.tryParse(typed.trim());
  if (n == null) return 'UNKNOWN';
  return n > 0 ? 'IN_STOCK' : 'OUT_OF_STOCK';
}

class AskodoxSellSheet extends ConsumerStatefulWidget {
  const AskodoxSellSheet({super.key});

  @override
  ConsumerState<AskodoxSellSheet> createState() => _AskodoxSellSheetState();
}

class _AskodoxSellSheetState extends ConsumerState<AskodoxSellSheet> {
  final _describe = TextEditingController();
  late final Map<String, TextEditingController> _fields = {
    for (final id in [
      AskodoxGuideFieldId.name,
      AskodoxGuideFieldId.price,
      AskodoxGuideFieldId.unit,
      AskodoxGuideFieldId.stock,
      AskodoxGuideFieldId.variant,
      AskodoxGuideFieldId.category,
    ])
      id: TextEditingController(),
  };
  AskodoxCatalogDraft? _draft;
  bool _busy = false;
  String? _error;

  bool get _te => Localizations.maybeLocaleOf(context)?.languageCode == 'te';
  String _t(String en, String te) => _te ? te : en;

  @override
  void dispose() {
    _describe.dispose();
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _makeDraft() async {
    final text = _describe.text.trim();
    if (text.length < 3) {
      setState(() => _error = _t('Say what you sell first.', 'ముందు ఏమి అమ్ముతారో చెప్పండి.'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final draft = await ref.read(growthRepositoryProvider).draftListing(text: text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (draft == null) {
        _error = ref.read(authSessionProvider).user == null
            ? _t('Sign in to sell.', 'అమ్మడానికి సైన్ ఇన్ చేయండి.')
            : _t('Could not make a draft. Add a little more and try again.',
                'డ్రాఫ్ట్ కాలేదు. ఇంకొంచెం రాసి మళ్లీ ప్రయత్నించండి.');
        return;
      }
      _draft = draft;
      // Only what the seller's own words gave; everything else stays empty.
      final d = draft.draft;
      String text(Object? v) => v == null ? '' : '$v'.trim();
      final price = d['price'] is num ? (d['price'] as num) : null;
      _fields[AskodoxGuideFieldId.name]!.text = draft.title;
      _fields[AskodoxGuideFieldId.price]!.text = price == null
          ? ''
          : (price == price.roundToDouble() ? price.toInt().toString() : price.toString());
      _fields[AskodoxGuideFieldId.unit]!.text = text(d['unit']);
      _fields[AskodoxGuideFieldId.category]!.text = text(d['category_tag']);
    });
  }

  Future<void> _publish() async {
    final draft = _draft;
    if (draft == null) return;
    final price = double.tryParse(_fields[AskodoxGuideFieldId.price]!.text.replaceAll(RegExp(r'[₹,\s]'), ''));
    if (_fields[AskodoxGuideFieldId.name]!.text.trim().isEmpty || price == null || price <= 0) {
      setState(() => _error = _t('Add the name and the price before publishing.', 'ప్రచురించే ముందు పేరు, ధర ఇవ్వండి.'));
      return;
    }
    final stock = askodoxStockStatus(_fields[AskodoxGuideFieldId.stock]!.text);
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        key: const Key('askodoxSellConfirm'),
        title: Text(_t('Publish this listing?', 'ఈ లిస్టింగ్ ప్రచురించాలా?')),
        content: Text(
            '${_fields[AskodoxGuideFieldId.name]!.text.trim()} · ₹${_fields[AskodoxGuideFieldId.price]!.text.trim()}\n'
            '${_t('Buyers will be able to find it.', 'కొనుగోలుదారులకు ఇది కనిపిస్తుంది.')}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: Text(_t('Not yet', 'ఇంకా వద్దు'))),
          FilledButton(
              key: const Key('askodoxSellConfirmYes'),
              onPressed: () => Navigator.pop(dialog, true),
              child: Text(_t('Yes, publish', 'అవును, ప్రచురించు'))),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    String? value(String id) {
      final v = _fields[id]!.text.trim();
      return v.isEmpty ? null : v;
    }

    final listingId = await ref.read(growthRepositoryProvider).publishDraft(draft.id, {
      'subject': value(AskodoxGuideFieldId.name),
      'price': price,
      if (value(AskodoxGuideFieldId.unit) != null) 'unit': value(AskodoxGuideFieldId.unit),
      'stock_status': stock,
      if (value(AskodoxGuideFieldId.variant) != null) 'variant': value(AskodoxGuideFieldId.variant),
      if (value(AskodoxGuideFieldId.category) != null) 'category_tag': value(AskodoxGuideFieldId.category),
    });
    if (!mounted) return;
    if (listingId == null) {
      setState(() {
        _busy = false;
        _error = _t('Could not publish now. Your draft is kept -- try again.',
            'ఇప్పుడు ప్రచురించలేకపోయాను. డ్రాఫ్ట్ అలాగే ఉంది -- మళ్లీ ప్రయత్నించండి.');
      });
      return;
    }
    Navigator.pop(context, listingId);
  }

  Future<void> _discard() async {
    final draft = _draft;
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        content: Text(_t('Discard this draft?', 'ఈ డ్రాఫ్ట్ తీసేయాలా?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: Text(_t('Keep', 'ఉంచు'))),
          FilledButton(
              key: const Key('askodoxSellDiscardYes'),
              onPressed: () => Navigator.pop(dialog, true),
              child: Text(_t('Discard', 'తీసేయి'))),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    if (draft != null) {
      final session = ref.read(authSessionProvider);
      await ref.read(apiClientProvider).post<Map<String, Object?>>('/api/catalog/drafts/${draft.id}/discard',
          options: ApiRequestOptions(authToken: session.tokenPlaceholder));
    }
    if (mounted) Navigator.pop(context);
  }

  Widget _field(String id, String label, AskodoxFieldGuide guide, {TextInputType? keyboard}) => AskodoxGuidedField(
        fieldKey: ValueKey('askodoxSell-$id'),
        controller: _fields[id]!,
        label: label,
        guide: guide,
        keyboardType: keyboard,
      );

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    return Padding(
      key: const Key('askodoxSellSheet'),
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 16),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const AskodoxMascot(role: AskodoxMascotRole.listo, size: 40),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                  draft == null
                      ? _t('What do you want to sell?', 'ఏమి అమ్మాలనుకుంటున్నారు?')
                      : _t('Check and correct -- nothing is live yet', 'చూసి సరిచేయండి -- ఇంకా ఏదీ ప్రచురించలేదు'),
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            ),
          ]),
          if (draft == null) ...[
            AskodoxGuidedField(
              fieldKey: const Key('askodoxSellDescribe'),
              controller: _describe,
              label: _t('Describe it', 'దాని గురించి చెప్పండి'),
              guide: AskodoxFieldGuides.description,
              maxLines: 3,
              minLines: 2,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('askodoxSellMakeDraft'),
              onPressed: _busy ? null : _makeDraft,
              icon: _busy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.auto_awesome_rounded),
              label: Text(_t('Make a draft', 'డ్రాఫ్ట్ తయారు చేయి')),
            ),
          ] else ...[
            _field(AskodoxGuideFieldId.name, _t('Name', 'పేరు'), AskodoxFieldGuides.shopName),
            _field(AskodoxGuideFieldId.price, _t('Price (₹)', 'ధర (₹)'), AskodoxFieldGuides.price,
                keyboard: TextInputType.number),
            _field(AskodoxGuideFieldId.unit, _t('Price is for', 'ధర దేనికి'), AskodoxFieldGuides.unit),
            _field(AskodoxGuideFieldId.stock, _t('Stock', 'స్టాక్'), AskodoxFieldGuides.stock,
                keyboard: TextInputType.number),
            _field(AskodoxGuideFieldId.variant, _t('Sizes / colours', 'సైజులు / రంగులు'), AskodoxFieldGuides.variant),
            _field(AskodoxGuideFieldId.category, _t('Category', 'విభాగం'), AskodoxFieldGuides.category),
            AskodoxSmartGuideBar(targets: {
              AskodoxGuideFieldId.name: AskodoxGuideTarget(_t('Name', 'పేరు'), _fields[AskodoxGuideFieldId.name]!),
              AskodoxGuideFieldId.price: AskodoxGuideTarget(_t('Price', 'ధర'), _fields[AskodoxGuideFieldId.price]!),
              AskodoxGuideFieldId.unit: AskodoxGuideTarget(_t('Unit', 'యూనిట్'), _fields[AskodoxGuideFieldId.unit]!),
              AskodoxGuideFieldId.stock: AskodoxGuideTarget(_t('Stock', 'స్టాక్'), _fields[AskodoxGuideFieldId.stock]!),
              AskodoxGuideFieldId.variant:
                  AskodoxGuideTarget(_t('Sizes', 'సైజులు'), _fields[AskodoxGuideFieldId.variant]!),
              AskodoxGuideFieldId.category:
                  AskodoxGuideTarget(_t('Category', 'విభాగం'), _fields[AskodoxGuideFieldId.category]!),
            }),
            const SizedBox(height: 12),
            Row(children: [
              TextButton(
                key: const Key('askodoxSellDiscard'),
                onPressed: _busy ? null : _discard,
                child: Text(_t('Discard', 'తీసేయి')),
              ),
              const Spacer(),
              FilledButton.icon(
                key: const Key('askodoxSellPublish'),
                onPressed: _busy ? null : _publish,
                icon: const Icon(Icons.publish_rounded),
                label: Text(_t('Publish…', 'ప్రచురించు…')),
              ),
            ]),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, key: const Key('askodoxSellError'), style: const TextStyle(color: Color(0xFFB42318))),
            ),
        ]),
      ),
    );
  }
}
