import 'package:go_router/go_router.dart';

import '../../steps/presentation/checkin_steps_screen.dart';
import '../../steps/presentation/dues_steps_screen.dart';
import 'biz_hub.dart';
import 'biz_menu.dart';
import 'biz_money.dart';
import 'biz_reports.dart';
import 'biz_staff.dart';
import 'biz_work.dart';

/// The business hub's pages (owner 2026-11-18): `/biz/:id` is the hub, `/biz/:id/:group` a group page.
final askodoxBizRoutes = <GoRoute>[
  GoRoute(path: '/biz/:id', builder: (c, s) => AskodoxBizHubScreen(businessId: s.pathParameters['id']!)),
  GoRoute(path: '/biz/:id/menu', builder: (c, s) => AskodoxBizMenuScreen(businessId: s.pathParameters['id']!)),
  GoRoute(path: '/biz/:id/menu/sort', builder: (c, s) => AskodoxBizMenuSortScreen(businessId: s.pathParameters['id']!)),
  GoRoute(
      path: '/biz/:id/menu/section/:name',
      builder: (c, s) =>
          AskodoxBizSectionScreen(businessId: s.pathParameters['id']!, section: s.pathParameters['name']!)),
  GoRoute(
      path: '/biz/:id/menu/item/:pid',
      builder: (c, s) => AskodoxBizItemScreen(businessId: s.pathParameters['id']!, productId: s.pathParameters['pid']!)),
  GoRoute(path: '/biz/:id/money/cashbook', builder: (c, s) => AskodoxBizCashbookScreen(businessId: s.pathParameters['id']!)),
  // Owner 2026-11-22: dues and check-in are 3-step pages; the old pages stay at ?full=1 (their "⋮").
  GoRoute(
      path: '/biz/:id/money/dues',
      builder: (c, s) => s.uri.queryParameters['full'] == '1'
          ? AskodoxBizDuesScreen(businessId: s.pathParameters['id']!)
          : AskodoxDuesStepsScreen(businessId: s.pathParameters['id']!)),
  GoRoute(path: '/biz/:id/money/history', builder: (c, s) => AskodoxBizBillHistoryScreen(businessId: s.pathParameters['id']!)),
  GoRoute(path: '/biz/:id/reports', builder: (c, s) => AskodoxBizReportsScreen(businessId: s.pathParameters['id']!)),
  GoRoute(
      path: '/biz/:id/reports/day',
      builder: (c, s) =>
          AskodoxBizReportsScreen(businessId: s.pathParameters['id']!, date: s.uri.queryParameters['date'] ?? '')),
  GoRoute(
      path: '/biz/:id/reports/settings', builder: (c, s) => AskodoxBizReportSettingsScreen(businessId: s.pathParameters['id']!)),
  GoRoute(path: '/biz/:id/staff', builder: (c, s) => AskodoxBizStaffScreen(businessId: s.pathParameters['id']!)),
  GoRoute(path: '/biz/:id/staff/today', builder: (c, s) => AskodoxBizAttTodayScreen(businessId: s.pathParameters['id']!)),
  GoRoute(
      path: '/biz/:id/staff/checkin',
      builder: (c, s) => s.uri.queryParameters['full'] == '1'
          ? AskodoxBizCheckInScreen(businessId: s.pathParameters['id']!)
          : AskodoxCheckInStepsScreen(businessId: s.pathParameters['id']!)),
  GoRoute(path: '/biz/:id/staff/kiosk', builder: (c, s) => AskodoxBizKioskScreen(businessId: s.pathParameters['id']!)),
  GoRoute(
      path: '/biz/:id/staff/person/:ref',
      builder: (c, s) => AskodoxBizStaffPersonScreen(businessId: s.pathParameters['id']!, staffRef: s.pathParameters['ref']!)),
  GoRoute(path: '/biz/:id/staff/salary', builder: (c, s) => AskodoxBizSalaryScreen(businessId: s.pathParameters['id']!)),
  GoRoute(path: '/biz/:id/staff/tasks', builder: (c, s) => AskodoxBizTasksScreen(businessId: s.pathParameters['id']!)),
  GoRoute(path: '/biz/:id/staff/setup', builder: (c, s) => AskodoxBizAttSetupScreen(businessId: s.pathParameters['id']!)),
  // Business Kit ways 3-5 (owner 2026-11-24): before the group catch-all below.
  GoRoute(path: '/biz/:id/bookings', builder: (c, s) => AskodoxBizBookingsScreen(businessId: s.pathParameters['id']!)),
  GoRoute(path: '/biz/:id/jobs', builder: (c, s) => AskodoxBizJobsScreen(businessId: s.pathParameters['id']!)),
  GoRoute(path: '/biz/:id/monthly', builder: (c, s) => AskodoxBizMonthlyScreen(businessId: s.pathParameters['id']!)),
  GoRoute(
      path: '/biz/:id/:group',
      builder: (c, s) => AskodoxBizGroupScreen(businessId: s.pathParameters['id']!, groupId: s.pathParameters['group']!)),
];
