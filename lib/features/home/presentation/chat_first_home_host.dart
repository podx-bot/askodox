import 'dart:async';

import 'package:flutter/material.dart';

import '../../catalog/application/conversation_turn_store.dart';
import 'askodox_primary_home_screen.dart';

/// Primary ASKODOX experience.
///
/// A cold/home launch must always start on the locked ASKODOX Home. Persisted
/// conversation turns belong to Chats / History and must never force the Home
/// route straight into an old expanded conversation.
class ChatFirstHomeHost extends StatefulWidget {
  const ChatFirstHomeHost({super.key});

  @override
  State<ChatFirstHomeHost> createState() => _ChatFirstHomeHostState();
}

class _ChatFirstHomeHostState extends State<ChatFirstHomeHost> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    unawaited(_prepareHome());
  }

  Future<void> _prepareHome() async {
    // Do not restore old chat bubbles into the initial Home experience.
    // This clears only the legacy active-conversation presentation cache; the
    // UniversalDealController keeps its own deal state independently.
    await const ConversationTurnStore().clear();
    if (mounted) setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const ColoredBox(
        color: Color(0xFFF9FBFF),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return const AskodoxPrimaryHomeScreen();
  }
}
