/// Owner 2026-11-26 ("change the whole app with one command, not page by page"): the app-wide pieces of the screen
/// are switched HERE, in one place. Every page reads these; nothing is decided inside a page.
///
/// The defaults are what widget tests and older flows expect; the real app applies the owner's choice once in
/// `main()` through [askodoxApplyOwnerUi]. To change the whole app, change that one function.
library;

/// Mics INSIDE pages and boxes (step pages' bottom mic, speak-to-fill bars, box mics, command boxes). The chat's own
/// mic and the Ask button are not page mics.
bool askodoxPageMicsOn = true;

/// The "Guide on / off" chip (header + sign-in), its one-time intro card and the walkthrough that starts by itself.
bool askodoxGuideSwitchOn = true;

/// ONE "Ask" button on every page outside the bottom bar: say or type what you need, the answer comes on that page.
bool askodoxAskEverywhereOn = false;

/// The owner's app (2026-11-26): no guide chip, no mics on pages, one Ask button everywhere.
void askodoxApplyOwnerUi() {
  askodoxPageMicsOn = false;
  askodoxGuideSwitchOn = false;
  askodoxAskEverywhereOn = true;
}
