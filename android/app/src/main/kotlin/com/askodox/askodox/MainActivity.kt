package com.askodox.askodox

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
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
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.Locale

class MainActivity : FlutterActivity() {
    private val updateChannel = "com.askodox.app/update"
    private val deviceChannel = "com.askodox.app/device"
    private val voiceRequestCode = 4301
    private val locationPermissionRequestCode = 4302
    private val microphonePermissionRequestCode = 4303
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
                try {
                    val apk = File(path)
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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, deviceChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startVoiceSearch" -> startVoiceSearch(call.argument("languageCode"), result)
                    "startVoiceRecording" -> startVoiceRecording(result)
                    "voiceRecordingLevel" -> result.success(currentRecordingLevel())
                    "stopVoiceRecording" -> stopVoiceRecording(result)
                    "cancelVoiceRecording" -> {
                        cancelVoiceRecording()
                        result.success(null)
                    }
                    "playReplyAudio" -> playReplyAudio(call.argument<ByteArray>("bytes"), result)
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
                    else -> result.notImplemented()
                }
            }
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
                override fun onStart(utteranceId: String?) = Unit

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

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
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

    override fun onPause() {
        // Leaving the app (call, home button) cancels an in-flight recording
        // instead of silently recording in the background.
        if (recorder != null) cancelVoiceRecording()
        super.onPause()
    }

    override fun onDestroy() {
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
