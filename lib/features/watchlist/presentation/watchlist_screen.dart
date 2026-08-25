import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class WatchlistScreen extends StatelessWidget {
  const WatchlistScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFF),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        title: const Text(
          'History',
          style: TextStyle(color: Color(0xFF14213D), fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            tooltip: 'Filter history',
            onPressed: () {},
            icon: const Icon(Icons.tune_rounded, color: Color(0xFF1769FF)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
        children: [
          const Text(
            'Continue where you left off',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF14213D)),
          ),
          const SizedBox(height: 6),
          const Text(
            'Every ask, clarification, result and deal stays together as one ASKODOX timeline.',
            style: TextStyle(color: Color(0xFF667085), height: 1.4),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: const [
              _FilterChipLabel('All', true),
              _FilterChipLabel('Active', false),
              _FilterChipLabel('Matched', false),
              _FilterChipLabel('Completed', false),
            ],
          ),
          const SizedBox(height: 18),
          _HistoryCard(
            icon: Icons.shopping_bag_outlined,
            title: 'Chicken nearby',
            status: 'Matches ready',
            time: 'Just now',
            accent: const Color(0xFF10A53A),
            onTap: () => context.go('/search'),
          ),
          _HistoryCard(
            icon: Icons.work_outline_rounded,
            title: 'Computer operator job',
            status: 'Need one more detail',
            time: '2 hours ago',
            accent: const Color(0xFF1769FF),
            onTap: () => context.go('/search'),
          ),
          _HistoryCard(
            icon: Icons.directions_car_outlined,
            title: 'Ride to Vijayawada',
            status: '3 matches found',
            time: 'Yesterday',
            accent: const Color(0xFFFF8A00),
            onTap: () => context.go('/search'),
          ),
          _HistoryCard(
            icon: Icons.home_repair_service_outlined,
            title: 'AC service',
            status: 'Completed',
            time: '3 days ago',
            accent: const Color(0xFF8E5CF7),
            onTap: () => context.go('/search'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF1769FF),
        foregroundColor: Colors.white,
        onPressed: () => context.go('/'),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New ask', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
    );
  }
}

class _FilterChipLabel extends StatelessWidget {
  const _FilterChipLabel(this.label, this.selected);
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFE8F8ED) : Colors.white,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: selected ? const Color(0xFF10A53A) : const Color(0xFFE1E8F2)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? const Color(0xFF0B7E2C) : const Color(0xFF475467),
            fontWeight: FontWeight.w800,
          ),
        ),
      );
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.icon,
    required this.title,
    required this.status,
    required this.time,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String status;
  final String time;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        color: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFE5EAF2)),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 25,
                  backgroundColor: accent.withValues(alpha: .12),
                  child: Icon(icon, color: accent),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF14213D))),
                      const SizedBox(height: 5),
                      Row(children: [
                        Container(width: 7, height: 7, decoration: BoxDecoration(color: accent, shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                        Expanded(child: Text(status, style: const TextStyle(color: Color(0xFF667085)))),
                      ]),
                      const SizedBox(height: 4),
                      Text(time, style: const TextStyle(color: Color(0xFF98A2B3), fontSize: 12)),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Color(0xFF98A2B3)),
              ],
            ),
          ),
        ),
      );
}
