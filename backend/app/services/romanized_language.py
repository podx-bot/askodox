"""Which Indian language a message is written in -- also when it is typed in English letters.

Owner 2026-11-24: "e sms akadi unchi vachidhi" (Telugu in English letters) got an English answer. The reply
language must follow the person from the FIRST reply: native script first, then romanized Indian languages
(Telugu, Hindi, Tamil, Kannada, Malayalam, Bengali, Marathi, Gujarati, Punjabi, Odia), else the app's locale.

Universal table, no per-category rules. The SAME table and the same scoring live in the app
(`lib/features/home/domain/conversation_language.dart`); both suites read
`test/fixtures/romanized_language_cases.json`, so the two can never drift apart.

Scoring: a word in a language's table = 2 points, a word ending in one of its typical endings = 1 point
(only for words of 4+ letters that are not common English words). A language wins with 3+ points (one word
alone is not enough: 'kya', 'ledu') and more
than any other language; a message that is clearly an English sentence (several English function words and
no stronger Indian signal) stays English.
"""
from __future__ import annotations

import re

# Unicode block -> language (shared scripts map to their most common language).
SCRIPTS: tuple[tuple[int, int, str], ...] = (
    (0x0C00, 0x0C7F, "te"), (0x0900, 0x097F, "hi"), (0x0980, 0x09FF, "bn"), (0x0A00, 0x0A7F, "pa"),
    (0x0A80, 0x0AFF, "gu"), (0x0B00, 0x0B7F, "or"), (0x0B80, 0x0BFF, "ta"), (0x0C80, 0x0CFF, "kn"),
    (0x0D00, 0x0D7F, "ml"), (0x0600, 0x06FF, "ur"),
)

WORDS: dict[str, frozenset[str]] = {
    "te": frozenset("""
        naku naaku nenu neenu meeru miru meeku miku manaki memu vaadu vadu aame ame vallu
        kavali kaavali kavalante kaavalante undi undhi unnadi unnayi unnaya unnara ledu ledhu levu leru
        cheppu cheppandi cheppara cheyyandi cheyandi cheyali cheyyali chesi chesanu chesa chesindi chesaru
        ekkada ekkadi akkada akkadi akadi ikkada ikkadi ekkadiki enti emiti emi enduku endhuku eppudu ela elaa
        evaru evvaru entha enta enni ivvandi ichadu ichindi ivvali chupinchu chupinchandi choodu chudandi chusa
        dorukutundi dorukuthundi vachindi vachindhi vachidhi vachchindi vastundi vasthundi raledu ochindi
        nunchi nundi unchi gurinchi motham mottam kosam kooda kuda inka inkaa ippudu appudu repu ninna
        manchi baga bagundi bagunda ayindi aipoyindi avutundi avuthundi ayyindi pampandi pampu pampindi
        tisuko teesuko tiskondi kottandi kottu ammu amma nanna anna akka babu garu andi sare saresare
        nijam nijama nijamena nijamga idhi idi adhi adi daniki dani deeniki ee aa oka okka rendu moodu dabbulu dabbu paisalu kharchu
        cheppandiii telusa telusu teliyadu theliyadu artham ardham kaledu emaina emanna edaina ekkuva takkuva
        pani panulu chesthunnanu chestunna vellali vellandi randi raa po poyindi poindi kattali kattanu
        """.split()),
    "hi": frozenset("""
        mujhe mujhko mera meri mere hum humko hame hamein tum tumhe aap aapko apna apni unka uska
        chahiye chahie chaiye kahan kaha kya kyun kyon kaise kaisa kitna kitne kitni kab kaun kisne
        nahi nahin hai hain tha thi hoga hogi raha rahi rahe karo karna karen kariye kiya kiye
        batao bataiye bataye dikhao dikhaiye milega milegi mila mili wala wali wale sasta sasti accha
        acha achha bhai bhaiya yaar paisa paise rupaye aaya aayi gaya gayi bheja bhejo bhejna dena lena
        abhi kal aaj yahan wahan iska iski ke liye liye kuch sab bahut thoda jyada zyada samajh pata
        """.split()),
    "ta": frozenset("""
        enakku enaku venum venam vendum enga engae enna ennada irukku iruku illa illai sollunga sollu
        evvalavu evlo kidaikkum kidaikuma vanthathu vandhuchu vanthuchu panna pannunga podu paaru
        unga ungalukku naan nan neenga avan aval ippo appo inniku naalaikku romba konjam theriyum
        theriyala ethu edhu yaaru eppadi ethukku
        """.split()),
    "kn": frozenset("""
        nanage nange beku bekagide elli yenu enu ide idhe illa heli helu eshtu sigutte sigtade
        banthu bantu madi maadi kodi nodi naanu neevu avaru yaake hege yavaga gottilla gotthu tumba
        swalpa hogi baa
        """.split()),
    "ml": frozenset("""
        enikku enik venam venda evide entha enthu undo undu illa parayu ethra kittum vannu cheyyu
        njan ningal avan aval innu nale valare kurachu ariyilla manassilayilla engane eppol aaranu
        """.split()),
    "bn": frozenset("""
        amar amake lagbe kothay kothai ache achhe nei bolo bolun koto pabo kno keno kemon tumi apni
        ami eta oita kibhabe kobe kar dao den hobe hoyeche korbo korte taka
        """.split()),
    "mr": frozenset("""
        mala majha majhi majhe pahije kuthe kuthun aahe ahe nahi kay kasa kashi kiti sang sanga
        mhanje kara karaycha dya ghya aamhi tumhi tyala ithe tithe zala jhala aala
        """.split()),
    "gu": frozenset("""
        mane maru mari mara joie joiye kyan che chhe nathi shu kem ketlu ketla aapo batavo
        tame ame tamne amne thayu aavyu gayu kevi rite
        """.split()),
    "pa": frozenset("""
        mainu menu mera meri chahida chahidi kithe ki kiddan kiwen kinna kinne tusi tuhanu asi
        sanu dasso dasao karo hega hegi nahi ithe othe
        """.split()),
    "or": frozenset("""
        mote mora darkar kouthi kana kahinki kemiti ketebele kete achhi nahin kahantu tame ame
        mu ehi sehi heba hela
        """.split()),
}

# Typical word endings (only for 4+ letter words that are not common English words).
ENDINGS: dict[str, tuple[str, ...]] = {
    "te": ("indi", "indhi", "andi", "andhi", "aledu", "ledu", "unnadi", "unnanu", "aali",
           "inchu", "inchandi", "tundi", "thundi", "chhindi", "chindi", "nunchi"),
    "hi": ("iye", "enge", "egi", "ega", "kar", "wala", "wali"),
    "ta": ("unga", "kkum", "kuma", "thu", "chu", "kku"),
    "kn": ("bekku", "tini", "dene", "ide"),
    "ml": ("unnu", "ille", "nnu"),
    "bn": ("chhi", "bena", "lam"),
    "mr": ("ycha", "aycha", "tay"),
    "gu": ("vanu", "shu"),
    "pa": ("ida", "idi"),
    "or": ("chhi", "ibi"),
}

# Common English words: never counted by endings, and several of them make a message English.
ENGLISH = frozenset("""
    the a an is are was were be been am i you he she it we they my your our their me him her us them this that
    these those what which who whom whose when where why how do does did done have has had will would can could
    should shall may might must not no yes ok okay please thanks thank from to of in on at for with about into
    over under and or but if then so because just only also very more most some any all each every there here
    get got make made take took give gave go went come came see saw know need want like show tell send sent
    money account bank payment paid received message sms phone number app loan card please kindly
    hello hi hey good morning evening night today tomorrow yesterday price buy sell order help
    india indian business shop shops video videos mobile hall wall ball call fill full kill till still
    """.split())

_WORD = re.compile(r"[a-z]+")


def script_language(text: str) -> str | None:
    """The language of a native script used in ``text`` (most letters wins), or None for Latin / digits only."""
    counts: dict[str, int] = {}
    for ch in str(text or ""):
        code = ord(ch)
        for start, end, lang in SCRIPTS:
            if start <= code <= end:
                counts[lang] = counts.get(lang, 0) + 1
                break
    if not counts:
        return None
    return max(counts.items(), key=lambda kv: kv[1])[0]


def scores(text: str) -> dict[str, int]:
    """Points per language for a Latin-letter message (see module doc)."""
    words = _WORD.findall(str(text or "").lower())
    out: dict[str, int] = {}
    for lang, table in WORDS.items():
        endings = ENDINGS.get(lang, ())
        total = 0
        for word in words:
            if word in table:
                total += 2
            elif len(word) >= 4 and word not in ENGLISH and any(word.endswith(e) for e in endings):
                total += 1
        if total:
            out[lang] = total
    return out


def romanized_language(text: str) -> str | None:
    """The Indian language typed in English letters, or None (English, too short, or unclear)."""
    found = scores(text)
    if not found:
        return None
    ranked = sorted(found.items(), key=lambda kv: kv[1], reverse=True)
    best, points = ranked[0]
    if points < 3 or (len(ranked) > 1 and ranked[1][1] == points):
        return None
    words = _WORD.findall(str(text or "").lower())
    english = sum(1 for w in words if w in ENGLISH)
    # A real English sentence with one Indian-looking word stays English.
    if english >= 4 and english * 2 > points * 3:
        return None
    return best


def detect(text: str) -> str | None:
    """Native script first, then romanized; None when the message gives no language signal."""
    return script_language(text) or romanized_language(text)


def reply_locale(locale: str, message: str) -> str:
    """The language to answer in: what the person is writing in (script or romanized) wins over the app's
    locale; a message with no signal ("ok", "yes", a number, a brand) keeps the locale."""
    found = detect(message)
    return found or str(locale or "")
