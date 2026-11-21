import com.askodox.askodox.PaymentAlertParser
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
    val min = 60_000L
    yes("late bank app 13 min after sms = same", PaymentAlertParser.samePaymentWindow("bank", listOf("sms"), 13 * min))
    yes("app 59 min after sms = same", PaymentAlertParser.samePaymentWindow("upi", listOf("sms"), 59 * min))
    yes("app 61 min after sms = new", !PaymentAlertParser.samePaymentWindow("upi", listOf("sms"), 61 * min))
    yes("sms 2 min after app = same", PaymentAlertParser.samePaymentWindow("sms", listOf("upi"), 2 * min))
    yes("sms 20 min after app = new (QR payment)", !PaymentAlertParser.samePaymentWindow("sms", listOf("upi"), 20 * min))
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
    check("phonepe to your bank", "Received ₹3,000", "VOODUGULA DURGA sent ₹3,000 to your ICICI Bank account", "IN 300000 payer=VOODUGULA DURGA")
    check("received sent to your a/c", null, "Received ₹3,000 from VOODUGULA DURGA. Sent to your bank account XX4321", "IN 300000")
    check("paid to your account", null, "₹3,000 received! DURGA paid to your account", "IN 300000")
    check("real debit still out", null, "Paid ₹3,000 to VOODUGULA DURGA", "OUT 300000 to=VOODUGULA DURGA")
    check("icici debit with credited still out", null, "ICICI Bank Acct XX123 debited for Rs 3000.00 on 20-Nov-26; DURGA credited. UPI:532012345678", "OUT 300000")
    // Incoming + outgoing words, no strong debit word = a doubtful debit (❓ on the phone, never sure).
    val mixed = PaymentAlertParser.parse(null, "Received ₹3,000 from DURGA, sent to Ramesh")
    yes("mixed wording is doubtful", mixed is Result.Outgoing && mixed.doubtful)
    val sure = PaymentAlertParser.parse(null, "ICICI Bank Acct XX123 debited for Rs 3000.00; DURGA credited.")
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
    println(if (fails == 0) "ALL PASS" else "$fails FAILED")
    if (fails > 0) kotlin.system.exitProcess(1)
}
