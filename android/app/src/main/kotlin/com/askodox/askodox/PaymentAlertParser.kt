package com.askodox.askodox

import java.util.Locale

/**
 * Pure (no Android imports) reader for the incoming-payment notification of an ALLOWED payment app.
 * Only the amount, a transaction reference and (for the spoken thank-you ONLY) the payer's name leave this
 * function -- never the text or a number. The name is spoken on this phone and never stored or uploaded.
 *
 * A notification is accepted only when it clearly says money came IN and carries exactly one amount.
 * Outgoing payments, requests, OTPs, cashback / rewards / offers, failures and refunds are ignored.
 * Balances are never the payment; with several amounts the first non-balance amount is the payment.
 * Clear incoming wording with NO amount at all is AMBIGUOUS (recorded, never announced as money).
 */
object PaymentAlertParser {
    sealed class Result {
        data class Accepted(val amountPaise: Long, val reference: String?, val payer: String? = null,
                            val account: String? = null) : Result()
        data class Ambiguous(val reason: String) : Result()

        /**
         * A payment-app message with ONE amount whose wording is neither known incoming nor known outgoing: the
         * phone asks the person once ("did you receive this?"). [template] is the message with the amount
         * replaced by ₹# (title / names never kept).
         */
        data class Unknown(val amountPaise: Long, val template: String) : Result()
        object Ignored : Result()

        /** Money that LEFT the person's account (debited / paid to / sent to). Never uploaded; spoken only if asked. */
        data class Outgoing(val amountPaise: Long, val party: String?, val account: String?) : Result()
    }

    /** The message body with amounts as ₹#, lower case, single spaces -- the shape a person can confirm. */
    fun template(text: String?): String {
        val t = amountRegex.replace(text ?: "", "₹#").lowercase(Locale.ROOT).replace(Regex("\\s+"), " ").trim()
        return t.take(120)
    }

    private val incoming = listOf(
        "received", "credited", "paid you", "sent you", "has paid", "have paid you", "payment of", "added to your",
        // PhonePe: "Bhagya sent ₹1 to you." -- the amount sits between "sent" and "to you", so "sent you" never matched.
        // Outgoing texts still say "you sent" / "sent to" / "paid to" and stay rejected below.
        " to you",
        // Bank SMS of every bank ("has a credit by Transfer of Rs 1,000", "credit of INR 500").
        "a credit", "credit of", "credit by",
        "deposited", "జమ", "అందింది", "అందాయి", "स्वीकार", "प्राप्त", "मिले", "मिला", "जमा",
    )
    private val reject = listOf(
        "paid to", "sent to", "you paid", "you sent", "debited", "debit", "request", "collect", "otp", "one time",
        "cashback", "reward", "offer", "coupon", "scratch", "failed", "declined", "unsuccessful", "pending",
        "refund", "reversed", "due", "reminder", "recharge", "bill pay", " won", "win ", "loan", "emi",
        "verification code", "password", "pin ",
    )
    private val amountRegex = Regex("""(?:₹|\brs[.:]?|\binr[.:]?)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)""", RegexOption.IGNORE_CASE)

    /** Bank SMS that write the amount WITHOUT a currency ("SBI: A/C X1234 debited by 20.0 on ..."). */
    private val bareBankAmount = Regex(
        """\b(?:credited|debited|deposited|withdrawn|credit|debit)\s*(?:by|with|for|of)\s+([0-9][0-9,]*(?:\.[0-9]{1,2})?)\b(?!\s*(?:/|-\d))""",
        RegexOption.IGNORE_CASE,
    )

    /**
     * The fixed safety lines every bank adds ("Not you? Call 1800..", "Never share OTP/PIN", "SMS BLOCK UPI to ..")
     * are cut off before reading: their "OTP" / "PIN" / phone numbers made a real credit look like an OTP message.
     */
    private val bankBoilerplate = Regex(
        """(?i)(?:\bnot\s+(?:you|u)\b|\bif\s+not\s+(?:done\s+by\s+|initiated\s+by\s+)?(?:you|u)\b|\bnever\s+share|""" +
            """\bdo\s*n[o']?t\s+share|\bcall\s+\+?\d{3,}|\bsms\s+block|\bto\s+report|\bfor\s+dispute|\breport\s+fraud|""" +
            """\bif\s+this\s+(?:was|is)\s+not|\bhttps?://).*$""",
    )

    /** Message without the bank's safety lines; the original when cutting would leave nothing. */
    fun withoutBoilerplate(s: String): String {
        val cut = bankBoilerplate.replace(s, "").trim()
        return if (cut.length >= 8) cut else s
    }

    /**
     * Words of messages that carry a rupee amount but are NOT a payment (bills, statements, orders, offers). Such a
     * message is ignored instead of asking the person "did you receive this?" -- bank SMS apps carry many of them.
     */
    private val notPaymentHints = listOf("bill ", "bill of", "statement", "minimum", "limit", "premium", "policy", "order",
        "delivered", "shipped", "invoice", "generated", "plan", "validity", "data pack", "renew", "subscription", "fine",
        "challan", "penalty", "charges", "fee ", "interest", "sale", "% off", "save ", "upto", "up to")
    private val refRegex = Regex(
        """\b(?:utr|upi\s*ref(?:erence)?|ref(?:erence)?|txn|transaction|upi)\s*(?:id|no\.?|number)?\s*[:#.\-/]?\s*([A-Za-z0-9]{6,40})""",
        RegexOption.IGNORE_CASE,
    )

    /**
     * [moreIncoming] / [moreReject]: extra phrases the server sends (no app update needed for new wording).
     * [learnedIn] / [learnedOut]: message templates this person confirmed as received / sent on this phone.
     */
    fun parse(
        title: String?,
        text: String?,
        moreIncoming: Collection<String> = emptyList(),
        moreReject: Collection<String> = emptyList(),
        learnedIn: Collection<String> = emptyList(),
        learnedOut: Collection<String> = emptyList(),
    ): Result {
        val joined = withoutBoilerplate(listOfNotNull(title, text).joinToString(" ").replace('\n', ' ').trim())
        if (joined.isEmpty()) return Result.Ignored
        val body = text?.let { withoutBoilerplate(it.replace('\n', ' ')) }
        val lower = " ${joined.lowercase()} "
        val shape = template(body)
        if (shape.isNotEmpty() && learnedOut.any { it.isNotEmpty() && shape.contains(it) }) return Result.Ignored
        val learned = shape.isNotEmpty() && learnedIn.any { it.isNotEmpty() && shape.contains(it) }
        val rejected = (reject + moreReject).any { it.isNotEmpty() && lower.contains(it.lowercase()) }
        if (!learned && (incoming + moreIncoming).none { it.isNotEmpty() && lower.contains(it.lowercase()) }) {
            if (rejected) return outgoingOrIgnored(joined, lower, body, title)
            val only = paymentAmounts(joined).toSet()
            // "Paid ₹10 to Bhagya": clear outgoing wording with a payee is a debit, not a question for the person.
            val payee = payeeName(body) ?: payeeName(title)
            if (payee != null && only.size == 1) return Result.Outgoing(only.first(), payee, accountTail(joined))
            // HDFC / Kotak style debit SMS: "Sent Rs.100.00 From HDFC Bank A/C *1234 To RAMESH On 15/11/26".
            if (sentFrom.containsMatchIn(joined) && only.isNotEmpty()) {
                return Result.Outgoing(only.first(), payeeName(body) ?: payeeName(title), accountTail(joined))
            }
            if (notPaymentHints.any { lower.contains(it) }) return Result.Ignored
            return if (only.size == 1 && shape.contains("₹#") && shape.length >= 8) Result.Unknown(only.first(), shape)
            else Result.Ignored
        }
        if (!learned && rejected) return outgoingOrIgnored(joined, lower, body, title)
        // Owner 2026-11-15 ("clear cut"): bank apps add the account BALANCE ("Avl Bal Rs.5,230"); that is never the
        // payment. The payment is the FIRST amount that is not a balance (banks write the credited amount first).
        val amounts = paymentAmounts(joined)
        if (amounts.isEmpty()) return Result.Ambiguous("amount_missing")
        val reference = refRegex.findAll(joined).map { it.groupValues[1] }.firstOrNull { it.count(Char::isDigit) >= 6 }
        return Result.Accepted(amounts.first(), reference, payerName(body) ?: payerName(title), accountTail(joined))
    }

    private val sentFrom = Regex("""\bsent\s+$AMT\s+from\b""", RegexOption.IGNORE_CASE)

    private val debitWords = listOf("debited", "you paid", "you sent", "paid to", "sent to", "withdrawn", "spent")
    private val notMoney = listOf("request", "collect", "otp", "one time", "failed", "declined", "unsuccessful", "pending",
        "refund", "reversed", "due", "reminder", "cashback", "reward", "offer", "coupon", "scratch", "verification code",
        "password", "pin ", "loan", "emi", "recharge", "bill pay")

    /** Clear "money went out" wording with exactly one amount -> Outgoing; everything else stays ignored. */
    private fun outgoingOrIgnored(joined: String, lower: String, text: String?, title: String?): Result {
        if (debitWords.none { lower.contains(it) } || notMoney.any { lower.contains(it) }) return Result.Ignored
        val amounts = paymentAmounts(joined)
        if (amounts.isEmpty()) return Result.Ignored
        return Result.Outgoing(amounts.first(), payeeName(text) ?: payeeName(title), accountTail(joined))
    }

    private const val END = """(?:\s+(?:on|via|in|from|using|ref|refno|upi|utr|at|thru|through|avl|bal)\b|[,!;(]|\.(?=\s|$|\(|(?-i:[A-Z]))|$)"""
    private val payeePatterns = listOf(
        Regex("""(?:paid|sent)\s+$AMT\s+to\s+(.{2,60}?)$END""", RegexOption.IGNORE_CASE),
        Regex("""you\s+(?:paid|sent)\s+$AMT\s+to\s+(.{2,60}?)$END""", RegexOption.IGNORE_CASE),
        Regex("""(?:paid|sent)\s+to\s+(.{2,60}?)$END""", RegexOption.IGNORE_CASE),
        Regex("""(?:trf|transfer(?:red)?|upi)\s+to\s+(.{2,60}?)$END""", RegexOption.IGNORE_CASE),
        Regex("""\bsent\s+$AMT\s+from\s+.{0,60}?\s+to\s+(\S.{1,60}?)$END""", RegexOption.IGNORE_CASE), // HDFC / Kotak SMS
        Regex(""";\s*([A-Za-z][A-Za-z .]{1,40}?)\s+credited""", RegexOption.IGNORE_CASE),            // ICICI debit SMS
        Regex("""upi/p2[am]/\d+/([A-Za-z][A-Za-z .]{1,40}?)(?:/|$END)""", RegexOption.IGNORE_CASE),     // Axis
    )

    /** Who the money went to (spoken only on this phone, letters only, never stored in the upload). */
    fun payeeName(text: String?): String? = nameFrom(payeePatterns, text)

    /**
     * The first clean person / shop name any pattern finds. A UPI id gives its letters part ("ramesh@ybl" ->
     * "ramesh"); numbers, ids and bank words are never a name.
     */
    private fun nameFrom(patterns: List<Regex>, text: String?): String? {
        val t = (text ?: "").replace('\n', ' ').trim()
        if (t.isEmpty()) return null
        for (re in patterns) {
            for (m in re.findAll(t)) {
                var name = m.groupValues[1].trim().trim('.', ',', '!', ':', '-', '\'', '"', '(', ')').replace(Regex("\\s+"), " ")
                if (name.contains('@')) {
                    val local = name.substringBefore('@').substringAfterLast(' ')
                    name = local.replace(Regex("[._-]+"), " ").trim()
                    if (name.any(Char::isDigit) || name.length < 3) continue
                }
                if (name.length < 2 || name.length > 40) continue
                if (name.any { it.isDigit() || it == '@' || it == '₹' || it == '/' }) continue
                if (name.split(' ').size > 4) continue
                if (name.lowercase().split(' ').any { it in notAName }) continue
                return name
            }
        }
        return null
    }

    private val accountRegex = Regex(
        """(?:a/c|acct?|account|\bac\b)\s*(?:no\.?|number)?\s*[:.\-]?\s*[xX*.]*\s*(\d{3,4})\b""",
        RegexOption.IGNORE_CASE,
    )

    /** Last 3-4 digits of the account a bank SMS names ("A/c XX1234" -> "1234"); never more than that. */
    fun accountTail(text: String?): String? = accountRegex.find(text ?: "")?.groupValues?.get(1)

    private val balanceBefore = Regex(
        """(?:bal(?:ance)?|avl|avail(?:able)?|a/c\s*bal|closing)\s*(?:bal(?:ance)?)?\s*(?:is|:|-|of)?\s*$""",
        RegexOption.IGNORE_CASE,
    )

    /** Amounts in the message in order, without balances (the words just before the amount say "bal" etc.). */
    fun paymentAmounts(joined: String): List<Long> {
        val withCurrency = amountRegex.findAll(joined).mapNotNull { m ->
            val before = joined.substring(maxOf(0, m.range.first - 24), m.range.first)
            if (balanceBefore.containsMatchIn(before)) null else toPaise(m.groupValues[1])
        }.filter { it > 0 }.distinct().toList()
        if (withCurrency.isNotEmpty()) return withCurrency
        // "debited by 20.0" (SBI and others write no Rs / INR): only right after credited / debited by|with|for.
        return bareBankAmount.findAll(joined).mapNotNull { toPaise(it.groupValues[1]) }.filter { it > 0 }.distinct().toList()
    }

    private const val AMT = """(?:₹|rs[.:]?|inr[.:]?)\s*[0-9][0-9,]*(?:\.[0-9]{1,2})?"""
    private val payerPatterns = listOf(
        Regex("""^\s*(.{2,60}?)\s+(?:has\s+)?sent\s+$AMT\s+to\s+you""", RegexOption.IGNORE_CASE),   // PhonePe
        Regex("""^\s*(.{2,60}?)\s+(?:has\s+)?paid\s+you\s+$AMT""", RegexOption.IGNORE_CASE),          // Google Pay
        Regex("""^\s*(.{2,60}?)\s+has\s+sent\s+you\s+$AMT""", RegexOption.IGNORE_CASE),
        Regex("""received\s+$AMT\s+from\s+(.{2,60}?)(?:\s+(?:on|via|in|to|at)\b|[.,!]|$)""", RegexOption.IGNORE_CASE), // Paytm
        Regex("""upi/p2[am]/\d+/([A-Za-z][A-Za-z .]{1,40}?)(?:/|$END)""", RegexOption.IGNORE_CASE),     // Axis
        Regex("""$AMT\s+received\s+from\s+(.{2,60}?)(?:\s+(?:on|via|in|to|at)\b|[.,!]|$)""", RegexOption.IGNORE_CASE),
        // MUST stay last (payerName applies it only to the text after the credit word).
        // Bank SMS: "... by|from NAME" anywhere AFTER the credit word (payerName passes only that part).
        Regex("""(?:^|\s)(?:by|from)\s+(?:upi\s*[-/:]?\s*|(?:a/c\s+linked\s+to\s+)?vpa\s+)?([A-Za-z][A-Za-z0-9 .@_-]{1,50}?)$END""", RegexOption.IGNORE_CASE),
    )
    private val notAName = setOf("you", "upi", "bank", "account", "a/c", "your", "someone", "phonepe", "paytm", "google",
        "gpay", "bhim", "money", "payment", "received", "ref", "neft", "imps", "utr", "rtgs", "txn", "transfer", "rs", "inr",
        "mob", "bk", "vpa", "linked", "mobile", "cash", "atm", "branch", "cheque", "clearing", "interest", "salary", "of")

    /**
     * The payer's display name from an incoming-payment message ("Bhagya sent ₹30 to you" -> "Bhagya"), or null.
     * Letters only: anything with a digit or @ (a number / UPI id) is never returned.
     */
    fun payerName(text: String?): String? {
        val t = text ?: return null
        // Bank SMS name the payer after the credit word ("credited ... by RAMESH"); a "by" before it ("debited by")
        // is never the payer. App messages keep the whole text (their names come first: "Bhagya sent ₹1 to you").
        val at = creditWord.find(t)?.range?.last
        val bankPart = if (at != null) t.substring(at + 1) else null
        return nameFrom(payerPatterns.dropLast(1), t) ?: bankPart?.let { nameFrom(listOf(payerPatterns.last()), it) }
    }

    private val creditWord = Regex("""\b(?:credited|credit|received|deposited)\b""", RegexOption.IGNORE_CASE)

    fun toPaise(raw: String): Long? {
        val clean = raw.replace(",", "")
        if (clean.isEmpty()) return null
        val parts = clean.split('.')
        val rupees = parts[0].toLongOrNull() ?: return null
        val paise = if (parts.size > 1) parts[1].padEnd(2, '0').take(2).toLongOrNull() ?: 0 else 0
        val total = rupees * 100 + paise
        return if (total in 1..1_000_000_000L) total else null
    }

    /** The whole sentence (device voice, or when the cloud voice is not reachable). */
    fun announcement(amountPaise: Long?, language: String, test: Boolean = false, payer: String? = null,
                     shop: String? = null): String = announcementParts(amountPaise, language, test, payer, shop).joinToString(" ")

    /**
     * Personal phone (no shop): who credited / debited and how much -- plain facts, no shop thank-you.
     * [credit] false = money left the account (announced only when the person turned debit alerts on).
     */
    fun personalParts(amountPaise: Long, language: String, credit: Boolean, party: String?): List<String> {
        val rupees = amountPaise / 100
        val paise = amountPaise % 100
        val who = party?.trim()?.takeIf { it.isNotEmpty() }
        val money = when (language) {
            "te" -> "$rupees రూపాయలు" + (if (paise > 0) " $paise పైసలు" else "")
            "hi" -> "$rupees रुपये" + (if (paise > 0) " $paise पैसे" else "")
            "en" -> "$rupees rupees" + (if (paise > 0) " $paise paise" else "")
            else -> {
                // Any other language: its own rupee / paise words from the same table the shop thank-you uses.
                val w = WORDS[language] ?: WORDS["en_fallback"]!!
                w.rupees.replace("{n}", rupees.toString()) + (if (paise > 0) " " + w.paise.replace("{n}", paise.toString()) else "")
            }
        }
        // Owner 2026-11-16: say credit / debit in the person's OWN language ("జమ అయ్యాయి" / "వెళ్ళాయి"), not the
        // English words in local letters. Other languages: ONE table row (credit, debit; {who} / {money}).
        return when (language) {
            "te" -> if (credit) listOf(if (who != null) "$who నుండి" else "", "$money జమ అయ్యాయి.")
                    else listOf(if (who != null) "$who కి" else "", "$money " + (if (who != null) "వెళ్ళాయి." else "ఖాతా నుండి వెళ్ళాయి."))
            "hi" -> if (credit) listOf(if (who != null) "$who से" else "", "$money जमा हुए।")
                    else listOf(if (who != null) "$who को" else "", "$money " + (if (who != null) "गए।" else "खाते से कटे।"))
            "en" -> if (credit) listOf(if (who != null) "$who sent" else "Received", "$money.")
                    else listOf("Spent", "$money" + (if (who != null) " to $who." else "."))
            else -> {
                val row = PERSONAL[language]
                if (row == null) {
                    if (credit) listOf(if (who != null) "$who sent" else "Received", "$money.")
                    else listOf("Spent", "$money" + (if (who != null) " to $who." else "."))
                } else {
                    val t = if (credit) (if (who != null) row[0] else row[1]) else (if (who != null) row[2] else row[3])
                    listOf(t.replace("{who}", who ?: "").replace("{money}", money))
                }
            }
        }.filter { it.isNotEmpty() }
    }

    /** language -> [credit with name, credit, debit with name, debit] (spoken for "My phone"). */
    private val PERSONAL: Map<String, List<String>> = mapOf(
        "ta" to listOf("{who} இடமிருந்து {money} வந்தது.", "{money} வரவு ஆனது.", "{who}-க்கு {money} சென்றது.", "{money} கணக்கிலிருந்து சென்றது."),
        "kn" to listOf("{who} ಅವರಿಂದ {money} ಬಂದಿದೆ.", "{money} ಜಮೆ ಆಗಿದೆ.", "{who} ಅವರಿಗೆ {money} ಹೋಗಿದೆ.", "{money} ಖಾತೆಯಿಂದ ಹೋಗಿದೆ."),
        "ml" to listOf("{who}-ൽ നിന്ന് {money} ലഭിച്ചു.", "{money} വരവ് വച്ചു.", "{who}-ന് {money} പോയി.", "{money} അക്കൗണ്ടിൽ നിന്ന് പോയി."),
        "bn" to listOf("{who}-এর কাছ থেকে {money} এসেছে।", "{money} জমা হয়েছে।", "{who}-কে {money} গেছে।", "{money} অ্যাকাউন্ট থেকে গেছে।"),
        "mr" to listOf("{who} कडून {money} मिळाले.", "{money} जमा झाले.", "{who} ला {money} गेले.", "{money} खात्यातून गेले."),
        "gu" to listOf("{who} તરફથી {money} મળ્યા.", "{money} જમા થયા.", "{who} ને {money} ગયા.", "{money} ખાતામાંથી ગયા."),
        "pa" to listOf("{who} ਤੋਂ {money} ਮਿਲੇ।", "{money} ਜਮ੍ਹਾ ਹੋਏ।", "{who} ਨੂੰ {money} ਗਏ।", "{money} ਖਾਤੇ ਵਿੱਚੋਂ ਗਏ।"),
        "or" to listOf("{who}ଙ୍କ ଠାରୁ {money} ମିଳିଲା।", "{money} ଜମା ହେଲା।", "{who}ଙ୍କୁ {money} ଗଲା।", "{money} ଖାତାରୁ ଗଲା।"),
        "ur" to listOf("{who} سے {money} موصول ہوئے۔", "{money} جمع ہوئے۔", "{who} کو {money} گئے۔", "{money} اکاؤنٹ سے گئے۔"),
    )

    private val BUSINESS_WORDS = Regex(
        """(?i)\b(shop|store|stores|mart|traders?|trading|enterprises?|agencies|agency|hotel|restaurant|mess|bakery|medicals?|pharmacy|"""
            + """clinic|hospital|garage|motors?|electricals?|electronics|textiles?|cloth|fashions?|jewell?ers?|jewell?ery|supermarket|"""
            + """provisions?|kirana|general|centre|center|services?|solutions|company|co|ltd|pvt|llp|brothers|bros|sons|and sons|&)\b|"""
            + """(షాప్|స్టోర్|మార్ట్|ట్రేడర్స్|ఎంటర్ప్రైజెస్|హోటల్|మెడికల్స్|మెడికల్|బ్రదర్స్)""")

    /** Owner 2026-11-15: "please visit again" only to a SHOP; a person's name just gets the thanks. */
    fun looksLikeBusiness(name: String?): Boolean = name != null && BUSINESS_WORDS.containsMatchIn(name)

    /**
     * The thank-you the shop speaks to the customer (owner 2026-11-13): "Thank you <name> garu, 30 rupees reached
     * <shop>, thank you, please come again". Split into parts so the cloud voice can keep the parts that never
     * change (the closing line, the shop part) on the phone and fetch only the name / amount parts once each.
     */
    fun announcementParts(amountPaise: Long?, language: String, test: Boolean = false, payer: String? = null,
                          shop: String? = null): List<String> {
        val parts = mutableListOf<String>()
        val words = WORDS[language]
        if (test) parts += when (language) { "te" -> "టెస్ట్."; "hi" -> "टेस्ट।"; "en" -> "Test."; else -> words?.test ?: "Test." }
        if (amountPaise == null) {
            parts += when (language) {
                "te" -> "పేమెంట్ నోటిఫికేషన్ వచ్చింది, కానీ మొత్తం స్పష్టంగా లేదు. యాప్‌లో చూడండి."
                "hi" -> "पेमेंट नोटिफिकेशन आया, पर रकम साफ़ नहीं है। ऐप में देखें।"
                "en" -> "A payment notification arrived but the amount is not clear. Please check the app."
                else -> words?.unclear ?: "A payment notification arrived but the amount is not clear. Please check the app."
            }
            return parts
        }
        val rupees = amountPaise / 100
        val paise = amountPaise % 100
        val name = payer?.trim()?.takeIf { it.isNotEmpty() }
        val place = shop?.trim()?.take(40)?.takeIf { it.isNotEmpty() }
        val again = looksLikeBusiness(name)
        when (language) {
            "te" -> {
                parts += if (name != null) "థ్యాంక్ యూ $name గారు." else "థ్యాంక్ యూ."
                parts += "$rupees రూపాయలు" + (if (paise > 0) " $paise పైసలు" else "")
                parts += if (place != null) "$place కి అందాయి." else "మాకు అందాయి."
                if (again) parts += "ధన్యవాదాలు, మళ్ళీ విచ్చేయండి."
            }
            "hi" -> {
                parts += if (name != null) "धन्यवाद $name जी।" else "धन्यवाद।"
                parts += "$rupees रुपये" + (if (paise > 0) " $paise पैसे" else "")
                parts += if (place != null) "$place को मिल गए।" else "हमें मिल गए।"
                if (again) parts += "फिर से पधारिए।"
            }
            "en" -> {
                parts += if (name != null) "Thank you $name." else "Thank you."
                parts += "$rupees rupees" + (if (paise > 0) " $paise paise" else "")
                parts += if (place != null) "received at $place." else "received."
                if (again) parts += "Please visit again."
            }
            else -> {
                val w = words ?: WORDS.getValue("en_fallback")
                parts += if (name != null) w.thanksName.replace("{name}", name) else w.thanks
                parts += w.rupees.replace("{n}", "$rupees") + (if (paise > 0) " " + w.paise.replace("{n}", "$paise") else "")
                parts += if (place != null) w.reachedAt.replace("{place}", place) else w.reached
                if (again) parts += w.again
            }
        }
        return parts
    }

    /** The same thank-you in the other Indian languages the ElevenLabs voices speak (owner 2026-11-14: "all languages"). */
    private class Words(
        val test: String, val unclear: String, val thanksName: String, val thanks: String, val rupees: String,
        val paise: String, val reachedAt: String, val reached: String, val again: String,
    )

    private val WORDS: Map<String, Words> = mapOf(
        "en_fallback" to Words("Test.", "A payment notification arrived but the amount is not clear. Please check the app.",
            "Thank you {name}.", "Thank you.", "{n} rupees", "{n} paise", "received at {place}.", "received.", "Please visit again."),
        "ta" to Words("சோதனை.", "பணம் வந்ததாக அறிவிப்பு வந்தது, ஆனால் தொகை தெளிவாக இல்லை. ஆப்பில் பாருங்கள்.",
            "நன்றி {name} அவர்களே.", "நன்றி.", "{n} ரூபாய்", "{n} பைசா", "{place}-க்கு வந்துவிட்டது.", "எங்களுக்கு வந்துவிட்டது.", "மீண்டும் வாருங்கள்."),
        "kn" to Words("ಪರೀಕ್ಷೆ.", "ಪಾವತಿ ಸೂಚನೆ ಬಂದಿದೆ, ಆದರೆ ಮೊತ್ತ ಸ್ಪಷ್ಟವಾಗಿಲ್ಲ. ಆ್ಯಪ್‌ನಲ್ಲಿ ನೋಡಿ.",
            "ಧನ್ಯವಾದಗಳು {name} ಅವರೇ.", "ಧನ್ಯವಾದಗಳು.", "{n} ರೂಪಾಯಿ", "{n} ಪೈಸೆ", "{place} ಗೆ ತಲುಪಿದೆ.", "ನಮಗೆ ತಲುಪಿದೆ.", "ಮತ್ತೆ ಬನ್ನಿ."),
        "ml" to Words("പരീക്ഷണം.", "പേയ്‌മെന്റ് അറിയിപ്പ് വന്നു, പക്ഷേ തുക വ്യക്തമല്ല. ആപ്പിൽ നോക്കൂ.",
            "നന്ദി {name}.", "നന്ദി.", "{n} രൂപ", "{n} പൈസ", "{place}-ൽ ലഭിച്ചു.", "ഞങ്ങൾക്ക് ലഭിച്ചു.", "വീണ്ടും വരൂ."),
        "bn" to Words("পরীক্ষা।", "পেমেন্টের নোটিফিকেশন এসেছে, কিন্তু টাকার পরিমাণ পরিষ্কার নয়। অ্যাপে দেখুন।",
            "ধন্যবাদ {name}।", "ধন্যবাদ।", "{n} টাকা", "{n} পয়সা", "{place}-এ পৌঁছেছে।", "আমাদের কাছে পৌঁছেছে।", "আবার আসবেন।"),
        "mr" to Words("चाचणी.", "पेमेंटची सूचना आली, पण रक्कम स्पष्ट नाही. ॲपमध्ये पहा.",
            "धन्यवाद {name}.", "धन्यवाद.", "{n} रुपये", "{n} पैसे", "{place} ला मिळाले.", "आम्हाला मिळाले.", "पुन्हा या."),
        "gu" to Words("ટેસ્ટ.", "પેમેન્ટની સૂચના આવી, પણ રકમ સ્પષ્ટ નથી. એપમાં જુઓ.",
            "આભાર {name}.", "આભાર.", "{n} રૂપિયા", "{n} પૈસા", "{place} ને મળ્યા.", "અમને મળ્યા.", "ફરી પધારજો."),
        "pa" to Words("ਟੈਸਟ।", "ਭੁਗਤਾਨ ਦੀ ਸੂਚਨਾ ਆਈ, ਪਰ ਰਕਮ ਸਾਫ਼ ਨਹੀਂ ਹੈ। ਐਪ ਵਿੱਚ ਦੇਖੋ।",
            "ਧੰਨਵਾਦ {name} ਜੀ।", "ਧੰਨਵਾਦ।", "{n} ਰੁਪਏ", "{n} ਪੈਸੇ", "{place} ਨੂੰ ਮਿਲ ਗਏ।", "ਸਾਨੂੰ ਮਿਲ ਗਏ।", "ਫਿਰ ਆਇਓ।"),
        "or" to Words("ପରୀକ୍ଷା।", "ପେମେଣ୍ଟ ସୂଚନା ଆସିଛି, କିନ୍ତୁ ରାଶି ସ୍ପଷ୍ଟ ନାହିଁ। ଆପ୍‌ରେ ଦେଖନ୍ତୁ।",
            "ଧନ୍ୟବାଦ {name}।", "ଧନ୍ୟବାଦ।", "{n} ଟଙ୍କା", "{n} ପଇସା", "{place} କୁ ପହଞ୍ଚିଛି।", "ଆମ ପାଖରେ ପହଞ୍ଚିଛି।", "ପୁଣି ଆସନ୍ତୁ।"),
        "ur" to Words("ٹیسٹ۔", "ادائیگی کی اطلاع آئی ہے، لیکن رقم واضح نہیں ہے۔ ایپ میں دیکھیں۔",
            "شکریہ {name} جی۔", "شکریہ۔", "{n} روپے", "{n} پیسے", "{place} کو مل گئے۔", "ہمیں مل گئے۔", "دوبارہ تشریف لائیں۔"),
    )

    /** True when "HH:mm" now falls inside [start, end) (overnight ranges allowed). Empty = never quiet. */
    fun inQuietHours(start: String, end: String, minuteOfDay: Int): Boolean {
        fun parse(v: String): Int? {
            val p = v.split(':')
            if (p.size != 2) return null
            val h = p[0].toIntOrNull() ?: return null
            val m = p[1].toIntOrNull() ?: return null
            return if (h in 0..23 && m in 0..59) h * 60 + m else null
        }
        val s = parse(start) ?: return false
        val e = parse(end) ?: return false
        if (s == e) return false
        return if (s < e) minuteOfDay in s until e else minuteOfDay >= s || minuteOfDay < e
    }

    // ------------------------------------------------------------------ one payment, several messages (owner 2026-11-17)
    /**
     * A bank / company SMS comes from a REGISTERED sender ID ("JD-HDFCBK-S", "AD-SBIINB-T", "VM-ICICIT"): two letters,
     * a dash, the registered name, and (TRAI 2025) -S service / -T transactional / -G government. A person's number or a
     * promotional (-P) sender is never a bank confirmation.
     */
    fun isBankSender(title: String?): Boolean {
        val t = title?.trim()?.uppercase(Locale.ROOT) ?: return false
        return Regex("""^[A-Z]{2}-[A-Z0-9]{3,9}(-[STG])?$""").matches(t)
    }

    /** "*2317@ibl" / "9502072317@ibl" -> "2317@ibl": the payer's UPI handle tail, to tell two payments apart. */
    fun upiHandleTail(text: String): String? =
        Regex("""[A-Za-z0-9.*_\-]*?(\d{4})@([A-Za-z]{2,20})""").find(text)?.let { "${it.groupValues[1]}@${it.groupValues[2].lowercase(Locale.ROOT)}" }

    /** The UPI app / bank app notification may come up to an hour AFTER the bank SMS of the same payment ... */
    const val NOTE_AFTER_SMS_MS = 60 * 60_000L
    /** ... but a bank SMS is quick: it is the same payment only when it comes within 10 minutes of the notification. */
    const val SMS_AFTER_NOTE_MS = 10 * 60_000L
    /** Two notifications of different kinds (a UPI app + the bank's own app) of one payment. */
    const val NOTE_AND_NOTE_MS = 30 * 60_000L

    /**
     * Can a message of [kind] (sms / upi / bank) be the same payment as an earlier row made of [rowKinds], when its
     * payment time is [deltaMs] after the row's (negative = before)? A kind the row already has never joins it
     * (two SMS = two payments).
     */
    fun samePaymentWindow(kind: String, rowKinds: List<String>, deltaMs: Long): Boolean = when {
        kind in rowKinds -> false
        kind == "sms" -> deltaMs in -NOTE_AFTER_SMS_MS..SMS_AFTER_NOTE_MS   // this SMS vs the row's notification
        "sms" in rowKinds -> deltaMs in -SMS_AFTER_NOTE_MS..NOTE_AFTER_SMS_MS // this notification vs the row's SMS
        else -> kotlin.math.abs(deltaMs) <= NOTE_AND_NOTE_MS
    }

    // ------------------------------------------------------------------ dues, EMI, balance (owner 2026-11-17)

    data class Due(val amountPaise: Long, val dueDate: String, val label: String)

    private val months = listOf("jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec")

    private fun rupees(s: String): Long? = s.replace(",", "").toBigDecimalOrNull()?.movePointRight(2)?.toLong()

    /**
     * A bill / EMI REMINDER (not a payment): "Due date for Andhra Pradesh … ₹1,941.00 due on Nov 21, 2026", "EMI of
     * Rs 2,500 is due on 05-12-2026", "Bill of Rs.821 due by 21/11/2026". Returns the amount, the date (yyyy-MM-dd) and a
     * short label from the title, or null.
     */
    fun dueReminder(title: String?, text: String?, year: Int = java.util.Calendar.getInstance().get(java.util.Calendar.YEAR)): Due? {
        val body = "${title ?: ""} ${text ?: ""}".replace('\n', ' ')
        val low = body.lowercase(Locale.ROOT)
        if (!Regex("""\b(due|payable|pay by|last date)\b""").containsMatchIn(low)) return null
        if (Regex("""\b(credited|received|debited|paid|sent you|successful)\b""").containsMatchIn(low)) return null
        val amt = Regex("""(?:₹|rs\.?|inr)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)""").find(low)?.groupValues?.get(1)?.let(::rupees) ?: return null
        if (amt <= 0) return null
        var date: String? = null
        Regex("""\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?\s+(\d{1,2})(?:,?\s*(\d{4}))?""").find(low)?.let { m ->
            val mo = months.indexOf(m.groupValues[1]) + 1
            date = "%04d-%02d-%02d".format(m.groupValues[3].toIntOrNull() ?: year, mo, m.groupValues[2].toInt())
        }
        if (date == null) Regex("""\b(\d{1,2})\s+(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?(?:,?\s*(\d{4}))?""").find(low)?.let { m ->
            val mo = months.indexOf(m.groupValues[2]) + 1
            date = "%04d-%02d-%02d".format(m.groupValues[3].toIntOrNull() ?: year, mo, m.groupValues[1].toInt())
        }
        if (date == null) Regex("""\b(\d{1,2})[-/.](\d{1,2})[-/.](\d{2,4})\b""").find(low)?.let { m ->
            val y = m.groupValues[3].toInt().let { if (it < 100) 2000 + it else it }
            date = "%04d-%02d-%02d".format(y, m.groupValues[2].toInt(), m.groupValues[1].toInt())
        }
        val d = date ?: return null
        val label = (title ?: "").replace(Regex("""(?i)^due date for\s+"""), "").trim().take(60).ifEmpty { "Bill" }
        return Due(amt, d, label)
    }

    /** A debit that is an EMI / auto-debit / mandate (so the app can offer "add as a monthly EMI"). */
    fun isEmi(text: String?): Boolean =
        Regex("""(?i)\b(emi|nach|e-?nach|ach\s*d[r]|auto[- ]?debit|mandate|si\s+debit|standing instruction|loan a/?c)\b""").containsMatchIn(text ?: "")

    /** "Avl Bal Rs 32,140.00" / "Available balance: INR 1,234.50" / "Bal: Rs.500" -> paise, or null. */
    fun availableBalance(text: String?): Long? {
        val m = Regex("""(?i)\b(?:avl\.?\s*bal(?:ance)?|available\s+bal(?:ance)?|a/c\s+bal(?:ance)?|bal(?:ance)?)\s*(?:is|:|-)?\s*(?:₹|rs\.?|inr)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)""").find(text ?: "")
        return m?.groupValues?.get(1)?.let(::rupees)
    }
}
