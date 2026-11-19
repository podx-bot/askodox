import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/flags/askodox_release_phase.dart' show askodoxRouteShownNow;
import '../../pos/data/pos_repository.dart';
import 'biz_hub.dart';

/// Business work from the MAIN chat (owner 2026-11-18): "ఈ రోజు ఎంత అమ్మాం?", "చికెన్ 65 ఆఫ్ చెయ్యి", "చింతయ్యకి 500
/// అడ్వాన్స్" typed or spoken in the chat do the same as the ASK bar on the business pages: the answer appears in the
/// chat, a page opens, or ONE change waits for ✓. Only for people who belong to a business; the model decides (page
/// "chat" = unknown unless clearly about their own business) and anything else goes on to the normal assistant.

/// The person's own business (the first one they belong to); null = none / signed out / offline.
final askodoxChatBusinessProvider = FutureProvider.autoDispose<String?>((ref) async {
  try {
    final list = await ref.watch(askodoxPosRepositoryProvider).businesses();
    return list.isEmpty ? null : '${list.first['id']}';
  } catch (_) {
    return null;
  }
});

/// A cheap first look so ordinary chat never waits for an extra AI call: words that running a business uses.
/// The model still makes the real decision.
bool askodoxLooksLikeBusinessTalk(String text) {
  final t = text.toLowerCase();
  const words = [
    // English / typed Telugu
    'sales', 'sold', 'today sale', 'my shop', 'my business', 'my hotel', 'dues', 'baaki', 'baki', 'cashbook',
    'expense', 'kharchu', 'income', 'staff', 'attendance', 'salary', 'jeetham', 'advance', 'task', 'report',
    'menu', 'item off', 'item on', ' off chey', ' on chey', 'price', 'dhara', 'bill history', 'busy time',
    'night report', 'orders today', 'kitchen', 'waiter', 'table call',
    // Telugu
    'అమ్మకం', 'అమ్మాం', 'అమ్మింది', 'అమ్మాము', 'బాకీ', 'క్యాష్‌బుక్', 'ఖర్చు', 'ఆదాయం', 'సిబ్బంది', 'హాజరు',
    'జీతం', 'జీతాలు', 'అడ్వాన్స్', 'రిపోర్ట్', 'మెనూ', 'ఆఫ్ చెయ్', 'ఆఫ్ చేయ', 'ఆన్ చెయ్', 'ఆన్ చేయ', 'ధర',
    'నా షాప్', 'మా షాప్', 'నా బిజినెస్', 'మా హోటల్', 'బిల్లులు', 'ఆర్డర్లు', 'వంటగది', 'వెయిటర్', 'పని ఇవ్వు',
    'పని చెప్పు', 'పని కేటాయించు', 'వచ్చాను', 'రద్దీ',
  ];
  return words.any(t.contains);
}

class AskodoxChatBusinessAnswer {
  const AskodoxChatBusinessAnswer(this.businessId, this.reply, this.open, this.confirm, this.link);
  final String businessId;
  final String reply;
  final String? open;
  final AskodoxJson confirm;
  final String? link;
}

/// null = not business talk (or no business / an error): the chat carries on as normal.
Future<AskodoxChatBusinessAnswer?> askodoxChatBusinessAsk(WidgetRef ref, String text, bool te) async {
  if (!askodoxLooksLikeBusinessTalk(text)) return null;
  final id = await ref.read(askodoxChatBusinessProvider.future);
  if (id == null) return null;
  try {
    final out = await ref.read(askodoxPosRepositoryProvider).ask(id, text, page: 'chat', lang: te ? 'te' : 'en');
    if ('${out['intent'] ?? 'unknown'}' == 'unknown') return null;
    final open = '${out['open'] ?? ''}';
    final link = '${out['link'] ?? ''}';
    return AskodoxChatBusinessAnswer(id, '${out['reply'] ?? ''}', open.isEmpty ? null : open, askodoxPosMap(out['confirm']),
        link.isEmpty ? null : link);
  } catch (_) {
    return null;
  }
}

/// The ✓ / ✗ question for ONE change; runs it only on ✓. Returns the line to show after (null = nothing changed).
Future<String?> askodoxConfirmBusinessChange(
    BuildContext context, WidgetRef ref, String businessId, AskodoxJson confirm, bool te) async {
  final yes = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(te ? 'ఇలా చేయనా?' : 'Do this?'),
      content: Text('${confirm['summary'] ?? ''}', style: const TextStyle(fontSize: 16)),
      actions: [
        TextButton(
            key: const Key('askodoxChatBizNo'),
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(te ? '✗ వద్దు' : '✗ No')),
        FilledButton(
            key: const Key('askodoxChatBizYes'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(te ? '✓ అవును, చేయి' : '✓ Yes, do it')),
      ],
    ),
  );
  if (yes != true) return te ? 'సరే, ఏమీ మార్చలేదు.' : 'Okay, nothing changed.';
  try {
    await ref.read(askodoxPosRepositoryProvider).askConfirm(businessId, {
      for (final e in confirm.entries)
        if (e.key != 'summary' && e.value != null) e.key: e.value,
    });
    return te ? '✓ చేశాను: ${confirm['summary']}' : '✓ Done: ${confirm['summary']}';
  } on AskodoxPosException catch (e) {
    return e.message(te);
  } catch (_) {
    return te ? 'ఇప్పుడు కాలేదు. మళ్ళీ ప్రయత్నించండి.' : 'Could not do that now. Try again.';
  }
}

/// After the reply is in the chat: open the page, ask ✓ for a change, or offer to open the report.
Future<void> askodoxChatBusinessFollowUp(BuildContext context, WidgetRef ref, AskodoxChatBusinessAnswer a, bool te,
    {required void Function(String text) say}) async {
  if (a.confirm.isNotEmpty) {
    final line = await askodoxConfirmBusinessChange(context, ref, a.businessId, a.confirm, te);
    if (line != null) say(line);
    return;
  }
  final open = a.open;
  if (open != null) {
    final route = askodoxBizRoute(a.businessId, open);
    if (askodoxRouteShownNow(route) && context.mounted) unawaited(context.push(route));
    return;
  }
  final link = a.link;
  if (link != null && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 8),
      content: Text(te ? 'పూర్తి రిపోర్ట్ — బార్లు, కారణాలు, సలహాలతో' : 'The full report — bars, reasons, suggestions'),
      action: SnackBarAction(
          label: te ? 'తెరువు' : 'Open', onPressed: () => context.push(askodoxBizRoute(a.businessId, link))),
    ));
  }
}


/// Owner 2026-11-19 (agents inside the main chat): which role agent the words name, or null. "stock agent ఏం తక్కువ
/// ఉంది", "ఫైనాన్స్ ఏజెంట్", "@sales" ... Only the shop's role agents (pos_agents.AGENTS); the agent still answers only
/// from the shop's own records within the person's role.
String? askodoxChatAgentOf(String text) {
  final t = text.toLowerCase();
  if (!(t.contains('agent') || t.contains('ఏజెంట్') || t.contains('एजेंट') || t.startsWith('@'))) return null;
  const names = <String, List<String>>{
    'inventory': ['inventory', 'stock', 'స్టాక్', 'సరుకు', 'स्टॉक'],
    'finance': ['finance', 'money', 'ఫైనాన్స్', 'డబ్బు', 'फाइनेंस'],
    'sales': ['sales', 'సేల్స్', 'అమ్మకాల', 'सेल्स'],
    'support': ['support', 'complaint', 'సపోర్ట్', 'ఫిర్యాదు', 'सपोर्ट'],
    'tax': ['tax', 'gst', 'టాక్స్', 'పన్ను', 'జీఎస్టీ', 'टैक्स'],
    'hr': ['hr', 'staff', 'సిబ్బంది', 'స్టాఫ్', 'स्टाफ'],
    'owner': ['owner', 'ఓనర్', 'ఓనరు', 'मालिक'],
  };
  for (final e in names.entries) {
    if (e.value.any((w) => RegExp('(^|[^a-z])${RegExp.escape(w)}').hasMatch(t))) return e.key;
  }
  return null;
}

/// Asks that agent of the person's shop; null when there is no shop / no permission / no answer (chat goes on).
Future<String?> askodoxChatAgentAsk(WidgetRef ref, String agent, String text, bool te) async {
  final id = await ref.read(askodoxChatBusinessProvider.future);
  if (id == null) return null;
  try {
    final out = await ref.read(askodoxPosRepositoryProvider).agentAsk(id, agent, text, te ? 'te' : 'en');
    final answer = '${out['answer'] ?? ''}'.trim();
    return answer.isEmpty ? null : answer;
  } catch (_) {
    return null;
  }
}
