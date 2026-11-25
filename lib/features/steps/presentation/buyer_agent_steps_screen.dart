import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../pos/data/pos_repository.dart';
import '../../pos/presentation/pos_common.dart';
import 'step_kit.dart';

/// Owner 2026-11-25 (3-step design, batch 29): the buyer's own helper `/me/agent`.
/// Top = ONE question box, middle = the answer (from the person's own shop records: bills, dues, shop advances),
/// bottom = ONE big Ask button with the mic (the mic fills the box and asks). Shop advances + the old page in ⋮.
/// The agent only reads; it never pays, approves or messages anyone. Old page stays at `?full=1`.
class AskodoxBuyerAgentStepsScreen extends ConsumerStatefulWidget {
  const AskodoxBuyerAgentStepsScreen({super.key});

  @override
  ConsumerState<AskodoxBuyerAgentStepsScreen> createState() => _BuyerAgentStepsState();
}

class _BuyerAgentStepsState extends ConsumerState<AskodoxBuyerAgentStepsScreen> {
  final _question = TextEditingController();
  AskodoxJson? _answer;
  Object? _error;
  bool _busy = false;

  bool get _te => askodoxPosTe(context);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ask());
  }

  @override
  void dispose() {
    _question.dispose();
    super.dispose();
  }

  Future<void> _ask() async {
    if (!mounted || _busy) return;
    final te = _te;
    setState(() => _busy = true);
    try {
      final out = await ref.read(askodoxPosRepositoryProvider).buyerAgentAsk(_question.text.trim(), te ? 'te' : 'en');
      if (mounted) {
        setState(() {
          _answer = out;
          _error = null;
        });
      }
    } on AskodoxPosException catch (e) {
      if (!mounted) return;
      if (_answer == null) {
        setState(() => _error = e);
      } else {
        askodoxPosSnack(context, e.message(te));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final answer = _answer;
    return AskodoxStepScaffold(
      key: const Key('askodoxBuyerAgentSteps'),
      title: te ? 'నా సహాయకుడు' : 'My helper',
      question: te ? 'ఏం అడగాలి?' : 'What do you want to ask?',
      hint: te ? 'ఉదా: ఏ షాప్‌కి ఎంత బాకీ ఉన్నాను?' : 'e.g. how much do I owe which shop?',
      more: [
        AskodoxStepMore('askodoxBuyerAgentStepsAdvances', te ? 'షాప్ అడ్వాన్సులు' : 'Shop advances', Icons.savings_outlined,
            () => context.push('/me/shop-advances')),
        AskodoxStepMore('askodoxBuyerAgentStepsFull', te ? 'పాత పేజీ' : 'Old page', Icons.menu_book_rounded,
            () => context.push('/me/agent?full=1')),
      ],
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
        TextField(
          key: const Key('askodoxBuyerAgentStepsQuestion'),
          controller: _question,
          onSubmitted: (_) => _ask(),
          style: const TextStyle(fontSize: 18),
          decoration: InputDecoration(
              border: const OutlineInputBorder(), hintText: te ? 'ఇక్కడ రాయండి లేదా మైక్ నొక్కండి' : 'Type here or tap the mic'),
        ),
        const SizedBox(height: 12),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null && answer == null) AskodoxPosError(error: _error!, onRetry: _ask),
        if (answer != null)
          Container(
            key: const Key('askodoxBuyerAgentStepsAnswer'),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: askodoxStepGreenSoft, borderRadius: BorderRadius.circular(16)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${answer['answer'] ?? ''}', style: const TextStyle(fontSize: 17, height: 1.4)),
              const SizedBox(height: 6),
              Text(te ? 'మీ సొంత షాప్ రికార్డుల నుండి. ఇది ఏదీ కట్టదు, ఎవరికీ పంపదు.' : 'From your own shop records. It never pays or sends anything.',
                  style: const TextStyle(fontSize: 12, color: askodoxStepMuted)),
            ]),
          ),
      ]),
      bottom: AskodoxStepBottom(
        buttonKey: const Key('askodoxBuyerAgentStepsAsk'),
        label: te ? 'అడుగు' : 'Ask',
        icon: Icons.send_rounded,
        busy: _busy,
        onPressed: _ask,
        onSpoken: (said) {
          _question.text = said;
          unawaited(_ask());
        },
      ),
    );
  }
}
