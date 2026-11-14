package com.askodox.askodox

import java.util.Locale

/**
 * Pure (no Android imports) reader for the incoming-payment notification of an ALLOWED payment app.
 * Only the amount, a transaction reference and (for the spoken thank-you ONLY) the payer's name leave this
 * function -- never the text or a number. The name is spoken on this phone and never stored or uploaded.
 *
 * A notification is accepted only when it clearly says money came IN and carries exactly one amount.
 * Outgoing payments, requests, OTPs, cashback / rewards / offers, failures and refunds are ignored.
 * Clear incoming wording without a single clear amount is AMBIGUOUS (recorded, never announced as money).
 */
object PaymentAlertParser {
    sealed class Result {
        data class Accepted(val amountPaise: Long, val reference: String?, val payer: String? = null) : Result()
        data class Ambiguous(val reason: String) : Result()

        /**
         * A payment-app message with ONE amount whose wording is neither known incoming nor known outgoing: the
         * phone asks the person once ("did you receive this?"). [template] is the message with the amount
         * replaced by ₹# (title / names never kept).
         */
        data class Unknown(val amountPaise: Long, val template: String) : Result()
        object Ignored : Result()
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
        val joined = listOfNotNull(title, text).joinToString(" ").replace('\n', ' ').trim()
        if (joined.isEmpty()) return Result.Ignored
        val lower = " ${joined.lowercase()} "
        val shape = template(text)
        if (shape.isNotEmpty() && learnedOut.any { it.isNotEmpty() && shape.contains(it) }) return Result.Ignored
        val learned = shape.isNotEmpty() && learnedIn.any { it.isNotEmpty() && shape.contains(it) }
        val rejected = (reject + moreReject).any { it.isNotEmpty() && lower.contains(it.lowercase()) }
        if (!learned && (incoming + moreIncoming).none { it.isNotEmpty() && lower.contains(it.lowercase()) }) {
            if (rejected) return Result.Ignored
            val only = amountRegex.findAll(joined).mapNotNull { toPaise(it.groupValues[1]) }.filter { it > 0 }.toSet()
            return if (only.size == 1 && shape.contains("₹#") && shape.length >= 8) Result.Unknown(only.first(), shape)
            else Result.Ignored
        }
        if (!learned && rejected) return Result.Ignored
        val amounts = amountRegex.findAll(joined).mapNotNull { toPaise(it.groupValues[1]) }.filter { it > 0 }.toSet()
        if (amounts.isEmpty()) return Result.Ambiguous("amount_missing")
        if (amounts.size > 1) return Result.Ambiguous("multiple_amounts")
        val reference = refRegex.findAll(joined).map { it.groupValues[1] }.firstOrNull { it.any(Char::isDigit) }
        return Result.Accepted(amounts.first(), reference, payerName(text) ?: payerName(title))
    }

    private const val AMT = """(?:₹|rs\.?|inr)\s*[0-9][0-9,]*(?:\.[0-9]{1,2})?"""
    private val payerPatterns = listOf(
        Regex("""^\s*(.{2,60}?)\s+(?:has\s+)?sent\s+$AMT\s+to\s+you""", RegexOption.IGNORE_CASE),   // PhonePe
        Regex("""^\s*(.{2,60}?)\s+(?:has\s+)?paid\s+you\s+$AMT""", RegexOption.IGNORE_CASE),          // Google Pay
        Regex("""^\s*(.{2,60}?)\s+has\s+sent\s+you\s+$AMT""", RegexOption.IGNORE_CASE),
        Regex("""received\s+$AMT\s+from\s+(.{2,60}?)(?:\s+(?:on|via|in|to|at)\b|[.,!]|$)""", RegexOption.IGNORE_CASE), // Paytm
        Regex("""$AMT\s+received\s+from\s+(.{2,60}?)(?:\s+(?:on|via|in|to|at)\b|[.,!]|$)""", RegexOption.IGNORE_CASE),
    )
    private val notAName = setOf("you", "upi", "bank", "account", "a/c", "your", "someone", "phonepe", "paytm", "google",
        "gpay", "bhim", "money", "payment", "received")

    /**
     * The payer's display name from an incoming-payment message ("Bhagya sent ₹30 to you" -> "Bhagya"), or null.
     * Letters only: anything with a digit or @ (a number / UPI id) is never returned.
     */
    fun payerName(text: String?): String? {
        val t = (text ?: "").replace('\n', ' ').trim()
        if (t.isEmpty()) return null
        for (re in payerPatterns) {
            val raw = re.find(t)?.groupValues?.get(1) ?: continue
            val name = raw.trim().trim('.', ',', '!', ':', '-', '\'', '"').replace(Regex("\\s+"), " ")
            if (name.length < 2 || name.length > 40) continue
            if (name.any { it.isDigit() || it == '@' || it == '₹' || it == '/' }) continue
            if (name.split(' ').size > 4) continue
            if (name.lowercase().split(' ').any { it in notAName }) continue
            return name
        }
        return null
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

    /** The whole sentence (device voice, or when the cloud voice is not reachable). */
    fun announcement(amountPaise: Long?, language: String, test: Boolean = false, payer: String? = null,
                     shop: String? = null): String = announcementParts(amountPaise, language, test, payer, shop).joinToString(" ")

    /**
     * The thank-you the shop speaks to the customer (owner 2026-11-13): "Thank you <name> garu, 30 rupees reached
     * <shop>, thank you, please come again". Split into parts so the cloud voice can keep the parts that never
     * change (the closing line, the shop part) on the phone and fetch only the name / amount parts once each.
     */
    fun announcementParts(amountPaise: Long?, language: String, test: Boolean = false, payer: String? = null,
                          shop: String? = null): List<String> {
        val parts = mutableListOf<String>()
        if (test) parts += when (language) { "te" -> "టెస్ట్."; "hi" -> "टेस्ट।"; else -> "Test." }
        if (amountPaise == null) {
            parts += when (language) {
                "te" -> "పేమెంట్ నోటిఫికేషన్ వచ్చింది, కానీ మొత్తం స్పష్టంగా లేదు. యాప్‌లో చూడండి."
                "hi" -> "पेमेंट नोटिफिकेशन आया, पर रकम साफ़ नहीं है। ऐप में देखें।"
                else -> "A payment notification arrived but the amount is not clear. Please check the app."
            }
            return parts
        }
        val rupees = amountPaise / 100
        val paise = amountPaise % 100
        val name = payer?.trim()?.takeIf { it.isNotEmpty() }
        val place = shop?.trim()?.take(40)?.takeIf { it.isNotEmpty() }
        when (language) {
            "te" -> {
                parts += if (name != null) "థ్యాంక్ యూ $name గారు." else "థ్యాంక్ యూ."
                parts += "$rupees రూపాయలు" + (if (paise > 0) " $paise పైసలు" else "")
                parts += if (place != null) "$place కి అందాయి." else "మాకు అందాయి."
                parts += "ధన్యవాదాలు, మళ్ళీ విచ్చేయండి."
            }
            "hi" -> {
                parts += if (name != null) "धन्यवाद $name जी।" else "धन्यवाद।"
                parts += "$rupees रुपये" + (if (paise > 0) " $paise पैसे" else "")
                parts += if (place != null) "$place को मिल गए।" else "हमें मिल गए।"
                parts += "फिर से पधारिए।"
            }
            else -> {
                parts += if (name != null) "Thank you $name." else "Thank you."
                parts += "$rupees rupees" + (if (paise > 0) " $paise paise" else "")
                parts += if (place != null) "received at $place." else "received."
                parts += "Please visit again."
            }
        }
        return parts
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
