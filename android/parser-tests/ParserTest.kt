import com.askodox.askodox.PaymentAlertParser
import com.askodox.askodox.PaymentVoicePack
import com.askodox.askodox.PaymentAlertParser.Result

var fails = 0
fun check(name: String, title: String?, text: String, expect: String) {
    val r = PaymentAlertParser.parse(title, text)
    val got = when (r) {
        is Result.Accepted -> "IN ${r.amountPaise} payer=${r.payer} acct=${r.account} ref=${r.reference}"
        is Result.Outgoing -> "OUT ${r.amountPaise} to=${r.party} acct=${r.account}"
        is Result.Unknown -> "UNKNOWN ${r.amountPaise}"
        is Result.Ambiguous -> "AMBIG"
        else -> "IGNORED"
    }
    val ok = got.startsWith(expect)
    if (!ok) fails++
    println((if (ok) "ok   " else "FAIL ") + name + " -> " + got + (if (ok) "" else "   (want $expect)"))
}

/**
 * The phone's history in miniature: every message goes through the SAME decision the app uses
 * (PaymentAlertParser.pickSamePayment); a new row = one voice, a join = silent.
 */
class Sim {
    val rows = ArrayList<PaymentAlertParser.Row>()
    var spoken = 0
    private val base = 1_795_000_000_000L
    fun get(pkg: String, kind: String, title: String?, text: String, atMin: Long): String {
        val r = PaymentAlertParser.parse(title, text) as Result.Accepted
        val msg = PaymentAlertParser.Msg(pkg, kind, "in", r.amountPaise, base + atMin * 60_000L, r.account, r.reference,
            PaymentAlertParser.upiHandleTail("${title ?: ""} $text"), r.payer, bankSms = kind == "sms",
            textKey = PaymentAlertParser.messageKey(text))
        val hit = PaymentAlertParser.pickSamePayment(rows, msg)
        if (hit != null) {
            val o = rows[hit]
            rows[hit] = o.copy(kinds = o.kinds + kind, apps = o.apps + pkg, textKeys = o.textKeys + listOfNotNull(msg.textKey), reference = o.reference ?: msg.reference,
                handle = o.handle ?: msg.handle, payer = o.payer ?: msg.payer, account = o.account ?: msg.account)
            return "joined"
        }
        rows.add(PaymentAlertParser.Row(rows.size, msg.atMs, pkg, kind, listOf(kind), "in", msg.amountPaise,
            msg.account, msg.reference, msg.handle, msg.payer, apps = listOf(pkg), textKeys = listOfNotNull(msg.textKey)))
        spoken++
        return "spoken"
    }

    /** A message of either direction (a debit SMS, "Paid ₹X to Y"): the same decision as [get]. */
    fun any(pkg: String, kind: String, title: String?, text: String, atMin: Long): String =
        put(pkg, kind, title, text, atMin, false, HashSet())

    /**
     * A payment app's SUMMARY notification, as the phone handles it: every line alone, a row is taken by one line
     * only. Per line: "joined" (silent) or "late" (a payment the history did not have: written, never said as new).
     */
    fun summary(pkg: String, kind: String, title: String?, text: String, atMin: Long): List<String> {
        val taken = HashSet<Int>()
        return PaymentAlertParser.digestLines(title, text).map { put(pkg, kind, null, it, atMin, true, taken) }
    }

    private fun put(pkg: String, kind: String, title: String?, text: String, atMin: Long, summary: Boolean,
                    taken: MutableSet<Int>): String {
        val at = base + atMin * 60_000L
        val msg = when (val r = PaymentAlertParser.parse(title, text)) {
            is Result.Accepted -> PaymentAlertParser.Msg(pkg, kind, "in", r.amountPaise, at, r.account, r.reference,
                PaymentAlertParser.upiHandleTail("${title ?: ""} $text"), r.payer, bankSms = kind == "sms", summary = summary)
            is Result.Outgoing -> PaymentAlertParser.Msg(pkg, kind, "out", r.amountPaise, at, r.account, null, null, r.party,
                bankSms = kind == "sms", summary = summary)
            else -> return "ignored"
        }
        val hit = PaymentAlertParser.pickSamePayment(rows, msg, taken)
        if (hit != null) {
            val o = rows[hit]
            rows[hit] = o.copy(kinds = (o.kinds + kind).distinct(), apps = (o.apps + pkg).distinct(), reference = o.reference ?: msg.reference,
                handle = o.handle ?: msg.handle, payer = o.payer ?: msg.payer, account = o.account ?: msg.account)
            taken.add(hit)
            return "joined"
        }
        rows.add(PaymentAlertParser.Row(rows.size, msg.atMs, pkg, kind, listOf(kind), msg.direction, msg.amountPaise,
            msg.account, msg.reference, msg.handle, msg.payer, apps = listOf(pkg)))
        taken.add(rows.size - 1)
        if (summary) return "late"
        spoken++
        return "spoken"
    }
}

const val SMS = "com.google.android.apps.messaging"
const val PHONEPE = "com.phonepe.app"
const val HDFC_APP = "com.snapwork.hdfc"
const val PAYTM = "net.one97.paytm"
const val TRUECALLER = "com.truecaller"

fun main() {
    // UPI apps
    check("phonepe in", "Received ₹1", "Bhagya sent ₹1 to you.", "IN 100 payer=Bhagya")
    check("gpay in", null, "Ramesh paid you ₹250", "IN 25000 payer=Ramesh")
    check("paytm in", null, "Received ₹50 from Suresh on Paytm", "IN 5000 payer=Suresh")
    check("phonepe out", null, "Paid ₹10 to Bhagya", "OUT 1000 to=Bhagya")
    check("cashback", null, "You won ₹10 cashback", "IGNORED")
    check("request", null, "Ramesh requested ₹200 from you", "IGNORED")
    // Bank SMS -- credits
    check("sbi upi in", null, "Dear SBI UPI User, ur A/cX1234 credited by Rs500 on 15Nov26 by (Ref no 532012345678)", "IN 50000 payer=null acct=1234 ref=532012345678")
    check("sbi trf in", null, "Dear Customer, Your A/C XXXXX1234 has a credit by Transfer of Rs 1,000.00 on 15/11/26 by KOVELAKARU. Avl Bal Rs 12,000.50-SBI", "IN 100000 payer=KOVELAKARU acct=1234")
    check("hdfc in", null, "Money Received - INR 500.00 in your HDFC Bank A/c xx1234 on 15-11-26 by A/c linked to VPA ramesh.k@okaxis (UPI Ref No. 532012345678).", "IN 50000 payer=ramesh k acct=1234 ref=532012345678")
    check("hdfc credit alert vpa", null, "Credit Alert!\nRs.5.00 credited to HDFC Bank A/c XX6911 on 15-11-26 from VPA *akar@ibl (UPI 335406702784)", "IN 500 payer=null acct=6911 ref=335406702784")
    check("hdfc neft", null, "Update! INR 2,000.00 deposited in HDFC Bank A/c XX1234 on 15-NOV-26 for NEFT Cr-HDFC0001-RAMESH. Avl bal INR 9,000.00. Cheque deposits in A/C are subject to clearing", "IN 200000")
    check("icici in", null, "Dear Customer, Acct XX123 is credited with Rs 500.00 on 15-Nov-26 from RAMESH. UPI:532012345678-ICICI Bank.", "IN 50000 payer=RAMESH acct=123 ref=532012345678")
    check("icici neft", null, "ICICI Bank Account XX123 credited:Rs. 500.00 on 15-Nov-26. Info NEFT-xxx. Available Balance is Rs. 10,000.00.", "IN 50000")
    check("axis in", null, "INR 500.00 credited to A/c no. XX1234 on 15-11-26 at 10:20:30 IST. Info- UPI/P2A/532012345678/RAMESH. Avl Bal- INR 5,000.00 - Axis Bank", "IN 50000 payer=RAMESH acct=1234")
    check("kotak in", null, "Received Rs.500.00 in your Kotak Bank a/c X1234 from ramesh@ybl on 15/11/26.UPI Ref:532012345678.", "IN 50000 payer=ramesh acct=1234 ref=532012345678")
    check("canara in", null, "An amount of INR 500.00 has been CREDITED to your account XXX1234 on 15/11/2026 towards UPI. Total Avail.bal INR 5,000.00 - Canara Bank", "IN 50000")
    check("union in", null, "A/c *1234 Credited for Rs:500.00 on 15-11-2026 10:20:30 by Mob Bk ref no 532012345678 Avl Bal Rs:5000.00.Never Share OTP/PIN/CVV-Union Bank", "IN 50000 payer=null acct=1234 ref=532012345678")
    check("bob in", null, "Rs.500.00 Credited to A/c ...1234 thru UPI/532012345678 by ramesh@ybl. Total Bal:Rs.5000.00CR. Avlbl Amt:Rs.5000.00(15-11-2026 10:20:30) - Bank of Baroda", "IN 50000 payer=ramesh acct=1234")
    check("pnb in", null, "Your A/c XX1234 credited INR 500.00 on 15-11-26 through UPI Ref 532012345678. Avl Bal INR 5000.00 CR - PNB", "IN 50000")
    check("indian in", null, "Your a/c no. XXXXX1234 is credited by Rs.500.00 on 15-11-2026 by a/c linked to mobile 9XXXXXX123 (IMPS Ref no 532012345678).", "IN 50000 payer=null acct=1234")
    check("te sms", null, "మీ ఖాతా XX1234 లో రూ. జమ Rs.500 అయ్యింది", "IN 50000")
    // Bank SMS -- debits
    check("sbi out", null, "Dear UPI user A/C X1234 debited by 20.0 on date 15Nov26 trf to RAMESH Refno 532012345678. If not u? call 1800111109. -SBI", "OUT 2000 to=RAMESH acct=1234")
    check("hdfc out", null, "Sent Rs.100.00 From HDFC Bank A/C *1234 To RAMESH STORES On 15/11/26 Ref 532012345678 Not You? Call 18002586161/SMS BLOCK UPI to 7308080808", "OUT 10000 to=RAMESH STORES acct=1234")
    check("icici out", null, "ICICI Bank Acct XX123 debited for Rs 100.00 on 15-Nov-26; RAMESH credited. UPI:532012345678. Call 18002662 for dispute. SMS BLOCK 123 to 9215676766.", "OUT 10000 to=RAMESH acct=123")
    check("axis out", null, "INR 100.00 debited A/c no. XX1234 15-11-26 10:20:30 UPI/P2M/532012345678/SHOP NAME Not you? SMS BLOCKUPI Cust ID to 919951860002 Axis Bank", "OUT 10000 to=SHOP NAME acct=1234")
    check("kotak out", null, "Sent Rs.100.00 from Kotak Bank AC X1234 to shop@ybl on 15-11-26.UPI Ref 532012345678. Not you, https://kotak.com/KBANKT/Fraud", "OUT 10000 to=shop acct=1234")
    // Not payments (SMS app carries all of these)
    check("otp", null, "123456 is your OTP for txn of Rs 500 at AMAZON. Do not share.", "IGNORED")
    check("bill", null, "Your electricity bill of Rs 1,250 is generated. Pay by 20 Nov.", "IGNORED")
    check("offer", null, "Flat 50% off! Shop for Rs 499 only", "IGNORED")
    check("loan", null, "Get instant loan of Rs 5,00,000", "IGNORED")
    check("card due", null, "Your credit card statement: total due Rs 5,000, minimum Rs 250", "IGNORED")
    check("recharge", null, "Recharge of Rs 299 successful. Validity 28 days", "IGNORED")
    check("delivery", null, "Your order of Rs 799 has been delivered", "IGNORED")
    // "My phone" speaks credit / debit in the person's own language (owner 2026-11-16)
    fun said(name: String, lang: String, credit: Boolean, who: String?, mustHave: String, mustNot: String) {
        val t = PaymentAlertParser.personalParts(600, lang, credit, who).joinToString(" ")
        val ok = t.contains(mustHave) && (mustNot.isEmpty() || !t.contains(mustNot))
        if (!ok) fails++
        println((if (ok) "ok   " else "FAIL ") + name + " -> " + t)
    }
    said("te credit", "te", true, "Ramesh", "జమ అయ్యాయి", "క్రెడిట్")
    said("te debit", "te", false, "Ramesh", "వెళ్ళాయి", "డెబిట్")
    said("hi credit", "hi", true, null, "जमा हुए", "क्रेडिट")
    said("ta credit", "ta", true, "Ramesh", "வந்தது", "")
    said("en debit", "en", false, "Ramesh", "Spent", "Debited")
    // Owner 2026-11-17 phone: the exact messages of one morning
    check("hdfc sms 240", "JD-HDFCBK-S", "Credit Alert!\nRs.240.00 credited to HDFC Bank A/c XX6911 on 17-11-26 from VPA *2317@ibl (UPI 925142780111)", "IN 24000 payer=null acct=6911 ref=925142780111")
    check("hdfc app 240", "Money Received!", "MOHAMMAD HAFIZ (9502072317@ibl) sent you ₹240.00.", "IN 24000")
    check("phonepe 2000", "GH", "sent ₹2,000 to you.", "IN 200000")
    check("gpay due", "Due date for Andhra Pradesh electricity", "₹821.00 due on Nov 21, 2026.", "IGNORED")
    // Owner 2026-11-18: PhonePe UPI Circle -- a member paid a third person from the account. Never "received",
    // never "amount not clear".
    check("circle no amount", "Payment successful!", "Manohar Annayya has paid BHUKYA SUJATHA.", "IGNORED")
    check("circle with amount", "Payment of ₹2 successful by 2283", "Sujatha has paid BHUKYA SUJATHA.", "OUT 200 to=BHUKYA SUJATHA")
    check("circle words", null, "₹50 paid from your UPI Circle by Ravi to Kirana Store", "OUT 5000")
    check("has paid you stays in", null, "Ramesh has paid you ₹300", "IN 30000 payer=Ramesh")
    check("has paid to you stays in", null, "Ramesh has paid ₹300 to you", "IN 30000")
    fun yes(name: String, ok: Boolean) { if (!ok) fails++; println((if (ok) "ok   " else "FAIL ") + name) }
    yes("bank sender JD-HDFCBK-S", PaymentAlertParser.isBankSender("JD-HDFCBK-S"))
    yes("bank sender old AD-HDFCBK", PaymentAlertParser.isBankSender("AD-HDFCBK"))
    yes("bank sender VM-ICICIT-T", PaymentAlertParser.isBankSender(" VM-ICICIT-T "))
    yes("promo sender is not a bank", !PaymentAlertParser.isBankSender("VK-OFFERS-P"))
    yes("phone number is not a bank", !PaymentAlertParser.isBankSender("+919876543210"))
    yes("contact name is not a bank", !PaymentAlertParser.isBankSender("HDFC Bank"))
    yes("fake: +91 mobile", PaymentAlertParser.looksLikePersonNumber("+91 98765 43210"))
    yes("fake: 10 digits", PaymentAlertParser.looksLikePersonNumber("9876543210"))
    yes("bank id is not a person", !PaymentAlertParser.looksLikePersonNumber("JD-HDFCBK-S"))
    yes("verified name is not a person", !PaymentAlertParser.looksLikePersonNumber("HDFC Bank"))
    yes("short code is not a person", !PaymentAlertParser.looksLikePersonNumber("56767"))
    yes("no title is not a person", !PaymentAlertParser.looksLikePersonNumber(null))
    yes("handle from sms", PaymentAlertParser.upiHandleTail("from VPA *2317@ibl (UPI 925142780111)") == "2317@ibl")
    yes("handle from app", PaymentAlertParser.upiHandleTail("MOHAMMAD HAFIZ (9502072317@ibl) sent you") == "2317@ibl")
    yes("no handle", PaymentAlertParser.upiHandleTail("GH sent ₹2,000 to you.") == null)
    // Owner 2026-11-22: a masked id still tells two people apart; an e-mail or the shop's own id is never the payer.
    yes("masked handle", PaymentAlertParser.upiHandleTail("Rs.300.00 credited to HDFC Bank A/c XX6911 from VPA *akar@ibl (UPI 532612349999)") == "akar@ibl")
    yes("named handle", PaymentAlertParser.upiHandleTail("by A/c linked to VPA ramesh.k@okaxis (UPI Ref No. 532012345678)") == "eshk@okaxis")
    yes("e-mail is not a handle", PaymentAlertParser.upiHandleTail("Rs 300 credited. Write to care@hdfcbank.com") == null)
    yes("shop's own id is not the payer", PaymentAlertParser.upiHandleTail("Rs 300 credited to VPA myshop@icici from RAMESH") == null)
    yes("payer after the shop's own id", PaymentAlertParser.upiHandleTail("credited to VPA myshop@icici from 9502072317@ybl") == "2317@ybl")
    yes("handles same", PaymentAlertParser.compareHandles("2317@ibl", "2317@IBL") == PaymentAlertParser.RefMatch.SAME)
    yes("handles differ", PaymentAlertParser.compareHandles("2317@ibl", "akar@ibl") == PaymentAlertParser.RefMatch.DIFFERENT)
    yes("handle missing", PaymentAlertParser.compareHandles(null, "akar@ibl") == PaymentAlertParser.RefMatch.UNKNOWN)
    yes("same payer exact", PaymentAlertParser.samePayer("MOHAMMAD HAFIZ", "Mohammad Hafiz"))
    yes("same payer other order", PaymentAlertParser.samePayer("KOVELAKARU MANOHAR", "Manohar Kovelakaru"))
    yes("same payer cut short by the bank", PaymentAlertParser.samePayer("MOHAMMAD HAF", "MOHAMMAD HAFIZ"))
    yes("one shared word is not the same payer", !PaymentAlertParser.samePayer("RAMESH KUMAR", "SURESH KUMAR"))
    yes("first name only is not enough", !PaymentAlertParser.samePayer("RAMESH", "RAMESH BABU"))
    yes("no name = no clue", !PaymentAlertParser.samePayer(null, "RAMESH"))
    // Owner 2026-11-22: the name WAS on the notification but never spoken.
    check("phonepe name with upi id in brackets", null, "MOHAMMAD HAFIZ (9502072317@ibl) sent you ₹300", "IN 30000 payer=MOHAMMAD HAFIZ")
    check("name sent you", "Money received", "Ramesh Kumar sent you ₹300", "IN 30000 payer=Ramesh Kumar")
    check("name + id has sent to you", "Received ₹300", "RAMESH KUMAR (9502072317@ybl) has sent ₹300 to you", "IN 30000 payer=RAMESH KUMAR")
    check("title amount, text from name", "₹300 received", "from RAMESH KUMAR", "IN 30000 payer=RAMESH KUMAR")
    check("title name, text sent you", "RAMESH KUMAR", "sent you ₹300", "IN 30000 payer=RAMESH KUMAR")
    check("app label in title is never the name", "PhonePe", "sent you ₹300", "IN 30000 payer=null")
    val min = 60_000L
    yes("late bank app 13 min after sms = same", PaymentAlertParser.samePaymentWindow("bank", listOf("sms"), 13 * min))
    yes("app 59 min after sms = same", PaymentAlertParser.samePaymentWindow("upi", listOf("sms"), 59 * min))
    // Owner 2026-11-22 ("however late the second message comes, one payment is spoken once"): any order, up to 2 h.
    yes("app 61 min after sms = same (owner 2026-11-22)", PaymentAlertParser.samePaymentWindow("upi", listOf("sms"), 61 * min))
    yes("app 2 h + 1 min after sms, no clue = new", !PaymentAlertParser.samePaymentWindow("upi", listOf("sms"), 121 * min))
    yes("sms 2 min after app = same", PaymentAlertParser.samePaymentWindow("sms", listOf("upi"), 2 * min))
    yes("bank sms 60 min after app = same (owner 2026-11-22, was spoken again)", PaymentAlertParser.samePaymentWindow("sms", listOf("upi"), 60 * min))
    yes("sms 2 h + 1 min after app, no clue = new", !PaymentAlertParser.samePaymentWindow("sms", listOf("upi"), 121 * min))
    yes("same payer: sms 5 h after app = same", PaymentAlertParser.samePaymentWindow("sms", listOf("upi"), 300 * min, sameClue = true))
    yes("same payer: 6 h + 1 min = new", !PaymentAlertParser.samePaymentWindow("sms", listOf("upi"), 361 * min, sameClue = true))
    yes("same payer never joins a kind the row has", !PaymentAlertParser.samePaymentWindow("sms", listOf("sms"), min, sameClue = true))
    yes("two sms never join", !PaymentAlertParser.samePaymentWindow("sms", listOf("sms"), 0))
    yes("sms + app already paired: third sms = new", !PaymentAlertParser.samePaymentWindow("sms", listOf("sms", "upi"), min))
    yes("bank app + upi app 5 min = same", PaymentAlertParser.samePaymentWindow("bank", listOf("upi"), 5 * min))
    val due = PaymentAlertParser.dueReminder("Due date for Andhra Pradesh Southern Power", "₹1,941.00 due on Nov 21, 2026.", 2026)
    yes("gpay due reminder", due?.amountPaise == 194100L && due.dueDate == "2026-11-21" && due.label.startsWith("Andhra"))
    val due2 = PaymentAlertParser.dueReminder("HDFC Bank", "EMI of Rs 2,500 for loan a/c XX12 is due on 05-12-2026", 2026)
    yes("emi due reminder", due2?.amountPaise == 250000L && due2.dueDate == "2026-12-05")
    yes("a payment is not a due", PaymentAlertParser.dueReminder("HDFC", "Rs.240 credited to HDFC Bank A/c XX6911", 2026) == null)
    yes("emi debit", PaymentAlertParser.isEmi("Rs 1,941 debited from A/c XX6911 towards EMI of loan"))
    yes("nach debit", PaymentAlertParser.isEmi("NACH DR of Rs.1941 by BAJAJFIN"))
    yes("normal debit not emi", !PaymentAlertParser.isEmi("Rs 50 debited to VPA shop@ybl"))
    yes("balance avl bal", PaymentAlertParser.availableBalance("Rs 240 credited. Avl Bal Rs 32,140.00") == 3214000L)
    yes("balance available", PaymentAlertParser.availableBalance("Available balance: INR 1,234.50") == 123450L)
    yes("no balance", PaymentAlertParser.availableBalance("Rs 240 credited to A/c XX6911") == null)
    // Owner 2026-11-17: one common key -- the UPI RRN -- for the SMS and the app's notification of the same money.
    val R = PaymentAlertParser.RefMatch.SAME
    yes("rrn from sms", PaymentAlertParser.rrn("from VPA *2317@ibl (UPI 925142780111)") == "925142780111")
    yes("rrn not a +91 phone", PaymentAlertParser.rrn("call 919876543210 now") == null)
    yes("same rrn = same", PaymentAlertParser.compareRefs("925142780111", "925142780111") == R)
    yes("tail = same", PaymentAlertParser.compareRefs("925142780111", "0111") == R)
    yes("two rrn = different", PaymentAlertParser.compareRefs("925142780111", "925142780999") == PaymentAlertParser.RefMatch.DIFFERENT)
    yes("rrn vs app txn id = unknown", PaymentAlertParser.compareRefs("925142780111", "T2511171845123456") == PaymentAlertParser.RefMatch.UNKNOWN)
    yes("missing = unknown", PaymentAlertParser.compareRefs(null, "925142780111") == PaymentAlertParser.RefMatch.UNKNOWN)
    yes("accounts 6911 vs 7571 differ", PaymentAlertParser.accountsDiffer("6911", "XX7571"))
    yes("accounts 6911 vs 06911 same", !PaymentAlertParser.accountsDiffer("6911", "06911"))
    yes("one account missing = not different", !PaymentAlertParser.accountsDiffer(null, "6911"))
    val app = PaymentAlertParser.parse("PhonePe", "Received ₹240 from MOHAMMAD HAFIZ. UPI Ref No. 925142780111. Transaction ID T2511171845123456")
    yes("app notification carries the RRN, not its own id", app is PaymentAlertParser.Result.Accepted && app.reference == "925142780111")
    // Owner 2026-11-21 (Rs 3,000 RECEIVED, shown as minus): money sent / paid / credited TO YOUR account is incoming.
    check("phonepe to your bank", "Received ₹3,000", "KOTA SRINIVAS sent ₹3,000 to your ICICI Bank account", "IN 300000 payer=KOTA SRINIVAS")
    check("received sent to your a/c", null, "Received ₹3,000 from KOTA SRINIVAS. Sent to your bank account XX4321", "IN 300000")
    check("paid to your account", null, "₹3,000 received! SRINIVAS paid to your account", "IN 300000")
    check("real debit still out", null, "Paid ₹3,000 to KOTA SRINIVAS", "OUT 300000 to=KOTA SRINIVAS")
    check("icici debit with credited still out", null, "ICICI Bank Acct XX123 debited for Rs 3000.00 on 20-Nov-26; SRINIVAS credited. UPI:532012345678", "OUT 300000")
    // Incoming + outgoing words, no strong debit word = a doubtful debit (❓ on the phone, never sure).
    val mixed = PaymentAlertParser.parse(null, "Received ₹3,000 from SRINIVAS, sent to Ramesh")
    yes("mixed wording is doubtful", mixed is Result.Outgoing && mixed.doubtful)
    val sure = PaymentAlertParser.parse(null, "ICICI Bank Acct XX123 debited for Rs 3000.00; SRINIVAS credited.")
    yes("strong debit not doubtful", sure is Result.Outgoing && !sure.doubtful)
    // Owner 2026-11-21 (Airtel bill paid, voice said "3081 received"): a company thanking you for YOUR payment = money out.
    check("airtel thanks for payment", "AD-AIRTEL-S", "Thank you for the payment of Rs.3081.00 for your Airtel Postpaid number 98XXXXXX21. Txn ID 1234567890", "OUT 308100 to=AIRTEL")
    check("biller received your payment", "VM-ACTFBR", "Dear Customer, we have received your payment of Rs 3,081 towards your account 1234.", "OUT 308100 to=ACTFBR")
    check("payment received towards your bill", null, "Payment of ₹3,081 received towards your Jio bill. Thank you", "OUT 308100")
    check("your payment successful", null, "Your payment of ₹499 is successful for Airtel Xstream", "OUT 49900")
    check("payment received from a person still in", null, "Payment of ₹500 received from Ramesh", "IN 50000")
    check("hdfc credit still in", "AD-HDFCBK-S", "Credit Alert! Rs.3081.00 credited to HDFC Bank A/c XX6911 from VPA ramesh@ybl (UPI 335406702784)", "IN 308100")
    // Owner 2026-11-21: refund / bill / initiated / failed messages are explained, never money; a landed refund is money in.
    check("refund landed = in", "AX-HDFCBK-S", "Refund of Rs.499.00 credited to your HDFC Bank A/c XX6911 from AMAZON", "IN 49900")
    check("refund initiated = not money", null, "Refund of ₹499 initiated. It will be credited to your account in 5-7 working days", "IGNORED")
    check("payment initiated = not money", "AD-AIRTEL-S", "Payment of Rs 3081 initiated for your Airtel number. Txn 123456", "IGNORED")
    check("bill generated = not money", "AD-AIRTEL-S", "Your Airtel bill of Rs 3081 has been generated. Pay by 25-Nov", "IGNORED")
    yes("notice refund", PaymentAlertParser.notice(null, "Refund of ₹499 initiated. It will be credited in 5-7 days")?.kind == "refund_started")
    yes("notice pending", PaymentAlertParser.notice("AD-AIRTEL-S", "Payment of Rs 3081 initiated for your Airtel number")?.kind == "pending")
    yes("notice bill", PaymentAlertParser.notice("AD-AIRTEL-S", "Your Airtel bill of Rs 3081 has been generated")?.let { it.kind == "bill" && it.amountPaise == 308100L } == true)
    yes("notice failed", PaymentAlertParser.notice(null, "Payment of ₹200 to Ramesh failed. Money will be refunded if debited")?.kind in setOf("failed", "refund_started"))
    yes("notice suspect link", PaymentAlertParser.notice("+919876543210", "Rs 5000 credited! Click http://bit.ly/x to claim")?.kind == "suspect")
    yes("bank safety lines are not suspect", PaymentAlertParser.notice("AX-HDFCBK-S", "Rs 50 debited from A/c XX6911. Not you? Call 18002586161") == null)
    check("fraud credited click = not money", null, "Rs 5000 credited to your account! Click here to claim", "IGNORED")
    check("insurance claim credited still in", "AX-HDFCBK-S", "Rs.12,000.00 credited to HDFC Bank A/c XX6911 towards claim settlement", "IN 1200000")
    yes("promo sender", PaymentAlertParser.isPromoSender("VM-AIRTEL-P") && !PaymentAlertParser.isPromoSender("AD-AIRTEL-S"))
    yes("promo is not a bank", !PaymentAlertParser.isBankSender("VM-HDFCBK-P"))
    // A person's correction on a row teaches every message of the same kind (any name, any amount).
    val sk = PaymentAlertParser.skeleton("Sent ₹3,000 to RAMESH via PhonePe")
    yes("skeleton drops names", sk == PaymentAlertParser.skeleton("Sent ₹45 to SURESH KUMAR via PhonePe") && !sk.contains("ramesh"))
    val taught = PaymentAlertParser.parse(null, "Sent ₹45 to SURESH via PhonePe", learnedKinds = mapOf(sk to "in"))
    yes("correction in = incoming", taught is Result.Accepted && taught.amountPaise == 4500L)
    val none = PaymentAlertParser.parse(null, "Sent ₹45 to SURESH via PhonePe", learnedKinds = mapOf(sk to "none"))
    yes("correction none = ignored", none is Result.Ignored)
    // Owner 2026-11-22 (HDFC "Bill Paid!" SMS was kept only as a "bill generated" note): a bill that WAS paid is money
    // that went out -- every bank, UPI app and biller. (Numbers below are made up.)
    check("hdfc bill paid", "AD-HDFCBK-S", "Bill Paid!\nAPCPDC Ele Bill 1234567890123 of Rs. 962.00 paid on 22-Nov-2026 from HDFC Bank Account XXXXXXXXXX1234.\nBillPay Ref: HGANP0AAAA0012345678", "OUT 96200 to=APCPDC Ele Bill acct=1234")
    check("hdfc bill paid 1941", "JD-HDFCBK-S", "Bill Paid!\nAPCPDC Ele Bill 1234567890456 of Rs. 1941.00 paid on 22-Nov-2026 from HDFC Bank Account XXXXXXXXXX1234.\nBillPay Ref: HGANP0BBBB0012345679", "OUT 194100 to=APCPDC Ele Bill acct=1234")
    val hd = PaymentAlertParser.parse("AD-HDFCBK-S", "Bill Paid!\nAPCPDC Ele Bill 1234567890123 of Rs. 962.00 paid on 22-Nov-2026 from HDFC Bank Account XXXXXXXXXX1234.\nBillPay Ref: HGANP0AAAA0012345678")
    yes("bank bill paid = a paid bill from the person's own account", hd is Result.Outgoing && hd.bill && hd.ownAccount && !hd.biller && !hd.doubtful)
    check("icici bill payment made", "VM-ICICIT-S", "Dear Customer, bill payment of Rs 962.00 for APSPDCL has been made from your ICICI Bank Account XX123. Ref no 123456789.", "OUT 96200 to=APSPDCL acct=123")
    check("sbi bill payment successful", "AD-SBIINB-S", "Your bill payment of Rs.962.00 towards APCPDCL is successful. Ref No. SB123456. -SBI", "OUT 96200 to=APCPDCL")
    check("axis bill payment", null, "Bill payment for APSPDCL of INR 962.00 is successful from A/c no. XX1234 on 22-11-26. Axis Bank", "OUT 96200 to=APSPDCL acct=1234")
    check("kotak bill payment", null, "Bill Payment of Rs 962.00 to APCPDCL from Kotak Bank AC X1234 is successful. Ref 123456", "OUT 96200 to=APCPDCL acct=1234")
    check("phonepe bill app", "Bill Payment Successful", "₹962 paid for APCPDCL electricity bill", "OUT 96200 to=APCPDCL electricity")
    check("paytm bill app", null, "Electricity bill payment of ₹962 is successful", "OUT 96200")
    check("amazon pay bill", null, "Your bill payment of ₹962 for APSPDCL was successful", "OUT 96200 to=APSPDCL")
    check("bill of amount paid", null, "Electricity bill of ₹962 paid successfully", "OUT 96200 to=Electricity")
    check("payment towards bill successful", null, "Payment of Rs 962 towards your electricity bill is successful", "OUT 96200 to=electricity")
    check("water bill paid te sender", "VK-HMWSSB-S", "Your water bill of Rs.450 has been paid. Receipt No 778899", "OUT 45000 to=water")
    // The company's own receipt (electricity / water / gas boards name the service number, not "your").
    check("discom receipt towards sc no", "AD-APCPDC-S", "Dear Consumer, Rs.962 received towards SC No 1234567890123 on 22-11-2026. Receipt No 998877. Thank you", "OUT 96200 to=APCPDC")
    check("discom payment received for sc no", "AD-APCPDC-S", "Payment of Rs.962 received for SC No 1234567890123. Receipt No 998877", "OUT 96200 to=APCPDC")
    check("bill payment received", "VM-APCPDC", "Bill payment of Rs 962 received successfully. Receipt 123", "OUT 96200 to=APCPDC")
    val ack = PaymentAlertParser.parse("AD-APCPDC-S", "Dear Consumer, Rs.962 received towards SC No 1234567890123 on 22-11-2026. Receipt No 998877")
    yes("company receipt = biller, not the bank's word", ack is Result.Outgoing && ack.biller && !ack.bill && !ack.ownAccount)
    // Any service payment that is DONE from the person's own account (recharge, premium, transfer ...).
    check("recharge from own account", null, "Recharge of Rs 299 for 98XXXXXX21 is successful from your HDFC Bank A/c XX1234", "OUT 29900 to=null acct=1234")
    check("paid from own account", null, "Rs 500 paid from A/c XX1234 to RAMESH on 22-11-26", "OUT 50000 to=RAMESH acct=1234")
    check("premium from own account", null, "Payment of Rs 2,500 for LIC premium has been made from your SBI A/c XX1234", "OUT 250000")
    check("premium paid", null, "Your LIC premium of Rs 2,500 for policy 123456789 has been paid successfully", "OUT 250000")
    check("emi paid from own account", null, "EMI of Rs 2,500 for loan a/c XX12 has been paid from your A/c XX1234", "OUT 250000")
    check("lender got the emi", "AD-BAJAJF-S", "Your EMI of Rs 2,500 for loan XX12 has been received. Thank you", "OUT 250000 to=BAJAJF")
    // The payer's own success message without the word "bill" (was read as money RECEIVED).
    check("payment to biller successful", "PhonePe", "Payment of ₹962 to APCPDCL successful", "OUT 96200 to=APCPDCL")
    check("payment for service successful", null, "Gas booking payment of Rs 950 for Indane is successful. Paid via UPI", "OUT 95000 to=Indane")
    check("payment for your order successful", null, "Payment of ₹350 for your order was successful", "OUT 35000")
    check("payment successful from a person stays in", null, "Payment of ₹500 to your account from Ramesh is successful", "IN 50000")
    check("payment for order stays as it was", null, "Payment of ₹500 for order 123 was successful", "IN 50000")
    check("paid to a card", "CRED", "paid ₹5,000 to HDFC Bank credit card. payment successful", "OUT 500000 to=null")
    check("autopay done", "AD-HDFCBK-S", "HDFC Bank: Autopay (E-mandate) of Rs 199 towards Netflix is successfully processed from your Credit Card ending 1234", "OUT 19900 to=Netflix")
    // The bank's own debit SMS is money that left -- whatever it was FOR (these were dropped for the words EMI / loan / recharge).
    check("emi debit sms", "AD-HDFCBK-S", "Rs 1,941 debited from A/c XX1234 towards EMI of loan", "OUT 194100 to=null acct=1234")
    check("emi debited from your account", "AD-HDFCBK-S", "EMI of Rs 2,500 for loan a/c XX12 has been debited from your A/c XX1234", "OUT 250000")
    check("recharge debit sms", "AD-HDFCBK-S", "Rs 299 debited from A/c XX1234 for Jio recharge on 22-11-26", "OUT 29900")
    check("bill payment debit sms", "AD-HDFCBK-S", "Rs 962.00 debited from A/c XX1234 towards bill payment of APCPDCL on 22-11-26", "OUT 96200")
    check("card dues debit sms", "AD-HDFCBK-S", "Rs 5,000 debited from A/c XX1234 towards credit card dues", "OUT 500000")
    check("you paid for recharge", "Google Pay", "You paid ₹299 for Jio recharge", "OUT 29900")
    check("sbi has a debit by transfer", "AD-SBIBNK-S", "Dear Customer, Your A/C XXXXX1234 has a debit by transfer of Rs 962.00 on 22/11/26. Avl Bal Rs 5,000.00.-SBI", "OUT 96200 to=null acct=1234")
    check("emi will be debited = not yet", "AD-HDFCBK-S", "EMI of Rs 2,500 will be debited from your A/c XX1234 on 05-Dec. Maintain balance", "IGNORED")
    check("emi is due, to be debited", "AD-HDFCBK-S", "Your EMI of Rs 2,500 is due on 05-Dec-2026. Amount to be debited from A/c XX1234", "IGNORED")
    check("loan advert", "AD-HDFCBK-S", "Pre-approved loan of Rs 5,00,000. Apply now, EMI debited monthly from your account", "IGNORED")
    check("loan disbursed, fee debited = not a payment of the loan amount", "AD-HDFCBK-S", "Your loan of Rs 50,000 has been disbursed and credited to your A/c XX1234. Processing fee of Rs 590 debited", "IGNORED")
    check("debit failed for emi", "AD-HDFCBK-S", "EMI of Rs 2,500 could not be debited from A/c XX1234: debit failed. Please pay", "IGNORED")
    // Company receipts in every wording.
    check("discom paid for usc", "AD-TSSPDC-S", "TSSPDCL: Rs.1941 paid for USC No 123456789 on 22-11-2026, Receipt No 123. Thank you", "OUT 194100 to=TSSPDC")
    check("card payment received", "AD-HDFCBK-S", "Payment of Rs 5,000 received on your HDFC Bank Credit Card ending 1234 on 22-11-26. Thank you", "OUT 500000")
    check("insurer got the premium", "AD-LICIND-S", "Premium of Rs.2500 for policy 123456789 received on 22/11/2026. Next due 02/2027", "OUT 250000 to=LICIND")
    check("emi received from a person is not my payment", null, "EMI amount Rs 2,500 received from Ramesh", "IGNORED")
    check("done, biller updates later", null, "Bill payment of Rs 962 for APCPDCL is successful. It will be updated at the biller's end in 2 working days", "OUT 96200 to=APCPDCL")
    check("premium paid, next due named", "AD-LICIND-S", "Premium of Rs.2500 for policy 123456789 paid successfully. Next due 02/2027", "OUT 250000")
    // A shop's own message about money that CAME IN is never a company receipt.
    check("received towards a bill from a person stays in", null, "Rs.500 received towards bill no 12 from Ramesh", "IN 50000")
    check("bill payment received from a person is not my payment", null, "Bill payment of Rs 500 received from Ramesh", "IGNORED")
    check("received for consumer from a person stays in", null, "Rs 500 received for consumer no 12 from Ramesh Kumar", "IN 50000")
    check("received, settlement later stays in", "Paytm for Business", "Received ₹500 from Ramesh. Settlement will be processed tomorrow", "IN 50000 payer=Ramesh")
    check("payment to your shop is not my payment out", null, "Payment of ₹500 to your shop is successful", "IN 50000")
    check("operator recharge message stays ignored", null, "Recharge of Rs 299 successful. Validity 28 days", "IGNORED")
    // NOT paid: generated / due / failed / pending / asked for / an offer -- never money that went out.
    check("bill generated ignore if paid", "AD-APCPDC-S", "Your electricity bill of Rs 962 is generated. Due date 05-12-2026. Please ignore if already paid.", "IGNORED")
    check("bill payment failed", null, "Bill payment of Rs 962 for APSPDCL failed. Amount will be refunded in 3 days", "IGNORED")
    check("bill payment pending", null, "Your bill payment of Rs 962 for APSPDCL is pending. We will update you", "IGNORED")
    check("pay your bill offer", null, "Pay your electricity bill of Rs 962 now and get cashback", "IGNORED")
    check("bill not paid yet", null, "Your APCPDCL bill of Rs 962 is not paid. Pay now to avoid disconnection", "IGNORED")
    check("payment can be made", null, "Dear customer, bill of Rs 962 for Nov. Payment can be made online or at the counter", "IGNORED")
    check("otp for bill payment", null, "123456 is OTP for bill payment of Rs 962 from your A/c XX1234. Do not share", "IGNORED")
    check("autopay will be processed", null, "Autopay of Rs 199 for Netflix will be processed from A/c XX1234 on 5 Dec", "IGNORED")
    // Money that came IN stays in, whatever it says about a bill.
    check("paid you for bill stays in", null, "Ramesh paid you ₹500 for bill 12", "IN 50000 payer=Ramesh")
    check("somebody else paid a bill = not my money out", null, "Ramesh paid ₹500 for bill 12", "IGNORED")
    check("bill paid by another person", null, "Bill 12 of Rs 500 paid by Ramesh via UPI", "IGNORED")
    check("bill that only names the last payment", "AD-APCPDC-S", "Bill for SC 1234567890123: Rs 962. Last paid Rs 900 on 20-Oct", "IGNORED")
    check("refund of a paid bill = in", "AX-HDFCBK-S", "Refund of Rs.962.00 for your bill paid on 20-Nov credited to your HDFC Bank A/c XX1234", "IN 96200")
    yes("failed bill = failed / refund note", PaymentAlertParser.notice(null, "Bill payment of Rs 962 for APSPDCL failed. Amount will be refunded in 3 days")?.kind in setOf("failed", "refund_started"))
    // One bill, several messages: the bank's "Bill Paid" SMS (billpay), its debit SMS (sms) and the company's receipt (biller).
    yes("debit sms 2 min after bill paid sms = same", PaymentAlertParser.samePaymentWindow("sms", listOf("billpay"), 2 * min))
    yes("bill paid sms 2 min after debit sms = same", PaymentAlertParser.samePaymentWindow("billpay", listOf("sms"), 2 * min))
    yes("company receipt 45 min after bill paid sms = same", PaymentAlertParser.samePaymentWindow("biller", listOf("billpay"), 45 * min))
    yes("app message 5 min before bill paid sms = same", PaymentAlertParser.samePaymentWindow("billpay", listOf("upi"), 5 * min))
    yes("debit sms 30 min away from the bill paid sms = another payment", !PaymentAlertParser.samePaymentWindow("sms", listOf("billpay"), -30 * min))
    yes("two bill paid sms never join", !PaymentAlertParser.samePaymentWindow("billpay", listOf("billpay"), 0))
    yes("bill paid sms 20 min after app = new", !PaymentAlertParser.samePaymentWindow("billpay", listOf("upi"), 20 * min))
    // Bill generated / due: "ignore if already paid" is not a payment; an SMS sender id is shown as the company's name.
    val gen = PaymentAlertParser.dueReminder("AD-APCPDC-S", "Dear Consumer, your bill for SC No 1234567890123 is Rs.962.00. Due date 05-12-2026. Please ignore if already paid.", 2026)
    yes("bill generated with 'ignore if paid' = a due", gen?.amountPaise == 96200L && gen.dueDate == "2026-12-05" && gen.label == "APCPDC")
    val gen2 = PaymentAlertParser.dueReminder("VM-AIRTEL-S", "Your Airtel bill of Rs 499 is generated. Pay by 25-Nov-2026. If you have already paid, kindly ignore.", 2026)
    yes("pay by + 'if already paid ignore' = a due", gen2?.amountPaise == 49900L && gen2.dueDate == "2026-11-25")
    val gen3 = PaymentAlertParser.dueReminder("AD-AIRTEL-S", "Your Airtel bill dated 20-Nov-26 for Rs 499 is generated. Due date 05-Dec-26.", 2026)
    yes("the date after 'due date' is the due date, not the bill's own date", gen3?.dueDate == "2026-12-05" && gen3.amountPaise == 49900L && gen3.label == "AIRTEL")
    val gen4 = PaymentAlertParser.dueReminder("AD-APCPDC-S", "Bill dt 01-11-2026 for SC 1234567890123: Rs.962 payable by 15-11-2026", 2026)
    yes("payable by", gen4?.dueDate == "2026-11-15")
    yes("a paid bill is not a due", PaymentAlertParser.dueReminder("AD-HDFCBK-S", "Bill Paid! APCPDC Ele Bill 1234567890123 of Rs. 962.00 paid on 22-Nov-2026 from HDFC Bank Account XXXXXXXXXX1234.", 2026) == null)
    yes("bill generated without a date = a bill note", PaymentAlertParser.notice("AD-APCPDC-S", "Your electricity bill of Rs 962 has been generated for Nov-2026")?.kind == "bill")
    // Owner 2026-11-22 ("refunds, credits, cancel, generated, autopay ... read those words too; a fake one = warn")
    check("cashback landed = in", "AX-HDFCBK-S", "Rs.50.00 cashback credited to your HDFC Bank A/c XX1234 on 22-11-26", "IN 5000")
    check("cashback offer = ignored", null, "Win up to ₹100 cashback on your next recharge!", "IGNORED")
    check("interest credited = in", "AX-SBIINB-S", "Interest of Rs 120.00 credited to your A/c XX1234 on 22-11-26", "IN 12000")
    yes("cashback is spoken as cashback", (PaymentAlertParser.parse("AX-HDFCBK-S", "Rs.50.00 cashback credited to your HDFC Bank A/c XX1234") as? Result.Accepted)?.bonus == "cashback")
    yes("interest is spoken as interest", (PaymentAlertParser.parse("AX-SBIINB-S", "Interest of Rs 120.00 credited to your A/c XX1234") as? Result.Accepted)?.bonus == "interest")
    yes("a plain credit has no bonus", (PaymentAlertParser.parse(null, "Ramesh paid you ₹250") as? Result.Accepted)?.bonus == null)
    check("cancelled payment = not money", null, "Your payment of ₹300 to Ramesh was cancelled", "IGNORED")
    yes("notice cancelled", PaymentAlertParser.notice(null, "Your payment of ₹300 to Ramesh was cancelled")?.kind == "cancelled")
    yes("notice request", PaymentAlertParser.notice(null, "Ramesh has requested ₹2,000 from you. Approve on PhonePe")?.let { it.kind == "request" && it.amountPaise == 200000L } == true)
    yes("notice collect request", PaymentAlertParser.notice("AX-HDFCBK-S", "Collect request of Rs 500 from ramesh@ybl is pending for approval")?.kind == "request")
    yes("notice autopay set up", PaymentAlertParser.notice(null, "Your AutoPay mandate of Rs 499 for Netflix has been successfully created")?.kind == "autopay")
    yes("notice autopay stopped", PaymentAlertParser.notice(null, "Your AutoPay of Rs 499 for Netflix has been revoked")?.kind == "autopay_off")
    yes("autopay to run later stays a pending note", PaymentAlertParser.notice(null, "Autopay of Rs 199 for Netflix will be processed from A/c XX1234 on 5 Dec")?.kind == "pending")
    yes("refund started stays refund_started", PaymentAlertParser.notice(null, "Refund of ₹499 initiated. It will be credited in 5-7 days")?.kind == "refund_started")
    // What the phone SAYS: never the "received" words for a notice.
    yes("bill paid voice te", PaymentAlertParser.billPaidParts(413300, "te", "Bajaj Finance", true).joinToString(" ") == "Bajaj Finance లోన్ వాయిదా 4133 రూపాయలు కట్టారు.")
    yes("bill paid voice en", PaymentAlertParser.billPaidParts(96200, "en", null, false).joinToString(" ") == "Bill of 962 rupees paid.")
    yes("cashback voice te", PaymentAlertParser.bonusParts(5000, "te", "cashback").joinToString(" ") == "50 రూపాయలు క్యాష్‌బ్యాక్ ఖాతాలో పడింది.")
    for (k in listOf("refund_started", "pending", "failed", "cancelled", "bill", "autopay", "autopay_off", "request", "suspect")) {
        for (lang in listOf("te", "hi", "en", "ta")) {
            val said = PaymentAlertParser.noticeParts(k, 29900, lang).joinToString(" ")
            yes("notice voice $k $lang", said.isNotBlank() && !said.contains("జమ") && !said.contains("అందింది") &&
                !said.contains("received", ignoreCase = true))
        }
    }
    yes("fake warning without an amount", PaymentAlertParser.noticeParts("suspect", null, "te").first().startsWith("జాగ్రత్త"))
    yes("voice kind of a notice", PaymentAlertParser.voiceKindOf("refund_started") == "pending" &&
        PaymentAlertParser.voiceKindOf("cancelled") == "failed" && PaymentAlertParser.voiceKindOf("bill") == "due" &&
        PaymentAlertParser.voiceKindOf("suspect") == "fake" && PaymentAlertParser.voiceKindOf("autopay_off") == "autopay")
    // Owner 2026-11-22 (a JK-xxxxx-S "DEPOSIT SUCCESS ... Rs.8,551,00 ... A/c: <10 digits> ... bit.ly" SMS was said and
    // counted as ₹8,55,100 received). Made-up numbers only.
    val fake = "TRADESFORNSEBILLAMT\nDEPOSIT SUCCESS\nA/c: 9000012345\nTime: 18:20 PM\nAmount: Rs.8,551,00\nStatus: RECEIVED\nOpen: bit.ly/4kYG0he\n-EXAMPLESECURITIES"
    val fakeNoLink = fake.replace("\nOpen: bit.ly/4kYG0he", "")
    check("fake deposit SMS = never money", "JK-ABCDEF-S", fake, "IGNORED")
    check("fake deposit SMS without its link = never money", "JK-ABCDEF-S", fakeNoLink, "IGNORED")
    yes("fake deposit = a ⚠️ warning, no amount (the amount itself is broken)",
        PaymentAlertParser.notice("JK-ABCDEF-S", fakeNoLink)?.let { it.kind == "suspect" && it.amountPaise == null } == true)
    yes("fake signs", PaymentAlertParser.fakeSigns(fake) == listOf("link", "bad_amount", "open_account"))
    yes("an earlier confirmed wording does not make a fake one money",
        PaymentAlertParser.parse("JK-ABCDEF-S", fakeNoLink, learnedIn = listOf(PaymentAlertParser.template(fakeNoLink))) is Result.Ignored)
    yes("the person's own 'wrong -> came in' on that message still wins",
        PaymentAlertParser.parse("JK-ABCDEF-S", fakeNoLink, learnedKinds = mapOf(PaymentAlertParser.skeleton(fakeNoLink) to "in")) is Result.Accepted)
    check("whole account number + received = never money", "JK-ABCDEF-S", "Rs.5,000.00 received in A/c No. 9000012345 Status: SUCCESS", "IGNORED")
    check("tinyurl credit = never money", null, "Rs 2,000 credited to your account. Open tinyurl.com/abcd to claim", "IGNORED")
    for (g in listOf("8,55,100", "855,100", "8551", "8551.00", "1,00,000.50", "12,34,567", "500,")) yes("amount $g is well grouped", PaymentAlertParser.wellGrouped(g))
    for (g in listOf("8,551,00", "85,5100", "1,0000")) yes("amount $g is broken", !PaymentAlertParser.wellGrouped(g))
    check("real credit 8,551.00 stays money", "AX-HDFCBK-S", "Rs.8,551.00 credited to your A/c XX1234 on 22-11-26 by UPI", "IN 855100")
    check("real NEFT from a broker stays money", "AX-SBIINB-S", "Rs 1,00,000.00 credited to A/c XXXXXX1234 by NEFT from EXAMPLE SECURITIES LTD", "IN 10000000")
    check("bank's own link line is cut, credit stays", "AX-HDFCBK-S", "Rs.500.00 credited to A/c XX1234 on 22-11-26. Not you? Visit https://hdfcbk.io/a/x", "IN 50000")
    check("EMI debit with a whole loan number stays a debit", "AX-HDFCBK-S", "Rs 4,133.00 debited from A/c XX1234 towards loan account 123456789012 EMI on 22-11-26", "OUT 413300")
    // ---------------------------------------------------------------- ONE payment = ONE voice (owner's real reports)
    // Owner 2026-11-22: notification first (name on it), the bank SMS an HOUR later -> the SMS was spoken again.
    Sim().run {
        get(PHONEPE, "upi", null, "MOHAMMAD HAFIZ (9502072317@ibl) sent you ₹300", 0)
        val late = get(SMS, "sms", "JD-HDFCBK-S", "Rs.300.00 credited to HDFC Bank A/c XX6911 on 22-11-26 from VPA 9502072317@ibl (UPI 532612345678)", 60)
        yes("notification, then bank SMS 1 h later = spoken once", late == "joined" && spoken == 1 && rows.size == 1)
        yes("the first voice has the payer's name", rows[0].payer == "MOHAMMAD HAFIZ")
    }
    // Owner 2026-11-22: bank SMS first, the app's notification later -> the notification was spoken again.
    Sim().run {
        get(SMS, "sms", "JD-HDFCBK-S", "Rs.300.00 credited to HDFC Bank A/c XX6911 on 22-11-26 from VPA *2317@ibl (UPI 532612345678)", 0)
        val late = get(PHONEPE, "upi", null, "MOHAMMAD HAFIZ (9502072317@ibl) sent you ₹300", 75)
        yes("bank SMS, then notification 75 min later = spoken once", late == "joined" && spoken == 1)
    }
    // Same, with nothing in common but the amount (SBI SMS has no payer): still one voice within 2 h.
    Sim().run {
        get(PHONEPE, "upi", "Received ₹300", "Bhagya sent ₹300 to you.", 0)
        val late = get(SMS, "sms", "JD-SBIUPI-S", "Dear SBI UPI User, ur A/cX1234 credited by Rs300 on 22Nov26 by (Ref no 532612345678)", 70)
        yes("no clue, SMS 70 min later = spoken once", late == "joined" && spoken == 1)
    }
    // The bank's own app notification very late after an SMS + PhonePe pair: joined by the payer's name.
    Sim().run {
        get(SMS, "sms", "JD-HDFCBK-S", "Rs.300.00 credited to HDFC Bank A/c XX6911 on 22-11-26 (UPI 532612345678)", 0)
        get(PHONEPE, "upi", null, "MOHAMMAD HAFIZ (9502072317@ibl) sent you ₹300", 1)
        val late = get(HDFC_APP, "bank", null, "You have received Rs.300.00 from MOHAMMAD HAFIZ", 150)
        yes("late bank app 2.5 h later, same payer = silent", late == "joined" && spoken == 1)
    }
    // QR safety: ANOTHER customer's ₹300 (QR = SMS only) 30 min after a PhonePe ₹300 must still be spoken.
    Sim().run {
        get(PHONEPE, "upi", null, "MOHAMMAD HAFIZ (9502072317@ibl) sent you ₹300", 0)
        val qr = get(SMS, "sms", "JD-HDFCBK-S", "Rs.300.00 credited to HDFC Bank A/c XX6911 on 22-11-26 from VPA *akar@ibl (UPI 532612349999)", 30)
        val own = get(SMS, "sms", "JD-HDFCBK-S", "Rs.300.00 credited to HDFC Bank A/c XX6911 on 22-11-26 from VPA 9502072317@ibl (UPI 532612345678)", 50)
        yes("another payer's QR ₹300 = spoken", qr == "spoken")
        yes("the first payer's late SMS joins HIS row", own == "joined" && spoken == 2 && rows[0].kinds.contains("sms"))
    }
    // Two different RRNs are two payments, whatever the time.
    Sim().run {
        get(SMS, "sms", "JD-HDFCBK-S", "Rs.300.00 credited to HDFC Bank A/c XX6911 (UPI 532612345678)", 0)
        val second = get(HDFC_APP, "bank", null, "Rs.300.00 credited to A/c XX6911 UPI Ref 532612340000", 5)
        yes("different RRN = second payment spoken", second == "spoken" && spoken == 2)
    }
    // Rs 1 + Rs 1 from the same app a minute apart = two payments (owner 2026-11-15).
    Sim().run {
        get(PHONEPE, "upi", null, "Bhagya sent ₹1 to you.", 0)
        val second = get(PHONEPE, "upi", null, "Bhagya sent ₹1 to you.", 1)
        yes("same app, same amount twice = two voices", second == "spoken" && spoken == 2)
    }
    // Two SMS-only ₹500 payments, then a notification: it joins the CLOSEST one, the count stays right.
    Sim().run {
        get(SMS, "sms", "JD-SBIUPI-S", "Dear SBI UPI User, ur A/cX1234 credited by Rs500 on 22Nov26 by (Ref no 532612340001)", 0)
        get(SMS, "sms", "JD-SBIUPI-S", "Dear SBI UPI User, ur A/cX1234 credited by Rs500 on 22Nov26 by (Ref no 532612340002)", 85)
        val note = get(PHONEPE, "upi", "Received ₹500", "Bhagya sent ₹500 to you.", 86)
        yes("notification joins the closest SMS", note == "joined" && spoken == 2 && rows[1].kinds.contains("upi") && !rows[0].kinds.contains("upi"))
    }
    // A different account tail is a different payment.
    Sim().run {
        get(SMS, "sms", "JD-HDFCBK-S", "Rs.300.00 credited to HDFC Bank A/c XX6911 on 22-11-26", 0)
        val other = get(HDFC_APP, "bank", null, "Rs.300.00 credited to A/c XX7571", 3)
        yes("another account = spoken", other == "spoken")
    }
    // Owner 2026-11-23 (PhonePe "2 new completed transaction updates": last night's ₹3,000 that CAME IN and
    // yesterday's ₹3,360 that went to someone were read as ONE message -- "₹3,000 went to <that someone>", spoken
    // 9 h after the money had come in): a payment app's SUMMARY of several transactions is several messages, each
    // read alone; it tells EARLIER payments, so it never speaks as new money. (Names and numbers are made up.)
    val sumTitle = "2 new completed transaction updates"
    val sumText = "· KOTA SRINIVAS RAO has sent ₹3,000 to your bank account HDFC Bank-4321\n· ₹3,360 has been sent to mahesh"
    check("summary read whole is never one payment", sumTitle, sumText, "IGNORED")
    val sumLines = PaymentAlertParser.digestLines(sumTitle, sumText)
    yes("summary = its two lines", sumLines.size == 2)
    check("summary line 1 = money in", null, sumLines.getOrElse(0) { "" }, "IN 300000 payer=KOTA SRINIVAS RAO acct=4321")
    check("summary line 2 = money out", null, sumLines.getOrElse(1) { "" }, "OUT 336000 to=mahesh")
    yes("heading inside the text", PaymentAlertParser.digestLines(null, "3 new payments\nRamesh sent ₹10 to you\nPaid ₹20 to Ravi\nSuresh sent ₹30 to you").size == 3)
    yes("bullet points without a heading", PaymentAlertParser.digestLines("PhonePe", "• Ramesh sent ₹10 to you • Paid ₹20 to Ravi").size == 2)
    yes("one transaction is not a summary", PaymentAlertParser.digestLines("1 new transaction update", "· Ramesh has sent ₹10 to your bank account").isEmpty())
    yes("bank SMS + balance line is not a summary", PaymentAlertParser.digestLines("JD-HDFCBK-S", "Rs.500.00 credited to HDFC Bank A/c XX1234\nAvl Bal Rs.5,230.00").isEmpty())
    yes("multi-line debit SMS is not a summary", PaymentAlertParser.digestLines("JD-HDFCBK-S", "Sent Rs.100.00\nFrom HDFC Bank A/C *1234\nTo RAMESH\nOn 15/11/26").isEmpty())
    yes("amount + balance in one sentence is not a summary", PaymentAlertParser.digestLines(null, "Rs 500 credited to A/c XX1234. Avl Bal Rs 5,230").isEmpty())
    yes("two lines, no heading, no bullets = one message", PaymentAlertParser.digestLines("Payment update", "Paid ₹500 to Ramesh\nCashback ₹10 earned").isEmpty())
    check("multi-line debit SMS still read as before", "JD-HDFCBK-S", "Sent Rs.100.00\nFrom HDFC Bank A/C *1234\nTo RAMESH\nOn 15/11/26", "OUT 10000 to=RAMESH acct=1234")
    yes("account after 'Bank-'", PaymentAlertParser.accountTail("to your bank account HDFC Bank-4321") == "4321")
    yes("a phone number after 'Bank -' is not an account", PaymentAlertParser.accountTail("Call HDFC Bank - 1800 258 6161") == null)
    yes("names clash only when no word is shared", PaymentAlertParser.namesClash("RAMESH", "SURESH KUMAR") &&
        !PaymentAlertParser.namesClash("mahesh", "MAHESH BABU") && !PaymentAlertParser.namesClash(null, "RAMESH"))
    // The notification's pieces: the same summary in two layouts is read ONCE; lines in separate pieces need a heading.
    yes("same summary in text + big text = its two lines, not four", PaymentAlertParser.digestLinesOf(sumTitle,
        listOf(sumText.replace("\n", " "), sumText, sumLines.last())).size == 2)
    yes("lines in separate pieces under a counting heading", PaymentAlertParser.digestLinesOf(sumTitle,
        listOf("KOTA SRINIVAS RAO has sent ₹3,000 to your bank account HDFC Bank-4321", "₹3,360 has been sent to mahesh",
            "₹3,360 has been sent to mahesh")).size == 2)
    yes("text + longer big text of ONE payment is not a summary", PaymentAlertParser.digestLinesOf("Money received",
        listOf("Ramesh sent ₹500 to you", "Ramesh sent ₹500 to you. Tap to see details")).isEmpty())
    yes("one payment told two ways, no counting heading = not a summary", PaymentAlertParser.digestLinesOf("PhonePe",
        listOf("You received ₹500", "Ramesh sent ₹500 to your bank account")).isEmpty())
    // The reported morning: debit SMS yesterday, credit SMS last night, the app's summary 9.5 h later.
    Sim().run {
        any(SMS, "sms", "JD-HDFCBK-S", "Sent Rs.3360.00 From HDFC Bank A/C *4321 To MAHESH BABU On 22/11/26 Ref 532612340777", 0)
        get(SMS, "sms", "JD-HDFCBK-S", "Rs.3000.00 credited to HDFC Bank A/c XX4321 on 22-11-26 (UPI 532612345111)", 300)
        val said = spoken
        val r = summary(PHONEPE, "upi", sumTitle, sumText, 873)
        yes("summary 9.5 h later: both lines join their rows", r == listOf("joined", "joined"))
        yes("summary: nothing spoken, no new row", spoken == said && rows.size == 2)
        yes("summary: the payer's name fills the bank SMS row", rows[1].payer == "KOTA SRINIVAS RAO" && rows[1].direction == "in")
        val again = summary(PHONEPE, "upi", "3 new completed transaction updates", sumText + "\n· ₹500 has been sent to Ravi", 900)
        yes("the summary again with one more line: old lines stay silent, the new one is written late",
            again == listOf("joined", "joined", "late") && spoken == said && rows.size == 3)
    }
    // The app told the payment at the time; its own summary later repeats it (same app = still the same money).
    Sim().run {
        get(PHONEPE, "upi", "Received ₹3,000", "KOTA SRINIVAS RAO has sent ₹3,000 to your bank account HDFC Bank-4321", 0)
        val r = summary(PHONEPE, "upi", sumTitle, sumText, 500)
        yes("summary repeats the app's own earlier message = silent", r.getOrNull(0) == "joined")
        yes("a line nobody told before = written late, never said as new money", r.getOrNull(1) == "late" && spoken == 1 && rows.size == 2)
    }
    // Rs 1 + Rs 1 (owner 2026-11-15) inside a summary: one row each; a second equal line with no row = a missed payment.
    Sim().run {
        get(PHONEPE, "upi", null, "Bhagya sent ₹1 to you.", 0)
        get(PHONEPE, "upi", null, "Bhagya sent ₹1 to you.", 1)
        val r = summary(PHONEPE, "upi", sumTitle, "· Bhagya has sent ₹1 to your bank account HDFC Bank-4321\n· Bhagya has sent ₹1 to your bank account HDFC Bank-4321", 300)
        yes("two equal lines take the two rows, one each", r == listOf("joined", "joined") && rows.size == 2 && spoken == 2)
    }
    Sim().run {
        get(PHONEPE, "upi", null, "Bhagya sent ₹1 to you.", 0)
        val r = summary(PHONEPE, "upi", sumTitle, "· Bhagya has sent ₹1 to your bank account HDFC Bank-4321\n· Bhagya has sent ₹1 to your bank account HDFC Bank-4321", 300)
        yes("two equal lines, one row: the second is a payment the phone missed", r == listOf("joined", "late") && rows.size == 2 && spoken == 1)
    }
    // Another person's payment of the same amount is not swallowed by a summary line; an old row is out of reach.
    Sim().run {
        get(SMS, "sms", "JD-HDFCBK-S", "Rs.500.00 credited to HDFC Bank A/c XX4321 on 22-11-26 from VPA ramesh@ybl (UPI 532612345222)", 0)
        val r = summary(PHONEPE, "upi", sumTitle, "· SURESH KUMAR has sent ₹500 to your bank account HDFC Bank-4321\n· ₹20 has been sent to Ravi", 600)
        yes("a different person's same amount = his own (late) row", r.getOrNull(0) == "late" && rows.size == 3)
    }
    Sim().run {
        get(SMS, "sms", "JD-HDFCBK-S", "Rs.3000.00 credited to HDFC Bank A/c XX4321 on 20-11-26 (UPI 532612345333)", 0)
        val r = summary(PHONEPE, "upi", sumTitle, sumText, 49 * 60)
        yes("a row older than two days is not the summary's payment", r.getOrNull(0) == "late")
    }
    // An ordinary (not summary) message hours later is still a new payment, as before.
    Sim().run {
        get(SMS, "sms", "JD-HDFCBK-S", "Rs.3000.00 credited to HDFC Bank A/c XX4321 on 22-11-26 (UPI 532612345111)", 0)
        val later = get(PHONEPE, "upi", null, "Ramesh sent ₹3,000 to you.", 573)
        yes("a real message 9.5 h later is still a new payment", later == "spoken" && spoken == 2)
    }
    // Owner 2026-11-23 (Jio recharge Rs 448 paid from ICICI: the bank SMS "debited for Rs 448.00 ...; Jio Prepaid Recharge
    // credited" gave no voice and no row). The payee's NAME ("... Recharge credited", "to jiorecharge@paytm", "OFFER
    // MART") never decides; the bank's debit wording does. Every bank shape, made-up numbers only.
    check("icici debit for a recharge", "AD-ICICIT-S", "ICICI Bank Acct XX123 debited for Rs 448.00 on 23-Nov-26; Jio Prepaid Recharge credited. UPI:532012345678. Call 18002662 for dispute. SMS BLOCK 123 to 9215676766.", "OUT 44800 to=Jio Prepaid Recharge acct=123")
    check("icici debit for an emi", "AD-ICICIT-S", "ICICI Bank Acct XX123 debited for Rs 1,941.00 on 23-Nov-26; HDFC LOAN EMI credited. UPI:532012345678.", "OUT 194100 to=HDFC LOAN EMI acct=123")
    check("icici debit for a bill pay", "AD-ICICIT-S", "ICICI Bank Acct XX123 debited for Rs 962.00 on 23-Nov-26; APSPDCL BILL PAY credited. UPI:532012345678.", "OUT 96200 to=APSPDCL BILL PAY acct=123")
    check("icici debit to a shop named offer", "AD-ICICIT-S", "ICICI Bank Acct XX123 debited for Rs 500.00 on 23-Nov-26; OFFER MART credited. UPI:532012345678.", "OUT 50000 to=OFFER MART acct=123")
    check("hdfc sent to a recharge", "AD-HDFCBK-S", "Sent Rs.448.00 From HDFC Bank A/C *1234 To JIO PREPAID RECHARGE On 23/11/26 Ref 532012345678 Not You? Call 18002586161", "OUT 44800 to=JIO PREPAID RECHARGE acct=1234")
    check("kotak sent to a recharge id", "AD-KOTAKB-S", "Sent Rs.448.00 from Kotak Bank AC X1234 to jiorecharge@paytm on 23-11-26.UPI Ref 532012345678. Not you, https://kotak.com/KBANKT/Fraud", "OUT 44800 to=jiorecharge acct=1234")
    check("bob dr / cr debit", "AD-BOBTXN-S", "Rs.100.00 Dr. from A/C XXXXXX1234 and Cr. to ramesh@ybl. Ref:532012345678. AvlBal:Rs5000.00(2026:11:15 10:20:30). Not you? Call 18005700 -BOB", "OUT 10000 to=ramesh acct=1234")
    check("bob dr / cr debit for a recharge", "AD-BOBTXN-S", "Rs.448.00 Dr. from A/C XXXXXX1234 and Cr. to jiorecharge@paytm. Ref:532012345678. AvlBal:Rs5000.00(2026:11:23 10:20:30). Not you? Call 18005700 -BOB", "OUT 44800 to=jiorecharge acct=1234")
    check("sbi debit for a recharge", "AD-SBIUPI-S", "Dear UPI user A/C X1234 debited by 448.0 on date 23Nov26 trf to Jio Prepaid Recharge Refno 532012345678. If not u? call 1800111109. -SBI", "OUT 44800 to=Jio Prepaid Recharge acct=1234")
    // The operator's own "Recharge Successful" goes to the number that was recharged -- it may be somebody else's money.
    check("jio recharge successful, no rupee sign", "JG-JioPay-S", "Recharge Successful !\nPlan Name : 448.00\nJio Number : 9000000001\nTransaction ID : BR000TEST1\nView plan details - http://tiny.jio.com/dmyjioplans", "IGNORED")
    check("jio recharge successful, telugu", "JM-JioPay-S", "రీఛార్జ్ విజయవంతమైంది!\nప్లాన్ పేరు : 448.00\nJio నంబర్ : 9000000001\nలావాదేవీ ID : BR000TEST1", "IGNORED")
    // Still NOT money that went out.
    check("icici failed for a recharge", "AD-ICICIT-S", "ICICI Bank: Transaction of Rs 448.00 to Jio Prepaid Recharge failed on 23-Nov-26. Amount will be reversed.", "IGNORED")
    check("collect request from a recharge id", null, "Collect request of Rs 448 from jiorecharge@paytm. Approve in your UPI app.", "IGNORED")
    check("recharge autopay will be debited", "AD-ICICIT-S", "Rs 448 will be debited from your a/c XX1234 for Jio recharge autopay on 25-Nov-26", "IGNORED")
    check("loan in, fee out stays ignored", "AD-ICICIT-S", "Loan of Rs 50,000 credited to your a/c XX1234. Processing fee Rs 590 debited.", "IGNORED")
    // The three messages of one recharge = ONE row, ONE voice, in any order.
    val icici448 = "ICICI Bank Acct XX123 debited for Rs 448.00 on 23-Nov-26; Jio Prepaid Recharge credited. UPI:532012345678. Call 18002662 for dispute."
    val jioEn = "Recharge Successful !\nPlan Name : 448.00\nJio Number : 9000000001\nTransaction ID : BR000TEST1"
    val jioTe = "రీఛార్జ్ విజయవంతమైంది!\nప్లాన్ పేరు : 448.00\nJio నంబర్ : 9000000001\nలావాదేవీ ID : BR000TEST1"
    Sim().run {
        val a = any(SMS, "sms", "JM-JioPay-S", jioTe, 0)
        val b = any(SMS, "sms", "JG-JioPay-S", jioEn, 0)
        val c = any(SMS, "sms", "AD-ICICIT-S", icici448, 0)
        yes("jio recharge: one row, one voice, from the bank's SMS", a == "ignored" && b == "ignored" && c == "spoken" &&
            rows.size == 1 && spoken == 1 && rows[0].direction == "out")
        val d = any(PHONEPE, "upi", null, "Paid ₹448 to Jio Prepaid", 2)
        yes("the UPI app's own 'paid' message joins it silently", d == "joined" && rows.size == 1 && spoken == 1)
    }
    // What the phone SAYS (owner 2026-11-23): an unsure message asks to check, a late one says so, a wrong voice says sorry.
    yes("unsure voice asks to check the bank balance", PaymentAlertParser.noticeParts("unsure", 300000, "te").joinToString(" ").let {
        it.contains("3000 రూపాయలు") && it.contains("బ్యాంక్ బ్యాలెన్స్") && !it.contains("వెళ్ళాయి") })
    yes("late voice says it is an earlier payment", PaymentAlertParser.noticeParts("late_out", 336000, "te", "mahesh").joinToString(" ").let {
        it.startsWith("ఆలస్యంగా తెలిసింది") && it.contains("mahesh కి 3360 రూపాయలు") })
    yes("late voice, money in, English", PaymentAlertParser.noticeParts("late_in", 300000, "en", "Ramesh").joinToString(" ") ==
        "Found out late: 3000 rupees came in earlier from Ramesh.")
    yes("sorry voice", PaymentAlertParser.noticeParts("sorry_out", 300000, "te").joinToString(" ").let { it.startsWith("సారీ") && it.contains("వెళ్ళలేదు") })
    yes("voice switches of the new lines", PaymentAlertParser.voiceKindOf("late_in") == "in" &&
        PaymentAlertParser.voiceKindOf("late_out") == "out" && PaymentAlertParser.voiceKindOf("unsure") == "check" &&
        PaymentAlertParser.voiceKindOf("sorry_in") == "sorry")
    voicePackChecks()
    oneVoiceChecks()
    println(if (fails == 0) "ALL PASS" else "$fails FAILED")
    if (fails > 0) kotlin.system.exitProcess(1)
}

/**
 * Owner 2026-11-23 (ASKODOX Lite step 1): any amount is said with NO internet in the same ElevenLabs voice, from a
 * pack of clips fetched once; ASKODOX lines (hello, customer line, night count) follow fixed rules.
 */
fun voicePackChecks() {
    fun ok(name: String, cond: Boolean) {
        if (!cond) fails++
        println((if (cond) "ok   " else "FAIL ") + name)
    }
    val P = PaymentVoicePack
    ok("te 1234", P.numberWords(1234, "te") == listOf("వెయ్యి", "రెండు వందల", "ముప్పై నాలుగు"))
    ok("te 500", P.numberWords(500, "te") == listOf("ఐదు వందల"))
    ok("te 100 / 150", P.numberWords(100, "te") == listOf("వంద") && P.numberWords(150, "te") == listOf("నూట", "యాభై"))
    ok("te 2000", P.numberWords(2000, "te") == listOf("రెండు", "వేల"))
    ok("te 1,25,000", P.numberWords(125_000, "te") == listOf("ఒక లక్ష", "ఇరవై ఐదు", "వేల"))
    ok("te 1 rupee", P.numberWords(1, "te") == listOf("ఒక్క"))
    ok("te 1 crore", P.numberWords(10_000_000, "te") == listOf("ఒక కోటి"))
    ok("hi 1234", P.numberWords(1234, "hi") == listOf("एक", "हज़ार", "दो", "सौ", "चौंतीस"))
    ok("en 25,30,045", P.numberWords(2_530_045, "en") == listOf("twenty five", "lakh", "thirty", "thousand", "forty five"))
    ok("hi 1..99 all different", (1..99).map { P.below100(it, "hi") }.toSet().size == 99)
    ok("te 1..99 all different", (1..99).map { P.below100(it, "te") }.toSet().size == 99)
    ok("a language without number words is not guessed", P.numberWords(5, "ta") == null && P.clipsFor("5 ரூபாய்", "ta") == null)
    ok("no 0 / no number past 99 crore", P.numberWords(0, "te") == null && P.numberWords(1_000_000_000L, "te") == null)
    ok("segments", P.segments("1,250 రూపాయలు 50 పైసలు జమ అయ్యాయి.") == listOf(
        PaymentVoicePack.Seg(1250, "1,250"), PaymentVoicePack.Seg(null, "రూపాయలు"), PaymentVoicePack.Seg(50, "50"),
        PaymentVoicePack.Seg(null, "పైసలు జమ అయ్యాయి.")))
    ok("clips of a credit line", P.clipsFor("1250 రూపాయలు జమ అయ్యాయి.", "te") ==
        listOf("వెయ్యి", "రెండు వందల", "యాభై", "రూపాయలు జమ అయ్యాయి."))
    ok("words with no number stay one clip", P.clipsFor("మాకు అందాయి.", "te") == listOf("మాకు అందాయి."))

    // EVERY clip of every sentence the phone says (no names) is in the pack -- any amount, rupees and paise.
    val amounts = listOf(1L, 7L, 99L, 100L, 101L, 999L, 1000L, 1001L, 12_345L, 99_999L, 100_000L, 250_075L, 9_999_999L, 10_000_000L)
    for (lang in listOf("te", "hi", "en")) {
        val shop = "Lakshmi Kirana"
        val pack = P.packTexts(lang, shop).toSet()
        val missing = LinkedHashSet<String>()
        for (rupees in amounts) for (paise in listOf(0L, 5L, 50L)) {
            val a = rupees * 100 + paise
            if (a > 1_000_000_000L) continue
            val sentences = ArrayList<List<String>>()
            for (credit in listOf(true, false)) sentences += PaymentAlertParser.personalParts(a, lang, credit, null)
            sentences += PaymentAlertParser.announcementParts(a, lang, false, null, shop)
            sentences += PaymentAlertParser.announcementParts(a, lang, false, null, null)
            sentences += PaymentAlertParser.billPaidParts(a, lang, null, true)
            sentences += PaymentAlertParser.bonusParts(a, lang, "cashback")
            for (k in listOf("refund_started", "failed", "unsure", "late_in", "sorry_in", "request"))
                sentences += PaymentAlertParser.noticeParts(k, a, lang, null)
            sentences += P.nightParts(3, a, lang)
            for (s in sentences) for (part in s) {
                val clips = P.clipsFor(part, lang)
                if (clips == null) missing += "<no clips> $part" else clips.filter { it !in pack }.forEach { missing += it }
            }
        }
        ok("$lang: every clip is in the pack" + (if (missing.isEmpty()) "" else " -- missing $missing"), missing.isEmpty())
        ok("$lang: pack is small (${pack.size} clips)", pack.size in 60..400)
    }
    ok("the shop's own words are in its pack", "Lakshmi Kirana కి అందాయి." in P.packTexts("te", "Lakshmi Kirana"))

    // ASKODOX lines: ASKODOX is the VOICE, never where the money went.
    for (lang in listOf("te", "hi", "en", "ta", "kn", "ml", "bn", "mr", "gu", "pa", "or", "ur")) {
        val all = (listOf(P.helloPart(lang), P.customerPart(lang)) + P.nightParts(2, 120_000, lang)).joinToString(" ")
        ok("$lang: ASKODOX lines exist", lang == "en" || P.helloPart(lang) != P.helloPart("en"))
        ok("$lang: lines never say money came INTO ASKODOX", !all.contains("ASKODOX లో") && !all.lowercase().contains("in askodox"))
    }
    ok("night, one payment (te)", P.nightParts(1, 50_000, "te") ==
        listOf("ఆస్కోడాక్స్ లెక్క:", "ఈరోజు ఒక్క పేమెంట్ వచ్చింది,", "మొత్తం 500 రూపాయలు.", "రేపు కలుద్దాం!"))
    ok("night, 45 payments (en)", P.nightParts(45, 1_240_000, "en")[1] == "45 payments came today,")

    // Owner 2026-11-23: no payment that day = no night count at all (no voice, no notification).
    val rows = listOf(PaymentVoicePack.DayRow(20_000, 50_000, true), PaymentVoicePack.DayRow(20_000, 30_000, true),
        PaymentVoicePack.DayRow(19_999, 99_900, true), PaymentVoicePack.DayRow(20_000, 70_000, false))
    ok("night count = today's counted payments only", P.dayTotals(rows, 20_000) == (2 to 80_000L))
    ok("a day with no payment = nothing", P.dayTotals(rows, 20_001) == (0 to 0L) && P.dayTotals(emptyList(), 5) == (0 to 0L))

    // Hello before the FIRST payment of the day; customer line from the 3rd payment, max 2 a day, 2 h apart.
    val h = 60 * 60_000L
    var st = PaymentVoicePack.BrandState()
    val day = 20_000L
    val t0 = day * 86_400_000L
    val seen = ArrayList<String>()
    for ((i, at) in listOf(0L, 10 * 60_000L, 20 * 60_000L, 30 * 60_000L, 3 * h, 4 * h, 9 * h).withIndex()) {
        val c = P.brandChoice(day, t0 + at, st, helloOn = true, customerOn = true)
        seen += "${i + 1}:" + (if (c.hello) "H" else "") + (if (c.customer) "C" else "")
        st = c.next
    }
    ok("hello once, customer on the 3rd and again 2 h later, never a 3rd time -- $seen",
        seen == listOf("1:H", "2:", "3:C", "4:", "5:C", "6:", "7:"))
    val next = P.brandChoice(day + 1, t0 + 25 * h, st, helloOn = true, customerOn = true)
    ok("a new day starts with hello again", next.hello && !next.customer && next.next.payCount == 1)
    var off = PaymentVoicePack.BrandState()
    val offSeen = ArrayList<Boolean>()
    for (i in 0 until 3) { val c = P.brandChoice(day, t0 + i * h, off, helloOn = false, customerOn = true); offSeen += c.hello; off = c.next }
    ok("hello switched off is never said", offSeen.none { it })
    val noLine = P.brandChoice(day, t0, PaymentVoicePack.BrandState(day, 5, day, -1, 0, 0), helloOn = true, customerOn = false)
    ok("customer line switched off is never said", !noLine.customer)

    // The night count at 21:00 local time (India +5:30).
    val ist = 19_800_000L
    val todayStart = day * 86_400_000L - ist
    ok("before 9 pm -> today 9 pm", P.nextNightAt(todayStart + 20 * h, ist, 21 * 60) == todayStart + 21 * h)
    ok("after 9 pm -> tomorrow 9 pm", P.nextNightAt(todayStart + 22 * h, ist, 21 * 60) == todayStart + 45 * h)
    ok("time setting", P.minuteOf("21:30") == 1290 && P.minuteOf("bad") == 1260 && P.minuteOf(null) == 1260)

    // Owner 2026-11-23: each ACCOUNT is ON for "mine" / "shop" / "off"; the account decides, not the app.
    val sides = mapOf("1234" to "shop", "5678" to "mine", "999" to "off")
    val apps = mapOf(PHONEPE to "mine")
    ok("bank SMS into the shop's account -> shop, even from the SMS app on the My phone list",
        PaymentAlertParser.accountSide("1234", SMS, sides, apps) == "shop")
    ok("same app, the person's own account -> mine", PaymentAlertParser.accountSide("5678", SMS, sides, apps) == "mine")
    ok("an account switched OFF -> off", PaymentAlertParser.accountSide("4999", SMS, sides, apps) == "off")
    ok("XX1234 written as 234 is the same account", PaymentAlertParser.accountSide("234", SMS, sides, emptyMap()) == "shop")
    ok("no account digits -> the app linked to an account", PaymentAlertParser.accountSide(null, PHONEPE, sides, apps) == "mine")
    ok("nothing chosen -> null (the app decides, as before)", PaymentAlertParser.accountSide("4321", SMS, sides, emptyMap()) == null)
    ok("an unknown word is never a side", PaymentAlertParser.accountSide("1111", SMS, mapOf("1111" to "x"), emptyMap()) == null)
    val shopAcct = PaymentAlertParser.parse(null,
        "Money Received - INR 100.00 in your HDFC Bank A/c xx1234 on 23-11-26 by A/c linked to VPA mrs.manasa@okaxis (UPI Ref No. 532012345678).")
    ok("a real bank SMS shape carries the account the side is read from",
        shopAcct is Result.Accepted && PaymentAlertParser.accountSide(shopAcct.account, SMS, sides, apps) == "shop")
}


/**
 * Owner 2026-11-24 ("one payment twice; the voice stops before the last word and then says it all again; at 9 pm the
 * count came 4-5 times"). Names and numbers are made up; the shapes and the gaps are the real ones.
 */
fun oneVoiceChecks() {
    fun ok(name: String, cond: Boolean) { if (!cond) fails++; println((if (cond) "ok   " else "FAIL ") + name) }
    // 1. TWO UPI apps tell the SAME credit (PhonePe and Paytm both notify money landing in the linked bank account).
    Sim().run {
        get(PHONEPE, "upi", "Received ₹500", "RAMESH KUMAR sent ₹500 to your bank account HDFC Bank-4321", 0)
        val b = get(PAYTM, "upi", null, "Received ₹500 in your HDFC Bank a/c from Ramesh Kumar", 1)
        ok("owner 2026-11-24: PhonePe + Paytm for one credit = one voice", b == "joined" && spoken == 1)
    }
    // Owner 2026-11-24 ("two people can pay the same amount at the same moment"): the same amount from two apps a
    // minute apart with NOTHING that proves it is one payment = two payments, two voices.
    Sim().run {
        get(PHONEPE, "upi", null, "Bhagya sent ₹500 to you.", 0)
        val b = get(PAYTM, "upi", null, "Received ₹500 from Suresh on Paytm", 1)
        ok("owner 2026-11-24: two apps, two different people, 1 min apart = two voices", b == "spoken" && spoken == 2)
    }
    Sim().run {
        get(PHONEPE, "upi", "Received ₹500", "You received ₹500 in your bank account", 0)
        val b = get(PAYTM, "upi", null, "Received ₹500 in your bank account", 1)
        ok("owner 2026-11-24: same amount, two apps, no id / name / same text = two voices", b == "spoken" && spoken == 2)
    }
    Sim().run {
        get(SMS, "sms", "AX-CANBNK-S", "An amount of INR 500.00 has been CREDITED to your account XXX1234 on 24/11/2026 towards UPI. Total Avail.bal INR 5,000.00 - Canara Bank", 0)
        val b = get(TRUECALLER, "sms", "AX-CANBNK-S", "An amount of INR 500.00 has been CREDITED to your account XXX1234 on 24/11/2026 towards UPI. Total Avail.bal INR 5,500.00 - Canara Bank", 1)
        ok("two SMS apps, different balance in the text = two payments", b == "spoken" && spoken == 2)
    }
    // ... but two DIFFERENT customers through two apps, 40 min apart, nothing in common = two payments.
    Sim().run {
        get(PHONEPE, "upi", null, "Bhagya sent ₹500 to you.", 0)
        val b = get(PAYTM, "upi", null, "Received ₹500 from Suresh on Paytm", 40)
        ok("two apps, two people, 40 min apart = two voices", b == "spoken" && spoken == 2)
    }
    // 2. ONE bank SMS shown by TWO SMS apps (Messages + Truecaller), no reference on it.
    Sim().run {
        get(SMS, "sms", "AX-CANBNK-S", "An amount of INR 500.00 has been CREDITED to your account XXX1234 on 24/11/2026 towards UPI. Total Avail.bal INR 5,000.00 - Canara Bank", 0)
        val b = get(TRUECALLER, "sms", "AX-CANBNK-S", "An amount of INR 500.00 has been CREDITED to your account XXX1234 on 24/11/2026 towards UPI. Total Avail.bal INR 5,000.00 - Canara Bank", 0)
        ok("owner 2026-11-24: one SMS in two SMS apps = one voice", b == "joined" && spoken == 1)
    }
    // ... while two real SMS-only payments in ONE SMS app stay two (owner 2026-11-15).
    Sim().run {
        get(SMS, "sms", "AX-CANBNK-S", "An amount of INR 500.00 has been CREDITED to your account XXX1234 on 24/11/2026 towards UPI. - Canara Bank", 0)
        val b = get(SMS, "sms", "AX-CANBNK-S", "An amount of INR 500.00 has been CREDITED to your account XXX1234 on 24/11/2026 towards UPI. - Canara Bank", 3)
        ok("two SMS in one SMS app = two payments", b == "spoken" && spoken == 2)
    }
    // 3. The SAME reference twice from the same app (a re-sent / second SMS of one payment) = the same money.
    Sim().run {
        get(SMS, "sms", "JD-HDFCBK-S", "Rs.500.00 credited to HDFC Bank A/c XX6911 on 24-11-26 (UPI 532612345678)", 0)
        val b = get(SMS, "sms", "JD-HDFCBK-S", "Money Received - INR 500.00 in your HDFC Bank A/c xx6911 on 24-11-26 by A/c linked to VPA ramesh.k@okaxis (UPI Ref No. 532612345678).", 55)
        ok("owner 2026-11-24: same RRN again from the same app, 55 min later = silent", b == "joined" && spoken == 1)
    }
    Sim().run {
        get(PHONEPE, "upi", null, "Ramesh sent ₹500 to you. UPI Ref 532612345678", 0)
        val b = get(PHONEPE, "upi", null, "Payment of ₹500 received from Ramesh. Ref No 532612345678", 60)
        ok("same app shows the same RRN an hour later = silent", b == "joined" && spoken == 1)
    }
    // 4. The payer's UPI id written with another bank handle on the SMS (9876543210@ybl in the app, @axl on the SMS).
    Sim().run {
        get(PHONEPE, "upi", null, "RAMESH KUMAR (9876543210@ybl) sent you ₹500", 0)
        val b = get(SMS, "sms", "JD-HDFCBK-S", "Rs.500.00 credited to HDFC Bank A/c XX6911 on 24-11-26 from VPA 9876543210@axl (UPI 532612345678)", 60)
        ok("owner 2026-11-24: same payer number, other handle, SMS 1 h later = silent", b == "joined" && spoken == 1)
    }
    // ... a really different payer id is still a different payment (QR safety stays).
    Sim().run {
        get(PHONEPE, "upi", null, "RAMESH KUMAR (9876543210@ybl) sent you ₹500", 0)
        val b = get(SMS, "sms", "JD-HDFCBK-S", "Rs.500.00 credited to HDFC Bank A/c XX6911 on 24-11-26 from VPA *akar@ibl (UPI 532612349999)", 20)
        ok("another payer's id = another payment", b == "spoken" && spoken == 2)
    }

    // 5. A payment heard from ANOTHER phone / the bank (push) and later this phone's own message of the same shop money.
    val H = PaymentAlertParser
    val m = 60_000L
    val heard = ArrayList<PaymentAlertParser.Heard>()
    fun hear(path: String, scope: String, paise: Long, atMin: Long): Boolean = H.claimHeard(heard, path, scope, paise, atMin * m)
    ok("push for the shop's ₹500 is said", hear("remote", "shop1", 50000, 0))
    ok("owner 2026-11-24: this phone's own SMS for it 60 min later = silent", !hear("local", "shop1", 50000, 60))
    ok("a second real ₹500 of the shop later = said", hear("local", "shop1", 50000, 70))
    ok("the person's own money never pairs with the shop's push", hear("remote", "shop1", 7000, 100) && hear("local", "", 7000, 101))
    ok("another shop's push never pairs", hear("remote", "shop2", 9900, 200) && hear("local", "shop1", 9900, 201))
    ok("older than 2 h = a new payment", hear("remote", "shop1", 12300, 300) && hear("local", "shop1", 12300, 300 + 121))

    // 6. The voice is one MP3 made of parts. Each part's own tags (ID3, the "Info" frame) are dropped when joined, and
    //    the real length is counted from the frames -- the player stopped a sentence at the FIRST part's length.
    fun frame(): ByteArray { // MPEG-1 Layer III, 128 kbps, 44.1 kHz, no padding: 417 bytes, 1152 samples
        val f = ByteArray(417); f[0] = 0xFF.toByte(); f[1] = 0xFB.toByte(); f[2] = 0x90.toByte(); f[3] = 0x64; return f
    }
    fun infoFrame(): ByteArray { val f = frame(); "Info".toByteArray().copyInto(f, 4 + 32); return f }
    val id3 = byteArrayOf('I'.code.toByte(), 'D'.code.toByte(), '3'.code.toByte(), 4, 0, 0, 0, 0, 0, 20) + ByteArray(20)
    fun part(n: Int) = id3 + infoFrame() + (1..n).map { frame() }.reduce { a, b -> a + b }
    val V = PaymentVoicePack
    val joined = V.joinMp3(listOf(part(40), part(25), part(60)))
    ok("joined voice = only the sound frames", joined.size == 125 * 417)
    ok("joined voice length counted from its frames (125 x 26.1 ms)", V.mp3DurationMs(joined) in 3260L..3270L)
    ok("one part keeps its frames", V.mp3DurationMs(V.joinMp3(listOf(part(10)))) in 260L..262L)
    ok("not an MP3 -> no length", V.mp3DurationMs(ByteArray(100)) == 0L)
    // 7. A voice that already PLAYED is never said a second time by the fallback voice.
    ok("cut after the voice played = no second voice", !V.sayAgainAfterFailure(playedMs = 2600, expectedMs = 3000))
    ok("failed before any sound = the fallback voice says it", V.sayAgainAfterFailure(playedMs = 0, expectedMs = 3000))

    // 8. The night count: ONE voice per phone, whatever sides it listens for.
    val one = V.nightTotal(listOf(9 to 4_100_000L, 2 to 50_000L))
    ok("owner 2026-11-24: shop 9 + own 2 = one night line of 11", one == (11 to 4_150_000L))
    ok("no payment anywhere = nothing", V.nightTotal(listOf(0 to 0L, 0 to 0L)) == (0 to 0L))
}
