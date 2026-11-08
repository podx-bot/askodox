import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/askodox_hub_icons.dart';
import '../../../shared/widgets/navigator_section.dart';
import '../../home/domain/conversation_language.dart';
import '../../location/application/location_controller.dart';
import '../data/travel_radio_repository.dart';

/// ASKODOX Travel Radio. Plays short segments built ONLY from real facts for
/// where the person is (place name, nearby places, staff-approved news).
/// Owner, 2026-11-04: NO separate radio package -- each segment is one AI
/// Credits use (free while AI Credits charging is off).
class TravelRadioScreen extends ConsumerStatefulWidget {
  const TravelRadioScreen({super.key, this.device = const MethodChannel('com.askodox.app/device')});
  final MethodChannel device;

  @override
  ConsumerState<TravelRadioScreen> createState() => _TravelRadioScreenState();
}

class _TravelRadioScreenState extends ConsumerState<TravelRadioScreen> {
  AskodoxRadioSegment? _segment;
  bool _busy = false, _playing = false;
  final _town = TextEditingController();
  AskodoxTownNews? _news;

  Future<void> _playTown() async {
    final place = _town.text.trim();
    if (place.length < 2 || _busy || _playing) return;
    final lang = ref.read(askodoxReplyLanguageProvider);
    setState(() => _busy = true);
    final news = await ref.read(travelRadioRepositoryProvider)
        .town(place: place, lang: const {'te', 'hi'}.contains(lang) ? lang : 'en');
    if (!mounted) return;
    setState(() {
      _news = news;
      _busy = false;
    });
    if (news.problem != null) return;
    await _say(news.audio, news.text, lang);
  }

  Future<void> _say(Uint8List? audio, String text, String lang) async {
    setState(() => _playing = true);
    try {
      var played = false;
      if (audio != null) {
        played = await widget.device.invokeMethod<bool>(
                'playReplyAudio', <String, Object?>{'bytes': audio, 'languageCode': lang}) ==
            true;
      }
      if (!played) {
        await widget.device.invokeMethod<bool>('speakReply', <String, Object?>{'text': text, 'languageCode': lang});
      }
    } catch (_) {
      // No audio on this device: the text stays on screen.
    } finally {
      if (mounted) setState(() => _playing = false);
    }
  }

  bool get _te => Localizations.localeOf(context).languageCode == 'te';

  Future<void> _playNext() async {
    final location = ref.read(locationControllerProvider);
    final lang = ref.read(askodoxReplyLanguageProvider);
    if (!location.hasPlace) {
      setState(() => _segment = const AskodoxRadioSegment(problem: 'no_location'));
      return;
    }
    setState(() => _busy = true);
    final segment = await ref.read(travelRadioRepositoryProvider).next(
        latitude: location.centre.latitude,
        longitude: location.centre.longitude,
        lang: const {'te', 'hi'}.contains(lang) ? lang : 'en');
    if (!mounted) return;
    setState(() {
      _segment = segment;
      _busy = false;
    });
    if (segment.problem != null) return;
    setState(() => _playing = true);
    try {
      var played = false;
      if (segment.audio != null) {
        played = await widget.device.invokeMethod<bool>(
                'playReplyAudio', <String, Object?>{'bytes': segment.audio, 'languageCode': lang}) ==
            true;
      }
      if (!played) {
        await widget.device.invokeMethod<bool>('speakReply', <String, Object?>{'text': segment.text, 'languageCode': lang});
      }
    } catch (_) {
      // No audio on this device: the text stays on screen.
    } finally {
      if (mounted) setState(() => _playing = false);
    }
  }

  Future<void> _stop() async {
    try {
      await widget.device.invokeMethod<bool>('stopSpeaking');
    } catch (_) {}
    if (mounted) setState(() => _playing = false);
  }

  @override
  void dispose() {
    _town.dispose();
    widget.device.invokeMethod<bool>('stopSpeaking').catchError((_) => false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(travelRadioStatusProvider);
    final te = _te;
    return Scaffold(
      appBar: AppBar(
        title: Text(te ? 'రేడియో' : 'Radio'),
        actions: const [AskodoxHubIcons(current: 'radio')],
      ),
      body: status.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(child: Text(askodoxRadioProblemText('unavailable', te))),
        data: (s) => s == null
            ? Center(child: Text(te ? 'సైన్ ఇన్ చేయండి.' : 'Please sign in.', key: const Key('askodoxRadioSignIn')))
            : ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
                AskodoxNavSection(
                  title: te ? 'ఇప్పుడు వినండి' : 'Listen now',
                  icon: Icons.radio_outlined,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(
                          te
                              ? 'మీరు ఉన్న ప్రదేశం, దగ్గరలోని ప్రదేశాలు, తాజా సమాచారం -- నిజమైన సమాచారం మాత్రమే.'
                              : 'Where you are, places nearby and fresh updates -- real information only.',
                        ),
                        const SizedBox(height: 6),
                        Text(
                            s.internalTesting
                                ? (te ? 'అంతర్గత పరీక్ష -- ఏమీ కట్ అవ్వదు.' : 'Internal testing -- nothing is deducted.')
                                : s.creditsCharging && s.creditRatePaise > 0
                                    ? (te
                                        ? 'ప్రతి భాగానికి AI Credits నుండి ₹${(s.creditRatePaise / 100).toStringAsFixed(2)} కట్ అవుతుంది. వేరే ప్యాకేజ్ అవసరం లేదు.'
                                        : 'Each segment uses ₹${(s.creditRatePaise / 100).toStringAsFixed(2)} of your AI Credits. No separate package.')
                                    : (te
                                        ? 'మీ AI Credits తోనే పనిచేస్తుంది -- ఇప్పుడు ఉచితం. వేరే ప్యాకేజ్ అవసరం లేదు.'
                                        : 'Runs on your AI Credits -- free right now. No separate package.'),
                            key: const Key('askodoxRadioCredits'),
                            style: const TextStyle(fontSize: 12, color: Color(0xFF475467))),
                        if (s.internalTesting) ...[
                          const SizedBox(height: 6),
                          Text(te ? 'అంతర్గత పరీక్ష -- ధర / బిల్లింగ్ లేదు' : 'Internal testing -- no price, no billing',
                              key: const Key('askodoxRadioInternalTesting'),
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFFB45309))),
                        ],
                        if (s.access) ...[
                          const SizedBox(height: 6),
                          Text(te
                              ? 'ఈరోజు: ${s.minutesToday} / ${s.dailyMinutes} నిమిషాలు'
                              : 'Today: ${s.minutesToday} / ${s.dailyMinutes} min',
                              style: const TextStyle(fontSize: 12)),
                        ],
                        const SizedBox(height: 10),
                        Row(children: [
                          FilledButton.icon(
                            key: const Key('askodoxRadioPlay'),
                            onPressed: _busy || _playing || !s.enabled || !s.access ? null : _playNext,
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: Text(te ? 'తర్వాతది వినండి' : 'Play next'),
                          ),
                          const SizedBox(width: 8),
                          if (_playing)
                            OutlinedButton.icon(
                              key: const Key('askodoxRadioStop'),
                              onPressed: _stop,
                              icon: const Icon(Icons.stop_rounded),
                              label: Text(te ? 'ఆపండి' : 'Stop'),
                            ),
                        ]),
                        if (!s.enabled || !s.access) ...[
                          const SizedBox(height: 8),
                          Text(askodoxRadioProblemText(s.enabled ? 'AI_CREDITS_LOW' : 'RADIO_DISABLED', te),
                              key: const Key('askodoxRadioLocked')),
                        ],
                        if (_segment != null) ...[
                          const SizedBox(height: 12),
                          if (_segment!.problem != null)
                            Text(askodoxRadioProblemText(_segment!.problem!, te), key: const Key('askodoxRadioProblem'))
                          else ...[
                            Text(_segment!.title, style: const TextStyle(fontWeight: FontWeight.w800)),
                            const SizedBox(height: 4),
                            Text(_segment!.text, key: const Key('askodoxRadioText')),
                          ],
                        ],
                      ]),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                AskodoxNavSection(
                  title: te ? 'ఊరి వార్తలు' : 'Town news',
                  icon: Icons.newspaper_rounded,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(te
                            ? 'ఏ ఊరి పేరు అయినా రాయండి — ఆ ఊరి తాజా వార్తలు వెంటనే వినిపిస్తాం (నిజమైన వార్తలు మాత్రమే, ఎక్కడివో పేరుతో).'
                            : 'Type any town — we read its latest news right away (real headlines only, with their source).'),
                        const SizedBox(height: 8),
                        Row(children: [
                          Expanded(
                            child: TextField(
                              key: const Key('askodoxRadioTown'),
                              controller: _town,
                              textInputAction: TextInputAction.search,
                              onSubmitted: (_) => _playTown(),
                              decoration: InputDecoration(
                                hintText: te ? 'ఉదా. ఉయ్యూరు' : 'e.g. Vuyyuru',
                                isDense: true,
                                border: const OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            key: const Key('askodoxRadioTownPlay'),
                            onPressed: _busy || _playing || !s.enabled || !s.access ? null : _playTown,
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: Text(te ? 'వినండి' : 'Listen'),
                          ),
                        ]),
                        const SizedBox(height: 6),
                        Text(
                          s.creditsCharging && s.creditRatePaise > 0
                              ? (te
                                  ? 'ఒక ఊరి బులెటిన్ = AI Credits నుండి ₹${(s.creditRatePaise / 100).toStringAsFixed(2)}. ఏమీ దొరకకపోతే ఏమీ కట్ కాదు.'
                                  : 'One town bulletin = ₹${(s.creditRatePaise / 100).toStringAsFixed(2)} of AI Credits. Nothing found = nothing charged.')
                              : (te
                                  ? 'ఒక ఊరి బులెటిన్ = ఒక AI Credits ఉపయోగం — ఇప్పటికి ఛార్జ్ లేదు. ఏమీ దొరకకపోతే ఏమీ కట్ కాదు.'
                                  : 'One town bulletin = one AI Credits use — no charge for now. Nothing found = nothing charged.'),
                          key: const Key('askodoxRadioTownCost'),
                          style: const TextStyle(fontSize: 12, color: Color(0xFF475467)),
                        ),
                        if (_news != null) ...[
                          const SizedBox(height: 10),
                          if (_news!.problem != null)
                            Text(askodoxRadioProblemText(_news!.problem!, te), key: const Key('askodoxRadioTownProblem'))
                          else
                            for (final h in _news!.headlines)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Text.rich(TextSpan(children: [
                                  TextSpan(text: h.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                                  if (h.source.isNotEmpty)
                                    TextSpan(text: '  · ${h.source}', style: const TextStyle(fontSize: 12, color: Color(0xFF667085))),
                                ])),
                              ),
                        ],
                      ]),
                    ),
                  ],
                ),
              ]),
      ),
    );
  }
}
