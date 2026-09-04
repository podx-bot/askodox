package com.askodox.askodox

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
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
    private val acknowledgementUtteranceId = "askodox_voice_acknowledgement"
    private var pendingVoiceResult: MethodChannel.Result? = null
    private var pendingLocationResult: MethodChannel.Result? = null
    private var pendingSpeechResult: MethodChannel.Result? = null
    private var textToSpeech: TextToSpeech? = null
    private var ttsReady = false

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
                    startActivity(Intent(Intent.ACTION_VIEW).apply {
                        setDataAndType(uri, "application/vnd.android.package-archive")
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION)
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
                    "speakAcknowledgement" -> speakAcknowledgement(
                        call.argument("languageCode"),
                        call.argument("voicePreference"),
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
                    if (utteranceId != acknowledgementUtteranceId) return
                    runOnUiThread { finishSpeechResult(true) }
                }

                override fun onError(utteranceId: String?) {
                    if (utteranceId != acknowledgementUtteranceId) return
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
        val engine = textToSpeech
        if (!ttsReady || engine == null) {
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
            acknowledgementText(locale.language),
            TextToSpeech.QUEUE_FLUSH,
            null,
            acknowledgementUtteranceId,
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
            }
            startActivityForResult(intent, voiceRequestCode)
        } catch (e: Exception) {
            pendingVoiceResult = null
            result.error("voice_unavailable", e.message ?: "Speech recognition unavailable", null)
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
        if (requestCode != locationPermissionRequestCode) return
        val result = pendingLocationResult ?: return
        pendingLocationResult = null
        if (grantResults.any { it == PackageManager.PERMISSION_GRANTED }) {
            returnLocation(result)
        } else {
            result.error("location_denied", "Location permission denied", null)
        }
    }

    override fun onDestroy() {
        pendingSpeechResult?.success(false)
        pendingSpeechResult = null
        textToSpeech?.stop()
        textToSpeech?.shutdown()
        textToSpeech = null
        ttsReady = false
        super.onDestroy()
    }
}
