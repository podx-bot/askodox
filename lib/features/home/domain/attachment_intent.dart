import 'chat_action_intent.dart';
import 'home_request_routing.dart';
import 'need_state.dart';

final _actionWords = RegExp(
  r'\b(buy|order|purchase|price|cost|rate|where (can|to)|near ?(me|by)|find|shop|store|seller|sell|book|repair|'
  r'service|fix|deliver|rent|hire|compare|online|available)\b',
  caseSensitive: false,
);

/// True when the customer's own words (sent with an attachment) ask ASKODOX
/// to ACT -- find, buy, sell, price, book, repair. A photo/video/file sent
/// alone, or with "what is this?", is a request to UNDERSTAND it: no search,
/// no sellers, no online cards, no referral/join prompts.
bool askodoxAttachmentWantsAction(String typed) {
  final text = typed.trim();
  if (text.isEmpty) return false;
  return _actionWords.hasMatch(text) ||
      askodoxWantsResultsNow(text) ||
      askodoxWantsToList(text) ||
      askodoxStatesANeed(text) ||
      AskodoxHomeRequestRouting.isTransactional(text);
}

/// Instructions for the reasoning turn that answers an attachment sent to be
/// understood. Only the extracted facts may be used; uncertainty and failed
/// files are stated honestly.
String askodoxAttachmentGuidance({bool lowConfidence = false, List<String> failed = const []}) => [
      'The customer shared attachment(s) to be understood. Explain what the attachment facts show, using only '
          'those facts. Then ask ONE short question about what they want to do with it, with options that fit '
          'THIS item (for example: find it nearby, compare prices, get it repaired or serviced, sell it, or '
          'understand it better).',
      'Do not list sellers, products, prices from elsewhere, online links, referral or join-ASKODOX suggestions '
          'in this reply.',
      if (lowConfidence)
        'The image analysis was NOT confident: say that you are not sure and ask the customer to confirm what it is.',
      if (failed.isNotEmpty)
        'These attachments could not be analysed: ${failed.join(', ')}. Say so plainly; do not guess their content.',
    ].join('\n');

/// Referral / "join ASKODOX" chips belong in Profile -> Refer & Earn. In the
/// chat they appear only when the customer's own message is about
/// referring, inviting, joining or offering a service/product.
bool askodoxAllowsGrowthPrompt(String userText) => RegExp(
      r'\b(refer|referral|invite|join|register|sign ?up|i (am|m) an? (seller|provider|shop|driver|plumber|electrician)|'
      r'i (sell|offer|provide)|list my|my shop|my business)\b',
      caseSensitive: false,
    ).hasMatch(userText);
