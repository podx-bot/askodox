import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_models.dart';
import '../../../core/providers/backend_providers.dart';

String _appUser(String raw) => raw.startsWith('app-') ? raw : 'app-$raw';

Future<Map<String, Object?>> _getMap(ApiClient client, String path) async {
  final result = await client.get<Map<String, Object?>>(path);
  if (result is ApiSuccess<Map<String, Object?>>) return result.data;
  final failure = (result as ApiError<Map<String, Object?>>).failure;
  throw StateError(failure.message ?? 'Unable to load deal data');
}

Future<Map<String, Object?>> _postMap(ApiClient client, String path, Map<String, Object?> body) async {
  final result = await client.post<Map<String, Object?>>(path, body: body);
  if (result is ApiSuccess<Map<String, Object?>>) return result.data;
  final failure = (result as ApiError<Map<String, Object?>>).failure;
  throw StateError(failure.message ?? 'Unable to update deal');
}

class DealInboxScreen extends ConsumerStatefulWidget {
  const DealInboxScreen({super.key});

  @override
  ConsumerState<DealInboxScreen> createState() => _DealInboxScreenState();
}

class _DealInboxScreenState extends ConsumerState<DealInboxScreen> {
  Future<Map<String, Object?>>? _future;

  String? get _userId {
    final user = ref.read(authSessionProvider).user;
    return user == null ? null : _appUser(user.id);
  }

  void _reload() {
    final id = _userId;
    if (id == null) return;
    setState(() {
      _future = _getMap(ref.read(apiClientProvider), '/debug/deal-inbox/$id');
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _userId == null
        ? Future<Map<String, Object?>>.error(StateError('Sign in to view deals'))
        : _getMap(ref.read(apiClientProvider), '/debug/deal-inbox/${_userId!}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Deals & conversations'),
        actions: [IconButton(onPressed: _reload, icon: const Icon(Icons.refresh), tooltip: 'Refresh')],
      ),
      body: FutureBuilder<Map<String, Object?>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorState(message: '${snapshot.error}', onRetry: _reload);
          }
          final data = snapshot.data ?? const <String, Object?>{};
          final rows = (data['threads'] as List? ?? const [])
              .whereType<Map>()
              .map((e) => Map<String, Object?>.from(e))
              .toList();
          final unread = (data['total_unread'] as num?)?.toInt() ?? 0;
          if (rows.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('No accepted deals yet. When a buyer accepts a seller response, the conversation will appear here.'),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                if (unread > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text('$unread unread deal update${unread == 1 ? '' : 's'}', style: Theme.of(context).textTheme.labelLarge),
                  ),
                for (final item in rows) _DealTile(item: item, userId: _userId!),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DealTile extends StatelessWidget {
  const _DealTile({required this.item, required this.userId});
  final Map<String, Object?> item;
  final String userId;

  @override
  Widget build(BuildContext context) {
    final requestId = (item['request_id'] as num?)?.toInt() ?? 0;
    final other = '${item['other_user_id'] ?? ''}';
    final unread = (item['unread_count'] as num?)?.toInt() ?? 0;
    final status = '${item['deal_status'] ?? 'NEGOTIATING'}'.replaceAll('_', ' ');
    final latest = '${item['latest_message'] ?? 'Deal accepted'}';
    return Card(
      child: ListTile(
        onTap: () => context.push('/deal/$requestId?user=${Uri.encodeComponent(userId)}&other=${Uri.encodeComponent(other)}'),
        leading: CircleAvatar(child: Text(unread > 0 ? '$unread' : '✓')),
        title: Text(other.isEmpty ? 'Deal #$requestId' : other),
        subtitle: Text('$status\n$latest', maxLines: 3, overflow: TextOverflow.ellipsis),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

class DealThreadScreen extends ConsumerStatefulWidget {
  const DealThreadScreen({required this.requestId, required this.userId, required this.otherUserId, super.key});
  final int requestId;
  final String userId;
  final String otherUserId;

  @override
  ConsumerState<DealThreadScreen> createState() => _DealThreadScreenState();
}

class _DealThreadScreenState extends ConsumerState<DealThreadScreen> {
  final _message = TextEditingController();
  Future<Map<String, Object?>>? _future;
  bool _sending = false;

  ApiClient get _client => ref.read(apiClientProvider);

  Future<Map<String, Object?>> _load() => _getMap(
        _client,
        '/debug/deal-thread/${widget.requestId}/${Uri.encodeComponent(widget.userId)}/${Uri.encodeComponent(widget.otherUserId)}',
      );

  void _refresh() => setState(() => _future = _load());

  @override
  void initState() {
    super.initState();
    _future = Future<Map<String, Object?>>.microtask(_load);
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _message.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await _postMap(_client, '/debug/deal-message', {
        'user_id': widget.userId,
        'request_id': widget.requestId,
        'other_user_id': widget.otherUserId,
        'message': text,
      });
      _message.clear();
      _refresh();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _setStatus(String status) async {
    try {
      await _postMap(_client, '/debug/deal-status', {
        'user_id': widget.userId,
        'request_id': widget.requestId,
        'other_user_id': widget.otherUserId,
        'status': status,
      });
      _refresh();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Deal #${widget.requestId}')),
      body: Column(
        children: [
          Expanded(
            child: FutureBuilder<Map<String, Object?>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) return _ErrorState(message: '${snapshot.error}', onRetry: _refresh);
                final data = snapshot.data ?? const <String, Object?>{};
                final deal = data['deal'] is Map ? Map<String, Object?>.from(data['deal'] as Map) : const <String, Object?>{};
                final messages = (data['messages'] as List? ?? const []).whereType<Map>().map((e) => Map<String, Object?>.from(e)).toList();
                final status = '${deal['deal_status'] ?? 'NEGOTIATING'}';
                return ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${deal['subject'] ?? 'Deal'}', style: Theme.of(context).textTheme.titleMedium),
                          Text('Status: ${status.replaceAll('_', ' ')}'),
                          if (deal['quantity'] != null) Text('Quantity: ${deal['quantity']} ${deal['unit'] ?? ''}'),
                          const SizedBox(height: 8),
                          Wrap(spacing: 8, runSpacing: 8, children: [
                            for (final next in const ['CONFIRMED', 'READY_FOR_PICKUP', 'OUT_FOR_DELIVERY', 'COMPLETED'])
                              ActionChip(label: Text(next.replaceAll('_', ' ')), onPressed: status == next ? null : () => _setStatus(next)),
                            ActionChip(label: const Text('CANCEL'), onPressed: status == 'CANCELLED' ? null : () => _setStatus('CANCELLED')),
                          ]),
                        ]),
                      ),
                    ),
                    for (final m in messages) _MessageBubble(message: m, mine: '${m['sender_user_id']}' == widget.userId),
                  ],
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(children: [
                Expanded(child: TextField(controller: _message, minLines: 1, maxLines: 4, decoration: const InputDecoration(hintText: 'Message buyer or seller', border: OutlineInputBorder()))),
                const SizedBox(width: 8),
                IconButton.filled(onPressed: _sending ? null : _send, icon: _sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send)),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.mine});
  final Map<String, Object?> message;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final type = '${message['message_type'] ?? 'USER'}';
    final text = '${message['message_text'] ?? ''}';
    if (type != 'USER') {
      return Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Center(child: Text(text, style: Theme.of(context).textTheme.bodySmall)));
    }
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 360),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: mine ? Theme.of(context).colorScheme.primaryContainer : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(text),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off, size: 42),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: onRetry, child: const Text('Retry')),
          ]),
        ),
      );
}
