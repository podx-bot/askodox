---
paths:
  - "lib/features/pos/domain/pos_commands.dart"
  - "lib/features/pos/domain/pos_name_sound.dart"
  - "lib/features/pos/presentation/pos_order_review.dart"
  - "lib/features/pos/presentation/pos_sale_screen.dart"
  - "lib/features/steps/presentation/bill_steps_screen.dart"
  - "backend/app/services/name_sound.py"
  - "backend/app/services/pos_menu_voice.py"
---

# Spoken / typed bill orders — read before touching these files

Owner 2026-11-24: "రెండు చికెన్ బిర్యానీ ఒక ఫ్రై పీస్ బిర్యానీ ఒక ఫ్యామిలీ ప్యాక్ చికెన్ దమ్ బిర్యానీ పార్సెల్" showed
"Item not found" three times — the menu names were in English, the order in Telugu. ASKODOX is for every shop and every
language: never assume the menu and the speech use the same script.

- **Any script matches any script.** `askodoxMatchItems` = exact -> every word in the name -> by SOUND
  (`pos_name_sound.dart`: Indic letters -> Latin -> consonant skeleton) -> name inside the phrase. Never remove the sound
  step; never add per-dish word lists (no "biryani" = "బిర్యానీ" tables).
- **Two twins, one rule.** `lib/features/pos/domain/pos_name_sound.dart` and `backend/app/services/name_sound.py` must
  give the same sound for the same word (soft c = s, Indic digits, nukta). Change both or neither.
- **Order words are not names**: parcel / పార్సెల్ / takeaway / please / ఇవ్వండి live in `_fillerWords`; a spoken full
  stop is dropped (`_plain`), a decimal point is kept.
- **A unit word inside a name** ("Family Pack ...", "Fry Piece Biryani") still counts for the match and then is not the
  unit. Counted units (pcs / plate / pack / box) are one count. **A number inside a name** ("Chicken 65") is not the
  quantity.
- **Half a name is offered, never added**: `askodoxSuggestItems` -> `candidates` (needsChoice, even with one). The
  cashier's own pick (`pick:`) always wins and keeps the spoken quantity.
- **Every owner-reported phrase becomes a case in `test/features/pos/spoken_order_any_script_test.dart` first**, then the
  fix. Keep the old cases in `pos_test.dart` / `pos_smart_test.dart` / `zero_setup_round_test.dart` passing.
