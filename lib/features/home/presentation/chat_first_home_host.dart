import 'package:flutter/material.dart';

import 'askodox_primary_home_screen.dart';

/// Primary ASKODOX experience.
///
/// This route owns one body only. The shared AppShell provides the single
/// header/drawer and single bottom navigation. Chat expands inside this same
/// body, so no nested Scaffold/AppBar/bottom navigation can be rendered.
class ChatFirstHomeHost extends StatelessWidget {
  const ChatFirstHomeHost({super.key});

  @override
  Widget build(BuildContext context) => const AskodoxPrimaryHomeScreen();
}
