/// What this app process already knows about start-up, so a rebuilt router
/// (it is rebuilt when the sign-in session changes) never shows the
/// onboarding / language page again to someone who finished onboarding.
/// Cleared on sign-out and account deletion. In memory only.
class AskodoxStartupHint {
  AskodoxStartupHint._();

  static bool onboardingComplete = false;

  /// Where a freshly built router should start.
  static String get initialLocation => onboardingComplete ? '/' : '/onboarding';
}
