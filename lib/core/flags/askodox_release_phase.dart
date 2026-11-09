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

/// Profile rows hidden in Phase 1 (their widget keys stay in the code).
const askodoxPhase2ProfileKeys = <String>{
  'profile-shop-scan',
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
};

/// App screens that belong to Phase 2. A chat action pointing at one shows no
/// button, and a guide that walks to one is not offered.
const askodoxPhase2Routes = <String>{
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
