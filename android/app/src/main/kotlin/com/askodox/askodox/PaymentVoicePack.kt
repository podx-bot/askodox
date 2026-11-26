package com.askodox.askodox

/**
 * Owner 2026-11-23 (ASKODOX Lite, step 1): the payment voice works with NO internet, in the SAME ElevenLabs voice.
 *
 * Pure Kotlin (no Android): the phone keeps a small "voice pack" per voice + language -- number words and the fixed
 * words around an amount -- fetched ONCE while the net is there. A payment whose whole sentence was never heard
 * before is then put together from those clips on the phone ([clipsFor]); nothing is spoken in a second voice.
 *
 * Also the ASKODOX lines (owner 2026-11-23, all ON by default, each can be switched off):
 *  - an ASKODOX tune before every payment voice (Player, raw resource `askodox_tune`);
 *  - "Namaste, today ASKODOX tells your payments" before the FIRST payment of the day ([brandChoice]);
 *  - "This voice is ASKODOX's -- free for you too" at most twice a day, never on the first payments;
 *  - the night "ASKODOX count" ([nightParts]) -- only on a day that had payments (no payment = no sound, no notice).
 * Money never "came through ASKODOX": the lines name ASKODOX as the voice, never as where the money went.
 */
object PaymentVoicePack {
    /** One piece of a spoken part: a number (said with the pack's number words) or plain words. */
    data class Seg(val number: Long?, val text: String)

    /** Languages whose number words are written here; others keep the earlier way (cached parts, else the phone's voice). */
    val NUMBER_LANGUAGES = setOf("te", "hi", "en")

    private val digits = Regex("""\d[\d,]*""")

    /** "500 రూపాయలు జమ అయ్యాయి." -> [500] ["రూపాయలు జమ అయ్యాయి."]. Commas inside a number are dropped. */
    fun segments(part: String): List<Seg> {
        val out = ArrayList<Seg>()
        var at = 0
        for (m in digits.findAll(part)) {
            val before = part.substring(at, m.range.first).trim()
            if (before.isNotEmpty()) out += Seg(null, before)
            val n = m.value.replace(",", "").toLongOrNull()
            if (n != null) out += Seg(n, m.value) else out += Seg(null, m.value)
            at = m.range.last + 1
        }
        val tail = part.substring(at).trim()
        if (tail.isNotEmpty()) out += Seg(null, tail)
        return out
    }

    /**
     * The clips (texts) that say [part] on the phone: plain words stay one clip, every number becomes its number words.
     * Null when a number is in a language without number words here (or out of range).
     */
    fun clipsFor(part: String, language: String): List<String>? {
        val segs = segments(part)
        if (segs.none { it.number != null }) return listOf(part.trim()).filter { it.isNotEmpty() }
        val out = ArrayList<String>()
        for (s in segs) {
            if (s.number == null) out += s.text
            else out += numberWords(s.number, language) ?: return null
        }
        return out
    }

    // ------------------------------------------------------------------------------------------- number words

    private val TE_UNITS = listOf("", "ఒకటి", "రెండు", "మూడు", "నాలుగు", "ఐదు", "ఆరు", "ఏడు", "ఎనిమిది", "తొమ్మిది")
    private val TE_TEENS = listOf("పది", "పదకొండు", "పన్నెండు", "పదమూడు", "పద్నాలుగు", "పదిహేను", "పదహారు", "పదిహేడు",
        "పద్దెనిమిది", "పందొమ్మిది")
    private val TE_TENS = listOf("", "", "ఇరవై", "ముప్పై", "నలభై", "యాభై", "అరవై", "డెబ్బై", "ఎనభై", "తొంభై")

    private val HI_1_99 = listOf("",
        "एक", "दो", "तीन", "चार", "पाँच", "छह", "सात", "आठ", "नौ", "दस",
        "ग्यारह", "बारह", "तेरह", "चौदह", "पंद्रह", "सोलह", "सत्रह", "अठारह", "उन्नीस", "बीस",
        "इक्कीस", "बाईस", "तेईस", "चौबीस", "पच्चीस", "छब्बीस", "सत्ताईस", "अट्ठाईस", "उनतीस", "तीस",
        "इकतीस", "बत्तीस", "तैंतीस", "चौंतीस", "पैंतीस", "छत्तीस", "सैंतीस", "अड़तीस", "उनतालीस", "चालीस",
        "इकतालीस", "बयालीस", "तैंतालीस", "चवालीस", "पैंतालीस", "छियालीस", "सैंतालीस", "अड़तालीस", "उनचास", "पचास",
        "इक्यावन", "बावन", "तिरपन", "चौवन", "पचपन", "छप्पन", "सत्तावन", "अट्ठावन", "उनसठ", "साठ",
        "इकसठ", "बासठ", "तिरसठ", "चौंसठ", "पैंसठ", "छियासठ", "सड़सठ", "अड़सठ", "उनहत्तर", "सत्तर",
        "इकहत्तर", "बहत्तर", "तिहत्तर", "चौहत्तर", "पचहत्तर", "छिहत्तर", "सतहत्तर", "अठहत्तर", "उन्यासी", "अस्सी",
        "इक्यासी", "बयासी", "तिरासी", "चौरासी", "पचासी", "छियासी", "सत्तासी", "अट्ठासी", "नवासी", "नब्बे",
        "इक्यानवे", "बानवे", "तिरानवे", "चौरानवे", "पचानवे", "छियानवे", "सत्तानवे", "अट्ठानवे", "निन्यानवे")

    private val EN_ONES = listOf("", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
        "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen")
    private val EN_TENS = listOf("", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety")

    /** 1..99 as ONE clip ("ముప్పై నాలుగు", "चौंतीस", "thirty four"). */
    fun below100(n: Int, language: String): String? {
        if (n !in 1..99) return null
        return when (language) {
            "te" -> when {
                n < 10 -> TE_UNITS[n]
                n < 20 -> TE_TEENS[n - 10]
                else -> TE_TENS[n / 10] + (if (n % 10 > 0) " " + TE_UNITS[n % 10] else "")
            }
            "hi" -> HI_1_99[n]
            "en" -> if (n < 20) EN_ONES[n] else EN_TENS[n / 10] + (if (n % 10 > 0) " " + EN_ONES[n % 10] else "")
            else -> null
        }
    }

    /**
     * The clips that say [n] (Indian system: crore, lakh, thousand, hundred) before the word for rupees / paise:
     * 1234 -> te ["వెయ్యి", "రెండు వందల", "ముప్పై నాలుగు"], hi ["एक", "हज़ार", "दो", "सौ", "चौंतीस"].
     * Null for a language without number words here, or for 0 / more than 99 crore.
     */
    fun numberWords(n: Long, language: String): List<String>? {
        if (language !in NUMBER_LANGUAGES || n <= 0 || n >= 1_000_000_000L) return null
        if (language == "te" && n == 1L) return listOf("ఒక్క")
        val crore = (n / 10_000_000L).toInt()
        val lakh = ((n / 100_000L) % 100).toInt()
        val thousand = ((n / 1000L) % 100).toInt()
        val hundred = ((n / 100L) % 10).toInt()
        val rest = (n % 100).toInt()
        val out = ArrayList<String>()
        fun w(x: Int) = below100(x, language)!!
        when (language) {
            "te" -> {
                if (crore > 0) { if (crore == 1) out += "ఒక కోటి" else { out += w(crore); out += "కోట్ల" } }
                if (lakh > 0) { if (lakh == 1) out += "ఒక లక్ష" else { out += w(lakh); out += "లక్షల" } }
                if (thousand > 0) { if (thousand == 1) out += "వెయ్యి" else { out += w(thousand); out += "వేల" } }
                if (hundred > 0) out += if (hundred == 1) (if (rest > 0) "నూట" else "వంద") else "${TE_UNITS[hundred]} వందల"
            }
            "hi" -> {
                if (crore > 0) { out += w(crore); out += "करोड़" }
                if (lakh > 0) { out += w(lakh); out += "लाख" }
                if (thousand > 0) { out += w(thousand); out += "हज़ार" }
                if (hundred > 0) { out += w(hundred); out += "सौ" }
            }
            "en" -> {
                if (crore > 0) { out += w(crore); out += "crore" }
                if (lakh > 0) { out += w(lakh); out += "lakh" }
                if (thousand > 0) { out += w(thousand); out += "thousand" }
                if (hundred > 0) { out += w(hundred); out += "hundred" }
            }
        }
        if (rest > 0) out += w(rest)
        return out
    }

    /** Every number clip a language needs (1..99 + the scale words). */
    fun numberTexts(language: String): List<String> {
        if (language !in NUMBER_LANGUAGES) return emptyList()
        val out = LinkedHashSet<String>()
        for (i in 1..99) below100(i, language)?.let { out += it }
        out += when (language) {
            "te" -> listOf("ఒక్క", "ఒక కోటి", "కోట్ల", "ఒక లక్ష", "లక్షల", "వెయ్యి", "వేల", "నూట", "వంద") +
                (2..9).map { "${TE_UNITS[it]} వందల" }
            "hi" -> listOf("करोड़", "लाख", "हज़ार", "सौ")
            else -> listOf("crore", "lakh", "thousand", "hundred")
        }
        return out.toList()
    }

    /**
     * The whole pack for one language: number words + the fixed words of every sentence the payment voice says
     * (taken from the SAME builders the phone speaks with, so a new sentence there is in the pack by itself).
     * Names are never in the pack (a name is fetched when it is first heard, and kept).
     */
    fun packTexts(language: String, shop: String?): List<String> {
        val out = LinkedHashSet<String>(numberTexts(language))
        val who = NAME_MARK
        val shopName = shop?.trim()?.takeIf { it.isNotEmpty() }
        val parts = ArrayList<String>()
        for (a in listOf(77_700L, 77_777L)) {
            for (credit in listOf(true, false)) {
                parts += PaymentAlertParser.personalParts(a, language, credit, null)
                parts += PaymentAlertParser.personalParts(a, language, credit, who)
            }
            // with the shop's own name, and without (a shop phone that has no name saved, the "Listen" sample)
            for (place in listOf(shopName, null).distinct()) {
                parts += PaymentAlertParser.announcementParts(a, language, false, null, place)
                parts += PaymentAlertParser.announcementParts(a, language, false, "$who Stores", place)
            }
            parts += PaymentAlertParser.billPaidParts(a, language, null, true)
            parts += PaymentAlertParser.billPaidParts(a, language, null, false)
            parts += PaymentAlertParser.bonusParts(a, language, "cashback")
            parts += PaymentAlertParser.bonusParts(a, language, "interest")
            for (k in NOTICE_KINDS) parts += PaymentAlertParser.noticeParts(k, a, language, null)
            parts += nightParts(1, a, language)
            parts += nightParts(12, a, language)
        }
        parts += helloPart(language)
        parts += customerPart(language)
        for (p in parts) {
            if (p.contains(NAME_MARK)) continue
            for (s in segments(p)) if (s.number == null && s.text.isNotBlank()) out += s.text
        }
        return out.toList()
    }

    private const val NAME_MARK = "QXZ"
    private val NOTICE_KINDS = listOf("refund_started", "pending", "failed", "cancelled", "bill", "autopay", "autopay_off",
        "request", "unsure", "late_in", "late_out", "sorry_out", "sorry_in", "suspect")

    // ------------------------------------------------------------------------------------------- ASKODOX lines

    /** "Namaste! Today ASKODOX tells your payments." (said before the first payment of the day). */
    fun helloPart(language: String): String = HELLO[language] ?: HELLO.getValue("en")

    /** "This voice is ASKODOX's. Free for you too." (owner 2026-11-26: "for you", not "for your shop") (customers at the counter hear it; max 2 a day). */
    fun customerPart(language: String): String = CUSTOMER[language] ?: CUSTOMER.getValue("en")

    /**
     * Owner 2026-11-24 (at 9 pm "9 payments" once, "2 payments" once, then again): ONE night voice per phone. The sides
     * this phone listens for (the shop, My phone) are added into one count + total; each side's own numbers are shown
     * in the notification only.
     */
    fun nightTotal(sides: List<Pair<Int, Long>>): Pair<Int, Long> =
        sides.fold(0 to 0L) { acc, s -> (acc.first + s.first) to (acc.second + s.second) }

    /**
     * Owner 2026-11-24 ("it stops before the last word, then the same payment is said again"): when the voice file
     * failed AFTER it was already heard, the fallback voice must NOT say the sentence a second time.
     */
    fun sayAgainAfterFailure(playedMs: Long, expectedMs: Long): Boolean = playedMs < 700L

    // ------------------------------------------------------------------ MP3 parts (owner 2026-11-24)

    /** Bytes of one MPEG audio frame header at [i], with its length and samples; null when no valid Layer III frame. */
    private fun frameAt(b: ByteArray, i: Int): Triple<Int, Int, Int>? {
        if (i + 4 > b.size) return null
        val h1 = b[i].toInt() and 0xFF
        val h2 = b[i + 1].toInt() and 0xFF
        val h3 = b[i + 2].toInt() and 0xFF
        if (h1 != 0xFF || (h2 and 0xE0) != 0xE0) return null
        val version = (h2 shr 3) and 3          // 3 = MPEG-1, 2 = MPEG-2, 0 = MPEG-2.5
        val layer = (h2 shr 1) and 3            // 1 = Layer III
        if (version == 1 || layer != 1) return null
        val brIndex = (h3 shr 4) and 15
        val srIndex = (h3 shr 2) and 3
        if (brIndex == 0 || brIndex == 15 || srIndex == 3) return null
        val pad = (h3 shr 1) and 1
        val mpeg1 = version == 3
        val br = (if (mpeg1) intArrayOf(0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320)
            else intArrayOf(0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160))[brIndex] * 1000
        val sr = intArrayOf(44100, 48000, 32000)[srIndex] / (if (mpeg1) 1 else if (version == 2) 2 else 4)
        val len = (if (mpeg1) 144 else 72) * br / sr + pad
        return Triple(len, if (mpeg1) 1152 else 576, sr)
    }

    /** Is the frame at [i] the encoder's "Xing" / "Info" / "VBRI" tag frame (no sound; it states ONE part's length)? */
    private fun isTagFrame(b: ByteArray, i: Int, len: Int): Boolean {
        val end = minOf(b.size, i + len)
        for (k in i + 4 until end - 3) {
            val w = String(byteArrayOf(b[k], b[k + 1], b[k + 2], b[k + 3]), Charsets.ISO_8859_1)
            if (w == "Xing" || w == "Info" || w == "VBRI") return k <= i + 4 + 36
        }
        return false
    }

    /** The sound frames of one MP3 part: its ID3 tags and its "Info" frame dropped. Unreadable -> the bytes as they are. */
    fun mp3Frames(b: ByteArray): ByteArray {
        var i = 0
        if (b.size >= 10 && b[0] == 'I'.code.toByte() && b[1] == 'D'.code.toByte() && b[2] == '3'.code.toByte()) {
            val size = ((b[6].toInt() and 0x7F) shl 21) or ((b[7].toInt() and 0x7F) shl 14) or
                ((b[8].toInt() and 0x7F) shl 7) or (b[9].toInt() and 0x7F)
            i = 10 + size + (if ((b[5].toInt() and 0x10) != 0) 10 else 0)
        }
        var end = b.size
        if (end - i >= 128 && b[end - 128] == 'T'.code.toByte() && b[end - 127] == 'A'.code.toByte() &&
            b[end - 126] == 'G'.code.toByte()) end -= 128
        while (i < end && frameAt(b, i) == null) i++
        val first = frameAt(b, i) ?: return b
        if (isTagFrame(b, i, first.first)) i += first.first
        return if (i >= end) ByteArray(0) else b.copyOfRange(i, end)
    }

    /** The parts of one sentence joined into ONE MP3: sound frames only, so the player sees the whole length. */
    fun joinMp3(parts: List<ByteArray>): ByteArray {
        val out = java.io.ByteArrayOutputStream()
        for (p in parts) out.write(mp3Frames(p))
        return out.toByteArray()
    }

    /** The real length of an MP3, counted frame by frame (0 when it is not one). */
    fun mp3DurationMs(b: ByteArray): Long {
        var i = 0
        var micros = 0L
        var frames = 0
        while (i < b.size) {
            val f = frameAt(b, i)
            if (f == null) { i++; continue }
            micros += f.second * 1_000_000L / f.third
            frames++
            i += maxOf(1, f.first)
        }
        return if (frames == 0) 0L else micros / 1000
    }

    /** The night count: "ASKODOX count: today 45 payments came, total 12400 rupees. See you tomorrow!" */
    fun nightParts(count: Int, amountPaise: Long, language: String): List<String> {
        val row = NIGHT[language] ?: NIGHT.getValue("en")
        val money = PaymentAlertParser.moneyWords(amountPaise, language)
        return listOf(row[0], if (count == 1) row[1] else row[2].replace("{n}", count.toString()),
            row[3].replace("{money}", money), row[4])
    }

    // ASKODOX is written the way it is SAID in each script, so the voice never spells it letter by letter.
    private val HELLO: Map<String, String> = mapOf(
        "te" to "నమస్తే! ఈరోజు మీ పేమెంట్స్ ఆస్కోడాక్స్ చెప్తుంది.",
        "hi" to "नमस्ते! आज आपके पेमेंट आस्कोडॉक्स बताएगा।",
        "en" to "Hello! Askodox will tell you today's payments.",
        "ta" to "வணக்கம்! இன்றைய பேமெண்ட்களை அஸ்கோடாக்ஸ் சொல்லும்.",
        "kn" to "ನಮಸ್ಕಾರ! ಇಂದಿನ ಪೇಮೆಂಟ್‌ಗಳನ್ನು ಅಸ್ಕೋಡಾಕ್ಸ್ ಹೇಳುತ್ತದೆ.",
        "ml" to "നമസ്കാരം! ഇന്നത്തെ പേയ്‌മെന്റുകൾ അസ്കോഡോക്സ് പറയും.",
        "bn" to "নমস্কার! আজকের পেমেন্ট আস্কোডক্স জানাবে।",
        "mr" to "नमस्कार! आजचे पेमेंट आस्कोडॉक्स सांगेल.",
        "gu" to "નમસ્તે! આજના પેમેન્ટ આસ્કોડોક્સ કહેશે.",
        "pa" to "ਨਮਸਕਾਰ! ਅੱਜ ਦੇ ਪੇਮੈਂਟ ਆਸਕੋਡੌਕਸ ਦੱਸੇਗਾ।",
        "or" to "ନମସ୍କାର! ଆଜିର ପେମେଣ୍ଟ ଆସ୍କୋଡକ୍ସ କହିବ।",
        "ur" to "آداب! آج کی پیمنٹس آسکوڈوکس بتائے گا۔",
    )

    private val CUSTOMER: Map<String, String> = mapOf(
        "te" to "ఈ సౌండ్ ఆస్కోడాక్స్ ది. మీకు కూడా ఫ్రీ.",
        "hi" to "यह आवाज़ आस्कोडॉक्स की है। आपके लिए भी फ्री।",
        "en" to "This voice is from Askodox. Free for you too.",
        "ta" to "இந்த குரல் அஸ்கோடாக்ஸ் உடையது. உங்களுக்கும் இலவசம்.",
        "kn" to "ಈ ಧ್ವನಿ ಅಸ್ಕೋಡಾಕ್ಸ್‌ನದು. ನಿಮಗೂ ಉಚಿತ.",
        "ml" to "ഈ ശബ്ദം അസ്കോഡോക്സിന്റേതാണ്. നിങ്ങൾക്കും സൗജന്യം.",
        "bn" to "এই আওয়াজ আস্কোডক্সের। আপনার জন্যও ফ্রি।",
        "mr" to "हा आवाज आस्कोडॉक्सचा आहे. तुमच्यासाठीही मोफत.",
        "gu" to "આ અવાજ આસ્કોડોક્સનો છે. તમારા માટે પણ મફત.",
        "pa" to "ਇਹ ਆਵਾਜ਼ ਆਸਕੋਡੌਕਸ ਦੀ ਹੈ। ਤੁਹਾਡੇ ਲਈ ਵੀ ਮੁਫ਼ਤ।",
        "or" to "ଏହି ସ୍ୱର ଆସ୍କୋଡକ୍ସର। ଆପଣଙ୍କ ପାଇଁ ମଧ୍ୟ ମାଗଣା।",
        "ur" to "یہ آواز آسکوڈوکس کی ہے۔ آپ کے لیے بھی مفت۔",
    )

    /** language -> [head, one payment, {n} payments, total {money}, goodbye]. */
    private val NIGHT: Map<String, List<String>> = mapOf(
        "te" to listOf("ఆస్కోడాక్స్ లెక్క:", "ఈరోజు ఒక్క పేమెంట్ వచ్చింది,", "ఈరోజు {n} పేమెంట్స్ వచ్చాయి,", "మొత్తం {money}.", "రేపు కలుద్దాం!"),
        "hi" to listOf("आस्कोडॉक्स का हिसाब:", "आज एक पेमेंट आया,", "आज {n} पेमेंट आए,", "कुल {money}।", "कल मिलते हैं!"),
        "en" to listOf("Askodox count:", "one payment came today,", "{n} payments came today,", "total {money}.", "See you tomorrow!"),
        "ta" to listOf("அஸ்கோடாக்ஸ் கணக்கு:", "இன்று ஒரு பேமெண்ட் வந்தது,", "இன்று {n} பேமெண்ட்கள் வந்தன,", "மொத்தம் {money}.", "நாளை சந்திப்போம்!"),
        "kn" to listOf("ಅಸ್ಕೋಡಾಕ್ಸ್ ಲೆಕ್ಕ:", "ಇಂದು ಒಂದು ಪೇಮೆಂಟ್ ಬಂದಿದೆ,", "ಇಂದು {n} ಪೇಮೆಂಟ್‌ಗಳು ಬಂದಿವೆ,", "ಒಟ್ಟು {money}.", "ನಾಳೆ ಸಿಗೋಣ!"),
        "ml" to listOf("അസ്കോഡോക്സ് കണക്ക്:", "ഇന്ന് ഒരു പേയ്‌മെന്റ് വന്നു,", "ഇന്ന് {n} പേയ്‌മെന്റുകൾ വന്നു,", "ആകെ {money}.", "നാളെ കാണാം!"),
        "bn" to listOf("আস্কোডক্সের হিসাব:", "আজ একটি পেমেন্ট এসেছে,", "আজ {n}টি পেমেন্ট এসেছে,", "মোট {money}।", "কাল দেখা হবে!"),
        "mr" to listOf("आस्कोडॉक्सचा हिशोब:", "आज एक पेमेंट आले,", "आज {n} पेमेंट आले,", "एकूण {money}.", "उद्या भेटू!"),
        "gu" to listOf("આસ્કોડોક્સનો હિસાબ:", "આજે એક પેમેન્ટ આવ્યું,", "આજે {n} પેમેન્ટ આવ્યા,", "કુલ {money}.", "કાલે મળીએ!"),
        "pa" to listOf("ਆਸਕੋਡੌਕਸ ਦਾ ਹਿਸਾਬ:", "ਅੱਜ ਇੱਕ ਪੇਮੈਂਟ ਆਇਆ,", "ਅੱਜ {n} ਪੇਮੈਂਟ ਆਏ,", "ਕੁੱਲ {money}।", "ਕੱਲ੍ਹ ਮਿਲਾਂਗੇ!"),
        "or" to listOf("ଆସ୍କୋଡକ୍ସ ହିସାବ:", "ଆଜି ଗୋଟିଏ ପେମେଣ୍ଟ ଆସିଲା,", "ଆଜି {n}ଟି ପେମେଣ୍ଟ ଆସିଲା,", "ମୋଟ {money}।", "କାଲି ଦେଖା ହେବ!"),
        "ur" to listOf("آسکوڈوکس کا حساب:", "آج ایک پیمنٹ آئی،", "آج {n} پیمنٹس آئیں،", "کل رقم {money}۔", "پھر ملیں گے!"),
    )

    // ------------------------------------------------------------------------------------------- when to say them

    /** The customer line: from the 3rd payment of the day, at most twice a day, at least 2 hours apart. */
    const val CUSTOMER_FROM_PAYMENT = 3
    const val CUSTOMER_PER_DAY = 2
    const val CUSTOMER_GAP_MS = 2 * 60 * 60_000L

    /** What the phone remembers between payments (kept in its own preferences). */
    data class BrandState(val payDay: Long = -1, val payCount: Int = 0, val helloDay: Long = -1,
                          val customerDay: Long = -1, val customerCount: Int = 0, val lastCustomerAt: Long = 0)

    data class BrandChoice(val hello: Boolean, val customer: Boolean, val next: BrandState)

    /**
     * For ONE real incoming payment that is about to be spoken: say the morning hello before it? the customer line
     * after it? [today] = the phone's local day number. Only spoken payments count (a silent one never gets a line).
     */
    fun brandChoice(today: Long, now: Long, s: BrandState, helloOn: Boolean, customerOn: Boolean): BrandChoice {
        val count = (if (s.payDay == today) s.payCount else 0) + 1
        val hello = helloOn && s.helloDay != today
        val customerToday = if (s.customerDay == today) s.customerCount else 0
        val customer = customerOn && !hello && count >= CUSTOMER_FROM_PAYMENT && customerToday < CUSTOMER_PER_DAY &&
            (customerToday == 0 || now - s.lastCustomerAt >= CUSTOMER_GAP_MS)
        val next = BrandState(
            payDay = today, payCount = count,
            helloDay = if (hello) today else s.helloDay,
            customerDay = if (customer) today else if (s.customerDay == today) today else s.customerDay,
            customerCount = if (customer) customerToday + 1 else customerToday,
            lastCustomerAt = if (customer) now else s.lastCustomerAt,
        )
        return BrandChoice(hello, customer, next)
    }

    /** One history row as the night count sees it. */
    data class DayRow(val day: Long, val amountPaise: Long, val counted: Boolean)

    /** (payments, total paise) that CAME IN on [today]; rows not counted (test, set aside, out, notices) are skipped. */
    fun dayTotals(rows: List<DayRow>, today: Long): Pair<Int, Long> {
        var n = 0
        var total = 0L
        for (r in rows) if (r.counted && r.day == today && r.amountPaise > 0) { n++; total += r.amountPaise }
        return n to total
    }

    /** The next time the night count is due: today at [minuteOfDay] if still ahead, else tomorrow (local time). */
    fun nextNightAt(nowMs: Long, zoneOffsetMs: Long, minuteOfDay: Int): Long {
        val dayStart = Math.floorDiv(nowMs + zoneOffsetMs, 86_400_000L) * 86_400_000L - zoneOffsetMs
        val today = dayStart + minuteOfDay * 60_000L
        return if (today > nowMs) today else today + 86_400_000L
    }

    /** "21:00" -> 1260 minutes; anything else -> 21:00. */
    fun minuteOf(hhmm: String?): Int {
        val p = (hhmm ?: "").split(":")
        val h = p.getOrNull(0)?.trim()?.toIntOrNull()
        val m = p.getOrNull(1)?.trim()?.toIntOrNull() ?: 0
        return if (h != null && h in 0..23 && m in 0..59) h * 60 + m else 21 * 60
    }
}
