package com.askodox.askodox

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.IBinder
import android.provider.Settings
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import kotlin.math.abs

/**
 * The ASKODOX floating bubble: a small, movable companion shown OVER other
 * apps only after the user turned it on in Profile and granted Android's
 * "Display over other apps" permission.
 *
 * * It never records audio, never reads the screen, never runs timers --
 *   it is one view. Tap = back to ASKODOX; x = hide it (it returns the next
 *   time the user leaves ASKODOX while the setting is on); the notification
 *   and Profile turn it off.
 * * Android requires a foreground service (with its notification) to keep
 *   an overlay alive; type "specialUse" with the reason declared in the
 *   manifest.
 * * The service is started while ASKODOX is on screen (allowed); leaving /
 *   returning only shows / hides the view (MainActivity onStop / onStart).
 */
class AskodoxFloatingCompanionService : Service() {
    companion object {
        private const val channelId = "askodox_bubble"
        private const val notificationId = 7401
        const val actionStop = "com.askodox.bubble.STOP"

        @Volatile
        var instance: AskodoxFloatingCompanionService? = null
            private set

        fun canDraw(context: Context): Boolean =
            Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(context)
    }

    private var windowManager: WindowManager? = null
    private var bubble: View? = null
    private var params: WindowManager.LayoutParams? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == actionStop || !canDraw(this)) {
            if (intent?.action == actionStop) {
                // "Turn off" in the notification turns the Profile setting off too.
                getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE).edit()
                    .putBoolean("flutter.askodox.bubble.enabled", false).apply()
            }
            stopSelf()
            return START_NOT_STICKY
        }
        val type = if (Build.VERSION.SDK_INT >= 34) ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE else 0
        ServiceCompat.startForeground(this, notificationId, buildNotification(), type)
        return START_NOT_STICKY
    }

    private fun buildNotification(): Notification {
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && manager.getNotificationChannel(channelId) == null) {
            manager.createNotificationChannel(
                NotificationChannel(channelId, "ASKODOX bubble", NotificationManager.IMPORTANCE_MIN).apply {
                    description = "Shown while the floating ASKODOX bubble is on"
                    setShowBadge(false)
                },
            )
        }
        val open = PendingIntent.getActivity(
            this, 1, Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val stop = PendingIntent.getService(
            this, 2, Intent(this, AskodoxFloatingCompanionService::class.java).setAction(actionStop),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Builder(this, channelId)
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle("ASKODOX bubble is on")
            .setContentText("Tap to open ASKODOX. Turn it off here or in Profile.")
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setSilent(true)
            .setOngoing(true)
            .setContentIntent(open)
            .addAction(0, "Turn off", stop)
            .build()
    }

    /** Called by MainActivity: visible while the user is outside ASKODOX. */
    fun setVisible(visible: Boolean) {
        if (visible) show() else hide()
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun show() {
        if (bubble != null || !canDraw(this)) return
        val density = resources.displayMetrics.density
        val size = (56 * density).toInt()
        val icon = ImageView(this).apply {
            setImageResource(applicationInfo.icon)
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(0xFF6C4DFF.toInt())
            }
            val pad = (8 * density).toInt()
            setPadding(pad, pad, pad, pad)
            contentDescription = "Open ASKODOX"
        }
        val close = TextView(this).apply {
            text = "×"
            textSize = 16f
            setTextColor(0xFFFFFFFF.toInt())
            gravity = Gravity.CENTER
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(0xCC10204A.toInt())
            }
            contentDescription = "Hide ASKODOX bubble"
            setOnClickListener { hide() }
        }
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            addView(FrameLayout(context).apply { addView(icon, FrameLayout.LayoutParams(size, size)) })
            addView(close, LinearLayout.LayoutParams((24 * density).toInt(), (24 * density).toInt()))
        }
        val overlayType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }
        val lp = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            overlayType,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = (resources.displayMetrics.widthPixels - size * 1.6).toInt()
            y = (resources.displayMetrics.heightPixels * 0.55).toInt()
        }
        // Drag to move; a tap (little movement) opens ASKODOX.
        var startX = 0
        var startY = 0
        var touchX = 0f
        var touchY = 0f
        icon.setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    startX = lp.x; startY = lp.y; touchX = event.rawX; touchY = event.rawY; true
                }
                MotionEvent.ACTION_MOVE -> {
                    lp.x = startX + (event.rawX - touchX).toInt()
                    lp.y = startY + (event.rawY - touchY).toInt()
                    try { windowManager?.updateViewLayout(root, lp) } catch (_: Exception) {}
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (abs(event.rawX - touchX) < 10 * density && abs(event.rawY - touchY) < 10 * density) openApp()
                    true
                }
                else -> false
            }
        }
        try {
            windowManager?.addView(root, lp)
            bubble = root
            params = lp
        } catch (_: Exception) {
            bubble = null
        }
    }

    private fun hide() {
        val view = bubble ?: return
        try { windowManager?.removeView(view) } catch (_: Exception) {}
        bubble = null
    }

    private fun openApp() {
        hide()
        startActivity(
            Intent(this, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or Intent.FLAG_ACTIVITY_SINGLE_TOP),
        )
    }

    override fun onDestroy() {
        hide()
        instance = null
        super.onDestroy()
    }
}
