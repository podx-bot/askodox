package com.askodox.askodox

import android.app.Activity
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.SoundPool
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Work Mode game audio (owner 2026-11-10): short sounds mixed by SoundPool, ONE looping music
 * track and short voice lines, all from small files the app ships as Flutter assets. Dart sends a
 * file's bytes once ("prepare"); it is kept in the cache folder. Plays on the media stream with
 * game usage and never touches the reply voice player.
 */
object AskodoxGameAudio {
    private const val CHANNEL = "com.askodox.app/game_audio"
    private var pool: SoundPool? = null
    private val ids = HashMap<String, Int>()
    private val ready = HashSet<Int>()
    private var music: MediaPlayer? = null
    private var musicName: String? = null
    private var voice: MediaPlayer? = null

    fun register(activity: Activity, messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "has" -> result.success(file(activity, call.argument<String>("name") ?: "").exists())
                    "prepare" -> result.success(
                        prepare(activity, call.argument<String>("name") ?: "", call.argument<ByteArray>("bytes"),
                            call.argument<Boolean>("short") ?: true),
                    )
                    "play" -> result.success(play(call.argument<String>("name") ?: "", volume(call.argument("volume"), 0.8f)))
                    "voice" -> result.success(voice(activity, call.argument<String>("name") ?: "", volume(call.argument("volume"), 1f)))
                    "music" -> result.success(music(activity, call.argument<String>("name"), volume(call.argument("volume"), 0.3f)))
                    "stop" -> {
                        stopAll()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.success(false)
            }
        }
    }

    private fun volume(raw: Any?, fallback: Float): Float =
        ((raw as? Number)?.toFloat() ?: fallback).coerceIn(0f, 1f)

    private fun file(activity: Activity, name: String): File {
        val safe = name.replace(Regex("[^a-z0-9_]"), "")
        val dir = File(activity.cacheDir, "game_audio")
        dir.mkdirs()
        return File(dir, "$safe.ogg")
    }

    private fun attributes(): AudioAttributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_GAME)
        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
        .build()

    private fun soundPool(): SoundPool {
        pool?.let { return it }
        val created = SoundPool.Builder().setMaxStreams(4).setAudioAttributes(attributes()).build()
        created.setOnLoadCompleteListener { _, id, status -> if (status == 0) ready.add(id) }
        pool = created
        return created
    }

    /** Writes the file once; a short sound is also loaded into the mixer. */
    private fun prepare(activity: Activity, name: String, bytes: ByteArray?, short: Boolean): Boolean {
        if (name.isEmpty()) return false
        val target = file(activity, name)
        if (bytes != null && (!target.exists() || target.length() != bytes.size.toLong())) target.writeBytes(bytes)
        if (!target.exists()) return false
        if (short && !ids.containsKey(name)) ids[name] = soundPool().load(target.path, 1)
        return true
    }

    private fun play(name: String, volume: Float): Boolean {
        val id = ids[name] ?: return false
        if (!ready.contains(id)) return false
        return soundPool().play(id, volume, volume, 1, 0, 1f) != 0
    }

    private fun voice(activity: Activity, name: String, volume: Float): Boolean {
        val target = file(activity, name)
        if (!target.exists()) return false
        voice?.release()
        voice = MediaPlayer().apply {
            setAudioAttributes(attributes())
            setDataSource(target.path)
            setVolume(volume, volume)
            setOnCompletionListener { it.release(); if (voice === it) voice = null }
            prepare()
            start()
        }
        return true
    }

    /** null name = music off. The same track keeps playing (no restart). */
    private fun music(activity: Activity, name: String?, volume: Float): Boolean {
        if (name == null || name.isEmpty()) {
            music?.release()
            music = null
            musicName = null
            return true
        }
        if (name == musicName && music != null) {
            music?.setVolume(volume, volume)
            return true
        }
        val target = file(activity, name)
        if (!target.exists()) return false
        music?.release()
        music = MediaPlayer().apply {
            setAudioAttributes(attributes())
            setDataSource(target.path)
            isLooping = true
            setVolume(volume, volume)
            prepare()
            start()
        }
        musicName = name
        return true
    }

    private fun stopAll() {
        music?.release()
        music = null
        musicName = null
        voice?.release()
        voice = null
        pool?.autoPause()
    }
}
