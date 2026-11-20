import 'package:go_router/go_router.dart';

import 'pos_advance_screens.dart';
import 'pos_agent_screens.dart';
import 'pos_bills_screens.dart';
import 'pos_catalogue_screens.dart';
import 'pos_collect_screens.dart';
import 'pos_crm_screens.dart';
import 'pos_frontdesk_screens.dart';
import 'pos_desk_manage_screens.dart';
import 'pos_dues_screen.dart';
import 'pos_frontdesk_staff_screens.dart';
import 'pos_home_screen.dart';
import 'my_payment_alerts_screen.dart';
import 'money_screens.dart';
import 'my_phone_payments_screen.dart';
import 'payments_hub_screen.dart';
import 'pos_payment_alerts_screen.dart';
import 'pos_purchase_screens.dart';
import 'pos_records_screens.dart';
import 'pos_restaurant_screens.dart';
import 'pos_sale_screen.dart';
import 'pos_selfshop_screens.dart';
import 'pos_shop_tool_screen.dart';

/// Universal POS routes (entry: My Business -> Shop billing).
/// Shown in Phase 1 too: a person's own UPI QR / bank, so people pay them directly.
final askodoxPaymentMethodRoutes = <GoRoute>[
  // The Payments tab (redesign 2026-11-13): today, the week, latest payments, QR / alerts / accounts.
  GoRoute(path: '/me/payments', builder: (context, state) => const AskodoxPaymentsHubScreen()),
  // Bills (owner 2026-11-16): the customer's own bills from shops, and a shop's bill history.
  GoRoute(path: '/me/bills', builder: (context, state) => const AskodoxMyBillsScreen()),
  GoRoute(path: '/money', builder: (context, state) => const AskodoxMoneyScreen()),
  GoRoute(path: '/bills/:id', builder: (context, state) => AskodoxBillHistoryScreen(businessId: state.pathParameters['id']!)),
  GoRoute(path: '/me/payments/phone', builder: (context, state) => const AskodoxMyPhonePaymentsScreen()),
  GoRoute(path: '/me/payment-methods', builder: (context, state) => const AskodoxMyPaymentMethodsScreen()),
  // Payment sound alerts without the POS (owner 2026-11-10): the shop, its staff and who hears the sound.
  GoRoute(path: '/me/payment-alerts', builder: (context, state) => const AskodoxMyPaymentAlertsScreen()),
  GoRoute(
      path: '/me/payment-alerts/:id',
      builder: (context, state) => AskodoxPosPaymentAlertsScreen(businessId: state.pathParameters['id']!)),
  // Each part of the alert menu is its own page: status | who | staff | voice | bank | history.
  GoRoute(
      path: '/me/payment-alerts/:id/:view',
      builder: (context, state) =>
          AskodoxPosPaymentAlertsScreen(businessId: state.pathParameters['id']!, view: state.pathParameters['view']!)),
];

/// Front desk (owner 2026-11-15: receptionist / waiter flow brings users, so it is in Phase 1 too): the customer's
/// QR menu + receptionist + live order, and the shop's one orders desk / menu / QR.
final askodoxFrontDeskRoutes = <GoRoute>[
  GoRoute(
      path: '/order-desk',
      builder: (context, state) => AskodoxOrderDeskScreen(
          code: state.uri.queryParameters['code'] ?? '',
          kind: state.uri.queryParameters['kind'] ?? '',
          cart: state.uri.queryParameters['cart'] ?? '')),
  GoRoute(path: '/order-desk/enter', builder: (context, state) => const AskodoxOrderCodeScreen()),
  GoRoute(path: '/order-desk/track/:oid', builder: (context, state) => AskodoxOrderTrackScreen(orderId: state.pathParameters['oid']!)),
  // Owner 2026-11-18: order notifications sent before the fix point here ("Page not found").
  GoRoute(path: '/order/track/:oid', redirect: (context, state) => '/order-desk/track/${state.pathParameters['oid']}'),
  GoRoute(path: '/pos/:id/orders', redirect: (context, state) => '/desk/${state.pathParameters['id']}'),
  GoRoute(path: '/desk/:id', builder: (context, state) => AskodoxDeskOrdersScreen(businessId: state.pathParameters['id']!)),
  GoRoute(path: '/desk/:id/menu', builder: (context, state) => AskodoxDeskMenuScreen(businessId: state.pathParameters['id']!)),
  GoRoute(path: '/desk/:id/settings', builder: (context, state) => AskodoxDeskSettingsScreen(businessId: state.pathParameters['id']!)),
  GoRoute(path: '/desk/:id/sales', builder: (context, state) => AskodoxDeskSalesScreen(businessId: state.pathParameters['id']!)),
  GoRoute(path: '/desk/:id/qr', builder: (context, state) => AskodoxDeskQrScreen(businessId: state.pathParameters['id']!)),
];

final askodoxPosRoutes = <GoRoute>[
  // /my-shop/<tool>: the shop is found for the person (owner 2026-11-19: any shop tool from the chat or a pin).
  GoRoute(path: '/my-shop/dues', builder: (context, state) => AskodoxShopToolScreen(tool: 'dues', query: state.uri.query)),
  GoRoute(path: '/my-shop/sale', builder: (context, state) => AskodoxShopToolScreen(tool: 'sale', query: state.uri.query)),
  GoRoute(path: '/my-shop/payment-alerts', builder: (context, state) => AskodoxShopToolScreen(tool: 'payment-alerts', query: state.uri.query)),
  GoRoute(path: '/my-shop/collect', builder: (context, state) => AskodoxShopToolScreen(tool: 'collect', query: state.uri.query)),
  GoRoute(path: '/my-shop/orders', builder: (context, state) => AskodoxShopToolScreen(tool: 'orders', query: state.uri.query)),
  GoRoute(path: '/my-shop/tables', builder: (context, state) => AskodoxShopToolScreen(tool: 'tables', query: state.uri.query)),
  GoRoute(path: '/my-shop/kitchen', builder: (context, state) => AskodoxShopToolScreen(tool: 'kitchen', query: state.uri.query)),
  GoRoute(path: '/my-shop/items', builder: (context, state) => AskodoxShopToolScreen(tool: 'items', query: state.uri.query)),
  GoRoute(path: '/my-shop/suppliers', builder: (context, state) => AskodoxShopToolScreen(tool: 'suppliers', query: state.uri.query)),
  GoRoute(path: '/my-shop/expiry', builder: (context, state) => AskodoxShopToolScreen(tool: 'expiry', query: state.uri.query)),
  GoRoute(path: '/my-shop/customers', builder: (context, state) => AskodoxShopToolScreen(tool: 'customers', query: state.uri.query)),
  GoRoute(path: '/my-shop/agents', builder: (context, state) => AskodoxShopToolScreen(tool: 'agents', query: state.uri.query)),
  GoRoute(path: '/my-shop/bills', builder: (context, state) => AskodoxShopToolScreen(tool: 'bills', query: state.uri.query)),
  GoRoute(path: '/my-shop/day', builder: (context, state) => AskodoxShopToolScreen(tool: 'day', query: state.uri.query)),
  GoRoute(path: '/my-shop/gst', builder: (context, state) => AskodoxShopToolScreen(tool: 'gst', query: state.uri.query)),
  GoRoute(path: '/my-shop/staff', builder: (context, state) => AskodoxShopToolScreen(tool: 'staff', query: state.uri.query)),
  GoRoute(path: '/my-shop/printer', builder: (context, state) => AskodoxShopToolScreen(tool: 'printer', query: state.uri.query)),
  GoRoute(path: '/my-shop/advance', builder: (context, state) => AskodoxShopToolScreen(tool: 'advance', query: state.uri.query)),
  GoRoute(path: '/my-shop/selfshop', builder: (context, state) => AskodoxShopToolScreen(tool: 'selfshop', query: state.uri.query)),
  GoRoute(path: '/pos', builder: (context, state) => const AskodoxPosHomeScreen()),
  GoRoute(path: '/pos/:id', builder: (context, state) => AskodoxPosDashboardScreen(businessId: state.pathParameters['id']!)),
  GoRoute(path: '/pos/:id/collect', builder: (context, state) => AskodoxPosCollectScreen(businessId: state.pathParameters['id']!)),
  // The person's OWN ways to be paid (any app's / bank's UPI QR, bank account).
  GoRoute(
      path: '/pos/:id/payment-alerts',
      builder: (context, state) => AskodoxPosPaymentAlertsScreen(businessId: state.pathParameters['id']!)),
  // Role-based AI agents (shop dashboard tile) + the personal buyer agent (Profile -> Personal Finance).
  GoRoute(path: '/pos/:id/agents', builder: (context, state) => AskodoxPosAgentsScreen(businessId: state.pathParameters['id']!)),
  GoRoute(
      path: '/pos/:id/agents/:agent',
      builder: (context, state) =>
          AskodoxPosAgentScreen(businessId: state.pathParameters['id']!, agent: state.pathParameters['agent']!)),
  GoRoute(path: '/me/agent', builder: (context, state) => const AskodoxBuyerAgentScreen()),
  // Business CRM (My Business -> Business CRM; also a tile on the shop dashboard).
  GoRoute(path: '/crm', builder: (context, state) => const AskodoxCrmEntryScreen()),
  GoRoute(
      path: '/pos/:id/crm',
      builder: (context, state) => AskodoxPosCrmScreen(
          businessId: state.pathParameters['id']!, initialTab: state.uri.queryParameters['tab'] ?? '')),
  GoRoute(
      path: '/pos/:id/crm/leads',
      builder: (context, state) => AskodoxPosCrmLeadsScreen(
          businessId: state.pathParameters['id']!, stage: state.uri.queryParameters['stage'] ?? '')),
  GoRoute(
      path: '/pos/:id/crm/lead/:lid',
      builder: (context, state) =>
          AskodoxPosCrmLeadScreen(businessId: state.pathParameters['id']!, leadId: state.pathParameters['lid']!)),
  GoRoute(
      path: '/pos/:id/crm/complaint/:cid',
      builder: (context, state) =>
          AskodoxPosCrmComplaintScreen(businessId: state.pathParameters['id']!, complaintId: state.pathParameters['cid']!)),
  GoRoute(
      path: '/pos/:id/crm/customer/:cid',
      builder: (context, state) =>
          AskodoxPosCrmCustomerScreen(businessId: state.pathParameters['id']!, customerId: state.pathParameters['cid']!)),
  GoRoute(
      path: '/pos/:id/sale',
      builder: (context, state) => AskodoxPosSaleScreen(
          businessId: state.pathParameters['id']!,
          leadId: state.uri.queryParameters['lead'],
          customerId: state.uri.queryParameters['customer'],
          say: state.uri.queryParameters['say'])),
  GoRoute(path: '/pos/:id/items', builder: (context, state) => AskodoxPosItemsScreen(businessId: state.pathParameters['id']!)),
  GoRoute(
      path: '/pos/:id/catalogue', builder: (context, state) => AskodoxPosCatalogueScreen(businessId: state.pathParameters['id']!)),
  GoRoute(
      path: '/pos/:id/item/:pid',
      builder: (context, state) =>
          AskodoxPosItemDetailsScreen(businessId: state.pathParameters['id']!, productId: state.pathParameters['pid']!)),
  GoRoute(path: '/pos/:id/dues', builder: (context, state) => AskodoxPosDuesScreen(businessId: state.pathParameters['id']!)),
  GoRoute(
      path: '/pos/:id/customers',
      builder: (context, state) => AskodoxPosCustomersScreen(businessId: state.pathParameters['id']!)),
  GoRoute(
      path: '/pos/:id/customers/:cid',
      builder: (context, state) =>
          AskodoxPosCustomerScreen(businessId: state.pathParameters['id']!, customerId: state.pathParameters['cid']!)),
  GoRoute(
      path: '/pos/:id/invoices', builder: (context, state) => AskodoxPosInvoicesScreen(businessId: state.pathParameters['id']!)),
  GoRoute(
      path: '/pos/:id/invoice/:iid',
      builder: (context, state) =>
          AskodoxPosInvoiceScreen(
              businessId: state.pathParameters['id']!,
              invoiceId: state.pathParameters['iid']!,
              fresh: state.uri.queryParameters['fresh'] == '1')),
  GoRoute(path: '/pos/:id/day', builder: (context, state) => AskodoxPosDayScreen(businessId: state.pathParameters['id']!)),
  GoRoute(path: '/pos/:id/gst', builder: (context, state) => AskodoxPosGstScreen(businessId: state.pathParameters['id']!)),
  GoRoute(path: '/pos/:id/staff', builder: (context, state) => AskodoxPosStaffScreen(businessId: state.pathParameters['id']!)),
  GoRoute(path: '/pos/:id/tables', builder: (context, state) => AskodoxPosTablesScreen(businessId: state.pathParameters['id']!)),
  GoRoute(
      path: '/pos/:id/order/:oid',
      builder: (context, state) =>
          AskodoxPosOrderScreen(businessId: state.pathParameters['id']!, orderId: state.pathParameters['oid']!)),
  GoRoute(path: '/pos/:id/kitchen', builder: (context, state) => AskodoxPosKitchenScreen(businessId: state.pathParameters['id']!)),
  GoRoute(path: '/pos/:id/suppliers', builder: (context, state) => AskodoxPosSuppliersScreen(businessId: state.pathParameters['id']!)),
  GoRoute(
      path: '/pos/:id/suppliers/:sid',
      builder: (context, state) =>
          AskodoxPosSupplierScreen(businessId: state.pathParameters['id']!, supplierId: state.pathParameters['sid']!)),
  GoRoute(path: '/pos/:id/purchase/new', builder: (context, state) => AskodoxPosPurchaseScreen(businessId: state.pathParameters['id']!)),
  GoRoute(
      path: '/pos/:id/purchase-orders', builder: (context, state) => AskodoxPosPurchaseOrdersScreen(businessId: state.pathParameters['id']!)),
  GoRoute(path: '/pos/:id/stock-report', builder: (context, state) => AskodoxPosStockReportScreen(businessId: state.pathParameters['id']!)),
  GoRoute(path: '/pos/:id/printer', builder: (context, state) => const AskodoxPosPrinterScreen()),
  GoRoute(
      path: '/pos/:id/advance', builder: (context, state) => AskodoxPosAdvanceSettingsScreen(businessId: state.pathParameters['id']!)),
  GoRoute(
      path: '/pos/:id/selfshop', builder: (context, state) => AskodoxPosSelfShopScreen(businessId: state.pathParameters['id']!)),
  GoRoute(
      path: '/pos/:id/selfshop/:sid',
      builder: (context, state) =>
          AskodoxPosSelfShopCheckScreen(businessId: state.pathParameters['id']!, sessionId: state.pathParameters['sid']!)),
  // Customer side: scan & shop in a store that turned self-shopping on.
  GoRoute(path: '/shop-scan', builder: (context, state) => const AskodoxSelfShopScreen()),
  // Customer side: approve / reject what shops recorded against your number.
  GoRoute(path: '/me/shop-advances', builder: (context, state) => const AskodoxMyShopAdvancesScreen()),
];
