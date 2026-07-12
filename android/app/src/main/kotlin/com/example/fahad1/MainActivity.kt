package com.example.fahad1

import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.res.Configuration
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.speech.tts.TextToSpeech
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

class MainActivity : FlutterActivity(), TextToSpeech.OnInitListener {
    private val speechChannelName = "csexam_qr_attendance/speech"
    private val lockedModeChannelName = "aust_exam/locked_mode"
    private var textToSpeech: TextToSpeech? = null
    private var speechReady = false
    private var pendingSpeech: String? = null
    private var lockedModeEnabled = false
    private var lockedChannel: MethodChannel? = null
    private val sharedFileChannelName = "aust_import/shared"
    private var sharedChannel: MethodChannel? = null
    private var pendingSharedText: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        ensureTextToSpeech()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ensureTextToSpeech()
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            speechChannelName,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "speak" -> {
                    speak(call.argument<String>("message").orEmpty())
                    result.success(null)
                }
                "stop" -> {
                    pendingSpeech = null
                    textToSpeech?.stop()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        lockedChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            lockedModeChannelName,
        )
        lockedChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "enable" -> {
                    enableLockedMode()
                    result.success(null)
                }
                "disable" -> {
                    disableLockedMode()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        // Shared-file import: read the text of a file the app was opened with
        // (WhatsApp / Files → Open with AUST Portal) so Flutter can import it.
        sharedChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            sharedFileChannelName,
        )
        sharedChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getPending" -> {
                    val text = pendingSharedText
                    pendingSharedText = null
                    result.success(text)
                }
                else -> result.notImplemented()
            }
        }
        // Capture the launch intent (cold start via "Open with").
        pendingSharedText = extractSharedText(intent) ?: pendingSharedText
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val text = extractSharedText(intent)
        if (text != null) {
            pendingSharedText = text
            sharedChannel?.invokeMethod("onShared", null)
        }
    }

    /// Reads the UTF-8 text of a file the activity was opened/shared with.
    private fun extractSharedText(intent: Intent?): String? {
        if (intent == null) return null
        val uri: Uri? = when (intent.action) {
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND -> {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra(Intent.EXTRA_STREAM) as? Uri
            }
            else -> null
        }
        if (uri == null) return null
        return try {
            contentResolver.openInputStream(uri)?.bufferedReader()?.use { it.readText() }
        } catch (e: Exception) {
            null
        }
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus && lockedModeEnabled) {
            hideSystemBars()
        }
    }

    // Split-screen / multi-window during a locked attempt is a bypass — tell
    // Flutter so it can count a warning / auto-submit. (resizeableActivity is
    // also false to block it on most devices.)
    override fun onMultiWindowModeChanged(
        isInMultiWindowMode: Boolean,
        newConfig: Configuration?,
    ) {
        super.onMultiWindowModeChanged(isInMultiWindowMode, newConfig)
        if (isInMultiWindowMode && lockedModeEnabled) {
            lockedChannel?.invokeMethod("lockBreak", "Split screen detected")
        }
    }

    override fun onInit(status: Int) {
        if (status != TextToSpeech.SUCCESS) return
        speechReady = true
        textToSpeech?.language = Locale.US
        textToSpeech?.setPitch(1.0f)
        textToSpeech?.setSpeechRate(0.92f)
        pendingSpeech?.let { message ->
            pendingSpeech = null
            speak(message)
        }
    }

    override fun onDestroy() {
        textToSpeech?.stop()
        textToSpeech?.shutdown()
        textToSpeech = null
        super.onDestroy()
    }

    private fun ensureTextToSpeech() {
        if (textToSpeech == null) {
            textToSpeech = TextToSpeech(this, this)
        }
    }

    private fun speak(message: String) {
        val text = message.trim()
        if (text.isEmpty()) return
        val engine = textToSpeech
        if (engine == null || !speechReady) {
            pendingSpeech = text
            return
        }
        engine.stop()
        engine.speak(text, TextToSpeech.QUEUE_FLUSH, null, "attendance_prompt")
    }

    private fun enableLockedMode() {
        lockedModeEnabled = true
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
        hideSystemBars()
        try {
            startLockTask()
        } catch (_: Exception) {
            // Lock task needs screen pinning or device-owner approval.
        }
    }

    private fun disableLockedMode() {
        lockedModeEnabled = false
        try {
            stopLockTask()
        } catch (_: Exception) {
            // Ignore if lock task was not active.
        }
        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
        showSystemBars()
    }

    private fun hideSystemBars() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.insetsController?.let { controller ->
                controller.hide(
                    WindowInsets.Type.statusBars() or
                        WindowInsets.Type.navigationBars(),
                )
                controller.systemBarsBehavior =
                    WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            }
        } else {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility =
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or
                    View.SYSTEM_UI_FLAG_FULLSCREEN or
                    View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                    View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                    View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
                    View.SYSTEM_UI_FLAG_LAYOUT_STABLE
        }
    }

    private fun showSystemBars() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.insetsController?.show(
                WindowInsets.Type.statusBars() or WindowInsets.Type.navigationBars(),
            )
        }
        @Suppress("DEPRECATION")
        window.decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_VISIBLE
    }
}
