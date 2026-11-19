import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Owner 2026-11-19: which app / bank a payment alert came from, at a glance. The phone's OWN installed app icon
/// (asked from Android, no copied logos); a bank SMS shows the bank's sender name as a small badge; anything else falls
/// back to the plain arrow icon.
class AskodoxPaymentSourceIcon extends StatefulWidget {
  const AskodoxPaymentSourceIcon({super.key, required this.event, required this.fallback});

  final Map<String, Object?> event;
  final Widget fallback;

  static const _channel = MethodChannel('com.askodox.app/payment_alerts');
  static final Map<String, Future<Uint8List?>> _cache = {};

  static Future<Uint8List?> iconOf(String package) => _cache.putIfAbsent(package, () async {
        try {
          return await _channel.invokeMethod<Uint8List>('appIcon', <String, Object?>{'package': package});
        } catch (_) {
          return null;
        }
      });

  /// "JD-HDFCBK-S" -> "HDFCBK"; '' when the row has no bank sender.
  static String bankBadge(Object? sender) {
    final parts = '${sender ?? ''}'.trim().toUpperCase().split('-');
    return parts.length >= 2 ? parts[1] : '';
  }

  @override
  State<AskodoxPaymentSourceIcon> createState() => _AskodoxPaymentSourceIconState();
}

class _AskodoxPaymentSourceIconState extends State<AskodoxPaymentSourceIcon> {
  Future<Uint8List?>? _icon;

  @override
  void initState() {
    super.initState();
    final package = '${widget.event['source_app'] ?? ''}';
    if (package.contains('.') && widget.event['kind'] != 'sms') _icon = AskodoxPaymentSourceIcon.iconOf(package);
  }

  @override
  Widget build(BuildContext context) {
    final badge = AskodoxPaymentSourceIcon.bankBadge(widget.event['bank_sms_from']);
    if (widget.event['status'] == 'suspect_sender') {
      return const Icon(Icons.warning_amber_rounded, color: Color(0xFFB45309));
    }
    if (_icon == null) {
      if (badge.isEmpty) return widget.fallback;
      return Container(
        width: 40,
        padding: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(color: const Color(0xFFE8EEFB), borderRadius: BorderRadius.circular(8)),
        child: Text(badge,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.fade,
            style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: Color(0xFF1E3FA0))),
      );
    }
    return FutureBuilder<Uint8List?>(
      future: _icon,
      builder: (context, snap) {
        final bytes = snap.data;
        if (bytes == null || bytes.isEmpty) return widget.fallback;
        return ClipRRect(
            borderRadius: BorderRadius.circular(8), child: Image.memory(bytes, width: 32, height: 32, gaplessPlayback: true));
      },
    );
  }
}
