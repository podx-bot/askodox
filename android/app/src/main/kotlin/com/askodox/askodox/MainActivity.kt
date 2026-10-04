package com.askodox.askodox

import android.Manifest
import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageInstaller
import android.net.Uri
import android.provider.Settings
import android.content.pm.PackageManager
import android.location.Geocoder
import android.location.Location
import android.location.LocationManager
import android.media.MediaPlayer
import android.media.MediaRecorder
import android.os.Build
import android.os.Bundle
import android.speech.RecognizerIntent
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.speech.tts.Voice
import android.widget.Toast
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.Locale

class MainActivity : FlutterActivity() {
    private val updateChannel = "com.askodox.app/update"
    private val installStatusAction = "com.askodox.askodox.INSTALL_STATUS"
    // Device channel kept so native speech progress (word ranges) can reach
    // the ASKODOX friend's lip-sync in Dart.
    private var deviceMethods: MethodChannel? = null
    private val deviceChannel = "com.askodox.app/device"
    private val voiceRequestCode = 4301
    private val locationPermissionRequestCode = 4302
    private val microphonePermissionRequestCode = 4303
    private val notificationPermissionRequestCode = 4304
    private var pendingNotificationPermission: MethodChannel.Result? = null
    // Routine ASKODOX updates (seller replies, request status, price/stock)
    // are SILENT by default; "important" is reserved for time-critical ones.
    private val updatesChannelId = "askodox_updates"
    private val importantChannelId = "askodox_important"
    // A tapped notification opens this in-app route (read once by Dart).
    private var launchRoute: String? = null
    // Text / link another app shared to ASKODOX (Android "Share"), read once.
    private var sharedText: String? = null
    private val acknowledgementUtteranceId = "askodox_voice_acknowledgement"
    private val replyUtteranceId = "askodox_voice_reply"
    private var pendingVoiceResult: MethodChannel.Result? = null
    private var pendingLocationResult: MethodChannel.Result? = null
    private var pendingSpeechResult: MethodChannel.Result? = null
    private var textToSpeech: TextToSpeech? = null
    private var ttsReady = false

    // Main Chat voice: record in-app and let the backend's Sarvam-first
    // /api/in-app/voice/transcribe produce the transcript (Telugu, English,
    // mixed). The system RecognizerIntent is not used for Main Chat.
    private var pendingRecordingStart: MethodChannel.Result? = null
    private var recorder: MediaRecorder? = null
    private var recordingFile: File? = null
    private var mediaPlayer: MediaPlayer? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        initializeTextToSpeech()

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, updateChannel)
            .setMethodCallHandler { call, result ->
                if (call.method != "installApk") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val path = call.argument<String>("path")
                if (path.isNullOrBlank()) {
                    result.error("missing_path", "APK path missing", null)
                    return@setMethodCallHandler
                }
                val apk = File(path)
                if (!apk.isFile || apk.length() <= 0L) {
                    result.error("missing_apk", "Downloaded APK is missing or empty", null)
                    return@setMethodCallHandler
                }
                try {
                    // Primary: Android PackageInstaller session (no file path
                    // has to be shareable). Fallback: the system install intent.
                    installWithPackageInstaller(apk)
                    result.success(true)
                    return@setMethodCallHandler
                } catch (_: Exception) {
                }
                try {
                    val uri = FileProvider.getUriForFile(this, "$packageName.askodox.fileprovider", apk)
                    startActivity(Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
                        setDataAndType(uri, "application/vnd.android.package-archive")
                        addCategory(Intent.CATEGORY_DEFAULT)
                        addFlags(
                            Intent.FLAG_ACTIVITY_NEW_TASK or
                                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
                        )
                        putExtra(Intent.EXTRA_NOT_UNKNOWN_SOURCE, true)
                    })
                    result.success(true)
                } catch (e: Exception) {
                    result.error("install_failed", e.message, null)
                }
            }

        val device = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, deviceChannel)
        deviceMethods = device
        device
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "takeSharedText" -> {
                        result.success(sharedText)
                        sharedText = null
                    }
                    "startVoiceSearch" -> startVoiceSearch(call.argument("languageCode"), result)
                    "startVoiceRecording" -> startVoiceRecording(result)
                    "voiceRecordingLevel" -> result.success(currentRecordingLevel())
                    "stopVoiceRecording" -> stopVoiceRecording(result)
                    "cancelVoiceRecording" -> {
                        cancelVoiceRecording()
                        result.success(null)
                    }
                    "playReplyAudio" -> playReplyAudio(call.argument<ByteArray>("bytes"), result)
                    "replyAudioProgress" -> result.success(replyAudioProgress())
                    "stopSpeaking" -> {
                        stopSpeaking()
                        result.success(true)
                    }
                    "speakAcknowledgement" -> speakAcknowledgement(
                        call.argument("languageCode"),
                        call.argument("voicePreference"),
                        result,
                    )
                    "speakReply" -> speakText(
                        call.argument("text"),
                        call.argument("languageCode"),
                        call.argument("voicePreference"),
                        replyUtteranceId,
                        result,
                    )
                    "getCurrentLocation" -> getCurrentLocation(result)
                    "notificationsEnabled" -> result.success(NotificationManagerCompat.from(this).areNotificationsEnabled())
                    "requestNotificationPermission" -> requestNotificationPermission(result)
                    "openNotificationSettings" -> { openNotificationSettings(); result.success(true) }
                    "openAppSettings" -> { openAppSettings(); result.success(true) }
                    "showNotification" -> result.success(
                        showNotification(
                            call.argument<Int>("id") ?: 0,
                            call.argument<String>("title") ?: "ASKODOX",
                            call.argument<String>("body") ?: "",
                            call.argument<String>("route"),
                            call.argument<Boolean>("important") ?: false,
                        ),
                    )
                    "consumeLaunchRoute" -> { result.success(launchRoute); launchRoute = null }
                    "reverseGeocode" -> reverseGeocode(
                        call.argument<Double>("latitude"),
                        call.argument<Double>("longitude"),
                        result,
                    )
                    "geocodeName" -> geocodeName(call.argument<String>("query"), result)
                    "floatingBubbleStatus" -> result.success(
                        mapOf(
                            "supported" to (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O),
                            "canDrawOverlays" to AskodoxFloatingCompanionService.canDraw(this),
                            "running" to (AskodoxFloatingCompanionService.instance != null),
                        ),
                    )
                    "openOverlaySettings" -> {
                        startActivity(
                            Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName"))
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                        )
                        result.success(true)
                    }
                    "startFloatingBubble" -> result.success(startFloatingBubble())
                    "stopFloatingBubble" -> {
                        stopService(Intent(this, AskodoxFloatingCompanionService::class.java))
                        result.success(true)
                    }
                    "deviceHealth" -> result.success(deviceHealth())
                    // Screen Guide (opt-in accessibility service; see AskodoxScreenGuideService).
                    "screenGuideStatus" -> result.success(
                        mapOf(
                            "supported" to (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O),
                            // False in sideloaded phone-test builds: the service is only
                            // declared in Play-distributed builds (see AndroidManifest.xml).
                            "declared" to screenGuideDeclared(),
                            "accessibilityEnabled" to AskodoxScreenGuideService.isEnabled(this),
                            "connected" to (AskodoxScreenGuideService.instance != null),
                            "state" to AskodoxScreenGuideService.state,
                            "instruction" to AskodoxScreenGuideService.lastInstruction,
                        ),
                    )
                    "openAccessibilitySettings" -> {
                        startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        result.success(true)
                    }
                    "startScreenGuide" -> {
                        val sessionId = call.argument<String>("sessionId").orEmpty()
                        val token = call.argument<String>("token").orEmpty()
                        val baseUrl = call.argument<String>("baseUrl").orEmpty()
                        if (sessionId.isEmpty() || token.isEmpty() || !baseUrl.startsWith("https://")) {
                            result.success(false)
                        } else {
                            result.success(
                                AskodoxScreenGuideService.begin(
                                    AskodoxScreenGuideService.Session(
                                        sessionId, token, baseUrl,
                                        call.argument<String>("language") ?: "en",
                                        call.argument<Boolean>("voice") ?: true,
                                    ),
                                ),
                            )
                        }
                    }
                    "resumeScreenGuide" -> { AskodoxScreenGuideService.resume(); result.success(true) }
                    "stopScreenGuide" -> {
                        AskodoxScreenGuideService.end(call.argument<String>("outcome") ?: "abandoned")
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun screenGuideDeclared(): Boolean = try {
        packageManager.getServiceInfo(
            android.content.ComponentName(this, AskodoxScreenGuideService::class.java), 0,
        )
        true
    } catch (_: PackageManager.NameNotFoundException) {
        false
    }

    private fun initializeTextToSpeech() {
        textToSpeech = TextToSpeech(this) { status ->
            if (status != TextToSpeech.SUCCESS) {
                ttsReady = false
                return@TextToSpeech
            }
            val engine = textToSpeech ?: return@TextToSpeech
            val languageResult = engine.setLanguage(Locale.getDefault())
            ttsReady = languageResult != TextToSpeech.LANG_MISSING_DATA &&
                languageResult != TextToSpeech.LANG_NOT_SUPPORTED
            engine.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                override fun onStart(utteranceId: String?) {
                    if (utteranceId != replyUtteranceId) return
                    runOnUiThread { deviceMethods?.invokeMethod("speechStarted", null) }
                }

                // Word being spoken right now (API 26+): drives the friend's
                // mouth in sync with the device voice.
                override fun onRangeStart(utteranceId: String?, start: Int, end: Int, frame: Int) {
                    if (utteranceId != replyUtteranceId) return
                    runOnUiThread {
                        deviceMethods?.invokeMethod("speechRange", mapOf("start" to start, "end" to end))
                    }
                }

                override fun onDone(utteranceId: String?) {
                    if (utteranceId != acknowledgementUtteranceId && utteranceId != replyUtteranceId) return
                    runOnUiThread { finishSpeechResult(true) }
                }

                override fun onError(utteranceId: String?) {
                    if (utteranceId != acknowledgementUtteranceId && utteranceId != replyUtteranceId) return
                    runOnUiThread { finishSpeechResult(false) }
                }
            })
        }
    }

    private val askodoxIndianLanguageCodes = setOf(
        "as", "bn", "brx", "doi", "gu", "hi", "kn", "ks", "kok", "mai", "ml",
        "mni", "mr", "ne", "or", "pa", "sa", "sat", "sd", "ta", "te", "ur",
    )

    private fun localeFor(languageCode: String?): Locale {
        val normalized = languageCode?.trim()?.lowercase(Locale.ROOT)
        return when {
            normalized == "en" -> Locale.ENGLISH
            normalized != null && askodoxIndianLanguageCodes.contains(normalized) ->
                Locale(normalized, "IN")
            else -> Locale.getDefault()
        }
    }

    private fun voiceDeclaresPreference(voice: Voice, preference: String): Boolean {
        val normalized = preference.lowercase(Locale.ROOT)
        if (normalized != "male" && normalized != "female") return false
        return voice.features.orEmpty().any { feature ->
            val value = feature.lowercase(Locale.ROOT)
            value == normalized ||
                value == "gender=$normalized" ||
                value == "gender:$normalized" ||
                value == "voice_gender_$normalized"
        }
    }

    private fun selectCompatibleVoice(
        engine: TextToSpeech,
        locale: Locale,
        voicePreference: String?,
    ) {
        val voices = engine.voices ?: return
        val languageCandidates = voices.filter { voice ->
            voice.locale.language.equals(locale.language, ignoreCase = true)
        }
        if (languageCandidates.isEmpty()) return

        val normalizedPreference = voicePreference?.lowercase(Locale.ROOT) ?: "automatic"
        val explicitPreferenceCandidates = if (
            normalizedPreference == "male" || normalizedPreference == "female"
        ) {
            languageCandidates.filter { voice ->
                voiceDeclaresPreference(voice, normalizedPreference)
            }
        } else {
            emptyList()
        }

        // Android's standard Voice API does not expose gender. We only honor a
        // male/female preference when the TTS engine explicitly declares it in
        // voice features; otherwise we safely fall back without guessing names.
        val candidates = explicitPreferenceCandidates.ifEmpty { languageCandidates }
        val preferred = candidates.sortedWith(
            compareByDescending<Voice> { voice ->
                locale.country.isNotBlank() &&
                    voice.locale.country.equals(locale.country, ignoreCase = true)
            }
                .thenBy { it.isNetworkConnectionRequired }
                .thenByDescending { it.quality }
                .thenBy { it.latency }
                .thenBy { it.name },
        ).firstOrNull()

        if (preferred != null) {
            try {
                engine.voice = preferred
            } catch (_: Exception) {
                // Keep the engine-selected voice when a vendor rejects a voice.
            }
        }
    }

    private fun speakAcknowledgement(
        languageCode: String?,
        voicePreference: String?,
        result: MethodChannel.Result,
    ) {
        val locale = localeFor(languageCode)
        speakText(
            acknowledgementText(locale.language),
            languageCode,
            voicePreference,
            acknowledgementUtteranceId,
            result,
        )
    }

    private fun speakText(
        text: String?,
        languageCode: String?,
        voicePreference: String?,
        utteranceId: String,
        result: MethodChannel.Result,
    ) {
        val engine = textToSpeech
        if (!ttsReady || engine == null || text.isNullOrBlank()) {
            result.success(false)
            return
        }

        val locale = localeFor(languageCode)
        val languageResult = engine.setLanguage(locale)
        if (languageResult == TextToSpeech.LANG_MISSING_DATA ||
            languageResult == TextToSpeech.LANG_NOT_SUPPORTED
        ) {
            result.success(false)
            return
        }
        selectCompatibleVoice(engine, locale, voicePreference)

        pendingSpeechResult?.success(false)
        pendingSpeechResult = result
        engine.stop()
        val status = engine.speak(
            text,
            TextToSpeech.QUEUE_FLUSH,
            null,
            utteranceId,
        )
        if (status == TextToSpeech.ERROR) finishSpeechResult(false)
    }

    private fun acknowledgementText(languageCode: String): String = when (languageCode) {
        "te" -> "అర్థమైంది. మీ అభ్యర్థనను కొనసాగిస్తున్నాను."
        "hi" -> "समझ गया। आपकी रिक्वेस्ट आगे बढ़ा रहा हूँ।"
        "or" -> "ବୁଝିଲି। ଆପଣଙ୍କ ଅନୁରୋଧ ଜାରି ରଖୁଛି।"
        else -> "Got it. Continuing your request."
    }

    /** Position/duration of the Sarvam reply audio (lip-sync timing). */
    private fun replyAudioProgress(): Map<String, Int>? {
        val player = mediaPlayer ?: return null
        return try {
            mapOf("position" to player.currentPosition, "duration" to player.duration)
        } catch (_: Exception) {
            null
        }
    }

    private fun installWithPackageInstaller(source: File) {
        val installer = packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL).apply {
            setAppPackageName(packageName)
        }
        val sessionId = installer.createSession(params)
        installer.openSession(sessionId).use { session ->
            source.inputStream().use { input ->
                session.openWrite("ASKODOX-update.apk", 0L, source.length()).use { output ->
                    input.copyTo(output)
                    session.fsync(output)
                }
            }
            val callback = Intent(this, MainActivity::class.java).apply {
                action = installStatusAction
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            }
            val mutableFlag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0
            val sender = PendingIntent.getActivity(
                this, sessionId, callback, PendingIntent.FLAG_UPDATE_CURRENT or mutableFlag,
            ).intentSender
            session.commit(sender)
        }
    }

    private fun handleInstallStatus(statusIntent: Intent?) {
        if (statusIntent?.action != installStatusAction) return
        when (val status = statusIntent.getIntExtra(PackageInstaller.EXTRA_STATUS, Int.MIN_VALUE)) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                val confirmIntent: Intent? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    statusIntent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    statusIntent.getParcelableExtra(Intent.EXTRA_INTENT)
                }
                if (confirmIntent != null) {
                    confirmIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    startActivity(confirmIntent)
                } else {
                    Toast.makeText(this, "ASKODOX update needs install confirmation", Toast.LENGTH_LONG).show()
                }
            }
            PackageInstaller.STATUS_SUCCESS ->
                Toast.makeText(this, "ASKODOX update installed", Toast.LENGTH_SHORT).show()
            Int.MIN_VALUE -> Unit
            else -> {
                val message = statusIntent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)
                    ?: "Android installer failed (status $status)"
                Toast.makeText(this, message, Toast.LENGTH_LONG).show()
            }
        }
    }

    private fun finishSpeechResult(completed: Boolean) {
        val result = pendingSpeechResult ?: return
        pendingSpeechResult = null
        result.success(completed)
    }

    private fun startVoiceSearch(languageCode: String?, result: MethodChannel.Result) {
        if (pendingVoiceResult != null) {
            result.error("voice_busy", "Voice search is already active", null)
            return
        }
        try {
            pendingVoiceResult = result
            val locale = localeFor(languageCode)
            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, locale.toLanguageTag())
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, locale.toLanguageTag())
                putExtra(RecognizerIntent.EXTRA_PROMPT, "Ask ASKODOX")
                putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 3)
                // Give users enough time for natural Telugu/English/mixed requests.
                // Some Android recognizers otherwise finalize after ~1–2 seconds of silence.
                putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_MINIMUM_LENGTH_MILLIS, 10000L)
                putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 2500L)
                putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS, 1800L)
                putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            }
            startActivityForResult(intent, voiceRequestCode)
        } catch (e: Exception) {
            pendingVoiceResult = null
            result.error("voice_unavailable", e.message ?: "Speech recognition unavailable", null)
        }
    }

    private fun startVoiceRecording(result: MethodChannel.Result) {
        if (recorder != null || pendingRecordingStart != null) {
            result.error("voice_busy", "Voice recording is already active", null)
            return
        }
        // Interruption: when the user starts talking, ASKODOX stops speaking.
        stopSpeaking()
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            pendingRecordingStart = result
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.RECORD_AUDIO),
                microphonePermissionRequestCode,
            )
            return
        }
        beginRecording(result)
    }

    /**
     * Starts an in-app recording and returns true. The app decides when to
     * stop (genuine silence or the user's Stop) from voiceRecordingLevel;
     * native code never ends a recording on its own except when the app
     * leaves the foreground.
     */
    private fun beginRecording(result: MethodChannel.Result) {
        var file: File? = null
        var active: MediaRecorder? = null
        try {
            file = File.createTempFile("askodox_voice_", ".m4a", cacheDir)
            active = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                MediaRecorder(this)
            } else {
                @Suppress("DEPRECATION")
                MediaRecorder()
            }
            active.setAudioSource(MediaRecorder.AudioSource.VOICE_RECOGNITION)
            active.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            active.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            active.setAudioSamplingRate(16000)
            active.setAudioChannels(1)
            active.setAudioEncodingBitRate(64000)
            active.setOutputFile(file.absolutePath)
            active.prepare()
            active.start()
            recorder = active
            recordingFile = file
            result.success(true)
        } catch (e: Exception) {
            try { active?.release() } catch (_: Exception) {}
            file?.delete()
            recorder = null
            recordingFile = null
            result.error("voice_unavailable", e.message ?: "Microphone unavailable", null)
        }
    }

    /** Peak amplitude since the last call, or null when nothing is recording. */
    private fun currentRecordingLevel(): Int? {
        val active = recorder ?: return null
        return try { active.maxAmplitude } catch (_: Exception) { 0 }
    }

    private fun releaseRecorder(): Pair<File?, Boolean> {
        val active = recorder
        val file = recordingFile
        recorder = null
        recordingFile = null
        var stopped = false
        if (active != null) {
            stopped = try {
                active.stop()
                true
            } catch (_: Exception) {
                false // stop() throws when nothing usable was captured
            }
            try { active.release() } catch (_: Exception) {}
        }
        return Pair(file, stopped)
    }

    private fun stopVoiceRecording(result: MethodChannel.Result) {
        val (file, stopped) = releaseRecorder()
        if (!stopped || file == null || file.length() == 0L) {
            file?.delete()
            result.error("no_speech", "No speech was recorded", null)
            return
        }
        result.success(file.absolutePath)
    }

    private fun cancelVoiceRecording() {
        pendingRecordingStart?.success(false)
        pendingRecordingStart = null
        val (file, _) = releaseRecorder()
        file?.delete()
    }

    private fun stopSpeaking() {
        try { textToSpeech?.stop() } catch (_: Exception) {}
        val player = mediaPlayer
        mediaPlayer = null
        if (player != null) {
            try { player.stop() } catch (_: Exception) {}
            try { player.release() } catch (_: Exception) {}
        }
        finishSpeechResult(false)
    }

    /**
     * Plays reply audio produced by the backend's Sarvam Bulbul v3 TTS
     * (Ogg/Opus). Returns true when it finished playing; false when the
     * device cannot decode it or playback failed, so the app can fall back
     * to device TextToSpeech.
     */
    private fun playReplyAudio(bytes: ByteArray?, result: MethodChannel.Result) {
        if (bytes == null || bytes.isEmpty()) {
            result.success(false)
            return
        }
        stopSpeaking()
        var player: MediaPlayer? = null
        try {
            val file = File(cacheDir, "askodox_reply_audio.ogg")
            file.writeBytes(bytes)
            player = MediaPlayer()
            player.setDataSource(file.absolutePath)
            player.setOnCompletionListener { finished ->
                if (mediaPlayer === finished) mediaPlayer = null
                try { finished.release() } catch (_: Exception) {}
                finishSpeechResult(true)
            }
            player.setOnErrorListener { failed, _, _ ->
                if (mediaPlayer === failed) mediaPlayer = null
                try { failed.release() } catch (_: Exception) {}
                finishSpeechResult(false)
                true
            }
            player.prepare()
            pendingSpeechResult = result
            mediaPlayer = player
            player.start()
        } catch (e: Exception) {
            try { player?.release() } catch (_: Exception) {}
            if (mediaPlayer === player) mediaPlayer = null
            if (pendingSpeechResult === result) pendingSpeechResult = null
            result.success(false)
        }
    }


    private fun getCurrentLocation(result: MethodChannel.Result) {
        if (pendingLocationResult != null) {
            result.error("location_busy", "Location request is already active", null)
            return
        }
        val fine = ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION)
        val coarse = ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_COARSE_LOCATION)
        if (fine != PackageManager.PERMISSION_GRANTED && coarse != PackageManager.PERMISSION_GRANTED) {
            pendingLocationResult = result
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION),
                locationPermissionRequestCode,
            )
            return
        }
        returnLocation(result)
    }

    private fun returnLocation(result: MethodChannel.Result) {
        try {
            val manager = getSystemService(LOCATION_SERVICE) as LocationManager
            val providers = manager.getProviders(true)
            var best: Location? = null
            for (provider in providers) {
                val candidate = try { manager.getLastKnownLocation(provider) } catch (_: SecurityException) { null }
                if (candidate != null && (best == null || candidate.accuracy < best!!.accuracy)) best = candidate
            }
            if (best == null) {
                result.error("location_unavailable", "Turn on location and try again", null)
                return
            }
            result.success(mapOf(
                "latitude" to best!!.latitude,
                "longitude" to best!!.longitude,
                "accuracy" to best!!.accuracy.toDouble(),
            ))
        } catch (e: Exception) {
            result.error("location_failed", e.message ?: "Unable to read location", null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != voiceRequestCode) return
        val result = pendingVoiceResult ?: return
        pendingVoiceResult = null
        if (resultCode != Activity.RESULT_OK) {
            result.success(null)
            return
        }
        val values = data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)
        result.success(values?.firstOrNull())
    }

    // --------------------------------------------------------- location ----

    // Names the GPS point with the phone's own geocoder (no API key, works
    // on most Android phones). Returns null when the device cannot name it;
    // the app then asks the backend, and never invents a place.
    @Suppress("DEPRECATION")
    private fun reverseGeocode(latitude: Double?, longitude: Double?, result: MethodChannel.Result) {
        if (latitude == null || longitude == null || !Geocoder.isPresent()) {
            result.success(null)
            return
        }
        Thread {
            val place = try {
                Geocoder(this, Locale("en", "IN")).getFromLocation(latitude, longitude, 1)?.firstOrNull()
            } catch (_: Exception) {
                null
            }
            val named = place?.let {
                mapOf(
                    "subLocality" to it.subLocality,
                    "locality" to (it.locality ?: it.subAdminArea),
                    "adminArea" to it.adminArea,
                    "countryCode" to it.countryCode,
                )
            }
            runOnUiThread { result.success(named) }
        }.start()
    }

    // Finds a typed place ("vijayawada") with the phone's geocoder when the
    // backend search has nothing (Maps key without Geocoding / offline).
    @Suppress("DEPRECATION")
    private fun geocodeName(query: String?, result: MethodChannel.Result) {
        val text = query?.trim().orEmpty()
        if (text.length < 2 || !Geocoder.isPresent()) {
            result.success(emptyList<Map<String, Any?>>())
            return
        }
        Thread {
            val found = try {
                Geocoder(this, Locale("en", "IN")).getFromLocationName(text, 5) ?: emptyList()
            } catch (_: Exception) {
                emptyList()
            }
            val places = found.filter { it.countryCode == null || it.countryCode == "IN" }.map {
                mapOf(
                    "latitude" to it.latitude,
                    "longitude" to it.longitude,
                    "featureName" to it.featureName,
                    "locality" to (it.locality ?: it.subAdminArea),
                    "adminArea" to it.adminArea,
                )
            }
            runOnUiThread { result.success(places) }
        }.start()
    }

    // ------------------------------------------------------ notifications --

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        launchRoute = intent?.getStringExtra("askodox_route")
        captureShared(intent)
        handleInstallStatus(intent)
    }

    private fun captureShared(intent: Intent?) {
        if (intent?.action == Intent.ACTION_SEND && intent.type?.startsWith("text/") == true) {
            intent.getStringExtra(Intent.EXTRA_TEXT)?.take(4000)?.let { sharedText = it }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        intent.getStringExtra("askodox_route")?.let { launchRoute = it }
        captureShared(intent)
        handleInstallStatus(intent)
    }

    private fun ensureNotificationChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        manager.createNotificationChannel(
            NotificationChannel(updatesChannelId, "ASKODOX updates", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Seller replies, request status, price and availability changes (silent)"
                setSound(null, null)
                enableVibration(false)
            },
        )
        manager.createNotificationChannel(
            NotificationChannel(importantChannelId, "Important", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Security and time-critical account messages"
            },
        )
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        ) {
            result.success(NotificationManagerCompat.from(this).areNotificationsEnabled())
            return
        }
        pendingNotificationPermission?.success(false)
        pendingNotificationPermission = result
        ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.POST_NOTIFICATIONS), notificationPermissionRequestCode)
    }

    private fun openNotificationSettings() {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
        } else {
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", packageName, null))
        }
        startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    private fun openAppSettings() {
        startActivity(
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", packageName, null))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )
    }

    private fun showNotification(id: Int, title: String, body: String, route: String?, important: Boolean): Boolean {
        val manager = NotificationManagerCompat.from(this)
        if (!manager.areNotificationsEnabled()) return false
        ensureNotificationChannels()
        val open = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            if (!route.isNullOrBlank()) putExtra("askodox_route", route)
        }
        val tap = PendingIntent.getActivity(
            this, id, open, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = NotificationCompat.Builder(this, if (important) importantChannelId else updatesChannelId)
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(if (important) NotificationCompat.PRIORITY_HIGH else NotificationCompat.PRIORITY_LOW)
            .setSilent(!important)
            .setAutoCancel(true)
            .setContentIntent(tap)
            .build()
        return try {
            manager.notify(id, notification)
            true
        } catch (_: SecurityException) {
            false
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == notificationPermissionRequestCode) {
            val result = pendingNotificationPermission ?: return
            pendingNotificationPermission = null
            result.success(grantResults.any { it == PackageManager.PERMISSION_GRANTED })
            return
        }
        if (requestCode == microphonePermissionRequestCode) {
            val result = pendingRecordingStart ?: return
            pendingRecordingStart = null
            if (grantResults.any { it == PackageManager.PERMISSION_GRANTED }) {
                beginRecording(result)
            } else {
                result.error("mic_denied", "Microphone permission denied", null)
            }
            return
        }
        if (requestCode != locationPermissionRequestCode) return
        val result = pendingLocationResult ?: return
        pendingLocationResult = null
        if (grantResults.any { it == PackageManager.PERMISSION_GRANTED }) {
            returnLocation(result)
        } else {
            result.error("location_denied", "Location permission denied", null)
        }
    }

    // ----------------------------------------------------- floating bubble --

    // Started only while ASKODOX is on screen (Android 12+ forbids starting
    // a foreground service from the background) and only with the overlay
    // permission the user granted.
    private fun startFloatingBubble(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || !AskodoxFloatingCompanionService.canDraw(this)) return false
        return try {
            ContextCompat.startForegroundService(this, Intent(this, AskodoxFloatingCompanionService::class.java))
            true
        } catch (_: Exception) {
            false
        }
    }

    override fun onStart() {
        super.onStart()
        AskodoxFloatingCompanionService.instance?.setVisible(false)
    }

    override fun onStop() {
        AskodoxFloatingCompanionService.instance?.setVisible(true)
        super.onStop()
    }

    // ------------------------------------------------------- device health --

    // Battery, temperature, thermal state and memory for the in-app
    // performance panel (read-only, nothing leaves the phone).
    private fun deviceHealth(): Map<String, Any?> {
        val battery = registerReceiver(null, android.content.IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val level = battery?.getIntExtra(android.os.BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = battery?.getIntExtra(android.os.BatteryManager.EXTRA_SCALE, -1) ?: -1
        val status = battery?.getIntExtra(android.os.BatteryManager.EXTRA_STATUS, -1) ?: -1
        val temp = battery?.getIntExtra(android.os.BatteryManager.EXTRA_TEMPERATURE, Int.MIN_VALUE) ?: Int.MIN_VALUE
        val power = getSystemService(POWER_SERVICE) as android.os.PowerManager
        val activity = getSystemService(ACTIVITY_SERVICE) as android.app.ActivityManager
        val memory = android.app.ActivityManager.MemoryInfo().also { activity.getMemoryInfo(it) }
        return mapOf(
            "batteryPercent" to (if (level >= 0 && scale > 0) level * 100 / scale else null),
            "charging" to (status == android.os.BatteryManager.BATTERY_STATUS_CHARGING ||
                status == android.os.BatteryManager.BATTERY_STATUS_FULL),
            "batteryTempC" to (if (temp != Int.MIN_VALUE) temp / 10.0 else null),
            "thermalStatus" to (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) power.currentThermalStatus else null),
            "powerSave" to power.isPowerSaveMode,
            "appPssKb" to android.os.Debug.getPss(),
            "deviceAvailMb" to memory.availMem / (1024 * 1024),
            "deviceTotalMb" to memory.totalMem / (1024 * 1024),
            "lowMemory" to memory.lowMemory,
            "memoryClassMb" to activity.memoryClass,
            "sdk" to Build.VERSION.SDK_INT,
            "model" to "${Build.MANUFACTURER} ${Build.MODEL}",
            "processUptimeMs" to (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N)
                android.os.SystemClock.elapsedRealtime() - android.os.Process.getStartElapsedRealtime() else null),
        )
    }

    override fun onPause() {
        // Leaving the app (call, home button) cancels an in-flight recording
        // instead of silently recording in the background.
        if (recorder != null) cancelVoiceRecording()
        super.onPause()
    }

    override fun onDestroy() {
        deviceMethods = null
        cancelVoiceRecording()
        try { mediaPlayer?.release() } catch (_: Exception) {}
        mediaPlayer = null
        pendingSpeechResult?.success(false)
        pendingSpeechResult = null
        textToSpeech?.stop()
        textToSpeech?.shutdown()
        textToSpeech = null
        ttsReady = false
        super.onDestroy()
    }
}
