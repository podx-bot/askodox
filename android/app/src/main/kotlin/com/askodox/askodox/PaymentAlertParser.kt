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
                            val account: String? = null, val refund: Boolean = false,
                            /** Owner 2026-11-22: "cashback" / "interest" that LANDED in the account (spoken as such). */
                            val bonus: String? = null) : Result()
        data class Ambiguous(val reason: String) : Result()

        /**
         * A payment-app message with ONE amount whose wording is neither known incoming nor known outgoing: the
         * phone asks the person once ("did you receive this?"). [template] is the message with the amount
         * replaced by ₹# (title / names never kept).
         */
        data class Unknown(val amountPaise: Long, val template: String) : Result()
        object Ignored : Result()

        /**
         * Money that LEFT the person's account (debited / paid to / sent to). Never uploaded; spoken only if asked.
         * [doubtful]: the message ALSO says money came in and has no strong debit word ("debited", "you paid", ...),
         * e.g. a PhonePe line with "received" and "sent to" (owner 2026-11-21, Rs 3,000 read as minus): the row shows ❓
         * and the person can correct it.
         */
        data class Outgoing(val amountPaise: Long, val party: String?, val account: String?,
                            val doubtful: Boolean = false, val biller: Boolean = false,
                            /** A bill / service payment that is DONE ("Bill Paid!", "bill payment successful"). */
                            val bill: Boolean = false,
                            /** The message names the person's OWN account as the source ("from HDFC Bank Account XX1234"). */
                            val ownAccount: Boolean = false) : Result()
    }

    /**
     * Owner 2026-11-21 (Rs 3,000 received, shown as minus): "sent to your bank account" / "paid to your a/c" /
     * "credited to your account" is money coming TO the person -- the outgoing words "sent to" / "paid to" must not
     * count there. Used only for the reject / debit checks; the incoming check still sees " to you".
     */
    fun rejectView(lower: String): String =
        Regex("""\b(sent|paid|transferred|transfer|trf|credited|added|deposited|moved)\s+to\s+(?=your?\b)""").replace(lower, "$1 into ")

    /** Words that make a debit certain even when the message also has incoming words (ICICI: "debited ...; X credited"). */
    private val strongDebit = listOf("debited", "withdrawn", "spent", "you paid", "you sent", "you have paid", "you have sent")

    /**
     * The words of a message that say WHAT kind of message it is, without names, numbers or ids: the key a person's
     * correction ("this came in" / "this went out" / "not a payment") is learned under, so the next message of the
     * same kind from ANY person / amount is read the same way.
     */
    fun skeleton(text: String?): String {
        val t = template(withoutBoilerplate((text ?: "").replace('\n', ' ')))
        val words = Regex("""₹#|[a-z/]+|[\u0900-\u0DFF]+""").findAll(t).map { it.value }.filter { it == "₹#" || it in SKELETON_WORDS }
        return words.joinToString(" ")
    }

    private val SKELETON_WORDS = setOf(
        "received", "receive", "credited", "credit", "debited", "debit", "sent", "send", "paid", "pay", "payment", "to",
        "you", "your", "from", "by", "in", "into", "of", "has", "have", "money", "successfully", "successful", "bank",
        "account", "a/c", "ac", "acct", "upi", "transferred", "transfer", "trf", "added", "wallet", "balance", "avl", "bal",
        "is", "was", "on", "via", "for", "at", "done", "completed", "linked", "sbi", "hdfc", "icici", "axis", "kotak", "phonepe",
        "gpay", "paytm", "bhim", "vpa", "towards", "withdrawn", "spent", "deposited", "refund", "cashback", "request",
        "జమ", "అందింది", "అందాయి", "పంపారు", "చెల్లించారు",
    )

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
        // Owner 2026-11-21: "initiated" / "processing" = NOT done yet (no money moved); shown as a notice, never spoken.
        "initiated", "processing", "in process", "under process", "in progress", "scheduled", "will be credited",
        "will be debited", "will be deducted", "will reflect",
        // Owner 2026-11-22 ("refunds, credits, cancel, generated ... read those words too"): a cancelled payment is a
        // notice that is explained (and spoken when the person keeps that kind on), never money received.
        " cancelled", " canceled",
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
        "challan", "penalty", "charges", "fee ", "interest", "sale", "% off", "save ", "upto", "up to",
        // Owner 2026-11-22 ("etc."): autopay / mandate / standing-instruction notices of every bank and app -- not done yet.
        "will be processed", "will be charged", "will be auto", "will be paid", "will be collected", "will be presented",
        "will be executed", "will be recovered")
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
        learnedKinds: Map<String, String> = emptyMap(),
    ): Result {
        val joined = withoutBoilerplate(listOfNotNull(title, text).joinToString(" ").replace('\n', ' ').trim())
        if (joined.isEmpty()) return Result.Ignored
        // Owner 2026-11-23: a payment app's SUMMARY of several transactions is never ONE payment (the amount of one
        // line + the name of another was spoken as money sent). The phone reads each line alone -- see [digestLines].
        if (digestLines(title, text).size >= 2) return Result.Ignored
        val body = text?.let { withoutBoilerplate(it.replace('\n', ' ')) }
        val lower = " ${joined.lowercase()} "
        val shape = template(body)
        // A correction the person made on a row of this kind of message (any name / amount) decides first.
        val corrected = skeleton(body ?: joined).takeIf { it.split(' ').size >= 3 }?.let { learnedKinds[it] }
        if (corrected == "none") return Result.Ignored
        if (corrected == "out") {
            val amounts = paymentAmounts(joined)
            return if (amounts.isEmpty()) Result.Ignored
            else Result.Outgoing(amounts.first(), payeeName(body) ?: payeeName(title), accountTail(joined))
        }
        if (shape.isNotEmpty() && learnedOut.any { it.isNotEmpty() && shape.contains(it) }) return Result.Ignored
        // Owner 2026-11-21 (Airtel bill paid -> the voice said "3081 received"): a company THANKING you for your payment
        // ("Thank you for the payment of Rs 3081 for your Airtel number", "we have received your payment") is money YOU
        // paid -- never money that came in, even though it says "payment of" / "received".
        if (corrected != "in" && (billerAck.containsMatchIn(joined) ||
                (serviceAck.containsMatchIn(joined) && !fromOther.containsMatchIn(joined)))) {
            val amounts = paymentAmounts(joined)
            return if (amounts.isEmpty()) Result.Ignored
            else Result.Outgoing(amounts.first(), billerName(title), accountTail(joined), biller = true)
        }
        val learned = corrected == "in" || (shape.isNotEmpty() && learnedIn.any { it.isNotEmpty() && shape.contains(it) })
        // Owner 2026-11-22 (fake "DEPOSIT SUCCESS ... Rs.8,551,00" said as ₹8,55,100 received): a fake-looking "money came"
        // message is never money -- not even when an earlier confirmed wording matches; only "wrong -> came in" on it does.
        if (corrected != "in" && looksFakeCredit(joined) && strongDebit.none { lower.contains(it) }) return Result.Ignored
        // Owner 2026-11-21 (fraud messages): "credited ... click / KYC / lottery / verify account" is never spoken as
        // money; it becomes a ⚠️ notice instead.
        if (!learned && fraudHint.containsMatchIn(joined)) return Result.Ignored
        val view = rejectView(lower)
        // A refund that has LANDED ("Refund of Rs 499 credited to your a/c") is money in; "refund initiated" is not.
        if (!learned && refundLanded.containsMatchIn(joined) && notYet.none { lower.contains(it) }) {
            val amounts = paymentAmounts(joined)
            if (amounts.isNotEmpty()) return Result.Accepted(amounts.first(), rrn(joined), null, accountTail(joined), refund = true)
        }
        // Owner 2026-11-22 ("credits"): cashback / reward / interest that LANDED in the person's account is money in --
        // spoken as cashback / interest. Offers ("win up to ₹100 cashback"), scratch cards and "will be credited" are not.
        if (!learned && bonusLanded.containsMatchIn(joined) && notYet.none { lower.contains(it) } &&
            bonusAd.none { lower.contains(it) }) {
            val amounts = paymentAmounts(joined)
            if (amounts.isNotEmpty()) {
                val bonus = if (interestWord.containsMatchIn(joined)) "interest" else "cashback"
                return Result.Accepted(amounts.first(), rrn(joined), null, accountTail(joined), bonus = bonus)
            }
        }
        // Owner 2026-11-22 (HDFC "Bill Paid! ... paid on ... from HDFC Bank Account XX1234" was kept only as a "bill
        // generated" note): a bill / service payment that is DONE is money that went out -- before the words "bill",
        // "bill pay", "recharge", "emi" below can throw it away.
        if (!learned) paidBill(joined, lower, body, title)?.let { return it }
        val rejected = (reject + moreReject).any { it.isNotEmpty() && view.contains(it.lowercase()) }
        // Owner 2026-11-18 (PhonePe UPI Circle): "Manohar has paid BHUKYA SUJATHA" / "Payment of ₹2 successful by 2283"
        // = someone (a circle member, a family / on-behalf payment) paid a THIRD person -- never money this phone received.
        // With one amount it is money that left the account; without one it is ignored (never "amount not clear").
        if (!learned && thirdPartyPayment(joined, lower)) {
            val amounts = paymentAmounts(joined)
            if (amounts.isEmpty()) return Result.Ignored
            return Result.Outgoing(amounts.first(), thirdPartyPayee(body) ?: thirdPartyPayee(title), accountTail(joined))
        }
        // "Payment of ₹962 to APCPDCL successful" / "payment of Rs 950 for Indane is successful" is the PAYER's message
        // (it was read as money received because of the words "payment of").
        if (!learned) paidOut(joined, lower, body, title)?.let { return it }
        if (!learned && (incoming + moreIncoming).none { it.isNotEmpty() && lower.contains(it.lowercase()) }) {
            if (rejected) return outgoingOrIgnored(joined, view, body, title)
            val only = paymentAmounts(joined).toSet()
            // "Paid ₹10 to Bhagya": clear outgoing wording with a payee is a debit, not a question for the person.
            val payee = payeeName(body) ?: payeeName(title)
            if (payee != null && only.size == 1) return Result.Outgoing(only.first(), payee, accountTail(joined))
            // HDFC / Kotak style debit SMS: "Sent Rs.100.00 From HDFC Bank A/C *1234 To RAMESH On 15/11/26".
            if (sentFrom.containsMatchIn(joined) && only.isNotEmpty()) {
                return Result.Outgoing(only.first(), payeeName(body) ?: payeeName(title), accountTail(joined))
            }
            if (notPaymentHints.any { lower.contains(it) }) return Result.Ignored
            // "Paid ₹5,000 to HDFC Bank credit card": still money that went out when the payee is not a clean name.
            if (only.size == 1 && paidAmountTo.containsMatchIn(joined)) return Result.Outgoing(only.first(), null, accountTail(joined))
            return if (only.size == 1 && shape.contains("₹#") && shape.length >= 8) Result.Unknown(only.first(), shape)
            else Result.Ignored
        }
        if (!learned && rejected) {
            // Incoming words AND outgoing words: a debit only with a STRONG debit word; otherwise ❓ (doubtful).
            val out = outgoingOrIgnored(joined, view, body, title)
            return if (out is Result.Outgoing && strongDebit.none { view.contains(it) }) out.copy(doubtful = true) else out
        }
        // Owner 2026-11-15 ("clear cut"): bank apps add the account BALANCE ("Avl Bal Rs.5,230"); that is never the
        // payment. The payment is the FIRST amount that is not a balance (banks write the credited amount first).
        val amounts = paymentAmounts(joined)
        if (amounts.isEmpty()) return Result.Ambiguous("amount_missing")
        // The UPI RRN (12 digits) is the ONE number a bank SMS and a UPI / bank app show for the same payment
        // (owner 2026-11-17: one common key). An app's own transaction id ("T2511...") is used only when no RRN is shown.
        val reference = rrn(joined)
            ?: refRegex.findAll(joined).map { it.groupValues[1] }.firstOrNull { it.count(Char::isDigit) >= 6 }
        return Result.Accepted(amounts.first(), reference, payerOf(title, body), accountTail(joined))
    }

    /**
     * The payer's name from a notification's title AND text (owner 2026-11-22: the name was on the notification but
     * never spoken). Apps split one sentence over the two: title "₹300 received" + text "from RAMESH KUMAR", or
     * title "RAMESH KUMAR" + text "sent you ₹300". The text alone first, then the title alone, then both together.
     */
    fun payerOf(title: String?, body: String?): String? {
        payerName(body)?.let { return it }
        payerName(title)?.let { return it }
        val t = title?.trim().orEmpty()
        val b = body?.trim().orEmpty()
        return if (t.isNotEmpty() && b.isNotEmpty()) payerName("$t $b") else null
    }

    private val refundLanded = Regex(
        """\brefund\b.{0,80}?\b(?:credited|added|deposited|reversed)\s+(?:to|in|into|back\s+to)\s+(?:your|a/?c|acc|account|bank|wallet)|""" +
            """\b(?:credited|added)\b.{0,60}?\brefund\b""",
        RegexOption.IGNORE_CASE,
    )
    /** Cashback / reward / interest that LANDED ("₹50 cashback credited to your account", "credited as cashback"). */
    private val bonusLanded = Regex(
        """\b(?:cash\s*back|reward|interest)\b.{0,80}?\b(?:credited|added|deposited|transferred)\s+(?:to|in|into|back\s+to)\s+(?:your|a/?c|acc|account|bank|wallet)|""" +
            """\b(?:credited|added|deposited)\b.{0,60}?\b(?:as|towards|for)\s+(?:a\s+|your\s+)?(?:cash\s*back|interest)\b""",
        RegexOption.IGNORE_CASE,
    )
    private val interestWord = Regex("""\binterest\b""", RegexOption.IGNORE_CASE)

    /** Offers / loans that only MENTION cashback or interest -- never money that landed. */
    private val bonusAd = listOf(" win ", " won ", "scratch", "up to", "upto", "get ₹", " earn ", "eligible", "chance", "offer",
        "coupon", "claim", "click", "valid till", "t&c", "loan", "disburs", " rate")
    private val notYet = listOf("initiated", "will be", "will reflect", "processing", "in process", "within", "working days",
        "business days", "requested", "raised")

    /**
     * Owner 2026-11-21 ("refund, bill generated, something initiated ... why did it come, check the bank / bill"):
     * a money message that is NOT a payment is still explained in the history (never spoken, never counted).
     * kind: refund_started | pending | failed | cancelled | bill | autopay | autopay_off | request | suspect.
     * Owner 2026-11-22: each kind can also be SPOKEN (the person's own on / off per kind); never counted as money.
     */
    data class Notice(val kind: String, val amountPaise: Long?)

    private val suspectWords = Regex(
        """(?i)https?://|\bbit\.ly|\bclick\b|\bkyc\b|\bblocked\b|\bsuspend|\bupdate\s+(?:your\s+)?(?:pan|aadhaar|kyc)|""" +
            """\bclaim\b|\bwon\b|\blottery|\bprize\b|\bverify\s+(?:your\s+)?account""")

    private val fraudHint = Regex(
        """(?i)\bclick\b|\bbit\.ly|\bkyc\b|\blottery|\bprize\b|\bverify\s+(?:your\s+)?account|\bupdate\s+(?:your\s+)?(?:pan|aadhaar|kyc)""")

    /**
     * Owner 2026-11-22 (a JK-xxxxx-S SMS "TRADES...BILLAMT DEPOSIT SUCCESS A/c: <a whole 10-digit number> Amount:
     * Rs.8,551,00 Status: RECEIVED Open: bit.ly/..." was SAID and COUNTED as ₹8,55,100 received, marked "Bank SMS"):
     * shapes no bank ever sends. Any one of them makes a "money came" message a ⚠️ fake warning -- never money, never
     * spoken as received, whatever wording was confirmed before (only the person's own "wrong -> came in" on such a
     * message overrides it). Works without the link too (an SMS app may hide or cut it from the notification).
     *  link         -- a public short link (bit.ly, tinyurl, rb.gy ...); banks use their own (hdfcbk.io ...)
     *  bad_amount   -- an amount with broken comma groups ("8,551,00" is neither 8,551.00 nor 85,51,000)
     *  open_account -- a WHOLE account / mobile number after "A/c" (banks always hide it: XX1234, *1234)
     * (A real broker's "funds added to your trading account" has none of these, so it is not called fake.)
     */
    fun fakeSigns(text: String?): List<String> {
        val t = text?.replace('\n', ' ') ?: return emptyList()
        val out = mutableListOf<String>()
        if (shortLink.containsMatchIn(t)) out += "link"
        if (amountRegex.findAll(t).any { !wellGrouped(it.groupValues[1]) }) out += "bad_amount"
        if (openAccount.containsMatchIn(t)) out += "open_account"
        return out
    }

    /** "8,55,100" / "855,100" / "8551" / "1,00,000.50" are amounts; "8,551,00" / "85,5100" are not. */
    fun wellGrouped(raw: String): Boolean {
        val whole = raw.trimEnd(',', '.').substringBefore('.')
        if (!whole.contains(',')) return true
        return Regex("""^\d{1,2}(?:,\d{2})*,\d{3}$""").matches(whole) || Regex("""^\d{1,3}(?:,\d{3})+$""").matches(whole)
    }

    private val shortLink = Regex(
        """(?i)\b(?:bit\.ly|tinyurl\.com|rb\.gy|cutt\.ly|t\.ly|is\.gd|shorturl\.at|tiny\.cc|ow\.ly|bitly\.|goo\.gl|s\.id|v\.gd|t\.co)/""")
    private val openAccount = Regex(
        """(?i)\b(?:a/?c|acct|account)(?:\s*(?:no\.?|number|num))?\s*[:.#-]?\s*\d{9,18}\b""")
    private val creditWords = listOf("credited", "received", "deposit", "refund", "cashback", "added", "success")

    /** A message that claims money CAME and carries a fake sign. */
    fun looksFakeCredit(text: String?): Boolean {
        val lower = text?.lowercase(Locale.ROOT) ?: return false
        return creditWords.any { lower.contains(it) } && fakeSigns(text).isNotEmpty()
    }

    fun notice(title: String?, text: String?): Notice? {
        val joined = listOfNotNull(title, text).joinToString(" ").replace('\n', ' ').trim()
        if (joined.isEmpty()) return null
        val lower = " ${joined.lowercase(Locale.ROOT)} "
        val clean = withoutBoilerplate(joined)
        val cleanLower = " ${clean.lowercase(Locale.ROOT)} "
        val amount = paymentAmounts(clean).firstOrNull()
        val moneyWords = listOf("credited", "received", "refund", "cashback", "debited", "payment", "transfer", "bill", "₹", " rs", "inr")
        if (moneyWords.none { lower.contains(it) }) return null
        // A link / "click" / KYC / "blocked" in a money message (the bank's own safety lines are cut off first).
        if (suspectWords.containsMatchIn(clean) && listOf("credited", "received", "refund", "cashback", "won", "prize", "debited",
                "blocked", "kyc").any { cleanLower.contains(it) }) return Notice("suspect", amount)
        if (looksFakeCredit(clean)) return Notice("suspect", if ("bad_amount" in fakeSigns(clean)) null else amount)
        // Someone asking the person to PAY (UPI collect / money request): money goes only if they approve.
        if (requestWords.containsMatchIn(clean)) return Notice("request", amount)
        // AutoPay / mandate / standing instruction set up or stopped (an AutoPay that RAN is a debit, read elsewhere).
        if (autopayWords.containsMatchIn(clean)) {
            if (autopayOff.containsMatchIn(clean)) return Notice("autopay_off", amount)
            if (autopayOn.containsMatchIn(clean)) return Notice("autopay", amount)
        }
        if (amount == null) return null
        return when {
            cleanLower.contains("refund") -> Notice("refund_started", amount)
            listOf(" cancelled", " canceled", "cancellation").any { cleanLower.contains(it) } -> Notice("cancelled", amount)
            listOf("failed", "declined", "unsuccessful", "could not be processed", "not processed", "reversed").any { cleanLower.contains(it) } ->
                Notice("failed", amount)
            listOf("initiated", "pending", "processing", "in process", "under process", "in progress", "scheduled", "will be debited",
                "will be deducted", "will be processed", "will be charged", "will be auto", "will be paid", "will be collected",
                "will be presented", "will be executed", "will be recovered").any { cleanLower.contains(it) } -> Notice("pending", amount)
            Regex("""\bbill\b.{0,40}?\b(?:generated|amount|of|for|is|due)\b|\bstatement\b|\btotal\s+(?:amount\s+)?due\b|\bamount\s+due\b""")
                .containsMatchIn(cleanLower) -> Notice("bill", amount)
            else -> null
        }
    }

    private val requestWords = Regex(
        """(?i)\b(?:collect\s+request|money\s+request|payment\s+request|request\s+to\s+pay|has\s+requested|is\s+requesting|""" +
            """requested\s+(?:money|payment|₹|rs\.?|inr)|requesting\s+(?:money|payment|₹|rs\.?|inr)|""" +
            """request(?:ed)?\s+(?:of|for)\s+(?:₹|rs\.?|inr))""")
    private val autopayWords = Regex("""(?i)\b(?:auto\s*-?\s*pay|e-?\s*mandate|mandate|standing\s+instruction|e-?nach|recurring\s+payment)\b""")
    private val autopayOff = Regex("""(?i)\b(?:revoked|cancell?ed|paused|deactivated|deleted|expired|stopped|withdrawn)\b""")
    private val autopayOn = Regex(
        """(?i)\b(?:created|registered|set\s*up|setup|activated|approved|is\s+now\s+active)\b""")

    /** TRAI rule: a sender id ending in -P is PROMOTIONAL (ads) -- never a payment, never a notice. */
    fun isPromoSender(title: String?): Boolean =
        Regex("""^[A-Z]{2}-[A-Z0-9]{3,9}-P$""").matches(title?.trim()?.uppercase(Locale.ROOT) ?: "")

    private val billerAck = Regex(
        """\b(?:thanks?(?:\s+you)?\s+for\s+(?:the\s+|your\s+|making\s+(?:the\s+|your\s+)?)?(?:bill\s+)?(?:payment|paying)|""" +
            """(?:we\s+have\s+|we've\s+|have\s+)?received\s+your\s+(?:bill\s+)?payment|""" +
            """payment\s+(?:of\s+$AMT\s+)?(?:has\s+been\s+|is\s+|was\s+)?received\s+(?:towards|for|against)\s+(?:your|the)\b|""" +
            """your\s+(?:bill\s+)?payment\s+of\s+$AMT\s+(?:has\s+been\s+|is\s+|was\s+)?(?:received|successful|successfully))""",
        RegexOption.IGNORE_CASE,
    )

    /**
     * Owner 2026-11-22 ("etc."): the receipt of every company that names the SERVICE instead of "your" -- electricity /
     * water / gas boards ("Rs.962 received towards SC No 1234...", "Rs.1941 paid for USC No ..."), card issuers
     * ("Payment of Rs 5,000 received on your Credit Card"), insurers / lenders ("Premium of Rs.2500 for policy 12
     * received", "Your EMI ... has been received"), "Bill payment of Rs 962 received". Money YOU paid -- unless the
     * message says it came FROM somebody ([fromOther]: then it is money received, e.g. a shop's own message).
     */
    private val serviceAck = Regex(
        """\b(?:payment\s+(?:of\s+$AMT\s+)?(?:has\s+been\s+|is\s+|was\s+)?(?:successfully\s+)?received\s+(?:successfully\s+)?""" +
            """(?:towards|for|against)\s+(?:$SERVICE_ID)\b|""" +
            """$AMT\s+(?:has\s+been\s+|is\s+|was\s+)?(?:successfully\s+)?(?:received|paid)\s+(?:towards|for|against)\s+""" +
            """(?:your\s+|the\s+)?(?:$SERVICE_ID)\b|""" +
            """bill\s+payment\s+(?:of\s+$AMT\s+)?(?:has\s+been\s+|is\s+|was\s+)?(?:successfully\s+)?received\b|""" +
            """payment\s+(?:of\s+$AMT\s+)?(?:has\s+been\s+|is\s+|was\s+)?received\s+(?:on|in)\s+(?:your|the)\s+(?:[a-z]+\s+){0,4}?card\b|""" +
            """(?:emi|premium|instal?lment)\b.{0,60}?\b(?:(?:has\s+been|is|was)\s+)?(?:successfully\s+)?received\b)""",
        RegexOption.IGNORE_CASE,
    )

    /** "from Ramesh" (a person / shop) -- never "from your HDFC a/c", "from A/c XX1234", "from HDFC Bank", "from UPI". */
    private val fromOther = Regex(
        """\bfrom\s+(?!your\b|the\s+(?:account|a/c|card)\b|a/c\b|acct?\b|account\b|[a-z]+\s+bank\b|upi\b|bank\b|card\b|wallet\b)[a-z]""",
        RegexOption.IGNORE_CASE,
    )

    /** The company name from an SMS sender id ("AD-AIRTEL-S" -> "AIRTEL"); a plain app title is kept as it is. */
    fun billerName(title: String?): String? {
        val t = title?.trim()?.takeIf { it.isNotEmpty() && it.length <= 40 } ?: return null
        val m = Regex("""^[A-Za-z]{2}-([A-Za-z0-9]{3,9})(?:-[STGstg])?$""").find(t)
        return m?.groupValues?.get(1) ?: t.takeIf { !it.any(Char::isDigit) }
    }

    // ------------------------------------------------------------------ a bill that WAS paid (owner 2026-11-22)

    /** The number a utility / insurer / lender names instead of "your": service / consumer / connection / policy / loan. */
    private const val SERVICE_ID = """sc\b|usc\b|uscno\b|service\s+(?:no|number|connection)|consumer|connection|ca\s*(?:no|number)|""" +
        """k\s*no|bp\s*(?:no|number)|policy|loan|subscriber|customer\s+(?:id|no|number)|vc\s*(?:no|number)"""

    /** Something a person owes and pays: a bill, an insurance premium, an EMI / instalment, a challan. */
    private const val BILL = """\b(?:e-?bill|bill\s*pay(?:ments?)?|bills?|premium|emi|instal?lments?|e-?challan|challan)\b"""
    private val billWord = Regex(BILL, RegexOption.IGNORE_CASE)
    private const val PAID_OK = """(?:successful|successfully|success|processed|completed|done|""" +
        """(?:has\s+been|have\s+been|was|is)\s+(?:successfully\s+)?made)"""
    private val billPaidPatterns = listOf(
        // "Bill Paid!", "electricity bill of ₹962 paid", "... Bill 1234… of Rs. 962.00 paid on ...", "bill has been paid"
        Regex("""$BILL.{0,90}?\bpaid\b""", RegexOption.IGNORE_CASE),
        // "Paid ₹962 for your electricity bill", "You paid your Airtel bill", "₹962 paid for APCPDCL electricity bill" --
        // never "Ramesh paid ₹500 for bill 12" (somebody else paid).
        Regex("""(?:^|[.!:]\s*|\byou\s+(?:have\s+|'ve\s+)?(?:successfully\s+)?|\bsuccessfully\s+|""" +
            """$AMT\s+(?:is\s+|was\s+|has\s+been\s+)?(?:successfully\s+)?)paid\b.{0,60}?$BILL""", RegexOption.IGNORE_CASE),
        // "Bill payment of Rs 962 for APSPDCL is successful", "payment ... towards your Jio bill is successful", "BillPay ... processed"
        Regex("""\b(?:payments?|bill\s*pay(?:ments?)?|paid)\b.{0,90}?\b$PAID_OK\b""", RegexOption.IGNORE_CASE),
        // "Successful payment of ₹962 for your bill", "Success! Bill payment ..."
        Regex("""\b(?:successful|successfully|success)\b.{0,40}?\b(?:payments?|bill\s*pay(?:ments?)?)\b""", RegexOption.IGNORE_CASE),
    )

    /** Wording that means the bill is NOT paid (yet), is asked for, or is an advertisement. */
    private val billNotPaid = listOf(
        "failed", "failure", "declined", "unsuccessful", "not successful", "could not", "couldn't", "unable to", "rejected",
        "cancelled", "canceled", "reversed", "reversal", "refund", "pending", "initiated", "processing", "in process",
        "under process", "in progress", "scheduled", "will be debited", "will be deducted", "will be processed",
        "will be charged", "will be auto", "will be paid", "will be collected", "will be presented", "will be executed",
        "will be recovered", "to be debited", "to be deducted", "to be paid", "not paid", "not been paid", "unpaid",
        "if paid", "if already", "already paid", "ignore", "generated", "pay now", "pay by", "pay before", "pay on or before",
        "payable", "overdue", "last date", "to avoid", "late fee", "reminder", "please pay", "kindly pay", "pay your", "pay online",
        "to pay", "can be made", "can be done", "can be paid", "may be made", "may be paid", "to be made", "can pay",
        "can make", "make payment", "make the payment", "make your payment", "ready for payment", "due for payment",
        "available for payment", "collect request", "money request", "payment request", "requested", "requesting",
        "request to pay", "request from", "approve payment", "approve the", "to approve", "otp", "one time", "verification code", "password", " pin ", "cashback", "reward",
        "offer", "coupon", "scratch", " won ", " win ", "% off", "click", "kyc", "lottery",
        // A bill message that only mentions an EARLIER payment, and advertisements.
        "last paid", "last payment", "previous", "prev.", "prev ", "convert", "eligible", "pre-approved", "preapproved",
        "apply now", "discount", "t&c",
    )

    /** "is due", "due date", "amount due" -- but a receipt's "Next due 02/2027" is about the NEXT bill, not this one. */
    private val stillDue = Regex("""(?<!\bnext\s)(?<!\bnext\s\s)\bdue\b""")

    /** "Bill 12 of Rs 500 paid by Ramesh": somebody ELSE paid (never "paid by UPI / card / cash"). */
    private val paidByOther = Regex(
        """\bpaid\s+by\s+(?!you\b|upi\b|card\b|cash\b|cheque\b|net\s*banking\b|debit\b|credit\b|wallet\b|auto|bank\b|neft\b|""" +
            """imps\b|[a-z]+\s+(?:bank|upi|card|pay|wallet)\b)[a-z]""",
        RegexOption.IGNORE_CASE,
    )

    /** Wording of money that came TO the person (those messages are never a bill the person paid). */
    private val billToMe = listOf(" to you", "paid you", "sent you", "received", "credited", "deposited", "added to your",
        "జమ", "అందింది", "అందాయి", "प्राप्त", "जमा")

    /** "from HDFC Bank Account XXXXXXXXXX1234" / "from your a/c XX1234" / "using your HDFC Bank Credit Card ending 1234". */
    private val ownAccountSource = Regex(
        """\b(?:from|using|via|through)\s+(?:your\s+)?(?:[A-Za-z&.]+\s+){0,4}?(?:a/c|acct?\.?|account|\bac\b|card)\s*""" +
            """(?:no\.?|number)?\s*(?:ending\s+(?:with\s+|in\s+)?)?[:.\-]?\s*[xX*.]*\s*\d{3,4}\b""",
        RegexOption.IGNORE_CASE,
    )
    private val plainDebit = Regex("""\b(?:debited|withdrawn|spent|debit)\b""", RegexOption.IGNORE_CASE)
    private val paidOkWord = Regex(
        """\b(?:paid|successful|successfully|processed|completed|(?:has\s+been|have\s+been|was)\s+(?:successfully\s+)?made)\b""",
        RegexOption.IGNORE_CASE)

    /**
     * Owner 2026-11-22 ("this bill payment should be a payment too, bill generated etc. too"): a bill / recharge /
     * premium / any service payment that is DONE -- "Bill Paid! APCPDC Ele Bill … of Rs. 962.00 paid on … from HDFC Bank
     * Account XX1234", "Bill payment of ₹962 for APSPDCL is successful", "electricity bill of ₹962 paid" -- is money that
     * went out. Every bank, UPI app and biller: the words decide, never a list of names. Returns null when the message
     * does not clearly say the payment is done (not paid yet, failed, asked for, an offer) or says money came in.
     */
    private fun paidBill(joined: String, lower: String, body: String?, title: String?): Result.Outgoing? {
        if (billNotPaid.any { lower.contains(it) } || billToMe.any { lower.contains(it) }) return null
        if (stillDue.containsMatchIn(lower) || paidByOther.containsMatchIn(joined)) return null
        val own = ownAccountSource.containsMatchIn(joined)
        val bill = billWord.containsMatchIn(joined) &&
            billPaidPatterns.any { it.containsMatchIn(joined) || (body != null && it.containsMatchIn(body)) }
        // Without a bill word: "... paid / successful ... from your A/c XX1234". The bank's plain debit SMS ("debited",
        // "withdrawn", "spent") is not this -- it stays the bank's debit SMS below.
        if (!bill && !(own && paidOkWord.containsMatchIn(joined) && !plainDebit.containsMatchIn(joined))) return null
        val amounts = paymentAmounts(joined)
        if (amounts.isEmpty()) return null
        val party = billPayee(body) ?: billPayee(title) ?: payeeName(body)
            ?: if (!own && isBankSender(title)) billerName(title) else null
        return Result.Outgoing(amounts.first(), party, accountTail(joined), bill = true, ownAccount = own)
    }

    /** "Payment of ₹962 to APCPDCL successful", "payment of Rs 950 for Indane is successful", "payment ... for your order was successful". */
    private val paidOutSuccess = Regex(
        """\bpayments?\s+(?:of\s+$AMT\s+)?(?:made\s+)?(?:to\s+(?!you\b|your\b)|(?:for|towards)\s+(?!you\b|your\s+(?:a/c|acct?|account|bank|wallet|upi)\b|order\b))""" +
            """.{2,80}?\b(?:(?:is|was|has\s+been)\s+)?(?:successful|successfully\s+(?:done|completed|processed|made)|completed)\b""",
        RegexOption.IGNORE_CASE,
    )
    private val fromWord = Regex("""\bfrom\b""", RegexOption.IGNORE_CASE)

    /**
     * The payer's own success message without the word "bill" ("Payment of ₹962 to APCPDCL successful"): money that went
     * out. Null when the message says money came in, names somebody it came FROM, or is not a finished payment.
     */
    private fun paidOut(joined: String, lower: String, body: String?, title: String?): Result.Outgoing? {
        if (!paidOutSuccess.containsMatchIn(joined)) return null
        if (billNotPaid.any { lower.contains(it) } || billToMe.any { lower.contains(it) } || stillDue.containsMatchIn(lower)) return null
        val own = ownAccountSource.containsMatchIn(joined)
        if (fromWord.containsMatchIn(joined) && !own) return null
        val amounts = paymentAmounts(joined)
        if (amounts.size != 1) return null
        return Result.Outgoing(amounts.first(), billPayee(body) ?: billPayee(title) ?: payeeName(body), accountTail(joined),
            bill = true, ownAccount = own)
    }

    private const val BILL_NAME = """([A-Za-z][A-Za-z .&'-]{1,40}?)"""
    private const val BILL_END = """(?:\s+(?:on|via|in|from|using|ref|refno|upi|utr|at|thru|through|is|was|has|have|had|for|of|bill|no|""" +
        """number|consumer|service|customer|a/c|ac|acct|account|successful|successfully|dated|dt|vide|with|towards|against|paid)\b|""" +
        """\s*\d|\s*(?:₹|rs\b|inr\b)|[,!;(:]|\.(?=\s|$|\(|(?-i:[A-Z]))|$)"""
    private val billPayeePatterns = listOf(
        // HDFC BillPay: "Bill Paid! APCPDC Ele Bill 1234… of Rs. 962.00 paid on ..."
        Regex("""\bbill\s+paid\b[\s!.:\-]*$BILL_NAME\s+(?:\d|(?:of|for)\s+$AMT|$AMT)""", RegexOption.IGNORE_CASE),
        // "... for / towards / of your Airtel Postpaid bill", "paid your electricity bill"
        Regex("""\b(?:for|towards|of|against)\s+(?:your\s+|the\s+)?$BILL_NAME\s+(?:bills?|premium|emi)\b""", RegexOption.IGNORE_CASE),
        Regex("""\b(?:your|the)\s+$BILL_NAME\s+(?:bills?|premium|emi)\b""", RegexOption.IGNORE_CASE),
        // "Bill payment of Rs 962 for / to / towards APSPDCL is successful", "₹962 paid for APCPDCL"
        Regex("""\b(?:bill\s*pay(?:ments?)?|payments?|paid|auto\s*-?pay|e-?mandate|mandate|recharge)(?:\s*\([^)]{0,24}\))?\s+(?:of\s+$AMT\s+)?(?:successfully\s+)?(?:for|to|towards)\s+(?:your\s+|the\s+)?$BILL_NAME$BILL_END""", RegexOption.IGNORE_CASE),
        // "Electricity bill of ₹962 paid successfully"
        Regex("""(?:^|[.!]\s+)$BILL_NAME\s+bills?\s+(?:of|for)\s+$AMT""", RegexOption.IGNORE_CASE),
    )

    /** What was paid for ("APCPDC Ele Bill", "Airtel Postpaid", "APSPDCL"): letters only, shown / spoken on this phone. */
    fun billPayee(text: String?): String? = nameFrom(billPayeePatterns, text)

    /** "Please ignore if already paid" and its cousins (bill / due SMS of every company). */
    private val ifPaidIgnore = Regex(
        """(?:pl(?:ease|s|z)?\.?\s+|kindly\s+)?ignore\s+(?:this\s+(?:message|sms|reminder)\s+)?if\s+(?:you\s+have\s+)?(?:already\s+)?""" +
            """(?:paid|made\s+(?:the\s+)?payment)|if\s+(?:you\s+have\s+)?(?:already\s+)?(?:paid|made\s+(?:the\s+)?payment)""" +
            """(?:\s*,?\s*(?:pl(?:ease|s|z)?\.?\s+|kindly\s+)?ignore)?|already\s+paid\s*\??\s*(?:pl(?:ease|s|z)?\.?\s+|kindly\s+)?ignore""")

    private val circleWords = listOf("upi circle", "on your behalf", "on behalf of", "secondary user", "delegate")
    private val hasPaidSomeone = Regex("""\b(?:has|have)\s+paid\s+(?!you\b)(?!(?:₹|rs\b|rs\.|inr\b))[a-z]""", RegexOption.IGNORE_CASE)
    private val successfulBy = Regex("""\bpayment\s+of\s+$AMT\s+(?:was\s+)?successful\s+by\b""", RegexOption.IGNORE_CASE)

    /** A payment made BY someone TO someone else (UPI Circle, on-behalf) -- the phone's owner is neither paid nor asked. */
    fun thirdPartyPayment(joined: String, lower: String = " ${joined.lowercase()} "): Boolean {
        if (lower.contains(" to you") || lower.contains("paid you") || lower.contains("sent you")) return false
        return circleWords.any { lower.contains(it) } || hasPaidSomeone.containsMatchIn(joined) || successfulBy.containsMatchIn(joined)
    }

    private val thirdPartyPayeePattern = listOf(Regex("""\b(?:has|have)\s+paid\s+(.{2,60}?)$END""", RegexOption.IGNORE_CASE))

    /** Who a third-party payment went to ("... has paid BHUKYA SUJATHA." -> "BHUKYA SUJATHA"). */
    fun thirdPartyPayee(text: String?): String? = nameFrom(thirdPartyPayeePattern, text)

    private val paidAmountTo = Regex("""\b(?:paid|sent)\s+$AMT\s+to\s+(?!you\b|your\b)\S""", RegexOption.IGNORE_CASE)
    private val sentFrom = Regex("""\bsent\s+$AMT\s+from\b""", RegexOption.IGNORE_CASE)

    /** Bank of Baroda and others: "Rs.448.00 Dr. from A/C XXXXXX1234 and Cr. to x@y" -- the bank's own debit SMS. */
    private val drFrom = Regex("""$AMT\s+dr\.?\s+(?:from|in|to)\s+(?:your\s+)?(?:a/?c|acct?|account)\b""", RegexOption.IGNORE_CASE)

    /**
     * Owner 2026-11-23 (ICICI "Acct XX123 debited for Rs 448.00 on 23-Nov-26; Jio Prepaid Recharge credited" -- no voice,
     * no row): the part of a debit SMS that NAMES who was paid -- "; <payee> credited" (ICICI), "and Cr. to <payee>"
     * (BoB), "and credited to <payee>", a UPI id -- is a name, never a sign that money came in, failed or was an offer.
     * Removed only for the debit checks; the payee is still read from the full text.
     */
    private val payeeSlots = listOf(
        Regex(""";\s*[a-z0-9][^;]{0,60}?\s+credited\b"""),
        Regex("""\band\s+(?:cr\.?|credited)\s+to\s+(?!your\b)\S+"""),
        Regex("""[a-z0-9._\-]+@[a-z][a-z0-9.\-]*"""),
    )

    private fun withoutPayee(lower: String): String = payeeSlots.fold(lower) { acc, re -> re.replace(acc, " ") }

    private val debitWords = listOf("debited", "you paid", "you sent", "paid to", "sent to", "withdrawn", "spent",
        // SBI and others: "Your A/C X1234 has a debit by transfer of Rs 962.00" (the mirror of "has a credit by").
        "a debit by", "a debit of", "has a debit")
    private val notMoney = listOf("request", "collect", "otp", "one time", "failed", "declined", "unsuccessful", "pending",
        "refund", "reversed", "due", "reminder", "cashback", "reward", "offer", "coupon", "scratch", "verification code",
        "password", "pin ", "loan", "emi", "recharge", "bill pay")

    /** What a debit was FOR (owner 2026-11-22: a bill / EMI / recharge that is paid IS a payment). */
    private val purposeWords = setOf("loan", "emi", "recharge", "bill pay")
    private val notDoneDebit = listOf("will be", "shall be", "would be", "to be debited", "to be deducted", "apply",
        "pre-approved", "preapproved", "eligible", "avail ",
        // "Loan of Rs 50,000 disbursed / credited to your a/c. Processing fee Rs 590 debited": the big amount came IN.
        "credited", "disbursed", "deposited", "received", "a credit", "credit of")
    private val dueWord = Regex("""\bdue\b""")

    /** Clear "money went out" wording with exactly one amount -> Outgoing; everything else stays ignored. */
    private fun outgoingOrIgnored(joined: String, lower: String, text: String?, title: String?): Result {
        // The bank's own "Sent Rs.X From ... A/C" (HDFC, Kotak) / "Rs.X Dr. from A/C" (BoB) is a debit as sure as "debited"
        // (owner 2026-11-23: "To JIO PREPAID RECHARGE" / "to jiorecharge@paytm" made those SMS disappear).
        val bankSent = sentFrom.containsMatchIn(joined) || drFrom.containsMatchIn(joined)
        if (!bankSent && debitWords.none { lower.contains(it) }) return Result.Ignored
        val view = withoutPayee(lower)
        // "Rs 1,941 debited from A/c XX1234 towards EMI of loan", "debited ... for Jio recharge", "you paid ... bill
        // payment", "debited towards card dues": the bank / app says the money LEFT -- what it was for never drops it.
        val done = (bankSent || strongDebit.any { view.contains(it) }) && notDoneDebit.none { view.contains(it) }
        val stopped = notMoney.any { w ->
            view.contains(w) && !(done && (w in purposeWords || (w == "due" && !dueWord.containsMatchIn(view))))
        }
        if (stopped) return Result.Ignored
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
        Regex("""$AMT\s+(?:sent|paid)\s+from\s+.{0,60}?\s+to\s+(\S.{1,60}?)$END""", RegexOption.IGNORE_CASE),
        Regex(""";\s*([A-Za-z][A-Za-z .]{1,40}?)\s+credited""", RegexOption.IGNORE_CASE),            // ICICI debit SMS
        Regex("""\bcr\.?\s+to\s+(\S.{1,60}?)$END""", RegexOption.IGNORE_CASE),                          // BoB debit SMS
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
                // Owner 2026-11-22 (names on the notification, never spoken): PhonePe writes the payer's UPI id in
                // brackets after the name -- "MOHAMMAD HAFIZ (9502072317@ibl) sent you ₹300". The name is the part
                // outside the brackets.
                val outside = name.replace(Regex("""\s*\([^)]*\)?\s*"""), " ").trim().trim('.', ',', '-', ':')
                if (outside.length >= 2 && outside != name && !outside.contains('@')) name = outside.replace(Regex("\\s+"), " ")
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

    /** A UPI app naming the person's account as "HDFC Bank-1234" / "SBI Bank - XX1234" (never a phone number after it). */
    private val bankDashRegex = Regex("""\bbank\s?[-–]\s?[xX*]{0,8}(\d{4})\b(?![\s-]*\d)""", RegexOption.IGNORE_CASE)

    /** Last 3-4 digits of the account a bank SMS names ("A/c XX1234" -> "1234"); never more than that. */
    /** The sides an account can be ON for (owner 2026-11-23). */
    val SIDES = setOf("mine", "shop", "off")

    /**
     * Owner 2026-11-23 ("seller account has 2 accounts"; Rs 100 paid to the shop's QR landed in "My own" because its
     * bank app was on the "My phone" list): each money ACCOUNT is ON for one side -- "mine" (the person) or "shop"
     * (the shop this phone listens for) -- or "off". The money's account decides, not the app it came through: one
     * PhonePe / one SMS app carries both kinds of money, for every bank. [accountSides] = the account's last digits
     * -> side (3-4 digits; "1234" and "234" are the same account), [appSides] = package -> side (an app the person
     * linked to an account). null = nothing chosen: the app decides, as before.
     */
    fun accountSide(account: String?, pkg: String, accountSides: Map<String, String>, appSides: Map<String, String>): String? {
        val tail = account?.filter { it.isDigit() }.orEmpty()
        if (tail.length >= 3) {
            accountSides[tail]?.let { return it.takeIf { s -> s in SIDES } }
            for ((k, v) in accountSides) {
                val key = k.filter { it.isDigit() }
                if (key.length >= 3 && (key.endsWith(tail) || tail.endsWith(key)) && v in SIDES) return v
            }
        }
        return appSides[pkg]?.takeIf { it in SIDES }
    }

    fun accountTail(text: String?): String? = accountRegex.find(text ?: "")?.groupValues?.get(1)
        ?: bankDashRegex.find(text ?: "")?.groupValues?.get(1)

    // ------------------------------------------------------------------ a summary of several transactions

    private const val BULLETS = "·•●▪◦‣∙⁃"
    private val digestSplit = Regex("""[\n\r]+|\s*[$BULLETS]\s*""")
    private val digestHeader = Regex(
        """\b\d{1,3}\s+(?:(?:new|more|recent|completed|successful|other|unread)\s+){0,3}""" +
            """(?:transactions?|payments?|transfers?|updates?)\b""", RegexOption.IGNORE_CASE)

    /**
     * Owner 2026-11-23 (PhonePe "2 new completed transaction updates · A has sent ₹3,000 to your bank account ·
     * ₹3,360 has been sent to B" was read as ONE message: "₹3,000 went to B", spoken hours after the money had come
     * IN): a payment app's SUMMARY of several transactions is several messages. Returns each transaction's own line
     * (two or more), or an empty list for an ordinary single message.
     * A summary = two or more lines / bullet points that EACH carry a payment amount, and either a heading that
     * counts them ("2 new completed transaction updates", "3 payments") or bullet points. A bank SMS over several
     * lines, or one sentence with a balance, is never a summary.
     */
    fun digestLines(title: String?, text: String?): List<String> {
        val body = text ?: return emptyList()
        val pieces = digestSplit.split(body).map { it.trim().trim('-', '*', '–').trim() }.filter { it.isNotEmpty() }
        if (pieces.size < 2) return emptyList()
        val money = pieces.filter { paymentAmounts(it).isNotEmpty() }
        if (money.size < 2) return emptyList()
        val counted = digestHeader.containsMatchIn(title ?: "") ||
            pieces.any { paymentAmounts(it).isEmpty() && digestHeader.containsMatchIn(it) }
        val bulleted = body.count { it in BULLETS } >= 2
        return if (counted || bulleted) money else emptyList()
    }

    /**
     * [digestLines] for a notification given as its separate pieces (text, big text, newest message, every line):
     * apps fill them with the SAME summary in different layouts, so the fullest single piece is read -- the pieces are
     * never added together (one line twice would look like two payments). Lines that sit in separate pieces (no
     * bullets, no line breaks) count as a summary only under a heading that counts them.
     */
    fun digestLinesOf(title: String?, parts: List<String?>): List<String> {
        val clean = parts.mapNotNull { it?.trim()?.takeIf { t -> t.isNotEmpty() } }
        var best = emptyList<String>()
        for (piece in clean) {
            val lines = digestLines(title, piece)
            if (lines.size > best.size) best = lines
        }
        if (best.size >= 2) return best
        if (!digestHeader.containsMatchIn(title ?: "")) return emptyList()
        fun norm(x: String) = x.lowercase(Locale.ROOT).replace(spaces, " ").trim()
        val money = clean.filter { paymentAmounts(it).isNotEmpty() }.distinctBy { norm(it) }
        val own = money.filter { a -> money.none { b -> b !== a && norm(b).length > norm(a).length && norm(b).contains(norm(a)) } }
        return if (own.size >= 2) own else emptyList()
    }

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
        Regex("""^\s*(.{2,60}?)\s+(?:has\s+)?sent\s+you\s+$AMT""", RegexOption.IGNORE_CASE),          // "NAME sent you ₹300"
        Regex("""received\s+$AMT\s+from\s+(.{2,60}?)(?:\s+(?:on|via|in|to|at)\b|[.,!]|$)""", RegexOption.IGNORE_CASE), // Paytm
        Regex("""upi/p2[am]/\d+/([A-Za-z][A-Za-z .]{1,40}?)(?:/|$END)""", RegexOption.IGNORE_CASE),     // Axis
        Regex("""$AMT\s+received\s+from\s+(.{2,60}?)(?:\s+(?:on|via|in|to|at)\b|[.,!]|$)""", RegexOption.IGNORE_CASE),
        // MUST stay last (payerName applies it only to the text after the credit word).
        // Bank SMS: "... by|from NAME" anywhere AFTER the credit word (payerName passes only that part).
        Regex("""(?:^|\s)(?:by|from)\s+(?:upi\s*[-/:]?\s*|(?:a/c\s+linked\s+to\s+)?vpa\s+)?([A-Za-z][A-Za-z0-9 .@_-]{1,50}?)$END""", RegexOption.IGNORE_CASE),
    )
    private val notAName = setOf("you", "upi", "bank", "account", "a/c", "your", "someone", "phonepe", "paytm", "google",
        "gpay", "bhim", "money", "payment", "received", "ref", "neft", "imps", "utr", "rtgs", "txn", "transfer", "rs", "inr",
        "mob", "bk", "vpa", "linked", "mobile", "cash", "atm", "branch", "cheque", "clearing", "interest", "salary", "of",
        "order", "purchase", "transaction", "booking", "number")

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

    /** "962 రూపాయలు" / "962 रुपये" / "962 rupees" (+ paise) in the person's language. */
    fun moneyWords(amountPaise: Long, language: String): String {
        val rupees = amountPaise / 100
        val paise = amountPaise % 100
        return when (language) {
            "te" -> "$rupees రూపాయలు" + (if (paise > 0) " $paise పైసలు" else "")
            "hi" -> "$rupees रुपये" + (if (paise > 0) " $paise पैसे" else "")
            "en" -> "$rupees rupees" + (if (paise > 0) " $paise paise" else "")
            else -> {
                val w = WORDS[language] ?: WORDS["en_fallback"]!!
                w.rupees.replace("{n}", rupees.toString()) + (if (paise > 0) " " + w.paise.replace("{n}", paise.toString()) else "")
            }
        }
    }

    /**
     * Owner 2026-11-22 ("the 3rd one: when such messages come a sound should come"): a bill / EMI / loan instalment
     * that was PAID -- "బజాజ్ ఫైనాన్స్ లోన్ వాయిదా 4133 రూపాయలు కట్టారు."
     */
    fun billPaidParts(amountPaise: Long, language: String, party: String?, emi: Boolean): List<String> {
        val money = moneyWords(amountPaise, language)
        val who = party?.trim()?.takeIf { it.isNotEmpty() }
        return when (language) {
            "te" -> listOf(listOfNotNull(who, if (emi) "లోన్ వాయిదా" else "బిల్లు").joinToString(" "), "$money కట్టారు.")
            "hi" -> listOf(listOfNotNull(who, if (emi) "लोन की किस्त" else "बिल").joinToString(" "), "$money भरे गए।")
            else -> listOf((if (emi) "Loan instalment" else "Bill") + (if (who != null) " to $who" else ""), "of $money paid.")
        }
    }

    /** Cashback / interest that landed: "50 రూపాయలు క్యాష్‌బ్యాక్ ఖాతాలో పడింది." */
    fun bonusParts(amountPaise: Long, language: String, bonus: String): List<String> {
        val money = moneyWords(amountPaise, language)
        val interest = bonus == "interest"
        return when (language) {
            "te" -> listOf(money, if (interest) "వడ్డీ ఖాతాలో పడింది." else "క్యాష్‌బ్యాక్ ఖాతాలో పడింది.")
            "hi" -> listOf(money, if (interest) "ब्याज खाते में आया।" else "कैशबैक खाते में आया।")
            else -> listOf(if (interest) "Interest of" else "Cashback of", "$money reached your account.")
        }
    }

    /**
     * Owner 2026-11-22: what the phone SAYS for a money message that is not a payment. Never the word for "received"
     * (that is only for money that came in). [kind] = a [Notice] kind; [amountPaise] may be null (a fake, a request).
     */
    fun noticeParts(kind: String, amountPaise: Long?, language: String, party: String? = null): List<String> {
        val money = amountPaise?.let { moneyWords(it, language) }
        val who = party?.trim()?.takeIf { it.isNotEmpty() }
        val te = language == "te"
        val hi = language == "hi"
        val m = money ?: ""
        val ofMoney = if (money != null) " of $money" else ""
        val text = when (kind) {
            "refund_started" -> when {
                te -> "$m రీఫండ్ మొదలైంది. ఇంకా ఖాతాలో పడలేదు."
                hi -> "$m का रिफंड शुरू हुआ। अभी खाते में नहीं आया।"
                else -> "Refund$ofMoney started. Not in your account yet."
            }
            "pending" -> when {
                te -> "$m పేమెంట్ ఇంకా పూర్తి కాలేదు, పెండింగ్‌లో ఉంది."
                hi -> "$m का पेमेंट अभी पूरा नहीं हुआ, पेंडिंग है।"
                else -> "Payment$ofMoney is pending, not done yet."
            }
            "failed" -> when {
                te -> "$m పేమెంట్ ఫెయిల్ అయింది. డబ్బు కట్ అయితే బ్యాంక్ యాప్‌లో చూడండి."
                hi -> "$m का पेमेंट फेल हुआ। पैसे कटे हों तो बैंक ऐप देखें।"
                else -> "Payment$ofMoney failed. If money was taken, check your bank app."
            }
            "cancelled" -> when {
                te -> "$m పేమెంట్ రద్దయింది."
                hi -> "$m का पेमेंट रद्द हुआ।"
                else -> "Payment$ofMoney was cancelled."
            }
            "bill" -> when {
                te -> "${who ?: ""} బిల్లు $m వచ్చింది. ఇంకా కట్టాల్సి ఉంది."
                hi -> "${who ?: ""} बिल $m आया है। अभी भरना बाकी है।"
                else -> "A bill" + (if (who != null) " from $who" else "") + "$ofMoney has come. It is still to be paid."
            }
            "autopay" -> when {
                te -> "${who ?: ""} ఆటోపే $m సెట్ అయింది."
                hi -> "${who ?: ""} ऑटोपे $m सेट हुआ।"
                else -> "AutoPay" + (if (who != null) " for $who" else "") + "$ofMoney was set up."
            }
            "autopay_off" -> when {
                te -> "${who ?: ""} ఆటోపే రద్దయింది."
                hi -> "${who ?: ""} ऑटोपे रद्द हुआ।"
                else -> "AutoPay" + (if (who != null) " for $who" else "") + " was stopped."
            }
            "request" -> when {
                te -> "జాగ్రత్త: ఎవరో ${money ?: "డబ్బు"} అడుగుతున్నారు. మీరు ఒప్పుకుంటేనే డబ్బు పోతుంది."
                hi -> "सावधान: कोई ${money ?: "पैसे"} माँग रहा है। आप मंज़ूर करेंगे तभी पैसे जाएँगे।"
                else -> "Careful: someone is asking you for ${money ?: "money"}. Money goes only if you approve."
            }
            // Owner 2026-11-23: a message the phone is NOT SURE about is never said as a fact -- "check once".
            "unsure" -> when {
                te -> "$m గురించి ఒక మెసేజ్ వచ్చింది. డబ్బు వెళ్ళిందో లేదో ఖచ్చితంగా తెలియలేదు. ఒకసారి మీ బ్యాంక్ బ్యాలెన్స్ చూసుకోండి."
                hi -> "$m के बारे में एक मैसेज आया है। पैसे गए या नहीं, पक्का नहीं है। एक बार अपना बैंक बैलेंस देख लें।"
                else -> "A message" + (if (money != null) " about $money" else "") + " came. It is not sure that the money went out. Please check your bank balance once."
            }
            // A payment the phone hears about only LATER (in an app's summary): said once, as an earlier payment.
            "late_in" -> when {
                te -> "ఆలస్యంగా తెలిసింది: ${if (who != null) "$who నుండి " else ""}$m ఇంతకుముందే జమ అయ్యాయి."
                hi -> "देर से पता चला: ${if (who != null) "$who से " else ""}$m पहले ही जमा हुए थे।"
                else -> "Found out late: ${money ?: "money"} came in earlier" + (if (who != null) " from $who." else ".")
            }
            "late_out" -> when {
                te -> "ఆలస్యంగా తెలిసింది: ${if (who != null) "$who కి " else ""}$m ఇంతకుముందే వెళ్ళాయి."
                hi -> "देर से पता चला: ${if (who != null) "$who को " else ""}$m पहले ही गए थे।"
                else -> "Found out late: ${money ?: "money"} went out earlier" + (if (who != null) " to $who." else ".")
            }
            // What the phone SAID earlier turned out wrong (the bank's own SMS says the opposite): it says so, once.
            "sorry_out" -> when {
                te -> "సారీ, ఇంతకుముందు $m వెళ్ళాయి అని చెప్పింది తప్పు. ఆ డబ్బు వెళ్ళలేదు."
                hi -> "माफ़ कीजिए, पहले $m गए बताया था, वह गलत था। वे पैसे नहीं गए।"
                else -> "Sorry, what I said earlier was wrong: ${money ?: "that money"} did not go out."
            }
            "sorry_in" -> when {
                te -> "సారీ, ఇంతకుముందు $m వచ్చాయి అని చెప్పింది తప్పు. ఆ డబ్బు రాలేదు."
                hi -> "माफ़ कीजिए, पहले $m आए बताया था, वह गलत था। वे पैसे नहीं आए।"
                else -> "Sorry, what I said earlier was wrong: ${money ?: "that money"} did not come in."
            }
            "suspect" -> when {
                te -> "జాగ్రత్త! ఇది నకిలీ మెసేజ్‌లా ఉంది. లింక్ నొక్కకండి. డబ్బు వచ్చిందో బ్యాంక్ యాప్‌లో చూడండి."
                hi -> "सावधान! यह मैसेज नकली लगता है। कोई लिंक न दबाएँ। पैसे आए या नहीं, बैंक ऐप में देखें।"
                else -> "Careful! This message looks fake. Do not tap any link. Check your bank app to see if money came."
            }
            else -> ""
        }
        return listOf(text.replace(spaces, " ").trim()).filter { it.isNotEmpty() }
    }

    private val spaces = Regex("""\s+""")

    /**
     * The voice switch a message kind belongs to (owner 2026-11-22, the "Payment voice" folder): in | out | bill |
     * refund | cashback | pending | failed | due | autopay | request | fake.
     */
    fun voiceKindOf(noticeKind: String): String = when (noticeKind) {
        "refund_started", "pending" -> "pending"
        "failed", "cancelled" -> "failed"
        "bill" -> "due"
        "autopay", "autopay_off" -> "autopay"
        "request" -> "request"
        "suspect" -> "fake"
        // Owner 2026-11-23: "check once" for an unsure message and "sorry" for a wrong earlier voice have no switch
        // yet (on); a payment heard of late follows the switch of its own direction.
        "unsure" -> "check"
        "late_in" -> "in"
        "late_out" -> "out"
        "sorry_out", "sorry_in" -> "sorry"
        else -> noticeKind
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

    /**
     * Owner 2026-11-19 (fake SMS): a "money received" SMS from a PERSON's number ("+91 98765 43210", "9876543210") is
     * how fraudsters fake a payment -- banks send from registered sender ids, never a mobile number. Such an SMS is
     * written in the history with a warning and is never spoken as received. A name the phone shows (a contact, or a
     * verified business name like "HDFC Bank") is not judged here.
     */
    fun looksLikePersonNumber(title: String?): Boolean {
        val t = title?.trim() ?: return false
        if (t.any { it.isLetter() }) return false
        return t.count { it.isDigit() } >= 7
    }

    private val handleRegex = Regex("""([A-Za-z0-9.*_\-]+)@([A-Za-z]{2,20})\b(?!\.[A-Za-z])""")
    private val receiverBefore = Regex("""(?i)(?<!linked\s)\b(?:to|in)\s+(?:your\s+)?(?:vpa|upi\s*id|upi)?\s*[:\-]?\s*$""")

    /**
     * The PAYER's UPI id, cut to its last 4 letters / digits + its bank handle, to tell two payments apart:
     * "*2317@ibl" / "9502072317@ibl" -> "2317@ibl", a masked "*akar@ibl" -> "akar@ibl" (owner 2026-11-22: masked ids
     * said nothing before). An e-mail address ("care@hdfcbank.com") and the shop's OWN id ("credited to VPA
     * shop@icici") are never the payer.
     */
    fun upiHandleTail(text: String): String? {
        for (m in handleRegex.findAll(text)) {
            if (receiverBefore.containsMatchIn(text.substring(0, m.range.first))) continue
            val local = m.groupValues[1].filter(Char::isLetterOrDigit).lowercase(Locale.ROOT)
            if (local.length < 4) continue
            return "${local.takeLast(4)}@${m.groupValues[2].lowercase(Locale.ROOT)}"
        }
        return null
    }

    /** Two payer UPI ids: SAME tail = the same person's money, DIFFERENT = two people, UNKNOWN = one is missing. */
    fun compareHandles(a: String?, b: String?): RefMatch {
        val x = a?.trim()?.lowercase(Locale.ROOT).orEmpty()
        val y = b?.trim()?.lowercase(Locale.ROOT).orEmpty()
        if (x.isEmpty() || y.isEmpty()) return RefMatch.UNKNOWN
        // Owner 2026-11-24: the same payer id written with another bank's handle (9876543210@ybl in the app,
        // 9876543210@axl on the bank's SMS) is the same person: the id before '@' decides, not the handle after it.
        return if (x.substringBefore('@') == y.substringBefore('@')) RefMatch.SAME else RefMatch.DIFFERENT
    }

    private val honorifics = setOf("MR", "MRS", "MS", "SRI", "SHRI", "SMT", "DR", "M/S")

    /**
     * Is the payer the same person on two messages (an app's name vs the bank's)? Only ever used as a reason TO join
     * (never to split): equal names, the same words in another order ("MANOHAR KOVELAKARU" / "KOVELAKARU MANOHAR"),
     * or a bank that cut a two-word name short ("MOHAMMAD HAF" / "MOHAMMAD HAFIZ").
     */
    fun samePayer(a: String?, b: String?): Boolean {
        fun words(s: String?) = s?.uppercase(Locale.ROOT)?.replace(Regex("[^A-Z ]"), " ")?.split(' ')
            ?.filter { it.length >= 2 && it !in honorifics }.orEmpty()
        val x = words(a)
        val y = words(b)
        if (x.isEmpty() || y.isEmpty()) return false
        if (x == y || x.toSet() == y.toSet()) return true
        val (short, long) = if (x.joinToString(" ").length <= y.joinToString(" ").length) x to y else y to x
        val s = short.joinToString(" ")
        return short.size >= 2 && s.length >= 6 && long.joinToString(" ").startsWith(s)
    }

    /**
     * Two names that cannot be the same person: both are there and they share no word of three or more letters
     * ("mahesh" / "MAHESH BABU" do not clash; "RAMESH" / "SURESH KUMAR" do). Used only for a summary line, to keep
     * another person's payment of the same amount out of a row.
     */
    fun namesClash(a: String?, b: String?): Boolean {
        fun words(s: String?) = s?.uppercase(Locale.ROOT)?.replace(Regex("[^A-Z ]"), " ")?.split(' ')
            ?.filter { it.length >= 3 && it !in honorifics }?.toSet().orEmpty()
        val x = words(a)
        val y = words(b)
        return x.isNotEmpty() && y.isNotEmpty() && x.intersect(y).isEmpty()
    }

    /** The bank's "Bill Paid" SMS vs the company's receipt: a receipt may come up to an hour after it ... */
    const val NOTE_AFTER_SMS_MS = 60 * 60_000L
    /** ... and the bank's two SMS of one bill (debit + "Bill Paid") come within 10 minutes of each other. */
    const val SMS_AFTER_NOTE_MS = 10 * 60_000L
    /**
     * Owner 2026-11-17 / 2026-11-22 ("however late the second message comes -- 15 min, 30 min, an hour -- one payment
     * is spoken ONCE"): the bank SMS and the UPI / bank app notification of one payment, in ANY order, up to 2 hours
     * apart, when nothing on them says they are two payments.
     */
    const val LATE_PAIR_MS = 2 * 60 * 60_000L
    /** The same payer's UPI id or name on both messages: the late one still joins up to 6 hours later. */
    const val SAME_PAYER_MS = 6 * 60 * 60_000L
    /**
     * One payment heard on this phone: from its OWN message ("local") or from a push of another phone / the bank
     * ("remote"). [scope] = the shop it is for; [used] = already paired with the other path.
     */
    data class Heard(val path: String, val scope: String, val amountPaise: Long, val atMs: Long, var used: Boolean = false)

    /**
     * Owner 2026-11-24 ("said again an hour later"): the shop's money can reach this phone twice -- as a push (another
     * phone or the bank reported it) and as this phone's own SMS / notification, often far apart. Pairs ONE local with
     * ONE remote of the same shop and amount within [LATE_PAIR_MS]: the second stays silent. Two real payments of the
     * same amount stay two (each pairs once). The person's own money (empty [scope]) never pairs with a shop's push.
     * Returns true when this one may speak; [heard] is updated (and kept small).
     */
    fun claimHeard(heard: MutableList<Heard>, path: String, scope: String, amountPaise: Long, atMs: Long): Boolean {
        heard.removeAll { atMs - it.atMs > SAME_PAYER_MS }
        while (heard.size > 100) heard.removeAt(0)
        if (scope.isEmpty() || amountPaise <= 0L) return true
        val twin = heard.filter { !it.used && it.path != path && it.scope == scope && it.amountPaise == amountPaise &&
            kotlin.math.abs(atMs - it.atMs) <= LATE_PAIR_MS }.minByOrNull { kotlin.math.abs(atMs - it.atMs) }
        if (twin != null) {
            twin.used = true
            heard.add(Heard(path, scope, amountPaise, atMs, used = true))
            return false
        }
        heard.add(Heard(path, scope, amountPaise, atMs))
        return true
    }

    /** Two different apps of the same kind (two UPI apps, two SMS apps) telling one payment WITH proof: within 10 minutes. */
    const val SAME_KIND_APPS_MS = 10 * 60_000L
    /** The same UPI reference (RRN) on both: the same money any time within a day. */
    const val SAME_REF_MS = 24 * 60 * 60_000L
    /** A payment app's SUMMARY line tells a payment made up to two days before it (owner 2026-11-23). */
    const val SUMMARY_MS = 48 * 60 * 60_000L
    /** ... and never one made after it (a few minutes of slack for the clocks of two messages). */
    const val SUMMARY_SLACK_MS = 5 * 60_000L

    /** Kinds of message that come through the SMS app NEXT TO the bank's debit SMS for the same money. */
    val SIDE_KINDS = setOf("biller", "billpay")

    /** One row of the phone's payment history, as [pickSamePayment] needs it. */
    data class Row(
        val index: Int, val atMs: Long, val sourceApp: String, val kind: String, val kinds: List<String>,
        val direction: String, val amountPaise: Long, val account: String? = null, val reference: String? = null,
        val handle: String? = null, val payer: String? = null, val excluded: Boolean = false, val test: Boolean = false,
        /** Every app whose message is in this row ([sourceApp] first). Empty = only [sourceApp]. */
        val apps: List<String> = emptyList(),
        /** [messageKey] of every message already in this row (the very same SMS / notification text). */
        val textKeys: List<String> = emptyList(),
    )

    /** The message that just arrived. [atMs] = its own payment time. */
    data class Msg(
        val sourceApp: String, val kind: String, val direction: String, val amountPaise: Long, val atMs: Long,
        val account: String? = null, val reference: String? = null, val handle: String? = null,
        val payer: String? = null, val bankSms: Boolean = false,
        /** One line of a payment app's SUMMARY ([digestLines]): an EARLIER payment, told again. */
        val summary: Boolean = false,
        /** [messageKey] of this message's text. */
        val textKey: String? = null,
    )

    /**
     * Owner 2026-11-24: the SAME message shown by two apps (one bank SMS in Messages AND Truecaller) has the very same
     * words -- date, balance, reference and all. Two real payments' messages differ (time, balance, reference).
     * Null when the text is too short to tell anything.
     */
    fun messageKey(text: String?): String? {
        val t = text?.lowercase(Locale.ROOT)?.replace(Regex("\\s+"), " ")?.trim().orEmpty()
        return if (t.length < 25 || !t.any(Char::isDigit)) null else t
    }

    /**
     * Owner 2026-11-15 / 17 / 22 -- ONE payment = ONE voice, ONE row. Which earlier row (if any) is the SAME money as
     * [msg]? Returns that row's [Row.index], or null = a new payment (spoken).
     *  - the same UPI reference (RRN) = the same money (any order, within a day); two different RRNs = two payments;
     *  - otherwise the same amount + direction from a DIFFERENT kind of source (sms / upi / bank) that the row does not
     *    have yet, with no clue saying "two payments" (different account, different payer UPI id), within
     *    [LATE_PAIR_MS] -- or [SAME_PAYER_MS] when the payer's UPI id or name is the same on both;
     *  - two messages from the same app never join (Rs 1 + Rs 1 = two payments), two SMS never join;
     *  - a row with a clue beats one without; then the row closest in time wins;
     *  - a SUMMARY line ([Msg.summary], owner 2026-11-23) is an EARLIER payment told again: it joins the row of the
     *    same amount + direction up to [SUMMARY_MS] before it, even a row the SAME app made -- unless both carry a
     *    person's name and the names share no word. [skip] = rows another line of the same summary already took
     *    (two equal lines = two payments, one row each).
     */
    fun pickSamePayment(rows: List<Row>, msg: Msg, skip: Set<Int> = emptySet()): Int? {
        var best: Row? = null
        var bestClue = false
        var bestGap = Long.MAX_VALUE
        for (r in rows) {
            if (r.atMs <= 0L || r.test || r.index in skip) continue
            if (r.direction != msg.direction) continue
            // A row set aside (❓) joins only the bank's own SMS that agrees with it (then it counts again).
            if (r.excluded && !msg.bankSms) continue
            val gap = msg.atMs - r.atMs
            // Owner 2026-11-24 (the same payment said again an hour later): the SAME UPI reference is the same money
            // whoever tells it -- also the SAME app or SMS app telling it a second time (a re-sent notification, the
            // bank's second SMS of one credit). Checked before the "same app = two payments" rule below.
            when (compareRefs(r.reference, msg.reference)) {
                RefMatch.SAME -> if (kotlin.math.abs(gap) <= SAME_REF_MS) return r.index
                RefMatch.DIFFERENT -> continue
                RefMatch.UNKNOWN -> {}
            }
            val rowApps = r.apps.ifEmpty { listOf(r.sourceApp) }
            if (!msg.summary && msg.sourceApp in rowApps && msg.kind !in SIDE_KINDS && r.kind !in SIDE_KINDS) continue
            if (r.amountPaise != msg.amountPaise) continue
            if (accountsDiffer(r.account, msg.account)) continue
            val handles = compareHandles(r.handle, msg.handle)
            if (handles == RefMatch.DIFFERENT) continue
            val sameText = msg.textKey != null && msg.textKey in r.textKeys
            val clue = handles == RefMatch.SAME || samePayer(r.payer, msg.payer) || sameText
            val fits = if (msg.summary) {
                gap >= -SUMMARY_SLACK_MS && gap <= SUMMARY_MS && (clue || !namesClash(r.payer, msg.payer))
            } else samePaymentWindow(msg.kind, r.kinds, gap, clue, otherApp = msg.sourceApp !in rowApps)
            if (!fits) continue
            val g = kotlin.math.abs(gap)
            if (best == null || (clue && !bestClue) || (clue == bestClue && g < bestGap)) {
                best = r; bestClue = clue; bestGap = g
            }
        }
        return best?.index
    }

    /**
     * Can a message of [kind] (sms / upi / bank) be the same payment as an earlier row made of [rowKinds], when its
     * payment time is [deltaMs] after the row's (negative = before)? A kind the row already has never joins it
     * (two SMS = two payments).
     */
    private val rrnRegex = Regex("""(?<![0-9])([0-9]{12})(?![0-9])""")

    /** The UPI reference number (RRN): 12 digits, not a phone number / account / amount. */
    fun rrn(text: String?): String? = rrnRegex.findAll(text ?: "").map { it.groupValues[1] }
        .firstOrNull { !it.startsWith("91") || it.length != 12 || it[2] !in '6'..'9' }

    enum class RefMatch { SAME, DIFFERENT, UNKNOWN }

    /**
     * Owner 2026-11-17 (the same money spoken twice, a fraction of a second apart): two messages' references.
     * SAME = equal, or one is the other's tail (an app showing only the last digits);
     * DIFFERENT = two full UPI RRNs (12 digits) that differ: two payments, whatever the amount;
     * UNKNOWN = different KINDS of number (the bank's RRN vs an app's own "T2511..." id, or one missing) -- they say
     * nothing either way, so amount + time + source decide.
     */
    fun compareRefs(a: String?, b: String?): RefMatch {
        val x = a?.trim().orEmpty()
        val y = b?.trim().orEmpty()
        if (x.isEmpty() || y.isEmpty()) return RefMatch.UNKNOWN
        if (x.equals(y, ignoreCase = true)) return RefMatch.SAME
        val shorter = if (x.length <= y.length) x else y
        val longer = if (x.length <= y.length) y else x
        if (shorter.length >= 4 && shorter.all(Char::isDigit) && longer.endsWith(shorter)) return RefMatch.SAME
        val rrnA = x.length == 12 && x.all(Char::isDigit)
        val rrnB = y.length == 12 && y.all(Char::isDigit)
        return if (rrnA && rrnB) RefMatch.DIFFERENT else RefMatch.UNKNOWN
    }

    /** Two account tails (last digits of the bank account) that cannot be the same account. */
    fun accountsDiffer(a: String?, b: String?): Boolean {
        val x = a?.filter(Char::isDigit).orEmpty()
        val y = b?.filter(Char::isDigit).orEmpty()
        if (x.length < 3 || y.length < 3) return false
        val n = minOf(x.length, y.length)
        return x.takeLast(n) != y.takeLast(n)
    }

    fun samePaymentWindow(kind: String, rowKinds: List<String>, deltaMs: Long, sameClue: Boolean = false,
                          otherApp: Boolean = false): Boolean = when {
        // Owner 2026-11-24: two DIFFERENT apps of the same kind may tell one payment (PhonePe and Paytm both notify a
        // credit to the linked bank account; one SMS shown by two SMS apps) -- but two customers may also pay the same
        // amount at the same moment. The same amount + time alone is NEVER enough here: only with proof that it is the
        // same money ([sameClue]: the same payer id / name or the very same message text; the same reference is
        // decided before this). The SAME app twice = two payments.
        kind in rowKinds -> otherApp && sameClue && kind !in SIDE_KINDS && kotlin.math.abs(deltaMs) <= SAME_KIND_APPS_MS
        // "billpay" (owner 2026-11-22) = the bank's own "Bill Paid ... from your account" SMS: as quick and as sure as
        // its debit SMS, and it may be the same money as that debit SMS or the company's thank-you.
        // The bank's two SMS for ONE bill (debit alert + "Bill Paid") come within minutes of each other.
        (kind == "billpay" && "sms" in rowKinds) || (kind == "sms" && "billpay" in rowKinds) ->
            kotlin.math.abs(deltaMs) <= SMS_AFTER_NOTE_MS
        kind == "billpay" -> deltaMs in -NOTE_AFTER_SMS_MS..SMS_AFTER_NOTE_MS   // the "Bill Paid" SMS vs the row's app / receipt
        "billpay" in rowKinds -> deltaMs in -SMS_AFTER_NOTE_MS..NOTE_AFTER_SMS_MS // an app / receipt vs the row's "Bill Paid" SMS
        // Owner 2026-11-22: a bank SMS an HOUR after the app's notification (or the app's an hour after the SMS) was
        // spoken again. Any order, up to 2 h; up to 6 h when the payer's UPI id / name is the same on both.
        sameClue -> kotlin.math.abs(deltaMs) <= SAME_PAYER_MS
        else -> kotlin.math.abs(deltaMs) <= LATE_PAIR_MS
    }

    // ------------------------------------------------------------------ dues, EMI, balance (owner 2026-11-17)

    data class Due(val amountPaise: Long, val dueDate: String, val label: String)

    private val months = listOf("jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec")

    private fun rupees(s: String): Long? = s.replace(",", "").toBigDecimalOrNull()?.movePointRight(2)?.toLong()

    /** The first date in [low] (lower case): "nov 21, 2026", "21 Nov 2026", "25-Nov-2026", "25/Nov/26", "05-12-2026" -> yyyy-MM-dd. */
    private fun dateIn(low: String, year: Int): String? {
        Regex("""\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?\s+(\d{1,2})(?:,?\s*(\d{4}))?""").find(low)?.let { m ->
            val mo = months.indexOf(m.groupValues[1]) + 1
            return "%04d-%02d-%02d".format(m.groupValues[3].toIntOrNull() ?: year, mo, m.groupValues[2].toInt())
        }
        Regex("""\b(\d{1,2})(?:\s+|[-/.])(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?(?:,?\s*(\d{4})|[-/.](\d{4}|\d{2})\b)?""").find(low)?.let { m ->
            val mo = months.indexOf(m.groupValues[2]) + 1
            val y = m.groupValues[3].toIntOrNull() ?: m.groupValues[4].toIntOrNull()?.let { if (it < 100) 2000 + it else it } ?: year
            return "%04d-%02d-%02d".format(y, mo, m.groupValues[1].toInt())
        }
        Regex("""\b(\d{1,2})[-/.](\d{1,2})[-/.](\d{2,4})\b""").find(low)?.let { m ->
            val y = m.groupValues[3].toInt().let { if (it < 100) 2000 + it else it }
            return "%04d-%02d-%02d".format(y, m.groupValues[2].toInt(), m.groupValues[1].toInt())
        }
        return null
    }

    /**
     * A bill / EMI REMINDER (not a payment): "Due date for Andhra Pradesh … ₹1,941.00 due on Nov 21, 2026", "EMI of
     * Rs 2,500 is due on 05-12-2026", "Bill of Rs.821 due by 21/11/2026". Returns the amount, the date (yyyy-MM-dd) and a
     * short label from the title, or null.
     */
    fun dueReminder(title: String?, text: String?, year: Int = java.util.Calendar.getInstance().get(java.util.Calendar.YEAR)): Due? {
        val body = "${title ?: ""} ${text ?: ""}".replace('\n', ' ')
        val low = body.lowercase(Locale.ROOT)
        if (!Regex("""\b(due|payable|pay by|last date)\b""").containsMatchIn(low)) return null
        // "Please ignore if already paid" is on almost every bill / due SMS: it is not a payment (owner 2026-11-22).
        val said = ifPaidIgnore.replace(low, " ")
        if (Regex("""\b(credited|received|debited|paid|sent you|successful)\b""").containsMatchIn(said)) return null
        val amt = Regex("""(?:₹|rs\.?|inr)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)""").find(low)?.groupValues?.get(1)?.let(::rupees) ?: return null
        if (amt <= 0) return null
        // The date AFTER the word "due / pay by / last date" is the due date; a bill's own date ("bill dated 20-Nov-26
        // ... due date 05-Dec-26") is not (owner 2026-11-22).
        val dueAt = Regex("""\b(?:due|pay\s+by|payable|last\s+date|on\s+or\s+before)\b""").find(low)?.range?.first
        val date = (dueAt?.let { dateIn(low.substring(it), year) }) ?: dateIn(low, year)
        val d = date ?: return null
        // An SMS sender id ("AD-APCPDC-S") is shown as the company's name ("APCPDC"), never the raw id.
        val label = (if (isBankSender(title)) billerName(title) else null)
            ?: (title ?: "").replace(Regex("""(?i)^due date for\s+"""), "").trim().take(60).ifEmpty { "Bill" }
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
