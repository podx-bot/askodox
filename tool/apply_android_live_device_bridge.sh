#!/usr/bin/env bash
set -euo pipefail

MANIFEST="android/app/src/main/AndroidManifest.xml"
RES_XML="android/app/src/main/res/xml"
KOTLIN_DIR="android/app/src/main/kotlin/com/askodox/askodox"
mkdir -p "$KOTLIN_DIR" "$RES_XML"

# Keep the FileProvider root deterministic. The native bridge always copies the
# downloaded APK into cacheDir/askodox_updates before asking Android to install
# it, so Dart/path_provider implementation details cannot break the hand-off.
cat > "$RES_XML/askodox_update_paths.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<paths xmlns:android="http://schemas.android.com/apk/res/android">
    <cache-path name="askodox_updates" path="askodox_updates/" />
</paths>
EOF

cat > "$KOTLIN_DIR/MainActivity.kt" <<'EOF'
package com.askodox.askodox

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import android.speech.RecognizerIntent
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
    private var pendingVoiceResult: MethodChannel.Result? = null
    private var pendingLocationResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, updateChannel)
            .setMethodCallHandler { call, result ->
                if (call.method != "installApk") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val sourcePath = call.argument<String>("path")
                if (sourcePath.isNullOrBlank()) {
                    result.error("missing_path", "APK path missing", null)
                    return@setMethodCallHandler
                }
                try {
                    val source = File(sourcePath)
                    if (!source.isFile || source.length() <= 0L) {
                        result.error("missing_apk", "Downloaded APK is missing or empty", null)
                        return@setMethodCallHandler
                    }

                    // HARD GUARANTEE: FileProvider exposes only this exact cache
                    // subtree. Always copy the APK here before creating its URI.
                    // This avoids code_cache/files/temp-directory differences on
                    // Samsung and other Android builds.
                    val updateDir = File(cacheDir, "askodox_updates")
                    if (!updateDir.exists() && !updateDir.mkdirs()) {
                        result.error("cache_create_failed", "Unable to create update cache", null)
                        return@setMethodCallHandler
                    }
                    val installApk = File(updateDir, "askodox-update.apk")
                    if (installApk.exists()) installApk.delete()
                    source.inputStream().use { input ->
                        installApk.outputStream().use { output -> input.copyTo(output) }
                    }
                    if (!installApk.isFile || installApk.length() != source.length()) {
                        result.error("apk_copy_failed", "Unable to prepare APK for installer", null)
                        return@setMethodCallHandler
                    }

                    val uri = FileProvider.getUriForFile(
                        this,
                        "$packageName.askodox.fileprovider",
                        installApk,
                    )
                    val intent = Intent(Intent.ACTION_VIEW).apply {
                        setDataAndType(uri, "application/vnd.android.package-archive")
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        clipData = android.content.ClipData.newRawUri("ASKODOX update", uri)
                    }
                    startActivity(intent)
                    result.success(true)
                } catch (e: Exception) {
                    result.error("install_failed", e.message ?: e.javaClass.simpleName, null)
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, deviceChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startVoiceSearch" -> startVoiceSearch(result)
                    "getCurrentLocation" -> getCurrentLocation(result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun startVoiceSearch(result: MethodChannel.Result) {
        if (pendingVoiceResult != null) {
            result.error("voice_busy", "Voice search is already active", null)
            return
        }
        try {
            pendingVoiceResult = result
            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, Locale.getDefault())
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
}
EOF

python3 - "$MANIFEST" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
permissions = [
    'android.permission.INTERNET',
    'android.permission.REQUEST_INSTALL_PACKAGES',
    'android.permission.ACCESS_FINE_LOCATION',
    'android.permission.ACCESS_COARSE_LOCATION',
]
for permission in permissions:
    if permission not in s:
        s = s.replace('<application', f'<uses-permission android:name="{permission}" />\n    <application', 1)

provider='''        <provider
            android:name="androidx.core.content.FileProvider"
            android:authorities="${applicationId}.askodox.fileprovider"
            android:exported="false"
            android:grantUriPermissions="true">
            <meta-data
                android:name="android.support.FILE_PROVIDER_PATHS"
                android:resource="@xml/askodox_update_paths" />
        </provider>'''
if '.askodox.fileprovider' not in s:
    s = s.replace('</application>', provider + '\n    </application>', 1)
p.write_text(s)
PY

echo 'ASKODOX hard update handoff, internet, voice and device location bridge applied.'
