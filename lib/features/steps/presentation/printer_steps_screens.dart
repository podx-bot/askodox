import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../devices/data/ble_gateway.dart';
import '../../pos/data/pos_printer.dart';
import '../../pos/domain/escpos.dart';
import '../../pos/presentation/pos_common.dart';
import 'step_kit.dart';

/// Owner 2026-11-24 (3-step design, batch 17): the bill printer `/pos/:id/printer`. Top = the printer in use (or none),
/// bottom = ONE big button (Test print, or Find a printer when none). Finding one is 3 steps: how it connects (Bluetooth
/// scan / paired / USB) -> pick it from the list -> done + test print. Paper size and the old page are in the menu ⋮.
class AskodoxPrinterStepsScreen extends ConsumerStatefulWidget {
  const AskodoxPrinterStepsScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxPrinterStepsScreen> createState() => _PrinterState();
}

class _PrinterState extends ConsumerState<AskodoxPrinterStepsScreen> {
  AskodoxSavedPrinter? _saved;
  bool _loaded = false;
  int _step = 0; // 0 = the printer, 1 = how it connects, 2 = pick, 3 = done
  List<_Found> _found = const [];
  bool _busy = false;
  int _paper = 58;
  String? _message;
  String? _testNote;

  bool get _te => askodoxPosTe(context);

  @override
  void initState() {
    super.initState();
    AskodoxSavedPrinter.load().then((p) {
      if (!mounted) return;
      setState(() {
        _saved = p;
        _paper = p?.paperMm ?? 58;
        _loaded = true;
      });
    });
  }

  String _linkName(String id) => switch (askodoxPrinterLink(id)) {
        'classic' => _te ? 'క్లాసిక్ బ్లూటూత్' : 'Classic Bluetooth',
        'usb' => 'USB',
        _ => 'Bluetooth LE',
      };

  Future<void> _scan() async {
    final te = _te;
    final ble = ref.read(askodoxBleGatewayProvider);
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (!await ble.isOn()) await ble.requestTurnOn();
      final rows = await ble.scan(const Duration(seconds: 8));
      if (!mounted) return;
      setState(() {
        _found = [for (final d in rows) _Found(d.id, d.name.isEmpty ? (te ? 'పేరు లేని పరికరం' : 'Unnamed device') : d.name, 'RSSI ${d.rssi}')];
        _step = 2;
        if (_found.isEmpty) _message = te ? 'ఏ ప్రింటర్ కనిపించలేదు. ప్రింటర్ ఆన్ చేసి దగ్గరగా ఉంచండి.' : 'No printer found. Switch it on and keep it close.';
      });
    } on AskodoxBleException catch (e) {
      if (mounted) {
        setState(() => _message = e.code == 'permission_denied'
            ? (te ? 'బ్లూటూత్ అనుమతి ఇవ్వలేదు.' : 'Bluetooth permission was not given.')
            : (te ? 'స్కాన్ విఫలమైంది.' : 'The scan failed.'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _listNative(bool usb) async {
    final te = _te;
    final native = ref.read(askodoxNativePrintersProvider);
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final rows = usb ? await native.usb() : await native.paired();
      if (!mounted) return;
      setState(() {
        _found = [
          for (final d in rows)
            _Found(d.id, d.name, d.hint ? (te ? 'ప్రింటర్‌లా కనిపిస్తోంది' : 'Looks like a printer') : d.id.split(':').skip(1).join(':'))
        ];
        _step = 2;
        if (rows.isEmpty) {
          _message = usb
              ? (te ? 'USB ప్రింటర్ కనిపించలేదు (OTG కేబుల్‌తో కనెక్ట్ చేయండి).' : 'No USB printer found (connect it with an OTG cable).')
              : (te ? 'జత చేసిన పరికరాలు లేవు. ఫోన్ బ్లూటూత్ సెట్టింగ్స్‌లో ప్రింటర్‌ని జత చేయండి.' : 'No paired devices. Pair the printer in the phone\'s Bluetooth settings.');
        }
      });
    } on AskodoxPrinterException catch (e) {
      if (mounted) setState(() => _message = e.message(te));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _choose(_Found d) async {
    final p = AskodoxSavedPrinter(id: d.id, name: d.name, paperMm: _paper);
    await p.save();
    if (!mounted) return;
    setState(() {
      _saved = p;
      _testNote = null;
      _step = 3;
    });
  }

  Future<void> _setPaper(int mm) async {
    setState(() => _paper = mm);
    final p = _saved;
    if (p != null) {
      final updated = AskodoxSavedPrinter(id: p.id, name: p.name, paperMm: mm);
      await updated.save();
      if (mounted) setState(() => _saved = updated);
    }
  }

  Future<void> _test() async {
    final te = _te;
    final p = _saved;
    if (p == null) return;
    final bytes = (AskodoxEscPos().init().align(1).bold(true).text('ASKODOX test print').bold(false).text('Paper ${p.paperMm} mm')
          ..text('-' * askodoxReceiptColumns(p.paperMm))
          ..feed(3)
          ..cut())
        .bytes();
    setState(() => _busy = true);
    try {
      await ref.read(askodoxPrinterTransportProvider).write(p.id, bytes);
      if (mounted) setState(() => _testNote = te ? 'పంపాం — పేపర్ మీద వచ్చిందా చూడండి.' : 'Sent — check that it printed.');
    } on AskodoxPrinterException catch (e) {
      if (mounted) setState(() => _testNote = e.message(te));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<AskodoxStepMore> _more() {
    final te = _te;
    return [
      AskodoxStepMore('askodoxPrinterStepsFind', te ? 'వేరే ప్రింటర్ వెతుకు' : 'Find another printer', Icons.bluetooth_searching,
          () => setState(() {
                _step = 1;
                _message = null;
              })),
      AskodoxStepMore(
          'askodoxPrinterStepsPaper',
          _paper == 58 ? (te ? 'పేపర్ 80 mm కి మార్చు' : 'Switch paper to 80 mm') : (te ? 'పేపర్ 58 mm కి మార్చు' : 'Switch paper to 58 mm'),
          Icons.straighten,
          () => unawaited(_setPaper(_paper == 58 ? 80 : 58))),
      AskodoxStepMore('askodoxPrinterStepsFull', te ? 'పాత పేజీ (వివరాలు)' : 'Old page (details)', Icons.menu_book_rounded,
          () => context.push('/pos/${widget.businessId}/printer?full=1')),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final title = te ? 'ప్రింటర్' : 'Printer';
    if (_step == 1) {
      return AskodoxStepScaffold(
        key: const Key('askodoxPrinterSteps1'),
        title: title,
        step: 1,
        total: 3,
        question: te ? 'ప్రింటర్ ఎలా కనెక్ట్ అయింది?' : 'How is the printer connected?',
        hint: te ? 'ESC/POS థర్మల్ ప్రింటర్లు. Wi-Fi ప్రింటర్లు ఇంకా లేవు.' : 'ESC/POS thermal printers. Wi-Fi printers are not supported yet.',
        onBack: () => setState(() => _step = 0),
        more: _more(),
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
          AskodoxStepToggle(
            options: const [('58', '58 mm'), ('80', '80 mm')],
            value: '$_paper',
            onChanged: (v) => setState(() => _paper = int.parse(v)),
          ),
          const SizedBox(height: 14),
          AskodoxStepChoice(
            key: const Key('askodoxPrinterStepsScan'),
            icon: Icons.bluetooth_searching,
            color: askodoxStepGreen,
            title: te ? 'బ్లూటూత్ (వెతుకు)' : 'Bluetooth (search)',
            sub: te ? 'కొత్త BLE ప్రింటర్' : 'A new BLE printer',
            onTap: _busy ? null : _scan,
          ),
          const SizedBox(height: 10),
          AskodoxStepChoice(
            key: const Key('askodoxPrinterStepsPaired'),
            icon: Icons.bluetooth_connected,
            color: askodoxStepGreen,
            title: te ? 'జత చేసినవి' : 'Paired',
            sub: te ? 'ఫోన్ సెట్టింగ్స్‌లో జత చేసిన ప్రింటర్' : 'Paired in the phone settings',
            onTap: _busy ? null : () => _listNative(false),
          ),
          const SizedBox(height: 10),
          AskodoxStepChoice(
            key: const Key('askodoxPrinterStepsUsb'),
            icon: Icons.usb,
            color: askodoxStepGreen,
            title: 'USB',
            sub: te ? 'OTG కేబుల్‌తో' : 'With an OTG cable',
            onTap: _busy ? null : () => _listNative(true),
          ),
          if (_message != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_message!, key: const Key('askodoxPrinterStepsMessage'))),
        ]),
      );
    }
    if (_step == 2) {
      return AskodoxStepScaffold(
        key: const Key('askodoxPrinterSteps2'),
        title: title,
        step: 2,
        total: 3,
        question: te ? 'ఏది మీ ప్రింటర్?' : 'Which one is your printer?',
        hint: _message,
        onBack: () => setState(() => _step = 1),
        more: _more(),
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
          for (final d in _found)
            AskodoxStepPersonRow(
              key: ValueKey('askodoxPrinterStepsFound-${d.id}'),
              name: d.name,
              sub: d.sub,
              amount: te ? 'ఎంచు' : 'Pick',
              onTap: () => _choose(d),
            ),
        ]),
      );
    }
    if (_step == 3) {
      final p = _saved;
      return AskodoxStepScaffold(
        key: const Key('askodoxPrinterSteps3'),
        title: title,
        step: 3,
        total: 3,
        more: _more(),
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 28, 16, 16), children: [
          const Center(child: AskodoxStepDoneMark()),
          const SizedBox(height: 26),
          AskodoxStepBigNumber(p?.name ?? '', label: te ? 'ప్రింటర్ సేవ్ అయింది · ${p?.paperMm} mm' : 'Printer saved · ${p?.paperMm} mm', size: 30),
          if (_testNote != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_testNote!, textAlign: TextAlign.center)),
        ]),
        bottom: AskodoxStepBottom(
          buttonKey: const Key('askodoxPrinterStepsTest3'),
          label: te ? 'టెస్ట్ ప్రింట్' : 'Test print',
          icon: Icons.print,
          busy: _busy,
          onPressed: _test,
        ),
      );
    }
    final p = _saved;
    return AskodoxStepScaffold(
      key: const Key('askodoxPrinterSteps'),
      title: title,
      more: _more(),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.fromLTRB(16, 28, 16, 16), children: [
              Icon(Icons.print, size: 72, color: p == null ? askodoxStepMuted : askodoxStepGreen),
              const SizedBox(height: 14),
              AskodoxStepBigNumber(p?.name ?? (te ? 'ప్రింటర్ లేదు' : 'No printer'),
                  label: p == null ? (te ? 'బిల్లు ప్రింట్ కోసం ప్రింటర్ ఎంచుకోండి' : 'Choose a printer to print bills') : '${p.paperMm} mm · ${_linkName(p.id)}',
                  size: 30),
              if (_testNote != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_testNote!, key: const Key('askodoxPrinterStepsNote'), textAlign: TextAlign.center)),
            ]),
      bottom: !_loaded
          ? null
          : p == null
              ? AskodoxStepBottom(
                  buttonKey: const Key('askodoxPrinterStepsStart'),
                  label: te ? 'ప్రింటర్ వెతుకు' : 'Find a printer',
                  icon: Icons.bluetooth_searching,
                  onPressed: () => setState(() => _step = 1),
                )
              : AskodoxStepBottom(
                  buttonKey: const Key('askodoxPrinterStepsTest'),
                  label: te ? 'టెస్ట్ ప్రింట్' : 'Test print',
                  icon: Icons.print,
                  busy: _busy,
                  onPressed: _test,
                ),
    );
  }
}

class _Found {
  const _Found(this.id, this.name, this.sub);
  final String id;
  final String name;
  final String sub;
}
