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
          'those facts; never describe anything the facts do not contain. Then ask ONE short question about what '
          'they want to do with it, with options that fit THIS content.',
      'Do not assume it is a shopping request. Offer buying, price or repair options ONLY when the attachment is '
          'clearly a product or item someone might buy, sell or repair. For a report, bill, letter, form, '
          'certificate, personal photo, vehicle, place or anything else, offer to explain, summarise or answer '
          'questions about it instead.',
      'Medical, legal or financial documents: explain the readable content cautiously, say what it does not '
          'establish, and suggest confirming with a qualified professional; never diagnose.',
      'Privacy: do not repeat phone numbers, ID / Aadhaar / PAN / account / card numbers, or full addresses from '
          'the attachment unless the customer asks about that exact detail.',
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

final _videoReference = RegExp(
  r'\b(video|clip|this|it|its|that|he|she|they|shown|show|showed|says?|said|mention(ed|s)?|demo)\b'
  r'|వీడియో|ఇది|ఇందులో|దీని|దాని|చూపి|చెప్పా',
  caseSensitive: false,
);
final _questionShape = RegExp(
  r'\?\s*$|^\s*(what|which|who|whom|whose|when|where|why|how|is|are|does|do|did|can|could|will|would|should|has|have)\b'
  r'|ా\s*$|ఏమి|ఎంత|ఎలా|ఎక్కడ|ఎప్పుడు|ఏది|ఉందా|చేస్తుందా',
  caseSensitive: false,
);
final _leaveVideo = RegExp(
  r'\b(near ?(me|by)|nearby|where (can|to) (i )?(buy|get)|buy (it|this|one)|order (it|this|one)|book|sell (it|this|my)|'
  r'show me (shops|sellers|options|results)|find (me )?(a |shops|sellers))\b'
  r'|దగ్గర(లో)?|కొనాలి|ఆర్డర్',
  caseSensitive: false,
);

/// A question about a video the customer attached in THIS conversation
/// ("does it inflate bike tyres?", "what did he say about battery?") goes to
/// that video's grounded study -- never to a product/deal search (which
/// answered "No verified local match… ID 47" on the phone). Asking to buy /
/// find it nearby / order still acts.
bool askodoxAsksAboutVideo(String typed, {bool justAttached = false}) {
  final text = typed.trim();
  if (text.isEmpty || _leaveVideo.hasMatch(text)) return false;
  // Not isTransactional: "does it inflate bike tyres?" mentions a product
  // word but asks about the video.
  if (askodoxWantsResultsNow(text) || askodoxWantsToList(text)) return false;
  if (!_questionShape.hasMatch(text)) return false;
  return justAttached || _videoReference.hasMatch(text);
}

/// The grounded answer as chat text: the study's own words plus where in the
/// video it was seen / said; "not in this video" stays honest.
String askodoxVideoAnswerText(String answer, List<String> timestamps,
    {required bool found, String lang = 'en', String? basis}) {
  final te = lang == 'te';
  final body = answer.trim().isNotEmpty
      ? answer.trim()
      : (te ? 'ఈ వీడియోలో ఆ విషయం లేదు.' : 'That is not in this video.');
  final source = switch (basis) {
    'seen_in_video' => te ? 'వీడియోలో కనిపించింది' : 'Seen in video',
    'said_by_seller' => te ? 'సెల్లర్ చెప్పారు' : 'Said by seller',
    'listing' => te ? 'సెల్లర్ లిస్టింగ్' : "Seller's listing",
    'askodox' => te ? 'ASKODOX గమనిక' : 'ASKODOX note',
    _ => null,
  };
  final lines = [body];
  if (found && source != null) lines.add('[$source]');
  if (found && timestamps.isNotEmpty) {
    final at = timestamps.take(3).join(', ');
    lines.add(te ? '(వీడియోలో: $at)' : '(In the video at $at)');
  }
  return lines.join('\n');
}

final _deliveryProvider = RegExp(
  r"\b(i can|i will|i'?d like to|i want to|want to|join as|work as|become a|register as)\b.{0,30}"
  r'\b(deliver|delivery|drive|driver|partner|rider|courier)\b'
  r'|నేను .{0,20}(డెలివరీ|డ్రైవర్|డ్రైవ్)|(డెలివరీ|డ్రైవర్) (గా )?(పని|చేస్తాను|చేయగలను)',
  caseSensitive: false,
);
final _deliveryQuestion = RegExp(
  r'\b(can|do|does|will|could) (you|askodox|u)\b.{0,20}\b(deliver|delivery|courier|send)\b'
  r'|\b(is|any) (home )?delivery (available|possible|there)\b'
  r'|డెలివరీ (చేస్తారా|ఉందా|చేయగలరా)|డెలివర్ చేస్తారా',
  caseSensitive: false,
);

/// "Can you deliver food?" / "I can work as a delivery partner": a question
/// about WHAT ASKODOX can do (answered from the category tree's
/// capabilities), not a product search.
bool askodoxAsksDeliveryCapability(String text) =>
    _deliveryProvider.hasMatch(text) || _deliveryQuestion.hasMatch(text);
