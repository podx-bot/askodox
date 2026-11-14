import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../pos/data/pos_repository.dart';

bool _te(BuildContext context) => Localizations.localeOf(context).languageCode == 'te';

String _errorText(Object error, bool te) => te ? 'ఇప్పుడు సాధ్యం కాలేదు. మళ్ళీ ప్రయత్నించండి.' : 'Could not load right now. Try again.';

/// One shop: its name, what it does, how many people follow it, and Follow / Unfollow.
/// Shop owners see "your shop" and no follow button; everyone else sees the same follow control.
class AskodoxShopFollowScreen extends ConsumerStatefulWidget {
  const AskodoxShopFollowScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxShopFollowScreen> createState() => _AskodoxShopFollowScreenState();
}

class _AskodoxShopFollowScreenState extends ConsumerState<AskodoxShopFollowScreen> {
  AskodoxJson? _shop;
  Object? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final shop = await ref.read(askodoxPosRepositoryProvider).shopState(widget.businessId);
      if (mounted) setState(() => _shop = shop);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _toggle() async {
    final shop = _shop;
    if (shop == null || _busy) return;
    final repo = ref.read(askodoxPosRepositoryProvider);
    setState(() => _busy = true);
    try {
      final updated = shop['following'] == true
          ? await repo.unfollowShop(widget.businessId)
          : await repo.followShop(widget.businessId);
      if (mounted) setState(() => _shop = updated);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The shop's own details (the owner's words), shown before anything else.
  List<Widget> _details(AskodoxJson shop, bool te) {
    final profile = askodoxPosMap(shop['profile']);
    final fields = askodoxPosMap(profile['fields']);
    String v(String key) => '${fields[key] ?? ''}';
    Widget line(String label, String value) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('$label: $value'),
        );
    return [
      if (profile['status'] == 'verified')
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(te ? '✓ ASKODOX నిర్ధారించింది' : '✓ Verified by ASKODOX'),
        ),
      if (v('category').isNotEmpty) line(te ? 'ఏం దొరుకుతుంది' : 'What they offer', v('category')),
      if (v('description').isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(v('description'))),
      if (v('hours').isNotEmpty) line(te ? 'సమయం' : 'Hours', v('hours')),
      if (v('landmark').isNotEmpty) line(te ? 'గుర్తు' : 'Landmark', v('landmark')),
      if (v('offers').isNotEmpty) line(te ? 'ఆఫర్లు' : 'Offers', v('offers')),
      if (v('delivery').isNotEmpty) line(te ? 'డెలివరీ' : 'Delivery', v('delivery')),
      if (v('whatsapp').isNotEmpty) line('WhatsApp', v('whatsapp')),
      if (v('website').isNotEmpty) line(te ? 'వెబ్‌సైట్' : 'Website', v('website')),
      if (v('facebook').isNotEmpty) line('Facebook', v('facebook')),
      if (v('instagram').isNotEmpty) line('Instagram', v('instagram')),
      if (v('youtube').isNotEmpty) line('YouTube', v('youtube')),
      if (v('extra').isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(v('extra'))),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final te = _te(context);
    final shop = _shop;
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'షాప్' : 'Shop')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: shop == null
            ? (_error != null
                ? Text(_errorText(_error!, te))
                : const Center(child: CircularProgressIndicator()))
            : ListView(
                children: [
                  Text('${shop['name']}', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 6),
                  if ('${shop['address'] ?? ''}'.isNotEmpty) Text('${shop['address']}'),
                  ..._details(shop, te),
                  const SizedBox(height: 12),
                  Text(te
                      ? '${shop['followers']} మంది ఫాలో చేస్తున్నారు'
                      : '${shop['followers']} followers'),
                  const SizedBox(height: 16),
                  if (shop['is_owner'] == true) ...[
                    Text(te ? 'ఇది మీ షాప్.' : 'This is your shop.'),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: () => context.push('/shops/${widget.businessId}/post'),
                      icon: const Icon(Icons.edit_outlined),
                      label: Text(te ? 'ఈ రోజు పోస్ట్ చేయండి' : "Post today's picture"),
                    ),
                  ] else
                    FilledButton(
                      onPressed: _busy ? null : _toggle,
                      child: Text(shop['following'] == true
                          ? (te ? 'ఫాలో ఆపండి' : 'Unfollow')
                          : (te ? 'ఫాలో చేయండి' : 'Follow')),
                    ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_errorText(_error!, te)),
                  ],
                ],
              ),
      ),
    );
  }
}

/// The shops this person follows. Tap one to open it.
class AskodoxFollowingShopsScreen extends ConsumerStatefulWidget {
  const AskodoxFollowingShopsScreen({super.key});

  @override
  ConsumerState<AskodoxFollowingShopsScreen> createState() => _AskodoxFollowingShopsScreenState();
}

class _AskodoxFollowingShopsScreenState extends ConsumerState<AskodoxFollowingShopsScreen> {
  late final Future<List<AskodoxJson>> _follows = ref.read(askodoxPosRepositoryProvider).myFollows();

  @override
  Widget build(BuildContext context) {
    final te = _te(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(te ? 'నేను ఫాలో చేస్తున్న షాప్‌లు' : 'Shops I follow'),
        actions: [
          IconButton(
            tooltip: te ? 'షాప్ అప్‌డేట్స్' : 'Shop updates',
            icon: const Icon(Icons.dynamic_feed_outlined),
            onPressed: () => context.push('/me/shop-feed'),
          ),
        ],
      ),
      body: FutureBuilder<List<AskodoxJson>>(
        future: _follows,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) return Center(child: Text(_errorText(snapshot.error!, te)));
          final shops = snapshot.data ?? const <AskodoxJson>[];
          if (shops.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(te
                    ? 'ఇంకా ఏ షాప్‌ను ఫాలో చేయలేదు. షాప్ పేజీలో ఫాలో నొక్కండి.'
                    : 'You do not follow any shop yet. Open a shop and tap Follow.'),
              ),
            );
          }
          return ListView.separated(
            itemCount: shops.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final shop = shops[index];
              return ListTile(
                leading: const Icon(Icons.storefront_outlined),
                title: Text('${shop['name']}'),
                subtitle: Text('${shop['address'] ?? ''}'),
                onTap: () => context.push('/shops/${shop['business_id']}'),
              );
            },
          );
        },
      ),
    );
  }
}
