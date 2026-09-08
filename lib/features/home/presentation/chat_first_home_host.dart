import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../catalog/presentation/search_screen.dart';
import '../../deal_brain/application/universal_deal_controller.dart';
import 'home_screen.dart';

/// Keeps ASKODOX conversation on the primary Home route.
///
/// Home is the idle state. As soon as a request exists, the same primary route
/// expands into the active conversation state. Contextual result/detail pages
/// can still be pushed on top and back navigation returns to this live chat.
class ChatFirstHomeHost extends ConsumerWidget {
  const ChatFirstHomeHost({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(universalDealControllerProvider);
    if (session.deal != null) {
      return const SearchScreen();
    }
    return const HomeScreen();
  }
}
