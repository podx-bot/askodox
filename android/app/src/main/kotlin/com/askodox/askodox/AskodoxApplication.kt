package com.askodox.askodox

import android.app.Application
import java.io.File

/**
 * ASKODOX's own Application class. Besides giving the app a named identity it
 * keeps a short record of the last native crash (exception type + the top
 * stack frames; no messages, numbers or user data) so the next start can
 * report WHY the app closed (sign-in diagnostics, `takeLastCrash`).
 */
class AskodoxApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, error ->
            try {
                recordCrash(thread, error)
            } catch (_: Throwable) {
            }
            previous?.uncaughtException(thread, error)
        }
    }

    private fun recordCrash(thread: Thread, error: Throwable) {
        val root = generateSequence(error) { it.cause }.last()
        val frames = (root.stackTrace.take(6) + error.stackTrace.take(2))
            .joinToString(";") { "${it.className.substringAfterLast('.')}.${it.methodName}:${it.lineNumber}" }
        val text = "type=${error.javaClass.simpleName} root=${root.javaClass.simpleName} thread=${thread.name.take(20)} at=$frames"
        File(filesDir, CRASH_FILE).writeText(text.replace(Regex("\\d{5,}"), "#").take(900))
    }

    companion object {
        const val CRASH_FILE = "askodox_last_crash.txt"

        /** The last recorded crash (read once, then removed). */
        fun takeLastCrash(app: Application): String? {
            val file = File(app.filesDir, CRASH_FILE)
            if (!file.exists()) return null
            return try { file.readText() } catch (_: Exception) { null } finally { file.delete() }
        }
    }
}
