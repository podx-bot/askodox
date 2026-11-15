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
    println(if (fails == 0) "ALL PASS" else "$fails FAILED")
    if (fails > 0) kotlin.system.exitProcess(1)
}
