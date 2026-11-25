import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/money_accounts.dart';
import '../domain/money_ledger.dart';
import 'pos_repository.dart';

/// The phone side of payment voice alerts (native channel `com.askodox.app/payment_alerts`).
/// Every method is safe on platforms without the channel (tests, web): it answers "not available".
class AskodoxPaymentAlertsBridge {
  AskodoxPaymentAlertsBridge([MethodChannel? channel]) : _ch = channel ?? const MethodChannel('com.askodox.app/payment_alerts');
  final MethodChannel _ch;

  Future<AskodoxJson> _map(String method, [Map<String, Object?>? args]) async {
    try {
      return askodoxPosMap(await _ch.invokeMethod<Object?>(method, args));
    } on MissingPluginException {
      return {'unavailable': true};
    } on PlatformException catch (e) {
      return {'error': e.message ?? e.code};
    }
  }

  Future<AskodoxJson> status() => _map('status');
  Future<AskodoxJson> configure(AskodoxJson config) => _map('configure', {'config': jsonEncode(config)});

  /// Staff phone: hear [businessId]'s payments with this phone's device id (nothing else changes on the phone).
  Future<bool> joinShop(String businessId, String deviceId, {required String baseUrl, required String token, String language = 'te'}) async {
    try {
      return await _ch.invokeMethod<bool>('joinShop',
              {'businessId': businessId, 'deviceId': deviceId, 'baseUrl': baseUrl, 'token': token, 'language': language}) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// "My phone" settings, kept apart from the shop's so both are heard at the same time (owner 2026-11-15, F).
  Future<AskodoxJson> configurePersonal(AskodoxJson config) =>
      _map('configure', {'config': jsonEncode(config), 'scope': 'personal'});
  Future<AskodoxJson> audioRoute() => _map('audioRoute');

  /// Owner 2026-11-23: an account turned ON for the shop -- its earlier money in "My own" since [since] moves to the
  /// shop (never spoken again). Returns how many moved; 0 off the phone / with no shop on this phone / offline.
  Future<int> moveAccountRows(String tail, DateTime since) async {
    try {
      return await _ch.invokeMethod<int>('moveAccountRows', {'tail': tail, 'sinceMs': since.millisecondsSinceEpoch}) ?? 0;
    } on MissingPluginException {
      return 0;
    } on PlatformException {
      return 0;
    }
  }
  /// Can the phone speak [language] with no internet? (ready / supported / installed / offline)
  Future<AskodoxJson> offlineVoice(String language) => _map('offlineVoice', {'language': language});
  /// Opens the phone's own "download voice data" page.
  Future<void> installOfflineVoice() => _call('installOfflineVoice');
  /// Says / shows today's upcoming payments (2 days before, on the day) -- the phone also does it by itself.
  Future<void> checkDues() => _call('checkDues');
  Future<AskodoxJson> speakTest(int amountPaise, {bool personal = false}) =>
      _map('speakTest', {'amountPaise': amountPaise, if (personal) 'scope': 'personal'});
  Future<AskodoxJson> simulate(String title, String text) => _map('simulate', {'title': title, 'text': text});
  Future<AskodoxJson> showVolume() => _map('showVolume');

  Future<void> _call(String method, [Map<String, Object?>? args]) async {
    try {
      await _ch.invokeMethod<Object?>(method, args);
    } on MissingPluginException {
      // not on a phone
    } on PlatformException {
      // settings screen missing on this phone
    }
  }

  Future<void> speakText(String text, String language) => _call('speakText', {'text': text, 'language': language});

  /// Owner 2026-11-22 (Payment voice folder): which kinds are said aloud, per scope (My phone / the shop on this phone).
  /// Unset kinds keep their default (everything on; "out" follows the older debit switch). Empty map off a phone.
  Future<Map<String, bool>> voiceKinds({required bool personal}) async {
    try {
      final out = await _ch.invokeMethod<String>('voiceKinds', {'scope': personal ? 'personal' : 'shop'});
      final j = jsonDecode(out ?? '{}');
      return j is Map ? {for (final e in j.entries) '${e.key}': e.value == true} : {};
    } catch (_) {
      return {};
    }
  }

  Future<void> setVoiceKinds(Map<String, bool> kinds, {required bool personal}) =>
      _call('setVoiceKinds', {'scope': personal ? 'personal' : 'shop', 'kinds': jsonEncode(kinds)});

  /// Says the example of one kind with the same words and voice a real message gets.
  Future<void> speakKind(String kind, {required bool personal, String? language}) =>
      _call('speakKind', {'kind': kind, 'scope': personal ? 'personal' : 'shop', if (language != null) 'language': language});

  /// Speak an alert another device / the bank reported; each event once per phone (push or screen, whichever first).
  Future<String> speakRemote(String eventId, String text, String language) async {
    try {
      return await _ch.invokeMethod<String>('speakRemote', {'eventId': eventId, 'text': text, 'language': language}) ??
          'unavailable';
    } catch (_) {
      return 'unavailable'; // not on a phone / older native side
    }
  }
  /// Installed? / battery unrestricted? / last time a notification from it reached this phone -- per payment app.
  Future<List<AskodoxJson>> paymentApps(Iterable<String> packages) async {
    try {
      final out = await _ch.invokeMethod<Object?>('paymentApps', {'packages': packages.toList()});
      return out is List ? askodoxPosList(out) : const [];
    } catch (_) {
      return const []; // not on a phone / older native side
    }
  }

  Future<void> openAppNotificationSettings([String? package]) =>
      _call('openAppNotificationSettings', {if (package != null) 'package': package});
  Future<void> openAppDetails([String? package]) => _call('openAppDetails', {if (package != null) 'package': package});
  Future<void> openListenerSettings() => _call('openListenerSettings');
  Future<void> openBatterySettings() => _call('openBatterySettings');
  Future<void> openBluetoothSettings() => _call('openBluetoothSettings');

  /// The phone maker's own "Autostart" page (Xiaomi, Oppo, Vivo, Realme, OnePlus, Huawei, Honor, Asus...).
  /// False when this phone has no such page (Samsung, Pixel, Motorola: nothing to do there).
  Future<bool> openAutostartSettings() async {
    try {
      return await _ch.invokeMethod<bool>('openAutostartSettings') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Opens the notification page of the phone's default SMS app; returns its package (null: none / not a phone).
  Future<String?> openSmsAppSettings() async {
    try {
      return await _ch.invokeMethod<String>('openSmsAppSettings');
    } catch (_) {
      return null;
    }
  }
  Future<void> clear() => _call('clear');

  /// Delete history rows on this phone (null / empty = all).
  Future<int> deleteEvents([List<String>? localIds]) async {
    try {
      final n = await _ch.invokeMethod<Object?>('deleteEvents', {'localIds': localIds});
      return n is int ? n : 0;
    } catch (_) {
      return 0;
    }
  }

  /// Owner 2026-11-21: "wrong" on a history row -- [choice] 'in' (this came in), 'out' (this went out) or 'none'
  /// (not a payment). The phone fixes the row and reads that kind of message the same way from now on.
  Future<AskodoxJson> correctEvent(String localId, String choice) =>
      _map('correctEvent', {'localId': localId, 'choice': choice});

  /// Apps on this phone the person can choose to read (label + package id only).
  Future<List<AskodoxJson>> installedApps() async {
    try {
      final out = await _ch.invokeMethod<Object?>('installedApps');
      return out is List ? askodoxPosList(out) : const [];
    } catch (_) {
      return const [];
    }
  }
  Future<void> markUploaded(String localId, {String? serverId, String? error}) =>
      _call('markUploaded', {'localId': localId, 'serverId': serverId, 'error': error});

  /// Payment-app messages with an amount in wording the phone does not know yet (kept on this phone only).
  Future<List<AskodoxJson>> unknowns() async {
    try {
      final raw = await _ch.invokeMethod<String>('unknowns');
      return askodoxPosList(jsonDecode(raw ?? '[]'));
    } catch (_) {
      return const [];
    }
  }

  /// The person's answer for one unknown message: received (speak this wording from now on) or sent (ignore it).
  Future<AskodoxJson> learnUnknown(String id, {required bool received}) => _map('learnUnknown', {'id': id, 'received': received});

  Future<List<AskodoxJson>> localEvents() async {
    try {
      final raw = await _ch.invokeMethod<String>('events');
      return askodoxPosList(jsonDecode(raw ?? '[]'));
    } catch (_) {
      return const [];
    }
  }

  /// A detection on this phone while the app is open (the screen refreshes).
  void onEvent(void Function(AskodoxJson event)? handler) {
    _ch.setMethodCallHandler(handler == null
        ? null
        : (call) async {
            if (call.method == 'paymentEvent') {
              try {
                handler(askodoxPosMap(jsonDecode('${call.arguments}')));
              } catch (_) {}
            }
            return null;
          });
  }
}

final askodoxPaymentAlertsBridgeProvider = Provider<AskodoxPaymentAlertsBridge>((ref) => AskodoxPaymentAlertsBridge());

/// Same default list as the server (`pos_payment_alerts.DEFAULT_APPS`), used only in phone-only mode.
const askodoxDefaultPaymentApps = <String, Object?>{
  'com.phonepe.app.business': 'PhonePe Business',
  'com.phonepe.app': 'PhonePe',
  'com.google.android.apps.nbu.paisa.merchant': 'Google Pay for Business',
  'com.google.android.apps.nbu.paisa.user': 'Google Pay',
  'com.paytm.business': 'Paytm for Business',
  'net.one97.paytm': 'Paytm',
  'in.org.npci.upiapp': 'BHIM',
};

/// SMS apps whose notifications carry bank messages ("Rs 500 credited to A/c XX1234") -- QR payments often give
/// only the bank SMS. Off the notification only: the app never reads the SMS inbox.
const askodoxSmsApps = <String, Object?>{
  'com.google.android.apps.messaging': 'Messages (Google)',
  'com.samsung.android.messaging': 'Messages (Samsung)',
  'com.android.mms': 'Messages',
};

/// Banking / wallet apps the person may add with one tap (installed ones are shown first on the screen).
final askodoxKnownMoneyApps = <String, Object?>{
  for (final e in askodoxMoneyAppCatalog.entries)
    if (!askodoxDefaultPaymentApps.containsKey(e.key) && !askodoxSmsApps.containsKey(e.key)) e.key: e.value.$1,
};

/// Every money app ASKODOX knows by name: package -> (label, kind). kind = upi | bank | sms.
/// Not a fixed allow-list (owner 2026-11-15: "no fixed list, any app / bank"): an app missing here is still found
/// on the phone by [askodoxLooksLikeMoneyApp] and can always be added by hand.
const askodoxMoneyAppCatalog = <String, (String, String)>{
  // UPI / wallets
  'com.phonepe.app': ('PhonePe', 'upi'),
  'com.phonepe.app.business': ('PhonePe Business', 'upi'),
  'com.google.android.apps.nbu.paisa.user': ('Google Pay', 'upi'),
  'com.google.android.apps.nbu.paisa.merchant': ('Google Pay for Business', 'upi'),
  'net.one97.paytm': ('Paytm', 'upi'),
  'com.paytm.business': ('Paytm for Business', 'upi'),
  'in.org.npci.upiapp': ('BHIM', 'upi'),
  'money.super.payments': ('super.money', 'upi'),
  'com.dreamplug.androidapp': ('CRED', 'upi'),
  'in.amazon.mShop.android.shopping': ('Amazon Pay', 'upi'),
  'com.mobikwik_new': ('MobiKwik', 'upi'),
  'com.freecharge.android': ('Freecharge', 'upi'),
  'com.naviapp': ('Navi', 'upi'),
  'com.fampay.in': ('FamPay', 'upi'),
  'com.myairtelapp': ('Airtel Thanks', 'upi'),
  'com.samsung.android.spay': ('Samsung Wallet', 'upi'),
  'com.whatsapp.w4b': ('WhatsApp Business', 'upi'),
  // Banks
  'com.sbi.lotusintouch': ('YONO SBI', 'bank'),
  'com.sbi.SBIFreedomPlus': ('SBI YONO Lite', 'bank'),
  'com.sbi.upi': ('BHIM SBI Pay', 'bank'),
  'com.snapwork.hdfc': ('HDFC Bank', 'bank'),
  'com.enstage.wibmo.hdfc': ('PayZapp (HDFC)', 'bank'),
  'com.csam.icici.bank.imobile': ('ICICI iMobile Pay', 'bank'),
  'com.axis.mobile': ('Axis Mobile', 'bank'),
  'com.msf.kbank.mobile': ('Kotak Bank', 'bank'),
  'com.bankofbaroda.mconnect': ('bob World', 'bank'),
  'com.canarabank.mobility': ('Canara ai1', 'bank'),
  'com.Version1': ('PNB ONE', 'bank'),
  'com.idfcfirstbank.optimus': ('IDFC FIRST Bank', 'bank'),
  'com.fedmobile': ('FedMobile', 'bank'),
  // SMS apps: bank SMS reach the phone through their notification (the SMS inbox is never read)
  'com.google.android.apps.messaging': ('Messages (Google)', 'sms'),
  'com.samsung.android.messaging': ('Messages (Samsung)', 'sms'),
  'com.android.mms': ('Messages', 'sms'),
  'com.truecaller': ('Truecaller (SMS)', 'sms'),
};

/// upi | bank | sms for any package (catalogue first, then the app's own name / package words).
String askodoxMoneyAppKind(String package, [String label = '']) {
  final known = askodoxMoneyAppCatalog[package];
  if (known != null) return known.$2;
  final t = '${package.toLowerCase()} ${label.toLowerCase()}';
  if (t.contains('messag') || t.contains('mms') || t.contains('sms')) return 'sms';
  if (t.contains('bank') || t.contains('yono') || t.contains('imobile')) return 'bank';
  return 'upi';
}

/// True for an installed app that is very likely a payment / bank / SMS app (shown as a suggestion, never added
/// without the person's tap).
bool askodoxLooksLikeMoneyApp(String package, String label) {
  if (askodoxMoneyAppCatalog.containsKey(package)) return true;
  final p = package.toLowerCase();
  final l = ' ${label.toLowerCase()} ';
  const words = [' bank', 'bank ', ' upi', 'upi ', ' pay', 'pay ', 'wallet', 'yono', 'imobile', ' messages', 'sms'];
  return p.contains('bank') || p.contains('.upi') || words.any(l.contains);
}

/// Business payment apps go to the shop by default, everything else to "My phone" (same rule as the phone side).
bool askodoxIsBusinessApp(String package) {
  final p = package.toLowerCase();
  return p.contains('business') || p.contains('merchant') || p.contains('.biz') || p.endsWith('forbusiness');
}

const askodoxPaymentAlertDeviceKey = 'askodox.pos.payalert.device.v1';

/// Stable random id for THIS install (never a hardware id).
Future<String> askodoxPaymentAlertInstallKey() async {
  final prefs = await SharedPreferences.getInstance();
  var key = prefs.getString(askodoxPaymentAlertDeviceKey) ?? '';
  if (key.isEmpty) {
    final r = Random.secure();
    key = 'dev-${List.generate(16, (_) => r.nextInt(36).toRadixString(36)).join()}';
    await prefs.setString(askodoxPaymentAlertDeviceKey, key);
  }
  return key;
}

/// Sends phone detections the native side could not upload (offline / app closed). Never drops one silently:
/// a refusal is stored on the local event with the server's code.
Future<int> askodoxSyncPaymentAlerts(AskodoxPosRepository repo, AskodoxPaymentAlertsBridge bridge, String businessId,
    String? deviceId) async {
  var sent = 0;
  for (final e in await bridge.localEvents()) {
    if (e['server_id'] != null || e['upload_error'] != null || e['test'] == true || e['direction'] != null) continue;
    final localId = '${e['local_id'] ?? ''}';
    if (localId.isEmpty) continue;
    final spoken = '${e['spoken'] ?? ''}';
    try {
      final out = await repo.reportPaymentEvent(businessId, {
        'client_event_id': e['client_event_id'],
        'source_app': e['source_app'],
        if (e['amount_paise'] != null) 'amount_paise': e['amount_paise'],
        if (e['reference'] != null) 'reference': e['reference'],
        'detected_at': e['detected_at'],
        if (e['reason'] != null) 'reason': e['reason'],
        if (deviceId != null) 'device_id': deviceId,
        if (spoken.isNotEmpty && spoken != 'pending') 'spoken': spoken,
      });
      await bridge.markUploaded(localId, serverId: '${out['id']}');
      sent++;
    } on AskodoxPosException catch (err) {
      if (!err.retryable && err.kind != 'sign_in') {
        await bridge.markUploaded(localId, error: err.code.isEmpty ? err.kind : err.code);
      }
    }
  }
  return sent;
}

/// "₹1,250.50" from paise (Indian grouping).
String askodoxRupees(Object? paise) {
  if (paise is! num) return '₹—';
  final p = paise.toInt();
  final rupees = p ~/ 100;
  final rest = p % 100;
  final digits = '$rupees';
  String grouped;
  if (digits.length <= 3) {
    grouped = digits;
  } else {
    final last3 = digits.substring(digits.length - 3);
    var head = digits.substring(0, digits.length - 3);
    final parts = <String>[];
    while (head.length > 2) {
      parts.insert(0, head.substring(head.length - 2));
      head = head.substring(0, head.length - 2);
    }
    if (head.isNotEmpty) parts.insert(0, head);
    grouped = '${parts.join(',')},$last3';
  }
  return rest == 0 ? '₹$grouped' : '₹$grouped.${rest.toString().padLeft(2, '0')}';
}

/// Status label (en, te). Owner 2026-11-18: only "received" (అందింది), never "confirmed" / "verified".
(String, String) askodoxPaymentStatusLabel(AskodoxJson e) {
  if (e['test'] == true) return ('Test alert', 'టెస్ట్ అలర్ట్');
  return switch ('${e['status']}') {
    'provider_verified' => ('Received (Razorpay)', 'Razorpay లో అందింది'),
    'ambiguous' => ('Ambiguous — check the app', 'స్పష్టంగా లేదు — యాప్‌లో చూడండి'),
    // Owner 2026-11-19: a "money received" SMS from a person's mobile number -- banks never send from one.
    'suspect_sender' => ('⚠️ SMS from a person\'s number, not a bank — likely fake. Check your bank app.',
        '⚠️ ఇది బ్యాంక్ నుంచి కాదు, ఒక వ్యక్తి నంబర్ నుంచి వచ్చిన SMS — మోసం కావచ్చు. బ్యాంక్ యాప్‌లో చూసుకోండి.'),
    'failed' => ('Failed', 'విఫలమైంది'),
    _ => ('Received (app notification) — check your bank app', 'నోటిఫికేషన్‌లో అందింది — బ్యాంక్ యాప్‌లో చూసుకోండి'),
  };
}

/// Owner 2026-11-17: a phone row the bank's own SMS (registered sender, e.g. JD-HDFCBK-S) also reported = the money
/// came. (en, te), or null for money sent. Owner 2026-11-18: "received" only, never "confirmed".
(String, String)? askodoxBankConfirmedLabel(Map<String, Object?>? local) {
  if (local == null || local['direction'] == 'out') return null;
  if (local['status'] == 'suspect_sender') {
    return ('⚠️ Not from a bank — likely fake SMS', '⚠️ బ్యాంక్ నుంచి కాదు — మోసపు SMS కావచ్చు');
  }
  if (local['bank_confirmed'] == true) return ('✅ Received (bank SMS)', '✅ బ్యాంక్ SMS లో అందింది');
  return ('⏳ Bank SMS not seen yet', '⏳ బ్యాంక్ SMS ఇంకా రాలేదు');
}

/// What happened to the voice on a device (en, te).
(String, String) askodoxSpokenLabel(String state) => switch (state) {
      'announced' => ('Spoken', 'చెప్పింది'),
      'quiet_hours' => ('Silent (quiet hours)', 'నిశ్శబ్ద సమయం — చెప్పలేదు'),
      'late' => ('Arrived late — written, not spoken', 'ఆలస్యంగా వచ్చింది — రాశాం, చెప్పలేదు'),
      'tts_failed' => ('Voice failed', 'వాయిస్ రాలేదు'),
      'muted' => ('Muted', 'మ్యూట్'),
      'seen' => ('Seen', 'చూశారు'),
      'suspect' => ('Not counted — the phone said "this looks fake"', 'లెక్కలో లేదు — "నకిలీలా ఉంది" అని చెప్పింది'),
      'delivered' => ('Delivered', 'అందింది'),
      'pending' => ('Speaking…', 'చెబుతోంది…'),
      'stuck' => ('Voice got stuck — not spoken', 'వాయిస్ ఆగిపోయింది — చెప్పలేదు'),
      'duplicate_local' => ('Spoken by this phone itself', 'ఈ ఫోన్ తానే చెప్పింది'),
      'waiting' => ('Waiting for the bank SMS (1 min)', 'బ్యాంక్ SMS కోసం ఆగుతోంది (1 నిమిషం)'),
      'skipped_bank' => ('Not spoken — the bank SMS said otherwise', 'చెప్పలేదు — బ్యాంక్ SMS వేరేగా చెప్పింది'),
      _ => ('No answer from the phone', 'ఫోన్ నుంచి సమాచారం లేదు'),
    };

/// CSV of non-sensitive fields (no names, phones or notification text).
String askodoxPaymentAlertsCsv(List<AskodoxJson> events) {
  final lines = ['detected_at,amount_rupees,source,reference_last4,status,test'];
  for (final e in events) {
    final amount = e['amount_paise'] is num ? ((e['amount_paise'] as num) / 100).toStringAsFixed(2) : '';
    lines.add([
      '${e['detected_at'] ?? ''}',
      amount,
      '${e['source_label'] ?? ''}'.replaceAll(',', ' '),
      '${e['reference_tail'] ?? ''}',
      '${e['status'] ?? ''}',
      e['test'] == true ? '1' : '0',
    ].join(','));
  }
  lines.add('# Received per phone notifications only - check your bank app. Not revenue or settled collections.');
  return '${lines.join('\n')}\n';
}


/// A normal person's OWN phone (no shop, no registered UPI ids): which apps / SMS to read, how to speak, account names.
/// Everything is kept on this phone only (owner 2026-11-15: "whoever wants any app or bank SMS; each person's history
/// is their own"). Defaults: the payment apps + common SMS apps; every item can be edited or deleted.
class AskodoxMyPhoneAlerts {
  AskodoxMyPhoneAlerts(this.enabled, this.apps, this.language, this.sayName, this.announceDebits, this.accounts,
      [Map<String, String>? destinations, this.setupDone = false])
      : destinations = destinations ?? {};

  bool enabled;
  Map<String, String> apps; // package -> label
  String language; // te | hi | en
  bool sayName;
  bool announceDebits;
  Map<String, String> accounts; // last digits -> person's name for it ("Savings", "Shop current")

  /// package -> 'shop' | 'mine' when the phone also listens for a shop (owner 2026-11-15, F). Missing = default
  /// ([askodoxIsBusinessApp] -> shop, else mine).
  Map<String, String> destinations;

  /// True once the apps found on this phone were offered the first time (never re-added after the person deletes).
  bool setupDone;

  /// Owner 2026-11-17: every place money comes in / goes out -- bank accounts, UPI IDs, wallets, QR codes.
  /// Bank places are kept in step with [accounts] (last digits -> name), which the history and the voice read.
  List<AskodoxMoneyPlace> places = [];

  /// History rows the person moved to an account by hand (localId -> account key).
  Map<String, String> assigned = {};

  /// "Ways to get paid" (server method ids) imported once and deleted by the person: never re-added.
  Set<String> dismissedMethods = {};

  /// Say the account's name in the voice ("HDFC current: Rs 240 came").
  bool sayAccount = false;

  /// One money history (owner 2026-11-17): payment row id -> the bill it paid ("mybill:TOKEN"), joined by a tap.
  Map<String, String> links = {};

  /// The person's category for one row / for every payment to one payee.
  Map<String, String> rowCategory = {};
  Map<String, String> payeeCategory = {};

  /// Upcoming payments the person keeps (EMI, current bill, rent, recharge ...).
  List<AskodoxDue> dues = [];

  /// "paymentId|billId" pairs and due / EMI suggestions the person said no to.
  Set<String> dismissed = {};

  /// Rebuilds [accounts] from the bank places (the native side and older screens read it).
  void syncAccounts() => accounts = {for (final p in places) if (p.type == 'bank' && p.tail.isNotEmpty) p.tail: p.name};

  String destinationOf(String package) =>
      destinations[package] ?? (askodoxIsBusinessApp(package) ? 'shop' : 'mine');

  static const _key = 'askodox.mine.payalert.v1';

  static Map<String, String> defaultApps() =>
      {for (final e in {...askodoxDefaultPaymentApps, ...askodoxSmsApps}.entries) e.key: '${e.value}'};

  static Future<AskodoxMyPhoneAlerts> load() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final j = jsonDecode(prefs.getString(_key) ?? '{}');
      if (j is Map) {
        final apps = j['apps'] is Map ? {for (final e in (j['apps'] as Map).entries) '${e.key}': '${e.value}'} : defaultApps();
        final acc = j['accounts'] is Map ? {for (final e in (j['accounts'] as Map).entries) '${e.key}': '${e.value}'} : <String, String>{};
        final dest = j['destinations'] is Map
            ? {for (final e in (j['destinations'] as Map).entries) '${e.key}': '${e.value}'}
            : <String, String>{};
        final m = AskodoxMyPhoneAlerts(j['enabled'] == true, apps, '${j['language'] ?? 'te'}', j['say_name'] != false,
            j['announce_debits'] == true, acc, dest, j['setup_done'] == true);
        m.places = j['places'] is List
            ? (j['places'] as List).map(AskodoxMoneyPlace.fromJson).whereType<AskodoxMoneyPlace>().toList()
            // first open after the update: the named bank accounts become places
            : [for (final e in acc.entries) AskodoxMoneyPlace(key: askodoxBankKey(e.key), type: 'bank', name: e.value, tail: e.key)];
        m.assigned = j['assigned'] is Map ? {for (final e in (j['assigned'] as Map).entries) '${e.key}': '${e.value}'} : {};
        m.dismissedMethods = j['dismissed_methods'] is List ? {for (final x in j['dismissed_methods'] as List) '$x'} : {};
        m.sayAccount = j['say_account'] == true;
        Map<String, String> strMap(Object? x) => x is Map ? {for (final e in x.entries) '${e.key}': '${e.value}'} : {};
        m.links = strMap(j['links']);
        m.rowCategory = strMap(j['row_category']);
        m.payeeCategory = strMap(j['payee_category']);
        m.dues = j['dues'] is List ? (j['dues'] as List).map(AskodoxDue.fromJson).whereType<AskodoxDue>().toList() : [];
        m.dismissed = j['dismissed'] is List ? {for (final x in j['dismissed'] as List) '$x'} : {};
        m.syncAccounts();
        return m;
      }
    } catch (_) {}
    return AskodoxMyPhoneAlerts(false, defaultApps(), 'te', true, false, {});
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key,
        jsonEncode({
          'enabled': enabled,
          'apps': apps,
          'language': language,
          'say_name': sayName,
          'announce_debits': announceDebits,
          'accounts': accounts,
          'destinations': destinations,
          'setup_done': setupDone,
          'places': [for (final p in places) p.toJson()],
          // only the newest 500 hand moves are kept
          'assigned': Map.fromEntries(assigned.entries.toList().reversed.take(500).toList().reversed),
          'dismissed_methods': dismissedMethods.toList(),
          'say_account': sayAccount,
          'links': links,
          'row_category': Map.fromEntries(rowCategory.entries.toList().reversed.take(1000).toList().reversed),
          'payee_category': payeeCategory,
          'dues': [for (final d in dues) d.toJson()],
          'dismissed': dismissed.toList().reversed.take(500).toList(),
        }));
  }

  /// What the native listener needs: NO business id = personal mode (credits + debits kept on the phone only).
  Map<String, Object?> nativeConfig({String baseUrl = '', String token = ''}) => {
        'enabled': enabled,
        'language': language,
        'voice': 'female',
        'say_name': sayName,
        'announce_debits': announceDebits,
        'cloud_voice': true,
        'rate_pct': 100,
        'volume_pct': 100,
        'loud': true,
        'chime': true,
        'quiet_start': '',
        'quiet_end': '',
        'apps': apps,
        'kinds': {for (final e in apps.entries) e.key: askodoxMoneyAppKind(e.key, e.value)},
        'destinations': destinations,
        'say_account': sayAccount,
        'account_names': accounts,
        // owner 2026-11-23: each account ON for "My own", the shop, or OFF -- the account decides, not the app
        'account_sides': askodoxAccountSideMaps(places).accounts,
        'app_sides': askodoxAccountSideMaps(places).apps,
        // the next date of each upcoming payment: the phone says it 2 days before and on the day
        'dues': [
          for (final d in dues)
            if (askodoxNextDue(d, DateTime.now()) case final next?)
              {'id': d.id, 'name': d.name, 'amount_paise': d.amountPaise, 'date': askodoxDay(next)},
        ],
        'business_id': '',
        'device_id': '',
        'base_url': baseUrl, // the chosen ElevenLabs voice for "My phone" too (device voice when empty / offline)
        'token': token,
      };

  /// The person's own name for an account tail ("Savings"), or "A/c ••1234".
  String accountName(String? tail) {
    if (tail == null || tail.isEmpty) return '';
    final mine = accounts[tail];
    return mine != null && mine.isNotEmpty ? mine : 'A/c ••$tail';
  }
}

/// Owner 2026-11-20 ("each staff phone needs setup -- no"): every shop where this person is STAFF is joined by itself
/// at app start, so the shop's payments are spoken on their phone with no page to open. Run once per app start
/// (`main()` turns it on); errors are ignored (the next start tries again).
bool askodoxAutoJoinStaffVoices = false;

Future<int> askodoxJoinStaffShopVoices(AskodoxPosRepository repo, AskodoxPaymentAlertsBridge bridge,
    {required String baseUrl, required String token}) async {
  if (!askodoxAutoJoinStaffVoices || token.isEmpty || baseUrl.isEmpty) return 0;
  var joined = 0;
  try {
    final key = await askodoxPaymentAlertInstallKey();
    for (final shop in await repo.businesses()) {
      final role = '${shop['my_role'] ?? ''}';
      if (role.isEmpty || role == 'owner') continue;
      try {
        final out = await repo.registerAlertDevice('${shop['id']}', {
          'device_key': key,
          'label': 'Phone ${key.substring(key.length - 4)}',
          'listener_on': false,
          'speaks_remote': true,
        });
        final device = '${out['device_id'] ?? ''}';
        if (device.isNotEmpty && await bridge.joinShop('${shop['id']}', device, baseUrl: baseUrl, token: token)) joined++;
      } on AskodoxPosException {
        // this shop does not use payment alerts (or the owner turned them off): skip it
      }
    }
  } catch (_) {}
  return joined;
}

/// Owner 2026-11-21: a row set aside (the bank's SMS said the opposite, or the person marked "not a payment") stays
/// visible with ❓ but never counts as money.
bool askodoxRowCountsAsMoney(Map<String, Object?> e) =>
    e['test'] != true && e['excluded'] != true && e['status'] != 'suspect_sender';

/// Owner 2026-11-21: a money message that is NOT a payment (refund started, payment initiated / failed, bill
/// generated, suspicious) -- why it came and what to check (en, te). Never counted, never spoken.
(String, String)? askodoxNoticeNote(Map<String, Object?> e) => switch ('${e['info'] ?? ''}') {
      'refund_started' => (
          'ℹ️ Refund started — the money has NOT come yet. Watch for the bank SMS in a few days.',
          'ℹ️ రిఫండ్ మొదలైంది — డబ్బు ఇంకా రాలేదు. కొన్ని రోజుల్లో బ్యాంక్ SMS వస్తుందేమో చూడండి.'
        ),
      'pending' => (
          'ℹ️ Payment started / pending — not finished. Check your bank app before paying again.',
          'ℹ️ పేమెంట్ మొదలైంది / pending — ఇంకా పూర్తి కాలేదు. మళ్ళీ కట్టే ముందు బ్యాంక్ యాప్‌లో చూడండి.'
        ),
      'failed' => (
          'ℹ️ Payment failed. If money was cut, it usually comes back; if not in a few days, ask your bank.',
          'ℹ️ పేమెంట్ ఫెయిల్ అయింది. డబ్బు కట్ అయితే సాధారణంగా తిరిగి వస్తుంది; కొన్ని రోజుల్లో రాకపోతే బ్యాంక్‌ను అడగండి.'
        ),
      // Owner 2026-11-25 (the ❓ net): a bank SMS with an amount the phone could not read -- asked, never guessed.
      'ask' => (
          '❓ Not understood — did this money come in or go out? Tap and say it once; the phone reads this kind by itself after that.',
          '❓ ఈ బ్యాంక్ మెసేజ్ అర్థం కాలేదు — డబ్బు వచ్చిందా, వెళ్ళిందా? నొక్కి ఒకసారి చెప్పండి; తర్వాత నుంచి ఫోనే చదువుతుంది.'
        ),
      'bill' => askodoxBillNote(e),
      // Owner 2026-11-22 ("cancel, autopay, someone asking for money ... read those too")
      'cancelled' => (
          'ℹ️ Payment cancelled — no money moved. If money was cut, check your bank app.',
          'ℹ️ పేమెంట్ రద్దయింది — డబ్బు కదలలేదు. డబ్బు కట్ అయితే బ్యాంక్ యాప్‌లో చూడండి.'
        ),
      'autopay' => (
          'ℹ️ AutoPay set up — money will be taken on its date. Stop it in the app that set it if you did not want it.',
          'ℹ️ ఆటోపే సెట్ అయింది — దాని తేదీకి డబ్బు కట్ అవుతుంది. మీరు పెట్టకపోతే ఆ యాప్‌లోనే ఆపండి.'
        ),
      'autopay_off' => ('ℹ️ AutoPay stopped — no more money will be taken for it.', 'ℹ️ ఆటోపే రద్దయింది — ఇక దానికి డబ్బు కట్ అవ్వదు.'),
      'request' => (
          '⚠️ Someone is asking you to PAY. Money goes only if you approve — never approve to "receive" money.',
          '⚠️ ఎవరో మిమ్మల్ని డబ్బు అడుగుతున్నారు. మీరు ఒప్పుకుంటేనే డబ్బు పోతుంది — "డబ్బు రావడానికి" ఎప్పుడూ ఒప్పుకోవద్దు.'
        ),
      'suspect' => (
          '⚠️ Suspicious message — do not tap any link. Check your bank app to see if money really came.',
          '⚠️ అనుమానాస్పద message — లింక్ నొక్కకండి. డబ్బు నిజంగా వచ్చిందో మీ బ్యాంక్ యాప్‌లో చూడండి.'
        ),
      _ => null,
    };

/// Owner 2026-11-22: a bill that CAME (not paid yet) says its last date when the message gave one ("2026-12-05" ->
/// "05-12-2026"); when the bill is paid the payment is its own row.
(String, String) askodoxBillNote(Map<String, Object?> e) {
  final due = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch('${e['due_date'] ?? ''}');
  if (due == null) {
    return (
      'ℹ️ Bill generated — this is what you have to pay, not money paid. Check the bill amount.',
      'ℹ️ బిల్ వచ్చింది — ఇది కట్టాల్సింది, కట్టింది కాదు. బిల్లు మొత్తం సరిచూసుకోండి.'
    );
  }
  final date = '${due.group(3)}-${due.group(2)}-${due.group(1)}';
  return (
    'ℹ️ Bill came — to be paid by $date; not money paid. It is also in Upcoming payments.',
    'ℹ️ బిల్ వచ్చింది — $date లోపు కట్టాలి; ఇది కట్టిన డబ్బు కాదు. "రాబోయే చెల్లింపులు" లో కూడా ఉంది.'
  );
}

/// The ❓ note of a doubtful row (en, te), or null.
(String, String)? askodoxRowDoubt(Map<String, Object?> e) => askodoxNoticeNote(e) ?? switch ('${e['doubt'] ?? ''}') {
      'bank_opposite' => (
          '❓ The bank SMS says the opposite — this app message was read wrongly; not counted',
          '❓ బ్యాంక్ SMS వేరేగా చెప్పింది — ఈ యాప్ message తప్పుగా చదివాం; లెక్కలో వేయలేదు'
        ),
      'not_payment' => ('❓ Marked "not a payment" — not counted', '❓ "payment కాదు" అన్నారు — లెక్కలో వేయలేదు'),
      'wording' => ('❓ Not sure it went out — check and correct if wrong', '❓ వెళ్ళిందో లేదో ఖచ్చితంగా లేదు — తప్పైతే సరిచేయండి'),
      _ => null,
    };
