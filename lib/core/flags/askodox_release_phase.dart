/// Release phase (owner decision 2026-11-04).
///
/// Phase 1 ships: chat + result cards, the ASKODOX feed, payment alerts /
/// collect, OTP sign-in, the basic profile (language, location, history,
/// memory, notifications, payment methods, privacy, help), Smart Tools,
/// AI Credits and Travel Radio.
///
/// Phase 2 surfaces (business tools and POS, rides / parcels, several roles,
/// KYC, plans, money / tax tools, opportunities, own video uploads) stay in the
/// code, untouched, but are HIDDEN until Phase 2. A Phase 2 build turns them
/// back on with `--dart-define=ASKODOX_PHASE2=true`; nothing is deleted.
library;

/// True only in a Phase 2 build.
const bool askodoxPhase2 = bool.fromEnvironment('ASKODOX_PHASE2');

/// The Google Play bundle (owner 2026-11-10). Digital goods there must go through Play Billing, so
/// the Razorpay AI Credits recharge is not offered in this build (balance + history still show).
const bool askodoxPlayStoreBuild = bool.fromEnvironment('ASKODOX_PLAY_STORE');

/// Profile rows hidden in Phase 1 (their widget keys stay in the code).
const askodoxPhase2ProfileKeys = <String>{
  'profile-shop-scan',
  'profile-smart-tools', // owner 2026-11-14: Smart Tools come back in Phase 2
  'profile-mobility',
  'profile-tax-assistant',
  'profile-personal-finance',
  'profile-shop-advances',
  'askodoxMyRolesEntry',
  'askodoxProfileEditRoles',
  'profile-opportunities',
  'askodoxProfileDeliveryOpportunities',
  'profile-business-center',
  'profile-my-listings',
  'profile-enquiries',
  'profile-promotions',
  'profile-automation',
  'profile-native-video',
  'profile-creations',
  'profile-verification',
  'profile-plans',
  'profile-buyer-agent',
  'profile-radio',
};

/// App screens that belong to Phase 2. A chat action pointing at one shows no
/// button, and a guide that walks to one is not offered.
const askodoxPhase2Routes = <String>{
  // The full POS stays Phase 2. Phase 1 has the simple My business desk (/me/business), owner 2026-11-14.
  '/pos',
  '/crm',
  '/business',
  '/listings/mine',
  '/orders/mine',
  '/orders/incoming',
  '/mobility',
  '/videos/native',
  '/profile/roles',
  '/verification',
  '/opportunities',
  '/me/finance',
  '/intel/tax',
  '/me/shop-advances',
  '/shop-scan',
  '/plans',
  '/me/agent',
  '/talk',
  // Owner 2026-11-09 / 11-10: Radio and the cross-app screen guide are not in Phase 1; developer pages
  // never open from a link in a customer build.
  '/radio',
  '/companion/screen-guide',
  '/companion-lab',
  '/companion-performance',
};

/// Whether a Profile row with this key is shown in this build.
bool askodoxShownNow(String key) => askodoxPhase2 || !askodoxPhase2ProfileKeys.contains(key);

/// Whether an in-app route is open in this build ("/business/promotions" falls
/// under "/business"; a query string is ignored).
bool askodoxRouteShownNow(String route) {
  if (askodoxPhase2) return true;
  final path = route.split('?').first;
  return !askodoxPhase2Routes.any((r) => path == r || path.startsWith('$r/'));
}
