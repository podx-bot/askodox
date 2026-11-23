---
paths:
  - "lib/features/pos/domain/shop_page_names.dart"
  - "lib/features/pos/presentation/pos_shop_tool_screen.dart"
  - "lib/features/pos/presentation/pos_home_screen.dart"
  - "lib/features/money_home/money_home_pages.dart"
  - "lib/features/business/presentation/biz_hub.dart"
  - "lib/features/guide/screen_help.dart"
  - "lib/shared/widgets/chat_pins.dart"
  - "backend/app/services/chat_actions.py"
  - "backend/app/services/pos_hub.py"
---

# One page, one name, one pin

Owner 2026-11-24: "New bill" and "Counter bill" were two pins above the chat that opened the SAME counter page.

- A shop page's name lives in ONE place: `askodoxShopPageNames` (`lib/features/pos/domain/shop_page_names.dart`).
  The Seller Money pages (`askodoxSellerPages` looks it up), the shop dashboard tiles (`_tile`), `/my-shop/<tool>`
  (`askodoxShopTools` is built from it), the screen guide titles, the chat buttons (`chat_actions.CATALOG`) and the ASK
  bar (`pos_hub.PAGES`) all carry that name. A new shop page = one line there; never a second name elsewhere.
- Tests that fail on a second name: `test/features/pos/one_page_one_name_test.dart`,
  `backend/tests/test_chat_actions.py` (reads the Dart file).
- Pins: one pin per PAGE (`AskodoxChatPin.samePageAs`, `askodoxSamePage`: `/my-shop/sale` = `/pos/<id>/sale`); pinning a
  page already pinned from another button offers move / remove only; saved pins join on start (`askodoxOnePinPerPage`)
  and show the page's name.
- An ACTION that lands on a shared page ("Add staff", "Table calls") keeps its own words; only names OF a page follow
  the list.
