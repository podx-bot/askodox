/// Owner 2026-11-26: the two sides of the app are named "My" and "My Biz" (not Buy / Sell, not "Dual Role"), so a
/// person, a shop owner, a job giver and a freelancer all read the switch the same way. ONE place: the bottom-bar
/// switch, the header chip and the screen-reader label all read these; change a word here and the whole app follows.
/// The words stay in English in every language (short enough for the switch, like the ASKODOX name itself).
library;

const askodoxMyName = 'My';
const askodoxMyBizName = 'My Biz';

/// The small line under the switch: what the side is, in the person's language.
String askodoxSideStateName({required bool seller, required bool te}) =>
    seller ? (te ? 'వ్యాపారం' : 'Business') : (te ? 'వ్యక్తిగతం' : 'Personal');

String askodoxSideName({required bool seller}) => seller ? askodoxMyBizName : askodoxMyName;

/// Read aloud by screen readers on the switch.
String askodoxSwitchSemantics({required bool seller, required bool te}) => te
    ? '${seller ? 'My Biz వైపు' : 'My వైపు'}. My నొక్కితే మీ వ్యక్తిగత పేజీ, My Biz నొక్కితే మీ షాప్ పేజీ'
    : '${seller ? 'My Biz side' : 'My side'}. My opens your personal page, My Biz opens your shop page';
