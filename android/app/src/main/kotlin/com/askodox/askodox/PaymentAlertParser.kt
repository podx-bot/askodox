package com.askodox.askodox

/**
 * Pure (no Android imports) reader for the incoming-payment notification of an ALLOWED payment app.
 * Only the amount and a transaction reference leave this function -- never the text, a name or a number.
 *
 * A notification is accepted only when it clearly says money came IN and carries exactly one amount.
 * Outgoing payments, requests, OTPs, cashback / rewards / offers, failures and refunds are ignored.
 * Clear incoming wording without a single clear amount is AMBIGUOUS (recorded, never announced as money).
 */
object PaymentAlertParser {
    sealed class Result {
        data class Accepted(val amountPaise: Long, val reference: String?) : Result()
        data class Ambiguous(val reason: String) : Result()
        object Ignored : Result()
    }

    private val incoming = listOf(
        "received", "credited", "paid you", "sent you", "has paid", "have paid you", "payment of", "added to your",
        "deposited", "జమ", "అందింది", "అందాయి", "स्वीकार", "प्राप्त", "मिले", "मिला", "जमा",
    )
    private val reject = listOf(
        "paid to", "sent to", "you paid", "you sent", "debited", "debit", "request", "collect", "otp", "one time",
        "cashback", "reward", "offer", "coupon", "scratch", "failed", "declined", "unsuccessful", "pending",
        "refund", "reversed", "due", "reminder", "recharge", "bill pay", " won", "win ", "loan", "emi",
        "verification code", "password", "pin ",
    )
    private val amountRegex = Regex("""(?:₹|\brs\.?|\binr)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)""", RegexOption.IGNORE_CASE)
    private val refRegex = Regex(
        """\b(?:utr|upi\s*ref(?:erence)?|ref(?:erence)?|txn|transaction)\s*(?:id|no\.?|number)?\s*[:#.\-]?\s*([A-Za-z0-9]{6,40})""",
        RegexOption.IGNORE_CASE,
    )

    fun parse(title: String?, text: String?): Result {
        val joined = listOfNotNull(title, text).joinToString(" ").replace('\n', ' ').trim()
        if (joined.isEmpty()) return Result.Ignored
        val lower = " ${joined.lowercase()} "
        if (incoming.none { lower.contains(it) }) return Result.Ignored
        if (reject.any { lower.contains(it) }) return Result.Ignored
        val amounts = amountRegex.findAll(joined).mapNotNull { toPaise(it.groupValues[1]) }.filter { it > 0 }.toSet()
        if (amounts.isEmpty()) return Result.Ambiguous("amount_missing")
        if (amounts.size > 1) return Result.Ambiguous("multiple_amounts")
        val reference = refRegex.findAll(joined).map { it.groupValues[1] }.firstOrNull { it.any(Char::isDigit) }
        return Result.Accepted(amounts.first(), reference)
    }

    fun toPaise(raw: String): Long? {
        val clean = raw.replace(",", "")
        if (clean.isEmpty()) return null
        val parts = clean.split('.')
        val rupees = parts[0].toLongOrNull() ?: return null
        val paise = if (parts.size > 1) parts[1].padEnd(2, '0').take(2).toLongOrNull() ?: 0 else 0
        val total = rupees * 100 + paise
        return if (total in 1..1_000_000_000L) total else null
    }

    /** The sentence spoken for a notification-only event: always asks to confirm in the bank. */
    fun announcement(amountPaise: Long?, language: String, test: Boolean = false): String {
        if (amountPaise == null) {
            return when (language) {
                "te" -> "పేమెంట్ నోటిఫికేషన్ వచ్చింది, కానీ మొత్తం స్పష్టంగా లేదు. యాప్‌లో చూడండి."
                "hi" -> "पेमेंट नोटिफिकेशन आया, पर रकम साफ़ नहीं है। ऐप में देखें।"
                else -> "A payment notification arrived but the amount is not clear. Please check the app."
            }
        }
        val rupees = amountPaise / 100
        val paise = amountPaise % 100
        val text = when (language) {
            "te" -> "$rupees రూపాయల" + (if (paise > 0) " $paise పైసల" else "") +
                " పేమెంట్ నోటిఫికేషన్ వచ్చింది. బ్యాంకులో నిర్ధారించుకోండి."
            "hi" -> "$rupees रुपये" + (if (paise > 0) " $paise पैसे" else "") +
                " का पेमेंट नोटिफिकेशन आया है। बैंक में पक्का कर लें।"
            else -> "Payment notification of $rupees rupees" + (if (paise > 0) " $paise paise" else "") +
                " received. Please confirm in your bank."
        }
        val prefix = when (language) { "te" -> "టెస్ట్. "; "hi" -> "टेस्ट। "; else -> "Test. " }
        return if (test) prefix + text else text
    }

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
}
