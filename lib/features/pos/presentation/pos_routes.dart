import 'package:go_router/go_router.dart';

import 'pos_advance_screens.dart';
import 'pos_catalogue_screens.dart';
import 'pos_home_screen.dart';
import 'pos_payment_alerts_screen.dart';
import 'pos_purchase_screens.dart';
import 'pos_records_screens.dart';
import 'pos_restaurant_screens.dart';
import 'pos_sale_screen.dart';
import 'pos_selfshop_screens.dart';

/// Universal POS routes (entry: My Business -> Shop billing).
final askodoxPosRoutes = <GoRoute>[
  GoRoute(path: '/pos', builder: (context, state) => const AskodoxPosHomeScreen()),
  GoRoute(path: '/pos/:id', builder: (context, state) => AskodoxPosDashboardScreen(businessId: state.pathParameters['id']!)),
  GoRoute(
      path: '/pos/:id/payment-alerts',
      builder: (context, state) => AskodoxPosPaymentAlertsScreen(businessId: state.pathParameters['id']!)),
  GoRoute(path: '/pos/:id/sale', builder: (context, state) => AskodoxPosSaleScreen(businessId: state.pathParameters['id']!)),
  GoRoute(path: '/pos/:id/items', builder: (context, state) => AskodoxPosItemsScreen(businessId: state.pathParameters['id']!)),
  GoRoute(
      path: '/pos/:id/catalogue', builder: (context, state) => AskodoxPosCatalogueScreen(businessId: state.pathParameters['id']!)),
  GoRoute(
      path: '/pos/:id/item/:pid',
      builder: (context, state) =>
          AskodoxPosItemDetailsScreen(businessId: state.pathParameters['id']!, productId: state.pathParameters['pid']!)),
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
          AskodoxPosInvoiceScreen(businessId: state.pathParameters['id']!, invoiceId: state.pathParameters['iid']!)),
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
