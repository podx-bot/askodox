import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/providers/backend_providers.dart';
import '../../home/domain/active_role.dart';
import '../../location/application/location_controller.dart';
import '../data/user_profile_repository.dart';

/// The top of Profile: the signed-in user's OWN stored data (photo, name,
/// mobile, address, language, roles, business details and verification) --
/// nothing hard-coded. Edits go to the one stored profile and every screen
/// reading [askodoxUserProfileProvider] updates.
class AskodoxProfileHeader extends ConsumerStatefulWidget {
  const AskodoxProfileHeader({super.key, required this.telugu, this.pickPhoto});

  final bool telugu;

  /// Injectable photo source (tests); defaults to the gallery/camera picker.
  final Future<List<int>?> Function(ImageSource source)? pickPhoto;

  @override
  ConsumerState<AskodoxProfileHeader> createState() => _AskodoxProfileHeaderState();
}

class _AskodoxProfileHeaderState extends ConsumerState<AskodoxProfileHeader> {
  bool _synced = false;
  String? _message;

  String _t(String en, String te) => widget.telugu ? te : en;

  /// First load after sign-in: values the user already gave on this phone
  /// (the name typed at sign-up, the app language, held roles) go to the
  /// stored profile once, when it does not have them yet.
  void _syncOnce(AskodoxUserProfile profile) {
    if (_synced) return;
    _synced = true;
    final local = ref.read(authSessionProvider).user?.displayName?.trim() ?? '';
    final roles = ref.read(askodoxRoleProvider).owned.map((r) => r.name).toList()..sort();
    final fields = <String, Object?>{
      if (profile.name == null && local.isNotEmpty && !local.startsWith('Demo ')) 'name': local,
      if (profile.language == null) 'language': Localizations.localeOf(context).languageCode,
      if (profile.roles.isEmpty && roles.isNotEmpty) 'roles': roles,
    };
    if (fields.isNotEmpty) unawaited(ref.read(askodoxUserProfileProvider.notifier).save(fields));
  }

  Future<void> _changePhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: Text(_t('Take a photo', 'ఫోటో తీయండి')),
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: Text(_t('Choose from Photos', 'ఫోటోల నుండి ఎంచుకోండి')),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
        ]),
      ),
    );
    if (source == null) return;
    final bytes = await (widget.pickPhoto ??
        (s) async {
          final file = await ImagePicker().pickImage(source: s, maxWidth: 512, maxHeight: 512, imageQuality: 80);
          return file?.readAsBytes();
        })(source);
    if (bytes == null || !mounted) return;
    final ok = await ref.read(askodoxUserProfileProvider.notifier).setPhoto(Uint8List.fromList(bytes));
    if (mounted) setState(() => _message = ok ? null : _t('The photo could not be saved.', 'ఫోటో సేవ్ కాలేదు.'));
  }

  Future<void> _edit(AskodoxUserProfile profile) async {
    final sells = ref.read(askodoxRoleProvider).owned.any(askodoxSupplyRoles.contains) ||
        profile.businessName != null;
    final place = ref.read(locationControllerProvider).displayLocation;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ProfileEditSheet(profile: profile, telugu: widget.telugu, business: sells, currentPlace: place),
    );
    if (saved == false && mounted) {
      setState(() => _message = _t('Your profile could not be saved. Try again.', 'ప్రొఫైల్ సేవ్ కాలేదు. మళ్లీ ప్రయత్నించండి.'));
    }
  }

  Widget _row(IconData icon, String label, String? value, {Key? key}) => Padding(
        key: key,
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: const Color(0xFF64748B)),
          const SizedBox(width: 8),
          SizedBox(width: 92, child: Text(label, style: const TextStyle(color: Color(0xFF64748B)))),
          Expanded(
            child: Text(value ?? _t('Not added', 'ఇవ్వలేదు'),
                style: TextStyle(
                    fontWeight: value == null ? FontWeight.w400 : FontWeight.w700,
                    color: value == null ? const Color(0xFF94A3B8) : null)),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    if (ref.watch(authSessionProvider).user == null) {
      return Column(children: [
        const CircleAvatar(radius: 42, child: Icon(Icons.person_rounded, size: 42)),
        const SizedBox(height: 10),
        Text(_t('Your ASKODOX profile', 'మీ ASKODOX ప్రొఫైల్'),
            textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
      ]);
    }
    final async = ref.watch(askodoxUserProfileProvider);
    final profile = async.valueOrNull;
    if (profile == null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: async.isLoading
              ? const CircularProgressIndicator()
              : Column(children: [
                  Text(_t('Your profile could not be loaded.', 'ప్రొఫైల్ లోడ్ కాలేదు.')),
                  TextButton(
                    onPressed: () => ref.invalidate(askodoxUserProfileProvider),
                    child: Text(_t('Retry', 'మళ్లీ ప్రయత్నించండి')),
                  ),
                ]),
        ),
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncOnce(profile);
    });
    final config = ref.watch(appConfigProvider);
    final token = ref.watch(authSessionProvider).tokenPlaceholder;
    final base = config.apiBaseUrl;
    final photo = profile.hasPhoto && base != null
        ? NetworkImage(
            base.resolve('/api/me/profile/photo?v=${Uri.encodeQueryComponent(profile.photoVersion ?? '')}').toString(),
            headers: {if (token != null) 'Authorization': 'Bearer $token'},
          )
        : null;
    final roles = ref.watch(askodoxRoleProvider).owned;
    final sells = roles.any(askodoxSupplyRoles.contains) || profile.businessName != null;
    final place = profile.address ?? ref.watch(locationControllerProvider).displayLocation;
    return Card(
      key: const Key('askodoxProfileHeader'),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            GestureDetector(
              key: const Key('askodoxProfilePhoto'),
              onTap: _changePhoto,
              child: Stack(children: [
                CircleAvatar(
                  radius: 38,
                  backgroundImage: photo,
                  child: photo == null ? const Icon(Icons.person_rounded, size: 38) : null,
                ),
                const Positioned(
                  right: 0,
                  bottom: 0,
                  child: CircleAvatar(radius: 12, child: Icon(Icons.camera_alt_rounded, size: 14)),
                ),
              ]),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(profile.name ?? _t('Add your name', 'మీ పేరు ఇవ్వండి'),
                    key: const Key('askodoxProfileName'),
                    style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
                if (profile.mobile != null)
                  Text(profile.mobile!, key: const Key('askodoxProfileMobile'),
                      style: const TextStyle(color: Color(0xFF64748B))),
              ]),
            ),
            IconButton(
              key: const Key('askodoxProfileEdit'),
              tooltip: _t('Edit profile', 'ప్రొఫైల్ మార్చండి'),
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _edit(profile),
            ),
          ]),
          const SizedBox(height: 10),
          _row(Icons.home_outlined, _t('Address', 'చిరునామా'), place, key: const Key('askodoxProfileAddress')),
          _row(Icons.translate_rounded, _t('Language', 'భాష'), switch (profile.language) {
            'te' => 'తెలుగు',
            'hi' => 'हिन्दी',
            'en' => 'English',
            'or' => 'ଓଡ଼ିଆ',
            _ => null,
          }),
          _row(Icons.badge_outlined, _t('Roles', 'పాత్రలు'),
              roles.isEmpty ? null : roles.map((r) => askodoxUserRoleLabel(r, telugu: widget.telugu)).join(', ')),
          if (sells) ...[
            const Divider(),
            _row(Icons.storefront_outlined, _t('Business', 'వ్యాపారం'), profile.businessName,
                key: const Key('askodoxProfileBusiness')),
            _row(Icons.place_outlined, _t('Shop address', 'షాప్ చిరునామా'), profile.businessAddress),
            _row(Icons.category_outlined, _t('Category', 'విభాగం'), profile.businessCategory),
            _row(
              Icons.verified_outlined,
              _t('Verification', 'ధృవీకరణ'),
              switch (profile.verificationStatus) {
                'business_verified' => _t('GSTIN on file (business)', 'GSTIN ఉంది (వ్యాపారం)'),
                'unverified' => _t('Not verified yet', 'ఇంకా ధృవీకరించలేదు'),
                _ => null,
              },
              key: const Key('askodoxProfileVerification'),
            ),
            if (profile.listings > 0)
              _row(Icons.inventory_2_outlined, _t('Listings', 'లిస్టింగ్‌లు'), '${profile.listings}'),
          ],
          if (_message != null)
            Text(_message!, style: const TextStyle(color: Color(0xFFB42318))),
        ]),
      ),
    );
  }
}

class _ProfileEditSheet extends ConsumerStatefulWidget {
  const _ProfileEditSheet({required this.profile, required this.telugu, required this.business, this.currentPlace});

  final AskodoxUserProfile profile;
  final bool telugu;
  final bool business;
  final String? currentPlace;

  @override
  ConsumerState<_ProfileEditSheet> createState() => _ProfileEditSheetState();
}

class _ProfileEditSheetState extends ConsumerState<_ProfileEditSheet> {
  late final _name = TextEditingController(text: widget.profile.name ?? '');
  late final _address = TextEditingController(text: widget.profile.address ?? widget.currentPlace ?? '');
  late final _shop = TextEditingController(text: widget.profile.businessName ?? '');
  late final _shopAddress = TextEditingController(text: widget.profile.businessAddress ?? '');
  late final _category = TextEditingController(text: widget.profile.businessCategory ?? '');
  late final _gstin = TextEditingController(text: widget.profile.gstin ?? '');
  bool _saving = false;

  String _t(String en, String te) => widget.telugu ? te : en;

  Future<void> _save() async {
    setState(() => _saving = true);
    final ok = await ref.read(askodoxUserProfileProvider.notifier).save({
      'name': _name.text.trim(),
      'address': _address.text.trim(),
      if (widget.business) ...{
        'business_name': _shop.text.trim(),
        'business_address': _shopAddress.text.trim(),
        'business_category': _category.text.trim(),
        if (_gstin.text.trim().isNotEmpty) 'gstin': _gstin.text.trim(),
      },
    });
    if (mounted) Navigator.pop(context, ok);
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_t('Edit profile', 'ప్రొఫైల్ మార్చండి'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              TextField(key: const Key('askodoxEditName'), controller: _name,
                  decoration: InputDecoration(labelText: _t('Name', 'పేరు'))),
              TextField(key: const Key('askodoxEditAddress'), controller: _address,
                  decoration: InputDecoration(labelText: _t('Address', 'చిరునామా'))),
              if (widget.business) ...[
                TextField(key: const Key('askodoxEditShop'), controller: _shop,
                    decoration: InputDecoration(labelText: _t('Business / shop name', 'వ్యాపారం / షాప్ పేరు'))),
                TextField(controller: _shopAddress,
                    decoration: InputDecoration(labelText: _t('Shop address', 'షాప్ చిరునామా'))),
                TextField(controller: _category,
                    decoration: InputDecoration(labelText: _t('Category / service', 'విభాగం / సర్వీస్'))),
                TextField(controller: _gstin, decoration: const InputDecoration(labelText: 'GSTIN (optional)')),
              ],
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  key: const Key('askodoxEditSave'),
                  onPressed: _saving ? null : _save,
                  child: Text(_t('Save', 'సేవ్ చేయండి')),
                ),
              ),
            ]),
          ),
        ),
      );
}
