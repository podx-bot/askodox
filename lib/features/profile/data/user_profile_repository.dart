import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_models.dart';
import '../../../core/providers/backend_providers.dart';

/// The signed-in user's ONE stored profile (GET/PUT /api/me/profile).
/// Nothing here is invented: an empty field stays empty.
class AskodoxUserProfile {
  const AskodoxUserProfile({
    required this.userId,
    this.name,
    this.mobile,
    this.address,
    this.latitude,
    this.longitude,
    this.language,
    this.roles = const [],
    this.businessName,
    this.businessAddress,
    this.businessCategory,
    this.gstin,
    this.hasPhoto = false,
    this.photoVersion,
    this.verificationStatus,
    this.sellerTier,
    this.listings = 0,
    this.email,
    this.activeRole,
    this.links = const [],
    this.roleDetails = const {},
  });

  final String? email;

  /// The role the person explicitly chose to act in (one of [roles]).
  final String? activeRole;

  /// Optional contact / social links: {kind, url}.
  final List<Map<String, String>> links;

  /// Per-role extension of this ONE profile (snake_case role key -> fields),
  /// e.g. seller.business_type, delivery_partner.vehicle_type.
  final Map<String, Map<String, Object?>> roleDetails;

  final String userId;
  final String? name;
  final String? mobile;
  final String? address;
  final double? latitude;
  final double? longitude;
  final String? language;
  final List<String> roles;
  final String? businessName;
  final String? businessAddress;
  final String? businessCategory;
  final String? gstin;
  final bool hasPhoto;
  final String? photoVersion;

  /// not_a_seller | unverified | business_verified (read-only, server side)
  final String? verificationStatus;
  final String? sellerTier;
  final int listings;

  static String? _s(Object? v) {
    final text = '${v ?? ''}'.trim();
    return text.isEmpty || text == 'null' ? null : text;
  }

  factory AskodoxUserProfile.fromJson(Map<String, Object?> json) {
    final verification = json['verification'] is Map ? Map<String, Object?>.from(json['verification'] as Map) : const {};
    return AskodoxUserProfile(
      userId: '${json['user_id'] ?? ''}',
      name: _s(json['name']),
      mobile: _s(json['mobile']),
      address: _s(json['address']),
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      language: _s(json['language']),
      roles: [for (final r in (json['roles'] as List? ?? const [])) '$r'],
      businessName: _s(json['business_name']),
      businessAddress: _s(json['business_address']),
      businessCategory: _s(json['business_category']),
      gstin: _s(json['gstin']),
      hasPhoto: json['has_photo'] == true,
      photoVersion: _s(json['photo_updated_at']),
      verificationStatus: _s(verification['status']),
      sellerTier: _s(verification['tier']),
      listings: (verification['listings'] as num?)?.toInt() ?? 0,
      email: _s(json['email']),
      activeRole: _s(json['active_role']),
      links: [
        for (final l in (json['links'] as List? ?? const []))
          if (l is Map) {'kind': '${l['kind'] ?? 'other'}', 'url': '${l['url'] ?? ''}'},
      ],
      roleDetails: {
        if (json['role_details'] is Map)
          for (final e in (json['role_details'] as Map).entries)
            if (e.value is Map) '${e.key}': Map<String, Object?>.from(e.value as Map),
      },
    );
  }
}

class AskodoxUserProfileRepository {
  const AskodoxUserProfileRepository(this._client, {this.authToken});

  final ApiClient _client;
  final String? authToken;

  ApiRequestOptions get _auth => ApiRequestOptions(authToken: authToken);

  Future<AskodoxUserProfile?> load() async {
    if (authToken == null || authToken!.isEmpty) return null;
    final result = await _client.get<Map<String, Object?>>('/api/me/profile', options: _auth);
    return result is ApiSuccess<Map<String, Object?>> ? AskodoxUserProfile.fromJson(result.data) : null;
  }

  Future<AskodoxUserProfile?> save(Map<String, Object?> fields) async {
    if (authToken == null || authToken!.isEmpty) return null;
    final result = await _client.put<Map<String, Object?>>('/api/me/profile', body: fields, options: _auth);
    return result is ApiSuccess<Map<String, Object?>> ? AskodoxUserProfile.fromJson(result.data) : null;
  }

  Future<AskodoxUserProfile?> setPhoto(Uint8List? jpeg) async {
    if (authToken == null || authToken!.isEmpty) return null;
    final ApiResult<Map<String, Object?>> result = jpeg == null
        ? await _client.delete<Map<String, Object?>>('/api/me/profile/photo', options: _auth)
        : await _client.put<Map<String, Object?>>('/api/me/profile/photo',
            body: {'photo_base64': base64Encode(jpeg)}, options: _auth);
    return result is ApiSuccess<Map<String, Object?>> ? AskodoxUserProfile.fromJson(result.data) : null;
  }
}

final askodoxUserProfileRepositoryProvider = Provider<AskodoxUserProfileRepository>((ref) {
  final session = ref.watch(authSessionProvider);
  return AskodoxUserProfileRepository(ref.watch(apiClientProvider),
      authToken: session.user == null ? null : session.tokenPlaceholder);
});

/// The profile every screen reads (Home, Chat, selling, Profile). Reloads
/// when the signed-in user changes; edits update it everywhere at once.
class AskodoxUserProfileController extends AsyncNotifier<AskodoxUserProfile?> {
  @override
  Future<AskodoxUserProfile?> build() => ref.watch(askodoxUserProfileRepositoryProvider).load();

  Future<bool> save(Map<String, Object?> fields) async {
    final saved = await ref.read(askodoxUserProfileRepositoryProvider).save(fields);
    if (saved != null) state = AsyncData(saved);
    return saved != null;
  }

  Future<bool> setPhoto(Uint8List? jpeg) async {
    final saved = await ref.read(askodoxUserProfileRepositoryProvider).setPhoto(jpeg);
    if (saved != null) state = AsyncData(saved);
    return saved != null;
  }
}

final askodoxUserProfileProvider =
    AsyncNotifierProvider<AskodoxUserProfileController, AskodoxUserProfile?>(AskodoxUserProfileController.new);

/// Fields each role adds to the master profile (mirrors the backend's
/// ROLE_FIELDS; the server drops anything else). Labels are English keys
/// shown with the role's own label.
const askodoxRoleProfileFields = <String, List<String>>{
  'seller': ['business_type', 'description', 'service_area_km', 'working_hours', 'catalog_note'],
  'service_provider': ['services', 'categories', 'service_area_km', 'availability', 'pricing', 'experience'],
  'job_seeker': ['skills', 'experience', 'preferred_locations', 'availability', 'expected_pay'],
  'delivery_partner': ['service_types', 'availability', 'operating_area', 'vehicle_type', 'vehicle_number'],
};

/// camelCase app role name -> the profile's snake_case role key.
String askodoxRoleKey(String roleName) =>
    roleName.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}');

String askodoxFieldLabel(String key) {
  final words = key.replaceAll('_km', ' (km)').replaceAll('_', ' ');
  return words[0].toUpperCase() + words.substring(1);
}
