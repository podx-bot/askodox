import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/flags/askodox_remote_flags.dart';
import '../../core/providers/app_settings_provider.dart';
import '../../services/reply_speech_service.dart';
import '../../shared/widgets/askodox_mascot.dart';
import '../companion/relationship.dart';

/// ASKODOX Screen Guide INSIDE the app: it points at the real button on the
/// real screen (dim + spotlight + pulse + arrow), says what to do in Telugu
/// or English (text + voice), waits for the user's own tap, notices when a
/// step is already done, brings the user back from a wrong screen, and
/// pauses on private screens (sign-in / OTP). It never taps anything itself
/// and never reads what is typed.
///
/// Steps point at widgets by their existing keys (`Key('x')` /
/// `ValueKey('x')`; a trailing `*` matches a key prefix), so screens need no
/// guide-specific code.
class AskodoxGuideStep {
  const AskodoxGuideStep(this.target, this.en, this.te, {this.route, this.fill = false});

  final String target;
  final String en;
  final String te;

  /// Where this step's button lives (used by "Take me there").
  final String? route;

  /// A field to fill in ("write your name here"): tapping it does NOT move on
  /// -- the person types, then taps "Next".
  final bool fill;
}

class AskodoxGuideFlow {
  const AskodoxGuideFlow(this.id, this.titleEn, this.titleTe, this.keywords, this.steps, {this.listed = true});

  final String id;
  final String titleEn;
  final String titleTe;
  final List<String> keywords;
  final List<AskodoxGuideStep> steps;

  /// Shown in the header Screen Guide list (screen guides started from a
  /// Profile tile's Guide button are not).
  final bool listed;

  String title(bool te) => te ? titleTe : titleEn;
}

const _profile = AskodoxGuideStep('askodoxNavProfile', 'Tap Profile at the bottom.', 'కింద ప్రొఫైల్ నొక్కండి.',
    route: '/profile');

const askodoxGuideFlows = <AskodoxGuideFlow>[
  AskodoxGuideFlow('upload_video', 'Upload a video', 'వీడియో అప్‌లోడ్ చేయడం',
      ['upload a video', 'upload video', 'add a video', 'publish a video', 'post a video', 'వీడియో అప్‌లోడ్', 'వీడియో పెట్ట'], [
    _profile,
    AskodoxGuideStep('profile-native-video', 'Tap "My videos".', '"నా వీడియోలు" నొక్కండి.', route: '/profile'),
    AskodoxGuideStep('video-pick-gallery', 'Tap "Choose video" and pick your video.', '"వీడియో ఎంచుకోండి" నొక్కి మీ వీడియో ఎంచుకోండి.',
        route: '/videos/native'),
    AskodoxGuideStep('video-title', 'Give it a short title.', 'చిన్న టైటిల్ ఇవ్వండి.', route: '/videos/native'),
    AskodoxGuideStep('video-upload', 'Tap "Upload for review". Staff check it before it is published.',
        '"రివ్యూకు అప్‌లోడ్" నొక్కండి. పబ్లిష్ ముందు స్టాఫ్ చూస్తారు.', route: '/videos/native'),
  ]),
  AskodoxGuideFlow('add_listing', 'Add a listing', 'లిస్టింగ్ జోడించడం',
      ['add a listing', 'add listing', 'list my product', 'sell my product', 'add a product', 'లిస్టింగ్', 'అమ్మడం ఎలా'], [
    _profile,
    AskodoxGuideStep('profile-my-listings', 'Tap "My listings".', '"నా లిస్టింగ్‌లు" నొక్కండి.', route: '/profile'),
    AskodoxGuideStep('askodoxAddListing', 'Tap "Sell something" and tell ASKODOX what you sell, the price and quantity.',
        '"ఏదైనా అమ్మండి" నొక్కి, ఏమి అమ్ముతారు, ధర, పరిమాణం చెప్పండి.', route: '/listings/mine'),
  ]),
  AskodoxGuideFlow('change_location', 'Change my location', 'లొకేషన్ మార్చడం',
      ['change location', 'change my location', 'set location', 'set my location', 'లొకేషన్ మార్చ', 'లొకేషన్ సెట్'], [
    AskodoxGuideStep('askodoxLocationChip', 'Tap your place at the top.', 'పైన మీ ప్రాంతం నొక్కండి.', route: '/'),
    AskodoxGuideStep('askodoxLocationSearch', 'Type your area or a landmark, then search.',
        'మీ ప్రాంతం లేదా ల్యాండ్‌మార్క్ టైప్ చేసి వెతకండి.', route: '/location'),
    AskodoxGuideStep('askodoxPlaceResult-*', 'Tap the right place in the list.', 'లిస్ట్‌లో సరైన ప్రాంతం నొక్కండి.',
        route: '/location'),
  ]),
  AskodoxGuideFlow('accept_order', 'Accept an order', 'ఆర్డర్ అంగీకరించడం',
      ['accept an order', 'accept order', 'accept a request', 'accept the request', 'ఆర్డర్ అంగీకరించ'], [
    AskodoxGuideStep('askodoxOrderAccept', 'Check the request, then tap "Accept". The buyer\'s contact appears only after you accept.',
        'రిక్వెస్ట్ చూసి "ఆమోదించు" నొక్కండి. అంగీకరించాకే కొనుగోలుదారు వివరాలు కనిపిస్తాయి.', route: '/orders/incoming'),
  ]),
  AskodoxGuideFlow('send_parcel', 'Send a parcel', 'పార్సెల్ పంపడం',
      ['send a parcel', 'send parcel', 'courier', 'పార్సెల్ పంప'], [
    _profile,
    AskodoxGuideStep('profile-mobility', 'Tap "Rides, parcels & carpool".', '"రైడ్స్, పార్సెల్స్ & కార్‌పూల్" నొక్కండి.',
        route: '/profile'),
    AskodoxGuideStep('mobility-kind-parcel', 'Choose "Parcel".', '"పార్సెల్" ఎంచుకోండి.', route: '/mobility'),
    AskodoxGuideStep('mobility-from', 'Where from? Type, use my location or pick on the map.',
        'ఎక్కడి నుంచి? టైప్ చేయండి, నా లొకేషన్ లేదా మ్యాప్ వాడండి.', route: '/mobility'),
    AskodoxGuideStep('mobility-to', 'Where to?', 'ఎక్కడికి?', route: '/mobility'),
    AskodoxGuideStep('mobility-submit', 'Tap "Send request". It is confirmed only when a partner accepts.',
        '"రిక్వెస్ట్ పంపండి" నొక్కండి. పార్ట్‌నర్ అంగీకరించాకే కన్ఫర్మ్.', route: '/mobility'),
  ]),
  AskodoxGuideFlow('become_partner', 'Become a delivery partner', 'డెలివరీ పార్ట్‌నర్ అవ్వడం',
      ['delivery partner', 'become a driver', 'become driver', 'join as partner', 'join as a partner', 'డెలివరీ పార్ట్‌నర్', 'డ్రైవర్‌గా'], [
    _profile,
    AskodoxGuideStep('askodoxProfileDeliveryOpportunities', 'Tap "Delivery opportunities".', '"డెలివరీ అవకాశాలు" నొక్కండి.',
        route: '/profile'),
    AskodoxGuideStep('partner-name', 'Fill in your name, vehicle and services.', 'మీ పేరు, వాహనం, సేవలు నింపండి.',
        route: '/mobility?tab=3'),
    AskodoxGuideStep('partner-apply', 'Tap Apply. Staff review it, then you can go online.',
        'అప్లై నొక్కండి. స్టాఫ్ రివ్యూ తర్వాత ఆన్‌లైన్‌కి వెళ్లవచ్చు.', route: '/mobility?tab=3'),
  ]),
  AskodoxGuideFlow('report_problem', 'Report a problem', 'సమస్య చెప్పడం',
      ['report a problem', 'report problem', 'send feedback', 'report a bug', 'సమస్య చెప్ప', 'ఫీడ్‌బ్యాక్'], [
    _profile,
    AskodoxGuideStep('profile-feedback', 'Tap "Report a problem / Send feedback".', '"సమస్య చెప్పండి / ఫీడ్‌బ్యాక్" నొక్కండి.',
        route: '/profile'),
    AskodoxGuideStep('askodoxFeedbackDescription', 'Describe what happened. Never type passwords, OTPs or card numbers.',
        'ఏమైందో రాయండి. పాస్‌వర్డ్, OTP, కార్డ్ నంబర్లు వద్దు.', route: '/beta-feedback'),
    AskodoxGuideStep('askodoxFeedbackSubmit', 'Tap "Submit feedback".', '"ఫీడ్‌బ్యాక్ పంపండి" నొక్కండి.',
        route: '/beta-feedback'),
  ]),
  ...askodoxScreenGuides,
];

/// "Guide" on every Profile tile: opens the screen and shows what each part
/// is for and what to write where. Steps point at the screens' existing keys.
const _p = '/profile';
const askodoxScreenGuides = <AskodoxGuideFlow>[
  AskodoxGuideFlow('screen_profile_details', 'Complete my profile', 'నా ప్రొఫైల్ పూర్తి చేయడం', ['complete my profile', 'edit profile', 'ప్రొఫైల్ ఎడిట్'], [
    AskodoxGuideStep('askodoxProfileEdit', 'Tap the pencil to edit your details.', 'మీ వివరాలు మార్చడానికి పెన్సిల్ నొక్కండి.', route: _p),
    AskodoxGuideStep('askodoxEditName', 'Write your full name as customers should see it.', 'కస్టమర్లకు కనిపించాల్సిన మీ పూర్తి పేరు ఇక్కడ రాయండి.', fill: true),
    AskodoxGuideStep('askodoxEditAddress', 'Write your town and area, for example "Vuyyuru, Krishna district".', 'మీ ఊరు, ప్రాంతం రాయండి. ఉదా: "ఉయ్యూరు, కృష్ణా జిల్లా".', fill: true),
    AskodoxGuideStep('askodoxEditShop', 'If you sell: your business name and shop address.', 'మీరు అమ్మితే: మీ వ్యాపారం పేరు, షాప్ అడ్రస్ ఇక్కడ.', fill: true),
    AskodoxGuideStep('askodoxEditSave', 'Tap Save.', 'సేవ్ నొక్కండి.'),
  ], listed: false),
  AskodoxGuideFlow('screen_business', 'Business dashboard', 'వ్యాపార డాష్‌బోర్డ్', [], [
    AskodoxGuideStep('profile-business-center', 'Tap "Business dashboard".', '"వ్యాపార డాష్‌బోర్డ్" నొక్కండి.', route: _p),
    AskodoxGuideStep('askodoxBusinessSection-analytics', 'Here: requests, details customers asked for and new demand. Open a section to act on it.', 'ఇక్కడ: అభ్యర్థనలు, కస్టమర్లు అడిగిన వివరాలు, కొత్త డిమాండ్. ఏ విభాగమైనా తెరిచి పని చేయండి.', route: '/business'),
  ], listed: false),
  AskodoxGuideFlow('screen_listings', 'My listings & catalog', 'నా లిస్టింగ్‌లు & కేటలాగ్', [], [
    AskodoxGuideStep('profile-my-listings', 'Tap "My listings & catalog".', '"నా లిస్టింగ్‌లు & కేటలాగ్" నొక్కండి.', route: _p),
    AskodoxGuideStep('askodoxAddListing', 'Tap "Sell something" and say what you sell, the price and the quantity.', '"ఏదైనా అమ్మండి" నొక్కి, ఏమి అమ్ముతారు, ధర, పరిమాణం చెప్పండి.', route: '/listings/mine'),
  ], listed: false),
  AskodoxGuideFlow('screen_enquiries', 'Customer enquiries', 'కస్టమర్ ఎంక్వైరీలు', [], [
    AskodoxGuideStep('profile-enquiries', 'Tap "Customer enquiries".', '"కస్టమర్ ఎంక్వైరీలు" నొక్కండి.', route: _p),
    AskodoxGuideStep('askodoxOrderAccept', 'Read the request, then tap "Accept". The customer\'s contact appears only after you accept.', 'రిక్వెస్ట్ చదివి "ఆమోదించు" నొక్కండి. అంగీకరించాకే కస్టమర్ వివరాలు కనిపిస్తాయి.', route: '/orders/incoming'),
  ], listed: false),
  AskodoxGuideFlow('screen_promotions', 'Offers & promotions', 'ఆఫర్లు & ప్రమోషన్లు', [], [
    AskodoxGuideStep('profile-promotions', 'Tap "Offers & promotions".', '"ఆఫర్లు & ప్రమోషన్లు" నొక్కండి.', route: _p),
    AskodoxGuideStep('askodoxOfferCreate', 'Tap to create a new offer.', 'కొత్త ఆఫర్ కోసం ఇక్కడ నొక్కండి.', route: '/business/promotions'),
    AskodoxGuideStep('askodoxOfferTitle', 'Write the offer in a few words, for example "10% off on rice bags".', 'ఆఫర్‌ను కొన్ని మాటల్లో రాయండి. ఉదా: "బియ్యం బస్తాలపై 10% తగ్గింపు".', route: '/business/promotions', fill: true),
    AskodoxGuideStep('askodoxOfferValue', 'Write the discount: an amount or a percent.', 'తగ్గింపు రాయండి: రూపాయలు లేదా శాతం.', route: '/business/promotions', fill: true),
    AskodoxGuideStep('askodoxOfferSubmit', 'Tap to save the offer.', 'ఆఫర్ సేవ్ చేయడానికి నొక్కండి.', route: '/business/promotions'),
  ], listed: false),
  AskodoxGuideFlow('screen_automation', 'Auto-replies', 'ఆటో-రిప్లైలు', [], [
    AskodoxGuideStep('profile-automation', 'Tap "Auto-replies".', '"ఆటో-రిప్లైలు" నొక్కండి.', route: _p),
    AskodoxGuideStep('askodoxAutoReplyEnabled', 'Switch auto-replies on.', 'ఆటో-రిప్లైలు ఆన్ చేయండి.', route: '/business/automation'),
    AskodoxGuideStep('askodoxAutoHours', 'Set your working hours.', 'మీ పని వేళలు సెట్ చేయండి.', route: '/business/automation', fill: true),
    AskodoxGuideStep('askodoxAutoFaqAdd', 'Add a question customers often ask.', 'కస్టమర్లు తరచూ అడిగే ప్రశ్న జోడించండి.', route: '/business/automation'),
    AskodoxGuideStep('askodoxAutoFaqTopic', 'Write the question, for example "Do you deliver?".', 'ప్రశ్న రాయండి. ఉదా: "డెలివరీ చేస్తారా?".', route: '/business/automation', fill: true),
    AskodoxGuideStep('askodoxAutoFaqAnswer', 'Write your answer exactly as it should be sent.', 'పంపాల్సిన సమాధానం ఉన్నది ఉన్నట్టు రాయండి.', route: '/business/automation', fill: true),
    AskodoxGuideStep('askodoxAutoFaqSave', 'Tap Save.', 'సేవ్ నొక్కండి.', route: '/business/automation'),
  ], listed: false),
  AskodoxGuideFlow('screen_videos', 'My videos', 'నా వీడియోలు', [], [
    AskodoxGuideStep('profile-native-video', 'Tap "My videos".', '"నా వీడియోలు" నొక్కండి.', route: _p),
    AskodoxGuideStep('video-pick-gallery', 'Tap "Choose video" and pick your video.', '"వీడియో ఎంచుకోండి" నొక్కి మీ వీడియో ఎంచుకోండి.', route: '/videos/native'),
    AskodoxGuideStep('video-title', 'Give it a short title.', 'చిన్న టైటిల్ రాయండి.', route: '/videos/native', fill: true),
    AskodoxGuideStep('video-upload', 'Tap "Upload for review". Staff check it before it is published.', '"రివ్యూకు అప్‌లోడ్" నొక్కండి. పబ్లిష్ ముందు స్టాఫ్ చూస్తారు.', route: '/videos/native'),
  ], listed: false),
  AskodoxGuideFlow('screen_creations', 'My creations', 'నా క్రియేషన్స్', [], [
    AskodoxGuideStep('profile-creations', 'Tap "My creations".', '"నా క్రియేషన్స్" నొక్కండి.', route: _p),
    AskodoxGuideStep('askodoxCreationAbout', 'Write the facts: what you sell, the price, any offer, your area.', 'వివరాలు రాయండి: ఏమి అమ్ముతారు, ధర, ఆఫర్, మీ ప్రాంతం.', route: '/business/creations', fill: true),
    AskodoxGuideStep('askodoxCreationDraft', 'Tap to make a draft from your facts.', 'మీ వివరాలతో డ్రాఫ్ట్ తయారు చేయడానికి నొక్కండి.', route: '/business/creations'),
    AskodoxGuideStep('askodoxCreationSave', 'Check the draft, then save it.', 'డ్రాఫ్ట్ చూసి సేవ్ చేయండి.', route: '/business/creations'),
  ], listed: false),
  AskodoxGuideFlow('screen_roles', 'My roles', 'నా పాత్రలు', [], [
    AskodoxGuideStep('askodoxMyRolesEntry', 'Tap "My roles".', '"నా పాత్రలు" నొక్కండి.', route: _p),
    AskodoxGuideStep('askodoxRolesPersonal', 'Each role adds its own sections. Keep on only what you really do.', 'ప్రతి పాత్ర దాని విభాగాలు జోడిస్తుంది. మీరు నిజంగా చేసేవే ఉంచండి.', route: '/profile/roles'),
  ], listed: false),
  AskodoxGuideFlow('screen_opportunities', 'Opportunities near you', 'మీ దగ్గరి అవకాశాలు', [], [
    AskodoxGuideStep('profile-opportunities', 'Tap here to see what customers near you are asking for, matched to your roles.', 'మీ పాత్రలకు సరిపడే, మీ దగ్గరి కస్టమర్లు అడుగుతున్నవి చూడడానికి ఇక్కడ నొక్కండి.', route: _p),
  ], listed: false),
  AskodoxGuideFlow('screen_partner', 'Delivery & ride partner', 'డెలివరీ & రైడ్ పార్ట్‌నర్', [], [
    AskodoxGuideStep('askodoxProfileDeliveryOpportunities', 'Tap "Delivery & ride partner".', '"డెలివరీ & రైడ్ పార్ట్‌నర్" నొక్కండి.', route: _p),
    AskodoxGuideStep('partner-name', 'Fill in your name, your vehicle and the services you give.', 'మీ పేరు, వాహనం, మీరు ఇచ్చే సేవలు నింపండి.', route: '/mobility?tab=3', fill: true),
    AskodoxGuideStep('partner-apply', 'Tap Apply. Staff review it first.', 'అప్లై నొక్కండి. ముందు స్టాఫ్ రివ్యూ చేస్తారు.', route: '/mobility?tab=3'),
  ], listed: false),
  AskodoxGuideFlow('screen_mobility', 'Rides, parcels & carpool', 'రైడ్స్, పార్సెల్స్ & కార్‌పూల్', [], [
    AskodoxGuideStep('profile-mobility', 'Tap "Rides, parcels & carpool".', '"రైడ్స్, పార్సెల్స్ & కార్‌పూల్" నొక్కండి.', route: _p),
    AskodoxGuideStep('mobility-from', 'Where from? Type it, use my location or pick on the map.', 'ఎక్కడి నుంచి? టైప్ చేయండి, నా లొకేషన్ లేదా మ్యాప్ వాడండి.', route: '/mobility', fill: true),
    AskodoxGuideStep('mobility-to', 'Where to?', 'ఎక్కడికి?', route: '/mobility', fill: true),
    AskodoxGuideStep('mobility-submit', 'Tap "Send request". It is confirmed only when a partner accepts.', '"రిక్వెస్ట్ పంపండి" నొక్కండి. పార్ట్‌నర్ అంగీకరించాకే కన్ఫర్మ్.', route: '/mobility'),
  ], listed: false),
  AskodoxGuideFlow('screen_location', 'Location', 'లొకేషన్', [], [
    AskodoxGuideStep('profile-location', 'Tap "Location".', '"లొకేషన్" నొక్కండి.', route: _p),
    AskodoxGuideStep('askodoxLocationSearch', 'Type your area or a landmark near you.', 'మీ ప్రాంతం లేదా దగ్గరి ల్యాండ్‌మార్క్ టైప్ చేయండి.', route: '/location', fill: true),
    AskodoxGuideStep('askodoxLocationSearchGo', 'Search, then pick the right place in the list.', 'వెతికి, లిస్ట్‌లో సరైన ప్రాంతం ఎంచుకోండి.', route: '/location'),
  ], listed: false),
  AskodoxGuideFlow('screen_notifications', 'Notifications', 'నోటిఫికేషన్స్', [], [
    AskodoxGuideStep('profile-notifications', 'Tap "Notifications".', '"నోటిఫికేషన్స్" నొక్కండి.', route: _p),
    AskodoxGuideStep('askodoxNotificationsSwitch', 'Switch on to hear when someone replies to you.', 'ఎవరైనా మీకు స్పందించినప్పుడు తెలియడానికి ఆన్ చేయండి.', route: '/settings/notifications'),
    AskodoxGuideStep('askodoxPushSelfTest', 'Send a test notification to this phone.', 'ఈ ఫోన్‌కు టెస్ట్ నోటిఫికేషన్ పంపండి.', route: '/settings/notifications'),
  ], listed: false),
  AskodoxGuideFlow('screen_memory', 'Memory & personalization', 'మెమరీ & వ్యక్తిగతీకరణ', [], [
    AskodoxGuideStep('askodoxProfileMemoryEntry', 'Tap "Memory & personalization".', '"మెమరీ & వ్యక్తిగతీకరణ" నొక్కండి.', route: _p),
    AskodoxGuideStep('askodoxMemoryEnabled', 'Choose whether ASKODOX remembers your needs. You can correct or delete anything.', 'ASKODOX మీ అవసరాలు గుర్తుంచుకోవాలో వద్దో ఎంచుకోండి. ఏదైనా సరిచేయొచ్చు, తొలగించొచ్చు.', route: '/profile/memory'),
  ], listed: false),
  AskodoxGuideFlow('screen_privacy', 'Privacy & data', 'గోప్యత & డేటా', [], [
    AskodoxGuideStep('profile-privacy', 'Here you see what is stored, download it or delete your account.', 'ఇక్కడ ఏమి సేవ్ అయిందో చూడొచ్చు, డౌన్‌లోడ్ చేయొచ్చు లేదా ఖాతా తొలగించొచ్చు.', route: _p),
  ], listed: false),
  AskodoxGuideFlow('screen_kyc', 'Verification (KYC)', 'ధృవీకరణ (KYC)', [], [
    AskodoxGuideStep('profile-verification', 'Tap "Verification".', '"ధృవీకరణ" నొక్కండి.', route: _p),
    AskodoxGuideStep('askodoxKycConsent', 'Read what is checked and give consent first.', 'ఏమి చెక్ చేస్తారో చదివి ముందు అనుమతి ఇవ్వండి.', route: '/verification'),
    AskodoxGuideStep('askodoxKycAddDocument', 'Add a clear photo of your document.', 'మీ డాక్యుమెంట్ స్పష్టమైన ఫోటో జోడించండి.', route: '/verification'),
  ], listed: false),
  AskodoxGuideFlow('screen_plans', 'Plans & subscription', 'ప్లాన్లు & సబ్‌స్క్రిప్షన్', [], [
    AskodoxGuideStep('profile-plans', 'Tap "Plans".', '"ప్లాన్లు" నొక్కండి.', route: _p),
    AskodoxGuideStep('askodoxPlansCurrent', 'Your current plan is shown here; compare the others below it.', 'మీ ప్రస్తుత ప్లాన్ ఇక్కడ; కింద మిగతావి పోల్చి చూడండి.', route: '/plans'),
  ], listed: false),
  AskodoxGuideFlow('screen_radio', 'Travel Radio', 'ట్రావెల్ రేడియో', [], [
    AskodoxGuideStep('profile-radio', 'Travel Radio tells you about places on your route. Tap to see the plans.', 'ట్రావెల్ రేడియో మీ దారిలోని ప్రాంతాల గురించి చెబుతుంది. ప్లాన్లు చూడడానికి నొక్కండి.', route: _p),
  ], listed: false),
  AskodoxGuideFlow('screen_feedback', 'Report a problem', 'సమస్య చెప్పడం', [], [
    AskodoxGuideStep('profile-feedback', 'Tap "Report a problem / Send feedback".', '"సమస్య చెప్పండి / ఫీడ్‌బ్యాక్" నొక్కండి.', route: _p),
    AskodoxGuideStep('askodoxFeedbackDescription', 'Describe what happened. Never type passwords, OTPs or card numbers.', 'ఏమైందో రాయండి. పాస్‌వర్డ్, OTP, కార్డ్ నంబర్లు వద్దు.', route: '/beta-feedback', fill: true),
    AskodoxGuideStep('askodoxFeedbackSubmit', 'Tap "Submit feedback".', '"ఫీడ్‌బ్యాక్ పంపండి" నొక్కండి.', route: '/beta-feedback'),
  ], listed: false),
];

final _howTo = RegExp(
    r'\b(how (do|can|to|should)|show me how|teach me|guide me|help me (to )?|where (do|can) i|steps? to)\b|ఎలా|చూపించు|నేర్పించు',
    caseSensitive: false);

/// A how-to question ("how do I upload a video?") -> the matching guide.
/// Plain requests ("send a parcel from X to Y") are not how-to questions.
AskodoxGuideFlow? askodoxGuideFor(String text) {
  final t = text.toLowerCase();
  if (!_howTo.hasMatch(t)) return null;
  for (final flow in askodoxGuideFlows) {
    if (flow.keywords.any(t.contains)) return flow;
  }
  return null;
}

AskodoxGuideFlow? askodoxGuideById(String id) {
  for (final f in askodoxGuideFlows) {
    if (f.id == id) return f;
  }
  return null;
}

/// Private screens: the guide hides and says it paused (nothing is read,
/// captured or spoken there).
const askodoxGuidePrivateRoutes = ['/onboarding', '/auth', '/staff', '/payment', '/checkout'];

bool askodoxGuideIsPrivate(String location) =>
    askodoxGuidePrivateRoutes.any((r) => location == r || location.startsWith('$r?') || location.startsWith('$r/'));

class AskodoxGuideState {
  const AskodoxGuideState({required this.flow, this.index = 0, this.done = false});
  final AskodoxGuideFlow flow;
  final int index;
  final bool done;

  AskodoxGuideStep get step => flow.steps[index.clamp(0, flow.steps.length - 1)];
  bool get last => index >= flow.steps.length - 1;
}

class AskodoxGuideController extends StateNotifier<AskodoxGuideState?> {
  AskodoxGuideController() : super(null);

  void start(AskodoxGuideFlow flow) => state = AskodoxGuideState(flow: flow);

  /// The user did this step (their own tap) -> the next one, or done.
  void advance() {
    final s = state;
    if (s == null || s.done) return;
    state = s.last
        ? AskodoxGuideState(flow: s.flow, index: s.index, done: true)
        : AskodoxGuideState(flow: s.flow, index: s.index + 1);
  }

  /// A later step's button is already on screen: the earlier ones are done.
  void jumpTo(int index) {
    final s = state;
    if (s == null || s.done || index <= s.index || index >= s.flow.steps.length) return;
    state = AskodoxGuideState(flow: s.flow, index: index);
  }

  void stop() => state = null;
}

final askodoxGuideProvider =
    StateNotifierProvider<AskodoxGuideController, AskodoxGuideState?>((ref) => AskodoxGuideController());

/// Speaks a guide line with the same voice as Main Chat: Sarvam Bulbul
/// (backend `/api/in-app/voice/speak`, flag `voice.sarvam_tts`, the Profile
/// voice choice) and device TTS only when that audio is unavailable. Guide
/// lines are fixed text and private screens pause the guide, so nothing the
/// user typed is ever sent. Off in tests / when unavailable.
typedef AskodoxGuideSpeaker = Future<void> Function(String text, String language);

final askodoxGuideSpeakerProvider = Provider<AskodoxGuideSpeaker>((ref) => (text, language) async {
      const device = MethodChannel('com.askodox.app/device');
      final voice = ref.read(appSettingsProvider).voicePreference.storageValue;
      try {
        if (ref.read(askodoxFlagProvider('voice.sarvam_tts'))) {
          final audio = await const ReplySpeechService().sarvamAudio(text, locale: language, voice: voice);
          if (audio != null &&
              await device.invokeMethod<bool>('playReplyAudio', {'bytes': audio, 'languageCode': language}) == true) {
            return;
          }
        }
        await device.invokeMethod<bool>('speakReply', {'text': text, 'languageCode': language, 'voicePreference': voice});
      } catch (_) {}
    });

/// Finds a widget by key value (or `prefix*`) in the live element tree.
Element? askodoxFindKeyed(Element root, String target) {
  final prefix = target.endsWith('*') ? target.substring(0, target.length - 1) : null;
  Element? found;
  void visit(Element e) {
    if (found != null) return;
    final key = e.widget.key;
    if (key is ValueKey) {
      final v = key.value;
      if (v is String && (prefix != null ? v.startsWith(prefix) : v == target)) {
        final box = e.renderObject;
        if (box is RenderBox && box.attached && box.hasSize) {
          found = e;
          return;
        }
      }
    }
    e.visitChildren(visit);
  }

  root.visitChildren(visit);
  return found;
}

/// The overlay above every screen (placed in the app builder).
class AskodoxGuideOverlay extends ConsumerStatefulWidget {
  const AskodoxGuideOverlay({super.key, required this.child, this.router});

  final Widget child;
  final GoRouter? router;

  @override
  ConsumerState<AskodoxGuideOverlay> createState() => _AskodoxGuideOverlayState();
}

class _AskodoxGuideOverlayState extends ConsumerState<AskodoxGuideOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);
  final _stackKey = GlobalKey();
  final _bubbleKey = GlobalKey();
  Timer? _scan;
  Rect? _rect;
  int _missing = 0;
  bool _private = false;
  String? _spoken;

  bool get _te => Localizations.maybeLocaleOf(context)?.languageCode == 'te';

  @override
  void initState() {
    super.initState();
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
    widget.router?.routerDelegate.addListener(_onRoute);
    ref.listenManual<AskodoxGuideState?>(askodoxGuideProvider, (previous, next) {
      if (next == null) {
        _scan?.cancel();
        _scan = null;
        if (mounted) setState(() => _rect = null);
        return;
      }
      _scan ??= Timer.periodic(const Duration(milliseconds: 250), (_) => _locate());
      _missing = 0;
      _locate();
      _speak(next);
      if (next.done) {
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted && identical(ref.read(askodoxGuideProvider), next)) ref.read(askodoxGuideProvider.notifier).stop();
        });
      }
    });
  }

  @override
  void didUpdateWidget(AskodoxGuideOverlay old) {
    super.didUpdateWidget(old);
    if (old.router != widget.router) {
      old.router?.routerDelegate.removeListener(_onRoute);
      widget.router?.routerDelegate.addListener(_onRoute);
    }
  }

  @override
  void dispose() {
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    widget.router?.routerDelegate.removeListener(_onRoute);
    _scan?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  void _onRoute() {
    // The TOP page's location (a pushed /onboarding counts too).
    String location = '';
    try {
      final config = widget.router?.routerDelegate.currentConfiguration;
      location = config == null || config.isEmpty ? '' : config.last.matchedLocation;
    } catch (_) {}
    final private = askodoxGuideIsPrivate(location);
    if (private == _private) return;
    // The router notifies while the app is building: apply after the frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _private != private) setState(() => _private = private);
    });
  }

  void _speak(AskodoxGuideState s) {
    if (_private) return;
    final line = s.done
        ? askodoxDoneLine(ref.read(askodoxRelationProvider), telugu: _te)
        : (_te ? s.step.te : s.step.en);
    final key = '${s.flow.id}:${s.index}:${s.done}';
    if (_spoken == key) return;
    _spoken = key;
    unawaited(ref.read(askodoxGuideSpeakerProvider)(line, _te ? 'te' : 'en'));
  }

  /// Where the current step's button is. A later step's button already on
  /// screen means the user is ahead (skip); nothing on screen for a while
  /// means a wrong screen (offer "Take me there").
  void _locate() {
    final s = ref.read(askodoxGuideProvider);
    final root = _stackKey.currentContext as Element?;
    if (s == null || s.done || root == null || !mounted) return;
    // The current step's button is on screen: stay on it.
    final currentHere = _visible(root, s.step.target) != null;
    // Only after the current button has been missing for a moment (a page
    // transition ignores taps for ~300 ms).
    if (!currentHere && _missing >= 4) {
      for (var i = s.index + 1; i < s.flow.steps.length; i++) {
        if (_visible(root, s.flow.steps[i].target) != null) {
          ref.read(askodoxGuideProvider.notifier).jumpTo(i);
          return;
        }
      }
    }
    final element = askodoxFindKeyed(root, s.step.target);
    Rect? rect = element == null ? null : _rectOf(element);
    if (element != null && rect != null && !_onScreen(rect)) {
      // Below the fold: scroll it into view for the user.
      Scrollable.ensureVisible(element, duration: const Duration(milliseconds: 250), alignment: .3);
      rect = null;
    } else if (element != null && rect != null && !_reachable(element)) {
      rect = null; // another tab / a page underneath: not where the user is
    }
    setState(() {
      _rect = rect;
      _missing = rect == null ? _missing + 1 : 0;
    });
  }

  Rect? _visible(Element root, String target) {
    final e = askodoxFindKeyed(root, target);
    final r = e == null ? null : _rectOf(e);
    return r != null && _onScreen(r) && _reachable(e!) ? r : null;
  }

  /// Truly on the visible screen: a tap at its centre would reach it (not
  /// an offstage tab, not a page under the top page).
  bool _reachable(Element e) {
    final box = e.renderObject as RenderBox?;
    if (box == null || !box.attached || !box.hasSize) return false;
    final centre = box.localToGlobal(box.size.center(Offset.zero));
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(result, centre, View.of(context).viewId);
    final bubble = _bubbleKey.currentContext?.findRenderObject();
    for (final entry in result.path) {
      RenderObject? node = entry.target is RenderObject ? entry.target as RenderObject : null;
      while (node != null) {
        if (identical(node, box)) return true;
        if (bubble != null && identical(node, bubble)) return true; // under our own bubble
        node = node.parent;
      }
    }
    return false;
  }

  Rect? _rectOf(Element e) {
    final box = e.renderObject as RenderBox?;
    final stack = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || stack == null || !box.attached || !box.hasSize) return null;
    final offset = box.localToGlobal(Offset.zero, ancestor: stack);
    return offset & box.size;
  }

  bool _onScreen(Rect r) {
    final size = (_stackKey.currentContext?.findRenderObject() as RenderBox?)?.size;
    if (size == null) return false;
    return r.top >= 0 && r.bottom <= size.height && r.left >= -1 && r.right <= size.width + 1 && r.height > 0;
  }

  /// The user's own tap on the highlighted button completes the step.
  void _onPointer(PointerEvent event) {
    if (event is! PointerUpEvent) return;
    final s = ref.read(askodoxGuideProvider);
    final rect = _rect;
    final stack = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (s == null || s.done || rect == null || stack == null || _private) return;
    if (s.step.fill) return; // typing here: the person taps "Next" when done
    final local = stack.globalToLocal(event.position);
    if (rect.inflate(6).contains(local)) {
      // After the tap's own action runs.
      Future.delayed(const Duration(milliseconds: 120), () {
        if (mounted && identical(ref.read(askodoxGuideProvider), s)) ref.read(askodoxGuideProvider.notifier).advance();
      });
    }
  }

  void _takeMeThere(String route) {
    final router = widget.router;
    if (router == null) return;
    const branches = ['/', '/profile', '/updates', '/watchlist'];
    if (branches.contains(route)) {
      router.go(route);
    } else {
      router.push(route);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(askodoxGuideProvider);
    return Stack(key: _stackKey, children: [
      widget.child,
      if (s != null && _private)
        Positioned(
          left: 16,
          right: 16,
          top: MediaQuery.paddingOf(context).top + 8,
          child: Material(
            key: const Key('askodoxGuidePaused'),
            color: const Color(0xFF10204A),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(
                  _te
                      ? 'ఇది ప్రైవేట్ స్క్రీన్ -- గైడ్ ఆగింది. ఇక్కడి వివరాలు చదవదు.'
                      : 'Private screen -- the guide is paused and reads nothing here.',
                  style: const TextStyle(color: Colors.white)),
            ),
          ),
        )
      else if (s != null) ...[
        if (_rect != null && !s.done)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _pulse,
                builder: (context, _) => CustomPaint(
                    key: const Key('askodoxGuideSpotlight'), painter: _SpotlightPainter(_rect!, _pulse.value)),
              ),
            ),
          ),
        if (_rect != null && !s.done) _arrow(_rect!),
        _bubble(context, s),
      ],
    ]);
  }

  Widget _arrow(Rect r) {
    final size = (_stackKey.currentContext?.findRenderObject() as RenderBox?)?.size ?? Size.zero;
    final below = r.center.dy < size.height / 2;
    return Positioned(
      left: (r.center.dx - 18).clamp(0, math.max(0, size.width - 36)).toDouble(),
      top: below ? r.bottom + 4 : r.top - 40,
      child: IgnorePointer(
        child: Icon(below ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
            key: const Key('askodoxGuideArrow'), size: 36, color: const Color(0xFFFFC94D)),
      ),
    );
  }

  Widget _bubble(BuildContext context, AskodoxGuideState s) {
    final size = (_stackKey.currentContext?.findRenderObject() as RenderBox?)?.size ?? MediaQuery.sizeOf(context);
    final r = _rect;
    final atTop = r != null && r.center.dy > size.height / 2;
    final step = s.step;
    final lost = !s.done && r == null && _missing >= 6;
    final text = s.done
        ? '${askodoxDoneLine(ref.watch(askodoxRelationProvider), telugu: _te)} 🎉'
        : lost
            ? (_te ? 'ఈ బటన్ ఈ స్క్రీన్‌లో లేదు.' : 'That button is not on this screen.')
            : (_te ? step.te : step.en);
    return Positioned(
      left: 12,
      right: 12,
      top: atTop ? MediaQuery.paddingOf(context).top + 8 : null,
      bottom: atTop ? null : MediaQuery.paddingOf(context).bottom + 96,
      child: Material(
        key: _bubbleKey,
        elevation: 6,
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 6, 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(right: 10, top: 2),
              // ASKO from the mascot team: the expression follows the step
              // (explaining, waiting for typing, lost, done).
              child: KeyedSubtree(
                key: const Key('askodoxGuideFace'),
                child: AskodoxMascot(
                  mood: s.done
                      ? AskodoxMascotMood.success
                      : lost
                          ? AskodoxMascotMood.confused
                          : step.fill
                              ? AskodoxMascotMood.typing
                              : AskodoxMascotMood.happy,
                  size: 52,
                ),
              ),
            ),
            Expanded(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${s.flow.title(_te)} · ${s.index + 1}/${s.flow.steps.length}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF6C4DFF), fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(text, key: const Key('askodoxGuideText'),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF10204A))),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              if (lost && step.route != null)
                TextButton(
                    key: const Key('askodoxGuideTakeMe'),
                    onPressed: () => _takeMeThere(step.route!),
                    child: Text(_te ? 'అక్కడికి తీసుకెళ్లు' : 'Take me there')),
              if (!s.done && (!s.last || step.fill))
                TextButton(
                    key: const Key('askodoxGuideSkip'),
                    onPressed: () => ref.read(askodoxGuideProvider.notifier).advance(),
                    child: Text(step.fill ? (_te ? 'రాశాను, తర్వాత' : 'Done, next') : (_te ? 'తర్వాతి దశ' : 'Skip step'))),
              TextButton(
                  key: const Key('askodoxGuideStop'),
                  onPressed: () => ref.read(askodoxGuideProvider.notifier).stop(),
                  child: Text(s.done ? (_te ? 'మూసివేయండి' : 'Close') : (_te ? 'ఆపండి' : 'Stop'))),
            ]),
          ])),
          ]),
        ),
      ),
    );
  }
}

/// The guide's face: eyes that look toward the field being explained and a
/// mouth that moves while it speaks.
class AskodoxGuideFacePainter extends CustomPainter {
  AskodoxGuideFacePainter({required this.look, required this.mouth, required this.blink});

  /// Unit direction the eyes look at.
  final Offset look;

  /// 0 = closed, 1 = wide open.
  final double mouth;
  final bool blink;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    canvas.drawCircle(c, r, Paint()..color = const Color(0xFF6C4DFF));
    canvas.drawCircle(c, r * .86, Paint()..color = const Color(0xFFF1ECFF));
    for (final dx in [-r * .34, r * .34]) {
      final eye = c + Offset(dx, -r * .18);
      if (blink) {
        canvas.drawLine(eye - Offset(r * .14, 0), eye + Offset(r * .14, 0),
            Paint()
              ..color = const Color(0xFF10204A)
              ..strokeWidth = 2.2
              ..strokeCap = StrokeCap.round);
      } else {
        canvas.drawCircle(eye, r * .17, Paint()..color = Colors.white);
        canvas.drawCircle(eye + look * (r * .07), r * .095, Paint()..color = const Color(0xFF10204A));
      }
    }
    final open = mouth.clamp(0.0, 1.0);
    final mouthRect = Rect.fromCenter(center: c + Offset(0, r * .36), width: r * .62, height: r * (.06 + .32 * open));
    canvas.drawRRect(RRect.fromRectAndRadius(mouthRect, Radius.circular(r * .2)),
        Paint()..color = const Color(0xFF10204A));
  }

  @override
  bool shouldRepaint(AskodoxGuideFacePainter old) => old.look != look || old.mouth != mouth || old.blink != blink;
}

class _SpotlightPainter extends CustomPainter {
  _SpotlightPainter(this.target, this.t);
  final Rect target;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final hole = RRect.fromRectAndRadius(target.inflate(6), const Radius.circular(14));
    final dim = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(hole)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(dim, Paint()..color = const Color(0x8C0B1330));
    canvas.drawRRect(
        hole.inflate(2 + 6 * t),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = Color.lerp(const Color(0xFFFFC94D), const Color(0x00FFC94D), t * .7)!);
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) => old.target != target || old.t != t;
}

/// "Show me how" list (Help, Screen Guide page, chat).
class AskodoxGuideList extends ConsumerWidget {
  const AskodoxGuideList({super.key, required this.te, this.onStarted});
  final bool te;
  final VoidCallback? onStarted;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(mainAxisSize: MainAxisSize.min, children: [
        for (final flow in askodoxGuideFlows.where((f) => f.listed))
          ListTile(
            key: ValueKey('askodoxGuideStart-${flow.id}'),
            leading: const Icon(Icons.assistant_navigation),
            title: Text(flow.title(te)),
            trailing: const Icon(Icons.play_arrow_rounded),
            onTap: () {
              ref.read(askodoxGuideProvider.notifier).start(flow);
              onStarted?.call();
            },
          ),
      ]);
}
