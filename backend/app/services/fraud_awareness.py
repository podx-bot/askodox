"""Fraud & Market Reality: how common schemes work (in general terms), the
warning signs, how to verify, what evidence to keep, where to report, the
consequences, and safer alternatives.

Rules (master command 18):
- Education and prevention only: descriptions stay at the level a consumer
  needs to recognise a scheme -- never steps, scripts or tools to run one.
- Reporting channels are official and carry the source they were checked
  against (``VERIFIED_ON``).
- Legitimate practices are not labelled fraud: every scheme lists what is
  normal so a seller is not accused for, e.g., a refurbished label.
- One universal schema; a new scheme is a config row, never new code.
"""
from __future__ import annotations

import re
from typing import Any, Dict, List, Optional

VERIFIED_ON = "2026-10-23"

CHANNELS: Dict[str, Dict[str, str]] = {
    "cyber_1930": {
        "name": "Cyber fraud helpline 1930 (call immediately after money is lost)",
        "contact": "1930",
        "url": "https://cybercrime.gov.in",
        "source": "https://static.pib.gov.in/WriteReadData/specificdocs/documents/2025/oct/doc2025107659501.pdf",
    },
    "cyber_portal": {
        "name": "National Cybercrime Reporting Portal",
        "contact": "cybercrime.gov.in",
        "url": "https://cybercrime.gov.in",
        "source": "https://static.pib.gov.in/WriteReadData/specificdocs/documents/2025/oct/doc2025107659501.pdf",
    },
    "nch": {
        "name": "National Consumer Helpline 1915 (WhatsApp / SMS 8800001915)",
        "contact": "1915",
        "url": "https://consumerhelpline.gov.in",
        "source": "https://static.pib.gov.in/WriteReadData/specificdocs/documents/2026/jan/doc2026130774701.pdf",
    },
    "e_jagriti": {
        "name": "e-Jagriti (file a consumer commission case online)",
        "contact": "e-Jagriti portal (Department of Consumer Affairs)",
        # Portal URL not confirmed from an official page: no link, by design.
        "url": "",
        "source": "https://static.pib.gov.in/WriteReadData/specificdocs/documents/2026/jan/doc2026130774701.pdf",
    },
    "chakshu": {
        "name": "Sanchar Saathi — Chakshu (report suspected fraud calls / SMS / WhatsApp)",
        "contact": "sancharsaathi.gov.in",
        "url": "https://sancharsaathi.gov.in",
        "source": "https://www.pib.gov.in/PressReleasePage.aspx?PRID=2223779&reg=3&lang=2",
    },
    "bis_care": {
        "name": "BIS Care app (verify ISI / BIS marks and gold HUID hallmark)",
        "contact": "BIS Care app",
        "url": "https://www.bis.gov.in",
        "source": "https://static.pib.gov.in/WriteReadData/specificdocs/documents/2026/jan/doc2026130774701.pdf",
    },
    "vahan": {
        "name": "VAHAN citizen services (registration, owner count, hypothecation)",
        "contact": "vahan.parivahan.gov.in",
        "url": "https://vahan.parivahan.gov.in/vahanservice/vahan/ui/appl_status/form_Know_Regn_Status.xhtml",
        "source": "https://parivahan.gov.in/en/content/faq",
    },
    "echallan": {
        "name": "e-Challan (pending traffic fines on a vehicle)",
        "contact": "echallan.parivahan.gov.in",
        "url": "https://echallan.parivahan.gov.in/",
        "source": "https://echallan.parivahan.gov.in/",
    },
    "rera_ap": {
        "name": "AP RERA (check project registration)",
        "contact": "rera.ap.gov.in",
        "url": "https://rera.ap.gov.in",
        "source": "https://rera.ap.gov.in/RERA/DOCUMENTS/downloads/Project_Individual_%20User%20Manual%201.2.pdf",
    },
    "rera_tg": {
        "name": "Telangana RERA (check project registration)",
        "contact": "rera.telangana.gov.in",
        "url": "https://rera.telangana.gov.in",
        "source": "https://rera.telangana.gov.in/Desing/FAQ.pdf",
    },
    "police": {
        "name": "Local police station (FIR) for cheating, threats or theft",
        "contact": "112 (emergency)",
        "url": "https://112.gov.in",
        "source": "https://112.gov.in",
    },
}

GENERAL_EVIDENCE = [
    "Screenshots of chats, ads, profiles and payment requests (with date and time visible).",
    "Transaction IDs / UTR numbers, bank statement lines, invoices or bills.",
    "Phone numbers, UPI IDs, website links and names used by the other side.",
    "Photos of the product, packaging, labels and serial numbers as received.",
]

SCHEMES: List[Dict[str, Any]] = [
    {
        "id": "online_payment_scam",
        "title": ("Online payment / UPI scams", "ఆన్‌లైన్ చెల్లింపు / UPI మోసాలు"),
        "keywords": ["upi", "otp", "collect request", "qr code", "refund call", "kyc update", "digital arrest",
                     "lottery", "prize", "courier parcel", "customs", "ఓటీపీ", "యూపీఐ", "లాటరీ"],
        "how_it_works": ("The fraudster creates urgency (refund, KYC block, parcel held, police case, prize) and gets "
                         "the victim to share an OTP, approve a collect request, scan a QR code or install a screen-"
                         "sharing app."),
        "normal_practice": "Banks and police never ask for OTP, PIN or money transfers over a call or video call.",
        "warning_signs": [
            ("Asked to share an OTP / PIN or to 'scan to receive money'.", "OTP / PIN చెప్పమని లేదా 'డబ్బు అందుకోవడానికి స్కాన్ చేయండి' అని అడగడం."),
            ("Threats of arrest or account block unless you pay now.", "ఇప్పుడే చెల్లించకపోతే అరెస్ట్ / ఖాతా బ్లాక్ అని బెదిరింపు."),
            ("Request to install a remote-access app.", "రిమోట్-యాక్సెస్ యాప్ ఇన్‌స్టాల్ చేయమనడం."),
        ],
        "verify": ["Call the bank on the number printed on your card / passbook, never a number from the caller.",
                   "Receiving money never needs a PIN, OTP or QR scan."],
        "report": ["cyber_1930", "cyber_portal", "chakshu"],
        "consequence": "Cheating and impersonation are criminal offences; quick reporting on 1930 can help freeze the money trail.",
        "safer": "Pay only inside trusted apps to verified merchants; turn on transaction alerts.",
    },
    {
        "id": "online_shopping_scam",
        "title": ("Fake online shops / social-media sellers", "నకిలీ ఆన్‌లైన్ షాపులు / సోషల్ మీడియా అమ్మకందారులు"),
        "keywords": ["instagram seller", "facebook seller", "website not delivered", "advance payment", "too cheap",
                     "not delivered", "fake website", "online shopping fraud", "డెలివరీ కాలేదు"],
        "how_it_works": ("A new page or website shows branded goods at very low prices, asks for full advance payment "
                         "by UPI, then stops responding or ships something else."),
        "normal_practice": "Genuine sellers usually offer cash-on-delivery or a marketplace with buyer protection and a GST invoice.",
        "warning_signs": [
            ("Price far below every other seller.", "మిగతా అందరి కంటే చాలా తక్కువ ధర."),
            ("Only advance UPI payment to a personal account.", "వ్యక్తిగత ఖాతాకు ముందుగానే UPI చెల్లింపు మాత్రమే."),
            ("New page, comments turned off, no address or GSTIN.", "కొత్త పేజీ, కామెంట్లు ఆఫ్, చిరునామా / GSTIN లేదు."),
        ],
        "verify": ["Search the seller's name + 'fraud'; check the website age and contact address.",
                   "Prefer cash-on-delivery or a marketplace with returns."],
        "report": ["nch", "cyber_portal", "e_jagriti"],
        "consequence": "Non-delivery after payment is cheating; the consumer commission can order refund and compensation.",
        "safer": "Buy from verified local sellers or marketplaces with buyer protection.",
    },
    {
        "id": "counterfeit_goods",
        "title": ("Counterfeit / duplicate products", "నకిలీ / డూప్లికేట్ వస్తువులు"),
        "keywords": ["fake product", "duplicate", "first copy", "counterfeit", "original or fake", "genuine or not",
                     "hallmark", "isi mark", "నకిలీ వస్తువు", "డూప్లికేట్"],
        "how_it_works": ("Look-alike products with copied branding are sold as genuine, often with poor print, missing "
                         "serial numbers or fake holograms."),
        "normal_practice": ("'Compatible' or unbranded products sold honestly as such are legal; the problem is passing "
                            "them off as the brand."),
        "warning_signs": [
            ("Blurred print, spelling mistakes, missing serial / IMEI.", "అస్పష్ట ముద్రణ, అక్షర తప్పులు, సీరియల్ / IMEI లేకపోవడం."),
            ("No invoice or warranty card.", "బిల్లు లేదా వారంటీ కార్డు లేదు."),
            ("Gold without a HUID hallmark.", "HUID హాల్‌మార్క్ లేని బంగారం."),
        ],
        "verify": ["Check the serial / IMEI on the brand's official site.",
                   "Verify ISI marks and gold HUID in the BIS Care app."],
        "report": ["nch", "e_jagriti"],
        "consequence": "Selling counterfeit goods violates trademark and consumer protection law.",
        "safer": "Buy from authorised dealers and keep the tax invoice.",
    },
    {
        "id": "refurbished_misrepresented",
        "title": ("Used goods sold as new / misrepresented refurbished", "పాత వస్తువును కొత్తదిగా అమ్మడం"),
        "keywords": ["refurbished", "open box", "used as new", "second hand phone", "renewed", "రీఫర్బిష్డ్"],
        "how_it_works": "A used or repaired item is sold as new, or a refurbished grade is overstated.",
        "normal_practice": "Refurbished goods clearly labelled with a grade and a warranty are legitimate and can save money.",
        "warning_signs": [
            ("Seal looks re-glued; accessories not original.", "సీల్ మళ్ళీ అతికించినట్లు; యాక్సెసరీలు ఒరిజినల్ కావు."),
            ("Warranty start date earlier than your purchase.", "వారంటీ తేదీ మీరు కొనడానికి ముందే మొదలైంది."),
        ],
        "verify": ["Check warranty status by serial number on the brand site.",
                   "Get the condition grade and warranty in writing on the invoice."],
        "report": ["nch", "e_jagriti"],
        "consequence": "Misdescribing goods is an unfair trade practice under consumer protection law.",
        "safer": "Buy refurbished only with a written grade, warranty and return window.",
    },
    {
        "id": "underweight_goods",
        "title": ("Short weight / tampered scales", "తక్కువ తూకం / తూకం మోసం"),
        "keywords": ["less weight", "underweight", "short weight", "weighing scale tampered", "తూకం తక్కువ",
                     "తూకం మోసం", "packaged weight"],
        "how_it_works": "Scales are tampered or packaging weight is included, so the buyer gets less than paid for.",
        "normal_practice": "Packaged goods must show net quantity; loose goods are weighed on a stamped scale.",
        "warning_signs": [
            ("Scale not zeroed or hidden from view.", "తూకం సున్నా చేయలేదు లేదా కనిపించకుండా ఉంది."),
            ("No verification stamp on the scale.", "తూకం యంత్రంపై ధృవీకరణ ముద్ర లేదు."),
        ],
        "verify": ["Ask to see the scale at zero and re-weigh on another shop's scale.",
                   "Check net quantity and MRP on packaged goods."],
        "report": ["nch"],
        "consequence": "Short weighing violates the Legal Metrology law; the shop can be fined.",
        "safer": "Use shops with visible, stamped electronic scales.",
    },
    {
        "id": "food_adulteration",
        "title": ("Food adulteration awareness", "ఆహార కల్తీ అవగాహన"),
        "keywords": ["adulteration", "adulterated", "kalti", "కల్తీ", "formalin", "artificial colour", "milk water"],
        "how_it_works": ("Cheaper substances are mixed in or colours / chemicals are added to make food look fresher. "
                         "Most adulterants are invisible to the eye and to a camera."),
        "normal_practice": "Permitted food additives within FSSAI limits and declared on the label are legal.",
        "warning_signs": [
            ("Unusually bright colour, odd smell or texture.", "అసాధారణ రంగు, వాసన లేదా టెక్స్చర్."),
            ("Price far below the market for the same quality.", "అదే నాణ్యతకు మార్కెట్ కంటే చాలా తక్కువ ధర."),
        ],
        "verify": ["Buy FSSAI-licensed packaged food and check the licence number.",
                   "For a real doubt, use a food-testing laboratory; a photo cannot confirm adulteration."],
        "report": ["nch"],
        "consequence": "Selling adulterated or unsafe food is an offence under the food safety law.",
        "safer": "Buy from licensed sellers; keep the bill and a sample if you plan to complain.",
    },
    {
        "id": "vehicle_resale_fraud",
        "title": ("Used vehicle resale fraud", "పాత వాహనాల అమ్మకం మోసం"),
        "keywords": ["used car", "second hand car", "used bike", "odometer", "rc transfer", "hypothecation",
                     "accident car", "flood car", "పాత కారు", "సెకండ్ హ్యాండ్ బైక్"],
        "how_it_works": ("Odometer readings are rolled back, accident / flood damage is hidden, a vehicle still under "
                         "loan is sold, or the RC is never transferred."),
        "normal_practice": "Selling a used vehicle 'as is' with honest disclosure and proper RC transfer is legitimate.",
        "warning_signs": [
            ("Low kilometres but worn pedals / seats.", "తక్కువ కిలోమీటర్లు కానీ అరిగిన పెడల్స్ / సీట్లు."),
            ("Seller avoids RC transfer or shows only a photocopy.", "RC బదిలీ తప్పించుకోవడం లేదా ఫోటోకాపీ మాత్రమే చూపడం."),
            ("Owner name on RC differs from the seller.", "RC లో పేరు అమ్మేవారి పేరుతో సరిపోలదు."),
        ],
        "verify": ["Check registration, owner count and hypothecation on VAHAN.",
                   "Check pending challans on e-Challan; get a mechanic inspection and service history."],
        "report": ["police", "nch"],
        "consequence": "Odometer tampering and selling a hypothecated vehicle without the lender's consent amount to cheating.",
        "safer": "Pay after RC transfer papers and NOC (if loan was taken) are in hand.",
    },
    {
        "id": "real_estate_fraud",
        "title": ("Real-estate / plot fraud", "రియల్ ఎస్టేట్ / ప్లాట్ మోసాలు"),
        "keywords": ["plot", "flat booking", "builder", "layout", "rera", "land documents", "double registration",
                     "ప్లాట్", "ఫ్లాట్", "బిల్డర్", "లేఅవుట్"],
        "how_it_works": ("Unapproved layouts, the same plot sold twice, forged title documents, or projects sold without "
                         "RERA registration."),
        "normal_practice": "Pre-launch offers exist, but a registered project shows its RERA number in every advertisement.",
        "warning_signs": [
            ("No RERA number on the advertisement.", "ప్రకటనలో RERA నంబర్ లేదు."),
            ("Pressure to pay cash or a large token today.", "ఈరోజే నగదు / పెద్ద టోకెన్ చెల్లించమని ఒత్తిడి."),
        ],
        "verify": ["Check the project on the State RERA portal.",
                   "Get the title documents and encumbrance checked by an advocate before paying."],
        "report": ["rera_ap", "rera_tg", "police"],
        "consequence": "Selling unregistered projects or forged titles leads to RERA penalties and criminal cases.",
        "safer": "Pay by bank transfer only after legal verification and a registered agreement.",
    },
    {
        "id": "construction_material_fraud",
        "title": ("Construction material fraud", "నిర్మాణ సామగ్రి మోసం"),
        "keywords": ["cement bag weight", "fake cement", "steel rod", "tmt", "less sand", "brick quality",
                     "సిమెంట్ బస్తా", "స్టీల్ రాడ్", "ఇసుక తక్కువ"],
        "how_it_works": ("Under-weight cement bags, re-packed old cement, under-size steel, or lorries short of the "
                         "billed sand / aggregate volume."),
        "normal_practice": "Brand cement shows the batch / manufacturing date; steel carries ISI marks and grade.",
        "warning_signs": [
            ("Bag weight below 50 kg; lumps in the cement.", "బస్తా 50 కేజీల కంటే తక్కువ; సిమెంట్‌లో గడ్డలు."),
            ("No ISI mark or grade on steel.", "స్టీల్‌పై ISI మార్క్ / గ్రేడ్ లేదు."),
        ],
        "verify": ["Weigh a few bags; check the manufacturing week on the bag.",
                   "Verify ISI licence in the BIS Care app; measure the lorry load (use the Smart Tools volume calculator)."],
        "report": ["nch"],
        "consequence": "Short supply and fake ISI marks violate Legal Metrology and BIS law.",
        "safer": "Buy from authorised dealers with a GST invoice showing quantity and grade.",
    },
    {
        "id": "employment_scam",
        "title": ("Job / work-from-home scams", "ఉద్యోగ / వర్క్-ఫ్రమ్-హోమ్ మోసాలు"),
        "keywords": ["job offer", "registration fee", "joining fee", "job offer fee", "registration fee job", "work from home", "part time task", "like and earn",
                     "offer letter", "job scam", "telegram task", "ఉద్యోగం ఫీజు", "పార్ట్ టైమ్"],
        "how_it_works": ("A job or 'task' earning is offered, then fees, deposits or investments are demanded; small "
                         "early payouts build trust before larger losses."),
        "normal_practice": "Genuine employers do not charge fees to hire you.",
        "warning_signs": [
            ("Any fee for registration, training or a laptop.", "రిజిస్ట్రేషన్, ట్రైనింగ్, ల్యాప్‌టాప్ కోసం ఏదైనా ఫీజు."),
            ("Tasks on Telegram / WhatsApp that need deposits.", "డిపాజిట్ అవసరమైన టెలిగ్రామ్ / వాట్సాప్ టాస్కులు."),
        ],
        "verify": ["Check the company on its official website and call its listed number.",
                   "Never pay to get a job."],
        "report": ["cyber_1930", "cyber_portal", "chakshu"],
        "consequence": "These are cheating offences; report quickly to stop further losses.",
        "safer": "Apply through official company career pages and verified job platforms.",
    },
    {
        "id": "fake_invoice_warranty",
        "title": ("Fake invoices / false warranties", "నకిలీ బిల్లులు / తప్పుడు వారంటీలు"),
        "keywords": ["fake bill", "fake invoice", "warranty not valid", "extended warranty fake", "gstin invalid",
                     "నకిలీ బిల్లు", "వారంటీ"],
        "how_it_works": ("A bill shows a GSTIN that does not exist or belongs to someone else, or a 'warranty' is "
                         "printed that the brand will not honour."),
        "normal_practice": "Small unregistered sellers may lawfully issue a plain bill without GST.",
        "warning_signs": [
            ("GSTIN on the bill fails the GST portal search.", "బిల్లులోని GSTIN GST పోర్టల్‌లో లేదు."),
            ("Warranty card not stamped or not in the brand's format.", "వారంటీ కార్డుపై ముద్ర లేదు."),
        ],
        "verify": ["Search the GSTIN on the GST portal ('Search Taxpayer').",
                   "Register the warranty with the brand directly."],
        "report": ["nch", "e_jagriti"],
        "consequence": "Issuing fake GST invoices is an offence under the CGST Act.",
        "safer": "Buy from registered sellers when you need a tax invoice or warranty.",
    },
    {
        "id": "unauthorised_service",
        "title": ("Unauthorised service providers", "అనధికార సర్వీస్ ప్రొవైడర్లు"),
        "keywords": ["customer care number", "service centre number google", "fake customer care", "technician fraud",
                     "కస్టమర్ కేర్ నంబర్"],
        "how_it_works": ("Fake 'customer care' numbers on search results or ads send technicians who overcharge, "
                         "replace parts with used ones, or take remote access to the phone."),
        "normal_practice": "Independent repair shops are legal when they say they are independent.",
        "warning_signs": [
            ("Number found only in an ad or a random listing.", "నంబర్ కేవలం ప్రకటనలో మాత్రమే కనిపించింది."),
            ("Advance 'visit fee' by UPI to a personal account.", "వ్యక్తిగత ఖాతాకు ముందుగా 'విజిట్ ఫీజు'."),
        ],
        "verify": ["Take the care number from the brand's official website or the product manual."],
        "report": ["cyber_1930", "nch"],
        "consequence": "Impersonating a brand's service is cheating.",
        "safer": "Book service from the brand app / website; ask for removed parts back.",
    },
]

_BY_ID = {scheme["id"]: scheme for scheme in SCHEMES}


def _localised(scheme: Dict[str, Any], te: bool) -> Dict[str, Any]:
    return {
        "id": scheme["id"],
        "title": scheme["title"][1 if te else 0],
        "how_it_works": scheme["how_it_works"],
        "normal_practice": scheme["normal_practice"],
        "warning_signs": [pair[1 if te else 0] for pair in scheme["warning_signs"]],
        "verify": list(scheme["verify"]),
        "evidence": list(GENERAL_EVIDENCE),
        "report": [{"id": c, **CHANNELS[c]} for c in scheme["report"]],
        "consequence": scheme["consequence"],
        "safer_alternative": scheme["safer"],
        "verified_on": VERIFIED_ON,
    }


def list_schemes(language: str = "en") -> List[Dict[str, Any]]:
    te = str(language or "").lower().startswith("te")
    return [{"id": s["id"], "title": s["title"][1 if te else 0]} for s in SCHEMES]


def scheme(scheme_id: str, language: str = "en") -> Optional[Dict[str, Any]]:
    found = _BY_ID.get(str(scheme_id or ""))
    if found is None:
        return None
    return _localised(found, str(language or "").lower().startswith("te"))


_WORD = re.compile(r"[a-z0-9]+")


def match(text: str) -> Optional[str]:
    """Best-matching scheme id for a message (keyword hits; Telugu substrings).
    None when nothing matches -- never a guess."""
    q = " " + " ".join(_WORD.findall(str(text or "").lower())) + " "
    raw = str(text or "").lower()
    best, score = None, 0
    for s in SCHEMES:
        hits = 0
        for kw in s["keywords"]:
            if kw.isascii():
                if f" {kw} " in q:
                    hits += 2 if " " in kw else 1
            elif kw in raw:
                hits += 1
        if hits > score:
            best, score = s["id"], hits
    return best


_FRAUD_INTENT = re.compile(
    r"\b(scam|scams|fraud|fake|cheat|cheated|cheating|duplicate|counterfeit|genuine or fake|original or fake|"
    r"is this (safe|real|legit|genuine)|legit|trust this|adulterat\w*|tamper\w*)\b|మోస|నకిలీ|కల్తీ")


def fraud_intent(text: str) -> bool:
    return bool(_FRAUD_INTENT.search(str(text or "").lower()))


_HOW_TO_COMMIT = re.compile(
    r"\bhow (can|do|to)\s+(i|we)?\s*(scam|cheat|fake|tamper|roll back|rollback|forge|counterfeit|make fake|"
    r"create fake|adulterate)\b|\b(teach|help) me (to )?(scam|cheat|forge|tamper)\b")


def commit_intent(text: str) -> bool:
    """Asking how to CARRY OUT a scheme (refused; awareness only)."""
    return bool(_HOW_TO_COMMIT.search(str(text or "").lower()))
