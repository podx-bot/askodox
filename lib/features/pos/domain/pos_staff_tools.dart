/// Owner 2026-11-20 ("why do my staff see my whole menu?"): per staff member, the owner ticks which shop tools they get.
/// Server: `pos_store.TOOL_PERMISSIONS` / `role_tools` / `start_tools` -- keep these lists equal.
library;

/// id, English, Telugu (the ids are the POS dashboard tile ids).
const askodoxStaffTools = <(String, String, String)>[
  ('payalerts', 'Payment sound', 'పేమెంట్ సౌండ్'),
  ('sale', 'Billing', 'బిల్లింగ్'),
  ('collect', 'Collect by UPI', 'UPI కలెక్ట్'),
  ('desk', 'Orders desk', 'ఆర్డర్స్ డెస్క్'),
  ('tables', 'Tables & KOT', 'టేబుల్స్ & KOT'),
  ('kitchen', 'Kitchen screen', 'వంటగది'),
  ('items', 'Items (menu)', 'ఐటమ్స్ (మెనూ)'),
  ('stock', 'Stock & expiry', 'స్టాక్ & ఎక్స్‌పైరీ'),
  ('suppliers', 'Suppliers & purchases', 'సప్లయర్లు'),
  ('customers', 'Customers & credit', 'కస్టమర్లు & ఖాతా'),
  ('dues', 'Baaki reminders', 'బాకీ గుర్తులు'),
  ('crm', 'Business CRM', 'CRM'),
  ('agents', 'AI agents', 'AI Agents'),
  ('bills', 'Bills', 'బిల్లులు'),
  ('day', 'Day close', 'రోజు ముగింపు'),
  ('gst', 'GST summary', 'GST'),
  ('printer', 'Printer', 'ప్రింటర్'),
  ('selfshop', 'Self-shopping', 'సెల్ఫ్ షాపింగ్'),
  ('price_change', 'Change prices on a bill', 'బిల్లులో ధర మార్చడం'),
];

const _rolePermissions = <String, Set<String>>{
  'manager': {'view', 'sell', 'price_override', 'return', 'cancel', 'products', 'stock', 'customers', 'collect', 'reports',
      'day_close', 'drafts', 'tables', 'kitchen', 'purchases', 'crm'},
  'cashier': {'view', 'sell', 'customers', 'collect', 'drafts', 'tables', 'kitchen', 'crm'},
  'accountant': {'view', 'reports'},
  'waiter': {'view', 'tables'},
  'kitchen': {'view', 'kitchen'},
  'attendant': {'view'},
  'delivery': {'view', 'deliver'},
};

const _toolPermissions = <String, Set<String>>{
  'sale': {'sell', 'drafts', 'customers'},
  'collect': {'collect'},
  'desk': {'tables', 'kitchen', 'sell', 'deliver'},
  'tables': {'tables'},
  'kitchen': {'kitchen'},
  'items': {'products'},
  'stock': {'stock'},
  'suppliers': {'purchases', 'stock'},
  'customers': {'customers', 'collect'},
  'dues': {'sell'},
  'crm': {'crm'},
  'bills': {'return', 'cancel'},
  'day': {'day_close'},
  'gst': {'reports'},
  'selfshop': {'sell'},
  'price_change': {'price_override'},
};

const _viewTools = {'items', 'bills', 'day'};

/// The tools a role can be given (never more than the role allows).
List<String> askodoxStaffToolsFor(String role) {
  final perms = _rolePermissions[role] ?? const <String>{};
  return [
    for (final t in askodoxStaffTools)
      if (!_toolPermissions.containsKey(t.$1) || _toolPermissions[t.$1]!.any(perms.contains) || _viewTools.contains(t.$1)) t.$1,
  ];
}

/// What a NEW staff member starts with: hear payments, plus the one screen their job is.
List<String> askodoxStaffStartTools(String role) => switch (role) {
      'manager' => askodoxStaffToolsFor('manager'),
      'waiter' => const ['payalerts', 'tables'],
      'kitchen' => const ['kitchen'],
      'delivery' => const ['payalerts', 'desk'],
      _ => const ['payalerts'],
    };
