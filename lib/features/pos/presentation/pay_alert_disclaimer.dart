import 'package:flutter/material.dart';

/// Owner 2026-11-18: payment alerts only ever say "received" (అందింది) -- never "confirmed" (నిర్ధారించింది).
/// ONE disclaimer note (CashAlert-style) shown on every payment-alert page: who we are not, what we read,
/// that alerts are not guaranteed, and that we are not linked to NPCI / UPI / RBI / banks / payment apps.
List<String> askodoxPayAlertDisclaimerLines(bool te) => te
    ? const [
        'ASKODOX బ్యాంక్ లేదా పేమెంట్ సంస్థ కాదు. డబ్బు మేము తీసుకోము, పంపము — కస్టమర్లు మీ UPI / QR కే నేరుగా కడతారు.',
        'ఫోన్‌కు వచ్చే పేమెంట్ యాప్ నోటిఫికేషన్ / బ్యాంక్ SMS చదివి "అందింది" అని మాత్రమే చెబుతాం. ఖాతాలో పడిందో లేదో మీ బ్యాంక్ యాప్‌లో ఒకసారి చూసుకోండి.',
        'అలర్ట్స్ ఫోన్, నెట్‌వర్క్, నోటిఫికేషన్ అనుమతిని బట్టి ఆలస్యం కావచ్చు లేదా రాకపోవచ్చు — హామీ లేదు.',
        'ASKODOX కు NPCI, UPI, RBI, బ్యాంకులు, పేమెంట్ యాప్‌లతో ఎలాంటి అనుబంధం లేదు.',
      ]
    : const [
        'ASKODOX is not a bank or a payment company. We never take or send money — customers pay your own UPI / QR.',
        'We read the payment app notification / bank SMS on your phone and only say "received". Check your bank app to see the money in your account.',
        'Alerts depend on the phone, network and notification access — they can be late or missed. No guarantee.',
        'ASKODOX is not affiliated with NPCI, UPI, RBI, any bank or payment app.',
      ];

class AskodoxPayAlertDisclaimer extends StatelessWidget {
  const AskodoxPayAlertDisclaimer({super.key, required this.te});

  final bool te;

  @override
  Widget build(BuildContext context) => Container(
        key: const Key('askodoxPayAlertDisclaimer'),
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: const Color(0xFFF6F7F9), borderRadius: BorderRadius.circular(10)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(te ? 'గమనిక' : 'Note', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            for (final line in askodoxPayAlertDisclaimerLines(te))
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text('• $line', style: const TextStyle(fontSize: 11.5, color: Color(0xFF5B6475))),
              ),
          ],
        ),
      );
}
