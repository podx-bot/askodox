import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/flags/askodox_release_phase.dart';
import 'package:podx/features/guide/in_app_guide.dart';

/// Release phase (owner decision 2026-11-04): Phase 2 surfaces stay in the code
/// but are hidden from a Phase 1 build; nothing is deleted.
void main() {
  test('a normal build is Phase 1', () {
    expect(askodoxPhase2, isFalse, reason: 'Phase 2 needs --dart-define=ASKODOX_PHASE2=true');
  });

  test('Phase 2 routes are closed (with their sub-screens), Phase 1 routes stay open', () {
    for (final route in ['/pos', '/pos/b1/items', '/business/promotions', '/mobility?tab=3', '/profile/roles',
        '/listings/mine', '/orders/incoming', '/me/finance', '/intel/tax', '/videos/native', '/verification',
        // Owner 2026-11-09 / 11-10: Radio, the cross-app guide and developer pages are not in Phase 1.
        '/radio', '/talk', '/companion/screen-guide', '/companion-lab']) {
      expect(askodoxRouteShownNow(route), isFalse, reason: route);
    }
    for (final route in ['/', '/profile', '/profile/memory', '/me/payment-methods', '/me/ai-credits',
        '/privacy', '/settings/notifications', '/updates', '/watchlist', '/tools', '/location', '/businesses']) {
      expect(askodoxRouteShownNow(route), isTrue, reason: route);
    }
  });

  test('every hidden Profile row key really exists in the Profile screen (no typo hides nothing)', () {
    final source = File('lib/features/profile/presentation/profile_screen.dart').readAsStringSync();
    for (final key in askodoxPhase2ProfileKeys) {
      expect(source.contains("'$key'"), isTrue, reason: key);
      expect(askodoxShownNow(key), isFalse, reason: key);
    }
    expect(askodoxShownNow('profile-ai-credits'), isTrue);
    expect(askodoxShownNow('profile-radio'), isFalse);
    expect(askodoxShownNow('profile-smart-tools'), isTrue);
    expect(askodoxShownNow('profile-privacy'), isTrue);
  });

  test('guides to Phase 2 screens are not offered; Phase 1 guides are', () {
    final available = {for (final f in askodoxGuideFlows) if (askodoxGuideAvailable(f)) f.id};
    for (final id in ['upload_video', 'add_listing', 'accept_order', 'send_parcel', 'become_partner']) {
      expect(available, isNot(contains(id)), reason: id);
    }
    for (final id in ['change_location', 'report_problem', 'screen_profile_details', 'screen_notifications']) {
      expect(available, contains(id), reason: id);
    }
  });
}
