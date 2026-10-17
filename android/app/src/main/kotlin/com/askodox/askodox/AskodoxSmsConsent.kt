package com.askodox.askodox

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Bundle
import androidx.core.content.ContextCompat
import com.google.android.gms.auth.api.phone.SmsRetriever
import com.google.android.gms.common.api.CommonStatusCodes
import com.google.android.gms.common.api.Status

/**
 * OTP autofill with the Android SMS User Consent API.
 *
 * Firebase sends the sign-in SMS in its own format (no app hash), so the
 * hash-based SMS Retriever cannot match it; User Consent works with any OTP
 * SMS: Google Play services shows Android's own "Allow ASKODOX to read this
 * message?" prompt for ONE incoming message (5 min window). Nothing is read
 * without that tap, and no READ_SMS / RECEIVE_SMS permission exists.
 *
 * Only the 6-digit code leaves this class; the message text is never stored,
 * logged or sent to Dart.
 */
class AskodoxSmsConsent(
    private val activity: Activity,
    private val requestCode: Int,
    private val onEvent: (event: String, code: String?) -> Unit,
) {
    private var receiver: BroadcastReceiver? = null
    // The SMS arrived while ASKODOX was in the background (e.g. the person
    // opened the Messages app): Android blocks starting the prompt from the
    // background, so it opens when ASKODOX is in front again.
    private var pendingPrompt: Intent? = null
    var resumed = false
        private set

    fun start(): Boolean {
        stop()
        val listener = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                if (intent.action != SmsRetriever.SMS_RETRIEVED_ACTION) return
                val extras = intent.extras ?: return
                @Suppress("DEPRECATION")
                val status = extras.get(SmsRetriever.EXTRA_STATUS) as? Status ?: return
                when (status.statusCode) {
                    CommonStatusCodes.SUCCESS -> showPrompt(extras)
                    CommonStatusCodes.TIMEOUT -> {
                        stop()
                        onEvent("timeout", null)
                    }
                }
            }
        }
        return try {
            // Only Google Play services (holder of SEND_PERMISSION) can deliver this broadcast.
            ContextCompat.registerReceiver(
                activity,
                listener,
                IntentFilter(SmsRetriever.SMS_RETRIEVED_ACTION),
                SmsRetriever.SEND_PERMISSION,
                null,
                ContextCompat.RECEIVER_EXPORTED,
            )
            receiver = listener
            SmsRetriever.getClient(activity).startSmsUserConsent(null)
                .addOnSuccessListener { onEvent("listening", null) }
                .addOnFailureListener { error ->
                    stop()
                    onEvent("error", error.javaClass.simpleName)
                }
            true
        } catch (error: Exception) {
            stop()
            onEvent("error", error.javaClass.simpleName)
            false
        }
    }

    private fun showPrompt(extras: Bundle) {
        @Suppress("DEPRECATION")
        val consent = extras.getParcelable<Intent>(SmsRetriever.EXTRA_CONSENT_INTENT)
        // Launch only Google Play services' own consent screen, never an
        // arbitrary intent with URI grants (intent redirection).
        val grants = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
        val target = consent?.component?.packageName ?: consent?.resolveActivity(activity.packageManager)?.packageName
        if (consent == null || target != "com.google.android.gms" || (consent.flags and grants) != 0) {
            onEvent("error", "untrusted_consent_intent")
            return
        }
        if (!resumed) {
            pendingPrompt = consent
            onEvent("waiting_for_app", null)
            return
        }
        launch(consent)
    }

    private fun launch(consent: Intent) {
        try {
            activity.startActivityForResult(consent, requestCode)
            onEvent("prompt", null)
        } catch (error: Exception) {
            onEvent("error", error.javaClass.simpleName)
        }
    }

    fun onResume() {
        resumed = true
        val waiting = pendingPrompt ?: return
        pendingPrompt = null
        launch(waiting)
    }

    fun onPause() {
        resumed = false
    }

    /** True when this was the consent screen's answer. */
    fun handleResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != this.requestCode) return false
        stop()
        if (resultCode != Activity.RESULT_OK) {
            onEvent("denied", null)
            return true
        }
        val code = extractCode(data?.getStringExtra(SmsRetriever.EXTRA_SMS_MESSAGE))
        if (code == null) onEvent("no_code", null) else onEvent("code", code)
        return true
    }

    fun stop() {
        pendingPrompt = null
        val current = receiver ?: return
        receiver = null
        try { activity.unregisterReceiver(current) } catch (_: Exception) {}
    }

    companion object {
        private val sixDigits = Regex("(?<!\\d)(\\d{6})(?!\\d)")

        /** The first standalone 6-digit number in the message (ASKODOX / Firebase codes are 6 digits). */
        fun extractCode(message: String?): String? = message?.let { sixDigits.find(it)?.groupValues?.get(1) }
    }
}
