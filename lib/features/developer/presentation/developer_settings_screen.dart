import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_models.dart';
import '../../../core/providers/backend_providers.dart';
import '../../conversation/data/conversation_server_settings.dart';

class DeveloperSettingsScreen extends ConsumerStatefulWidget {
  const DeveloperSettingsScreen({super.key});

  @override
  ConsumerState<DeveloperSettingsScreen> createState() =>
      _DeveloperSettingsScreenState();
}

class _DeveloperSettingsScreenState
    extends ConsumerState<DeveloperSettingsScreen> {
  final TextEditingController _serverController = TextEditingController();
  final ConversationServerSettings _serverSettings =
      const ConversationServerSettings();
  String? _serverError;
  bool _savingServer = false;

  @override
  void initState() {
    super.initState();
    _loadServerUrl();
  }

  Future<void> _loadServerUrl() async {
    try {
      final value = await _serverSettings.loadBaseUrl();
      if (mounted) {
        _serverController.text = value;
      }
    } catch (_) {
      // Keep the field empty if local persistence is unavailable.
    }
  }

  @override
  void dispose() {
    _serverController.dispose();
    super.dispose();
  }

  Future<void> _saveServerUrl() async {
    setState(() {
      _savingServer = true;
      _serverError = null;
    });

    try {
      await _serverSettings.saveBaseUrl(_serverController.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ASKODOX server URL saved.')),
      );
    } on FormatException catch (error) {
      if (mounted) setState(() => _serverError = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _serverError = 'Could not save the server URL.');
      }
    } finally {
      if (mounted) setState(() => _savingServer = false);
    }
  }

  Future<void> _setRole(UserRole role) async {
    await ref.read(authSessionProvider.notifier).setDemoRole(role);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Demo role set to ${role.name}.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) {
      return const Scaffold(
        body: Center(child: Text('Developer settings are unavailable.')),
      );
    }

    final session = ref.watch(authSessionProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Developer settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Card(
            child: ListTile(
              leading: Icon(Icons.science_outlined),
              title: Text('ASKODOX debug tools'),
              subtitle: Text('Debug-only diagnostics and test utilities.'),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Demo role',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final role in const [
                UserRole.buyer,
                UserRole.seller,
                UserRole.admin,
              ])
                ChoiceChip(
                  key: Key('demoRole-${role.name}'),
                  label: Text(role.name),
                  selected: session.status == AuthStatus.loggedIn &&
                      session.role == role,
                  onSelected: (_) => _setRole(role),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'Conversation server',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('developerServerUrlField'),
            controller: _serverController,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: 'Live backend URL',
              hintText: 'https://…',
              errorText: _serverError,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            key: const Key('developerServerSave'),
            onPressed: _savingServer ? null : _saveServerUrl,
            icon: const Icon(Icons.save_outlined),
            label: Text(_savingServer ? 'Saving…' : 'Save server URL'),
          ),
          const SizedBox(height: 20),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.sync),
            title: const Text('Sync status'),
            onTap: () => context.push('/sync-status'),
          ),
          ListTile(
            leading: const Icon(Icons.storage_outlined),
            title: const Text('Storage usage'),
            onTap: () => context.push('/storage-usage'),
          ),
          ListTile(
            leading: const Icon(Icons.speed),
            title: const Text('Performance monitor'),
            onTap: () => context.push('/performance-monitor'),
          ),
        ],
      ),
    );
  }
}
