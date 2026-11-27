import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/theme/askodox_look.dart';
import '../../services/media_picker.dart';
import '../memberships/memberships_logic.dart' show askodoxTermEnd;
import '../native_video/video_commerce.dart' show askodoxShareTextProvider;
import '../pos/data/pos_repository.dart';
import 'vault_logic.dart';
import 'vault_store.dart';

/// On only in `main()`: the "warranty ending" chip above the Home chat.
bool askodoxVaultChip = false;

/// Above the Home chat, only when a warranty the person asked to be reminded of ends within 30 days.
class AskodoxVaultChipStrip extends ConsumerWidget {
  const AskodoxVaultChipStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!askodoxVaultChip) return const SizedBox.shrink();
    final today = ref.watch(askodoxVaultClockProvider)();
    final ending = askodoxVaultEnding(ref.watch(askodoxVaultProvider).papers, today);
    if (ending.isEmpty) return const SizedBox.shrink();
    final te = Localizations.localeOf(context).languageCode == 'te';
    final first = ending.first;
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: ActionChip(
          key: const Key('askodoxVaultChip'),
          avatar: const Icon(Icons.verified_user_outlined, size: 16, color: AskodoxLook.accentText),
          label: Text('${first.item} · ${askodoxVaultStateText(first, today, te)}',
              overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
          onPressed: () => context.push('/me/vault'),
        ),
      ),
    );
  }
}

/// Bills & warranty (design canvas "bills & warranty" + "bill + warranty details"): a photo of the paper -> its facts
/// read for the person to check -> kept on this phone; the list finds it again and says which warranty is ending.
class AskodoxVaultScreen extends ConsumerStatefulWidget {
  const AskodoxVaultScreen({super.key});

  @override
  ConsumerState<AskodoxVaultScreen> createState() => _AskodoxVaultScreenState();
}

class _AskodoxVaultScreenState extends ConsumerState<AskodoxVaultScreen> {
  final _search = TextEditingController();
  final _item = TextEditingController();
  final _shop = TextEditingController();
  final _serial = TextEditingController();
  final _service = TextEditingController();
  String _filter = 'all';
  bool _editing = false;
  bool _reading = false;
  String _id = '';
  String _bought = '';
  String _until = '';
  String _note = '';
  bool _remind = true;
  Uint8List? _photo;
  String _photoName = '';
  int _amount = 0;

  @override
  void dispose() {
    for (final c in [_search, _item, _shop, _serial, _service]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _te => Localizations.localeOf(context).languageCode == 'te';
  DateTime get _today => ref.read(askodoxVaultClockProvider)();

  void _open(AskodoxVaultPaper? p) {
    _item.text = p?.item ?? '';
    _shop.text = p?.shop ?? '';
    _serial.text = p?.serial ?? '';
    _service.text = p?.servicePhone ?? '';
    setState(() {
      _id = p?.id ?? '';
      _bought = p?.boughtOn ?? '';
      _until = p?.warrantyUntil ?? '';
      _remind = p?.remind ?? true;
      _photoName = p?.photo ?? '';
      _amount = p?.amountPaise ?? 0;
      _photo = null;
      _note = '';
      _editing = true;
    });
  }

  Future<void> _fromPhoto(String source) async {
    final te = _te;
    final picked = (await ref.read(askodoxMediaPickerProvider).pick(source)).where((a) => a.isImage).toList();
    if (picked.isEmpty || !mounted) return;
    final photo = picked.first;
    if (photo.bytes.length > 4400000) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(te ? 'ఫోటో చాలా పెద్దది. చిన్న ఫోటో వాడండి.' : 'That photo is too large. Use a smaller one.')));
      return;
    }
    _open(null);
    setState(() {
      _photo = photo.bytes;
      _reading = true;
    });
    var note = te ? 'AI చదివింది. తేదీలు, వివరాలు ఒకసారి సరిచూడండి.' : 'Read by AI. Check the dates and details once.';
    try {
      final out = await ref.read(askodoxPosRepositoryProvider).vaultRead([
        {'data': base64Encode(photo.bytes), 'mime': photo.mimeType},
      ]);
      if (!mounted) return;
      if (out['read'] == true) {
        _item.text = '${out['item'] ?? ''}';
        _shop.text = '${out['shop'] ?? ''}';
        _serial.text = '${out['serial'] ?? ''}';
        _service.text = '${out['service_phone'] ?? ''}';
        _bought = askodoxVaultDay('${out['bought_on'] ?? ''}');
        _until = askodoxVaultDay('${out['warranty_until'] ?? ''}');
        _amount = out['amount_paise'] is num ? (out['amount_paise'] as num).toInt() : 0;
      } else {
        note = te ? 'ఫోటో సేవ్ అవుతుంది. వివరాలు మీరే రాయండి, లేదా మరో స్పష్టమైన ఫోటో తీయండి.' : 'The photo is kept. Type the details, or take a clearer photo.';
      }
    } on AskodoxPosException catch (e) {
      note = e.code == 'AI_CREDITS_LOW' || e.detail == 'AI_CREDITS_LOW'
          ? (te ? 'AI Credits అయిపోయాయి. ఫోటో సేవ్ అవుతుంది, వివరాలు మీరే రాయండి.' : 'AI Credits are used up. The photo is kept; type the details.')
          : (te ? 'ఫోటో సేవ్ అవుతుంది. వివరాలు మీరే రాయండి.' : 'The photo is kept. Type the details yourself.');
    } catch (_) {
      note = te ? 'ఫోటో సేవ్ అవుతుంది. వివరాలు మీరే రాయండి.' : 'The photo is kept. Type the details yourself.';
    }
    if (mounted) {
      setState(() {
        _reading = false;
        _note = note;
      });
    }
  }

  Future<void> _pickDay(bool bought) async {
    final now = _today;
    final start = askodoxVaultDay(bought ? _bought : _until);
    final picked = await showDatePicker(
      context: context,
      initialDate: start.isEmpty ? now : DateTime.parse(start),
      firstDate: DateTime(now.year - 30),
      lastDate: DateTime(now.year + 30),
    );
    if (picked != null && mounted) setState(() => bought ? _bought = askodoxVaultIso(picked) : _until = askodoxVaultIso(picked));
  }

  void _addMonths(int months) {
    final from = askodoxVaultDay(_bought).isEmpty ? _today : DateTime.parse(_bought);
    setState(() => _until = askodoxVaultIso(askodoxTermEnd(DateTime(from.year, from.month, from.day), months)));
  }

  Future<void> _save() async {
    final name = _item.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (name.isEmpty) return;
    final now = _today;
    await ref.read(askodoxVaultProvider.notifier).save(
        AskodoxVaultPaper(
            id: _id.isEmpty ? 'paper_${now.microsecondsSinceEpoch}' : _id,
            item: name,
            shop: _shop.text.trim(),
            boughtOn: _bought,
            warrantyUntil: _until,
            serial: _serial.text.trim(),
            servicePhone: _service.text.trim(),
            amountPaise: _amount,
            photo: _photoName,
            remind: _remind,
            addedAt: now.toIso8601String()),
        photo: _photo);
    if (mounted) setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final state = ref.watch(askodoxVaultProvider);
    return PopScope(
      canPop: !_editing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _editing = false);
      },
      child: Scaffold(
        key: const Key('askodoxVault'),
        appBar: AppBar(title: Text(_editing ? (te ? 'బిల్ + వారంటీ వివరాలు' : 'Bill + warranty details') : (te ? 'బిల్స్ & వారంటీ' : 'Bills & warranty'))),
        body: SafeArea(
          child: !state.loaded
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: _editing ? _fields(te) : _list(te, state.papers),
                ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------------------------------------ list
  List<Widget> _list(bool te, List<AskodoxVaultPaper> papers) {
    final today = _today;
    final shown = askodoxVaultShow(papers, today, query: _search.text, filter: _filter);
    const filters = [('all', 'All', 'అన్నీ'), ('warranty', 'With warranty', 'వారంటీ ఉన్నవి'), ('ending', 'Ending', 'ముగుస్తున్నవి')];
    return [
      TextField(
        key: const Key('askodoxVaultSearch'),
        controller: _search,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search_rounded), hintText: te ? 'వస్తువు పేరు లేదా షాప్ వెతకండి' : 'Search an item or a shop'),
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 8, children: [
        for (final f in filters)
          ChoiceChip(
            key: ValueKey('askodoxVaultFilter-${f.$1}'),
            label: Text(te ? f.$3 : f.$2),
            selected: _filter == f.$1,
            onSelected: (_) => setState(() => _filter = f.$1),
          ),
      ]),
      const SizedBox(height: 8),
      if (papers.isEmpty)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
                te
                    ? 'బిల్ లేదా వారంటీ కార్డ్ ఫోటో తీయండి. ఎప్పుడు కొన్నారు, వారంటీ ఎప్పటి వరకు, సీరియల్ నంబర్ ఇక్కడే దొరుకుతాయి.'
                    : 'Take a photo of a bill or a warranty card. When you bought it, how long the warranty runs and the serial '
                        'number will be found here.',
                key: const Key('askodoxVaultEmpty')),
          ),
        ),
      for (final p in shown)
        Card(
          key: ValueKey('askodoxVaultPaper-${p.id}'),
          child: ListTile(
            onTap: () => _details(p, te),
            leading: Icon(p.photo.isEmpty ? Icons.receipt_long_outlined : Icons.image_outlined, color: AskodoxLook.accentText),
            title: Text(p.item, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text([
              if (p.shop.isNotEmpty) p.shop,
              if (p.boughtOn.isNotEmpty) askodoxVaultShown(p.boughtOn),
            ].join(' · ')),
            trailing: Text(askodoxVaultStateText(p, today, te),
                key: ValueKey('askodoxVaultState-${p.id}'),
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: switch (askodoxVaultState(p, today)) {
                      'ending' => AskodoxLook.accentText,
                      'on' => AskodoxLook.good,
                      _ => AskodoxLook.muted,
                    })),
          ),
        ),
      const SizedBox(height: 12),
      FilledButton.icon(
        key: const Key('askodoxVaultCamera'),
        onPressed: () => _fromPhoto('camera'),
        icon: const Icon(Icons.photo_camera_outlined),
        label: Text(te ? 'బిల్ / వారంటీ కార్డ్ ఫోటో తీయండి' : 'Photo of a bill / warranty card'),
      ),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: OutlinedButton(
              key: const Key('askodoxVaultGallery'),
              onPressed: () => _fromPhoto('gallery'),
              child: Text(te ? 'గ్యాలరీ నుంచి' : 'From the gallery')),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton(
              key: const Key('askodoxVaultType'), onPressed: () => _open(null), child: Text(te ? 'నేనే రాస్తా' : 'I will type it')),
        ),
      ]),
      const SizedBox(height: 16),
      Text(
          te
              ? 'మీ బిల్స్, ఫోటోలు ఈ ఫోన్‌లో మీ ఖాతాలో మాత్రమే ఉంటాయి. ఫోటో చదవడానికి మాత్రమే AI కి వెళ్తుంది; అక్కడ సేవ్ అవ్వదు.'
              : 'Your bills and photos stay on this phone, in your account only. A photo goes to AI only to be read; it is not kept there.',
          key: const Key('askodoxVaultPrivacy'),
          style: const TextStyle(fontSize: 12.5, color: AskodoxLook.muted)),
    ];
  }

  // ------------------------------------------------------------------------------------------------ fields
  Widget _box(String keyName, TextEditingController c, String label, {TextInputType? keyboard}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(key: Key(keyName), controller: c, keyboardType: keyboard, decoration: InputDecoration(labelText: label)),
      );

  Widget _day(String keyName, String label, String iso, VoidCallback onTap) => ListTile(
        key: Key(keyName),
        contentPadding: EdgeInsets.zero,
        onTap: onTap,
        leading: const Icon(Icons.event_outlined),
        title: Text(label),
        trailing: Text(iso.isEmpty ? '—' : askodoxVaultShown(iso),
            key: Key('${keyName}Value'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, fontFeatures: AskodoxLook.figures)),
      );

  List<Widget> _fields(bool te) => [
        if (_reading) const LinearProgressIndicator(),
        if (_photo != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(_photo!, height: 140, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox(height: 8))),
          ),
        // A fixed place for the note (an empty line until there is one): the boxes under it never move.
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(_note, key: const Key('askodoxVaultNote'), style: const TextStyle(color: AskodoxLook.accentText)),
        ),
        _box('askodoxVaultItem', _item, te ? 'వస్తువు' : 'Item'),
        _box('askodoxVaultShop', _shop, te ? 'షాప్' : 'Shop'),
        _day('askodoxVaultBought', te ? 'కొన్న తేదీ' : 'Bought on', _bought, () => _pickDay(true)),
        _day('askodoxVaultUntil', te ? 'వారంటీ ముగింపు (సరిచూడండి)' : 'Warranty till (check it)', _until, () => _pickDay(false)),
        Wrap(spacing: 8, children: [
          for (final m in const [6, 12, 24, 36])
            ActionChip(
              key: ValueKey('askodoxVaultMonths-$m'),
              label: Text(m < 12 ? (te ? '$m నెలలు' : '$m months') : (te ? '${m ~/ 12} సం.' : '${m ~/ 12} yr')),
              onPressed: () => _addMonths(m),
            ),
        ]),
        const SizedBox(height: 10),
        _box('askodoxVaultSerial', _serial, te ? 'సీరియల్ నంబర్' : 'Serial number'),
        _box('askodoxVaultService', _service, te ? 'సర్వీస్ నంబర్' : 'Service number', keyboard: TextInputType.phone),
        SwitchListTile(
          key: const Key('askodoxVaultRemind'),
          contentPadding: EdgeInsets.zero,
          value: _remind,
          onChanged: (v) => setState(() => _remind = v),
          title: Text(te ? 'ముగియడానికి 30 రోజుల ముందు గుర్తు చేయి' : 'Remind me 30 days before it ends'),
        ),
        const SizedBox(height: 8),
        FilledButton(key: const Key('askodoxVaultSave'), onPressed: _reading ? null : _save, child: Text(te ? 'సేవ్ చేయి' : 'Save')),
        const SizedBox(height: 12),
        Text(
            te
                ? 'గమనిక: తేదీలు బిల్ / కార్డ్ నుంచి చదివినవి, తప్పులు ఉండొచ్చు. వారంటీ నిబంధనలు తయారీదారు కార్డ్‌లో ఉన్నవే సరైనవి.'
                : 'Note: the dates are read from the bill / card and can be wrong. The maker’s own card decides the warranty.',
            style: const TextStyle(fontSize: 12.5, color: AskodoxLook.muted)),
      ];

  // ------------------------------------------------------------------------------------------------ one paper
  Future<void> _details(AskodoxVaultPaper p, bool te) async {
    final files = ref.read(askodoxVaultFilesProvider);
    Widget row(String label, String value) => value.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              Expanded(child: Text(label, style: const TextStyle(color: AskodoxLook.muted))),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
            ]),
          );
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(p.item, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            Text(askodoxVaultStateText(p, _today, te), style: const TextStyle(color: AskodoxLook.accentText)),
            if (p.photo.isNotEmpty)
              FutureBuilder<Uint8List?>(
                future: files.read(p.photo),
                builder: (_, snap) => snap.data == null
                    ? const SizedBox(height: 8)
                    : Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.memory(snap.data!, height: 220, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const SizedBox(height: 8))),
                      ),
              ),
            row(te ? 'షాప్' : 'Shop', p.shop),
            row(te ? 'కొన్న తేదీ' : 'Bought on', askodoxVaultShown(p.boughtOn)),
            row(te ? 'వారంటీ ముగింపు' : 'Warranty till', askodoxVaultShown(p.warrantyUntil)),
            row(te ? 'సీరియల్ నంబర్' : 'Serial number', p.serial),
            row(te ? 'సర్వీస్ నంబర్' : 'Service number', p.servicePhone),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('askodoxVaultShare'),
              onPressed: () => ref.read(askodoxShareTextProvider)(askodoxVaultServiceText(p, te), subject: p.item),
              icon: const Icon(Icons.share_rounded),
              label: Text(te ? 'సర్వీస్ కోసం షేర్' : 'Share for service'),
            ),
            Row(children: [
              Expanded(
                child: TextButton(
                  key: const Key('askodoxVaultEdit'),
                  onPressed: () {
                    Navigator.of(sheet).pop();
                    _open(p);
                  },
                  child: Text(te ? 'మార్చు' : 'Change'),
                ),
              ),
              Expanded(
                child: TextButton(
                  key: const Key('askodoxVaultRemove'),
                  onPressed: () {
                    Navigator.of(sheet).pop();
                    ref.read(askodoxVaultProvider.notifier).remove(p.id);
                  },
                  child: Text(te ? 'తీసేయి' : 'Remove'),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}
