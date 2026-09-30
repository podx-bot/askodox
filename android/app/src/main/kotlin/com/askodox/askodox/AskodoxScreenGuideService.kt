package com.askodox.askodox

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.graphics.PixelFormat
import android.graphics.Rect
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.speech.tts.TextToSpeech
import android.view.Gravity
import android.view.GestureDetector
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.Locale
import java.util.concurrent.Executors

/**
 * ASKODOX Screen Guide: an OPT-IN accessibility service (the user enables it
 * in Android Settings > Accessibility) that guides a person step by step in
 * another app.
 *
 * Safety rules, enforced here on the phone before anything leaves it:
 * * It reads NOTHING unless the user started a guide in ASKODOX (session set).
 * * Privacy Shield first: password fields, OTP / PIN / UPI PIN / CVV / card /
 *   bank / Aadhaar words (English, Telugu, Hindi) and payment / banking apps
 *   -> PRIVACY PAUSED immediately; that screen is not sent, stored or logged.
 *   Resume needs the user's double-tap or Continue.
 * * Only visible labels + roles are sent (never field values), no screenshots.
 * * It never taps, types or performs actions: the highlight window does not
 *   take touches and the user does every step (no gestures, no performAction).
 * * A visible "ASKODOX guide" panel is always shown while active, with Stop.
 * * End Guide clears the session, token, labels and highlight from memory.
 */
class AskodoxScreenGuideService : AccessibilityService() {
    data class Session(
        val id: String,
        val token: String,
        val baseUrl: String,
        val language: String,
        val voice: Boolean,
    )

    companion object {
        @Volatile var instance: AskodoxScreenGuideService? = null
            private set
        @Volatile var session: Session? = null
            private set
        @Volatile var state: String = "IDLE"
            private set
        @Volatile var lastInstruction: String? = null
            private set

        private val sensitiveWords = Regex(
            "(\\botp\\b|one[\\s-]?time[\\s-]?pass|verification code|security code|\\bpassword\\b|\\bpasscode\\b|" +
                "\\bpin\\b|\\bmpin\\b|upi[\\s-]?pin|\\bcvv\\b|\\bcvc\\b|card number|card no|expiry|valid thru|" +
                "net[\\s-]?banking|internet banking|\\baadhaa?r\\b|\\bpan (card|number)\\b|passport|biometric|" +
                "fingerprint|face unlock|security question|transaction password|authori[sz]e (the )?payment|" +
                "approve (the )?payment|confirm (the )?payment|payment authori[sz]ation|3-?d secure|\\bvbv\\b|" +
                "securecode|mandate|ఓటీపీ|పాస్‌?వర్డ్|పిన్|ఆధార్|ओटीपी|पासवर्ड|पिन|आधार)",
            RegexOption.IGNORE_CASE,
        )
        private val sensitivePackages = listOf(
            "org.npci.", "in.org.npci.", "com.phonepe.", "net.one97.paytm", "com.google.android.apps.nbu.paisa",
            "com.sbi.", "com.csam.icici", "com.snapwork.hdfc", "com.axis.", "com.msf.kbank", "com.bankofbaroda",
            "com.infrasofttech.", "com.mobikwik", "com.freecharge", "com.google.android.gms.wallet",
            "com.google.android.apps.walletnfcrel",
        )

        fun isEnabled(context: Context): Boolean {
            val enabled = Settings.Secure.getString(
                context.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
            ) ?: return false
            val name = "${context.packageName}/${AskodoxScreenGuideService::class.java.name}"
            val short = "${context.packageName}/.AskodoxScreenGuideService"
            return enabled.split(':').any { it.equals(name, true) || it.equals(short, true) }
        }

        /** Called by MainActivity when the user starts a guide. */
        fun begin(newSession: Session): Boolean {
            val service = instance ?: return false
            service.startSession(newSession)
            return true
        }

        fun resume() { instance?.resumeFromUser() }

        fun end(outcome: String) { instance?.endSession(outcome) }

        fun textIsSensitive(text: String): Boolean = sensitiveWords.containsMatchIn(text)
    }

    private val main = Handler(Looper.getMainLooper())
    private val io = Executors.newSingleThreadExecutor()
    private var windowManager: WindowManager? = null
    private var panel: View? = null
    private var panelText: TextView? = null
    private var highlight: View? = null
    private var paused = false
    private var labelBounds: MutableMap<String, Rect> = mutableMapOf()
    private var tts: TextToSpeech? = null
    private var ttsReady = false
    private val captureRunnable = Runnable { capture() }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // No session: nothing is read at all.
        if (session == null || event == null) return
        val type = event.eventType
        if (type != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED &&
            type != AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED
        ) return
        if (event.packageName?.toString() == packageName) return
        main.removeCallbacks(captureRunnable)
        main.postDelayed(captureRunnable, 900)
    }

    override fun onInterrupt() {}

    override fun onDestroy() {
        clearAll()
        instance = null
        super.onDestroy()
    }

    // ------------------------------------------------------------ session --

    private fun startSession(newSession: Session) {
        main.post {
            session = newSession
            paused = false
            state = "ACTIVE"
            lastInstruction = null
            if (newSession.voice && tts == null) {
                tts = TextToSpeech(this) { status -> ttsReady = status == TextToSpeech.SUCCESS }
            }
            showPanel(if (newSession.language == "te") "గైడ్ మొదలైంది. మీరు సహాయం కావాల్సిన యాప్‌ను తెరవండి."
                      else "Guide started. Open the app you need help with.")
        }
    }

    private fun resumeFromUser() {
        val current = session ?: return
        main.post {
            paused = false
            state = "ACTIVE"
            showPanel(if (current.language == "te") "కొనసాగిస్తున్నాను…" else "Continuing…")
            io.execute { post("resume", JSONObject().put("session_id", current.id)) }
            main.postDelayed(captureRunnable, 400)  // re-checked: a sensitive screen pauses again
        }
    }

    private fun endSession(outcome: String) {
        val current = session
        main.post { clearAll() }
        if (current != null) {
            io.execute {
                post("end", JSONObject().put("session_id", current.id).put("outcome", outcome), current)
            }
        }
    }

    private fun clearAll() {
        main.removeCallbacks(captureRunnable)
        session = null
        paused = false
        state = "ENDED"
        lastInstruction = null
        labelBounds = mutableMapOf()
        tts?.stop()
        tts?.shutdown()
        tts = null
        ttsReady = false
        removeHighlight()
        panel?.let { try { windowManager?.removeView(it) } catch (_: Exception) {} }
        panel = null
        panelText = null
    }

    // ------------------------------------------------------------ capture --

    private fun pause() {
        val current = session ?: return
        paused = true
        state = "PRIVACY_PAUSED"
        lastInstruction = null
        labelBounds = mutableMapOf()
        removeHighlight()
        tts?.stop()
        showPanel(
            if (current.language == "te")
                "గోప్యత కోసం ఆపివేయబడింది — సున్నితమైన సమాచారం కనిపించింది.\n" +
                    "సున్నితమైన సమాచారం కనిపించింది. ASKODOX స్క్రీన్ సహాయం ఆపివేయబడింది. ఈ దశను మీరే పూర్తి చేయండి. " +
                    "పూర్తయ్యాక ఈ స్క్రీన్ నుండి బయటకు వచ్చి, ASKODOX‌ను రెండుసార్లు తాకండి లేదా Continue నొక్కండి."
            else
                "Privacy Paused — sensitive information detected.\n" +
                    "Sensitive information detected. ASKODOX screen assistance is paused. Please complete this step " +
                    "yourself. When finished and you leave this sensitive screen, double-tap ASKODOX or press " +
                    "Continue to resume.",
        )
    }

    private fun capture() {
        val current = session ?: return
        if (paused) return  // explicit resume only
        val root = rootInActiveWindow ?: return
        val pkg = root.packageName?.toString().orEmpty()
        if (pkg == packageName) return
        if (sensitivePackages.any { pkg.startsWith(it) }) { pause(); return }
        val elements = JSONArray()
        val bounds = mutableMapOf<String, Rect>()
        val queue = ArrayDeque<AccessibilityNodeInfo>()
        queue.add(root)
        var visited = 0
        while (queue.isNotEmpty() && visited < 150) {
            val node = queue.removeFirst()
            visited++
            // Privacy Shield BEFORE anything is kept: a password field or a
            // sensitive word stops the capture and nothing is sent.
            if (node.isPassword) { pause(); return }
            val hint = if (Build.VERSION.SDK_INT >= 26) node.hintText?.toString().orEmpty() else ""
            val label = (node.text ?: node.contentDescription)?.toString()?.trim().orEmpty()
            if (textIsSensitive("$label $hint")) { pause(); return }
            if (label.isNotEmpty() && node.isVisibleToUser && elements.length() < 60 && !node.isEditable) {
                // Editable fields are described by role only -- their content is never read.
                val rect = Rect()
                node.getBoundsInScreen(rect)
                val short = label.take(80)
                bounds[short] = rect
                elements.put(JSONObject()
                    .put("label", short)
                    .put("role", node.className?.toString()?.substringAfterLast('.')?.take(20) ?: "text")
                    .put("clickable", node.isClickable))
            } else if (node.isEditable && elements.length() < 60) {
                elements.put(JSONObject().put("label", hint.take(80)).put("role", "edit").put("clickable", true))
            }
            for (i in 0 until node.childCount) node.getChild(i)?.let { queue.add(it) }
        }
        labelBounds = bounds
        val appLabel = try {
            packageManager.getApplicationLabel(packageManager.getApplicationInfo(pkg, 0)).toString()
        } catch (_: Exception) { "" }
        val screen = JSONObject().put("package", pkg).put("app_label", appLabel).put("elements", elements)
        io.execute {
            val reply = post("step", JSONObject().put("session_id", current.id).put("screen", screen), current)
            main.post { handleStep(reply) }
        }
    }

    private fun handleStep(reply: JSONObject?) {
        if (session == null || paused) return
        if (reply == null) {
            showPanel(if (session?.language == "te") "ఇప్పుడు కనెక్ట్ కాలేదు. Continue నొక్కండి." else "Can't reach ASKODOX right now. Press Continue to retry.")
            return
        }
        if (reply.optString("state") == "PRIVACY_PAUSED") { pause(); return }
        if (reply.optString("state") == "DISABLED") {
            // Switched off by ASKODOX (policy / kill switch): explain and stop.
            showPanel(reply.optString("message", "Screen Guide is not available right now."))
            main.postDelayed({ clearAll() }, 6000)
            session = null
            return
        }
        val text = reply.optString("instruction", "")
        if (text.isEmpty()) return
        lastInstruction = text
        showPanel(text)
        removeHighlight()
        val target = reply.optString("target_label", "")
        if (reply.optBoolean("highlight") && target.isNotEmpty()) labelBounds[target]?.let { showHighlight(it) }
        if (session?.voice == true && ttsReady) {
            tts?.language = Locale.forLanguageTag(session?.language ?: "en")
            tts?.speak(reply.optString("speak", text), TextToSpeech.QUEUE_FLUSH, null, "askodox_guide")
        }
    }

    private fun post(path: String, body: JSONObject, s: Session? = session): JSONObject? {
        val current = s ?: return null
        return try {
            val conn = URL("${current.baseUrl.trimEnd('/')}/api/companion/guide/$path").openConnection() as HttpURLConnection
            conn.requestMethod = "POST"
            conn.connectTimeout = 8000
            conn.readTimeout = 15000
            conn.doOutput = true
            conn.setRequestProperty("Content-Type", "application/json")
            conn.setRequestProperty("Authorization", "Bearer ${current.token}")
            conn.outputStream.use { it.write(body.toString().toByteArray(Charsets.UTF_8)) }
            val ok = conn.responseCode in 200..299
            val text = (if (ok) conn.inputStream else conn.errorStream)?.bufferedReader()?.use { it.readText() }.orEmpty()
            conn.disconnect()
            if (ok) JSONObject(text) else null
        } catch (_: Exception) {
            null
        }
    }

    // ----------------------------------------------------------------- UI --

    private fun overlayParams(width: Int, height: Int, touchable: Boolean): WindowManager.LayoutParams {
        var flags = WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN
        if (!touchable) flags = flags or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }
        return WindowManager.LayoutParams(width, height, type, flags, PixelFormat.TRANSLUCENT)
    }

    private fun showPanel(message: String) {
        val wm = windowManager ?: return
        if (panel == null) {
            val density = resources.displayMetrics.density
            val header = TextView(this).apply {
                text = "● ASKODOX guide"  // visible indicator while the guide can see labels
                setTextColor(0xFFFFFFFF.toInt())
                textSize = 12f
            }
            val body = TextView(this).apply {
                setTextColor(0xFFFFFFFF.toInt())
                textSize = 15f
            }
            val cont = Button(this).apply { text = "Continue"; setOnClickListener { resumeFromUser() } }
            val stop = Button(this).apply { text = "End Guide"; setOnClickListener { endSession("abandoned") } }
            val buttons = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                addView(cont)
                addView(stop)
            }
            val root = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                val pad = (12 * density).toInt()
                setPadding(pad, pad, pad, pad)
                background = GradientDrawable().apply {
                    cornerRadius = 18 * density
                    setColor(0xEE1B1340.toInt())
                }
                addView(header)
                addView(body)
                addView(buttons)
            }
            // Double-tap the panel = Continue (resume after a privacy pause).
            val detector = GestureDetector(this, object : GestureDetector.SimpleOnGestureListener() {
                override fun onDoubleTap(e: MotionEvent): Boolean { resumeFromUser(); return true }
            })
            root.setOnTouchListener { _, e -> detector.onTouchEvent(e); false }
            val lp = overlayParams(WindowManager.LayoutParams.MATCH_PARENT, WindowManager.LayoutParams.WRAP_CONTENT, true)
            lp.gravity = Gravity.BOTTOM
            lp.y = (72 * density).toInt()
            lp.horizontalMargin = 0.03f
            try {
                wm.addView(root, lp)
                panel = root
                panelText = body
            } catch (_: Exception) {
                panel = null
            }
        }
        panelText?.text = message
    }

    private fun showHighlight(rect: Rect) {
        val wm = windowManager ?: return
        val density = resources.displayMetrics.density
        val view = View(this).apply {
            background = GradientDrawable().apply {
                setStroke((3 * density).toInt(), 0xFFFFC400.toInt())
                cornerRadius = 10 * density
                setColor(0x22FFC400)
            }
        }
        // Not touchable: every tap goes to the real app, typed by the user.
        val lp = overlayParams(rect.width().coerceAtLeast(1), rect.height().coerceAtLeast(1), false)
        lp.gravity = Gravity.TOP or Gravity.START
        lp.x = rect.left
        lp.y = rect.top
        try {
            wm.addView(view, lp)
            highlight = view
        } catch (_: Exception) {
            highlight = null
        }
    }

    private fun removeHighlight() {
        highlight?.let { try { windowManager?.removeView(it) } catch (_: Exception) {} }
        highlight = null
    }
}
