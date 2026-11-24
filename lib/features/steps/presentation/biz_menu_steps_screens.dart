import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../business/presentation/biz_menu.dart' show askodoxBizMenuProvider, askodoxMenuSections, askodoxSectionOf;
import '../../pos/data/pos_repository.dart';
import '../../pos/domain/pos_money.dart' show askodoxPaise;
import '../../pos/presentation/pos_common.dart';
import 'step_kit.dart';

String _sectionLabel(String s, bool te) => s.isEmpty ? (te ? 'విభాగం లేనివి' : 'No section') : s;

/// Owner 2026-11-24 (3-step design, batch 18): the menu by sections `/biz/:id/menu`. Top = how many items, middle = ONE
/// list of sections (tap = open it), bottom = ONE big button (add items). Search finds an item in every section. Sort with
/// AI, menu photos and the old page are in the menu ⋮.
class AskodoxBizMenuStepsScreen extends ConsumerStatefulWidget {
  const AskodoxBizMenuStepsScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxBizMenuStepsScreen> createState() => _BizMenuState();
}

class _BizMenuState extends ConsumerState<AskodoxBizMenuStepsScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final id = widget.businessId;
    final title = te ? 'మెనూ' : 'Menu';
    final menu = ref.watch(askodoxBizMenuProvider(id));
    final more = [
      AskodoxStepMore('askodoxBizMenuStepsSort', te ? 'AI తో సర్దు' : 'Sort with AI', Icons.auto_awesome, () => context.push('/biz/$id/menu/sort')),
      AskodoxStepMore('askodoxBizMenuStepsPhoto', te ? 'మెనూ ఫోటో' : 'Menu photo', Icons.photo_camera_outlined, () => context.push('/desk/$id/menu?full=1')),
      AskodoxStepMore('askodoxBizMenuStepsFull', te ? 'పాత పేజీ' : 'Old page', Icons.menu_book_rounded, () => context.push('/biz/$id/menu?full=1')),
    ];
    if (menu.hasError && !menu.hasValue) {
      return AskodoxStepScaffold(
          title: title, more: more, body: AskodoxPosError(error: menu.error!, onRetry: () => ref.invalidate(askodoxBizMenuProvider(id))));
    }
    final items = menu.valueOrNull;
    if (items == null) return AskodoxStepScaffold(title: title, more: more, body: const Center(child: CircularProgressIndicator()));
    final q = _search.text.trim().toLowerCase();
    final found = q.isEmpty
        ? const <AskodoxJson>[]
        : items.where((it) => '${it['name']}'.toLowerCase().contains(q) || '${it['item_no'] ?? ''}' == q).take(30).toList();
    final sections = askodoxMenuSections(items);
    return AskodoxStepScaffold(
      key: const Key('askodoxBizMenuSteps'),
      title: title,
      more: more,
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: AskodoxStepBigNumber('${items.length}', label: te ? 'ఐటమ్స్ · ${sections.length} విభాగాలు' : 'items · ${sections.length} sections'),
        ),
        if (items.length > 6)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: AskodoxStepSearch(
              controller: _search,
              fieldKey: const Key('askodoxBizMenuStepsSearch'),
              hint: te ? 'ఐటమ్ పేరు / నంబర్' : 'Item name / number',
              onChanged: (_) => setState(() {}),
            ),
          ),
        Expanded(
          child: items.isEmpty
              ? Center(child: Text(te ? 'ఇంకా ఐటమ్స్ లేవు. కింద బటన్ నొక్కండి.' : 'No items yet. Tap the button below.'))
              : ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
                  if (q.isNotEmpty) ...[
                    if (found.isEmpty) Padding(padding: const EdgeInsets.all(12), child: Text(te ? 'ఏమీ దొరకలేదు.' : 'Nothing found.')),
                    for (final it in found)
                      AskodoxStepPersonRow(
                        key: Key('askodoxBizMenuStepsFound-${it['id']}'),
                        name: '${it['name']}',
                        sub: _sectionLabel(askodoxSectionOf(it), te),
                        amount: askodoxPaise(askodoxPosInt(it['price_paise'])),
                        onTap: () => context.push('/biz/$id/menu/item/${it['id']}'),
                      ),
                  ] else
                    for (final s in sections)
                      AskodoxStepPersonRow(
                        key: Key('askodoxBizMenuStepsSection-$s'),
                        name: _sectionLabel(s, te),
                        sub: () {
                          final n = items.where((it) => askodoxSectionOf(it) == s && it['available'] != true).length;
                          return n > 0 ? (te ? '$n ఈ రోజు లేవు' : '$n out today') : '';
                        }(),
                        amount: '${items.where((it) => askodoxSectionOf(it) == s).length}',
                        onTap: () => context.push('/biz/$id/menu/section/${Uri.encodeComponent(s.isEmpty ? '-' : s)}'),
                      ),
                ]),
        ),
      ]),
      bottom: AskodoxStepBottom(
        buttonKey: const Key('askodoxBizMenuStepsAdd'),
        label: te ? 'ఐటమ్స్ చేర్చు' : 'Add items',
        icon: Icons.add_rounded,
        onPressed: () => context.push('/desk/$id/menu'),
      ),
    );
  }
}

/// One section of the menu `/biz/:id/menu/section/:name`: how many items, ONE list (tap = that item's page), bottom = add.
class AskodoxBizSectionStepsScreen extends ConsumerStatefulWidget {
  const AskodoxBizSectionStepsScreen({super.key, required this.businessId, required this.section});
  final String businessId;

  /// '-' = items without a section.
  final String section;

  @override
  ConsumerState<AskodoxBizSectionStepsScreen> createState() => _BizSectionState();
}

class _BizSectionState extends ConsumerState<AskodoxBizSectionStepsScreen> {
  bool _onlyOut = false;

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final id = widget.businessId;
    final section = widget.section == '-' ? '' : widget.section;
    final title = _sectionLabel(section, te);
    final menu = ref.watch(askodoxBizMenuProvider(id));
    final more = [
      AskodoxStepMore('askodoxBizSectionStepsOut', _onlyOut ? (te ? 'అన్నీ చూపు' : 'Show all') : (te ? 'ఈ రోజు లేనివే చూపు' : 'Show only out today'), Icons.filter_alt_outlined,
          () => setState(() => _onlyOut = !_onlyOut)),
      AskodoxStepMore('askodoxBizSectionStepsSort', te ? 'AI తో సర్దు' : 'Sort with AI', Icons.auto_awesome, () => context.push('/biz/$id/menu/sort')),
      AskodoxStepMore('askodoxBizSectionStepsFull', te ? 'పాత పేజీ' : 'Old page',
          Icons.menu_book_rounded, () => context.push('/biz/$id/menu/section/${Uri.encodeComponent(widget.section)}?full=1')),
    ];
    if (menu.hasError && !menu.hasValue) {
      return AskodoxStepScaffold(
          title: title, more: more, body: AskodoxPosError(error: menu.error!, onRetry: () => ref.invalidate(askodoxBizMenuProvider(id))));
    }
    final items = menu.valueOrNull;
    if (items == null) return AskodoxStepScaffold(title: title, more: more, body: const Center(child: CircularProgressIndicator()));
    final all = [for (final it in items) if (askodoxSectionOf(it) == section) it];
    final shown = [for (final it in all) if (!_onlyOut || it['available'] != true) it];
    final out = all.where((it) => it['available'] != true).length;
    return AskodoxStepScaffold(
      key: const Key('askodoxBizSectionSteps'),
      title: title,
      onBack: () => context.pop(),
      more: more,
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: AskodoxStepBigNumber('${all.length}', label: out > 0 ? (te ? 'ఐటమ్స్ · $out ఈ రోజు లేవు' : 'items · $out out today') : (te ? 'ఐటమ్స్' : 'items')),
        ),
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
            for (final it in shown)
              AskodoxStepPersonRow(
                key: Key('askodoxBizSectionStepsItem-${it['id']}'),
                name: '${it['name']}',
                sub: [
                  if (askodoxPosInt(it['item_no']) > 0) '#${it['item_no']}',
                  if (it['available'] != true) te ? 'ఈ రోజు లేదు' : 'Out today',
                ].join(' · '),
                amount: askodoxPaise(askodoxPosInt(it['price_paise'])),
                amountColor: it['available'] == true ? askodoxStepInk : askodoxStepMuted,
                onTap: () => context.push('/biz/$id/menu/item/${it['id']}'),
              ),
          ]),
        ),
      ]),
      bottom: AskodoxStepBottom(
        buttonKey: const Key('askodoxBizSectionStepsAdd'),
        label: te ? 'ఇక్కడ చేర్చు' : 'Add here',
        icon: Icons.add_rounded,
        onPressed: () => context.push('/desk/$id/menu'),
      ),
    );
  }
}
