import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'command_center_api.dart';

/// ASKODOX Admin Command Center (Phases 18-23). Real backend data only;
/// every action is authorised server-side. Kept out of the customer chat.
class CommandCenterScreen extends ConsumerStatefulWidget {
  const CommandCenterScreen({super.key});

  @override
  ConsumerState<CommandCenterScreen> createState() => _CommandCenterScreenState();
}

class _CommandCenterScreenState extends ConsumerState<CommandCenterScreen> {
  Map<String, dynamic>? _me;

  @override
  Widget build(BuildContext context) {
    final api = ref.watch(commandCenterApiProvider);
    final me = _me;
    if (me == null || !api.signedIn) {
      return _SignIn(api: api, onSignedIn: (value) => setState(() => _me = value));
    }
    final permissions = {for (final p in me['permissions'] as List) '$p'};
    final sections = [
      for (final section in _sections)
        if (permissions.contains(section.permission)) section,
    ];
    return DefaultTabController(
      length: sections.isEmpty ? 1 : sections.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Command Center • ${me['name']} (${me['role']})', overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(
              tooltip: 'Sign out',
              icon: const Icon(Icons.logout),
              onPressed: () {
                api.signOut();
                setState(() => _me = null);
              },
            ),
          ],
          bottom: sections.isEmpty
              ? null
              : TabBar(isScrollable: true, tabs: [for (final s in sections) Tab(text: s.label)]),
        ),
        body: sections.isEmpty
            ? const Center(child: Text('No Command Center permissions have been granted to this account.'))
            : TabBarView(children: [
                for (final s in sections) s.builder(api, permissions),
              ]),
      ),
    );
  }
}

typedef _SectionBuilder = Widget Function(CommandCenterApi api, Set<String> permissions);

class _Section {
  const _Section(this.label, this.permission, this.builder);
  final String label;
  final String permission;
  final _SectionBuilder builder;
}

final _sections = <_Section>[
  _Section('Overview', 'overview:view', (api, p) => _Overview(api: api)),
  _Section('Support', 'support:view', (api, p) => _Escalations(api: api, canManage: p.contains('support:manage'))),
  _Section('No-match', 'nomatch:view', (api, p) => _NoMatch(api: api, canManage: p.contains('nomatch:manage'))),
  _Section('Listings', 'catalog:view', (api, p) => _Listings(api: api, canManage: p.contains('catalog:manage'))),
  _Section('Requests', 'requests:view', (api, p) => _Requests(api: api, canManage: p.contains('requests:manage'))),
  _Section('Users', 'users:view', (api, p) => _Users(api: api, canManage: p.contains('users:manage'))),
  _Section('Notifications', 'notifications:view', (api, p) => _Notifications(api: api)),
  _Section('Config', 'config:view', (api, p) => _Config(api: api, canManage: p.contains('config:manage'))),
  _Section('Integrations', 'integrations:view',
      (api, p) => _Integrations(api: api, canCheck: p.contains('integrations:manage'))),
  _Section('Analytics', 'analytics:view', (api, p) => _Analytics(api: api, canExport: p.contains('analytics:export'))),
  _Section('Health', 'health:view', (api, p) => _Health(api: api)),
  _Section('Staff', 'staff:manage', (api, p) => _Staff(api: api, own: p)),
  _Section('Audit', 'audit:view', (api, p) => _Audit(api: api)),
];

// --------------------------------------------------------------- sign-in --

class _SignIn extends StatefulWidget {
  const _SignIn({required this.api, required this.onSignedIn});
  final CommandCenterApi api;
  final ValueChanged<Map<String, dynamic>> onSignedIn;

  @override
  State<_SignIn> createState() => _SignInState();
}

class _SignInState extends State<_SignIn> {
  final _secret = TextEditingController();
  var _kind = CommandCenterCredentialKind.staffToken;
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _secret.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final secret = _secret.text.trim();
    if (secret.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final me = await widget.api.signIn(CommandCenterCredential(_kind, secret));
      _secret.clear();
      widget.onSignedIn(me);
    } on CommandCenterException catch (error) {
      setState(() => _error = error.signedOut ? 'That key or token was not accepted.' : error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('ASKODOX Command Center')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: ListView(padding: const EdgeInsets.all(24), shrinkWrap: true, children: [
              const Icon(Icons.admin_panel_settings, size: 48),
              const SizedBox(height: 12),
              const Text('Sign in with the owner key or a staff token. Access is checked by the server.',
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              SegmentedButton<CommandCenterCredentialKind>(
                segments: const [
                  ButtonSegment(value: CommandCenterCredentialKind.staffToken, label: Text('Staff token')),
                  ButtonSegment(value: CommandCenterCredentialKind.ownerKey, label: Text('Owner key')),
                ],
                selected: {_kind},
                onSelectionChanged: (value) => setState(() => _kind = value.first),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('cc-secret'),
                controller: _secret,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'Key / token', border: OutlineInputBorder()),
                onSubmitted: (_) => _submit(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const Key('cc-sign-in'),
                onPressed: _busy ? null : _submit,
                icon: const Icon(Icons.login),
                label: Text(_busy ? 'Checking…' : 'Sign in'),
              ),
            ]),
          ),
        ),
      );
}

// --------------------------------------------------------------- helpers --

/// Loads [load] and rebuilds with the data; errors are shown, never hidden.
class _Loader extends StatefulWidget {
  const _Loader({required this.load, required this.builder, super.key});
  final Future<Map<String, dynamic>> Function() load;
  final Widget Function(BuildContext context, Map<String, dynamic> data, VoidCallback reload) builder;

  @override
  State<_Loader> createState() => _LoaderState();
}

class _LoaderState extends State<_Loader> {
  late Future<Map<String, dynamic>> _future = widget.load();

  void _reload() {
    final next = widget.load();
    setState(() {
      _future = next;
    });
  }

  @override
  void didUpdateWidget(covariant _Loader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.key != widget.key) _future = widget.load();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('Could not load: ${snapshot.error}', textAlign: TextAlign.center),
                  TextButton(onPressed: _reload, child: const Text('Retry')),
                ]),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: widget.builder(context, snapshot.data ?? const {}, _reload),
          );
        },
      );
}

/// Runs a mutation and reports the outcome; returns true on success.
Future<bool> _run(BuildContext context, Future<Object?> Function() action, String done) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action();
    messenger.showSnackBar(SnackBar(content: Text(done)));
    return true;
  } on CommandCenterException catch (error) {
    messenger.showSnackBar(SnackBar(content: Text(error.message)));
    return false;
  }
}

/// Confirmation for destructive changes. Returns null when cancelled, else
/// the note typed (required when [noteLabel] is set).
Future<String?> _confirm(BuildContext context, String title, String message, {String? noteLabel}) {
  final note = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(title),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(message),
          if (noteLabel != null)
            TextField(
              key: const Key('cc-confirm-note'),
              controller: note,
              decoration: InputDecoration(labelText: noteLabel),
              onChanged: (_) => setState(() {}),
            ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            key: const Key('cc-confirm'),
            onPressed: noteLabel != null && note.text.trim().isEmpty
                ? null
                : () => Navigator.pop(context, note.text.trim()),
            child: const Text('Confirm'),
          ),
        ],
      ),
    ),
  );
}

Future<String?> _ask(BuildContext context, String title, String label, {String initial = ''}) {
  final text = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(key: const Key('cc-ask'), controller: text, decoration: InputDecoration(labelText: label)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, text.text.trim()), child: const Text('Save')),
      ],
    ),
  );
}

Color _statusColor(BuildContext context, String status) => switch (status) {
      'ok' => Colors.green.shade700,
      'error' => Theme.of(context).colorScheme.error,
      'unknown' || 'configured' => Colors.orange.shade800,
      _ => Theme.of(context).colorScheme.outline,
    };

String _statusLabel(String status) => switch (status) {
      'ok' => 'Healthy (checked)',
      'error' => 'Error',
      'unknown' => 'Unknown (not checked)',
      'configured' => 'Configured (not checked)',
      'not_configured' => 'Not configured',
      'disabled' => 'Disabled',
      _ => status,
    };

class _StatusChip extends StatelessWidget {
  const _StatusChip(this.status);
  final String status;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(context, status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(border: Border.all(color: color), borderRadius: BorderRadius.circular(12)),
      child: Text(_statusLabel(status), style: TextStyle(color: color, fontSize: 12)),
    );
  }
}

Widget _empty(String text) => ListView(children: [Padding(padding: const EdgeInsets.all(32), child: Text(text, textAlign: TextAlign.center))]);

Widget _metric(String label, Object? value) => Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${value ?? 0}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
          Text(label, textAlign: TextAlign.center),
        ]),
      ),
    );

// -------------------------------------------------------------- sections --

class _Overview extends StatelessWidget {
  const _Overview({required this.api});
  final CommandCenterApi api;

  @override
  Widget build(BuildContext context) => _Loader(
        load: () => api.get('/admin/cc/overview'),
        builder: (context, data, _) {
          final participants = Map<String, dynamic>.from(data['participants'] as Map? ?? {});
          final requests = Map<String, dynamic>.from(data['requests'] as Map? ?? {});
          final listings = Map<String, dynamic>.from(data['listings'] as Map? ?? {});
          final orders = Map<String, dynamic>.from(data['orders'] as Map? ?? {});
          return GridView.extent(maxCrossAxisExtent: 180, padding: const EdgeInsets.all(12), children: [
            _metric('Buyers', participants['buyers']),
            _metric('Sellers', participants['sellers']),
            _metric('Service providers', participants['service_providers']),
            _metric('Job seekers', participants['job_seekers']),
            _metric('Delivery / ride', participants['delivery_ride']),
            _metric('Active requests', requests['active']),
            _metric('All requests', requests['total']),
            _metric('Orders', orders.values.fold<num>(0, (a, b) => a + (b as num? ?? 0))),
            _metric('Active listings', listings['active']),
            _metric('Disabled listings', listings['disabled']),
            _metric('Open support cases', data['support_open']),
            _metric('Open no-match', data['no_match_open']),
            _metric('Unread notifications', data['unread_notifications']),
          ]);
        },
      );
}

const _escalationStatuses = ['OPEN', 'IN_PROGRESS', 'WAITING_FOR_USER', 'RESOLVED', 'CLOSED'];

class _Escalations extends StatefulWidget {
  const _Escalations({required this.api, required this.canManage});
  final CommandCenterApi api;
  final bool canManage;

  @override
  State<_Escalations> createState() => _EscalationsState();
}

class _EscalationsState extends State<_Escalations> {
  String _status = '';

  @override
  Widget build(BuildContext context) => Column(children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(children: [
            for (final s in ['', ..._escalationStatuses])
              Padding(
                padding: const EdgeInsets.all(4),
                child: ChoiceChip(
                  label: Text(s.isEmpty ? 'All' : s),
                  selected: _status == s,
                  onSelected: (_) => setState(() => _status = s),
                ),
              ),
          ]),
        ),
        Expanded(
          child: _Loader(
            key: ValueKey('esc-$_status'),
            load: () => widget.api.get('/admin/cc/escalations', query: {if (_status.isNotEmpty) 'status': _status}),
            builder: (context, data, reload) {
              final items = ccItems(data);
              if (items.isEmpty) return _empty('No support escalations.');
              return ListView(children: [
                for (final e in items)
                  ListTile(
                    leading: Icon(e['critical'] == true ? Icons.priority_high : Icons.support_agent,
                        color: e['critical'] == true ? Theme.of(context).colorScheme.error : null),
                    title: Text('#${e['id']} ${e['category']} — ${e['issue']}', maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${e['status']} • ${e['assigned_to'] ?? 'unassigned'} • ${e['created_at']}'),
                    onTap: () async {
                      await showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) => _EscalationDetail(api: widget.api, id: e['id'], canManage: widget.canManage),
                      );
                      reload();
                    },
                  ),
              ]);
            },
          ),
        ),
      ]);
}

class _EscalationDetail extends StatelessWidget {
  const _EscalationDetail({required this.api, required this.id, required this.canManage});
  final CommandCenterApi api;
  final Object? id;
  final bool canManage;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.85,
        child: _Loader(
          load: () => api.get('/admin/cc/escalations/$id'),
          builder: (context, e, reload) {
            final ctx = Map<String, dynamic>.from(e['context'] as Map? ?? {});
            final conversation = [for (final t in (ctx['conversation'] as List? ?? const [])) if (t is Map) t];
            final tried = [for (final a in (ctx['actions_tried'] as List? ?? const [])) '$a'];
            Future<void> update(Map<String, Object?> body, String done) async {
              if (await _run(context, () => api.patch('/admin/cc/escalations/$id', body), done)) reload();
            }

            return ListView(padding: const EdgeInsets.all(16), children: [
              Text('Case #${e['id']} • ${e['category']}${e['critical'] == true ? ' • CRITICAL' : ''}',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(e['issue']?.toString() ?? ''),
              const Divider(),
              Text('Status: ${e['status']}'),
              Text('Assigned: ${e['assigned_to'] ?? 'unassigned'}'),
              Text('Requester: ${e['requester'] ?? '—'}'),
              if (ctx['deal_id'] != null) Text('Deal / request id: ${ctx['deal_id']}'),
              if (ctx['counterpart'] != null) Text('Counterpart: ${ctx['counterpart']}'),
              if ((ctx['active_role'] ?? '').toString().isNotEmpty) Text('Active role: ${ctx['active_role']}'),
              if ((ctx['status'] ?? '').toString().isNotEmpty) Text('Deal status: ${ctx['status']}'),
              if (e['resolution_note'] != null) Text('Resolution: ${e['resolution_note']}'),
              const Divider(),
              Text('What ASKODOX AI already tried', style: Theme.of(context).textTheme.titleSmall),
              if (tried.isEmpty) const Text('—') else for (final a in tried) Text('• $a'),
              const Divider(),
              Text('Conversation', style: Theme.of(context).textTheme.titleSmall),
              for (final t in conversation) Text('${t['role']}: ${t['text']}'),
              if (canManage) ...[
                const Divider(),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  OutlinedButton(
                    onPressed: () async {
                      final who = await _ask(context, 'Assign case', 'Staff name', initial: '${e['assigned_to'] ?? ''}');
                      if (who != null && who.isNotEmpty && context.mounted) {
                        await update({'assigned_to': who, 'status': 'IN_PROGRESS'}, 'Assigned to $who');
                      }
                    },
                    child: const Text('Assign'),
                  ),
                  OutlinedButton(
                    onPressed: () => update({'status': 'WAITING_FOR_USER'}, 'Waiting for user'),
                    child: const Text('Waiting for user'),
                  ),
                  for (final done in ['RESOLVED', 'CLOSED'])
                    FilledButton.tonal(
                      key: Key('cc-esc-$done'),
                      onPressed: () async {
                        final note = await _confirm(context, 'Mark $done?', 'The user-facing case will be $done.',
                            noteLabel: 'Resolution note');
                        if (note != null && context.mounted) {
                          await update({'status': done, 'resolution_note': note, 'confirm': true}, 'Case $done');
                        }
                      },
                      child: Text(done == 'RESOLVED' ? 'Resolve' : 'Close'),
                    ),
                ]),
              ],
            ]);
          },
        ),
      );
}

const _noMatchStatuses = ['OPEN', 'INVESTIGATING', 'SOURCE_ADDED', 'CATEGORY_ADDED', 'RESOLVED', 'DISMISSED'];

class _NoMatch extends StatelessWidget {
  const _NoMatch({required this.api, required this.canManage});
  final CommandCenterApi api;
  final bool canManage;

  @override
  Widget build(BuildContext context) => _Loader(
        load: () => api.get('/admin/cc/no-match'),
        builder: (context, data, reload) {
          final items = ccItems(data);
          if (items.isEmpty) return _empty('No unmatched searches. Every recent request found a local option.');
          return ListView(children: [
            for (final e in items)
              ListTile(
                title: Text('${e['subject'] ?? '—'} (${e['domain'] ?? '?'})'),
                subtitle: Text([
                  'Request #${e['demand_id']} • ${e['status']}',
                  if ((e['location_text'] ?? '').toString().isNotEmpty) 'Location: ${e['location_text']}',
                  if (e['source_status'] is Map)
                    'Sources: ${(e['source_status'] as Map).entries.map((s) => '${s.key}=${s.value}').join(', ')}',
                  if ((e['note'] ?? '').toString().isNotEmpty) 'Note: ${e['note']}',
                ].join('\n')),
                isThreeLine: true,
                trailing: canManage
                    ? PopupMenuButton<String>(
                        tooltip: 'Update',
                        onSelected: (status) async {
                          final note = await _ask(context, 'Mark $status', 'What was done (category / provider / source added)');
                          if (note == null || !context.mounted) return;
                          if (await _run(context, () => api.patch('/admin/cc/no-match/${e['id']}', {'status': status, 'note': note}),
                              'Marked $status')) {
                            reload();
                          }
                        },
                        itemBuilder: (_) => [for (final s in _noMatchStatuses) PopupMenuItem(value: s, child: Text(s))],
                      )
                    : null,
              ),
          ]);
        },
      );
}

class _Listings extends StatefulWidget {
  const _Listings({required this.api, required this.canManage});
  final CommandCenterApi api;
  final bool canManage;

  @override
  State<_Listings> createState() => _ListingsState();
}

class _ListingsState extends State<_Listings> {
  String _query = '';

  @override
  Widget build(BuildContext context) => Column(children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Search listings'),
            onSubmitted: (value) => setState(() => _query = value.trim()),
          ),
        ),
        Expanded(
          child: _Loader(
            key: ValueKey('listings-$_query'),
            load: () => widget.api.get('/admin/cc/listings', query: {if (_query.isNotEmpty) 'q': _query}),
            builder: (context, data, reload) {
              final items = ccItems(data);
              if (items.isEmpty) return _empty('No listings found.');
              return ListView(children: [
                for (final l in items)
                  SwitchListTile(
                    key: Key('cc-listing-${l['id']}'),
                    title: Text('${l['subject']}${l['brand'] != null ? ' • ${l['brand']}' : ''}'),
                    subtitle: Text('${l['seller']} • ₹${l['price'] ?? '—'} • ${l['category_tag'] ?? 'uncategorised'}'),
                    value: l['active'] == true,
                    onChanged: !widget.canManage
                        ? null
                        : (active) async {
                            final body = <String, Object?>{'active': active};
                            if (!active) {
                              final reason = await _confirm(context, 'Disable listing?',
                                  'Buyers will stop seeing "${l['subject']}".', noteLabel: 'Moderation reason');
                              if (reason == null) return;
                              body.addAll({'reason': reason, 'confirm': true});
                            }
                            if (!context.mounted) return;
                            if (await _run(context, () => widget.api.patch('/admin/cc/listings/${l['id']}', body),
                                active ? 'Listing enabled' : 'Listing disabled')) {
                              reload();
                            }
                          },
                  ),
              ]);
            },
          ),
        ),
      ]);
}

class _Requests extends StatelessWidget {
  const _Requests({required this.api, required this.canManage});
  final CommandCenterApi api;
  final bool canManage;

  @override
  Widget build(BuildContext context) => _Loader(
        load: () async => {
          'requests': ccItems(await api.get('/admin/cc/requests')),
          'orders': ccItems(await api.get('/admin/cc/orders')),
        },
        builder: (context, data, reload) {
          final requests = [for (final r in data['requests'] as List) r as Map<String, dynamic>];
          final orders = [for (final o in data['orders'] as List) o as Map<String, dynamic>];
          return ListView(children: [
            const ListTile(title: Text('Requests / deals', style: TextStyle(fontWeight: FontWeight.w600))),
            if (requests.isEmpty) const ListTile(title: Text('No requests yet.')),
            for (final r in requests)
              ListTile(
                title: Text('#${r['id']} ${r['side']} ${r['domain']} — ${r['subject'] ?? ''}'),
                subtitle: Text('${r['status']} • ${r['user']} • ${r['created_at']}'),
                trailing: canManage && r['status'] == 'ACTIVE'
                    ? PopupMenuButton<String>(
                        tooltip: 'Change status',
                        onSelected: (status) async {
                          final reason = await _confirm(context, 'Mark request #${r['id']} $status?',
                              'The requester will no longer receive matches.', noteLabel: 'Reason');
                          if (reason == null || !context.mounted) return;
                          if (await _run(context,
                              () => api.patch('/admin/cc/requests/${r['id']}', {'status': status, 'reason': reason, 'confirm': true}),
                              'Request $status')) {
                            reload();
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'CLOSED', child: Text('Close')),
                          PopupMenuItem(value: 'CANCELLED', child: Text('Cancel')),
                        ],
                      )
                    : null,
              ),
            const Divider(),
            const ListTile(title: Text('Orders', style: TextStyle(fontWeight: FontWeight.w600))),
            if (orders.isEmpty) const ListTile(title: Text('No orders yet.')),
            for (final o in orders)
              ListTile(
                title: Text('#${o['id']} ${o['product_title'] ?? ''}'),
                subtitle: Text('${o['status']} • buyer ${o['buyer']} • seller ${o['seller']}'),
              ),
          ]);
        },
      );
}

class _Users extends StatefulWidget {
  const _Users({required this.api, required this.canManage});
  final CommandCenterApi api;
  final bool canManage;

  @override
  State<_Users> createState() => _UsersState();
}

class _UsersState extends State<_Users> {
  String _role = 'all';
  static const _roles = {
    'all': 'All',
    'buyers': 'Buyers',
    'sellers': 'Sellers',
    'service_providers': 'Service providers',
    'job_seekers': 'Job seekers',
    'delivery_ride': 'Delivery / ride',
  };

  @override
  Widget build(BuildContext context) => Column(children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final entry in _roles.entries)
              Padding(
                padding: const EdgeInsets.all(4),
                child: ChoiceChip(
                  label: Text(entry.value),
                  selected: _role == entry.key,
                  onSelected: (_) => setState(() => _role = entry.key),
                ),
              ),
          ]),
        ),
        Expanded(
          child: _Loader(
            key: ValueKey('users-$_role'),
            load: () => widget.api.get('/admin/cc/users', query: {'role': _role}),
            builder: (context, data, reload) {
              final items = ccItems(data);
              if (items.isEmpty) return _empty('No participants in this group yet.');
              return ListView(children: [
                for (final u in items)
                  ListTile(
                    title: Text('${u['user']}'),
                    subtitle: Text('${u['role']} • ${u['active_listings']} active / ${u['disabled_listings']} disabled listings'),
                    trailing: widget.canManage && ((u['active_listings'] as num? ?? 0) + (u['disabled_listings'] as num? ?? 0)) > 0
                        ? TextButton(
                            onPressed: () async {
                              final disable = (u['active_listings'] as num? ?? 0) > 0;
                              final body = <String, Object?>{'active': !disable};
                              if (disable) {
                                final reason = await _confirm(context, 'Suspend seller?',
                                    'All listings of ${u['user']} will be hidden.', noteLabel: 'Reason');
                                if (reason == null) return;
                                body.addAll({'reason': reason, 'confirm': true});
                              }
                              if (!context.mounted) return;
                              if (await _run(context, () => widget.api.post('/admin/cc/users/${u['user_ref']}/listings', body),
                                  disable ? 'Seller suspended' : 'Seller restored')) {
                                reload();
                              }
                            },
                            child: Text((u['active_listings'] as num? ?? 0) > 0 ? 'Suspend' : 'Restore'),
                          )
                        : null,
                  ),
              ]);
            },
          ),
        ),
      ]);
}

class _Notifications extends StatelessWidget {
  const _Notifications({required this.api});
  final CommandCenterApi api;

  @override
  Widget build(BuildContext context) => _Loader(
        load: () => api.get('/admin/cc/notifications'),
        builder: (context, data, reload) {
          final items = ccItems(data);
          if (items.isEmpty) return _empty('No admin notifications.');
          return ListView(children: [
            for (final n in items)
              ListTile(
                leading: Icon(n['read'] == true ? Icons.notifications_none : Icons.notifications_active),
                title: Text('${n['title']}'),
                subtitle: Text('${n['kind']} • ${n['created_at']}'),
                trailing: n['read'] == true
                    ? null
                    : TextButton(
                        onPressed: () async {
                          if (await _run(context, () => api.post('/admin/cc/notifications/${n['id']}/read'), 'Marked read')) {
                            reload();
                          }
                        },
                        child: const Text('Mark read'),
                      ),
              ),
          ]);
        },
      );
}

class _Config extends StatelessWidget {
  const _Config({required this.api, required this.canManage});
  final CommandCenterApi api;
  final bool canManage;

  @override
  Widget build(BuildContext context) => _Loader(
        load: () => api.get('/admin/cc/config'),
        builder: (context, data, reload) => ListView(children: [
          for (final f in ccItems(data, 'flags'))
            SwitchListTile(
              key: Key('cc-flag-${f['key']}'),
              title: Text('${f['description']}'),
              subtitle: Text([
                '${f['key']}',
                if (f['requires'] != null)
                  f['integration_configured'] == true
                      ? 'Needs ${f['requires']} (configured)'
                      : 'Needs ${f['requires']} — NOT configured, stays unavailable',
                if (f['updated_by'] != null) 'Changed by ${f['updated_by']}',
              ].join('\n')),
              value: f['enabled'] == true,
              onChanged: !canManage
                  ? null
                  : (enabled) async {
                      if (!enabled &&
                          await _confirm(context, 'Turn off?', '"${f['description']}" will stop for every user.') == null) {
                        return;
                      }
                      if (!context.mounted) return;
                      if (await _run(context, () => api.put('/admin/cc/config/${f['key']}', {'enabled': enabled, 'confirm': true}),
                          enabled ? 'Turned on' : 'Turned off')) {
                        reload();
                      }
                    },
            ),
        ]),
      );
}

class _Integrations extends StatelessWidget {
  const _Integrations({required this.api, required this.canCheck});
  final CommandCenterApi api;
  final bool canCheck;

  @override
  Widget build(BuildContext context) => _Loader(
        load: () => api.get('/admin/cc/integrations'),
        builder: (context, data, reload) => ListView(children: [
          for (final i in ccItems(data))
            ListTile(
              key: Key('cc-integration-${i['name']}'),
              title: Text('${i['label']}'),
              subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const SizedBox(height: 4),
                _StatusChip('${i['status']}'),
                if ((i['detail'] ?? '').toString().isNotEmpty) Text('${i['detail']}'),
                if (i['last_check'] is Map)
                  Text('Last check: ${(i['last_check'] as Map)['detail']} (${(i['last_check'] as Map)['checked_at']})'),
              ]),
              trailing: canCheck && i['configured'] == true && i['enabled'] == true
                  ? TextButton(
                      onPressed: () async {
                        if (await _run(context, () => api.post('/admin/cc/integrations/${i['name']}/check'), 'Check finished')) {
                          reload();
                        }
                      },
                      child: const Text('Check now'),
                    )
                  : null,
            ),
        ]),
      );
}

class _Analytics extends StatefulWidget {
  const _Analytics({required this.api, required this.canExport});
  final CommandCenterApi api;
  final bool canExport;

  @override
  State<_Analytics> createState() => _AnalyticsState();
}

class _AnalyticsState extends State<_Analytics> {
  int _days = 30;
  String _domain = '';

  @override
  Widget build(BuildContext context) => Column(children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(children: [
            DropdownButton<int>(
              value: _days,
              items: const [
                DropdownMenuItem(value: 1, child: Text('24 h')),
                DropdownMenuItem(value: 7, child: Text('7 days')),
                DropdownMenuItem(value: 30, child: Text('30 days')),
                DropdownMenuItem(value: 90, child: Text('90 days')),
              ],
              onChanged: (value) => setState(() => _days = value ?? 30),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                decoration: const InputDecoration(labelText: 'Domain filter (e.g. PRODUCT)'),
                onSubmitted: (value) => setState(() => _domain = value.trim()),
              ),
            ),
          ]),
        ),
        Expanded(
          child: _Loader(
            key: ValueKey('analytics-$_days-$_domain'),
            load: () => widget.api.get('/admin/cc/analytics', query: {'days': _days, if (_domain.isNotEmpty) 'domain': _domain}),
            builder: (context, data, _) {
              final totals = Map<String, dynamic>.from(data['totals'] as Map? ?? {});
              final daily = ccItems(data, 'daily');
              final usage = ccItems(data, 'source_usage');
              return ListView(padding: const EdgeInsets.all(8), children: [
                Wrap(children: [
                  for (final entry in totals.entries)
                    SizedBox(width: 160, child: _metric(entry.key.replaceAll('_', ' '), entry.value)),
                ]),
                if (widget.canExport)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const Key('cc-export'),
                      icon: const Icon(Icons.download),
                      label: const Text('Copy CSV export'),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: commandCenterAnalyticsCsv(data)));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context)
                              .showSnackBar(const SnackBar(content: Text('CSV copied to clipboard')));
                        }
                      },
                    ),
                  ),
                const ListTile(title: Text('Daily trend')),
                if (daily.isEmpty) const ListTile(title: Text('No activity in this period.')),
                for (final d in daily)
                  ListTile(
                    dense: true,
                    title: Text('${d['date']}'),
                    subtitle: Text('requests ${d['requests']} • matches ${d['matches']} • no-match ${d['no_match']} • '
                        'orders ${d['orders']} • escalations ${d['escalations']} • joins ${d['seller_joins']}'),
                  ),
                const ListTile(title: Text('Source usage')),
                if (usage.isEmpty) const ListTile(title: Text('No discovery recorded yet.')),
                for (final u in usage) ListTile(dense: true, title: Text('${u['source']} → ${u['status']}: ${u['n']}')),
              ]);
            },
          ),
        ),
      ]);
}

class _Health extends StatelessWidget {
  const _Health({required this.api});
  final CommandCenterApi api;

  @override
  Widget build(BuildContext context) => _Loader(
        load: () => api.get('/admin/cc/health'),
        builder: (context, data, _) {
          final failures = Map<String, dynamic>.from(data['recent_failures'] as Map? ?? {});
          return ListView(children: [
            for (final c in ccItems(data, 'components'))
              ListTile(
                key: Key('cc-health-${c['name']}'),
                title: Text('${c['name']}'),
                subtitle: Text('${c['detail'] ?? ''}'),
                trailing: _StatusChip('${c['status']}'),
              ),
            const Divider(),
            ListTile(
              title: const Text('Recent failures'),
              subtitle: Text('Integration check failures: ${(failures['integration_checks'] as List? ?? const []).length}\n'
                  'Failed message deliveries: ${(failures['failed_deliveries'] as List? ?? const []).length}\n'
                  'No-match searches (24 h): ${failures['no_match_last_24h'] ?? 0}'),
            ),
            ListTile(dense: true, title: Text('Checked at ${data['checked_at'] ?? '—'}')),
          ]);
        },
      );
}

class _Staff extends StatelessWidget {
  const _Staff({required this.api, required this.own});
  final CommandCenterApi api;
  final Set<String> own;

  Future<void> _create(BuildContext context, List<String> roles, VoidCallback reload) async {
    final name = TextEditingController();
    var role = roles.first;
    final created = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Add staff'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(key: const Key('cc-staff-name'), controller: name, decoration: const InputDecoration(labelText: 'Name')),
            DropdownButton<String>(
              value: role,
              isExpanded: true,
              items: [for (final r in roles) DropdownMenuItem(value: r, child: Text(r))],
              onChanged: (value) => setState(() => role = value ?? role),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(
              key: const Key('cc-staff-create'),
              onPressed: () => Navigator.pop(context, {'name': name.text.trim(), 'role': role}),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    if (created == null || created['name']!.isEmpty || !context.mounted) return;
    try {
      final staff = await api.post('/admin/cc/staff', created);
      if (!context.mounted) return;
      // The token exists only in this response; the server keeps a hash.
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Staff token (shown once)'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Share it privately with this staff member. It cannot be shown again.'),
            const SizedBox(height: 8),
            SelectableText('${staff['token']}', key: const Key('cc-staff-token')),
          ]),
          actions: [
            TextButton(
              onPressed: () => Clipboard.setData(ClipboardData(text: '${staff['token']}')),
              child: const Text('Copy'),
            ),
            FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
          ],
        ),
      );
      reload();
    } on CommandCenterException catch (error) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _edit(BuildContext context, Map<String, dynamic> staff, List<String> all, VoidCallback reload) async {
    final current = {for (final p in staff['permissions'] as List? ?? const []) '$p'};
    final selected = {...current};
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Access for ${staff['name']}'),
          content: SizedBox(
            width: 360,
            child: ListView(shrinkWrap: true, children: [
              for (final p in all)
                CheckboxListTile(
                  dense: true,
                  title: Text(p),
                  value: selected.contains(p),
                  // Only permissions you hold can be granted (server enforces too).
                  onChanged: own.contains(p) || selected.contains(p)
                      ? (value) => setState(() => value == true ? selected.add(p) : selected.remove(p))
                      : null,
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (save != true || !context.mounted) return;
    final body = {
      'grant': [for (final p in selected) if (!current.contains(p)) p],
      'revoke': [for (final p in current) if (!selected.contains(p)) p],
    };
    if (await _run(context, () => api.patch('/admin/cc/staff/${staff['id']}', body), 'Access updated')) reload();
  }

  @override
  Widget build(BuildContext context) => _Loader(
        load: () => api.get('/admin/cc/staff'),
        builder: (context, data, reload) {
          final roles = [for (final r in (data['roles'] as Map? ?? const {}).keys) '$r'];
          final all = [for (final p in data['permissions'] as List? ?? const []) '$p'];
          return ListView(children: [
            ListTile(
              leading: const Icon(Icons.person_add),
              title: const Text('Add staff member'),
              onTap: roles.isEmpty ? null : () => _create(context, roles, reload),
            ),
            for (final s in ccItems(data))
              ListTile(
                title: Text('${s['name']} • ${s['role']}${s['active'] == true ? '' : ' (deactivated)'}'),
                subtitle: Text('${(s['permissions'] as List? ?? const []).length} permissions'),
                onTap: () => _edit(context, s, all, reload),
                trailing: s['active'] == true
                    ? TextButton(
                        onPressed: () async {
                          if (await _confirm(context, 'Deactivate ${s['name']}?', 'Their token stops working immediately.') ==
                                  null ||
                              !context.mounted) {
                            return;
                          }
                          if (await _run(context, () => api.patch('/admin/cc/staff/${s['id']}', {'active': false, 'confirm': true}),
                              'Staff deactivated')) {
                            reload();
                          }
                        },
                        child: const Text('Deactivate'),
                      )
                    : TextButton(
                        onPressed: () async {
                          if (await _run(context, () => api.patch('/admin/cc/staff/${s['id']}', {'active': true}), 'Staff reactivated')) {
                            reload();
                          }
                        },
                        child: const Text('Reactivate'),
                      ),
              ),
          ]);
        },
      );
}

class _Audit extends StatelessWidget {
  const _Audit({required this.api});
  final CommandCenterApi api;

  @override
  Widget build(BuildContext context) => _Loader(
        load: () => api.get('/admin/cc/audit'),
        builder: (context, data, _) {
          final items = ccItems(data);
          if (items.isEmpty) return _empty('No admin actions recorded yet.');
          return ListView(children: [
            for (final a in items)
              ListTile(
                dense: true,
                title: Text('${a['action']} • ${a['entity_type']} ${a['entity_id']}'),
                subtitle: Text('${a['actor']} • ${a['created_at']}${(a['reason'] ?? '').toString().isNotEmpty ? ' • ${a['reason']}' : ''}'),
              ),
          ]);
        },
      );
}
