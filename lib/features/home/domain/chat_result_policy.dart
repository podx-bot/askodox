import 'package:flutter/foundation.dart';

import '../../deal_brain/domain/universal_deal.dart';
import '../../matching/data/universal_match_repository.dart';

/// What a result card embedded in the ASKODOX chat lets the user do.
///
/// * [connect] -- a Party B from `/deals/{id}/matches` (or a sandbox demo
///   match): Party A accepts via `acceptMatch`, the existing consent-first
///   interest flow. Contact stays hidden until both sides accept.
/// * [sendRequest] -- a real seller listing from `/api/products/search`:
///   the existing order request, which the seller must Accept/Decline.
/// * [openLink] -- an online (normal or affiliate) destination.
/// * [watchVideo] -- a video / social result.
enum ChatResultAction { connect, sendRequest, openLink, watchVideo }

ChatResultAction chatResultActionFor(UniversalMatch match) {
  final source = match.source.toLowerCase();
  if (source == 'video') return ChatResultAction.watchVideo;
  if (source == 'online') return ChatResultAction.openLink;
  if (source == 'interest' ||
      source == 'demo_discovery' ||
      match.id.startsWith('demo-')) {
    return ChatResultAction.connect;
  }
  // Only a numeric seller_products id can become an order request.
  if (int.tryParse(match.id) != null) return ChatResultAction.sendRequest;
  final url = match.destinationUrl?.trim() ?? '';
  return url.isNotEmpty ? ChatResultAction.openLink : ChatResultAction.connect;
}

/// The role the user is acting in for the current request. Follows the
/// latest deal intent, so a buyer is never answered as a seller.
enum AskodoxChatRole {
  buyer,
  seller,
  customer,
  serviceProvider,
  employer,
  jobSeeker,
  rider,
  driver,
  sender,
  courier,
  renter,
  owner,
}

AskodoxChatRole? askodoxRoleForIntent(DealIntent intent) => switch (intent) {
      DealIntent.buy => AskodoxChatRole.buyer,
      DealIntent.sell => AskodoxChatRole.seller,
      DealIntent.needService => AskodoxChatRole.customer,
      DealIntent.bookAppointment => AskodoxChatRole.customer,
      DealIntent.offerService => AskodoxChatRole.serviceProvider,
      DealIntent.offerAppointment => AskodoxChatRole.serviceProvider,
      DealIntent.needWorker => AskodoxChatRole.employer,
      DealIntent.seekWork => AskodoxChatRole.jobSeeker,
      DealIntent.needRide => AskodoxChatRole.rider,
      DealIntent.offerRide => AskodoxChatRole.driver,
      DealIntent.sendParcel => AskodoxChatRole.sender,
      DealIntent.deliverParcel => AskodoxChatRole.courier,
      DealIntent.rent => AskodoxChatRole.renter,
      DealIntent.offerRental => AskodoxChatRole.owner,
      DealIntent.other => null,
    };

String askodoxRoleLabel(AskodoxChatRole role, {required bool telugu}) {
  if (telugu) {
    return switch (role) {
      AskodoxChatRole.buyer => 'కొనుగోలుదారు',
      AskodoxChatRole.seller => 'విక్రేత',
      AskodoxChatRole.customer => 'కస్టమర్',
      AskodoxChatRole.serviceProvider => 'సర్వీస్ ప్రొవైడర్',
      AskodoxChatRole.employer => 'యజమాని',
      AskodoxChatRole.jobSeeker => 'ఉద్యోగార్థి',
      AskodoxChatRole.rider => 'ప్రయాణికుడు',
      AskodoxChatRole.driver => 'డ్రైవర్',
      AskodoxChatRole.sender => 'పంపేవారు',
      AskodoxChatRole.courier => 'డెలివరీ భాగస్వామి',
      AskodoxChatRole.renter => 'అద్దెదారు',
      AskodoxChatRole.owner => 'యజమాని (అద్దెకు ఇచ్చేవారు)',
    };
  }
  return switch (role) {
    AskodoxChatRole.buyer => 'Buyer',
    AskodoxChatRole.seller => 'Seller',
    AskodoxChatRole.customer => 'Customer',
    AskodoxChatRole.serviceProvider => 'Service provider',
    AskodoxChatRole.employer => 'Employer',
    AskodoxChatRole.jobSeeker => 'Job seeker',
    AskodoxChatRole.rider => 'Rider',
    AskodoxChatRole.driver => 'Driver',
    AskodoxChatRole.sender => 'Sender',
    AskodoxChatRole.courier => 'Courier',
    AskodoxChatRole.renter => 'Renter',
    AskodoxChatRole.owner => 'Owner (renting out)',
  };
}

/// A short in-chat notice when the user's activity moves them into a
/// different role (for example from buying to selling). Null when there is
/// no previous role or the role did not change.
String? askodoxRoleSwitchNotice({
  required DealIntent? previous,
  required DealIntent current,
  required bool telugu,
}) {
  if (previous == null) return null;
  final from = askodoxRoleForIntent(previous);
  final to = askodoxRoleForIntent(current);
  if (from == null || to == null || from == to) return null;
  final label = askodoxRoleLabel(to, telugu: telugu);
  return telugu
      ? 'ఈ అభ్యర్థనకు మీ పాత్ర ఇప్పుడు: $label'
      : 'You are now acting as: $label for this request';
}

/// The result set ASKODOX embeds under one assistant reply in the chat.
@immutable
class AskodoxChatResults {
  const AskodoxChatResults({
    this.dealId,
    this.matches = const <UniversalMatch>[],
    this.failed = false,
    this.signInRequired = false,
    this.missingFields = const <String>[],
  });

  final String? dealId;
  final List<UniversalMatch> matches;

  /// Matching could not be reached (network / server error). The chat shows
  /// a retry action instead of pretending nothing matched.
  final bool failed;

  /// The backend refused because the user is signed out.
  final bool signInRequired;

  /// Backend said the request still needs these details (HTTP 422).
  final List<String> missingFields;

  List<UniversalMatch> get local => [
        for (final m in matches)
          if (chatResultActionFor(m) == ChatResultAction.connect ||
              chatResultActionFor(m) == ChatResultAction.sendRequest)
            m,
      ];

  List<UniversalMatch> get online => [
        for (final m in matches)
          if (chatResultActionFor(m) == ChatResultAction.openLink) m,
      ];

  List<UniversalMatch> get videos => [
        for (final m in matches)
          if (chatResultActionFor(m) == ChatResultAction.watchVideo) m,
      ];

  bool get hasLocal => local.isNotEmpty;
  bool get isEmpty => matches.isEmpty && !failed && !signInRequired;
}

/// Online + video results the app can offer by itself when the matching
/// backend is unreachable or the user is signed out. These are plain search
/// links -- never invented sellers, prices or stock.
List<UniversalMatch> askodoxOfflineFallbackResults(
  String subject, {
  bool includeVideos = true,
}) {
  final clean = subject.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (clean.isEmpty) return const <UniversalMatch>[];
  final q = Uri.encodeQueryComponent;
  return [
    UniversalMatch(
      id: 'online-0-google.com',
      title: 'Search online for $clean',
      subtitle: 'No verified local match yet -- compare prices and sellers online.',
      source: 'online',
      destinationUrl: 'https://www.google.com/search?q=${q('$clean price')}',
    ),
    if (includeVideos) ...[
      UniversalMatch(
        id: 'video-0-youtube.com',
        title: '$clean reviews on YouTube',
        subtitle: 'Watch video reviews and demos.',
        source: 'video',
        destinationUrl:
            'https://www.youtube.com/results?search_query=${q('$clean review')}',
      ),
      UniversalMatch(
        id: 'video-1-instagram.com',
        title: '$clean on Instagram',
        subtitle: 'Reels and creator posts.',
        source: 'video',
        destinationUrl:
            'https://www.instagram.com/explore/search/keyword/?q=${q(clean)}',
      ),
    ],
  ];
}

/// Intents where a "video review" result is meaningful.
bool askodoxIntentWantsVideos(DealIntent intent) => switch (intent) {
      DealIntent.buy ||
      DealIntent.needService ||
      DealIntent.rent ||
      DealIntent.bookAppointment =>
        true,
      _ => false,
    };

/// Combines the user's words with facts extracted from an attached photo or
/// file so the same intent → category → questions → matching pipeline runs
/// on both.
String askodoxAttachmentRequest(String userText, Object? facts) {
  final text = userText.trim();
  final clean = (facts ?? '').toString().trim();
  if (clean.isEmpty || clean.toLowerCase() == 'null') return text;
  return '$text\nAttachment facts: $clean';
}

/// Reply used when the AI reply is unavailable and the deal still needs a
/// category-specific detail (the deal brain's `lastQuestion`).
String askodoxDetailQuestionReply(String question, {required bool telugu}) =>
    telugu ? 'ఇంకా ఒక వివరం కావాలి: $question' : question;

/// Deterministic reply describing the embedded results when the AI reply is
/// unavailable. Honest about local vs online vs failure.
String askodoxResultsReply(AskodoxChatResults results, {required bool telugu}) {
  if (results.missingFields.isNotEmpty && results.matches.isEmpty) {
    final fields = results.missingFields
        .map((field) => field.replaceAll('_', ' '))
        .join(', ');
    return telugu
        ? 'మీకు సరైన match వెతకడానికి ఇంకా ఈ వివరాలు కావాలి: $fields'
        : 'To find the right match I still need: $fields';
  }
  if (results.signInRequired && !results.hasLocal) {
    return telugu
        ? 'స్థానిక విక్రేతలకు అభ్యర్థన పంపడానికి సైన్ ఇన్ చేయండి. ఈలోగా ఆన్‌లైన్ ఎంపికలు ఇవి.'
        : 'Sign in to send requests to local sellers and providers. Meanwhile, here are online options.';
  }
  if (results.failed) {
    return telugu
        ? 'ఇప్పుడు మ్యాచింగ్ సేవను చేరుకోలేకపోయాం. మీ అభ్యర్థన సురక్షితంగా ఉంది -- క్రింద "మళ్లీ ప్రయత్నించండి" నొక్కండి.'
        : 'I could not reach matching right now. Your request is safe -- tap Retry below.';
  }
  if (results.hasLocal) {
    return telugu
        ? 'మీ అభ్యర్థనకు సరిపోయే స్థానిక ఎంపికలు ఇవి. అభ్యర్థన పంపండి -- వారు అంగీకరించాకే కాంటాక్ట్ వివరాలు కనిపిస్తాయి.'
        : 'Here are local options that match your request. Send a request -- contact details appear only after they accept.';
  }
  if (results.online.isNotEmpty || results.videos.isNotEmpty) {
    return telugu
        ? 'ప్రస్తుతం ధృవీకరించిన స్థానిక match దొరకలేదు. మీ అవసరాన్ని సేవ్ చేశాను; ఈలోగా ఆన్‌లైన్ ఎంపికలు, వీడియోలు ఇవి.'
        : 'No verified local match yet. I saved your need; meanwhile here are online options and videos.';
  }
  return telugu
      ? 'ఈ అభ్యర్థనకు ప్రస్తుతం ధృవీకరించిన match దొరకలేదు. మీ అవసరాన్ని సేవ్ చేశాను; సరైన అవకాశం లభిస్తే ASKODOX మీకు తెలియజేస్తుంది.'
      : 'I could not find a verified match for this request yet. I saved your need and ASKODOX will notify you when a suitable option becomes available.';
}
