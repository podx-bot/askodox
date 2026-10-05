import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../growth/data/growth_repository.dart';

/// ONE ride / parcel being set up, shared by Main Chat and the Rides &
/// deliveries screen: what the chat understood ("auto from Benz Circle to
/// the airport") opens the screen pre-filled, and what the customer edits
/// there is what the chat's "Request a driver" sends.
class MobilityDraft {
  const MobilityDraft({required this.kind, this.from, this.to});

  final String kind;
  final AskodoxPlace? from;
  final AskodoxPlace? to;

  MobilityDraft copyWith({String? kind, AskodoxPlace? from, AskodoxPlace? to, bool clearFrom = false,
          bool clearTo = false}) =>
      MobilityDraft(
          kind: kind ?? this.kind, from: clearFrom ? null : (from ?? this.from), to: clearTo ? null : (to ?? this.to));

  /// `/mobility?kind=..&from=..&to=..` (labels only; coordinates stay in the
  /// shared draft, never in a link).
  String get location => Uri(path: '/mobility', queryParameters: {
        'kind': kind,
        if (from != null) 'from': from!.label,
        if (to != null) 'to': to!.label,
      }).toString();
}

final askodoxMobilityDraftProvider = StateProvider<MobilityDraft?>((ref) => null);

/// The backend's point shape for a chosen place (a label alone is resolved
/// server-side).
Map<String, Object?> askodoxMobilityPoint(AskodoxPlace place) => {
      'label': place.label,
      if (place.latitude != 0 || place.longitude != 0) ...{'latitude': place.latitude, 'longitude': place.longitude},
    };

/// Google Maps directions for the route (opens the Maps app; nothing is
/// sent from ASKODOX).
Uri askodoxRouteDirectionsUri(AskodoxPlace from, AskodoxPlace to) {
  String end(AskodoxPlace p) =>
      p.latitude != 0 || p.longitude != 0 ? '${p.latitude},${p.longitude}' : p.label;
  return Uri.https('www.google.com', '/maps/dir/', {'api': '1', 'origin': end(from), 'destination': end(to)});
}
