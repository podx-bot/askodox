import '../demo/demo_accounts.dart';

class ModuleFaq {
  const ModuleFaq(this.question, this.answer);
  final String question;
  final String answer;
}

class ModuleFaqs {
  const ModuleFaqs._();

  static const common = <ModuleFaq>[
    ModuleFaq('How does ASKODOX work?', 'Tell ASKODOX what you need. It captures the requirement, finds the relevant other party, and helps both sides continue the deal in the app.'),
    ModuleFaq('Do I need to contact everyone?', 'No. ASKODOX is designed to show or notify relevant matches instead of making you contact unrelated users.'),
    ModuleFaq('What if there is no match?', 'Your requirement can stay open for matching. If it cannot be resolved automatically, it can be escalated for support.'),
    ModuleFaq('Can I use voice?', 'Yes. Voice and text should feed the same requirement flow.'),
    ModuleFaq('Can I change my requirement?', 'Yes. Update only the changed detail; the rest of the existing requirement can be retained.'),
  ];

  static List<ModuleFaq> forModule(DemoModule module) => [
    ...common,
    switch (module) {
      DemoModule.commerce => const ModuleFaq('How do buying and selling work?', 'A buyer states the product need and a seller states availability. ASKODOX connects relevant sides and keeps the deal activity together.'),
      DemoModule.jobs => const ModuleFaq('How do jobs work?', 'Job givers post requirements and job seekers provide their skills or needs. ASKODOX matches relevant profiles.'),
      DemoModule.services => const ModuleFaq('How do services work?', 'A customer states the service needed and ASKODOX matches suitable service providers.'),
      DemoModule.rides => const ModuleFaq('How do rides work?', 'Passengers state route and timing needs; relevant drivers or rides are matched for the journey.'),
      DemoModule.parcel => const ModuleFaq('How does parcel delivery work?', 'The sender provides pickup/drop requirements and ASKODOX matches an appropriate delivery provider.'),
      DemoModule.appointments => const ModuleFaq('How do appointments work?', 'The user requests a suitable slot and the provider confirms an available appointment.'),
      DemoModule.catering => const ModuleFaq('How does catering RFQ work?', 'The customer gives function requirements and ASKODOX matches relevant caterers so quotations can be compared.'),
      DemoModule.localDiscovery => const ModuleFaq('How does local discovery work?', 'ASKODOX uses the user need and location context to surface relevant nearby options.'),
    },
  ];

  static const unresolvedMessage = 'Still need help? Send the unresolved question to ASKODOX Support so it can be reviewed instead of repeating the same answer.';
}
