import 'demo_accounts.dart';

class DemoTutorialStep {
  const DemoTutorialStep(this.title, this.instruction);
  final String title;
  final String instruction;
}

class DemoTutorials {
  const DemoTutorials._();

  static const commonJourney = <DemoTutorialStep>[
    DemoTutorialStep('1. Party B creates a need', 'Enter as Party B and show the customer/seeker request using the existing ASKODOX flow.'),
    DemoTutorialStep('2. ASKODOX matches Party A', 'Show the relevant seller/provider/giver match and the matched activity.'),
    DemoTutorialStep('3. Party A responds', 'Switch to Party A and demonstrate the response or acceptance using the existing workflow.'),
    DemoTutorialStep('4. Party B confirms', 'Switch back to Party B and show confirmation/deal activation.'),
    DemoTutorialStep('5. Complete the journey', 'Complete the demo and show the resulting History/Activity state.'),
    DemoTutorialStep('6. Reset and replay', 'Reset demo data so the same tutorial can be recorded or demonstrated again.'),
  ];

  static String titleFor(DemoModule module) => switch (module) {
    DemoModule.commerce => 'How to Buy & Sell',
    DemoModule.jobs => 'How Jobs Work',
    DemoModule.services => 'How Services Work',
    DemoModule.rides => 'How Rides Work',
    DemoModule.parcel => 'How Parcel Delivery Works',
    DemoModule.appointments => 'How Appointments Work',
    DemoModule.catering => 'How Catering RFQ Works',
    DemoModule.localDiscovery => 'How Local Discovery Works',
  };
}
