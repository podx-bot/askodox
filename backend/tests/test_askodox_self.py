"""ASKODOX knows its own name and what it does (owner 2026-11-20: 'class codex' was answered as OpenAI Codex)."""
from app.services import askodox_self, chat_actions
from app.services.askodox_self import fix_spoken_name, is_about_askodox


def test_sound_alikes_become_askodox_and_other_words_stay():
    assert fix_spoken_name("క్లాస్ కోడెక్స్ ఏం చేస్తుంది దీని వల్ల నాకు ఈజీ ఏంటి?").startswith("ASKODOX ఏం చేస్తుంది")
    assert fix_spoken_name("కోడెక్స్ కాదు ఆక్సోడెక్స్ అని అడిగాను") == "కోడెక్స్ కాదు ASKODOX అని అడిగాను"
    for said in ("what is askodox", "Axodex lo bill", "aksodex", "ask o dox app", "ascodox!", "मुझे आस्कोडॉक्स चाहिए",
                 "ఆస్కోడాక్స్ లో"):
        assert "ASKODOX" in fix_spoken_name(said), said
    for said in ("OpenAI codex", "Claude Codex", "fast codex", "go to the doc", "I want a desk lamp", "10 kg dal",
                 "asked docs"):
        assert fix_spoken_name(said) == said, said


def test_questions_about_askodox_use_its_own_facts():
    assert is_about_askodox(fix_spoken_name("ఆక్సోడెక్స్ ఏం చేస్తుంది"))
    assert not is_about_askodox("best phone under 20000")
    block = askodox_self.prompt_block()
    assert "you ARE ASKODOX" in block and "never from the web" in block
    for _key, _route, en, _te, _about in chat_actions.CATALOG:
        assert en in block, f"every real screen is in the facts: {en}"


def test_auto_open_prompt_never_asks_for_a_tap():
    opened = chat_actions.prompt_block(False, auto_open=True)
    assert "OPENS that screen by itself" in opened and "Never tell the user to tap" in opened
    assert "the user taps a button" in chat_actions.prompt_block(False)
