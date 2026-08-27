import '../auth/auth_models.dart';

enum DemoModule {
  commerce,
  jobs,
  services,
  rides,
  parcel,
  appointments,
  catering,
  localDiscovery,
}

enum DemoParty { a, b }

class DemoAccount {
  const DemoAccount({
    required this.module,
    required this.party,
    required this.loginId,
    required this.displayName,
    required this.role,
    required this.location,
    required this.sampleIntent,
  });

  final DemoModule module;
  final DemoParty party;
  final String loginId;
  final String displayName;
  final UserRole role;
  final String location;
  final String sampleIntent;

  String get id => 'demo-${module.name}-${party.name}';
  AuthUser get user => AuthUser(id: id, role: role, displayName: displayName);
}

class DemoAccounts {
  const DemoAccounts._();

  static const demoPassword = 'ASKODOX-DEMO';

  static const all = <DemoAccount>[
    DemoAccount(module: DemoModule.commerce, party: DemoParty.a, loginId: 'demo.commerce.seller', displayName: 'Demo Seller', role: UserRole.seller, location: 'Vijayawada', sampleIntent: 'Sell fresh chicken at local market price'),
    DemoAccount(module: DemoModule.commerce, party: DemoParty.b, loginId: 'demo.commerce.buyer', displayName: 'Demo Buyer', role: UserRole.buyer, location: 'Vijayawada', sampleIntent: 'Buy chicken nearby within budget'),
    DemoAccount(module: DemoModule.jobs, party: DemoParty.a, loginId: 'demo.jobs.giver', displayName: 'Demo Employer', role: UserRole.seller, location: 'Vijayawada', sampleIntent: 'Hire a computer operator'),
    DemoAccount(module: DemoModule.jobs, party: DemoParty.b, loginId: 'demo.jobs.seeker', displayName: 'Demo Job Seeker', role: UserRole.buyer, location: 'Vijayawada', sampleIntent: 'Find a computer operator job'),
    DemoAccount(module: DemoModule.services, party: DemoParty.a, loginId: 'demo.services.provider', displayName: 'Demo Service Provider', role: UserRole.seller, location: 'Vijayawada', sampleIntent: 'Provide AC repair service'),
    DemoAccount(module: DemoModule.services, party: DemoParty.b, loginId: 'demo.services.customer', displayName: 'Demo Service Customer', role: UserRole.buyer, location: 'Vijayawada', sampleIntent: 'Need AC repair today'),
    DemoAccount(module: DemoModule.rides, party: DemoParty.a, loginId: 'demo.rides.driver', displayName: 'Demo Driver', role: UserRole.seller, location: 'Vijayawada', sampleIntent: 'Post Vijayawada to Bhimavaram ride'),
    DemoAccount(module: DemoModule.rides, party: DemoParty.b, loginId: 'demo.rides.passenger', displayName: 'Demo Passenger', role: UserRole.buyer, location: 'Vijayawada', sampleIntent: 'Book one seat to Bhimavaram'),
    DemoAccount(module: DemoModule.parcel, party: DemoParty.a, loginId: 'demo.parcel.rider', displayName: 'Demo Delivery Rider', role: UserRole.seller, location: 'Vijayawada', sampleIntent: 'Accept nearby parcel delivery'),
    DemoAccount(module: DemoModule.parcel, party: DemoParty.b, loginId: 'demo.parcel.sender', displayName: 'Demo Parcel Sender', role: UserRole.buyer, location: 'Vijayawada', sampleIntent: 'Send a parcel within the city'),
    DemoAccount(module: DemoModule.appointments, party: DemoParty.a, loginId: 'demo.appointments.provider', displayName: 'Demo Appointment Provider', role: UserRole.seller, location: 'Vijayawada', sampleIntent: 'Offer bookable appointment slots'),
    DemoAccount(module: DemoModule.appointments, party: DemoParty.b, loginId: 'demo.appointments.customer', displayName: 'Demo Appointment Customer', role: UserRole.buyer, location: 'Vijayawada', sampleIntent: 'Book an appointment tomorrow'),
    DemoAccount(module: DemoModule.catering, party: DemoParty.a, loginId: 'demo.catering.caterer', displayName: 'Demo Caterer', role: UserRole.seller, location: 'Vijayawada', sampleIntent: 'Quote for 100-person function'),
    DemoAccount(module: DemoModule.catering, party: DemoParty.b, loginId: 'demo.catering.customer', displayName: 'Demo Catering Customer', role: UserRole.buyer, location: 'Vijayawada', sampleIntent: 'Need catering for 100 guests'),
    DemoAccount(module: DemoModule.localDiscovery, party: DemoParty.a, loginId: 'demo.local.business', displayName: 'Demo Local Business', role: UserRole.seller, location: 'Vijayawada', sampleIntent: 'Show local catalog and availability'),
    DemoAccount(module: DemoModule.localDiscovery, party: DemoParty.b, loginId: 'demo.local.seeker', displayName: 'Demo Local Seeker', role: UserRole.buyer, location: 'Vijayawada', sampleIntent: 'Find a nearby local seller'),
  ];

  static DemoAccount? byLoginId(String loginId) {
    for (final account in all) {
      if (account.loginId.toLowerCase() == loginId.trim().toLowerCase()) return account;
    }
    return null;
  }

  static List<DemoAccount> forModule(DemoModule module) =>
      all.where((account) => account.module == module).toList(growable: false);
}
