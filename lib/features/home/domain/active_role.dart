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
  // Participation roles (scoped to a transaction, never a global identity
  // change): they add value to someone else's deal and can be attributed.
  influencer,
  advisor,
  referrer,
  agent,
  partner,
  distributor,
  farmer,
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
      AskodoxUserRole.influencer => 'ఇన్‌ఫ్లుయెన్సర్',
      AskodoxUserRole.advisor => 'సలహాదారు',
      AskodoxUserRole.referrer => 'సూచించినవారు',
      AskodoxUserRole.agent => 'ఏజెంట్/మధ్యవర్తి',
      AskodoxUserRole.partner => 'భాగస్వామి',
      AskodoxUserRole.distributor => 'పంపిణీదారు',
      AskodoxUserRole.farmer => 'రైతు',
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
    AskodoxUserRole.influencer => 'Influencer',
    AskodoxUserRole.advisor => 'Advisor',
    AskodoxUserRole.referrer => 'Referrer',
    AskodoxUserRole.agent => 'Agent / Middleman',
    AskodoxUserRole.partner => 'Partner',
    AskodoxUserRole.distributor => 'Distributor',
    AskodoxUserRole.farmer => 'Farmer',
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

/// Supply-side roles: acting as one publishes listings / receives leads,
/// so it must come from the user's own words, never from a guessed intent.
const askodoxSupplyRoles = {
  AskodoxUserRole.seller,
  AskodoxUserRole.serviceProvider,
  AskodoxUserRole.jobSeeker,
  AskodoxUserRole.deliveryPartner,
  AskodoxUserRole.driver,
  AskodoxUserRole.farmer,
  AskodoxUserRole.distributor,
};

/// Roles that add value to another party's deal; recorded as transaction
/// participants (attribution) rather than changing who buys or sells.
const askodoxParticipationRoles = {
  AskodoxUserRole.influencer,
  AskodoxUserRole.advisor,
  AskodoxUserRole.referrer,
  AskodoxUserRole.agent,
  AskodoxUserRole.partner,
};

/// The role the conversation should make active for this message, scoped to
/// the current request: the user's own words win; an inferred deal intent
/// may only move between demand-side roles (Buyer <-> Employer). Browsing a
/// TV therefore can never turn a Buyer into a Seller.
///
/// Once the user acts as a Seller / Provider ([current] is a supply role),
/// that role stays for the task: product words ("grocery", "catalogue",
/// "price", "online"), a generic "I want / కావాలి" or a guessed buy intent
/// never switch it back to Buyer. Only an explicit request to buy ("I want
/// to buy", "కొనాలి", "switch to buyer") or another role the user states
/// moves it.
AskodoxUserRole? askodoxContextRole({
  required AskodoxRoleDetection? spoken,
  required AskodoxUserRole? fromIntent,
  AskodoxUserRole? current,
}) {
  if (current != null && askodoxSupplyRoles.contains(current)) {
    if (spoken == null) return current;
    if (spoken.role == AskodoxUserRole.buyer) return spoken.explicitBuy ? AskodoxUserRole.buyer : current;
    return spoken.role;
  }
  if (spoken != null && spoken.role != AskodoxUserRole.buyer) return spoken.role;
  if (spoken?.role == AskodoxUserRole.buyer) return AskodoxUserRole.buyer;
  if (fromIntent != null && askodoxSupplyRoles.contains(fromIntent)) return null;
  return fromIntent;
}

/// True when the user is acting as a supplier right now and did not
/// explicitly ask to buy: their product words describe what they offer.
bool askodoxActsAsSupplier(AskodoxUserRole current, String text) =>
    askodoxSupplyRoles.contains(current) && !(askodoxDetectRole(text)?.explicitBuy ?? false);

/// Words a seller uses about their own shop: catalogue, stock, price list,
/// "my shop" ... (en / te / hi). Used with the active role, never alone.
bool askodoxSellerShopCue(String message) => RegExp(
      r'\b(catalog(ue)?s?|inventory|stock list|price ?list|my (shop|store|products|items|business)|'
      r'add (my )?(products|items)|list (my )?(products|items)|upload (my )?(products|items)|template)\b|'
      r'కేటలాగ్|కాటలాగ్|క్యాటలాగ్|స్టాక్|నా (షాప్|దుకాణం|కొట్టు)|ధరల జాబితా|'
      r'कैटलॉग|कॅटलॉग|सूची|स्टॉक|मेरी दुकान|रेट लिस्ट',
      caseSensitive: false,
    ).hasMatch(message);

class AskodoxRoleDetection {
  const AskodoxRoleDetection(this.role, {this.ambiguous = false, this.explicitBuy = false});
  final AskodoxUserRole role;

  /// The user explicitly asked to BUY ("I want to buy", "కొనాలి", "switch
  /// to buyer") -- a generic "I want / I need / కావాలి" is not enough to
  /// take a Seller out of their role.
  final bool explicitBuy;

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
    // "TV for sale near me" is a BUYER looking at sale listings; only "my
    // TV for sale" / "I have a bike for sale" describes a seller.
    r"\b(my|i have|i've got|i got) [a-z0-9 ]*for sale\b",
    r'అమ్మాలి',
    r'అమ్ముతున్నాను',
  ]);
  final explicitBuy = _any(text, [
    r'\b(want|need|going|like) to (buy|purchase|order)\b',
    r"\bi('ll| will| wanna) (buy|purchase|order)\b",
    r'\b(switch|change|go) (to|back to) buy(er|ing)\b',
    r"\b(as|i('m| am)) a buyer\b",
    r'\bbuyer mode\b',
    r'కొనాలి',
    r'కొంటాను',
    r'కొనుక్కోవాలి',
    r'खरीदना',
    r'ख़रीदना',
    r'खरीदूं',
  ]);
  final buyer = explicitBuy ||
      _any(text, [
        r'\bi (want|need)\b',
        r'\bbuy\b',
        r'కావాలి',
        r'चाहिए',
      ]);

  // Participation / trade roles, only from how people describe themselves.
  final participation = <AskodoxUserRole, List<String>>{
    AskodoxUserRole.farmer: [r"\bi('m| am) a farmer\b", r'\bi (grow|farm|harvest)\b', r'\bmy (farm|crop|harvest)\b', r'రైతుని', r'పండిస్తాను'],
    AskodoxUserRole.distributor: [r"\bi('m| am) a (distributor|wholesaler|stockist|dealer)\b", r'\bi (distribute|supply) (to|in bulk)\b'],
    AskodoxUserRole.influencer: [r"\bi('m| am) an? (influencer|youtuber|creator|blogger)\b", r'\bmy (followers|channel|subscribers)\b'],
    AskodoxUserRole.advisor: [r"\bi('m| am) an? (advisor|consultant)\b", r'\bi (advise|consult)\b'],
    AskodoxUserRole.agent: [r"\bi('m| am) an? (agent|broker|middleman|commission agent)\b", r'\bi (broker|arrange) deals\b', r'మధ్యవర్తి'],
    AskodoxUserRole.referrer: [r'\bi (want to )?(refer|recommend) (someone|a friend|him|her|them)\b'],
    AskodoxUserRole.partner: [r'\b(partner with|become a partner|partnership with) askodox\b'],
  };
  for (final entry in participation.entries) {
    // "I'm a farmer" states the role; softer hints ("my channel", "I
    // recommend him") are confirmed with a question, never switched silently.
    final explicit = RegExp(entry.value.first).hasMatch(text);
    if (explicit || _any(text, entry.value.skip(1).toList())) {
      return AskodoxRoleDetection(entry.key, ambiguous: text.contains('?') || !explicit);
    }
  }

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
  return AskodoxRoleDetection(role,
      ambiguous: question || mixed, explicitBuy: role == AskodoxUserRole.buyer && explicitBuy);
}

/// Supply-side switches change what ASKODOX does for the user (listing,
/// accepting requests), and leaving a supply role ends their seller task --
/// so an ambiguous hint asks before switching in either case.
bool askodoxRoleSwitchIsHighImpact(AskodoxUserRole to, {AskodoxUserRole? from}) =>
    to != AskodoxUserRole.buyer || (from != null && askodoxSupplyRoles.contains(from));

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
