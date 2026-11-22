package com.askodox.askodox

import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
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
    internal val main = Handler(Looper.getMainLooper())
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
                        val next = JSONObject(json)
                        if (call.argument<String>("scope") == "personal") {
                            // Owner 2026-11-15 (pani F): "My phone" has its OWN settings, so the shop and the
                            // person's own apps are heard at the same time (no more "last screen opened wins").
                            prefs(app).edit().putString("personal_config", next.toString()).apply()
                            requestRebind(app)
                            CloudVoice.prefetch(app, next)
                            result.success(status(app))
                            return@setMethodCallHandler
                        }
                        // Owner 2026-11-15: a phone can belong to several shops (its own + a shop where the person is
                        // staff). Keep THIS phone's device id for EVERY shop it opened, so an alert pushed from any of
                        // them is acknowledged with that shop's own device id (one id for all -> 403 "not your device").
                        val ids = config(app).optJSONObject("device_ids") ?: JSONObject()
                        val biz = next.optString("business_id")
                        val dev = next.optString("device_id")
                        if (biz.isNotEmpty() && dev.isNotEmpty()) ids.put(biz, dev)
                        next.put("device_ids", ids)
                        prefs(app).edit().putString("config", next.toString()).apply()
                        requestRebind(app)
                        CloudVoice.prefetch(app, JSONObject(json)) // the fixed words, once per voice / language
                        result.success(status(app))
                    }
                    // Owner 2026-11-20 (staff zero setup): a shop's staff phone hears that shop's payments without
                    // opening any page -- only this shop's device id (and the sign-in / server it acks to) is added;
                    // the phone's own shop settings, if any, stay as they are.
                    "joinShop" -> {
                        val biz = call.argument<String>("businessId") ?: ""
                        val dev = call.argument<String>("deviceId") ?: ""
                        if (biz.isEmpty() || dev.isEmpty()) { result.success(false); return@setMethodCallHandler }
                        val cfg = config(app)
                        val ids = cfg.optJSONObject("device_ids") ?: JSONObject()
                        ids.put(biz, dev)
                        cfg.put("device_ids", ids)
                        if (cfg.optString("base_url").isEmpty()) cfg.put("base_url", call.argument<String>("baseUrl") ?: "")
                        val token = call.argument<String>("token") ?: ""
                        if (token.isNotEmpty()) cfg.put("token", token)
                        if (!cfg.has("language")) cfg.put("language", call.argument<String>("language") ?: "te")
                        if (!cfg.has("cloud_voice")) cfg.put("cloud_voice", true)
                        prefs(app).edit().putString("config", cfg.toString()).apply()
                        Speaker.warm(app)
                        result.success(true)
                    }
                    "clear" -> { prefs(app).edit().clear().apply(); result.success(true) }
                    "openListenerSettings" -> {
                        activity.startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                        result.success(true)
                    }
                    "openBatterySettings" -> {
                        // Owner 2026-11-20: Android's own one-tap "Allow" dialog when this build may ask (Play builds);
                        // otherwise the battery list as before.
                        val direct = try {
                            val declared = app.packageManager.getPackageInfo(app.packageName,
                                android.content.pm.PackageManager.GET_PERMISSIONS).requestedPermissions?.contains(
                                "android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS") == true
                            if (declared) {
                                activity.startActivity(Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                                    Uri.parse("package:" + app.packageName)))
                                true
                            } else false
                        } catch (_: Exception) { false }
                        if (!direct) activity.startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                        result.success(true)
                    }
                    // Xiaomi / Oppo / Vivo / Realme / OnePlus / Huawei / Honor / Asus / iQOO stop apps in the
                    // background unless "Autostart" is on. Opens that maker's own page; false = this phone has none.
                    "openAutostartSettings" -> result.success(openAutostart(activity))
                    "hasAutostartSettings" -> result.success(autostartIntent(app) != null)
                    "openSmsAppSettings" -> {
                        val pkg = defaultSmsPackage(app)
                        if (pkg != null) activity.startActivity(appNotificationSettings(app, pkg))
                        result.success(pkg)
                    }
                    "defaultSmsApp" -> result.success(defaultSmsPackage(app))
                    // Owner 2026-11-19: the history row shows the icon of the app the alert came from (the phone's own
                    // installed icon -- no copied logos). PNG bytes, or null when the app is not installed.
                    "appIcon" -> result.success(appIconPng(app, call.argument<String>("package") ?: ""))
                    "paymentApps" -> result.success(paymentApps(app, call.argument<List<String>>("packages") ?: emptyList()))
                    "openAppNotificationSettings" -> {
                        activity.startActivity(appNotificationSettings(app, call.argument<String>("package") ?: app.packageName))
                        result.success(true)
                    }
                    "openAppDetails" -> {
                        activity.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            Uri.parse("package:" + (call.argument<String>("package") ?: app.packageName))))
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
                    "checkDues" -> { checkDues(app); result.success(true) }
                    "offlineVoice" -> result.success(Speaker.offlineVoice(app, call.argument<String>("language") ?: "te"))
                    "installOfflineVoice" -> result.success(installOfflineVoice(activity))
                    "speakTest" -> {
                        val amount = (call.argument<Number>("amountPaise") ?: 100).toLong()
                        val cfg = if (call.argument<String>("scope") == "personal") personalConfig(app) else config(app)
                        speak(app, amount, test = true, eventId = null, cfg = cfg)
                        result.success(audioRoute(app))
                    }
                    "speakText" -> {
                        Speaker.say(app, call.argument<String>("text") ?: "", call.argument<String>("language") ?: "te",
                            config(app), null)
                        result.success(true)
                    }
                    // Owner 2026-11-22 (Payment voice folder): which kinds of money message are SPOKEN, per scope
                    // ("personal" = My phone, else the shop on this phone). Kept apart from configure() so a later
                    // configure never wipes the person's choices.
                    "setVoiceKinds" -> {
                        val personal = call.argument<String>("scope") == "personal"
                        val next = try { JSONObject(call.argument<String>("kinds") ?: "{}") } catch (_: Exception) { JSONObject() }
                        next.remove("fake") // the fake-message warning is always on
                        prefs(app).edit().putString(voiceKindsKey(personal), next.toString()).apply()
                        result.success(voiceKinds(app, personal).toString())
                    }
                    "voiceKinds" -> result.success(voiceKinds(app, call.argument<String>("scope") == "personal").toString())
                    // "▶ Listen" in the folder: the SAME words and voice a real message of that kind gets.
                    "speakKind" -> {
                        val personal = call.argument<String>("scope") == "personal"
                        val cfg = if (personal) personalConfig(app) else config(app)
                        val language = (call.argument<String>("language") ?: cfg.optString("language", "te")).ifEmpty { "te" }
                        val parts = sampleParts(call.argument<String>("kind") ?: "in", language, personal, cfg)
                        if (parts.isNotEmpty()) CloudVoice.say(app, parts, language, cfg, null)
                        result.success(parts.joinToString(" "))
                    }
                    "speakRemote" -> result.success(speakRemote(app, call.argument<String>("eventId") ?: "",
                        call.argument<String>("text") ?: "", call.argument<String>("language") ?: "te", null, false, null))
                    "events" -> result.success(events(app).toString())
                    "deleteEvents" -> result.success(deleteEvents(app, call.argument<List<String>>("localIds")))
                    "correctEvent" -> result.success(correctEvent(app, call.argument<String>("localId") ?: "",
                        call.argument<String>("choice") ?: ""))
                    "installedApps" -> result.success(installedApps(app))
                    "unknowns" -> result.success(unknowns(app).toString())
                    "learnUnknown" -> result.success(learnUnknown(app, call.argument<String>("id") ?: "",
                        call.argument<Boolean>("received") == true))
                    "markUploaded" -> {
                        markUploaded(app, call.argument<String>("localId") ?: "", call.argument<String>("serverId"),
                            call.argument<String>("error"))
                        result.success(true)
                    }
                    "simulate" -> {
                        // Debug-only path used by the in-app "test detection" button: runs the SAME parser and
                        // pipeline on a sample text, marked test=true so it is never counted as a payment.
                        val cfg = if (call.argument<String>("scope") == "personal") personalConfig(app) else config(app)
                        val r = handle(app, "askodox.test", call.argument<String>("title"), call.argument<String>("text"),
                            "sim-${System.currentTimeMillis()}", System.currentTimeMillis(), test = true, cfgIn = cfg)
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

    /** The person's own "My phone" settings (separate from the shop's, owner 2026-11-15 pani F). */
    fun personalConfig(context: Context): JSONObject =
        try { JSONObject(prefs(context).getString("personal_config", "{}") ?: "{}") } catch (_: Exception) { JSONObject() }

    /**
     * Where ONE notification of [pkg] goes: the shop ("shop"), the person's own history ("mine") or nowhere (null).
     * A notification always has exactly ONE destination. When both lists hold the app the person's own choice
     * (`destinations`) decides; without one a business app (PhonePe Business, GPay for Business, Paytm for Business
     * ...) goes to the shop and everything else to "My phone".
     */
    fun destination(shop: JSONObject, mine: JSONObject, pkg: String): Pair<String, JSONObject>? {
        val shopOn = shop.optBoolean("enabled", false) && shop.optString("business_id").isNotEmpty() &&
            shop.optJSONObject("apps")?.has(pkg) == true
        // Before this update "My phone" was saved as the shop config with no business id: keep it working.
        val legacyMine = !shop.has("business_id") || shop.optString("business_id").isEmpty()
        val mineCfg = if (mine.length() == 0 && legacyMine) shop else mine
        val mineOn = mineCfg.optBoolean("enabled", false) && mineCfg.optJSONObject("apps")?.has(pkg) == true &&
            mineCfg.optString("business_id").isEmpty()
        if (shopOn && mineOn) {
            val chosen = mine.optJSONObject("destinations")?.optString(pkg).orEmpty()
            val toShop = if (chosen.isNotEmpty()) chosen == "shop" else isBusinessApp(pkg)
            return if (toShop) "shop" to shop else "mine" to mineCfg
        }
        if (shopOn) return "shop" to shop
        if (mineOn) return "mine" to mineCfg
        return null
    }

    fun isBusinessApp(pkg: String): Boolean {
        val p = pkg.lowercase(Locale.ROOT)
        return p.contains("business") || p.contains("merchant") || p.contains(".biz") || p.endsWith("forbusiness")
    }

    /** Kinds of message that come through the SMS app NEXT TO the bank's debit SMS for the same money. */
    private val SIDE_KINDS = setOf("biller", "billpay")

    /** upi | bank | sms | other: the person's list says it; otherwise guessed from the package name. */
    fun kindOf(cfg: JSONObject, pkg: String): String {
        cfg.optJSONObject("kinds")?.optString(pkg)?.takeIf { it.isNotEmpty() }?.let { return it }
        val p = pkg.lowercase(Locale.ROOT)
        return when {
            p.contains("messag") || p.contains("mms") || p.contains("sms") -> "sms"
            p.contains("phonepe") || p.contains("paisa") || p.contains("paytm") || p.contains("npci") ||
                p.contains("super.payments") || p.contains("mobikwik") || p.contains("freecharge") || p.contains("cred") -> "upi"
            else -> "bank"
        }
    }

    private fun appIconPng(context: Context, pkg: String): ByteArray? = try {
        if (pkg.isBlank()) null else {
            val drawable = context.packageManager.getApplicationIcon(pkg)
            val size = 96
            val bitmap = android.graphics.Bitmap.createBitmap(size, size, android.graphics.Bitmap.Config.ARGB_8888)
            val canvas = android.graphics.Canvas(bitmap)
            drawable.setBounds(0, 0, size, size)
            drawable.draw(canvas)
            val out = java.io.ByteArrayOutputStream()
            bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, out)
            out.toByteArray()
        }
    } catch (_: Exception) {
        null
    }

    private fun defaultSmsPackage(context: Context): String? = try {
        android.provider.Telephony.Sms.getDefaultSmsPackage(context)
    } catch (_: Exception) {
        null
    }

    private val autostartComponents = listOf(
        "com.miui.securitycenter" to "com.miui.permcenter.autostart.AutoStartManagementActivity",
        "com.coloros.safecenter" to "com.coloros.safecenter.permission.startup.StartupAppListActivity",
        "com.coloros.safecenter" to "com.coloros.safecenter.startupapp.StartupAppListActivity",
        "com.oppo.safe" to "com.oppo.safe.permission.startup.StartupAppListActivity",
        "com.oplus.safecenter" to "com.oplus.safecenter.startupapp.StartupAppListActivity",
        "com.vivo.permissionmanager" to "com.vivo.permissionmanager.activity.BgStartUpManagerActivity",
        "com.iqoo.secure" to "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity",
        "com.iqoo.secure" to "com.iqoo.secure.ui.phoneoptimize.BgStartUpManager",
        "com.huawei.systemmanager" to "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity",
        "com.huawei.systemmanager" to "com.huawei.systemmanager.optimize.process.ProtectActivity",
        "com.hihonor.systemmanager" to "com.hihonor.systemmanager.startupmgr.ui.StartupNormalAppListActivity",
        "com.oneplus.security" to "com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity",
        "com.asus.mobilemanager" to "com.asus.mobilemanager.autostart.AutoStartActivity",
        "com.letv.android.letvsafe" to "com.letv.android.letvsafe.AutobootManageActivity",
        "com.transsion.phonemaster" to "com.cyin.himgr.autostart.AutoStartActivity",
    )

    private fun autostartIntent(context: Context): Intent? {
        val pm = context.packageManager
        for ((pkg, cls) in autostartComponents) {
            val i = Intent().setComponent(ComponentName(pkg, cls)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            try {
                if (pm.resolveActivity(i, 0) != null) return i
            } catch (_: Exception) {
            }
        }
        return null
    }

    private fun openAutostart(activity: Activity): Boolean {
        val i = autostartIntent(activity) ?: return false
        return try {
            activity.startActivity(i)
            true
        } catch (_: Exception) {
            false
        }
    }

    fun listenerAllowed(context: Context): Boolean =
        NotificationManagerCompat.getEnabledListenerPackages(context).contains(context.packageName)

    /**
     * Owner 2026-11-15: after a Play update Android (Samsung and others) can leave the listener unbound until the
     * person toggles notification access. Ask the system to bind it again whenever this app starts, is updated,
     * or the listener is disconnected -- not only when the alerts screen is opened.
     */
    fun rebindIfEnabled(context: Context) {
        if (config(context).optBoolean("enabled", false) || personalConfig(context).optBoolean("enabled", false)) {
            requestRebind(context)
        }
    }

    fun requestRebind(context: Context) {
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

    /**
     * Owner 2026-11-17: the voice must work WITHOUT internet in the language the person chose. Opens the phone's own
     * "download voice data" page (Google / Samsung speech engine); falls back to the text-to-speech settings page.
     */
    private fun installOfflineVoice(context: Context): Boolean {
        for (intent in listOf(Intent(TextToSpeech.Engine.ACTION_INSTALL_TTS_DATA), Intent("com.android.settings.TTS_SETTINGS"))) {
            try {
                if (context !is android.app.Activity) intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(intent)
                return true
            } catch (_: Exception) {
            }
        }
        return false
    }

    private fun status(context: Context): Map<String, Any?> {
        Speaker.warm(context)
        val cfg = config(context)
        return mapOf(
            "listenerDeclared" to listenerDeclared(context),
            "listenerAllowed" to listenerAllowed(context),
            "enabled" to cfg.optBoolean("enabled", false),
            "personalEnabled" to personalConfig(context).optBoolean("enabled", false),
            "autostartPage" to (autostartIntent(context) != null),
            "smsApp" to defaultSmsPackage(context),
            "connectedAt" to prefs(context).getLong("listener_connected_at", 0L),
            "disconnectedAt" to prefs(context).getLong("listener_disconnected_at", 0L),
            "ttsReady" to (if (Speaker.initDone) Speaker.ready else null),
            "ttsLanguageOk" to Speaker.languageOk,
            "pending" to events(context).let { list -> (0 until list.length()).count { !list.getJSONObject(it).has("server_id") } },
            "audio" to audioRoute(context),
            "maker" to (Build.MANUFACTURER ?: "").lowercase(Locale.ROOT),
            "batteryUnrestricted" to batteryUnrestricted(context, context.packageName),
            "notificationsEnabled" to NotificationManagerCompat.from(context).areNotificationsEnabled(),
        )
    }

    /** True when Android will not put this package to sleep (battery "Unrestricted" / not optimised). */
    fun batteryUnrestricted(context: Context, pkg: String): Boolean = try {
        Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
            (context.getSystemService(Context.POWER_SERVICE) as PowerManager).isIgnoringBatteryOptimizations(pkg)
    } catch (_: Exception) {
        false
    }

    /**
     * The setup flow's view of the allowed payment apps on this phone: installed?, battery unrestricted?, and when
     * the listener last saw ANY notification from it (proof its notifications reach this phone). Only package
     * names and times -- never notification content.
     */
    private fun paymentApps(context: Context, packages: List<String>): List<Map<String, Any?>> =
        packages.take(20).map { pkg ->
            val installed = try {
                context.packageManager.getPackageInfo(pkg, 0)
                true
            } catch (_: Exception) {
                false
            }
            mapOf(
                "package" to pkg,
                "installed" to installed,
                "batteryUnrestricted" to (installed && batteryUnrestricted(context, pkg)),
                "lastSeenAt" to prefs(context).getLong("seen:$pkg", 0L),
            )
        }

    private fun appNotificationSettings(context: Context, pkg: String): Intent {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, pkg)
        } else {
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$pkg"))
        }
        if (context.packageManager.resolveActivity(intent, 0) == null) {
            return Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$pkg"))
        }
        return intent
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
    fun events(context: Context): JSONArray {
        val list = try { JSONArray(prefs(context).getString("events", "[]") ?: "[]") } catch (_: Exception) { JSONArray() }
        // Owner 2026-11-20: a payment never shows "Speaking..." for ever -- older than 2 minutes = the voice got stuck.
        val now = System.currentTimeMillis()
        for (i in 0 until list.length()) {
            val e = list.optJSONObject(i) ?: continue
            if (e.optString("spoken") == "pending" && now - e.optLong("at_ms", now) > 120_000L) e.put("spoken", "stuck")
        }
        return list
    }

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
            if (serverId != null) { e.put("server_id", serverId); e.remove("upload_note") }
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

    /** Owner 2026-11-15: every history row can be deleted. null / empty list = clear all rows on this phone. */
    @Synchronized
    private fun deleteEvents(context: Context, ids: List<String>?): Int {
        val list = events(context)
        val keep = JSONArray()
        var removed = 0
        for (i in 0 until list.length()) {
            val e = list.getJSONObject(i)
            if (ids.isNullOrEmpty() || ids.contains(e.optString("local_id"))) removed++ else keep.put(e)
        }
        saveEvents(context, keep)
        return removed
    }

    /** Launchable apps on this phone (label + package id only) so the person can choose which apps to read. */
    private fun installedApps(context: Context): List<Map<String, String>> = try {
        val pm = context.packageManager
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        pm.queryIntentActivities(intent, 0)
            .map { it.activityInfo.packageName to it.loadLabel(pm).toString() }
            .filter { it.first != context.packageName }
            .distinctBy { it.first }
            .sortedBy { it.second.lowercase(Locale.ROOT) }
            .map { mapOf("package" to it.first, "label" to it.second) }
    } catch (_: Exception) {
        emptyList()
    }

    /**
     * Speak an alert another device (or the bank / provider) reported -- from the open screen's poll or
     * from a high-priority push while ASKODOX is closed. Each event is spoken once on this phone, whichever
     * path comes first. Returns spoken | duplicate | quiet_hours | muted | not_set_up.
     */
    fun speakRemote(context: Context, eventId: String, text: String, language: String, businessId: String?,
                    fromPush: Boolean, onFinished: (() -> Unit)?): String {
        val cfg = config(context)
        fun done(state: String): String { onFinished?.invoke(); return state }
        if (eventId.isEmpty() || text.isBlank()) return done("not_set_up")
        // A phone that never opened payment alerts (no shop, not enabled, no device id for this shop) stays silent.
        val knownShop = !businessId.isNullOrEmpty() && cfg.optJSONObject("device_ids")?.has(businessId) == true
        if (cfg.optString("business_id").isEmpty() && !cfg.optBoolean("enabled", false) && !knownShop) return done("not_set_up")
        if (!cfg.optBoolean("speaks_remote", true)) return done("muted")
        val cal = Calendar.getInstance()
        if (PaymentAlertParser.inQuietHours(cfg.optString("quiet_start"), cfg.optString("quiet_end"),
                cal.get(Calendar.HOUR_OF_DAY) * 60 + cal.get(Calendar.MINUTE))) {
            if (fromPush && businessId != null) ack(context, businessId, eventId, "quiet_hours")
            return done("quiet_hours")
        }
        if (!firstTime(context, "remote|$eventId", System.currentTimeMillis())) return done("duplicate")
        if (!claimVoice(context, amountFromText(text), System.currentTimeMillis(), "remote")) {
            // This phone already announced this money from its own notification: stay silent, and say so honestly.
            if (fromPush && businessId != null) ack(context, businessId, eventId, "duplicate_local")
            return done("duplicate")
        }
        CloudVoice.lastStuck = false
        CloudVoice.say(context, listOf(text), language, cfg) { ok ->
            val state = if (ok) "announced" else if (CloudVoice.lastStuck) "stuck" else "tts_failed"
            if (fromPush && businessId != null) ack(context, businessId, eventId, state)
            main.post { channel?.invokeMethod("paymentEvent", "{}") }
            onFinished?.invoke()
        }
        return "spoken"
    }

    /**
     * Owner 2026-11-15: ONE payment must not be heard twice. The phone's own notification reading and the
     * bank / other-device push can both announce the same money (the push often arrives first). Whichever path
     * speaks first records the amount; the OTHER path stays silent for 2 minutes. Two payments of the same amount
     * through the same path (two notifications from the phone) are two payments and are both spoken.
     * Returns true when this path may speak.
     */
    @Synchronized
    private fun claimVoice(context: Context, amountPaise: Long?, now: Long, path: String): Boolean {
        if (amountPaise == null || amountPaise <= 0) return true
        val p = prefs(context)
        val lastAmount = p.getLong("voice_amount", -1L)
        val lastAt = p.getLong("voice_at", 0L)
        val lastPath = p.getString("voice_path", "") ?: ""
        if (lastAmount == amountPaise && lastPath != path && now - lastAt in 0..120_000L) return false
        p.edit().putLong("voice_amount", amountPaise).putLong("voice_at", now).putString("voice_path", path).apply()
        return true
    }

    /** The amount a spoken alert text states ("... 640 ..."), in paise; null when it has no number. */
    private fun amountFromText(text: String): Long? =
        Regex("""\d[\d,]*(?:\.\d{1,2})?""").find(text)?.value?.replace(",", "")?.toDoubleOrNull()?.let { Math.round(it * 100) }

    /** Best-effort acknowledgement from the phone itself (push path, app closed). */
    /** The last resort when no voice could play: two loud beeps on the ALARM sound (heard even when media is low). */
    fun beep(context: Context) {
        try {
            val tone = android.media.ToneGenerator(AudioManager.STREAM_ALARM, 100)
            tone.startTone(android.media.ToneGenerator.TONE_CDMA_ALERT_CALL_GUARD, 700)
            main.postDelayed({ try { tone.startTone(android.media.ToneGenerator.TONE_CDMA_ALERT_CALL_GUARD, 700) } catch (_: Exception) {} }, 900)
            main.postDelayed({ try { tone.release() } catch (_: Exception) {} }, 2_200)
        } catch (_: Exception) {
        }
    }

    fun ack(context: Context, businessId: String, eventId: String, state: String) {
        io.execute {
            try {
                val cfg = config(context)
                val base = cfg.optString("base_url").trimEnd('/')
                val token = cfg.optString("token")
                val device = cfg.optJSONObject("device_ids")?.optString(businessId)?.takeIf { it.isNotEmpty() }
                    ?: (if (cfg.optString("business_id") == businessId) cfg.optString("device_id") else "")
                if (base.isEmpty() || token.isEmpty() || device.isEmpty()) return@execute
                val conn = URL("$base/api/pos/businesses/$businessId/payment-alerts/events/$eventId/ack")
                    .openConnection() as HttpURLConnection
                conn.requestMethod = "POST"
                conn.connectTimeout = 10000
                conn.readTimeout = 10000
                conn.doOutput = true
                conn.setRequestProperty("Content-Type", "application/json")
                conn.setRequestProperty("Authorization", "Bearer $token")
                conn.outputStream.use {
                    it.write(JSONObject().put("device_id", device).put("state", state).put("detail", Player.lastDetail)
                        .toString().toByteArray(Charsets.UTF_8))
                }
                conn.responseCode
                conn.disconnect()
            } catch (_: Exception) {
            }
        }
    }

    // ------------------------------------------------------- learned wording
    private fun strings(a: JSONArray?): List<String> =
        if (a == null) emptyList() else (0 until a.length()).mapNotNull { a.optString(it).takeIf { s -> s.isNotBlank() } }

    fun learned(context: Context, key: String): List<String> =
        try { strings(JSONArray(prefs(context).getString(key, "[]") ?: "[]")) } catch (_: Exception) { emptyList() }

    fun unknowns(context: Context): JSONArray =
        try { JSONArray(prefs(context).getString("unknown", "[]") ?: "[]") } catch (_: Exception) { JSONArray() }

    /** A payment-app message with one amount whose wording we do not know yet: kept ON THIS PHONE (max 20) for
     * the person to answer "did you receive this?". Only the shape (amount as ₹#) + amount + app + time. */
    @Synchronized
    private fun rememberUnknown(context: Context, pkg: String, u: PaymentAlertParser.Result.Unknown) {
        val list = unknowns(context)
        for (i in 0 until list.length()) if (list.getJSONObject(i).optString("template") == u.template) return
        val now = System.currentTimeMillis()
        list.put(JSONObject().put("id", "u-$now").put("package", pkg).put("template", u.template)
            .put("amount_paise", u.amountPaise).put("at", isoUtc(now)))
        val trimmed = JSONArray()
        for (i in maxOf(0, list.length() - 20) until list.length()) trimmed.put(list.getJSONObject(i))
        prefs(context).edit().putString("unknown", trimmed.toString()).apply()
        main.post { channel?.invokeMethod("paymentEvent", "{}") }
    }

    /** The person's answer: received -> this wording speaks from now on; sent -> it is ignored from now on. */
    @Synchronized
    private fun learnUnknown(context: Context, id: String, received: Boolean): Map<String, Any?> {
        val list = unknowns(context)
        val keep = JSONArray()
        var template = ""
        for (i in 0 until list.length()) {
            val item = list.getJSONObject(i)
            if (item.optString("id") == id) template = item.optString("template") else keep.put(item)
        }
        if (template.isEmpty()) return mapOf("ok" to false)
        val key = if (received) "learned_in" else "learned_out"
        val learned = learned(context, key).filter { it != template }.takeLast(49) + template
        prefs(context).edit().putString("unknown", keep.toString()).putString(key, JSONArray(learned).toString()).apply()
        return mapOf("ok" to true, "template" to template, "received" to received)
    }

    // -------------------------------------------------------------- pipeline
    /** Returns a small map describing what happened (for tests / the simulate button). */
    fun handle(context: Context, pkg: String, title: String?, text: String?, notificationKey: String, whenMillis: Long,
               test: Boolean = false, cfgIn: JSONObject? = null, messageTime: Long = 0L): Map<String, Any?> {
        val cfg = cfgIn ?: config(context)
        if (!test && !cfg.optBoolean("enabled", false)) return mapOf("result" to "disabled")
        // Owner 2026-11-17: a bill / EMI REMINDER ("₹1,941 due on Nov 21") on the person's own phone -> an upcoming due
        // offered in "Upcoming payments" (never spoken, never a payment, never uploaded).
        if (!test && cfg.optString("business_id").isEmpty()) {
            PaymentAlertParser.dueReminder(title, text)?.let { d ->
                val saved = saveDue(context, cfg, pkg, d)
                // Owner 2026-11-22 ("bill generated etc. too"): the bill that CAME is also shown in the person's history
                // with its last date (a note: never counted, never spoken) -- not only offered in Upcoming payments.
                if (saved["result"] == "due") {
                    saveNotice(context, cfg, pkg, PaymentAlertParser.Notice("bill", d.amountPaise), title, text, notificationKey,
                        whenMillis, dueDate = d.dueDate, label = d.label)
                }
                return saved
            }
        }
        // TRAI: a sender id ending in -P is an advertisement -- never a payment or a notice.
        if (PaymentAlertParser.isPromoSender(title)) return mapOf("result" to "ignored")
        val phrases = cfg.optJSONObject("phrases")
        val parsed = PaymentAlertParser.parse(title, text, strings(phrases?.optJSONArray("incoming")),
            strings(phrases?.optJSONArray("reject")), learned(context, "learned_in"), learned(context, "learned_out"),
            learnedKinds(context))
        if (parsed is PaymentAlertParser.Result.Unknown) {
            if (!test) rememberUnknown(context, pkg, parsed)
            return mapOf("result" to "unknown", "template" to parsed.template)
        }
        if (parsed is PaymentAlertParser.Result.Ignored) {
            // Owner 2026-11-21: refund started / payment initiated / failed / bill generated / suspicious link -- explained
            // in the person's own history (why it came, what to check), never spoken, never counted.
            // Owner 2026-11-22: each kind is also SAID when the person keeps it on in the Payment voice folder.
            if (!test && cfg.optString("business_id").isEmpty()) {
                PaymentAlertParser.notice(title, text)?.let { n -> return saveNotice(context, cfg, pkg, n, title, text, notificationKey, whenMillis) }
            } else if (!test) {
                // A shop phone: only the warnings (someone asking the shop to pay, a fake "credited" message) -- said, not kept.
                PaymentAlertParser.notice(title, text)?.takeIf { it.kind == "request" || it.kind == "suspect" }?.let { n ->
                    val key = "$pkg|shopnotice|${n.kind}|${n.amountPaise ?: 0}|$notificationKey"
                    val said = firstTime(context, key, System.currentTimeMillis()) && speakNotice(context, cfg, n, null, whenMillis)
                    return mapOf("result" to "notice", "kind" to n.kind, "spoken" to said)
                }
            }
            return mapOf("result" to "ignored")
        }
        // Owner 2026-11-15: a normal person's own phone (no shop) keeps credits AND debits of any app / bank SMS they chose.
        val personal = cfg.optString("business_id").isEmpty()
        if (parsed is PaymentAlertParser.Result.Outgoing) {
            if (!personal) return mapOf("result" to "ignored") // a shop only cares about money coming in
            return handleOutgoing(context, cfg, pkg, parsed, notificationKey, whenMillis, test, messageTime, text, title)
        }
        val amount = (parsed as? PaymentAlertParser.Result.Accepted)?.amountPaise
        val reference = (parsed as? PaymentAlertParser.Result.Accepted)?.reference
        // Spoken in the thank-you only; never put in the event, the log or the upload.
        val payer = (parsed as? PaymentAlertParser.Result.Accepted)?.payer
        val account = (parsed as? PaymentAlertParser.Result.Accepted)?.account
        // Owner 2026-11-17 (Rs 1,000 twice at 09:55): an app RE-POSTS its own notification with a new time. The message's
        // own time (chat-style notifications) is the identity; without it, the same notification + amount within 3 min.
        val identity = if (messageTime > 0) messageTime else whenMillis
        val key = if (reference != null) "$pkg|ref|$reference" else "$pkg|$notificationKey|${amount ?: 0}|$identity"
        val now = System.currentTimeMillis()
        if (!firstTime(context, key, now)) return mapOf("result" to "duplicate")
        if (!test && reference == null && messageTime <= 0 && amount != null &&
            repostOf(context, pkg, notificationKey, "in", amount, paymentTime(whenMillis, now))) return mapOf("result" to "duplicate")
        // Owner 2026-11-16 (double sound): a UPI app's notification sometimes reaches the phone MINUTES after its SMS. The
        // payment's own time (the notification's `when`) decides whether two messages are one payment, not the arrival time.
        val posted = paymentTime(whenMillis, now)
        // Owner 2026-11-17: a bank SMS from a REGISTERED sender (XX-HDFCBK-S / -T / -G) = the bank says the money landed.
        val bankSms = kindOf(cfg, pkg) == "sms" && PaymentAlertParser.isBankSender(title)
        val handle = PaymentAlertParser.upiHandleTail("${title ?: ""} ${text ?: ""}")
        val balance = if (kindOf(cfg, pkg) == "sms") PaymentAlertParser.availableBalance(text) else null
        // Owner 2026-11-19: "money received" SMS from a PERSON's mobile number = a likely fake. Written with a warning,
        // never spoken, never joined to a real payment, never sent to the shop's other phones.
        if (!test && amount != null && kindOf(cfg, pkg) == "sms" && PaymentAlertParser.looksLikePersonNumber(title)) {
            val fakeId = "pa-$now-${(Math.random() * 1e6).toInt()}"
            val fake = JSONObject()
                .put("local_id", fakeId)
                .put("client_event_id", key.take(110).replace(Regex("[^A-Za-z0-9_.:|-]"), "_"))
                .put("source_app", pkg)
                .put("source_label", "SMS ${title?.trim()?.takeLast(4) ?: ""}")
                .put("detected_at", isoUtc(now))
                .put("at_ms", posted)
                .put("kind", "sms")
                .put("status", "suspect_sender")
                .put("spoken", "suspect")
                .put("amount_paise", amount)
                .put("test", false)
            if (personal) fake.put("direction", "in")
            synchronized(this) { val list = events(context); list.put(fake); saveEvents(context, list) }
            main.post { channel?.invokeMethod("paymentEvent", fake.toString()) }
            // Owner 2026-11-22: never "received" -- the phone says it looks fake (always on).
            val warned = speakNotice(context, cfg, PaymentAlertParser.Notice("suspect", amount), null, whenMillis)
            return mapOf("result" to "suspect", "localId" to fakeId, "amountPaise" to amount, "spoken" to false, "warned" to warned)
        }
        // Owner 2026-11-21 (Rs 3,000 received, PhonePe row said minus): the bank's own SMS is the truth. An opposite
        // row of the SAME amount from an app notification within 10 minutes is set aside (❓, not counted, not spoken).
        if (!test && amount != null && personal && bankSms) setAsideOpposite(context, pkg, "in", amount, posted)
        val bankDisagrees = !test && amount != null && personal && !bankSms && bankSaysOpposite(context, pkg, "in", amount, posted)
        if (!test && amount != null && !bankDisagrees) {
            mergeSameMoney(context, cfg, pkg, "in", amount, account, reference, payer, posted, bankSms, handle, notificationKey,
                balance, raw = rawOf(title, text))?.let {
                return mapOf("result" to "merged", "localId" to it, "amountPaise" to amount, "spoken" to false)
            }
        }
        val localId = "pa-$now-${(Math.random() * 1e6).toInt()}"
        val labels = cfg.optJSONObject("apps")
        val event = JSONObject()
            .put("local_id", localId)
            .put("client_event_id", key.take(110).replace(Regex("[^A-Za-z0-9_.:|-]"), "_"))
            .put("source_app", pkg)
            .put("notification_key", notificationKey.take(120))
            .put("source_label", if (pkg == "askodox.test") "ASKODOX test" else labels?.optString(pkg, pkg) ?: pkg)
            .put("detected_at", isoUtc(now))
            .put("at_ms", posted)
            .put("seen_after_ms", now - posted)
            .put("kind", kindOf(cfg, pkg))
            .put("status", if (amount != null) "notification_unverified" else "ambiguous")
            .put("test", test)
        if (bankSms) event.put("bank_confirmed", true).put("bank_sms_from", title?.trim()?.take(20) ?: "")
        putRaw(event, title, text) // this phone only; never uploaded (the row's "what we read")
        if (bankDisagrees) event.put("excluded", true).put("doubt", "bank_opposite")
        if (balance != null) event.put("balance_paise", balance) // this phone only; never uploaded
        if (handle != null) event.put("upi_handle", handle) // this phone only; never uploaded
        if (amount != null) event.put("amount_paise", amount)
        if (reference != null) event.put("reference", reference)
        val refund = (parsed as? PaymentAlertParser.Result.Accepted)?.refund == true
        val bonus = (parsed as? PaymentAlertParser.Result.Accepted)?.bonus
        if (refund) event.put("note", "refund")
        if (bonus != null) event.put("note", bonus) // "cashback" / "interest" (owner 2026-11-22)
        if (personal) {
            event.put("direction", "in")
            if (account != null) event.put("account", account)
            if (!payer.isNullOrEmpty()) event.put("party", payer) // this phone only; never uploaded
        }
        if (parsed is PaymentAlertParser.Result.Ambiguous) event.put("reason", parsed.reason)
        val cal = Calendar.getInstance()
        val quiet = PaymentAlertParser.inQuietHours(cfg.optString("quiet_start"), cfg.optString("quiet_end"),
            cal.get(Calendar.HOUR_OF_DAY) * 60 + cal.get(Calendar.MINUTE))
        // A payment that happened long before the phone saw it (phone asleep, app stopped by the battery saver) is
        // written in the history but NOT spoken: a voice minutes later sounds like a second, new payment.
        val late = !test && now - posted > LATE_MS
        // Owner 2026-11-18: a payment message with NO amount is written in the history, never spoken ("amount not
        // clear" only confused people -- e.g. PhonePe UPI Circle notifications).
        val unclear = (amount == null || bankDisagrees) && !test
        // Owner 2026-11-22 (Payment voice folder): the person may switch a kind off (received / refund / cashback).
        val muted = !test && !voiceOn(context, cfg, if (refund) "refund" else if (bonus != null) "cashback" else "in")
        val mayVoice = !unclear && !muted && (quiet || test || late || claimVoice(context, amount, now, "local"))
        // Owner 2026-11-17: whichever message comes FIRST (SMS or notification) speaks at once -- no waiting for a name.
        event.put("spoken", if (bankDisagrees) "skipped_bank" else if (unclear) "seen" else if (muted) "muted" else if (quiet) "quiet_hours" else if (late) "late" else if (!mayVoice) "announced" else "pending")
        synchronized(this) { val list = events(context); list.put(event); saveEvents(context, list) }
        if (!unclear && !muted && !quiet && !late && mayVoice) speak(context, amount, test, localId, payer, cfg, if (personal) account else null, bonus)
        main.post { channel?.invokeMethod("paymentEvent", event.toString()) }
        if (!test && !personal) { upload(context, localId); retryPending(context, localId) }
        return mapOf("result" to if (amount != null) "accepted" else "ambiguous", "localId" to localId,
            "amountPaise" to amount, "spoken" to (!unclear && !muted && !quiet && !late && mayVoice))
    }

    /** A message whose own payment time is older than this (phone was off / asleep) is written, never spoken. */
    private const val LATE_MS = 60 * 60_000L

    /** How long a debit from an APP notification waits for the bank's SMS before it is spoken (owner 2026-11-21). */
    private const val DEBIT_WAIT_MS = 60_000L

    /** An app row and the bank's opposite SMS of the same amount within this time = one payment, read wrongly by the app. */
    private const val BANK_OPPOSITE_MS = 10 * 60_000L

    /** The message as the phone saw it (title + text), kept ON THIS PHONE only so the person can see what was read. */
    private fun rawOf(title: String?, text: String?): String =
        listOfNotNull(title?.trim()?.takeIf { it.isNotEmpty() }, text?.trim()?.takeIf { it.isNotEmpty() })
            .joinToString("\n").take(600)

    private fun putRaw(event: JSONObject, title: String?, text: String?) {
        if (!title.isNullOrBlank()) event.put("raw_title", title.trim().take(120))
        if (!text.isNullOrBlank()) event.put("raw_text", text.trim().take(600))
    }

    private fun eventById(context: Context, localId: String): JSONObject? {
        val list = events(context)
        for (i in 0 until list.length()) if (list.getJSONObject(i).optString("local_id") == localId) return list.getJSONObject(i)
        return null
    }

    /**
     * The bank's SMS says [direction] for [amount]: any APP-notification row of the same amount in the OTHER direction
     * within 10 minutes is the same money read wrongly -- set aside (❓, not counted; a debit still waiting is not spoken).
     */
    @Synchronized
    private fun setAsideOpposite(context: Context, pkg: String, direction: String, amount: Long, now: Long) {
        val list = events(context)
        var changed = false
        for (i in 0 until list.length()) {
            val e = list.getJSONObject(i)
            if (e.optBoolean("test") || e.optBoolean("bank_confirmed") || e.optString("source_app") == pkg) continue
            val dir = e.optString("direction")
            if (dir.isEmpty() || dir == "due" || dir == direction || e.optLong("amount_paise", -1L) != amount) continue
            if (kotlin.math.abs(now - e.optLong("at_ms", 0L)) > BANK_OPPOSITE_MS || e.optBoolean("excluded")) continue
            e.put("excluded", true).put("doubt", "bank_opposite")
            if (e.optString("spoken") == "waiting") e.put("spoken", "skipped_bank")
            changed = true
        }
        if (changed) {
            saveEvents(context, list)
            main.post { channel?.invokeMethod("paymentEvent", "{}") }
        }
    }

    /** True when the bank's own SMS already said the OTHER direction for the same amount within 10 minutes. */
    private fun bankSaysOpposite(context: Context, pkg: String, direction: String, amount: Long, now: Long): Boolean {
        val list = events(context)
        for (i in 0 until list.length()) {
            val e = list.getJSONObject(i)
            if (e.optBoolean("test") || !e.optBoolean("bank_confirmed") || e.optString("source_app") == pkg) continue
            val dir = e.optString("direction")
            if (dir.isEmpty() || dir == "due" || dir == direction || e.optLong("amount_paise", -1L) != amount) continue
            if (kotlin.math.abs(now - e.optLong("at_ms", 0L)) <= BANK_OPPOSITE_MS) return true
        }
        return false
    }

    /** The person's corrections: message kind (see [PaymentAlertParser.skeleton]) -> "in" | "out" | "none". */
    fun learnedKinds(context: Context): Map<String, String> = try {
        val o = JSONObject(prefs(context).getString("learned_kinds", "{}") ?: "{}")
        o.keys().asSequence().associateWith { o.optString(it) }
    } catch (_: Exception) { emptyMap() }

    /**
     * Owner 2026-11-21: "wrong" on a history row -- "this came in" / "this went out" / "not a payment". The row is fixed
     * at once, and when the message it was read from is still on the row, that KIND of message (any person, any
     * amount) is read the same way from now on. Nothing leaves the phone.
     */
    @Synchronized
    private fun correctEvent(context: Context, localId: String, choice: String): Map<String, Any?> {
        if (choice !in setOf("in", "out", "none")) return mapOf("ok" to false)
        val list = events(context)
        var row: JSONObject? = null
        for (i in 0 until list.length()) if (list.getJSONObject(i).optString("local_id") == localId) row = list.getJSONObject(i)
        val e = row ?: return mapOf("ok" to false)
        when (choice) {
            "none" -> e.put("excluded", true).put("doubt", "not_payment")
            else -> {
                if (e.has("direction")) e.put("direction", choice)
                e.remove("excluded"); e.remove("doubt")
            }
        }
        e.put("corrected", choice)
        if (e.optString("spoken") == "waiting") e.put("spoken", "skipped_bank")
        saveEvents(context, list)
        var learned = false
        val body = e.optString("raw_text")
        val sk = PaymentAlertParser.skeleton(body)
        if (body.isNotEmpty() && sk.split(' ').size >= 3) {
            val kinds = try { JSONObject(prefs(context).getString("learned_kinds", "{}") ?: "{}") } catch (_: Exception) { JSONObject() }
            kinds.put(sk, choice)
            while (kinds.length() > 60) kinds.remove(kinds.keys().next())
            prefs(context).edit().putString("learned_kinds", kinds.toString()).apply()
            learned = true
        }
        main.post { channel?.invokeMethod("paymentEvent", "{}") }
        return mapOf("ok" to true, "learned" to learned)
    }



    /** The payment's own time: the notification's `when` when it is sane (not in the future, not days old), else now. */
    private fun paymentTime(whenMillis: Long, now: Long): Long =
        if (whenMillis in (now - 2 * 24 * 3600 * 1000L)..(now + 5_000L)) minOf(whenMillis, now) else now

    /**
     * Owner 2026-11-15 / 2026-11-17 ("one payment = one voice, one row"): the SAME money reaches the phone as the bank's
     * SMS AND the UPI app's / bank app's notification -- sometimes many minutes apart. The FIRST one was spoken; this one
     * joins that row SILENTLY (name / account / reference fill the gaps, a bank SMS marks it bank-confirmed).
     * Same payment =
     *  - the same UPI / transaction reference on both (any time within a day), or
     *  - the same amount and direction from a DIFFERENT kind of source (sms / upi / bank) that the row does not have yet,
     *    within the window (notification up to an hour after the SMS; an SMS within 10 minutes of the notification),
     *    and no two different references / payer handles.
     * Two SMS never join, two messages from the same app never join: two real payments of the same amount stay two.
     * The OLDEST waiting row wins (a late notification belongs to the earlier payment). Returns the row or null.
     */
    @Synchronized
    private fun mergeSameMoney(context: Context, cfg: JSONObject, pkg: String, direction: String, amount: Long,
                               account: String?, reference: String?, party: String?, now: Long,
                               bankSms: Boolean = false, handle: String? = null, notificationKey: String? = null,
                               balance: Long? = null, emi: Boolean = false, raw: String? = null,
                               asKind: String? = null): String? {
        // [now] = THIS message's payment time; rows keep theirs in at_ms.
        val kind = asKind ?: kindOf(cfg, pkg)
        val list = events(context)
        var hit: JSONObject? = null
        for (i in 0 until list.length()) {
            val e = list.getJSONObject(i)
            val at = e.optLong("at_ms", 0L)
            if (at <= 0L || e.optBoolean("test")) continue
            // Two messages from the same app never join -- except a company's "thank you for your payment" SMS, the bank's
            // own "Bill Paid" SMS and the bank's debit SMS, which all come through the SMS app (kinds "biller" /
            // "billpay" vs "sms"; two of the same kind still never join).
            if (e.optString("source_app") == pkg && kind !in SIDE_KINDS && e.optString("kind") !in SIDE_KINDS) continue
            if ((e.optString("direction").ifEmpty { "in" }) != direction) continue
            // A row set aside (❓) joins only the bank's own SMS that agrees with it (then it counts again).
            if (e.optBoolean("excluded") && !bankSms) continue
            // ONE common key (owner 2026-11-17): the UPI RRN both messages carry. Same RRN = same money, any order,
            // any gap within a day. Two different full RRNs = two payments. An app's own id vs the bank's RRN says
            // nothing: amount + account + time + source decide below.
            when (PaymentAlertParser.compareRefs(e.optString("reference"), reference)) {
                PaymentAlertParser.RefMatch.SAME -> if (kotlin.math.abs(now - at) <= 24 * 3600_000L) { hit = e; break }
                PaymentAlertParser.RefMatch.DIFFERENT -> continue
                PaymentAlertParser.RefMatch.UNKNOWN -> {}
            }
            if (e.optLong("amount_paise", -1L) != amount) continue
            if (PaymentAlertParser.accountsDiffer(e.optString("account"), account)) continue
            val other = e.optString("upi_handle")
            if (handle != null && other.isNotEmpty() && other != handle) continue
            val kinds = (e.optJSONArray("merged_kinds") ?: JSONArray().put(e.optString("kind"))).let { a ->
                (0 until a.length()).map { a.optString(it) }
            }
            if (kind in kinds) continue
            if (PaymentAlertParser.samePaymentWindow(kind, kinds, now - at)) { hit = e; break }
        }
        val e = hit ?: return null
        val kinds = (e.optJSONArray("merged_kinds") ?: JSONArray().put(e.optString("kind"))).let { a ->
            (0 until a.length()).map { a.optString(it) }
        }
        val label = cfg.optJSONObject("apps")?.optString(pkg, pkg) ?: pkg
        if (kind !in kinds) e.put("merged_kinds", JSONArray(kinds + kind))
        e.put("also_from", listOfNotNull(e.optString("also_from").takeIf { it.isNotEmpty() }, label).joinToString(", "))
        if (account != null && !e.has("account")) e.put("account", account)
        if (reference != null && !e.has("reference")) e.put("reference", reference)
        if (handle != null && !e.has("upi_handle")) e.put("upi_handle", handle)
        if (!party.isNullOrEmpty() && !e.has("party") && e.has("direction")) e.put("party", party)
        if (bankSms) {
            e.put("bank_confirmed", true)
            if (e.optBoolean("excluded")) { e.remove("excluded"); e.remove("doubt") }
        }
        if (balance != null) e.put("balance_paise", balance)
        if (emi) e.put("emi", true)
        if (!raw.isNullOrEmpty()) {
            val also = e.optJSONArray("raw_also") ?: JSONArray()
            if (also.length() < 3) also.put(raw)
            e.put("raw_also", also)
        }
        if (notificationKey != null) {
            val keys = e.optJSONArray("merged_keys") ?: JSONArray()
            keys.put("$pkg|${notificationKey.take(120)}")
            e.put("merged_keys", keys)
        }
        saveEvents(context, list)
        main.post { channel?.invokeMethod("paymentEvent", e.toString()) }
        return e.optString("local_id")
    }

    /** Personal phone: a debit is kept in the history; it is SPOKEN only when the person turned debit alerts on. */
    private fun handleOutgoing(context: Context, cfg: JSONObject, pkg: String, o: PaymentAlertParser.Result.Outgoing,
                               notificationKey: String, whenMillis: Long, test: Boolean, messageTime: Long = 0L,
                               text: String? = null, title: String? = null): Map<String, Any?> {
        val balance = if (kindOf(cfg, pkg) == "sms") PaymentAlertParser.availableBalance(text) else null
        val emi = PaymentAlertParser.isEmi(text)
        val now = System.currentTimeMillis()
        val key = "$pkg|out|$notificationKey|${o.amountPaise}|${if (messageTime > 0) messageTime else whenMillis}"
        if (!firstTime(context, key, now)) return mapOf("result" to "duplicate")
        if (!test && messageTime <= 0 && repostOf(context, pkg, notificationKey, "out", o.amountPaise, paymentTime(whenMillis, now)))
            return mapOf("result" to "duplicate")
        val posted = paymentTime(whenMillis, now)
        // A company's "thank you for your payment" (Airtel, Jio, electricity ...) is the SAME money as the bank's debit
        // SMS / the UPI app's message: kind "biller" so it joins them (two SMS never join) and it is never the bank's word.
        // Owner 2026-11-22 (HDFC "Bill Paid! ... from HDFC Bank Account XX1234"): the bank's OWN message that a bill /
        // service was paid from the person's account is kind "billpay" -- the bank's word (confirmed), and the same money
        // as its debit SMS and the company's thank-you. A paid-bill SMS that names no account of the person (the
        // company's or an app's word) is "biller".
        val source = kindOf(cfg, pkg)
        val kind = when {
            o.biller -> "biller"
            o.bill && source == "sms" && o.ownAccount -> "billpay"
            o.bill && source == "sms" -> "biller"
            else -> source
        }
        val bankSms = source == "sms" && (kind == "sms" || kind == "billpay") && PaymentAlertParser.isBankSender(title)
        // Bank SMS wins (owner 2026-11-21): see the incoming side in [handle].
        if (!test && bankSms) setAsideOpposite(context, pkg, "out", o.amountPaise, posted)
        val bankDisagrees = !test && !bankSms && bankSaysOpposite(context, pkg, "out", o.amountPaise, posted)
        if (!test && !bankDisagrees) {
            mergeSameMoney(context, cfg, pkg, "out", o.amountPaise, o.account, null, o.party, posted, bankSms = bankSms,
                notificationKey = notificationKey, balance = balance, emi = emi, raw = rawOf(title, text), asKind = kind)?.let {
                return mapOf("result" to "merged", "localId" to it, "amountPaise" to o.amountPaise, "spoken" to false)
            }
        }
        val localId = "pa-$now-${(Math.random() * 1e6).toInt()}"
        val labels = cfg.optJSONObject("apps")
        val event = JSONObject()
            .put("local_id", localId)
            .put("client_event_id", key.take(110).replace(Regex("[^A-Za-z0-9_.:|-]"), "_"))
            .put("source_app", pkg)
            .put("notification_key", notificationKey.take(120))
            .put("source_label", if (pkg == "askodox.test") "ASKODOX test" else labels?.optString(pkg, pkg) ?: pkg)
            .put("detected_at", isoUtc(now))
            .put("status", "notification_unverified")
            .put("direction", "out")
            .put("at_ms", posted)
            .put("kind", kind)
            .put("amount_paise", o.amountPaise)
            .put("test", test)
        if (o.account != null) event.put("account", o.account)
        if (!o.party.isNullOrEmpty()) event.put("party", o.party)
        if (balance != null) event.put("balance_paise", balance)
        if (emi) event.put("emi", true)
        if (o.bill) event.put("bill", true)
        if (bankSms) event.put("bank_confirmed", true).put("bank_sms_from", title?.trim()?.take(20) ?: "")
        putRaw(event, title, text)
        if (bankDisagrees) event.put("excluded", true).put("doubt", "bank_opposite")
        else if (o.doubtful && !bankSms) event.put("doubt", "wording")
        val cal = Calendar.getInstance()
        val quiet = PaymentAlertParser.inQuietHours(cfg.optString("quiet_start"), cfg.optString("quiet_end"),
            cal.get(Calendar.HOUR_OF_DAY) * 60 + cal.get(Calendar.MINUTE))
        val late = now - posted > LATE_MS
        // Owner 2026-11-22 ("the 3rd one: when such ones come a sound should come"): a PAID bill / EMI / loan instalment
        // has its own switch (on unless the person turns it off); other debits keep the debit switch.
        val billPaid = o.bill || o.biller
        val say = voiceOn(context, cfg, if (billPaid) "bill" else "out") && !quiet && !late && !bankDisagrees
        // Owner 2026-11-21: a debit read from an APP notification waits ~60 s -- if the bank's SMS says the money came
        // IN, the row is set aside and nothing "went out" is spoken. The bank's own debit SMS speaks at once.
        val wait = say && !bankSms && !test
        event.put("spoken", if (bankDisagrees) "skipped_bank" else if (wait) "waiting" else if (say) "pending"
            else if (quiet) "quiet_hours" else if (late) "late" else "seen")
        synchronized(this) { val list = events(context); list.put(event); saveEvents(context, list) }
        if (say) {
            val language = cfg.optString("language", "te").ifEmpty { "te" }
            val name = if (cfg.optBoolean("say_name", true)) o.party else null
            val speakNow = {
                val row = eventById(context, localId)
                if (row == null || row.optBoolean("excluded") || row.optString("direction") != "out") {
                    if (row != null) update(context, localId) { it.put("spoken", "skipped_bank") }
                    main.post { channel?.invokeMethod("paymentEvent", "{}") }
                } else {
                    update(context, localId) { it.put("spoken", "pending") }
                    val parts = if (billPaid) PaymentAlertParser.billPaidParts(o.amountPaise, language, o.party, emi)
                        else withAccount(cfg, o.account, PaymentAlertParser.personalParts(o.amountPaise, language, false, name))
                    CloudVoice.say(context, parts, language, cfg) { ok ->
                        update(context, localId) { it.put("spoken", if (ok) "announced" else "tts_failed") }
                        main.post { channel?.invokeMethod("paymentEvent", "{}") }
                    }
                }
            }
            if (wait) main.postDelayed({ speakNow() }, DEBIT_WAIT_MS) else speakNow()
        }
        main.post { channel?.invokeMethod("paymentEvent", event.toString()) }
        return mapOf("result" to "outgoing", "localId" to localId, "amountPaise" to o.amountPaise, "spoken" to say)
    }

    /**
     * Owner 2026-11-17: "say which account" (My phone, optional): the person's OWN name for the account ("HDFC current")
     * is said first. Only when the message carried the account's last digits and the person named that account.
     */
    private fun withAccount(cfg: JSONObject, account: String?, parts: List<String>): List<String> {
        if (account.isNullOrEmpty() || !cfg.optBoolean("say_account", false)) return parts
        val name = cfg.optJSONObject("account_names")?.optString(account).orEmpty().trim()
        return if (name.isEmpty()) parts else listOf("$name:") + parts
    }

    /** Whole days since 1970 in the phone's own time zone (API 23 safe; no java.time). */
    private fun dayNumber(cal: Calendar): Long {
        val c = cal.clone() as Calendar
        val offset = c.get(Calendar.ZONE_OFFSET) + c.get(Calendar.DST_OFFSET)
        return (c.timeInMillis + offset) / 86_400_000L
    }

    /** A money message that is not a payment: one "info" row (not counted, not spoken). Suspicious ones also notify. */
    private fun saveNotice(context: Context, cfg: JSONObject, pkg: String, n: PaymentAlertParser.Notice, title: String?,
                           text: String?, notificationKey: String, whenMillis: Long, dueDate: String? = null,
                           label: String? = null): Map<String, Any?> {
        val now = System.currentTimeMillis()
        val key = "$pkg|notice|${n.kind}|${n.amountPaise ?: 0}|$notificationKey|${paymentTime(whenMillis, now) / 60_000L}"
        if (!firstTime(context, key, now)) return mapOf("result" to "duplicate")
        val localId = "info-$now-${(Math.random() * 1e6).toInt()}"
        val event = JSONObject()
            .put("local_id", localId)
            .put("direction", "info")
            .put("info", n.kind)
            .put("excluded", true)
            .put("source_app", pkg)
            .put("notification_key", notificationKey.take(120))
            .put("source_label", cfg.optJSONObject("apps")?.optString(pkg, pkg) ?: pkg)
            .put("detected_at", isoUtc(now))
            .put("at_ms", paymentTime(whenMillis, now))
            .put("kind", kindOf(cfg, pkg))
            .put("spoken", "none")
            .put("test", false)
        if (n.amountPaise != null) event.put("amount_paise", n.amountPaise)
        if (!dueDate.isNullOrEmpty()) event.put("due_date", dueDate)
        val party = label?.takeIf { it.isNotBlank() }
            ?: PaymentAlertParser.billerName(title)?.takeIf { !PaymentAlertParser.looksLikePersonNumber(title) }
        party?.let { event.put("party", it) }
        putRaw(event, title, text)
        // Owner 2026-11-22: said aloud when the person keeps this kind ON (Payment voice folder) -- never as "received".
        if (speakNotice(context, cfg, n, party, whenMillis)) event.put("spoken", "announced")
        synchronized(this) { val list = events(context); list.put(event); saveEvents(context, list) }
        if (n.kind == "suspect") {
            val te = cfg.optString("language", "te") == "te"
            showPaymentNotification(context, key, if (te) "⚠️ అనుమానాస్పద డబ్బు message" else "⚠️ Suspicious money message",
                if (te) "లింక్ నొక్కకండి. డబ్బు వచ్చిందో లేదో మీ బ్యాంక్ యాప్‌లోనే చూడండి." else "Do not tap any link. Check your bank app to see if money really came.")
        }
        main.post { channel?.invokeMethod("paymentEvent", event.toString()) }
        return mapOf("result" to "notice", "kind" to n.kind, "localId" to localId)
    }

    // ------------------------------------------------------------------ which kinds are SPOKEN (owner 2026-11-22)

    private fun voiceKindsKey(personal: Boolean) = if (personal) "voice_kinds_personal" else "voice_kinds_shop"

    /** The person's own on / off per kind ("in", "out", "bill", "refund", "cashback", "pending", "failed", "due",
     *  "autopay", "request"); a kind never set keeps its default. */
    fun voiceKinds(context: Context, personal: Boolean): JSONObject =
        try { JSONObject(prefs(context).getString(voiceKindsKey(personal), "{}") ?: "{}") } catch (_: Exception) { JSONObject() }

    /**
     * Whether this kind of message is said aloud. Defaults: everything on, except "out" (an ordinary debit), which keeps
     * the older "announce debits" setting. The fake-message warning ("fake") is always on.
     */
    fun voiceOn(context: Context, cfg: JSONObject, kind: String): Boolean {
        if (kind == "fake") return true
        val chosen = voiceKinds(context, cfg.optString("business_id").isEmpty())
        if (chosen.has(kind)) return chosen.optBoolean(kind, true)
        return if (kind == "out") cfg.optBoolean("announce_debits", false) else true
    }

    /**
     * A money message that is not a payment, SAID (never "received"): refund started / pending, failed / cancelled, a bill
     * that came, AutoPay set / stopped, someone asking for money, a fake message. Quiet hours and late messages stay silent.
     */
    private fun speakNotice(context: Context, cfg: JSONObject, n: PaymentAlertParser.Notice, party: String?, whenMillis: Long): Boolean {
        if (!voiceOn(context, cfg, PaymentAlertParser.voiceKindOf(n.kind))) return false
        val now = System.currentTimeMillis()
        if (now - paymentTime(whenMillis, now) > LATE_MS) return false
        val cal = Calendar.getInstance()
        if (PaymentAlertParser.inQuietHours(cfg.optString("quiet_start"), cfg.optString("quiet_end"),
                cal.get(Calendar.HOUR_OF_DAY) * 60 + cal.get(Calendar.MINUTE))) return false
        val language = cfg.optString("language", "te").ifEmpty { "te" }
        val parts = PaymentAlertParser.noticeParts(n.kind, n.amountPaise, language, party)
        if (parts.isEmpty()) return false
        CloudVoice.say(context, parts, language, cfg, null)
        return true
    }

    /** "▶ Listen" in the Payment voice folder: example words for one kind (made-up names / amounts). */
    private fun sampleParts(kind: String, language: String, personal: Boolean, cfg: JSONObject): List<String> {
        val te = language == "te"
        val shop = cfg.optString("shop_name")
        return when (kind) {
            "in" -> if (personal) PaymentAlertParser.personalParts(20000, language, true, if (te) "రమేష్" else "Ramesh")
                else PaymentAlertParser.announcementParts(20000, language, false, if (te) "రమేష్" else "Ramesh", shop)
            "out" -> PaymentAlertParser.personalParts(50000, language, false, if (te) "సురేష్" else "Suresh")
            "bill" -> PaymentAlertParser.billPaidParts(413300, language, "Bajaj Finance", true)
            "refund" -> if (personal) PaymentAlertParser.personalParts(49900, language, true, null)
                else PaymentAlertParser.announcementParts(49900, language, false, null, shop)
            "cashback" -> PaymentAlertParser.bonusParts(5000, language, "cashback")
            "pending" -> PaymentAlertParser.noticeParts("refund_started", 49900, language)
            "failed" -> PaymentAlertParser.noticeParts("failed", 30000, language)
            "due" -> PaymentAlertParser.noticeParts("bill", 96200, language, if (te) "కరెంట్" else "Electricity")
            "autopay" -> PaymentAlertParser.noticeParts("autopay", 49900, language, "Netflix")
            "request" -> PaymentAlertParser.noticeParts("request", 200000, language)
            "fake" -> PaymentAlertParser.noticeParts("suspect", null, language)
            else -> emptyList()
        }
    }

    /** A bill / EMI reminder kept as a "due" row (the app offers it in Upcoming payments). Same due twice = once. */
    private fun saveDue(context: Context, cfg: JSONObject, pkg: String, d: PaymentAlertParser.Due): Map<String, Any?> {
        val now = System.currentTimeMillis()
        val key = "$pkg|due|${d.amountPaise}|${d.dueDate}"
        if (!firstTime(context, key, now)) return mapOf("result" to "duplicate")
        val localId = "due-$now-${(Math.random() * 1e6).toInt()}"
        val event = JSONObject()
            .put("local_id", localId)
            .put("direction", "due")
            .put("source_app", pkg)
            .put("source_label", cfg.optJSONObject("apps")?.optString(pkg, pkg) ?: pkg)
            .put("detected_at", isoUtc(now))
            .put("at_ms", now)
            .put("kind", kindOf(cfg, pkg))
            .put("amount_paise", d.amountPaise)
            .put("due_date", d.dueDate)
            .put("party", d.label)
            .put("spoken", "none")
            .put("test", false)
        synchronized(this) { val list = events(context); list.put(event); saveEvents(context, list) }
        main.post { channel?.invokeMethod("paymentEvent", event.toString()) }
        return mapOf("result" to "due", "localId" to localId)
    }

    /**
     * Owner 2026-11-17: "Upcoming payments" the person keeps (EMI, current bill, rent, recharge ...) are said aloud and
     * shown 2 days before and on the day -- once each. Runs whenever the listener wakes (a notification) and when the app
     * opens; the list comes from the app (personal config "dues": id, name, amount_paise, date yyyy-MM-dd).
     */
    fun checkDues(context: Context) {
        val cfg = personalConfig(context)
        if (!cfg.optBoolean("enabled", false)) return
        val dues = cfg.optJSONArray("dues") ?: return
        val todayDay = dayNumber(Calendar.getInstance())
        val p = prefs(context)
        val language = cfg.optString("language", "te").ifEmpty { "te" }
        for (i in 0 until dues.length()) {
            val d = dues.optJSONObject(i) ?: continue
            val parts = d.optString("date").split("-").mapNotNull { it.toIntOrNull() }
            if (parts.size != 3) continue
            val cal = Calendar.getInstance().apply { clear(); set(parts[0], parts[1] - 1, parts[2]) }
            val left = (dayNumber(cal) - todayDay).toInt()
            if (left != 2 && left != 0) continue
            val mark = "due_said:${d.optString("id")}:${d.optString("date")}:$left"
            if (p.getBoolean(mark, false)) continue
            p.edit().putBoolean(mark, true).apply()
            val name = d.optString("name").ifEmpty { "Bill" }
            val rupees = d.optLong("amount_paise") / 100
            val text = when (language) {
                "te" -> if (left == 0) "$name ₹$rupees ఈ రోజు కట్టాలి." else "$name ₹$rupees రెండు రోజుల్లో కట్టాలి."
                "hi" -> if (left == 0) "$name ₹$rupees आज भरना है।" else "$name ₹$rupees दो दिन में भरना है।"
                else -> if (left == 0) "$name ₹$rupees is due today." else "$name ₹$rupees is due in 2 days."
            }
            showPaymentNotification(context, mark, if (language == "te") "కట్టాల్సిన చెల్లింపు" else "Payment due", text)
            if (!cfg.optBoolean("quiet_dues", false)) CloudVoice.say(context, listOf(text), language, cfg) { }
        }
    }

    /** An app showing its OWN notification again (same notification, same money, within 3 min) is not a new payment. */
    @Synchronized
    private fun repostOf(context: Context, pkg: String, notificationKey: String, direction: String, amount: Long, at: Long): Boolean {
        val list = events(context)
        for (i in 0 until list.length()) {
            val e = list.getJSONObject(i)
            val mine = e.optString("source_app") == pkg && e.optString("notification_key") == notificationKey.take(120)
            val joined = e.optJSONArray("merged_keys")?.let { a -> (0 until a.length()).any { a.optString(it) == "$pkg|${notificationKey.take(120)}" } } == true
            if (!mine && !joined) continue
            if ((e.optString("direction").ifEmpty { "in" }) != direction || e.optLong("amount_paise", -1L) != amount) continue
            if (kotlin.math.abs(at - e.optLong("at_ms", 0L)) <= 3 * 60_000L) return true
        }
        return false
    }

    private fun speak(context: Context, amount: Long?, test: Boolean, eventId: String?, payer: String? = null,
                      cfg: JSONObject = config(context), account: String? = null, bonus: String? = null) {
        val language = cfg.optString("language", "te").ifEmpty { "te" }
        val name = if (cfg.optBoolean("say_name", true)) payer else null
        val parts = if (cfg.optString("business_id").isEmpty() && amount != null && !test && bonus != null)
            withAccount(cfg, account, PaymentAlertParser.bonusParts(amount, language, bonus)) // cashback / interest
        else if (cfg.optString("business_id").isEmpty() && amount != null && !test)
            withAccount(cfg, account, PaymentAlertParser.personalParts(amount, language, true, name))
        else PaymentAlertParser.announcementParts(amount, language, test, name, cfg.optString("shop_name"))
        CloudVoice.say(context, parts, language, cfg) { ok ->
            if (eventId != null) {
                update(context, eventId) { it.put("spoken", if (ok) "announced" else "tts_failed") }
                main.post { channel?.invokeMethod("paymentEvent", "{}") } // the open screen refreshes "Voice: Spoken"
            }
        }
    }

    /**
     * Off the main thread. A payment that was SPOKEN must also reach the history: when the server cannot be reached
     * (offline, 5xx, an expired sign-in, rate limit) the upload is tried again after 20 s, 1, 3, 9 and 27 minutes,
     * and every new payment re-tries anything still waiting. Only a real refusal (4xx) stops, and it is kept on the
     * event as `upload_error` so the history can show why. The server is idempotent on client_event_id.
     */
    private fun upload(context: Context, localId: String, attempt: Int = 0) {
        io.execute {
            var done = false
            try {
                val cfg = config(context)
                val base = cfg.optString("base_url").trimEnd('/')
                val token = cfg.optString("token")
                val biz = cfg.optString("business_id")
                if (base.isEmpty() || token.isEmpty() || biz.isEmpty()) {
                    markUploadNote(context, localId, "not_configured")
                } else {
                    if (attempt == 0) Thread.sleep(2500) // let the announcement finish so "spoken" is final
                    val e = events(context).let { list ->
                        (0 until list.length()).map { list.getJSONObject(it) }.firstOrNull { it.optString("local_id") == localId }
                    }
                    if (e == null || e.has("server_id") || e.has("upload_error") || e.has("direction")) {
                        done = true
                    } else {
                        val body = JSONObject()
                        for (k in listOf("client_event_id", "source_app", "amount_paise", "reference", "detected_at", "reason")) {
                            if (e.has(k)) body.put(k, e.get(k))
                        }
                        val spoken = e.optString("spoken")
                        if (spoken != "pending") body.put("spoken", spoken)
                        val device = cfg.optJSONObject("device_ids")?.optString(biz)?.takeIf { it.isNotEmpty() }
                            ?: cfg.optString("device_id")
                        if (device.isNotEmpty()) body.put("device_id", device)
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
                            done = true
                        } else if (code in 400..499 && code != 401 && code != 429) {
                            markUploaded(context, localId, null, "http_$code")
                            done = true
                        } else {
                            markUploadNote(context, localId, "http_$code")
                        }
                        conn.disconnect()
                    }
                }
            } catch (_: Exception) {
                markUploadNote(context, localId, "offline")
            }
            if (!done && attempt < 5) {
                var wait = 20_000L
                repeat(attempt) { wait *= 3 }
                main.postDelayed({ upload(context, localId, attempt + 1) }, wait)
            }
        }
    }

    /** Why the last upload try did not finish (kept until it does); the history shows it. */
    private fun markUploadNote(context: Context, localId: String, note: String) =
        update(context, localId) { e -> e.put("upload_note", note) }

    /** Every new payment also pushes older ones that are still waiting (a phone that was offline or signed out). */
    private fun retryPending(context: Context, exceptId: String) {
        val now = System.currentTimeMillis()
        val list = events(context)
        for (i in 0 until list.length()) {
            val e = list.getJSONObject(i)
            val id = e.optString("local_id")
            if (id == exceptId || e.has("server_id") || e.has("upload_error") || e.has("direction") || e.optBoolean("test")) continue
            val madeAt = id.removePrefix("pa-").substringBefore("-").toLongOrNull() ?: 0L
            if (now - madeAt < 60_000L) continue
            upload(context, id, 1)
        }
    }

    private fun isoUtc(millis: Long): String {
        val fmt = java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US)
        fmt.timeZone = java.util.TimeZone.getTimeZone("UTC")
        return fmt.format(java.util.Date(millis))
    }

    /**
     * The shop's chosen ElevenLabs voice (owner 2026-11-13): each part of the thank-you is fetched ONCE from
     * ASKODOX (/api/in-app/voice/speak) and kept on this phone, so the fixed words (closing line, shop part) and
     * every name / amount heard before cost nothing again. Parts are joined into one MP3 and played by [Player]
     * (chime, loud, Bluetooth speaker). Offline, slow or any failure -> the phone's own voice says the whole
     * sentence ([Speaker]), so a payment is never silent.
     */
    object CloudVoice {
        /** True when the last failure was the 45 s limit (reported as "stuck", not "tts_failed"). */
        @Volatile var lastStuck = false
        private const val MAX_FILES = 400
        private const val SEGMENT_TIMEOUT_MS = 6500
        // Owner 2026-11-21 ("ElevenLabs voice does not come, another voice comes"): 3.5 s for the parts one after
        // another was too short for a NEW name / amount, so most payments fell back to the phone's own voice. Parts
        // are now fetched AT THE SAME TIME (the server keeps every part it made, for every phone) and waited up to
        // 6.5 s; common amounts are fetched ahead of time ([prefetch]).
        private const val TOTAL_BUDGET_MS = 6500L
        private val voiceIo = Executors.newSingleThreadExecutor() // never waits behind uploads
        private val partIo = Executors.newFixedThreadPool(4)       // one payment's parts in parallel
        private val warmIo = Executors.newSingleThreadExecutor()   // ahead-of-time parts; never delays a payment
        /** Amounts most shops / people receive: their spoken part is fetched once ahead of time. */
        private val COMMON_AMOUNTS = longArrayOf(10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 120, 150, 200, 250, 300,
            350, 400, 450, 500, 600, 700, 800, 1000, 1200, 1500, 2000, 2500, 3000, 5000, 10000)

        fun say(context: Context, parts: List<String>, language: String, cfg: JSONObject, finished: ((Boolean) -> Unit)?) {
            val app = context.applicationContext
            // Owner 2026-11-20: ONE answer per payment, always -- if no voice finished in 45 s the payment is marked
            // "stuck" (never "Speaking..." for ever) and a loud beep plays so the money is still heard.
            val answered = java.util.concurrent.atomic.AtomicBoolean(false)
            val done: (Boolean) -> Unit = { ok ->
                if (answered.compareAndSet(false, true)) {
                    if (!ok) AskodoxPaymentAlerts.beep(app)
                    finished?.invoke(ok)
                }
            }
            AskodoxPaymentAlerts.main.postDelayed({
                if (answered.compareAndSet(false, true)) {
                    lastStuck = true
                    AskodoxPaymentAlerts.beep(app)
                    finished?.invoke(false)
                }
            }, 45_000L)
            val text = parts.joinToString(" ")
            val fallback = { Speaker.say(app, text, language, cfg, done) }
            if (!enabled(cfg) || parts.isEmpty()) { fallback(); return }
            voiceIo.execute {
                // Owner 2026-11-17 ("sound came with the net off, then sometimes not"): a slow / failing network never
                // keeps a payment silent -- the phone's own voice speaks if the cloud voice is not ready in time,
                // and also when the cloud file fails to play.
                val deadline = System.currentTimeMillis() + TOTAL_BUDGET_MS
                val files = try {
                    val jobs = parts.map { p -> partIo.submit(java.util.concurrent.Callable { fetch(app, p, language, cfg, deadline) }) }
                    jobs.map { j ->
                        try {
                            j.get(maxOf(1L, deadline - System.currentTimeMillis()), java.util.concurrent.TimeUnit.MILLISECONDS)
                        } catch (_: Exception) { null }
                    }
                } catch (_: Exception) { null }
                if (files == null || files.any { it == null }) {
                    AskodoxPaymentAlerts.main.post { fallback() }
                    // keep fetching the missing parts in the background: the next payment gets the cloud voice
                    warmIo.execute { for (p in parts) try { fetch(app, p, language, cfg) } catch (_: Exception) { return@execute } }
                    return@execute
                }
                try {
                    val dir = java.io.File(app.cacheDir, "payalert").apply { mkdirs() }
                    val out = java.io.File(dir, "pv-${System.nanoTime()}.mp3")
                    out.outputStream().use { o -> files.forEach { f -> f!!.inputStream().use { it.copyTo(o) } } }
                    Player.enqueue(app, out, cfg) { ok -> if (ok) done(true) else AskodoxPaymentAlerts.main.post { fallback() } }
                } catch (_: Exception) {
                    AskodoxPaymentAlerts.main.post { fallback() }
                }
            }
        }

        /** Fetch the parts that never change for this shop / voice / language, in the background. */
        fun prefetch(context: Context, cfg: JSONObject) {
            if (!enabled(cfg) || !cfg.optBoolean("enabled", false)) return
            val app = context.applicationContext
            val language = cfg.optString("language", "te").ifEmpty { "te" }
            val shop = cfg.optString("business_id").isNotEmpty()
            val parts = PaymentAlertParser.announcementParts(100, language, false, null, cfg.optString("shop_name"))
            val warm = LinkedHashSet<String>(parts.drop(2))
            // The amount part of the most common amounts (shop thank-you or "My phone" credit line).
            for (rupees in COMMON_AMOUNTS) {
                val p = if (shop) PaymentAlertParser.announcementParts(rupees * 100, language, false, null, cfg.optString("shop_name"))
                else PaymentAlertParser.personalParts(rupees * 100, language, true, null)
                p.filter { Regex("""\d""").containsMatchIn(it) }.forEach { warm.add(it) }
            }
            warmIo.execute {
                for (p in warm) try { fetch(app, p, language, cfg) } catch (_: Exception) { return@execute }
            }
        }

        private fun enabled(cfg: JSONObject) =
            cfg.optBoolean("cloud_voice", true) && cfg.optString("base_url").startsWith("http")

        private fun voice(cfg: JSONObject) = cfg.optString("voice", "female").let {
            if (it in setOf("female", "male", "female2", "male2")) it else "female"
        }

        private fun dir(context: Context) = java.io.File(context.filesDir, "payvoice").apply { mkdirs() }

        private fun key(text: String, language: String, voice: String): String {
            val digest = java.security.MessageDigest.getInstance("SHA-256").digest("$voice|$language|$text".toByteArray())
            return digest.take(16).joinToString("") { "%02x".format(it) }
        }

        /** The part's MP3 on this phone (fetched once), or null when ASKODOX / ElevenLabs did not give one. */
        private fun fetch(context: Context, text: String, language: String, cfg: JSONObject,
                          deadline: Long = Long.MAX_VALUE): java.io.File? {
            val v = voice(cfg)
            val file = java.io.File(dir(context), key(text, language, v) + ".mp3")
            if (file.length() > 0) { file.setLastModified(System.currentTimeMillis()); return file }
            val left = deadline - System.currentTimeMillis()
            if (left < 300) return null // out of time: the phone's own voice speaks now (the part is fetched next time)
            val wait = minOf(SEGMENT_TIMEOUT_MS.toLong(), left).toInt()
            val base = cfg.optString("base_url").trimEnd('/')
            val conn = URL("$base/api/in-app/voice/speak").openConnection() as HttpURLConnection
            try {
                conn.requestMethod = "POST"
                conn.connectTimeout = wait
                conn.readTimeout = wait
                conn.doOutput = true
                conn.setRequestProperty("Content-Type", "application/json")
                // engine=elevenlabs: the server never answers with another voice (parts are joined into one MP3).
                val body = JSONObject().put("text", text).put("locale", "$language-IN").put("voice", v).put("engine", "elevenlabs")
                conn.outputStream.use { it.write(body.toString().toByteArray(Charsets.UTF_8)) }
                if (conn.responseCode != 200) return null
                // Only the ElevenLabs MP3 is kept: parts are joined byte-wise, which needs one format and one voice.
                if (conn.getHeaderField("X-ASKODOX-TTS-Path") != "elevenlabs") return null
                val tmp = java.io.File(file.path + ".part")
                conn.inputStream.use { input -> tmp.outputStream().use { input.copyTo(it) } }
                if (tmp.length() == 0L || !tmp.renameTo(file)) { tmp.delete(); return null }
                prune(context)
                return file
            } finally {
                conn.disconnect()
            }
        }

        private fun prune(context: Context) {
            val all = dir(context).listFiles { f -> f.name.endsWith(".mp3") } ?: return
            if (all.size <= MAX_FILES) return
            all.sortedBy { it.lastModified() }.take(all.size - MAX_FILES).forEach { it.delete() }
        }
    }

    /** One TextToSpeech for alerts, on MEDIA audio (Bluetooth speaker when connected), queued (QUEUE_ADD). */
    object Speaker {
        private var tts: TextToSpeech? = null
        @Volatile var ready = false
        /** True once the engine answered its start-up (success or failure): before that, "not ready" means "not checked yet". */
        @Volatile var initDone = false
        @Volatile var languageOk = true
        private val waiting = mutableListOf<() -> Unit>()
        private val callbacks = mutableMapOf<String, (Boolean) -> Unit>()
        private var appContext: Context? = null

        @Synchronized
        fun say(context: Context, text: String, language: String, cfg: JSONObject, done: ((Boolean) -> Unit)?) {
            if (text.isBlank()) return
            appContext = context.applicationContext
            val action = { speakNow(text, language, cfg, done) }
            if (ready) { action(); return }
            waiting.add(action)
            // Owner 2026-11-20: a speech engine that never answers its start-up must not keep a payment silent for
            // ever -- after 8 s the waiting payments fail (the caller beeps) and the engine is started fresh next time.
            AskodoxPaymentAlerts.main.postDelayed({
                synchronized(this) {
                    if (!ready && waiting.contains(action)) {
                        waiting.remove(action)
                        if (!initDone) { try { tts?.shutdown() } catch (_: Exception) {}; tts = null }
                        done?.invoke(false)
                    }
                }
            }, 8_000L)
            if (tts == null) {
                tts = TextToSpeech(context.applicationContext) { status ->
                    synchronized(this) {
                        ready = status == TextToSpeech.SUCCESS
                        initDone = true
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

        /** Start the engine before the first payment so the health check reads a real answer, not "never started". */
        @Synchronized
        fun warm(context: Context) {
            if (tts != null) return
            appContext = context.applicationContext
            tts = TextToSpeech(context.applicationContext) { status ->
                synchronized(this) {
                    ready = status == TextToSpeech.SUCCESS
                    initDone = true
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
                    }
                }
            }
        }

        /** The phone speech engine's own locale for an app language code ("te" -> te-IN; any Indian language). */
        fun localeOf(language: String): Locale = Locale(language.ifEmpty { "en" }, "IN")

        /**
         * Can this phone speak [language] with NO internet? ready=null while the engine is still starting.
         * supported = the engine knows the language at all; installed = its voice data is on the phone; offline = a voice
         * that needs no network is installed (the alert then speaks in that language even when the net is off).
         */
        @Synchronized
        fun offlineVoice(context: Context, language: String): Map<String, Any?> {
            warm(context)
            val engine = tts
            if (!initDone || engine == null) return mapOf("ready" to (if (initDone) false else null), "language" to language)
            val locale = localeOf(language)
            return try {
                val res = engine.isLanguageAvailable(locale)
                val supported = res != TextToSpeech.LANG_NOT_SUPPORTED
                val installed = supported && res != TextToSpeech.LANG_MISSING_DATA
                val offline = installed && (engine.voices ?: emptySet()).any { v ->
                    v.locale.language == locale.language && !v.isNetworkConnectionRequired &&
                        !v.features.contains(TextToSpeech.Engine.KEY_FEATURE_NOT_INSTALLED)
                }
                mapOf("ready" to true, "language" to language, "supported" to supported, "installed" to installed,
                    "offline" to offline, "engine" to (engine.defaultEngine ?: ""))
            } catch (_: Exception) {
                mapOf("ready" to true, "language" to language, "supported" to false, "installed" to false, "offline" to false)
            }
        }

        @Synchronized
        private fun finish(id: String?, ok: Boolean) {
            val cb = id?.let { callbacks.remove(it) } ?: return
            cb(ok)
        }

        private fun speakNow(text: String, language: String, cfg: JSONObject, done: ((Boolean) -> Unit)?) {
            val engine = tts ?: run { done?.invoke(false); return }
            val locale = localeOf(language) // any Indian language the person chose (ta, kn, ml, bn, mr, gu, pa, or, ur ...)
            val res = engine.setLanguage(locale)
            languageOk = res != TextToSpeech.LANG_MISSING_DATA && res != TextToSpeech.LANG_NOT_SUPPORTED
            var spoken = text
            if (!languageOk && language != "en") {
                engine.setLanguage(Locale("en", "IN"))
                spoken = PaymentAlertParser.announcement(Regex("""\d+""").find(text)?.value?.toLongOrNull()?.times(100), "en",
                    text.startsWith("టెస్ట్") || text.startsWith("टेस्ट"))
            }
            val wantMale = cfg.optString("voice").startsWith("male")
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
            val id = "pa-${System.nanoTime()}"
            val ctx = appContext ?: run { done?.invoke(false); return }
            val dir = java.io.File(ctx.cacheDir, "payalert").apply { mkdirs() }
            val file = java.io.File(dir, "$id.wav")
            synchronized(this) {
                callbacks[id] = { ok -> if (ok && file.length() > 0) Player.enqueue(ctx, file, cfg, done) else done?.invoke(false) }
            }
            if (engine.synthesizeToFile(spoken, Bundle(), file, id) == TextToSpeech.ERROR) finish(id, false)
            // an engine that never reports the file (missing voice data on some phones) fails after 12 s, never hangs
            AskodoxPaymentAlerts.main.postDelayed({ finish(id, false) }, 12_000L)
        }
    }

    /**
     * Plays announcements one after another, LOUD: a short chime first, media volume raised to the
     * maximum while it speaks (restored afterwards) and a loudness boost on the voice. Uses media
     * audio, so a connected Bluetooth speaker plays it.
     */
    object Player {
        private data class Item(val file: java.io.File, val cfg: JSONObject, val done: ((Boolean) -> Unit)?)
        private val queue = ArrayDeque<Item>()
        private var busy = false
        private var busySince = 0L
        private var savedVolume: Int? = null
        private var focus: android.media.AudioFocusRequest? = null

        /** What the last finished clip did (for the server trail): volume %, route, ms played. */
        @Volatile var lastDetail: String = ""

        fun enqueue(context: Context, file: java.io.File, cfg: JSONObject, done: ((Boolean) -> Unit)?) {
            AskodoxPaymentAlerts.main.post {
                queue.addLast(Item(file, cfg, done))
                // Owner 2026-11-20 (every payment since 08:08 stuck on "Speaking..."): a clip that never finished kept
                // the queue busy for ever. A queue busy for more than 40 s is started again.
                if (busy && System.currentTimeMillis() - busySince > 40_000L) busy = false
                if (!busy) next(context.applicationContext)
            }
        }

        private fun takeFocus(audio: AudioManager) {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    val req = android.media.AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
                        .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
                        .build()
                    audio.requestAudioFocus(req)
                    focus = req
                } else {
                    @Suppress("DEPRECATION")
                    audio.requestAudioFocus(null, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
                }
            } catch (_: Exception) {
            }
        }

        private fun dropFocus(audio: AudioManager) {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    focus?.let { audio.abandonAudioFocusRequest(it) }
                } else {
                    @Suppress("DEPRECATION")
                    audio.abandonAudioFocus(null)
                }
            } catch (_: Exception) {
            }
            focus = null
        }

        private fun next(context: Context) {
            val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val item = queue.removeFirstOrNull()
            if (item == null) {
                busy = false
                savedVolume?.let { v -> try { audio.setStreamVolume(AudioManager.STREAM_MUSIC, v, 0) } catch (_: Exception) {} }
                savedVolume = null
                dropFocus(audio)
                return
            }
            busy = true
            busySince = System.currentTimeMillis()
            takeFocus(audio)
            if (item.cfg.optBoolean("loud", true) && savedVolume == null) {
                try {
                    savedVolume = audio.getStreamVolume(AudioManager.STREAM_MUSIC)
                    audio.setStreamVolume(AudioManager.STREAM_MUSIC, audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC), 0)
                } catch (_: Exception) {
                    savedVolume = null // Do Not Disturb / policy: keep the user's volume
                }
            }
            val chime = item.cfg.optBoolean("chime", true)
            if (chime) {
                try {
                    val tone = android.media.ToneGenerator(AudioManager.STREAM_MUSIC, 100)
                    tone.startTone(android.media.ToneGenerator.TONE_PROP_ACK, 400)
                    AskodoxPaymentAlerts.main.postDelayed({ tone.release() }, 900)
                } catch (_: Exception) {
                }
            }
            AskodoxPaymentAlerts.main.postDelayed({ play(context, item) }, if (chime) 650L else 0L)
        }

        private fun play(context: Context, item: Item) {
            var enhancer: android.media.audiofx.LoudnessEnhancer? = null
            var finished = false
            var startedAt = 0L
            val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val finishItem = { ok: Boolean, mp: android.media.MediaPlayer? ->
                if (!finished) {
                    finished = true
                    lastDetail = try {
                        val max = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC).coerceAtLeast(1)
                        val vol = audio.getStreamVolume(AudioManager.STREAM_MUSIC) * 100 / max
                        val played = if (startedAt > 0) System.currentTimeMillis() - startedAt else 0
                        "vol=$vol% out=${AskodoxPaymentAlerts.audioRoute(context)["output"]} played_ms=$played ok=$ok"
                    } catch (_: Exception) { "ok=$ok" }
                    try { enhancer?.release() } catch (_: Exception) {}
                    try { mp?.release() } catch (_: Exception) {}
                    item.file.delete()
                    item.done?.invoke(ok)
                    next(context)
                }
            }
            try {
                val mp = android.media.MediaPlayer()
                mp.setAudioAttributes(AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
                mp.setDataSource(item.file.path)
                mp.prepare()
                val v = item.cfg.optInt("volume_pct", 100).coerceIn(10, 100) / 100f
                mp.setVolume(v, v)
                try {
                    enhancer = android.media.audiofx.LoudnessEnhancer(mp.audioSessionId).apply {
                        setTargetGain(item.cfg.optInt("boost_mb", 900).coerceIn(0, 1500))
                        enabled = true
                    }
                } catch (_: Exception) {
                    enhancer = null // effect not available on this phone: plain playback
                }
                mp.setOnCompletionListener { finishItem(true, it) }
                mp.setOnErrorListener { p, _, _ -> finishItem(false, p); true }
                startedAt = System.currentTimeMillis()
                mp.start()
                // A clip that never reports its end (audio stuck, focus lost) is closed after its length + 4 s, so the
                // next payment is never held behind it.
                val limit = (if (mp.duration > 0) mp.duration.toLong() else 12_000L).coerceAtMost(25_000L) + 4_000L
                AskodoxPaymentAlerts.main.postDelayed({ if (!finished) finishItem(false, mp) }, limit)
            } catch (_: Exception) {
                finishItem(false, null)
            }
        }
    }
}

/** Reads ONLY allowed payment apps' notifications; everything else returns before any content is touched. */
class AskodoxPaymentAlertListener : NotificationListenerService() {
    override fun onListenerConnected() {
        AskodoxPaymentAlerts.prefs(this).edit().putLong("listener_connected_at", System.currentTimeMillis()).apply()
        try { AskodoxPaymentAlerts.checkDues(this) } catch (_: Exception) {}
    }

    override fun onListenerDisconnected() {
        AskodoxPaymentAlerts.prefs(this).edit().putLong("listener_disconnected_at", System.currentTimeMillis()).apply()
        AskodoxPaymentAlerts.rebindIfEnabled(this)
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        val n = sbn ?: return
        try { AskodoxPaymentAlerts.checkDues(this) } catch (_: Exception) {}
        try {
            // ONE destination per notification: the shop or the person's own "My phone" (both can be on at once).
            val (_, cfg) = AskodoxPaymentAlerts.destination(AskodoxPaymentAlerts.config(this),
                AskodoxPaymentAlerts.personalConfig(this), n.packageName) ?: return // not a chosen app: never read
            // Only the time (no content): lets the setup flow show this app's notifications reach the phone.
            AskodoxPaymentAlerts.prefs(this).edit().putLong("seen:${n.packageName}", System.currentTimeMillis()).apply()
            if (n.isOngoing) return
            val notification = n.notification ?: return
            if (notification.flags and android.app.Notification.FLAG_GROUP_SUMMARY != 0) return
            val extras = notification.extras ?: return
            val title = extras.getCharSequence(android.app.Notification.EXTRA_TITLE)?.toString()
            // Messaging apps (Google Messages, Samsung Messages ...) use a MessagingStyle notification: the new
            // SMS sits in EXTRA_MESSAGES (newest last) and EXTRA_TEXT can say only "2 new messages". Only the
            // NEWEST message is read, so an older payment in the same thread is never counted again.
            val newestBundle = try {
                @Suppress("DEPRECATION")
                val list = extras.getParcelableArray(android.app.Notification.EXTRA_MESSAGES)
                list?.lastOrNull() as? android.os.Bundle
            } catch (_: Exception) { null }
            val newest = newestBundle?.getCharSequence("text")?.toString()
            // The newest message's OWN time: the same message shown again keeps it (owner 2026-11-17 duplicate).
            val messageTime = newestBundle?.getLong("time", 0L) ?: 0L
            val lines = try {
                extras.getCharSequenceArray(android.app.Notification.EXTRA_TEXT_LINES)?.lastOrNull()?.toString()
            } catch (_: Exception) { null }
            val text = listOfNotNull(
                extras.getCharSequence(android.app.Notification.EXTRA_TEXT)?.toString(),
                extras.getCharSequence(android.app.Notification.EXTRA_BIG_TEXT)?.toString(),
                newest, lines,
            ).distinct().joinToString(" ")
            val whenMillis = if (notification.`when` > 0) notification.`when` else n.postTime
            AskodoxPaymentAlerts.handle(this, n.packageName, title, text, n.key ?: "${n.id}", whenMillis, cfgIn = cfg,
                messageTime = messageTime)
        } catch (_: Exception) {
            // a malformed notification never crashes the listener
        }
    }
}

/**
 * High-priority FCM data message {type=payalert, event_id, business_id, text, language}: speak it now, even when
 * ASKODOX is closed or the phone is locked. This is the app's ONE FCM service (it extends the Flutter plugin's
 * service and is declared with a higher priority): payment alerts are spoken here, on FCM's worker thread, which
 * waits (max 18 s) until the voice has finished so Android does not stop the process mid-sentence. Every other
 * message goes to the Flutter plugin exactly as before.
 */
class AskodoxMessagingService : io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingService() {
    override fun onMessageReceived(remoteMessage: com.google.firebase.messaging.RemoteMessage) {
        val data = remoteMessage.data
        if (data["type"] == "say") {
            // Owner 2026-11-17: a new order / a table asking for water is SAID on the staff phone, even with the app closed.
            val ctx = applicationContext
            val key = data["title"].orEmpty() + "|" + data["text"].orEmpty()
            try { showPaymentNotification(ctx, key, data["title"] ?: "ASKODOX", data["text"] ?: "") } catch (_: Exception) {}
            val sentAt = data["sent_at"]?.toLongOrNull() ?: 0L
            val fresh = sentAt <= 0 || System.currentTimeMillis() - sentAt < 3 * 60_000L
            val cfg = AskodoxPaymentAlerts.config(ctx)
            if (fresh && cfg.optBoolean("speaks_remote", true) && !data["text"].isNullOrBlank()) {
                try {
                    val latch = java.util.concurrent.CountDownLatch(1)
                    val text = data["text"] ?: ""
                    val language = cfg.optString("language", "te").ifEmpty { "te" }
                    AskodoxPaymentAlerts.main.post {
                        AskodoxPaymentAlerts.Speaker.say(ctx, text, language, cfg) { latch.countDown() }
                    }
                    latch.await(15, java.util.concurrent.TimeUnit.SECONDS)
                } catch (_: Exception) {
                }
            }
            return
        }
        if (data["type"] != "payalert") {
            super.onMessageReceived(remoteMessage)
            return
        }
        val ctx = applicationContext
        val eventId = data["event_id"] ?: ""
        val businessId = data["business_id"]
        // Proof the push reached THIS phone (history shows "Delivered" even if the voice later fails).
        if (businessId != null && eventId.isNotEmpty()) AskodoxPaymentAlerts.ack(ctx, businessId, eventId, "delivered")
        // A push held back by the phone's battery saver arrives late: shown, never spoken (a late voice sounds like a
        // second, new payment). The server keeps it alive 10 minutes so a sleeping phone still gets it.
        val sentAt = data["sent_at"]?.toLongOrNull() ?: 0L
        if (sentAt > 0 && System.currentTimeMillis() - sentAt > 3 * 60_000L) {
            try { showPaymentNotification(ctx, eventId, data["title"] ?: "ASKODOX", data["text"] ?: "") } catch (_: Exception) {}
            if (businessId != null && eventId.isNotEmpty()) AskodoxPaymentAlerts.ack(ctx, businessId, eventId, "seen")
            return
        }
        // A visible, high-importance notification: Android keeps high-priority delivery (and wakes a locked
        // phone) only for messages that show something to the user. Silent: the voice is the sound.
        try {
            showPaymentNotification(ctx, eventId, data["title"] ?: "ASKODOX", data["text"] ?: "")
        } catch (_: Exception) {
        }
        try {
            val latch = java.util.concurrent.CountDownLatch(1)
            val state = AskodoxPaymentAlerts.speakRemote(ctx, eventId, data["text"] ?: "",
                data["language"] ?: "te", businessId, true) { latch.countDown() }
            if (state == "spoken") latch.await(18, java.util.concurrent.TimeUnit.SECONDS)
        } catch (_: Exception) {
        }
    }
}

private const val PAYMENT_CHANNEL = "askodox_payments"

private fun showPaymentNotification(context: Context, eventId: String, title: String, text: String) {
    if (text.isBlank()) return
    val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && manager.getNotificationChannel(PAYMENT_CHANNEL) == null) {
        manager.createNotificationChannel(android.app.NotificationChannel(PAYMENT_CHANNEL, "Payment alerts",
            android.app.NotificationManager.IMPORTANCE_HIGH).apply {
            description = "Shop payment alerts (the voice is played by ASKODOX itself)"
            setSound(null, null)
            enableVibration(true)
        })
    }
    val open = context.packageManager.getLaunchIntentForPackage(context.packageName)
    val pending = open?.let {
        android.app.PendingIntent.getActivity(context, eventId.hashCode(), it,
            android.app.PendingIntent.FLAG_IMMUTABLE or android.app.PendingIntent.FLAG_UPDATE_CURRENT)
    }
    val notification = androidx.core.app.NotificationCompat.Builder(context, PAYMENT_CHANNEL)
        .setSmallIcon(context.applicationInfo.icon)
        .setContentTitle(title)
        .setContentText(text)
        .setStyle(androidx.core.app.NotificationCompat.BigTextStyle().bigText(text))
        .setPriority(androidx.core.app.NotificationCompat.PRIORITY_HIGH)
        .setCategory(androidx.core.app.NotificationCompat.CATEGORY_STATUS)
        .setSilent(true)
        .setAutoCancel(true)
        .apply { if (pending != null) setContentIntent(pending) }
        .build()
    try {
        NotificationManagerCompat.from(context).notify("payalert", eventId.hashCode(), notification)
    } catch (_: SecurityException) {
        // notifications not allowed: the voice still plays
    }
}

/** After this app is updated from Play, bind the payment listener again (it is not always rebound by the system). */
class AskodoxPaymentAlertsReceiver : android.content.BroadcastReceiver() {
    override fun onReceive(context: Context, intent: android.content.Intent?) {
        if (intent?.action == android.content.Intent.ACTION_MY_PACKAGE_REPLACED) {
            AskodoxPaymentAlerts.rebindIfEnabled(context)
        }
    }
}
