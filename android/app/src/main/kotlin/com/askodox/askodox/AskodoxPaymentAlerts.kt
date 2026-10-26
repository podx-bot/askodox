package com.askodox.askodox

import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import androidx.core.app.NotificationManagerCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.Calendar
import java.util.Locale
import java.util.concurrent.Executors

/**
 * Payment voice alerts ("soundbox on the phone") on their OWN channel
 * ("com.askodox.app/payment_alerts"; one register line in MainActivity).
 *
 * The listener service reads ONLY notifications of the payment apps the owner allowed, only after the
 * owner granted Android notification access themselves. It speaks through normal media audio (so a
 * connected Bluetooth speaker plays it), keeps a small local log, and reports a minimal event
 * (amount, app, reference) to the shop's ASKODOX account. It never stores notification text.
 */
object AskodoxPaymentAlerts {
    private const val CHANNEL = "com.askodox.app/payment_alerts"
    private const val PREFS = "askodox_payment_alerts"
    private const val MAX_EVENTS = 300
    private var channel: MethodChannel? = null
    private val main = Handler(Looper.getMainLooper())
    private val io = Executors.newSingleThreadExecutor()

    fun register(activity: Activity, messenger: BinaryMessenger) {
        val app = activity.applicationContext
        val ch = MethodChannel(messenger, CHANNEL)
        channel = ch
        ch.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "status" -> result.success(status(app))
                    "configure" -> {
                        val json = call.argument<String>("config") ?: "{}"
                        prefs(app).edit().putString("config", JSONObject(json).toString()).apply()
                        requestRebind(app)
                        result.success(status(app))
                    }
                    "clear" -> { prefs(app).edit().clear().apply(); result.success(true) }
                    "openListenerSettings" -> {
                        activity.startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                        result.success(true)
                    }
                    "openBatterySettings" -> {
                        activity.startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                        result.success(true)
                    }
                    "openBluetoothSettings" -> {
                        activity.startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS))
                        result.success(true)
                    }
                    "showVolume" -> {
                        val audio = app.getSystemService(Context.AUDIO_SERVICE) as AudioManager
                        audio.adjustStreamVolume(AudioManager.STREAM_MUSIC, AudioManager.ADJUST_SAME, AudioManager.FLAG_SHOW_UI)
                        result.success(audioRoute(app))
                    }
                    "audioRoute" -> result.success(audioRoute(app))
                    "speakTest" -> {
                        val amount = (call.argument<Number>("amountPaise") ?: 100).toLong()
                        speak(app, amount, test = true, eventId = null)
                        result.success(audioRoute(app))
                    }
                    "speakText" -> {
                        Speaker.say(app, call.argument<String>("text") ?: "", call.argument<String>("language") ?: "te",
                            config(app), null)
                        result.success(true)
                    }
                    "events" -> result.success(events(app).toString())
                    "markUploaded" -> {
                        markUploaded(app, call.argument<String>("localId") ?: "", call.argument<String>("serverId"),
                            call.argument<String>("error"))
                        result.success(true)
                    }
                    "simulate" -> {
                        // Debug-only path used by the in-app "test detection" button: runs the SAME parser and
                        // pipeline on a sample text, marked test=true so it is never counted as a payment.
                        val r = handle(app, "askodox.test", call.argument<String>("title"), call.argument<String>("text"),
                            "sim-${System.currentTimeMillis()}", System.currentTimeMillis(), test = true)
                        result.success(r)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("payment_alerts", e.message, null)
            }
        }
    }

    // ----------------------------------------------------------------- state
    fun prefs(context: Context): SharedPreferences = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun config(context: Context): JSONObject =
        try { JSONObject(prefs(context).getString("config", "{}") ?: "{}") } catch (_: Exception) { JSONObject() }

    fun listenerAllowed(context: Context): Boolean =
        NotificationManagerCompat.getEnabledListenerPackages(context).contains(context.packageName)

    private fun requestRebind(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && listenerAllowed(context)) {
            try {
                NotificationListenerService.requestRebind(ComponentName(context, AskodoxPaymentAlertListener::class.java))
            } catch (_: Exception) {
            }
        }
    }

    /** False in sideloaded builds: the listener is declared only in Play-distributed builds. */
    fun listenerDeclared(context: Context): Boolean = try {
        context.packageManager.getServiceInfo(ComponentName(context, AskodoxPaymentAlertListener::class.java), 0)
        true
    } catch (_: Exception) {
        false
    }

    private fun status(context: Context): Map<String, Any?> {
        val cfg = config(context)
        return mapOf(
            "listenerDeclared" to listenerDeclared(context),
            "listenerAllowed" to listenerAllowed(context),
            "enabled" to cfg.optBoolean("enabled", false),
            "connectedAt" to prefs(context).getLong("listener_connected_at", 0L),
            "disconnectedAt" to prefs(context).getLong("listener_disconnected_at", 0L),
            "ttsReady" to Speaker.ready,
            "ttsLanguageOk" to Speaker.languageOk,
            "pending" to events(context).let { list -> (0 until list.length()).count { !list.getJSONObject(it).has("server_id") } },
            "audio" to audioRoute(context),
        )
    }

    fun audioRoute(context: Context): Map<String, Any?> {
        val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        var bluetooth: String? = null
        var wired = false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            for (d in audio.getDevices(AudioManager.GET_DEVICES_OUTPUTS)) {
                when (d.type) {
                    AudioDeviceInfo.TYPE_BLUETOOTH_A2DP -> bluetooth = d.productName?.toString() ?: "Bluetooth"
                    AudioDeviceInfo.TYPE_WIRED_HEADSET, AudioDeviceInfo.TYPE_WIRED_HEADPHONES -> wired = true
                }
            }
        }
        val max = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        val vol = audio.getStreamVolume(AudioManager.STREAM_MUSIC)
        return mapOf(
            "output" to when { bluetooth != null -> "bluetooth"; wired -> "wired"; else -> "phone" },
            "bluetoothName" to bluetooth,
            "mediaVolumePct" to if (max > 0) vol * 100 / max else 0,
            "silent" to (audio.ringerMode != AudioManager.RINGER_MODE_NORMAL),
        )
    }

    @Synchronized
    fun events(context: Context): JSONArray =
        try { JSONArray(prefs(context).getString("events", "[]") ?: "[]") } catch (_: Exception) { JSONArray() }

    @Synchronized
    private fun saveEvents(context: Context, list: JSONArray) {
        val trimmed = JSONArray()
        val start = maxOf(0, list.length() - MAX_EVENTS)
        for (i in start until list.length()) trimmed.put(list.get(i))
        prefs(context).edit().putString("events", trimmed.toString()).apply()
    }

    @Synchronized
    private fun update(context: Context, localId: String, block: (JSONObject) -> Unit) {
        val list = events(context)
        for (i in 0 until list.length()) {
            val e = list.getJSONObject(i)
            if (e.optString("local_id") == localId) { block(e); break }
        }
        saveEvents(context, list)
    }

    private fun markUploaded(context: Context, localId: String, serverId: String?, error: String?) =
        update(context, localId) { e ->
            if (serverId != null) e.put("server_id", serverId)
            if (error != null) e.put("upload_error", error)
        }

    /** Seen keys (pkg + notification + amount + its own time) survive restarts; older than 2 days are dropped. */
    @Synchronized
    private fun firstTime(context: Context, key: String, now: Long): Boolean {
        val seen = try { JSONObject(prefs(context).getString("seen", "{}") ?: "{}") } catch (_: Exception) { JSONObject() }
        if (seen.has(key)) return false
        val fresh = JSONObject()
        val names = seen.keys().asSequence().toList()
        for (n in names) { val t = seen.optLong(n); if (now - t < 2 * 24 * 3600 * 1000L) fresh.put(n, t) }
        fresh.put(key, now)
        prefs(context).edit().putString("seen", fresh.toString()).apply()
        return true
    }

    // -------------------------------------------------------------- pipeline
    /** Returns a small map describing what happened (for tests / the simulate button). */
    fun handle(context: Context, pkg: String, title: String?, text: String?, notificationKey: String, whenMillis: Long,
               test: Boolean = false): Map<String, Any?> {
        val cfg = config(context)
        if (!test && !cfg.optBoolean("enabled", false)) return mapOf("result" to "disabled")
        val parsed = PaymentAlertParser.parse(title, text)
        if (parsed is PaymentAlertParser.Result.Ignored) return mapOf("result" to "ignored")
        val amount = (parsed as? PaymentAlertParser.Result.Accepted)?.amountPaise
        val reference = (parsed as? PaymentAlertParser.Result.Accepted)?.reference
        val key = if (reference != null) "$pkg|ref|$reference" else "$pkg|$notificationKey|${amount ?: 0}|$whenMillis"
        val now = System.currentTimeMillis()
        if (!firstTime(context, key, now)) return mapOf("result" to "duplicate")
        val localId = "pa-$now-${(Math.random() * 1e6).toInt()}"
        val labels = cfg.optJSONObject("apps")
        val event = JSONObject()
            .put("local_id", localId)
            .put("client_event_id", key.take(110).replace(Regex("[^A-Za-z0-9_.:|-]"), "_"))
            .put("source_app", pkg)
            .put("source_label", labels?.optString(pkg, pkg) ?: pkg)
            .put("detected_at", isoUtc(now))
            .put("status", if (amount != null) "notification_unverified" else "ambiguous")
            .put("test", test)
        if (amount != null) event.put("amount_paise", amount)
        if (reference != null) event.put("reference", reference)
        if (parsed is PaymentAlertParser.Result.Ambiguous) event.put("reason", parsed.reason)
        val cal = Calendar.getInstance()
        val quiet = PaymentAlertParser.inQuietHours(cfg.optString("quiet_start"), cfg.optString("quiet_end"),
            cal.get(Calendar.HOUR_OF_DAY) * 60 + cal.get(Calendar.MINUTE))
        event.put("spoken", if (quiet) "quiet_hours" else "pending")
        synchronized(this) { val list = events(context); list.put(event); saveEvents(context, list) }
        if (!quiet) speak(context, amount, test, localId)
        main.post { channel?.invokeMethod("paymentEvent", event.toString()) }
        if (!test) upload(context, localId)
        return mapOf("result" to if (amount != null) "accepted" else "ambiguous", "localId" to localId,
            "amountPaise" to amount, "spoken" to !quiet)
    }

    private fun speak(context: Context, amount: Long?, test: Boolean, eventId: String?) {
        val cfg = config(context)
        val language = cfg.optString("language", "te").ifEmpty { "te" }
        Speaker.say(context, PaymentAlertParser.announcement(amount, language, test), language, cfg) { ok ->
            if (eventId != null) update(context, eventId) { it.put("spoken", if (ok) "announced" else "tts_failed") }
        }
    }

    /** Best effort, off the main thread: the app syncs anything left pending when it opens. */
    private fun upload(context: Context, localId: String) {
        io.execute {
            try {
                val cfg = config(context)
                val base = cfg.optString("base_url").trimEnd('/')
                val token = cfg.optString("token")
                val biz = cfg.optString("business_id")
                if (base.isEmpty() || token.isEmpty() || biz.isEmpty()) return@execute
                Thread.sleep(2500) // let the announcement finish so "spoken" is final
                val e = events(context).let { list ->
                    (0 until list.length()).map { list.getJSONObject(it) }.firstOrNull { it.optString("local_id") == localId }
                } ?: return@execute
                val body = JSONObject()
                for (k in listOf("client_event_id", "source_app", "amount_paise", "reference", "detected_at", "reason")) {
                    if (e.has(k)) body.put(k, e.get(k))
                }
                val spoken = e.optString("spoken")
                if (spoken != "pending") body.put("spoken", spoken)
                if (cfg.optString("device_id").isNotEmpty()) body.put("device_id", cfg.optString("device_id"))
                val conn = URL("$base/api/pos/businesses/$biz/payment-alerts/events").openConnection() as HttpURLConnection
                conn.requestMethod = "POST"
                conn.connectTimeout = 15000
                conn.readTimeout = 15000
                conn.doOutput = true
                conn.setRequestProperty("Content-Type", "application/json")
                conn.setRequestProperty("Authorization", "Bearer $token")
                conn.outputStream.use { it.write(body.toString().toByteArray(Charsets.UTF_8)) }
                val code = conn.responseCode
                if (code == 200) {
                    val text = conn.inputStream.bufferedReader().use { it.readText() }
                    markUploaded(context, localId, JSONObject(text).optString("id"), null)
                } else if (code in 400..499 && code != 401 && code != 429) {
                    markUploaded(context, localId, null, "http_$code")
                }
                conn.disconnect()
            } catch (_: Exception) {
                // offline: stays pending; the app retries when it opens
            }
        }
    }

    private fun isoUtc(millis: Long): String {
        val fmt = java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US)
        fmt.timeZone = java.util.TimeZone.getTimeZone("UTC")
        return fmt.format(java.util.Date(millis))
    }

    /** One TextToSpeech for alerts, on MEDIA audio (Bluetooth speaker when connected), queued (QUEUE_ADD). */
    object Speaker {
        private var tts: TextToSpeech? = null
        @Volatile var ready = false
        @Volatile var languageOk = true
        private val waiting = mutableListOf<() -> Unit>()
        private val callbacks = mutableMapOf<String, (Boolean) -> Unit>()

        @Synchronized
        fun say(context: Context, text: String, language: String, cfg: JSONObject, done: ((Boolean) -> Unit)?) {
            if (text.isBlank()) return
            val action = { speakNow(text, language, cfg, done) }
            if (ready) { action(); return }
            waiting.add(action)
            if (tts == null) {
                tts = TextToSpeech(context.applicationContext) { status ->
                    synchronized(this) {
                        ready = status == TextToSpeech.SUCCESS
                        val run = waiting.toList()
                        waiting.clear()
                        if (ready) {
                            tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                                override fun onStart(utteranceId: String?) {}
                                override fun onDone(utteranceId: String?) { finish(utteranceId, true) }
                                @Deprecated("Deprecated in Java")
                                override fun onError(utteranceId: String?) { finish(utteranceId, false) }
                                override fun onError(utteranceId: String?, errorCode: Int) { finish(utteranceId, false) }
                            })
                            run.forEach { it() }
                        } else {
                            tts = null
                            done?.invoke(false)
                        }
                    }
                }
            }
        }

        @Synchronized
        private fun finish(id: String?, ok: Boolean) {
            val cb = id?.let { callbacks.remove(it) } ?: return
            cb(ok)
        }

        private fun speakNow(text: String, language: String, cfg: JSONObject, done: ((Boolean) -> Unit)?) {
            val engine = tts ?: run { done?.invoke(false); return }
            val locale = when (language) { "te" -> Locale("te", "IN"); "hi" -> Locale("hi", "IN"); else -> Locale("en", "IN") }
            val res = engine.setLanguage(locale)
            languageOk = res != TextToSpeech.LANG_MISSING_DATA && res != TextToSpeech.LANG_NOT_SUPPORTED
            var spoken = text
            if (!languageOk && language != "en") {
                engine.setLanguage(Locale("en", "IN"))
                spoken = PaymentAlertParser.announcement(Regex("""\d+""").find(text)?.value?.toLongOrNull()?.times(100), "en",
                    text.startsWith("టెస్ట్") || text.startsWith("टेस्ट"))
            }
            val wantMale = cfg.optString("voice") == "male"
            try {
                engine.voices?.filter { it.locale.language == engine.voice?.locale?.language && !it.isNetworkConnectionRequired }
                    ?.firstOrNull { v ->
                        val name = v.name.lowercase()
                        if (wantMale) name.contains("male") && !name.contains("female") else name.contains("female")
                    }
                    ?.let { engine.voice = it }
            } catch (_: Exception) {
            }
            engine.setSpeechRate(cfg.optInt("rate_pct", 100).coerceIn(50, 200) / 100f)
            engine.setAudioAttributes(AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
            val params = Bundle()
            params.putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, cfg.optInt("volume_pct", 100).coerceIn(10, 100) / 100f)
            params.putInt(TextToSpeech.Engine.KEY_PARAM_STREAM, AudioManager.STREAM_MUSIC)
            val id = "pa-${System.nanoTime()}"
            if (done != null) synchronized(this) { callbacks[id] = done }
            if (engine.speak(spoken, TextToSpeech.QUEUE_ADD, params, id) == TextToSpeech.ERROR) finish(id, false)
        }
    }
}

/** Reads ONLY allowed payment apps' notifications; everything else returns before any content is touched. */
class AskodoxPaymentAlertListener : NotificationListenerService() {
    override fun onListenerConnected() {
        AskodoxPaymentAlerts.prefs(this).edit().putLong("listener_connected_at", System.currentTimeMillis()).apply()
    }

    override fun onListenerDisconnected() {
        AskodoxPaymentAlerts.prefs(this).edit().putLong("listener_disconnected_at", System.currentTimeMillis()).apply()
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        val n = sbn ?: return
        try {
            val cfg = AskodoxPaymentAlerts.config(this)
            if (!cfg.optBoolean("enabled", false)) return
            val apps = cfg.optJSONObject("apps") ?: return
            if (!apps.has(n.packageName)) return // not an allowed payment app: never read
            if (n.isOngoing) return
            val notification = n.notification ?: return
            if (notification.flags and android.app.Notification.FLAG_GROUP_SUMMARY != 0) return
            val extras = notification.extras ?: return
            val title = extras.getCharSequence(android.app.Notification.EXTRA_TITLE)?.toString()
            val text = listOfNotNull(
                extras.getCharSequence(android.app.Notification.EXTRA_TEXT)?.toString(),
                extras.getCharSequence(android.app.Notification.EXTRA_BIG_TEXT)?.toString(),
            ).distinct().joinToString(" ")
            val whenMillis = if (notification.`when` > 0) notification.`when` else n.postTime
            AskodoxPaymentAlerts.handle(this, n.packageName, title, text, n.key ?: "${n.id}", whenMillis)
        } catch (_: Exception) {
            // a malformed notification never crashes the listener
        }
    }
}
