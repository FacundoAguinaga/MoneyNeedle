package com.moneyneedle.moneyneedle_app

import android.content.Intent
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** STT nativo offline-first vía SpeechRecognizer.
 *  Canal "moneyneedle/stt": isAvailable() / listen() -> texto final | error.
 *  El permiso RECORD_AUDIO lo pide Flutter (permission_handler) antes de llamar.
 */
class MainActivity : FlutterActivity() {
    private val channel = "moneyneedle/stt"
    private var recognizer: SpeechRecognizer? = null
    private var pending: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isAvailable" -> result.success(SpeechRecognizer.isRecognitionAvailable(this))
                    "listen" -> startListening(result)
                    "stop" -> stopListening()
                    else -> result.notImplemented()
                }
            }
    }

    private fun startListening(result: MethodChannel.Result) {
        if (pending != null) {
            result.error("BUSY", "ya hay una escucha en curso", null)
            return
        }
        if (!SpeechRecognizer.isRecognitionAvailable(this)) {
            result.error("NO_ENGINE", "sin motor de reconocimiento en el device", null)
            return
        }
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, "es-AR")
            putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, false)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
        }
        pending = result
        recognizer = SpeechRecognizer.createSpeechRecognizer(this).apply {
            setRecognitionListener(object : RecognitionListener {
                override fun onResults(b: Bundle?) {
                    val text = b?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()
                    if (text.isNullOrBlank()) {
                        pending?.error("EMPTY", "sin texto reconocido", null)
                    } else {
                        pending?.success(text)
                    }
                    cleanup()
                }
                override fun onError(code: Int) {
                    // 6=silencio, 7=sin match, 8=ocupado, 13=sin permiso.
                    pending?.error("STT_$code", "falló el reconocimiento: $code", null)
                    cleanup()
                }
                override fun onReadyForSpeech(b: Bundle?) {}
                override fun onBeginningOfSpeech() {}
                override fun onRmsChanged(v: Float) {}
                override fun onBufferReceived(b: ByteArray?) {}
                override fun onEndOfSpeech() {}
                override fun onPartialResults(b: Bundle?) {}
                override fun onEvent(t: Int, b: Bundle?) {}
            })
            startListening(intent)
        }
    }

    private fun stopListening() {
        try {
            recognizer?.stopListening()
        } catch (_: Exception) {
        }
    }

    private fun cleanup() {
        pending = null
        try {
            recognizer?.destroy()
        } catch (_: Exception) {
        }
        recognizer = null
    }

    override fun onDestroy() {
        cleanup()
        super.onDestroy()
    }
}
