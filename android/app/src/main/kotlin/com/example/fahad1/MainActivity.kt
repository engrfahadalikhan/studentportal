package com.example.fahad1

import android.os.Bundle
import android.speech.tts.TextToSpeech
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

class MainActivity : FlutterActivity(), TextToSpeech.OnInitListener {
    private val speechChannelName = "csexam_qr_attendance/speech"
    private var textToSpeech: TextToSpeech? = null
    private var speechReady = false
    private var pendingSpeech: String? = null

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
}
