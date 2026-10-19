import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/providers/backend_providers.dart';
import '../../home/domain/active_role.dart';
import '../../location/application/location_controller.dart';
import '../../../shared/widgets/askodox_guided_field.dart';
import '../../../shared/widgets/askodox_mascot.dart';
import '../../companion/relationship.dart';
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
              : async.error is AskodoxSessionInvalid ||
                      (ref.watch(authSessionProvider).tokenPlaceholder ?? '').isEmpty ||
                      ref.watch(authSessionProvider).tokenPlaceholder == 'OTP_VERIFIED'
                  ? Column(key: const Key('askodoxProfileSignInAgain'), children: [
                      Text(
                        _t('Please sign in again to see and edit your profile.',
                            'మీ ప్రొఫైల్ చూడడానికి మళ్లీ సైన్ ఇన్ చేయండి.'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      FilledButton(
                        onPressed: () => context.push('/onboarding?signin=1'),
                        child: Text(_t('Sign in', 'సైన్ ఇన్')),
                      ),
                    ])
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
    final active = ref.watch(askodoxRoleProvider).active;
    final relation = ref.watch(askodoxRelationProvider);
    return Card(
      key: const Key('askodoxProfileHeader'),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Compact: photo, name, current role, verified phone.
          Row(children: [
            GestureDetector(
              key: const Key('askodoxProfilePhoto'),
              onTap: _changePhoto,
              child: Stack(children: [
                CircleAvatar(
                  radius: 28,
                  backgroundImage: photo,
                  child: photo == null ? const Icon(Icons.person_rounded, size: 28) : null,
                ),
                const Positioned(
                  right: -2,
                  bottom: -2,
                  child: CircleAvatar(radius: 10, child: Icon(Icons.camera_alt_rounded, size: 12)),
                ),
              ]),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(profile.name ?? _t('Add your name', 'మీ పేరు ఇవ్వండి'),
                    key: const Key('askodoxProfileName'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                const SizedBox(height: 2),
                Text(askodoxUserRoleLabel(active, telugu: widget.telugu),
                    key: const Key('askodoxProfileActiveRole'),
                    style: const TextStyle(color: Color(0xFF1769FF), fontWeight: FontWeight.w800, fontSize: 13)),
              ]),
            ),
            Tooltip(
              message: askodoxGreeting(relation, telugu: widget.telugu),
              child: const AskodoxMascot(size: 34),
            ),
            IconButton(
              key: const Key('askodoxProfileEdit'),
              tooltip: _t('Edit profile', 'ప్రొఫైల్ మార్చండి'),
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _edit(profile),
            ),
          ]),
          // Everything else only on demand.
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              key: const Key('askodoxPersonalDetails'),
              tilePadding: const EdgeInsets.only(right: 8),
              childrenPadding: const EdgeInsets.only(right: 8, bottom: 6),
              dense: true,
              visualDensity: VisualDensity.compact,
              title: Text(_t('Personal details', 'వ్యక్తిగత వివరాలు'),
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
              children: [
                if (profile.mobile != null)
                  _row(Icons.phone_iphone_rounded, _t('Phone', 'ఫోన్'), '${profile.mobile!}  ✓ ${_t('verified', 'ధృవీకరించబడింది')}',
                      key: const Key('askodoxProfileMobile')),
                _row(Icons.mail_outline_rounded, _t('E-mail', 'ఈ-మెయిల్'), profile.email),
                _row(Icons.home_outlined, _t('Address', 'చిరునామా'), place, key: const Key('askodoxProfileAddress')),
                for (final (i, d) in profile.deliveryAddresses.indexed)
                  Row(key: ValueKey('askodoxDeliveryAddress-$i'), children: [
                    Expanded(
                      child: _row(Icons.local_shipping_outlined,
                          d['label']!.isEmpty ? _t('Delivery', 'డెలివరీ') : d['label']!, d['address']),
                    ),
                    IconButton(
                      key: ValueKey('askodoxDeliveryAddressRemove-$i'),
                      tooltip: _t('Remove', 'తీసేయండి'),
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () => _removeDeliveryAddress(profile, i),
                    ),
                  ]),
                if (profile.deliveryAddresses.length < 5)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const Key('askodoxAddDeliveryAddress'),
                      icon: const Icon(Icons.add_location_alt_outlined, size: 18),
                      label: Text(_t('Add a delivery address', 'డెలివరీ చిరునామా జోడించండి')),
                      onPressed: () => _addDeliveryAddress(profile),
                    ),
                  ),
                _row(Icons.translate_rounded, _t('Language', 'భాష'), switch (profile.language) {
                  'te' => 'తెలుగు',
                  'hi' => 'हिन्दी',
                  'en' => 'English',
                  'or' => 'ଓଡ଼ିଆ',
                  _ => null,
                }),
                InkWell(
                  key: const Key('askodoxRelationPicker'),
                  onTap: _pickRelation,
                  child: _row(Icons.favorite_border_rounded, _t('ASKO calls you', 'ASKO మిమ్మల్ని పిలిచేది'),
                      askodoxCallName(relation, telugu: widget.telugu)),
                ),
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
              ],
            ),
          ),
          if (_message != null)
            Text(_message!, style: const TextStyle(color: Color(0xFFB42318))),
        ]),
      ),
    );
  }

  /// ASKO's way of calling this person (one character; only the address changes).
  Future<void> _pickRelation() async {
    final current = ref.read(askodoxRelationProvider);
    final picked = await showModalBottomSheet<AskodoxRelation>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const AskodoxMascot(size: 44),
              const SizedBox(width: 10),
              Expanded(
                child: Text(_t('How should ASKO call you?', 'ASKO మిమ్మల్ని ఎలా పిలవాలి?'),
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              ),
            ]),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final r in AskodoxRelation.values)
                ChoiceChip(
                  key: ValueKey('askodoxRelation-${r.name}'),
                  selected: r == current,
                  label: Text(widget.telugu ? askodoxRelations[r]!.labelTe : askodoxRelations[r]!.labelEn),
                  onSelected: (_) => Navigator.pop(sheet, r),
                ),
            ]),
          ]),
        ),
      ),
    );
    if (picked != null) await ref.read(askodoxRelationProvider.notifier).choose(picked);
  }

  Future<bool> _confirm(String question) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          content: Text(question),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialog, false), child: Text(_t('Cancel', 'రద్దు'))),
            FilledButton(
                key: const Key('askodoxConfirmYes'),
                onPressed: () => Navigator.pop(dialog, true),
                child: Text(_t('Yes, save', 'అవును, సేవ్ చేయండి'))),
          ],
        ),
      ) ??
      false;

  Future<void> _addDeliveryAddress(AskodoxUserProfile profile) async {
    final label = TextEditingController();
    final address = TextEditingController();
    final add = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(sheet).bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(_t('Add a delivery address', 'డెలివరీ చిరునామా జోడించండి'),
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          AskodoxGuidedField(
              fieldKey: const Key('askodoxDeliveryLabel'),
              controller: label,
              label: _t('Name for it', 'దానికి పేరు'),
              guide: AskodoxFieldGuides.addressLabel),
          AskodoxGuidedField(
              fieldKey: const Key('askodoxDeliveryAddressField'),
              controller: address,
              label: _t('Address', 'చిరునామా'),
              maxLines: 2,
              minLines: 1,
              guide: AskodoxFieldGuides.shopAddress),
          const SizedBox(height: 12),
          FilledButton(
              key: const Key('askodoxDeliveryAddressSave'),
              onPressed: () => Navigator.pop(sheet, true),
              child: Text(_t('Add', 'జోడించు'))),
        ]),
      ),
    );
    if (add != true || address.text.trim().length < 3 || !mounted) return;
    final next = [
      ...profile.deliveryAddresses,
      {'label': label.text.trim(), 'address': address.text.trim()},
    ];
    final ok = await ref.read(askodoxUserProfileProvider.notifier).save({'delivery_addresses': next});
    if (mounted && !ok) setState(() => _message = _t('Could not save. Try again.', 'సేవ్ కాలేదు. మళ్లీ ప్రయత్నించండి.'));
  }

  Future<void> _removeDeliveryAddress(AskodoxUserProfile profile, int index) async {
    final item = profile.deliveryAddresses[index];
    if (!await _confirm(_t('Remove "${item['address']}"?', '"${item['address']}" తీసేయాలా?')) || !mounted) return;
    final next = [...profile.deliveryAddresses]..removeAt(index);
    await ref.read(askodoxUserProfileProvider.notifier).save({'delivery_addresses': next});
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
  late final _email = TextEditingController(text: widget.profile.email ?? '');
  late final Map<String, TextEditingController> _links = {
    for (final kind in const ['website', 'whatsapp', 'instagram'])
      kind: TextEditingController(
          text: widget.profile.links.where((l) => l['kind'] == kind).map((l) => l['url']).firstOrNull ?? ''),
  };

  /// Role-specific fields for every role this person holds (one profile).
  late final Map<String, Map<String, TextEditingController>> _roleFields = {
    for (final role in ref.read(askodoxRoleProvider).owned.map((r) => askodoxRoleKey(r.name)))
      if (askodoxRoleProfileFields[role] case final fields?)
        role: {
          for (final f in fields)
            f: TextEditingController(text: _text(widget.profile.roleDetails[role]?[f])),
        },
  };
  bool _saving = false;
  String? _error;

  static String _text(Object? v) => v is List ? v.join(', ') : (v == null ? '' : '$v');

  String _t(String en, String te) => widget.telugu ? te : en;

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final email = _email.text.trim();
    if (email.isNotEmpty && !RegExp(r'^[^@\s]+@[^@\s]+\.[a-zA-Z]{2,}$').hasMatch(email)) {
      setState(() {
        _saving = false;
        _error = _t('Enter a valid e-mail address.', 'సరైన ఈ-మెయిల్ ఇవ్వండి.');
      });
      return;
    }
    final ok = await ref.read(askodoxUserProfileProvider.notifier).save({
      'name': _name.text.trim(),
      'address': _address.text.trim(),
      'email': email,
      'links': [
        for (final e in _links.entries)
          if (e.value.text.trim().isNotEmpty) {'kind': e.key, 'url': e.value.text.trim()},
      ],
      if (_roleFields.isNotEmpty)
        'role_details': {
          for (final r in _roleFields.entries)
            r.key: {for (final f in r.value.entries) f.key: f.value.text.trim()},
        },
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
              AskodoxGuidedField(fieldKey: const Key('askodoxEditName'), controller: _name,
                  label: _t('Name', 'పేరు'), guide: AskodoxFieldGuides.name),
              AskodoxGuidedField(fieldKey: const Key('askodoxEditAddress'), controller: _address,
                  label: _t('Address (town, area)', 'చిరునామా (ఊరు, ప్రాంతం)'), guide: AskodoxFieldGuides.town),
              AskodoxGuidedField(fieldKey: const Key('askodoxEditEmail'), controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  label: _t('E-mail (optional)', 'ఈ-మెయిల్ (ఐచ్ఛికం)'), guide: AskodoxFieldGuides.email),
              for (final e in _links.entries)
                TextField(key: ValueKey('askodoxEditLink-${e.key}'), controller: e.value,
                    decoration: InputDecoration(
                        labelText: switch (e.key) {
                          'website' => _t('Website (https://…)', 'వెబ్‌సైట్ (https://…)'),
                          'whatsapp' => 'WhatsApp',
                          _ => 'Instagram (https://…)',
                        })),
              if (widget.business) ...[
                AskodoxGuidedField(fieldKey: const Key('askodoxEditShop'), controller: _shop,
                    label: _t('Business / shop name', 'వ్యాపారం / షాప్ పేరు'), guide: AskodoxFieldGuides.shopName),
                AskodoxGuidedField(fieldKey: const Key('askodoxEditShopAddress'), controller: _shopAddress,
                    label: _t('Shop address', 'షాప్ చిరునామా'), guide: AskodoxFieldGuides.shopAddress),
                AskodoxGuidedField(fieldKey: const Key('askodoxEditCategory'), controller: _category,
                    label: _t('Category / service', 'విభాగం / సర్వీస్'), guide: AskodoxFieldGuides.category),
                AskodoxGuidedField(fieldKey: const Key('askodoxEditGstin'), controller: _gstin,
                    label: 'GSTIN (optional)', guide: AskodoxFieldGuides.gstin),
              ],
              for (final r in _roleFields.entries) ...[
                const SizedBox(height: 14),
                Text(askodoxFieldLabel(r.key),
                    key: ValueKey('askodoxEditRole-${r.key}'),
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                for (final f in r.value.entries)
                  TextField(key: ValueKey('askodoxEditRole-${r.key}-${f.key}'), controller: f.value,
                      decoration: InputDecoration(labelText: askodoxFieldLabel(f.key))),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!, key: const Key('askodoxEditError'),
                      style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w700)),
                ),
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
