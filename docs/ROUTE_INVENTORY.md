# Route inventory

Routes are declared in `lib/config/router/app_router.dart`. `RouteGuard` blocks suspended/deleted sessions, expired sessions, unauthenticated protected pages, seller-role mismatches, and admin permission/role mismatches. Unknown paths use the safe router error screen. The primary buyer shell uses `StatefulShellRoute.indexedStack`, preserving tab state.

| Path(s) | Role / permission | Screen | Typical source |
|---|---|---|---|
| `/`, `/search`, `/watchlist`, `/alerts`, `/profile` | guest except profile requires login | Buyer shell screens | bottom navigation |
| `/auth/login`, `/auth/session-expired`, `/account-status`, `/forbidden` | any | safe status message | route guard |
| `/location`, `/nearby`, `/shop/:id`, `/product/:id` | any | location/shop/product | home and search |
| `/map/shop/:id`, `/nearby/product/:id`, `/alert/:id/map` | any | safe redirect to nearby | deep links |
| `/discover/{barcode,ocr,image,voice}` | any | discovery | search actions |
| `/communications*`, `/notification-preferences` | any | communication and preferences | profile/alerts |
| `/analytics/buyer`, `/analytics/privacy` | any | buyer analytics/privacy | profile |
| `/privacy` | authenticated | privacy center | profile |
| `/beta-feedback` | any beta user | beta feedback | profile |
| `/seller/login`, `/seller/register` | any | seller access | profile |
| `/seller/dashboard`, `/seller/products[/add|/request]`, `/seller/requests`, `/seller/insights`, `/seller/profile`, `/seller/location` | seller | seller workspace | seller navigation |
| `/seller/usage`, `/seller/plans[/compare|/review|/payment]`, `/seller/subscription`, `/seller/invoices` | seller | monetization demo | seller workspace |
| `/seller/engagement`, `/seller/analytics*`, `/seller/notifications` | seller | analytics/communications | seller workspace |
| `/admin/login` | any | admin access | direct/admin entry |
| `/admin/subscriptions` | admin family; manage subscriptions | subscription admin | admin navigation |
| `/admin/announcements`, `/admin/analytics`, `/admin/reports` | admin family | admin tools | admin navigation |
| `/admin/:section` (defined enum values) | admin family; audit requires view audit log | admin section | admin shell |
| `/developer`, `/sync-status`, `/conflict/:id`, `/storage-usage` | development only by product policy | diagnostics | developer entry |
| `/performance-monitor`, `/developer/feedback` | debug build only | diagnostics | developer settings |

GoRouter route names are not used, so duplicate names do not apply. Required `:id` values are read only on matching routes. Before production, also remove all discoverability of non-debug diagnostic routes and enforce authorization server-side.
