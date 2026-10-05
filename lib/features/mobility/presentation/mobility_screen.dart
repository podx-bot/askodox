import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/backend_providers.dart';
import '../../growth/data/growth_repository.dart';
import '../../location/application/location_controller.dart';
import 'package:url_launcher/url_launcher.dart';

import '../application/mobility_draft.dart';
import '../data/mobility_repository.dart';
import 'place_field.dart';

/// Rides, parcels, carpool and the partner (driver / delivery) workspace --
/// one screen on top of ONE backend (`/api/delivery`). Every status shown is
/// the backend's own: a request is never shown as confirmed until a partner
/// accepts, and phones appear only after acceptance.
class MobilityScreen extends ConsumerStatefulWidget {
  const MobilityScreen({super.key, this.initialTab = 0, this.initialKind, this.initialFrom, this.initialTo});
  final int initialTab;

  /// Pre-fill from the chat (`/mobility?kind=&from=&to=`); the shared
  /// [askodoxMobilityDraftProvider] carries the coordinates.
  final String? initialKind;
  final String? initialFrom;
  final String? initialTo;

  @override
  ConsumerState<MobilityScreen> createState() => _MobilityScreenState();
}

const askodoxRideKinds = ['ride_auto', 'ride_bike', 'ride_taxi', 'ride_airport', 'ride_outstation', 'driver_only'];
const askodoxSendKinds = ['parcel', 'documents', 'local_delivery', 'pickup_drop'];

String askodoxKindLabel(String kind, bool te) => switch (kind) {
      'ride_auto' => te ? 'ఆటో' : 'Auto',
      'ride_bike' => te ? 'బైక్ టాక్సీ' : 'Bike taxi',
      'ride_taxi' => te ? 'టాక్సీ / కార్' : 'Taxi / car',
      'ride_airport' => te ? 'ఎయిర్‌పోర్ట్' : 'Airport',
      'ride_outstation' => te ? 'ఔట్‌స్టేషన్' : 'Outstation',
      'driver_only' => te ? 'డ్రైవర్ మాత్రమే' : 'Driver only',
      'parcel' => te ? 'పార్సెల్' : 'Parcel',
      'documents' => te ? 'డాక్యుమెంట్లు' : 'Documents',
      'local_delivery' => te ? 'లోకల్ డెలివరీ' : 'Local delivery',
      'pickup_drop' => te ? 'పికప్ & డ్రాప్' : 'Pickup & drop',
      'food' => te ? 'ఫుడ్' : 'Food',
      'grocery' => te ? 'కిరాణా' : 'Grocery',
      'product' => te ? 'ప్రొడక్ట్ డెలివరీ' : 'Product delivery',
      _ => kind,
    };

class _MobilityScreenState extends ConsumerState<MobilityScreen> {
  bool get _te => Localizations.localeOf(context).languageCode == 'te';
  String t(String en, String te) => _te ? te : en;

  @override
  Widget build(BuildContext context) {
    final signedIn = ref.watch(authSessionProvider).user != null;
    return DefaultTabController(
      length: 4,
      initialIndex: widget.initialTab.clamp(0, 3),
      child: Scaffold(
        appBar: AppBar(
          title: Text(t('Rides & deliveries', 'రైడ్స్ & డెలివరీలు')),
          bottom: TabBar(isScrollable: true, tabs: [
            Tab(text: t('Book', 'బుక్')),
            Tab(text: t('My trips', 'నా ట్రిప్స్')),
            Tab(text: t('Carpool', 'కార్‌పూల్')),
            Tab(text: t('Drive / deliver', 'డ్రైవ్ / డెలివర్')),
          ]),
        ),
        body: !signedIn
            ? Center(
                child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(t('Sign in to book a ride, send a parcel or drive with ASKODOX.',
                      'రైడ్ బుక్ చేయడానికి, పార్సెల్ పంపడానికి లేదా డ్రైవ్ చేయడానికి సైన్ ఇన్ చేయండి.'),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  FilledButton(
                      key: const ValueKey('mobility-signin'),
                      onPressed: () => context.push('/onboarding?signin=1'),
                      child: Text(t('Sign in', 'సైన్ ఇన్'))),
                ]),
              ))
            : TabBarView(children: [
                _BookTab(te: _te, kind: widget.initialKind, from: widget.initialFrom, to: widget.initialTo),
                _MyTripsTab(te: _te),
                _CarpoolTab(te: _te),
                _PartnerTab(te: _te),
              ]),
      ),
    );
  }
}

void _say(BuildContext context, String text) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

/// A typed place, or the current location when the field is left empty.
Map<String, Object?>? _point(WidgetRef ref, String text) {
  final typed = text.trim();
  if (typed.isNotEmpty) return {'label': typed};
  final loc = ref.read(locationControllerProvider);
  if (!loc.hasPlace) return null;
  return {
    'label': loc.displayLocation ?? 'Current location',
    'latitude': loc.centre.latitude,
    'longitude': loc.centre.longitude,
  };
}

class _BookTab extends ConsumerStatefulWidget {
  const _BookTab({required this.te, this.kind, this.from, this.to});
  final bool te;
  final String? kind;
  final String? from;
  final String? to;

  @override
  ConsumerState<_BookTab> createState() => _BookTabState();
}

class _BookTabState extends ConsumerState<_BookTab> {
  String t(String en, String te) => widget.te ? te : en;
  AskodoxPlace? _from;
  AskodoxPlace? _to;
  AskodoxRouteQuote? _route;
  int _routeQuery = 0;
  final _notes = TextEditingController();
  final _recipient = TextEditingController();
  final _recipientPhone = TextEditingController();
  String _kind = 'ride_auto';
  int _passengers = 1;
  DateTime? _when; // null = now
  bool _busy = false;
  MobilityJob? _last;

  bool get _send => askodoxSendKinds.contains(_kind);

  static bool _located(AskodoxPlace? p) => p != null && (p.latitude != 0 || p.longitude != 0);

  @override
  void initState() {
    super.initState();
    // ONE draft with the chat: what the chat understood opens here, and
    // edits here are what the chat's "Request a driver" sends.
    final draft = ref.read(askodoxMobilityDraftProvider);
    AskodoxPlace? labelled(String? label) =>
        label == null || label.trim().isEmpty ? null : AskodoxPlace(latitude: 0, longitude: 0, label: label.trim());
    final kind = widget.kind ?? draft?.kind;
    if (kind != null && (askodoxRideKinds.contains(kind) || askodoxSendKinds.contains(kind))) _kind = kind;
    _from = (draft?.from != null && (widget.from == null || draft!.from!.label == widget.from))
        ? draft!.from
        : labelled(widget.from);
    _to = (draft?.to != null && (widget.to == null || draft!.to!.label == widget.to)) ? draft!.to : labelled(widget.to);
    if (_from == null) {
      final loc = ref.read(locationControllerProvider);
      if (loc.hasPlace) {
        _from = AskodoxPlace(
            latitude: loc.centre.latitude,
            longitude: loc.centre.longitude,
            label: loc.displayLocation ?? 'Current location');
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _publish();
      _quoteRoute();
    });
  }

  void _publish() => ref.read(askodoxMobilityDraftProvider.notifier).state =
      MobilityDraft(kind: _kind, from: _from, to: _to);

  /// Distance / time for the chosen ends (Routes API through the backend);
  /// silent when Maps cannot answer.
  Future<void> _quoteRoute() async {
    final from = _from, to = _to;
    final id = ++_routeQuery;
    if (!_located(from) || !_located(to)) {
      if (_route != null) setState(() => _route = null);
      return;
    }
    AskodoxRouteQuote? quote;
    try {
      quote = await ref.read(growthRepositoryProvider).routeQuote(from!, to!);
    } catch (_) {
      quote = null;
    }
    if (mounted && id == _routeQuery) setState(() => _route = quote);
  }

  void _setEnd({AskodoxPlace? from, AskodoxPlace? to, bool isFrom = true}) {
    setState(() {
      if (isFrom) {
        _from = from;
      } else {
        _to = to;
      }
      _route = null;
    });
    _publish();
    _quoteRoute();
  }

  @override
  void dispose() {
    for (final c in [_notes, _recipient, _recipientPhone]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final pickup = _from != null ? askodoxMobilityPoint(_from!) : _point(ref, '');
    final drop = _to == null ? null : askodoxMobilityPoint(_to!);
    if (pickup == null || drop == null) {
      _say(context, t('Enter where from (or allow location) and where to.', 'ఎక్కడి నుంచి, ఎక్కడికి ఇవ్వండి.'));
      return;
    }
    setState(() => _busy = true);
    final result = await ref.read(mobilityRepositoryProvider).request(kind: _kind, pickup: pickup, drop: drop,
        details: {
          if (!_send) 'passengers': _passengers,
          if (_notes.text.trim().isNotEmpty) (_send ? 'item_description' : 'notes'): _notes.text.trim(),
          if (_send && _recipient.text.trim().isNotEmpty) 'recipient_name': _recipient.text.trim(),
          if (_send && _recipientPhone.text.trim().isNotEmpty) 'recipient_phone': _recipientPhone.text.trim(),
        },
        scheduleAt: _when == null ? '' : askodoxScheduleText(_when!));
    if (!mounted) return;
    setState(() {
      _busy = false;
      _last = result.data;
    });
    if (!result.ok) _say(context, result.error ?? t('Could not send the request.', 'రిక్వెస్ట్ పంపలేకపోయాం.'));
  }

  @override
  Widget build(BuildContext context) {
    final te = widget.te;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text(t('Ride', 'రైడ్'), style: Theme.of(context).textTheme.titleSmall),
      Wrap(spacing: 8, children: [
        for (final k in askodoxRideKinds)
          ChoiceChip(
              key: ValueKey('mobility-kind-$k'),
              label: Text(askodoxKindLabel(k, te)),
              selected: _kind == k,
              onSelected: (_) {
                setState(() => _kind = k);
                _publish();
              }),
      ]),
      const SizedBox(height: 8),
      Text(t('Send', 'పంపండి'), style: Theme.of(context).textTheme.titleSmall),
      Wrap(spacing: 8, children: [
        for (final k in askodoxSendKinds)
          ChoiceChip(
              key: ValueKey('mobility-kind-$k'),
              label: Text(askodoxKindLabel(k, te)),
              selected: _kind == k,
              onSelected: (_) {
                setState(() => _kind = k);
                _publish();
              }),
      ]),
      const SizedBox(height: 12),
      AskodoxPlaceField(
          fieldKey: 'mobility-from',
          te: te,
          allowCurrent: true,
          label: t('From', 'ఎక్కడి నుంచి'),
          icon: Icons.trip_origin,
          value: _from,
          onChanged: (p) => _setEnd(from: p)),
      const SizedBox(height: 8),
      AskodoxPlaceField(
          fieldKey: 'mobility-to',
          te: te,
          label: t('To', 'ఎక్కడికి'),
          icon: Icons.place_outlined,
          value: _to,
          onChanged: (p) => _setEnd(to: p, isFrom: false)),
      if (_from != null && _to != null)
        Padding(
          key: const ValueKey('mobility-route'),
          padding: const EdgeInsets.only(top: 6),
          child: Row(children: [
            const Icon(Icons.route_outlined, size: 18),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                  _route?.distanceKm != null
                      ? '${_route!.distanceKm!.toStringAsFixed(1)} km'
                          '${_route!.durationMinutes != null ? ' · ~${_route!.durationMinutes} min' : ''} '
                          '${t('by road', 'రోడ్డు మార్గం')}'
                      : t('Route distance appears once both places are on the map.',
                          'రెండు ప్రాంతాలు మ్యాప్‌లో ఉన్నప్పుడు దూరం కనిపిస్తుంది.'),
                  style: Theme.of(context).textTheme.bodySmall),
            ),
            TextButton.icon(
                key: const ValueKey('mobility-directions'),
                onPressed: () => launchUrl(askodoxRouteDirectionsUri(_from!, _to!), mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.directions_outlined, size: 18),
                label: Text(t('Map', 'మ్యాప్'))),
          ]),
        ),
      const SizedBox(height: 8),
      if (!_send)
        Row(children: [
          Text(t('Passengers', 'ప్రయాణికులు')),
          IconButton(
              onPressed: _passengers > 1 ? () => setState(() => _passengers--) : null,
              icon: const Icon(Icons.remove_circle_outline)),
          Text('$_passengers'),
          IconButton(onPressed: () => setState(() => _passengers++), icon: const Icon(Icons.add_circle_outline)),
        ]),
      TextField(
          controller: _notes,
          decoration: InputDecoration(
              labelText: _send ? t('What are you sending?', 'ఏమి పంపుతున్నారు?') : t('Note for the driver', 'డ్రైవర్‌కు నోట్'))),
      if (_send) ...[
        const SizedBox(height: 8),
        TextField(controller: _recipient, decoration: InputDecoration(labelText: t('Recipient name', 'అందుకునేవారి పేరు'))),
        const SizedBox(height: 8),
        TextField(
            controller: _recipientPhone,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
                labelText: t('Recipient phone', 'అందుకునేవారి ఫోన్'),
                helperText: t('Shared with the partner only after they accept.',
                    'పార్ట్‌నర్ అంగీకరించిన తర్వాతే చూపిస్తాం.'))),
      ],
      ListTile(
        key: const ValueKey('mobility-when'),
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.schedule),
        title: Text(_when == null
            ? t('Now', 'ఇప్పుడే')
            : '${t('Scheduled', 'షెడ్యూల్')}: ${askodoxScheduleText(_when!).replaceFirst('T', ' ')}'),
        subtitle: Text(t('Tap to schedule (airport, outstation, later today)', 'షెడ్యూల్ చేయడానికి నొక్కండి')),
        trailing: _when == null
            ? null
            : IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _when = null)),
        onTap: () async {
          final now = DateTime.now();
          final day = await showDatePicker(
              context: context, firstDate: now, lastDate: now.add(const Duration(days: 30)), initialDate: now);
          if (day == null || !context.mounted) return;
          final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))));
          if (time == null) return;
          setState(() => _when = DateTime(day.year, day.month, day.day, time.hour, time.minute));
        },
      ),
      const SizedBox(height: 16),
      FilledButton.icon(
          key: const ValueKey('mobility-submit'),
          onPressed: _busy ? null : _submit,
          icon: _busy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.send_rounded),
          label: Text(t('Send request', 'రిక్వెస్ట్ పంపండి'))),
      if (_last != null) ...[const SizedBox(height: 16), _JobCard(job: _last!, te: te)],
    ]);
  }
}

class _JobCard extends ConsumerWidget {
  const _JobCard({required this.job, required this.te, this.onChanged, this.partnerView = false});
  final MobilityJob job;
  final bool te;
  final bool partnerView;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    String t(String en, String tel) => te ? tel : en;
    final repo = ref.read(mobilityRepositoryProvider);
    return Card(
      key: ValueKey('mobility-job-${job.id}'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(askodoxKindLabel(job.kind, te), style: Theme.of(context).textTheme.titleMedium)),
            Chip(label: Text(job.confirmedByPartner ? t('Accepted', 'అంగీకరించారు') : t('Not confirmed', 'ఇంకా కన్ఫర్మ్ కాలేదు'))),
          ]),
          Text('${job.pickup} → ${job.drop}'),
          if (job.distanceKm != null) Text('${job.distanceKm!.toStringAsFixed(1)} km'),
          if (job.scheduleAt.isNotEmpty)
            Text('${t('Scheduled for', 'షెడ్యూల్')}: ${job.scheduleAt.replaceFirst('T', ' ')}'),
          const SizedBox(height: 4),
          Text(job.stage, style: const TextStyle(fontWeight: FontWeight.w600)),
          if (job.quote != null)
            Text(t('Estimate ₹${job.quote!.round()} (configured rate; the partner confirms)',
                'అంచనా ₹${job.quote!.round()} (పార్ట్‌నర్ కన్ఫర్మ్ చేస్తారు)')),
          if (job.partnerName.isNotEmpty) Text('${job.partnerName} · ${job.partnerVehicle}'),
          if (job.partnerPhone.isNotEmpty) SelectableText('${t('Partner', 'పార్ట్‌నర్')}: ${job.partnerPhone}'),
          if (job.customerPhone.isNotEmpty) SelectableText('${t('Customer', 'కస్టమర్')}: ${job.customerPhone}'),
          for (final e in job.details.entries) Text('${e.key.replaceAll('_', ' ')}: ${e.value}',
              style: Theme.of(context).textTheme.bodySmall),
          Wrap(spacing: 8, children: [
            if (!partnerView && job.cancellable)
              TextButton(
                  onPressed: () async {
                    final r = await repo.cancel(job.id);
                    if (context.mounted && !r.ok) _say(context, r.error ?? '');
                    onChanged?.call();
                  },
                  child: Text(t('Cancel', 'రద్దు'))),
            if (!partnerView && job.status == 'DELIVERED')
              FilledButton(
                  onPressed: () async {
                    await repo.confirm(job.id);
                    onChanged?.call();
                  },
                  child: Text(t('Confirm completed', 'పూర్తయిందని కన్ఫర్మ్'))),
            TextButton(
                onPressed: () async {
                  final ok = await repo.report('job', job.id, 'Reported from the app');
                  if (context.mounted) {
                    _say(context, ok ? t('Reported to ASKODOX staff.', 'స్టాఫ్‌కు రిపోర్ట్ చేశాం.') : t('Could not report.', 'రిపోర్ట్ కాలేదు.'));
                  }
                },
                child: Text(t('Report', 'రిపోర్ట్'))),
          ]),
        ]),
      ),
    );
  }
}

class _MyTripsTab extends ConsumerStatefulWidget {
  const _MyTripsTab({required this.te});
  final bool te;

  @override
  ConsumerState<_MyTripsTab> createState() => _MyTripsTabState();
}

class _MyTripsTabState extends ConsumerState<_MyTripsTab> {
  late Future<List<MobilityJob>> _items = ref.read(mobilityRepositoryProvider).myRequests();

  void _reload() => setState(() => _items = ref.read(mobilityRepositoryProvider).myRequests());

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: () async => _reload(),
        child: FutureBuilder<List<MobilityJob>>(
          future: _items,
          builder: (context, snap) {
            final items = snap.data ?? const <MobilityJob>[];
            if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
            if (items.isEmpty) {
              return ListView(children: [
                Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(widget.te ? 'ఇంకా రిక్వెస్ట్‌లు లేవు.' : 'No requests yet.', textAlign: TextAlign.center)),
              ]);
            }
            return ListView(padding: const EdgeInsets.all(12), children: [
              for (final j in items) _JobCard(job: j, te: widget.te, onChanged: _reload),
            ]);
          },
        ),
      );
}

class _CarpoolTab extends ConsumerStatefulWidget {
  const _CarpoolTab({required this.te});
  final bool te;

  @override
  ConsumerState<_CarpoolTab> createState() => _CarpoolTabState();
}

class _CarpoolTabState extends ConsumerState<_CarpoolTab> {
  String t(String en, String te) => widget.te ? te : en;
  final _from = TextEditingController();
  final _to = TextEditingController();
  final _date = TextEditingController();
  final _seats = TextEditingController(text: '1');
  final _share = TextEditingController();
  List<Map<String, Object?>>? _found;
  Map<String, Object?>? _mine;

  @override
  void initState() {
    super.initState();
    _loadMine();
  }

  @override
  void dispose() {
    for (final c in [_from, _to, _date, _seats, _share]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadMine() async {
    final mine = await ref.read(mobilityRepositoryProvider).myCarpool();
    if (mounted) setState(() => _mine = mine);
  }

  Future<AskodoxPlace?> _place(String text) async {
    if (text.trim().isEmpty) {
      final loc = ref.read(locationControllerProvider);
      return loc.hasPlace
          ? AskodoxPlace(latitude: loc.centre.latitude, longitude: loc.centre.longitude, label: 'Current location')
          : null;
    }
    final hits = await ref.read(growthRepositoryProvider).searchPlaces(text);
    return hits.isEmpty ? null : hits.first;
  }

  Future<void> _search() async {
    final a = await _place(_from.text);
    final b = await _place(_to.text);
    if (!mounted) return;
    if (a == null || b == null) {
      _say(context, t('Could not find those places on the map.', 'ఆ ప్రదేశాలు మ్యాప్‌లో దొరకలేదు.'));
      return;
    }
    final found = await ref.read(mobilityRepositoryProvider).searchCarpool(
        fromLat: a.latitude, fromLng: a.longitude, toLat: b.latitude, toLng: b.longitude, date: _date.text.trim());
    if (mounted) setState(() => _found = found);
  }

  Future<void> _offer() async {
    final from = _point(ref, _from.text);
    if (from == null || _to.text.trim().isEmpty || _date.text.trim().length < 10) {
      _say(context, t('Give from, to and the date/time (YYYY-MM-DD HH:MM).', 'ఎక్కడి నుంచి, ఎక్కడికి, తేదీ/సమయం ఇవ్వండి.'));
      return;
    }
    final r = await ref.read(mobilityRepositoryProvider).offerCarpool({
      'origin': from,
      'dest': {'label': _to.text.trim()},
      'depart_at': _date.text.trim().replaceFirst(' ', 'T'),
      'seats': int.tryParse(_seats.text) ?? 1,
      if (double.tryParse(_share.text) != null) 'contribution': double.parse(_share.text),
    });
    if (!mounted) return;
    _say(context, r.ok ? t('Ride offered. You decide who joins.', 'రైడ్ ఆఫర్ చేశారు. ఎవరు చేరాలో మీరే నిర్ణయిస్తారు.') : (r.error ?? ''));
    _loadMine();
  }

  @override
  Widget build(BuildContext context) {
    final hosting = (_mine?['hosting'] as List?) ?? const [];
    final riding = (_mine?['riding'] as List?) ?? const [];
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text(t('Share a trip you are making anyway. Contact is shared only after the host accepts.',
          'మీరు ఎలాగూ చేసే ప్రయాణాన్ని పంచుకోండి. హోస్ట్ అంగీకరించిన తర్వాతే కాంటాక్ట్.')),
      TextField(controller: _from, decoration: InputDecoration(labelText: t('From (empty = my location)', 'ఎక్కడి నుంచి'))),
      TextField(controller: _to, decoration: InputDecoration(labelText: t('To', 'ఎక్కడికి'))),
      TextField(controller: _date, decoration: InputDecoration(labelText: t('Date (YYYY-MM-DD) or date+time', 'తేదీ (YYYY-MM-DD)'))),
      Row(children: [
        Expanded(
            child: TextField(
                controller: _seats,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: t('Seats (offer)', 'సీట్లు')))),
        const SizedBox(width: 8),
        Expanded(
            child: TextField(
                controller: _share,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: t('Cost share ₹ (offer)', 'ఖర్చు వాటా ₹')))),
      ]),
      const SizedBox(height: 8),
      Wrap(spacing: 8, children: [
        FilledButton(key: const ValueKey('carpool-search'), onPressed: _search, child: Text(t('Find a ride', 'రైడ్ వెతకండి'))),
        OutlinedButton(key: const ValueKey('carpool-offer'), onPressed: _offer, child: Text(t('Offer seats', 'సీట్లు ఆఫర్'))),
      ]),
      if (_found != null) ...[
        const SizedBox(height: 12),
        if (_found!.isEmpty) Text(t('No shared rides on this route yet.', 'ఈ రూట్‌లో ఇంకా రైడ్‌లు లేవు.')),
        for (final r in _found!)
          ListTile(
            title: Text('${((r['origin'] as Map?) ?? const {})['label'] ?? ''} → ${((r['dest'] as Map?) ?? const {})['label'] ?? ''}'),
            subtitle: Text('${r['depart_at']} · ${r['seats_left']} ${t('seats', 'సీట్లు')}'
                '${r['contribution'] == null ? '' : ' · ₹${r['contribution']}'}'),
            trailing: TextButton(
                onPressed: () async {
                  final res = await ref.read(mobilityRepositoryProvider).requestSeat('${r['id']}');
                  if (!context.mounted) return;
                  _say(context, res.ok ? t('Request sent -- waiting for the host.', 'రిక్వెస్ట్ పంపాం -- హోస్ట్ కోసం వేచి ఉంది.') : (res.error ?? ''));
                  _loadMine();
                },
                child: Text(t('Request seat', 'సీట్ అడగండి'))),
          ),
      ],
      const Divider(height: 32),
      Text(t('My rides', 'నా రైడ్స్'), style: Theme.of(context).textTheme.titleSmall),
      for (final h in hosting.whereType<Map>())
        Card(
            child: Column(children: [
          ListTile(
              title: Text('${(h['origin'] as Map?)?['label'] ?? ''} → ${(h['dest'] as Map?)?['label'] ?? ''}'),
              subtitle: Text('${h['depart_at']} · ${h['status']} · ${h['seats_left']}/${h['seats']}')),
          for (final q in ((h['requests'] as List?) ?? const []).whereType<Map>())
            ListTile(
              dense: true,
              title: Text('${q['seats']} ${t('seat(s)', 'సీట్(లు)')} · ${q['status']}'),
              subtitle: q['passenger_phone'] == null ? null : SelectableText('${q['passenger_phone']}'),
              trailing: q['status'] == 'REQUESTED'
                  ? Wrap(children: [
                      IconButton(
                          icon: const Icon(Icons.check_circle_outline),
                          onPressed: () async {
                            await ref.read(mobilityRepositoryProvider).decideSeat('${q['id']}', true);
                            _loadMine();
                          }),
                      IconButton(
                          icon: const Icon(Icons.cancel_outlined),
                          onPressed: () async {
                            await ref.read(mobilityRepositoryProvider).decideSeat('${q['id']}', false);
                            _loadMine();
                          }),
                    ])
                  : null,
            ),
        ])),
      for (final r in riding.whereType<Map>())
        ListTile(
          title: Text('${t('Seat request', 'సీట్ రిక్వెస్ట్')} · ${r['status']}'),
          subtitle: (r['ride'] as Map?)?['host_phone'] == null
              ? Text(t('The host\'s number appears once they accept.', 'హోస్ట్ అంగీకరించిన తర్వాత నంబర్ కనిపిస్తుంది.'))
              : SelectableText('${(r['ride'] as Map)['host_phone']}'),
        ),
      if (hosting.isEmpty && riding.isEmpty) Text(t('Nothing yet.', 'ఇంకా ఏమీ లేదు.')),
    ]);
  }
}

class _PartnerTab extends ConsumerStatefulWidget {
  const _PartnerTab({required this.te});
  final bool te;

  @override
  ConsumerState<_PartnerTab> createState() => _PartnerTabState();
}

class _PartnerTabState extends ConsumerState<_PartnerTab> {
  String t(String en, String te) => widget.te ? te : en;
  MobilityResult<MobilityPartner?>? _me;
  List<MobilityJob> _offers = const [];
  ({List<MobilityJob> active, List<MobilityJob> history}) _trips = (active: const [], history: const []);
  final _name = TextEditingController();
  final _vehicleNumber = TextEditingController();
  final _licence = TextEditingController();
  final _town = TextEditingController();
  String _vehicle = 'two_wheeler';
  final Set<String> _services = {'parcel'};

  static const _serviceChoices = ['ride_auto', 'ride_bike', 'ride_taxi', 'ride_airport', 'ride_outstation',
    'driver_only', 'parcel', 'documents', 'food', 'grocery', 'product', 'pickup_drop'];
  static const _vehicles = ['two_wheeler', 'three_wheeler', 'car', 'van', 'truck', 'bicycle', 'walk'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_name, _vehicleNumber, _licence, _town]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final repo = ref.read(mobilityRepositoryProvider);
    final me = await repo.myPartner();
    final active = me.data?.status == 'ACTIVE';
    final offers = active ? await repo.offers() : const <MobilityJob>[];
    final trips = active ? await repo.trips() : (active: const <MobilityJob>[], history: const <MobilityJob>[]);
    if (!mounted) return;
    setState(() {
      _me = me;
      _offers = offers;
      _trips = trips;
      final p = me.data;
      if (p != null && _name.text.isEmpty) {
        _name.text = p.name;
        _vehicle = _vehicles.contains(p.vehicle) ? p.vehicle : _vehicle;
        _services
          ..clear()
          ..addAll(p.services);
      }
    });
  }

  Future<void> _apply({bool update = false}) async {
    if (_name.text.trim().length < 2 || _services.isEmpty) {
      _say(context, t('Add your name and at least one service.', 'పేరు, కనీసం ఒక సర్వీస్ ఇవ్వండి.'));
      return;
    }
    final r = await ref.read(mobilityRepositoryProvider).apply({
      'name': _name.text.trim(),
      'services': _services.toList(),
      'vehicle': _vehicle,
      'vehicle_number': _vehicleNumber.text.trim(),
      'licence_last4': _licence.text.trim(),
      'town': _town.text.trim(),
    }, update: update);
    if (!mounted) return;
    _say(context, r.ok ? t('Sent for review. ASKODOX staff verify you before you can go online.',
        'రివ్యూకు పంపాం. స్టాఫ్ వెరిఫై చేసిన తర్వాత ఆన్‌లైన్ అవ్వొచ్చు.') : (r.error ?? ''));
    _load();
  }

  Widget _form({bool update = false}) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(key: const ValueKey('partner-name'), controller: _name, decoration: InputDecoration(labelText: t('Your name', 'మీ పేరు'))),
        const SizedBox(height: 8),
        Text(t('Services you can do', 'మీరు చేయగల సర్వీసులు')),
        Wrap(spacing: 6, children: [
          for (final s in _serviceChoices)
            FilterChip(
                label: Text(askodoxKindLabel(s, widget.te)),
                selected: _services.contains(s),
                onSelected: (on) => setState(() => on ? _services.add(s) : _services.remove(s))),
        ]),
        DropdownButtonFormField<String>(
            initialValue: _vehicle,
            items: [for (final v in _vehicles) DropdownMenuItem(value: v, child: Text(v.replaceAll('_', ' ')))],
            onChanged: (v) => setState(() => _vehicle = v ?? _vehicle),
            decoration: InputDecoration(labelText: t('Vehicle', 'వాహనం'))),
        TextField(controller: _vehicleNumber, decoration: InputDecoration(labelText: t('Vehicle number', 'వాహనం నంబర్'))),
        TextField(
            controller: _licence,
            maxLength: 4,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
                labelText: t('Licence: last 4 digits only', 'లైసెన్స్: చివరి 4 అంకెలు మాత్రమే'),
                helperText: t('Documents are checked in person -- never uploaded.', 'డాక్యుమెంట్లు నేరుగా చూస్తారు -- అప్‌లోడ్ చేయరు.'))),
        TextField(controller: _town, decoration: InputDecoration(labelText: t('Town / city', 'ఊరు / నగరం'))),
        const SizedBox(height: 12),
        FilledButton(
            key: const ValueKey('partner-apply'),
            onPressed: () => _apply(update: update),
            child: Text(update ? t('Resubmit', 'మళ్లీ పంపండి') : t('Apply to drive / deliver', 'డ్రైవ్ / డెలివర్ చేయడానికి అప్లై'))),
      ]);

  @override
  Widget build(BuildContext context) {
    final me = _me;
    if (me == null) return const Center(child: CircularProgressIndicator());
    final p = me.data;
    final children = <Widget>[];
    if (!me.ok) {
      children.add(Text(me.error ?? t('Could not load.', 'లోడ్ కాలేదు.')));
    } else if (p == null) {
      children.addAll([
        Text(t('Earn by giving rides or delivering nearby. ASKODOX staff approve every partner.',
            'దగ్గర్లో రైడ్‌లు, డెలివరీలు చేసి సంపాదించండి. ప్రతి పార్ట్‌నర్‌ను స్టాఫ్ ఆమోదిస్తారు.')),
        const SizedBox(height: 12),
        _form(),
      ]);
    } else if (p.status != 'ACTIVE') {
      final text = switch (p.status) {
        'PENDING_REVIEW' => t('Your application is waiting for review.', 'మీ అప్లికేషన్ రివ్యూలో ఉంది.'),
        'DRAFT' => t('Staff asked for a correction. Update and resubmit.', 'స్టాఫ్ సవరణ అడిగారు. సరిచేసి మళ్లీ పంపండి.'),
        'REJECTED' => t('Your application was not approved. You can correct and resubmit.', 'అప్లికేషన్ ఆమోదించలేదు. సరిచేసి మళ్లీ పంపవచ్చు.'),
        'PAUSED' => t('Your partner account is paused by ASKODOX staff.', 'మీ ఖాతా తాత్కాలికంగా ఆపబడింది.'),
        'DISABLED' => t('Your partner account is disabled.', 'మీ ఖాతా నిలిపివేయబడింది.'),
        _ => p.status,
      };
      children.addAll([
        Card(child: ListTile(key: const ValueKey('partner-status'), title: Text(text), subtitle: p.reviewNote.isEmpty ? null : Text(p.reviewNote))),
        if (p.status == 'DRAFT' || p.status == 'REJECTED') _form(update: true),
      ]);
    } else {
      children.addAll([
        SwitchListTile(
          key: const ValueKey('partner-online'),
          title: Text(p.available ? t('Online -- receiving requests', 'ఆన్‌లైన్ -- రిక్వెస్ట్‌లు వస్తాయి') : t('Offline', 'ఆఫ్‌లైన్')),
          subtitle: Text(t('Requests near your location are offered to you.', 'మీ లొకేషన్ దగ్గరి రిక్వెస్ట్‌లు మీకు వస్తాయి.')),
          value: p.available,
          onChanged: (on) async {
            final loc = ref.read(locationControllerProvider);
            final r = await ref.read(mobilityRepositoryProvider).setAvailable(on,
                latitude: loc.hasPlace ? loc.centre.latitude : null,
                longitude: loc.hasPlace ? loc.centre.longitude : null);
            if (context.mounted && !r.ok) _say(context, r.error ?? '');
            _load();
          },
        ),
        Text(t('Requests for you', 'మీకోసం రిక్వెస్ట్‌లు'), style: Theme.of(context).textTheme.titleSmall),
        if (_offers.isEmpty) Text(t('No requests right now.', 'ఇప్పుడు రిక్వెస్ట్‌లు లేవు.')),
        for (final o in _offers)
          Card(
              child: Column(children: [
            _JobCard(job: o, te: widget.te, partnerView: true),
            OverflowBar(children: [
              TextButton(
                  onPressed: () async {
                    await ref.read(mobilityRepositoryProvider).decline(o.id);
                    _load();
                  },
                  child: Text(t('Decline', 'వద్దు'))),
              FilledButton(
                  key: ValueKey('partner-accept-${o.id}'),
                  onPressed: () async {
                    final r = await ref.read(mobilityRepositoryProvider).accept(o.id);
                    if (context.mounted && !r.ok) _say(context, r.error ?? '');
                    _load();
                  },
                  child: Text(t('Accept', 'అంగీకరించు'))),
            ]),
          ])),
        const SizedBox(height: 12),
        Text(t('Current trips', 'ప్రస్తుత ట్రిప్స్'), style: Theme.of(context).textTheme.titleSmall),
        for (final j in _trips.active)
          Card(
              child: Column(children: [
            _JobCard(job: j, te: widget.te, partnerView: true),
            if (askodoxNextTripStep(j.status) != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: FilledButton(
                    key: ValueKey('partner-step-${j.id}'),
                    onPressed: () async {
                      final r = await ref.read(mobilityRepositoryProvider).step(j.id, askodoxNextTripStep(j.status)!);
                      if (context.mounted && !r.ok) _say(context, r.error ?? '');
                      _load();
                    },
                    child: Text(askodoxTripStepLabel(askodoxNextTripStep(j.status)!, widget.te))),
              ),
          ])),
        if (_trips.history.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(t('History', 'చరిత్ర'), style: Theme.of(context).textTheme.titleSmall),
          for (final j in _trips.history)
            ListTile(dense: true, title: Text('${askodoxKindLabel(j.kind, widget.te)} · ${j.stage}'), subtitle: Text('${j.pickup} → ${j.drop}')),
        ],
      ]);
    }
    return RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(16), children: children));
  }
}

/// Local date-time as the backend stores it (YYYY-MM-DDTHH:MM).
String askodoxScheduleText(DateTime at) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${at.year}-${two(at.month)}-${two(at.day)}T${two(at.hour)}:${two(at.minute)}';
}

String askodoxTripStepLabel(String step, bool te) => switch (step) {
      'EN_ROUTE_PICKUP' => te ? 'పికప్‌కు బయలుదేరాను' : 'On my way to pickup',
      'ARRIVED_PICKUP' => te ? 'పికప్ వద్ద ఉన్నాను' : 'Arrived at pickup',
      'PICKED_UP' => te ? 'పికప్ చేశాను' : 'Picked up',
      'IN_TRANSIT' => te ? 'దారిలో ఉన్నాను' : 'On the way',
      'ARRIVED_DROP' => te ? 'డ్రాప్ వద్ద ఉన్నాను' : 'Arrived at drop',
      'DELIVERED' => te ? 'పూర్తి చేశాను' : 'Delivered / trip done',
      _ => step,
    };
