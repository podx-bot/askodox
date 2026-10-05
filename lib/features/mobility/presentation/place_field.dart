import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../growth/data/growth_repository.dart';
import '../../location/application/location_controller.dart';
import '../../location/domain/geo_models.dart';
import '../../location/presentation/map_pin_picker.dart';

/// A From / To place: type to search (suggestions as you type), use my
/// current location, pick on the map, or tap a recent place. The chosen
/// place carries coordinates; typed text alone is resolved by the backend.
class AskodoxPlaceField extends ConsumerStatefulWidget {
  const AskodoxPlaceField({
    super.key,
    required this.fieldKey,
    required this.label,
    required this.icon,
    required this.te,
    required this.value,
    required this.onChanged,
    this.allowCurrent = false,
  });

  final String fieldKey;
  final String label;
  final IconData icon;
  final bool te;
  final AskodoxPlace? value;
  final ValueChanged<AskodoxPlace?> onChanged;
  final bool allowCurrent;

  @override
  ConsumerState<AskodoxPlaceField> createState() => _AskodoxPlaceFieldState();
}

class _AskodoxPlaceFieldState extends ConsumerState<AskodoxPlaceField> {
  late final TextEditingController _text = TextEditingController(text: widget.value?.label ?? '');
  final _focus = FocusNode();
  List<AskodoxPlace> _suggestions = const [];
  List<BuyerSavedLocation> _recent = const [];
  Timer? _debounce;
  int _query = 0;
  bool _searching = false;

  String t(String en, String te) => widget.te ? te : en;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() async {
      if (_focus.hasFocus && _recent.isEmpty) {
        final recent = await ref.read(locationControllerProvider.notifier).recentPlaces();
        if (mounted) setState(() => _recent = recent);
      } else if (!_focus.hasFocus && mounted) {
        setState(() {});
      }
    });
  }

  @override
  void didUpdateWidget(AskodoxPlaceField old) {
    super.didUpdateWidget(old);
    final label = widget.value?.label ?? '';
    if (widget.value != old.value && label != _text.text) _text.text = label;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _typed(String value) {
    // Typed text is a place too (resolved server-side) until one is chosen.
    widget.onChanged(value.trim().isEmpty ? null : AskodoxPlace(latitude: 0, longitude: 0, label: value.trim()));
    _debounce?.cancel();
    if (value.trim().length < 3) {
      setState(() => _suggestions = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(value.trim()));
  }

  Future<void> _search(String query) async {
    final id = ++_query;
    setState(() => _searching = true);
    final centre = ref.read(locationControllerProvider).defaultLocation?.point;
    List<AskodoxPlace> found;
    try {
      found = await ref
          .read(growthRepositoryProvider)
          .searchPlaces(query, latitude: centre?.latitude, longitude: centre?.longitude);
    } catch (_) {
      found = const [];
    }
    if (!mounted || id != _query) return;
    setState(() {
      _searching = false;
      _suggestions = found.take(5).toList();
    });
  }

  void _choose(AskodoxPlace place) {
    _debounce?.cancel();
    _query++;
    _text.text = place.label;
    setState(() {
      _suggestions = const [];
      _searching = false;
    });
    _focus.unfocus();
    widget.onChanged(place);
  }

  void _useCurrent() {
    final loc = ref.read(locationControllerProvider);
    if (!loc.hasPlace) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t('Set your location first (Profile → Location), or type a place.',
              'ముందు మీ లొకేషన్ సెట్ చేయండి (ప్రొఫైల్ → లొకేషన్), లేదా ప్రాంతం టైప్ చేయండి.'))));
      return;
    }
    _choose(AskodoxPlace(
        latitude: loc.centre.latitude,
        longitude: loc.centre.longitude,
        label: loc.displayLocation ?? t('Current location', 'ప్రస్తుత లొకేషన్')));
  }

  Future<void> _map() async {
    final v = widget.value;
    final place = await AskodoxMapPinPicker.open(context,
        title: widget.label, initial: v != null && (v.latitude != 0 || v.longitude != 0) ? v : null);
    if (place != null && mounted) _choose(place);
  }

  @override
  Widget build(BuildContext context) {
    final showRecent = _focus.hasFocus && _text.text.trim().isEmpty && _recent.isNotEmpty;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        key: ValueKey(widget.fieldKey),
        controller: _text,
        focusNode: _focus,
        onChanged: _typed,
        textInputAction: TextInputAction.search,
        onSubmitted: (v) {
          if (v.trim().length >= 2) _search(v.trim());
        },
        decoration: InputDecoration(
          labelText: widget.label,
          prefixIcon: Icon(widget.icon),
          suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
            if (_searching)
              const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))),
            if (widget.allowCurrent)
              IconButton(
                  key: ValueKey('${widget.fieldKey}-current'),
                  tooltip: t('My location', 'నా లొకేషన్'),
                  icon: const Icon(Icons.my_location_rounded),
                  onPressed: _useCurrent),
            IconButton(
                key: ValueKey('${widget.fieldKey}-map'),
                tooltip: t('Pick on map', 'మ్యాప్‌లో ఎంచుకోండి'),
                icon: const Icon(Icons.map_outlined),
                onPressed: _map),
          ]),
        ),
      ),
      for (final p in _suggestions)
        ListTile(
          key: ValueKey('${widget.fieldKey}-suggest-${p.label}'),
          dense: true,
          leading: const Icon(Icons.place_outlined, size: 20),
          title: Text(p.label, maxLines: 2, overflow: TextOverflow.ellipsis),
          onTap: () => _choose(p),
        ),
      if (showRecent)
        for (final r in _recent.take(4))
          ListTile(
            key: ValueKey('${widget.fieldKey}-recent-${r.id}'),
            dense: true,
            leading: const Icon(Icons.history_rounded, size: 20),
            title: Text(r.address.isNotEmpty ? r.address : r.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () => _choose(AskodoxPlace(
                latitude: r.point.latitude,
                longitude: r.point.longitude,
                label: r.address.isNotEmpty ? r.address : r.name)),
          ),
    ]);
  }
}
