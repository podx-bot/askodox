import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/update/askodox_update_service.dart';
import '../../features/location/application/location_controller.dart';

const _navInk = Color(0xFF10204A);
const _navMuted = Color(0xFF667085);
const _navAccent = Color(0xFF4F46FF);

class AppShell extends ConsumerWidget {
  const AppShell({required this.shell, super.key});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isTe = Localizations.localeOf(context).languageCode == 'te';
    final locationState = ref.watch(locationControllerProvider);
    final locationLabel = locationState.displayLocation ?? (isTe ? 'లొకేషన్ ఎంచుకోండి' : 'Choose location');
    return Scaffold(
      backgroundColor: const Color(0xFFF8FBFF),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _navInk,
        elevation: 0,
        centerTitle: false,
        titleSpacing: 4,
        title: Row(children: [
          const Expanded(child: Text('ASKODOX', style: TextStyle(color: _navInk, fontWeight: FontWeight.w900, letterSpacing: 1.1))),
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => context.push('/location'),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.location_on_rounded, size: 20, color: Color(0xFF1769FF)),
                const SizedBox(width: 3),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 120),
                  child: Text(
                    locationLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _navInk, fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                ),
                const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: _navInk),
              ]),
            ),
          ),
        ]),
        actions: [
          IconButton(tooltip: isTe ? 'నోటిఫికేషన్స్' : 'Notifications', onPressed: () => shell.goBranch(3), icon: const Badge(smallSize: 8, child: Icon(Icons.notifications_none_rounded))),
          const SizedBox(width: 4),
        ],
      ),
      drawer: _AskodoxDrawer(
        isTe: isTe,
        currentBranch: shell.currentIndex,
        onBranch: (index) { Navigator.of(context).pop(); shell.goBranch(index, initialLocation: index == shell.currentIndex); },
        onRoute: (route) { Navigator.of(context).pop(); context.go(route); },
      ),
      body: shell,
      bottomNavigationBar: _PrimaryBottomBar(
        currentBranch: shell.currentIndex,
        isTe: isTe,
        onSelected: (index) {
          switch (index) {
            case 0: shell.goBranch(0, initialLocation: true); break;
            case 1: shell.goBranch(2, initialLocation: true); break;
            case 2: shell.goBranch(0, initialLocation: true); break;
            case 3: context.go('/nearby'); break;
            case 4: shell.goBranch(4, initialLocation: true); break;
          }
        },
      ),
    );
  }
}

class _PrimaryBottomBar extends StatelessWidget {
  const _PrimaryBottomBar({required this.currentBranch, required this.isTe, required this.onSelected});
  final int currentBranch;
  final bool isTe;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final selected = switch (currentBranch) { 2 => 1, 4 => 4, _ => 0 };
    return SafeArea(top: false, child: Container(
      height: 72,
      decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Color(0xFFE6ECF5)))),
      child: Row(children: [
        _item(0, selected, Icons.home_outlined, Icons.home_rounded, isTe ? 'హోమ్' : 'Home'),
        _item(1, selected, Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded, isTe ? 'చాట్స్' : 'Chats'),
        Expanded(child: InkWell(onTap: () => onSelected(2), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(width: 48, height: 48, decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [Color(0xFF1769FF), Color(0xFF713BFF)])), child: const Icon(Icons.auto_awesome_rounded, color: Colors.white)),
        ]))),
        _item(3, selected, Icons.explore_outlined, Icons.explore_rounded, isTe ? 'ఎక్స్‌ప్లోర్' : 'Explore'),
        _item(4, selected, Icons.person_outline_rounded, Icons.person_rounded, isTe ? 'ప్రొఫైల్' : 'Profile'),
      ]),
    ));
  }

  Widget _item(int index, int selected, IconData icon, IconData selectedIcon, String label) => Expanded(child: InkWell(
    onTap: () => onSelected(index),
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(index == selected ? selectedIcon : icon, color: index == selected ? _navAccent : _navInk, size: 24),
      const SizedBox(height: 4),
      Text(label, style: TextStyle(fontSize: 11, fontWeight: index == selected ? FontWeight.w800 : FontWeight.w700, color: index == selected ? _navAccent : _navInk)),
    ]),
  ));
}

class _AskodoxDrawer extends StatefulWidget {
  const _AskodoxDrawer({required this.isTe, required this.currentBranch, required this.onBranch, required this.onRoute});
  final bool isTe;
  final int currentBranch;
  final ValueChanged<int> onBranch;
  final ValueChanged<String> onRoute;
  @override State<_AskodoxDrawer> createState() => _AskodoxDrawerState();
}

class _AskodoxDrawerState extends State<_AskodoxDrawer> {
  bool busy = false;
  double progress = 0;

  Future<void> _update() async {
    if (busy) return;
    if (!AskodoxUpdateService.enabled) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Updates are enabled in signed live builds.'))); return;
    }
    setState(() => busy = true);
    try {
      const service = AskodoxUpdateService();
      final result = await service.checkForUpdate();
      final update = result.update;
      if (!mounted) return;
      if (update == null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.isTe ? 'మీ ASKODOX ఇప్పటికే తాజా వెర్షన్‌లో ఉంది.' : 'ASKODOX is already up to date.')));
      } else {
        await service.downloadAndInstall(update, onProgress: (value) { if (mounted) setState(() => progress = value); });
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Update failed: $e')));
    } finally { if (mounted) setState(() => busy = false); }
  }

  @override
  Widget build(BuildContext context) {
    final te = widget.isTe;
    return Drawer(
      backgroundColor: Colors.white,
      child: SafeArea(child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
        children: [
          const ListTile(
            contentPadding: EdgeInsets.symmetric(horizontal: 8),
            leading: CircleAvatar(backgroundColor: Color(0xFFEDEBFF), child: Icon(Icons.auto_awesome_rounded, color: _navAccent)),
            title: Text('ASKODOX', style: TextStyle(color: _navInk, fontWeight: FontWeight.w900, fontSize: 21)),
            subtitle: Text('Find local • Get it done', style: TextStyle(color: _navMuted, fontWeight: FontWeight.w600)),
          ),
          const Divider(color: Color(0xFFD9E1EC)),
          _tile(Icons.home_outlined, te ? 'హోమ్' : 'Home', () => widget.onBranch(0), selected: widget.currentBranch == 0),
          _tile(Icons.chat_bubble_outline_rounded, te ? 'చాట్స్ / హిస్టరీ' : 'Chats / History', () => widget.onBranch(2), selected: widget.currentBranch == 2),
          _tile(Icons.person_outline_rounded, te ? 'ప్రొఫైల్ & పాత్రలు' : 'Profile & Roles', () => widget.onBranch(4), selected: widget.currentBranch == 4),
          _tile(Icons.location_on_outlined, te ? 'లొకేషన్ మార్చండి' : 'Change Location', () => widget.onRoute('/location')),
          _tile(Icons.notifications_none_rounded, te ? 'యాక్టివిటీ' : 'Activity', () => widget.onBranch(3), selected: widget.currentBranch == 3),
          _tile(Icons.settings_outlined, te ? 'సెట్టింగ్స్' : 'Settings', () => widget.onRoute('/notification-preferences')),
          _tile(Icons.support_agent_rounded, te ? 'సపోర్ట్' : 'Support', () => widget.onRoute('/communications')),
          _tile(Icons.privacy_tip_outlined, te ? 'ప్రైవసీ' : 'Privacy', () => widget.onRoute('/privacy')),
          const Divider(color: Color(0xFFD9E1EC)),
          Container(
            decoration: BoxDecoration(color: const Color(0xFFF3F2FF), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE0DEFF))),
            child: ListTile(
              leading: busy ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, value: progress > 0 ? progress : null)) : const Icon(Icons.system_update_alt_rounded, color: Color(0xFF1769FF)),
              title: Text(te ? 'ASKODOX అప్డేట్' : 'Update ASKODOX', style: const TextStyle(color: _navInk, fontWeight: FontWeight.w900)),
              subtitle: Text(te ? 'తాజా signed app ను చెక్ చేసి ఇన్‌స్టాల్ చేయండి' : 'Check and install the latest signed app', style: const TextStyle(color: _navMuted, fontWeight: FontWeight.w600)),
              onTap: _update,
            ),
          ),
        ],
      )),
    );
  }

  Widget _tile(IconData icon, String label, VoidCallback onTap, {bool selected = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: ListTile(
      dense: true,
      tileColor: selected ? const Color(0xFFF0EFFF) : Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      leading: Icon(icon, color: selected ? _navAccent : _navInk),
      trailing: Icon(Icons.chevron_right_rounded, color: selected ? _navAccent : _navMuted, size: 20),
      title: Text(label, style: TextStyle(color: selected ? _navAccent : _navInk, fontWeight: FontWeight.w800)),
      onTap: onTap,
    ),
  );
}
