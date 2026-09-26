import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../deal_brain/domain/universal_deal.dart';

/// Roles a single ASKODOX user can hold at the same time. The user's
/// stored roles are never removed by conversation; the conversation only
/// moves the CURRENT ACTIVE role.
enum AskodoxUserRole {
  buyer,
  seller,
  serviceProvider,
  jobSeeker,
  deliveryPartner,
  employer,
  driver,
}

/// Roles shown on the Profile screen, in display order.
const askodoxProfileRoles = [
  AskodoxUserRole.buyer,
  AskodoxUserRole.seller,
  AskodoxUserRole.serviceProvider,
  AskodoxUserRole.jobSeeker,
  AskodoxUserRole.deliveryPartner,
];

String askodoxUserRoleLabel(AskodoxUserRole role, {bool telugu = false}) {
  if (telugu) {
    return switch (role) {
      AskodoxUserRole.buyer => 'కొనుగోలుదారు',
      AskodoxUserRole.seller => 'విక్రేత',
      AskodoxUserRole.serviceProvider => 'సర్వీస్ ప్రొవైడర్',
      AskodoxUserRole.jobSeeker => 'ఉద్యోగార్థి',
      AskodoxUserRole.deliveryPartner => 'డెలివరీ భాగస్వామి',
      AskodoxUserRole.employer => 'యజమాని',
      AskodoxUserRole.driver => 'డ్రైవర్',
    };
  }
  return switch (role) {
    AskodoxUserRole.buyer => 'Buyer',
    AskodoxUserRole.seller => 'Seller',
    AskodoxUserRole.serviceProvider => 'Service Provider',
    AskodoxUserRole.jobSeeker => 'Job Seeker',
    AskodoxUserRole.deliveryPartner => 'Delivery Partner',
    AskodoxUserRole.employer => 'Employer',
    AskodoxUserRole.driver => 'Driver',
  };
}

/// The role implied by the deal brain's intent. Demand-side intents (buying,
/// booking a service, needing a ride or sending a parcel) all act as Buyer.
AskodoxUserRole? askodoxRoleForIntent(DealIntent intent) => switch (intent) {
      DealIntent.buy ||
      DealIntent.needService ||
      DealIntent.bookAppointment ||
      DealIntent.needRide ||
      DealIntent.sendParcel ||
      DealIntent.rent =>
        AskodoxUserRole.buyer,
      DealIntent.sell || DealIntent.offerRental => AskodoxUserRole.seller,
      DealIntent.offerService ||
      DealIntent.offerAppointment =>
        AskodoxUserRole.serviceProvider,
      DealIntent.seekWork => AskodoxUserRole.jobSeeker,
      DealIntent.deliverParcel => AskodoxUserRole.deliveryPartner,
      DealIntent.needWorker => AskodoxUserRole.employer,
      DealIntent.offerRide => AskodoxUserRole.driver,
      DealIntent.other => null,
    };

class AskodoxRoleDetection {
  const AskodoxRoleDetection(this.role, {this.ambiguous = false});
  final AskodoxUserRole role;

  /// True when the message only hints at the role (a question about it, or
  /// mixed buy/sell cues). High-impact switches are then confirmed first.
  final bool ambiguous;
}

bool _any(String text, List<String> patterns) =>
    patterns.any((p) => RegExp(p).hasMatch(text));

/// Detects the role a message is acting in, from what the user says about
/// themselves ("I repair ACs", "I can deliver parcels", "I want to sell my
/// TV", "I need a computer operator job", "I want chicken").
AskodoxRoleDetection? askodoxDetectRole(String message) {
  final text = ' ${message.toLowerCase().replaceAll(RegExp(r'\s+'), ' ')} ';
  final jobSeeker = _any(text, [
    r'\b(need|want|looking for|searching for|find)( me)? (a |an )?([a-z ]+ )?(job|work|employment)\b',
    r'ఉద్యోగం కావాలి',
    r'పని కావాలి',
  ]);
  final delivery = _any(text, [
    r'\bi (can|will) deliver\b',
    r'\bi deliver\b',
    r'\bdelivery partner\b',
    r'\bi have a (bike|scooter|vehicle) (for|to do) deliver',
  ]);
  final provider = _any(text, [
    r'\bi (repair|fix|service|install|clean|paint|teach|tutor|cater|design)\b',
    r'\bi (provide|offer|do) [a-z ]*(service|services|repair|repairs|work)\b',
    r"\bi('m| am) an? (plumber|electrician|mechanic|technician|carpenter|painter|tutor|driver|beautician|tailor)\b",
    r'\boffer service\b',
    r'సర్వీస్ ఇస్తాను',
    r'రిపేర్ చేస్తాను',
  ]);
  final seller = _any(text, [
    r'\b(want|need|going) to sell\b',
    r'\bi (am )?sell(ing)?\b',
    r'\bsell my\b',
    r'\bfor sale\b',
    r'అమ్మాలి',
    r'అమ్ముతున్నాను',
  ]);
  final buyer = _any(text, [
    r'\b(want|need) to buy\b',
    r'\bi (want|need)\b',
    r'\bbuy\b',
    r'కావాలి',
    r'కొనాలి',
  ]);

  final question = text.contains('?') ||
      _any(text, [r'\b(can|should|could) i\b', r'\bhow (do|can) i\b']);

  AskodoxUserRole? role;
  if (jobSeeker) {
    role = AskodoxUserRole.jobSeeker;
  } else if (delivery) {
    role = AskodoxUserRole.deliveryPartner;
  } else if (provider) {
    role = AskodoxUserRole.serviceProvider;
  } else if (seller) {
    role = AskodoxUserRole.seller;
  } else if (buyer) {
    role = AskodoxUserRole.buyer;
  }
  if (role == null) return null;
  final mixed = seller && buyer && !_any(text, [r'\bsell my\b', r'\bwant to sell\b']);
  return AskodoxRoleDetection(role, ambiguous: question || mixed);
}

/// Supply-side switches change what ASKODOX does for the user (listing,
/// accepting requests), so an ambiguous hint asks before switching.
bool askodoxRoleSwitchIsHighImpact(AskodoxUserRole to) =>
    to != AskodoxUserRole.buyer;

String askodoxRoleChangedMessage(
  AskodoxUserRole from,
  AskodoxUserRole to, {
  required bool telugu,
}) =>
    telugu
        ? 'యాక్టివ్ పాత్ర మారింది: ${askodoxUserRoleLabel(from, telugu: true)} → ${askodoxUserRoleLabel(to, telugu: true)}'
        : 'Active role changed: ${askodoxUserRoleLabel(from)} → ${askodoxUserRoleLabel(to)}';

String askodoxRoleSwitchQuestion(AskodoxUserRole to, {required bool telugu}) =>
    telugu
        ? '${askodoxUserRoleLabel(to, telugu: true)} మోడ్‌కి మారాలా?'
        : 'Switch to ${askodoxUserRoleLabel(to)} mode?';

class AskodoxRoleState {
  const AskodoxRoleState({
    this.owned = const {AskodoxUserRole.buyer},
    this.active = AskodoxUserRole.buyer,
  });

  /// Roles the user holds (edited only from Profile).
  final Set<AskodoxUserRole> owned;

  /// Role the current conversation is acting in.
  final AskodoxUserRole active;

  AskodoxRoleState copyWith({Set<AskodoxUserRole>? owned, AskodoxUserRole? active}) =>
      AskodoxRoleState(owned: owned ?? this.owned, active: active ?? this.active);
}

final askodoxRoleProvider =
    StateNotifierProvider<AskodoxRoleController, AskodoxRoleState>(
  (ref) => AskodoxRoleController(),
);

class AskodoxRoleController extends StateNotifier<AskodoxRoleState> {
  AskodoxRoleController() : super(const AskodoxRoleState()) {
    _load();
  }

  static const _key = 'askodox.roles.v1';

  /// Switches the CURRENT ACTIVE role. Stored roles are left untouched.
  void setActive(AskodoxUserRole role) {
    if (state.active == role) return;
    state = state.copyWith(active: role);
    _save();
  }

  /// Profile-only: add or remove a held role (at least one always remains).
  void toggleOwned(AskodoxUserRole role, bool owned) {
    final next = {...state.owned};
    if (owned) {
      next.add(role);
    } else if (next.length > 1) {
      next.remove(role);
    }
    state = state.copyWith(owned: next);
    _save();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || !mounted) return;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      AskodoxUserRole? parse(Object? name) {
        for (final role in AskodoxUserRole.values) {
          if (role.name == name) return role;
        }
        return null;
      }

      final owned = (json['owned'] as List? ?? const [])
          .map(parse)
          .whereType<AskodoxUserRole>()
          .toSet();
      state = AskodoxRoleState(
        owned: owned.isEmpty ? const {AskodoxUserRole.buyer} : owned,
        active: parse(json['active']) ?? AskodoxUserRole.buyer,
      );
    } catch (_) {
      // Fall back to the default Buyer role.
    }
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode({
        'owned': [for (final role in state.owned) role.name],
        'active': state.active.name,
      }));
    } catch (_) {}
  }
}
