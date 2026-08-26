import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../buyer/application/buyer_providers.dart';
import '../../../buyer/domain/entities/buyer_models.dart';

class ProductRequestActions extends ConsumerWidget {
  const ProductRequestActions({this.compact = false, super.key});
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final te = Localizations.localeOf(context).languageCode == 'te';
    String t(String en, String telugu) => te ? telugu : en;
    void show(String message) => ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));

    final request = FilledButton.icon(
      onPressed: () {
        ref.read(buyerRepositoryProvider).saveRequest(
              BuyerProductRequest(
                id: DateTime.now().microsecondsSinceEpoch.toString(),
                productName: t('Requested product', 'అభ్యర్థించిన ఉత్పత్తి'),
                createdAt: DateTime.now(),
              ),
            );
        show(t('Product request saved locally.', 'ఉత్పత్తి అభ్యర్థన స్థానికంగా సేవ్ అయింది.'));
      },
      icon: const Icon(Icons.add_shopping_cart),
      label: Text(t('Request Product', 'ఉత్పత్తిని అభ్యర్థించండి')),
    );

    final upload = OutlinedButton.icon(
      onPressed: () => show(t(
        'Product image upload is a placeholder.',
        'ఉత్పత్తి చిత్రం అప్‌లోడ్ ప్రస్తుతం డెమో మాత్రమే.',
      )),
      icon: const Icon(Icons.add_a_photo_outlined),
      label: Text(t('Upload Product Image', 'ఉత్పత్తి చిత్రాన్ని అప్‌లోడ్ చేయండి')),
    );

    final watch = OutlinedButton.icon(
      onPressed: () => show(t('Added to watchlist', 'వాచ్‌లిస్ట్‌కు జోడించబడింది')),
      icon: const Icon(Icons.favorite_border),
      label: Text(t('Add to Watchlist', 'వాచ్‌లిస్ట్‌కు జోడించండి')),
    );

    final notify = OutlinedButton.icon(
      onPressed: () => show(t('Notifications enabled', 'నోటిఫికేషన్లు ప్రారంభించబడ్డాయి')),
      icon: const Icon(Icons.notifications_active_outlined),
      label: Text(t('Notify Me', 'నాకు తెలియజేయండి')),
    );

    final children = [request, upload, watch, notify];
    return compact
        ? Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: children,
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children
                .expand((element) => [element, const SizedBox(height: 10)])
                .toList(),
          );
  }
}
