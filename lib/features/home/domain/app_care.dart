/// AI-first Customer Care (owner 2026-11-15, pani D).
///
/// "I want to talk to Customer Care" never opens a staff chat. ASKODOX AI first solves it with everything it knows
/// about the app -- the same help text every screen has -- and asks what the problem is when the person has not
/// said. Only when the problem is STILL not solved does the chat offer "Send to ASKODOX team": a ticket in the
/// Command Center plus an email and a phone notification to the owner. There is no live chat with staff.
library;

import '../../../core/flags/askodox_release_phase.dart';
import '../../guide/screen_help.dart';

final _careWords = RegExp(
  r'customer\s*(care|support|service)|\bsupport\b|\bhelp\s*desk\b|\bhuman\b|\b(real\s+)?agent\b|'
  r'\b(talk|speak|chat)\s+(to|with)\s+(someone|a\s+person|support|team)|కస్టమర్\s*కేర్|సపోర్ట్|హెల్ప్\s*లైన్|'
  r'ग्राहक\s*सेवा|कस्टमर\s*केयर',
  caseSensitive: false,
);

/// True when the person asks for Customer Care / a person / support.
bool askodoxWantsCustomerCare(String text) => _careWords.hasMatch(text);

/// What ASKODOX knows about the app: the screens of THIS build (Phase 2 screens left out) with their steps.
/// Kept short (the model reads it on every Customer Care turn).
String askodoxAppKnowledge({int maxChars = 6000}) {
  final out = StringBuffer();
  for (final e in askodoxScreenHelp.entries) {
    final path = e.key;
    if (path.startsWith('/admin') || path.startsWith('/developer')) continue;
    if (!askodoxRouteShownNow(path)) continue;
    final line = '- ${e.value.titleEn} ($path): ${e.value.stepsEn.join(' ')}\n';
    if (out.length + line.length > maxChars) break;
    out.write(line);
  }
  return out.toString();
}

/// The instruction the assistant gets on a Customer Care turn.
String askodoxAppCareGuidance() => 'ASKODOX app help (Customer Care, first line). The customer asked for Customer Care '
    'or reported a problem with the app. Solve it YOURSELF first, in the language of the conversation: if the '
    'problem is not clear, ask ONE short question about what is going wrong; otherwise give the exact steps in the '
    'app (screen names and buttons from the list below) or on the phone (Android settings: notifications, battery, '
    'permissions). Never say a staff member will chat or call; there is no live chat. If after your answer it is '
    'still not solved, tell them they can tap "Send to ASKODOX team" and the team will look at it. Never invent a '
    'screen or button that is not in this list.\n'
    'ASKODOX screens and what to do on each:\n${askodoxAppKnowledge()}';
