import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  /// "My phone" settings, kept apart from the shop's so both are heard at the same time (owner 2026-11-15, F).
  Future<AskodoxJson> configurePersonal(AskodoxJson config) =>
      _map('configure', {'config': jsonEncode(config), 'scope': 'personal'});
  Future<AskodoxJson> audioRoute() => _map('audioRoute');
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

/// Status label (en, te) -- a notification is never called "received" money.
(String, String) askodoxPaymentStatusLabel(AskodoxJson e) {
  if (e['test'] == true) return ('Test alert', 'టెస్ట్ అలర్ట్');
  return switch ('${e['status']}') {
    'provider_verified' => ('Bank / provider verified', 'బ్యాంక్ / ప్రొవైడర్ నిర్ధారించింది'),
    'ambiguous' => ('Ambiguous — check the app', 'స్పష్టంగా లేదు — యాప్‌లో చూడండి'),
    'failed' => ('Failed', 'విఫలమైంది'),
    _ => ('Notification detected — unverified', 'నోటిఫికేషన్ వచ్చింది — నిర్ధారించలేదు'),
  };
}

/// What happened to the voice on a device (en, te).
(String, String) askodoxSpokenLabel(String state) => switch (state) {
      'announced' => ('Spoken', 'చెప్పింది'),
      'quiet_hours' => ('Silent (quiet hours)', 'నిశ్శబ్ద సమయం — చెప్పలేదు'),
      'late' => ('Arrived late — written, not spoken', 'ఆలస్యంగా వచ్చింది — రాశాం, చెప్పలేదు'),
      'tts_failed' => ('Voice failed', 'వాయిస్ రాలేదు'),
      'muted' => ('Muted', 'మ్యూట్'),
      'seen' => ('Seen', 'చూశారు'),
      'delivered' => ('Delivered', 'అందింది'),
      'pending' => ('Speaking…', 'చెబుతోంది…'),
      _ => ('Not confirmed', 'నిర్ధారణ లేదు'),
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
  lines.add('# Notifications only. Not bank-verified. Not revenue or settled collections.');
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
        return AskodoxMyPhoneAlerts(j['enabled'] == true, apps, '${j['language'] ?? 'te'}', j['say_name'] != false,
            j['announce_debits'] == true, acc, dest, j['setup_done'] == true);
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
