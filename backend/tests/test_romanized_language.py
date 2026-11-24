"""Reply language follows the person from the first reply (owner 2026-11-24: Telugu typed in English letters got an
English answer). Same cases as the app's detector (test/fixtures/romanized_language_cases.json)."""
import json
from pathlib import Path

from app.services import romanized_language as rl

CASES = json.loads((Path(__file__).resolve().parents[2] / "test/fixtures/romanized_language_cases.json").read_text())


def test_shared_cases():
    wrong = [(text, want, rl.detect(text)) for text, want in CASES["cases"] if rl.detect(text) != want]
    assert not wrong, wrong


def test_reply_locale_prefers_what_the_person_writes():
    assert rl.reply_locale("en", "e sms akadi unchi vachidhi") == "te"
    assert rl.reply_locale("", "mujhe AC chahiye") == "hi"
    # No signal keeps the app's conversation language (a short "ok" never flips it).
    assert rl.reply_locale("te", "ok") == "te"
    assert rl.reply_locale("te", "43 inch") == "te"
    assert rl.reply_locale("en", "what is the price of this phone") == "en"


def test_english_sentence_with_one_indian_word_stays_english():
    assert rl.detect("please tell me the price of the new phone that my anna wants to buy") is None


def test_app_tables_are_the_same_as_the_server_tables():
    import re

    dart = (Path(__file__).resolve().parents[2] / "lib/features/home/domain/romanized_language_tables.dart").read_text()

    def words(name):
        block = dart.split(f"const {name}")[1].split(";")[0]
        return {k: set(re.findall(r"'([a-z]+)'", v)) for k, v in re.findall(r"'([a-z]+)': [\[{]([^\]}]*)[\]}]", block)}

    assert words("askodoxRomanizedWords") == {k: set(v) for k, v in rl.WORDS.items()}
    assert words("askodoxRomanizedEndings") == {k: set(v) for k, v in rl.ENDINGS.items()}
    english = set(re.findall(r"'([a-z]+)'", dart.split("const askodoxRomanizedEnglish")[1]))
    assert english == set(rl.ENGLISH)
