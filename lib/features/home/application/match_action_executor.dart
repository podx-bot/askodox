import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/backend_providers.dart';
import '../../matching/data/universal_match_repository.dart';
import '../../orders/data/order_repository.dart';
import '../domain/chat_result_policy.dart';

/// The ONE implementation of "act on this option", used by the result
/// card's Send request / Connect button AND by a typed confirmation in chat
/// ("yes", "order it", "book it"). Both reach the same backend endpoint:
/// * a registered listing -> `POST /api/orders` (seller accepts/declines)
/// * a Party B / interest -> `POST /deals/{id}/accept-match` (consent-first)
/// Online pages, nearby unregistered shops and videos cannot be ordered
/// through ASKODOX; for them this returns a failure with an honest reason.
Future<OrderActionResult> askodoxExecuteMatchAction(
  WidgetRef ref, {
  required UniversalMatch match,
  required String? dealId,
  required bool telugu,
  Map<String, Object?>? requestContext,
  String? question,
}) async {
  final action = chatResultActionFor(match);
  final needsIdentity = action == ChatResultAction.sendRequest || action == ChatResultAction.connect;
  final signInResult = OrderActionResult(
    success: false,
    needsSignIn: true,
    message: telugu
        ? 'అభ్యర్థన పంపడానికి మీ ఫోన్ నంబర్‌తో సైన్ ఇన్ చేయండి. ఫలితాలు చూడడానికి సైన్ ఇన్ అవసరం లేదు.'
        : 'Sign in with your phone number to send this request. Browsing results never needs sign-in.',
  );
  // Only acting needs identity; a guest is asked to sign in, never shown a
  // raw server error.
  if (needsIdentity && ref.read(authSessionProvider).user == null) return signInResult;
  try {
    if (action == ChatResultAction.sendRequest) {
      final placed = await ref.read(orderRepositoryProvider).placeOrder(
            productId: match.id,
            requestContext: requestContext,
            question: question,
          );
      // An expired/missing session on the server side: same sign-in offer.
      if (!placed.success && _isSignInError(placed.message)) return signInResult;
      return placed;
    }
    if (action == ChatResultAction.connect) {
      if (dealId == null || dealId.isEmpty) return signInResult;
      await ref.read(universalMatchRepositoryProvider).acceptMatch(dealId: dealId, matchId: match.id);
      return const OrderActionResult(success: true);
    }
    return OrderActionResult(
      success: false,
      message: telugu
          ? 'ఇది ASKODOX లో నమోదు కాని ఎంపిక -- దాన్ని తెరిచి నేరుగా సంప్రదించండి.'
          : 'This option is not on ASKODOX, so a request cannot be sent here -- open it to contact them directly.',
    );
  } catch (error) {
    final message = error is StateError ? error.message : null;
    if (_isSignInError(message ?? '$error')) return signInResult;
    return OrderActionResult(
      success: false,
      message: message ?? (telugu ? 'అభ్యర్థన పంపడం సాధ్యం కాలేదు.' : 'Unable to send this request.'),
    );
  }
}

bool _isSignInError(String? message) {
  final text = (message ?? '').toLowerCase();
  return text.contains('sign in') || text.contains('session') && text.contains('expired') || text.contains('401');
}
