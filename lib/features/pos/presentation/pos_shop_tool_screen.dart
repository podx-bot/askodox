import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/pos_repository.dart';
import 'pos_common.dart';

/// Shop tool -> its page inside the shop (`<id>` is filled in). Owner 2026-11-19: a shop person opens ANY shop tool by
/// talking ("new bill", "my AI agents", "stock") or from a pin, without first finding the shop dashboard.
const askodoxShopTools = <String, (String, String, String)>{
  'sale': ('/pos/<id>/sale', 'New bill', 'కొత్త బిల్లు'),
  'payment-alerts': ('/pos/<id>/payment-alerts', 'Payment alerts', 'పేమెంట్ అలర్ట్స్'),
  'collect': ('/pos/<id>/collect', 'Collect by UPI', 'UPI తో కట్టించుకోండి'),
  'orders': ('/desk/<id>', 'Orders desk', 'ఆర్డర్స్ డెస్క్'),
  'tables': ('/pos/<id>/tables', 'Tables & KOT', 'టేబుల్స్ & KOT'),
  'kitchen': ('/pos/<id>/kitchen', 'Kitchen screen', 'వంటగది స్క్రీన్'),
  'items': ('/pos/<id>/items', 'Items & stock', 'సరుకులు & స్టాక్'),
  'suppliers': ('/pos/<id>/suppliers', 'Suppliers & purchases', 'సప్లయర్లు & కొనుగోళ్లు'),
  'expiry': ('/pos/<id>/stock-report', 'Expiry & stock value', 'ఎక్స్‌పైరీ & స్టాక్ విలువ'),
  'customers': ('/pos/<id>/customers', 'Customers & credit', 'కస్టమర్లు & ఖాతా'),
  'dues': ('/pos/<id>/dues', 'Baaki reminders', 'బాకీ గుర్తులు'),
  'agents': ('/pos/<id>/agents', 'AI agents', 'AI Agents'),
  'bills': ('/pos/<id>/invoices', 'Bills', 'బిల్లులు'),
  'day': ('/pos/<id>/day', 'Day close', 'రోజు ముగింపు'),
  'gst': ('/pos/<id>/gst', 'GST summary', 'GST సారాంశం'),
  'staff': ('/pos/<id>/staff', 'Staff & roles', 'సిబ్బంది'),
  'printer': ('/pos/<id>/printer', 'Printer', 'ప్రింటర్'),
  'advance': ('/pos/<id>/advance', 'Shop advance', 'షాప్ అడ్వాన్స్'),
  'selfshop': ('/pos/<id>/selfshop', 'Self-shopping', 'సెల్ఫ్ షాపింగ్'),
};

String askodoxShopToolRoute(String tool, String businessId, [String query = '']) =>
    (askodoxShopTools[tool]?.$1 ?? '/pos/<id>').replaceFirst('<id>', businessId) + (query.isEmpty ? '' : '?$query');

/// `/my-shop/<tool>`: one shop -> straight to the tool; several -> choose the shop; none -> add a shop first.
class AskodoxShopToolScreen extends ConsumerStatefulWidget {
  const AskodoxShopToolScreen({super.key, required this.tool, this.query = ''});
  final String tool;

  /// Passed on to the tool's page (e.g. `say=` spoken items for a new bill).
  final String query;

  @override
  ConsumerState<AskodoxShopToolScreen> createState() => _AskodoxShopToolScreenState();
}

class _AskodoxShopToolScreenState extends ConsumerState<AskodoxShopToolScreen> {
  late final Future<List<AskodoxJson>> _shops = ref.read(askodoxPosRepositoryProvider).businesses();
  bool _jumped = false;

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final names = askodoxShopTools[widget.tool];
    return Scaffold(
      appBar: AppBar(title: Text(names == null ? (te ? 'నా షాప్' : 'My shop') : (te ? names.$3 : names.$2))),
      body: FutureBuilder<List<AskodoxJson>>(
        future: _shops,
        builder: (context, snap) {
          if (snap.hasError) return AskodoxPosError(error: snap.error!);
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final shops = snap.data!;
          if (shops.length == 1 && !_jumped) {
            _jumped = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) context.replace(askodoxShopToolRoute(widget.tool, '${shops.first['id']}', widget.query));
            });
            return const Center(child: CircularProgressIndicator());
          }
          if (shops.isEmpty) {
            return ListView(padding: const EdgeInsets.all(16), children: [
              Text(te
                  ? 'ఇది షాప్ ఉన్నవారి టూల్. ముందు మీ షాప్‌ని చేర్చండి.'
                  : 'This is a shop tool. Add your shop first.'),
              const SizedBox(height: 12),
              FilledButton(
                  key: const Key('askodoxShopToolCreate'),
                  onPressed: () => context.replace('/pos'),
                  child: Text(te ? 'షాప్ చేర్చండి' : 'Add my shop')),
            ]);
          }
          return ListView(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(te ? 'ఏ షాప్?' : 'Which shop?', style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
            for (final s in shops)
              ListTile(
                key: ValueKey('askodoxShopToolShop-${s['id']}'),
                leading: const Icon(Icons.storefront_outlined),
                title: Text('${s['name']}'),
                subtitle: Text('${s['my_role'] ?? ''}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.replace(askodoxShopToolRoute(widget.tool, '${s['id']}', widget.query)),
              ),
          ]);
        },
      ),
    );
  }
}
