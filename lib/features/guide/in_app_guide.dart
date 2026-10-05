import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// ASKODOX Screen Guide INSIDE the app: it points at the real button on the
/// real screen (dim + spotlight + pulse + arrow), says what to do in Telugu
/// or English (text + voice), waits for the user's own tap, notices when a
/// step is already done, brings the user back from a wrong screen, and
/// pauses on private screens (sign-in / OTP). It never taps anything itself
/// and never reads what is typed.
///
/// Steps point at widgets by their existing keys (`Key('x')` /
/// `ValueKey('x')`; a trailing `*` matches a key prefix), so screens need no
/// guide-specific code.
class AskodoxGuideStep {
  const AskodoxGuideStep(this.target, this.en, this.te, {this.route});

  final String target;
  final String en;
  final String te;

  /// Where this step's button lives (used by "Take me there").
  final String? route;
}

class AskodoxGuideFlow {
  const AskodoxGuideFlow(this.id, this.titleEn, this.titleTe, this.keywords, this.steps);

  final String id;
  final String titleEn;
  final String titleTe;
  final List<String> keywords;
  final List<AskodoxGuideStep> steps;

  String title(bool te) => te ? titleTe : titleEn;
}

const _profile = AskodoxGuideStep('askodoxNavProfile', 'Tap Profile at the bottom.', 'కింద ప్రొఫైల్ నొక్కండి.',
    route: '/profile');

const askodoxGuideFlows = <AskodoxGuideFlow>[
  AskodoxGuideFlow('upload_video', 'Upload a video', 'వీడియో అప్‌లోడ్ చేయడం',
      ['upload a video', 'upload video', 'add a video', 'publish a video', 'post a video', 'వీడియో అప్‌లోడ్', 'వీడియో పెట్ట'], [
    _profile,
    AskodoxGuideStep('profile-native-video', 'Tap "My videos".', '"నా వీడియోలు" నొక్కండి.', route: '/profile'),
    AskodoxGuideStep('video-pick-gallery', 'Tap "Choose video" and pick your video.', '"వీడియో ఎంచుకోండి" నొక్కి మీ వీడియో ఎంచుకోండి.',
        route: '/videos/native'),
    AskodoxGuideStep('video-title', 'Give it a short title.', 'చిన్న టైటిల్ ఇవ్వండి.', route: '/videos/native'),
    AskodoxGuideStep('video-upload', 'Tap "Upload for review". Staff check it before it is published.',
        '"రివ్యూకు అప్‌లోడ్" నొక్కండి. పబ్లిష్ ముందు స్టాఫ్ చూస్తారు.', route: '/videos/native'),
  ]),
  AskodoxGuideFlow('add_listing', 'Add a listing', 'లిస్టింగ్ జోడించడం',
      ['add a listing', 'add listing', 'list my product', 'sell my product', 'add a product', 'లిస్టింగ్', 'అమ్మడం ఎలా'], [
    _profile,
    AskodoxGuideStep('profile-my-listings', 'Tap "My listings".', '"నా లిస్టింగ్‌లు" నొక్కండి.', route: '/profile'),
    AskodoxGuideStep('askodoxAddListing', 'Tap "Sell something" and tell ASKODOX what you sell, the price and quantity.',
        '"ఏదైనా అమ్మండి" నొక్కి, ఏమి అమ్ముతారు, ధర, పరిమాణం చెప్పండి.', route: '/listings/mine'),
  ]),
  AskodoxGuideFlow('change_location', 'Change my location', 'లొకేషన్ మార్చడం',
      ['change location', 'change my location', 'set location', 'set my location', 'లొకేషన్ మార్చ', 'లొకేషన్ సెట్'], [
    AskodoxGuideStep('askodoxLocationChip', 'Tap your place at the top.', 'పైన మీ ప్రాంతం నొక్కండి.', route: '/'),
    AskodoxGuideStep('askodoxLocationSearch', 'Type your area or a landmark, then search.',
        'మీ ప్రాంతం లేదా ల్యాండ్‌మార్క్ టైప్ చేసి వెతకండి.', route: '/location'),
    AskodoxGuideStep('askodoxPlaceResult-*', 'Tap the right place in the list.', 'లిస్ట్‌లో సరైన ప్రాంతం నొక్కండి.',
        route: '/location'),
  ]),
  AskodoxGuideFlow('accept_order', 'Accept an order', 'ఆర్డర్ అంగీకరించడం',
      ['accept an order', 'accept order', 'accept a request', 'accept the request', 'ఆర్డర్ అంగీకరించ'], [
    AskodoxGuideStep('askodoxOrderAccept', 'Check the request, then tap "Accept". The buyer\'s contact appears only after you accept.',
        'రిక్వెస్ట్ చూసి "ఆమోదించు" నొక్కండి. అంగీకరించాకే కొనుగోలుదారు వివరాలు కనిపిస్తాయి.', route: '/orders/incoming'),
  ]),
  AskodoxGuideFlow('send_parcel', 'Send a parcel', 'పార్సెల్ పంపడం',
      ['send a parcel', 'send parcel', 'courier', 'పార్సెల్ పంప'], [
    _profile,
    AskodoxGuideStep('profile-mobility', 'Tap "Rides, parcels & carpool".', '"రైడ్స్, పార్సెల్స్ & కార్‌పూల్" నొక్కండి.',
        route: '/profile'),
    AskodoxGuideStep('mobility-kind-parcel', 'Choose "Parcel".', '"పార్సెల్" ఎంచుకోండి.', route: '/mobility'),
    AskodoxGuideStep('mobility-from', 'Where from? Type, use my location or pick on the map.',
        'ఎక్కడి నుంచి? టైప్ చేయండి, నా లొకేషన్ లేదా మ్యాప్ వాడండి.', route: '/mobility'),
    AskodoxGuideStep('mobility-to', 'Where to?', 'ఎక్కడికి?', route: '/mobility'),
    AskodoxGuideStep('mobility-submit', 'Tap "Send request". It is confirmed only when a partner accepts.',
        '"రిక్వెస్ట్ పంపండి" నొక్కండి. పార్ట్‌నర్ అంగీకరించాకే కన్ఫర్మ్.', route: '/mobility'),
  ]),
  AskodoxGuideFlow('become_partner', 'Become a delivery partner', 'డెలివరీ పార్ట్‌నర్ అవ్వడం',
      ['delivery partner', 'become a driver', 'become driver', 'join as partner', 'join as a partner', 'డెలివరీ పార్ట్‌నర్', 'డ్రైవర్‌గా'], [
    _profile,
    AskodoxGuideStep('askodoxProfileDeliveryOpportunities', 'Tap "Delivery opportunities".', '"డెలివరీ అవకాశాలు" నొక్కండి.',
        route: '/profile'),
    AskodoxGuideStep('partner-name', 'Fill in your name, vehicle and services.', 'మీ పేరు, వాహనం, సేవలు నింపండి.',
        route: '/mobility?tab=3'),
    AskodoxGuideStep('partner-apply', 'Tap Apply. Staff review it, then you can go online.',
        'అప్లై నొక్కండి. స్టాఫ్ రివ్యూ తర్వాత ఆన్‌లైన్‌కి వెళ్లవచ్చు.', route: '/mobility?tab=3'),
  ]),
  AskodoxGuideFlow('report_problem', 'Report a problem', 'సమస్య చెప్పడం',
      ['report a problem', 'report problem', 'send feedback', 'report a bug', 'సమస్య చెప్ప', 'ఫీడ్‌బ్యాక్'], [
    _profile,
    AskodoxGuideStep('profile-feedback', 'Tap "Report a problem / Send feedback".', '"సమస్య చెప్పండి / ఫీడ్‌బ్యాక్" నొక్కండి.',
        route: '/profile'),
    AskodoxGuideStep('askodoxFeedbackDescription', 'Describe what happened. Never type passwords, OTPs or card numbers.',
        'ఏమైందో రాయండి. పాస్‌వర్డ్, OTP, కార్డ్ నంబర్లు వద్దు.', route: '/beta-feedback'),
    AskodoxGuideStep('askodoxFeedbackSubmit', 'Tap "Submit feedback".', '"ఫీడ్‌బ్యాక్ పంపండి" నొక్కండి.',
        route: '/beta-feedback'),
  ]),
];

final _howTo = RegExp(
    r'\b(how (do|can|to|should)|show me how|teach me|guide me|help me (to )?|where (do|can) i|steps? to)\b|ఎలా|చూపించు|నేర్పించు',
    caseSensitive: false);

/// A how-to question ("how do I upload a video?") -> the matching guide.
/// Plain requests ("send a parcel from X to Y") are not how-to questions.
AskodoxGuideFlow? askodoxGuideFor(String text) {
  final t = text.toLowerCase();
  if (!_howTo.hasMatch(t)) return null;
  for (final flow in askodoxGuideFlows) {
    if (flow.keywords.any(t.contains)) return flow;
  }
  return null;
}

AskodoxGuideFlow? askodoxGuideById(String id) {
  for (final f in askodoxGuideFlows) {
    if (f.id == id) return f;
  }
  return null;
}

/// Private screens: the guide hides and says it paused (nothing is read,
/// captured or spoken there).
const askodoxGuidePrivateRoutes = ['/onboarding', '/auth', '/staff', '/payment', '/checkout'];

bool askodoxGuideIsPrivate(String location) =>
    askodoxGuidePrivateRoutes.any((r) => location == r || location.startsWith('$r?') || location.startsWith('$r/'));

class AskodoxGuideState {
  const AskodoxGuideState({required this.flow, this.index = 0, this.done = false});
  final AskodoxGuideFlow flow;
  final int index;
  final bool done;

  AskodoxGuideStep get step => flow.steps[index.clamp(0, flow.steps.length - 1)];
  bool get last => index >= flow.steps.length - 1;
}

class AskodoxGuideController extends StateNotifier<AskodoxGuideState?> {
  AskodoxGuideController() : super(null);

  void start(AskodoxGuideFlow flow) => state = AskodoxGuideState(flow: flow);

  /// The user did this step (their own tap) -> the next one, or done.
  void advance() {
    final s = state;
    if (s == null || s.done) return;
    state = s.last
        ? AskodoxGuideState(flow: s.flow, index: s.index, done: true)
        : AskodoxGuideState(flow: s.flow, index: s.index + 1);
  }

  /// A later step's button is already on screen: the earlier ones are done.
  void jumpTo(int index) {
    final s = state;
    if (s == null || s.done || index <= s.index || index >= s.flow.steps.length) return;
    state = AskodoxGuideState(flow: s.flow, index: index);
  }

  void stop() => state = null;
}

final askodoxGuideProvider =
    StateNotifierProvider<AskodoxGuideController, AskodoxGuideState?>((ref) => AskodoxGuideController());

/// Speaks a guide line (device TTS through the ONE native bridge). Off in
/// tests / when unavailable.
typedef AskodoxGuideSpeaker = Future<void> Function(String text, String language);

final askodoxGuideSpeakerProvider = Provider<AskodoxGuideSpeaker>((ref) => (text, language) async {
      try {
        await const MethodChannel('com.askodox.app/device')
            .invokeMethod<bool>('speakReply', {'text': text, 'languageCode': language, 'voicePreference': 'automatic'});
      } catch (_) {}
    });

/// Finds a widget by key value (or `prefix*`) in the live element tree.
Element? askodoxFindKeyed(Element root, String target) {
  final prefix = target.endsWith('*') ? target.substring(0, target.length - 1) : null;
  Element? found;
  void visit(Element e) {
    if (found != null) return;
    final key = e.widget.key;
    if (key is ValueKey) {
      final v = key.value;
      if (v is String && (prefix != null ? v.startsWith(prefix) : v == target)) {
        final box = e.renderObject;
        if (box is RenderBox && box.attached && box.hasSize) {
          found = e;
          return;
        }
      }
    }
    e.visitChildren(visit);
  }

  root.visitChildren(visit);
  return found;
}

/// The overlay above every screen (placed in the app builder).
class AskodoxGuideOverlay extends ConsumerStatefulWidget {
  const AskodoxGuideOverlay({super.key, required this.child, this.router});

  final Widget child;
  final GoRouter? router;

  @override
  ConsumerState<AskodoxGuideOverlay> createState() => _AskodoxGuideOverlayState();
}

class _AskodoxGuideOverlayState extends ConsumerState<AskodoxGuideOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);
  final _stackKey = GlobalKey();
  final _bubbleKey = GlobalKey();
  Timer? _scan;
  Rect? _rect;
  int _missing = 0;
  bool _private = false;
  String? _spoken;

  bool get _te => Localizations.maybeLocaleOf(context)?.languageCode == 'te';

  @override
  void initState() {
    super.initState();
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
    widget.router?.routerDelegate.addListener(_onRoute);
    ref.listenManual<AskodoxGuideState?>(askodoxGuideProvider, (previous, next) {
      if (next == null) {
        _scan?.cancel();
        _scan = null;
        if (mounted) setState(() => _rect = null);
        return;
      }
      _scan ??= Timer.periodic(const Duration(milliseconds: 250), (_) => _locate());
      _missing = 0;
      _locate();
      _speak(next);
      if (next.done) {
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted && identical(ref.read(askodoxGuideProvider), next)) ref.read(askodoxGuideProvider.notifier).stop();
        });
      }
    });
  }

  @override
  void didUpdateWidget(AskodoxGuideOverlay old) {
    super.didUpdateWidget(old);
    if (old.router != widget.router) {
      old.router?.routerDelegate.removeListener(_onRoute);
      widget.router?.routerDelegate.addListener(_onRoute);
    }
  }

  @override
  void dispose() {
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    widget.router?.routerDelegate.removeListener(_onRoute);
    _scan?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  void _onRoute() {
    // The TOP page's location (a pushed /onboarding counts too).
    String location = '';
    try {
      final config = widget.router?.routerDelegate.currentConfiguration;
      location = config == null || config.isEmpty ? '' : config.last.matchedLocation;
    } catch (_) {}
    final private = askodoxGuideIsPrivate(location);
    if (private == _private) return;
    // The router notifies while the app is building: apply after the frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _private != private) setState(() => _private = private);
    });
  }

  void _speak(AskodoxGuideState s) {
    if (_private) return;
    final line = s.done
        ? (_te ? 'పూర్తయింది!' : 'Done!')
        : (_te ? s.step.te : s.step.en);
    final key = '${s.flow.id}:${s.index}:${s.done}';
    if (_spoken == key) return;
    _spoken = key;
    unawaited(ref.read(askodoxGuideSpeakerProvider)(line, _te ? 'te' : 'en'));
  }

  /// Where the current step's button is. A later step's button already on
  /// screen means the user is ahead (skip); nothing on screen for a while
  /// means a wrong screen (offer "Take me there").
  void _locate() {
    final s = ref.read(askodoxGuideProvider);
    final root = _stackKey.currentContext as Element?;
    if (s == null || s.done || root == null || !mounted) return;
    // The current step's button is on screen: stay on it.
    final currentHere = _visible(root, s.step.target) != null;
    // Only after the current button has been missing for a moment (a page
    // transition ignores taps for ~300 ms).
    if (!currentHere && _missing >= 4) {
      for (var i = s.index + 1; i < s.flow.steps.length; i++) {
        if (_visible(root, s.flow.steps[i].target) != null) {
          ref.read(askodoxGuideProvider.notifier).jumpTo(i);
          return;
        }
      }
    }
    final element = askodoxFindKeyed(root, s.step.target);
    Rect? rect = element == null ? null : _rectOf(element);
    if (element != null && rect != null && !_onScreen(rect)) {
      // Below the fold: scroll it into view for the user.
      Scrollable.ensureVisible(element, duration: const Duration(milliseconds: 250), alignment: .3);
      rect = null;
    } else if (element != null && rect != null && !_reachable(element)) {
      rect = null; // another tab / a page underneath: not where the user is
    }
    setState(() {
      _rect = rect;
      _missing = rect == null ? _missing + 1 : 0;
    });
  }

  Rect? _visible(Element root, String target) {
    final e = askodoxFindKeyed(root, target);
    final r = e == null ? null : _rectOf(e);
    return r != null && _onScreen(r) && _reachable(e!) ? r : null;
  }

  /// Truly on the visible screen: a tap at its centre would reach it (not
  /// an offstage tab, not a page under the top page).
  bool _reachable(Element e) {
    final box = e.renderObject as RenderBox?;
    if (box == null || !box.attached || !box.hasSize) return false;
    final centre = box.localToGlobal(box.size.center(Offset.zero));
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(result, centre, View.of(context).viewId);
    final bubble = _bubbleKey.currentContext?.findRenderObject();
    for (final entry in result.path) {
      RenderObject? node = entry.target is RenderObject ? entry.target as RenderObject : null;
      while (node != null) {
        if (identical(node, box)) return true;
        if (bubble != null && identical(node, bubble)) return true; // under our own bubble
        node = node.parent;
      }
    }
    return false;
  }

  Rect? _rectOf(Element e) {
    final box = e.renderObject as RenderBox?;
    final stack = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || stack == null || !box.attached || !box.hasSize) return null;
    final offset = box.localToGlobal(Offset.zero, ancestor: stack);
    return offset & box.size;
  }

  bool _onScreen(Rect r) {
    final size = (_stackKey.currentContext?.findRenderObject() as RenderBox?)?.size;
    if (size == null) return false;
    return r.top >= 0 && r.bottom <= size.height && r.left >= -1 && r.right <= size.width + 1 && r.height > 0;
  }

  /// The user's own tap on the highlighted button completes the step.
  void _onPointer(PointerEvent event) {
    if (event is! PointerUpEvent) return;
    final s = ref.read(askodoxGuideProvider);
    final rect = _rect;
    final stack = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (s == null || s.done || rect == null || stack == null || _private) return;
    final local = stack.globalToLocal(event.position);
    if (rect.inflate(6).contains(local)) {
      // After the tap's own action runs.
      Future.delayed(const Duration(milliseconds: 120), () {
        if (mounted && identical(ref.read(askodoxGuideProvider), s)) ref.read(askodoxGuideProvider.notifier).advance();
      });
    }
  }

  void _takeMeThere(String route) {
    final router = widget.router;
    if (router == null) return;
    const branches = ['/', '/profile', '/updates', '/watchlist'];
    if (branches.contains(route)) {
      router.go(route);
    } else {
      router.push(route);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(askodoxGuideProvider);
    return Stack(key: _stackKey, children: [
      widget.child,
      if (s != null && _private)
        Positioned(
          left: 16,
          right: 16,
          top: MediaQuery.paddingOf(context).top + 8,
          child: Material(
            key: const Key('askodoxGuidePaused'),
            color: const Color(0xFF10204A),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(
                  _te
                      ? 'ఇది ప్రైవేట్ స్క్రీన్ -- గైడ్ ఆగింది. ఇక్కడి వివరాలు చదవదు.'
                      : 'Private screen -- the guide is paused and reads nothing here.',
                  style: const TextStyle(color: Colors.white)),
            ),
          ),
        )
      else if (s != null) ...[
        if (_rect != null && !s.done)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _pulse,
                builder: (context, _) => CustomPaint(
                    key: const Key('askodoxGuideSpotlight'), painter: _SpotlightPainter(_rect!, _pulse.value)),
              ),
            ),
          ),
        if (_rect != null && !s.done) _arrow(_rect!),
        _bubble(context, s),
      ],
    ]);
  }

  Widget _arrow(Rect r) {
    final size = (_stackKey.currentContext?.findRenderObject() as RenderBox?)?.size ?? Size.zero;
    final below = r.center.dy < size.height / 2;
    return Positioned(
      left: (r.center.dx - 18).clamp(0, math.max(0, size.width - 36)).toDouble(),
      top: below ? r.bottom + 4 : r.top - 40,
      child: IgnorePointer(
        child: Icon(below ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
            key: const Key('askodoxGuideArrow'), size: 36, color: const Color(0xFFFFC94D)),
      ),
    );
  }

  Widget _bubble(BuildContext context, AskodoxGuideState s) {
    final size = (_stackKey.currentContext?.findRenderObject() as RenderBox?)?.size ?? MediaQuery.sizeOf(context);
    final r = _rect;
    final atTop = r != null && r.center.dy > size.height / 2;
    final step = s.step;
    final lost = !s.done && r == null && _missing >= 6;
    final text = s.done
        ? (_te ? 'పూర్తయింది! 🎉' : 'Done! 🎉')
        : lost
            ? (_te ? 'ఈ బటన్ ఈ స్క్రీన్‌లో లేదు.' : 'That button is not on this screen.')
            : (_te ? step.te : step.en);
    return Positioned(
      left: 12,
      right: 12,
      top: atTop ? MediaQuery.paddingOf(context).top + 8 : null,
      bottom: atTop ? null : MediaQuery.paddingOf(context).bottom + 96,
      child: Material(
        key: _bubbleKey,
        elevation: 6,
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 6, 6),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${s.flow.title(_te)} · ${s.index + 1}/${s.flow.steps.length}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF6C4DFF), fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(text, key: const Key('askodoxGuideText'),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF10204A))),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              if (lost && step.route != null)
                TextButton(
                    key: const Key('askodoxGuideTakeMe'),
                    onPressed: () => _takeMeThere(step.route!),
                    child: Text(_te ? 'అక్కడికి తీసుకెళ్లు' : 'Take me there')),
              if (!s.done && !s.last)
                TextButton(
                    key: const Key('askodoxGuideSkip'),
                    onPressed: () => ref.read(askodoxGuideProvider.notifier).advance(),
                    child: Text(_te ? 'తర్వాతి దశ' : 'Skip step')),
              TextButton(
                  key: const Key('askodoxGuideStop'),
                  onPressed: () => ref.read(askodoxGuideProvider.notifier).stop(),
                  child: Text(s.done ? (_te ? 'మూసివేయండి' : 'Close') : (_te ? 'ఆపండి' : 'Stop'))),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  _SpotlightPainter(this.target, this.t);
  final Rect target;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final hole = RRect.fromRectAndRadius(target.inflate(6), const Radius.circular(14));
    final dim = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(hole)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(dim, Paint()..color = const Color(0x8C0B1330));
    canvas.drawRRect(
        hole.inflate(2 + 6 * t),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = Color.lerp(const Color(0xFFFFC94D), const Color(0x00FFC94D), t * .7)!);
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) => old.target != target || old.t != t;
}

/// "Show me how" list (Help, Screen Guide page, chat).
class AskodoxGuideList extends ConsumerWidget {
  const AskodoxGuideList({super.key, required this.te, this.onStarted});
  final bool te;
  final VoidCallback? onStarted;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(mainAxisSize: MainAxisSize.min, children: [
        for (final flow in askodoxGuideFlows)
          ListTile(
            key: ValueKey('askodoxGuideStart-${flow.id}'),
            leading: const Icon(Icons.assistant_navigation),
            title: Text(flow.title(te)),
            trailing: const Icon(Icons.play_arrow_rounded),
            onTap: () {
              ref.read(askodoxGuideProvider.notifier).start(flow);
              onStarted?.call();
            },
          ),
      ]);
}
