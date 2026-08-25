import 'package:flutter/material.dart';

import '../application/admin_controller.dart';
import 'admin_screens.dart';

String _t(BuildContext context, String en, String te) =>
    Localizations.localeOf(context).languageCode == 'te' ? te : en;

String _title(BuildContext context, AdminSection section) => switch (section) {
  AdminSection.dashboard => _t(context, 'Dashboard', 'డ్యాష్‌బోర్డ్'),
  AdminSection.sellers => _t(context, 'Sellers', 'సెల్లర్లు'),
  AdminSection.catalog => _t(context, 'Catalog', 'కాటలాగ్'),
  AdminSection.productRequests => _t(context, 'Product requests', 'ఉత్పత్తి రిక్వెస్టులు'),
  AdminSection.searchQuality => _t(context, 'Search quality', 'సెర్చ్ నాణ్యత'),
  AdminSection.moderation => _t(context, 'Moderation', 'మోడరేషన్'),
  AdminSection.support => _t(context, 'Support', 'సపోర్ట్'),
  AdminSection.auditLog => _t(context, 'Audit log', 'ఆడిట్ లాగ్'),
  AdminSection.settings => _t(context, 'Settings', 'సెట్టింగ్స్'),
};

String _description(BuildContext context, AdminSection section) => switch (section) {
  AdminSection.dashboard => _t(context, 'Monitor ASKODOX operations and key activity.', 'ASKODOX కార్యకలాపాలు మరియు ముఖ్యమైన యాక్టివిటీని పర్యవేక్షించండి.'),
  AdminSection.sellers => _t(context, 'Review seller accounts, verification and shop status.', 'సెల్లర్ అకౌంట్లు, వెరిఫికేషన్ మరియు షాప్ స్థితిని పరిశీలించండి.'),
  AdminSection.catalog => _t(context, 'Manage products, categories and catalog quality.', 'ఉత్పత్తులు, కేటగిరీలు మరియు కాటలాగ్ నాణ్యతను నిర్వహించండి.'),
  AdminSection.productRequests => _t(context, 'Review customer and seller product requests.', 'కస్టమర్ మరియు సెల్లర్ ఉత్పత్తి రిక్వెస్టులను పరిశీలించండి.'),
  AdminSection.searchQuality => _t(context, 'Track failed searches, corrections and match quality.', 'ఫెయిల్ అయిన సెర్చ్‌లు, సవరణలు మరియు మ్యాచ్ నాణ్యతను ట్రాక్ చేయండి.'),
  AdminSection.moderation => _t(context, 'Review reported or risky content and take action.', 'రిపోర్ట్ అయిన లేదా రిస్క్ ఉన్న కంటెంట్‌ను పరిశీలించి చర్య తీసుకోండి.'),
  AdminSection.support => _t(context, 'Manage support requests and unresolved user issues.', 'సపోర్ట్ రిక్వెస్టులు మరియు పరిష్కారం కాని యూజర్ సమస్యలను నిర్వహించండి.'),
  AdminSection.auditLog => _t(context, 'Review important admin and system changes.', 'ముఖ్యమైన అడ్మిన్ మరియు సిస్టమ్ మార్పులను పరిశీలించండి.'),
  AdminSection.settings => _t(context, 'Configure admin and platform controls.', 'అడ్మిన్ మరియు ప్లాట్‌ఫారమ్ నియంత్రణలను సెట్ చేయండి.'),
};

IconData _icon(AdminSection section) => switch (section) {
  AdminSection.dashboard => Icons.dashboard_outlined,
  AdminSection.sellers => Icons.store_outlined,
  AdminSection.catalog => Icons.inventory_2_outlined,
  AdminSection.productRequests => Icons.playlist_add_check,
  AdminSection.searchQuality => Icons.manage_search,
  AdminSection.moderation => Icons.gavel_outlined,
  AdminSection.support => Icons.support_agent,
  AdminSection.auditLog => Icons.history,
  AdminSection.settings => Icons.settings_outlined,
};

class LocalizedAdminSectionScreen extends StatelessWidget {
  const LocalizedAdminSectionScreen({required this.section, super.key});
  final AdminSection section;

  @override
  Widget build(BuildContext context) {
    final telugu = Localizations.localeOf(context).languageCode == 'te';
    if (!telugu) return AdminSectionScreen(section: section);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(children: [
              CircleAvatar(radius: 24, child: Icon(_icon(section))),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_title(context, section), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(_description(context, section)),
              ])),
            ]),
            const SizedBox(height: 24),
            _AdminInfoCard(section: section),
          ],
        ),
      ),
    );
  }
}

class _AdminInfoCard extends StatelessWidget {
  const _AdminInfoCard({required this.section});
  final AdminSection section;

  @override
  Widget build(BuildContext context) {
    final items = switch (section) {
      AdminSection.dashboard => const [('ఆపరేషన్స్', 'ప్రస్తుత ప్లాట్‌ఫారమ్ కార్యకలాపాలను చూడండి.'), ('క్వాలిటీ', 'సెర్చ్ మరియు కాటలాగ్ నాణ్యతను పర్యవేక్షించండి.'), ('సపోర్ట్', 'పరిష్కారం కావాల్సిన సమస్యలను చూడండి.')],
      AdminSection.sellers => const [('సెల్లర్ వెరిఫికేషన్', 'పెండింగ్ వెరిఫికేషన్‌లను పరిశీలించండి.'), ('షాప్ స్థితి', 'యాక్టివ్ మరియు పరిమితం చేసిన షాప్‌లను చూడండి.'), ('ట్రస్ట్', 'సెల్లర్ ట్రస్ట్ మరియు క్వాలిటీ సంకేతాలను పరిశీలించండి.')],
      AdminSection.catalog => const [('ఉత్పత్తులు', 'కాటలాగ్ ఉత్పత్తులను నిర్వహించండి.'), ('కేటగిరీలు', 'కేటగిరీ నిర్మాణాన్ని పరిశీలించండి.'), ('నాణ్యత', 'తప్పు లేదా అసంపూర్ణ ఉత్పత్తి సమాచారాన్ని సరిచూడండి.')],
      AdminSection.productRequests => const [('కొత్త రిక్వెస్టులు', 'కొత్త ఉత్పత్తి రిక్వెస్టులను పరిశీలించండి.'), ('మ్యాచింగ్', 'సరైన కాటలాగ్ లేదా సెల్లర్‌తో మ్యాచ్ చేయండి.'), ('పెండింగ్', 'ఇంకా పరిష్కారం కాని రిక్వెస్టులను ఫాలోఅప్ చేయండి.')],
      AdminSection.searchQuality => const [('ఫెయిల్ సెర్చ్‌లు', 'ఫలితం రాని సెర్చ్‌లను గుర్తించండి.'), ('సవరణలు', 'తప్పు పదాలు మరియు ప్రత్యామ్నాయ పదాలను మెరుగుపరచండి.'), ('మ్యాచ్ నాణ్యత', 'సెర్చ్ ఫలితాల సంబంధితతను పరిశీలించండి.')],
      AdminSection.moderation => const [('రిపోర్టులు', 'యూజర్లు రిపోర్ట్ చేసిన కంటెంట్‌ను చూడండి.'), ('రిస్క్ రివ్యూ', 'అనుమానాస్పద కంటెంట్‌ను పరిశీలించండి.'), ('చర్యలు', 'అవసరమైన మోడరేషన్ చర్యలను నమోదు చేయండి.')],
      AdminSection.support => const [('ఓపెన్ సమస్యలు', 'ఇంకా పరిష్కారం కాని సపోర్ట్ సమస్యలను చూడండి.'), ('ఎస్కలేషన్', 'మానవ సహాయం అవసరమైన కేసులను గుర్తించండి.'), ('ఫాలోఅప్', 'యూజర్ సమస్య పరిష్కార స్థితిని ట్రాక్ చేయండి.')],
      AdminSection.auditLog => const [('అడ్మిన్ చర్యలు', 'ముఖ్యమైన అడ్మిన్ మార్పులను చూడండి.'), ('సిస్టమ్ మార్పులు', 'ప్లాట్‌ఫారమ్ మార్పుల చరిత్రను పరిశీలించండి.'), ('ట్రేస్', 'ఎప్పుడు ఏ మార్పు జరిగిందో గుర్తించండి.')],
      AdminSection.settings => const [('ప్లాట్‌ఫారమ్', 'ప్రధాన ప్లాట్‌ఫారమ్ నియంత్రణలను నిర్వహించండి.'), ('నోటిఫికేషన్స్', 'అడ్మిన్ అలర్ట్ సెట్టింగ్స్‌ను నిర్వహించండి.'), ('భద్రత', 'యాక్సెస్ మరియు భద్రత నియంత్రణలను పరిశీలించండి.')],
    };
    return Card(child: Column(children: [
      for (var i = 0; i < items.length; i++) ...[
        ListTile(title: Text(items[i].$1, style: const TextStyle(fontWeight: FontWeight.w600)), subtitle: Text(items[i].$2), trailing: const Icon(Icons.chevron_right)),
        if (i != items.length - 1) const Divider(height: 1),
      ],
    ]));
  }
}
