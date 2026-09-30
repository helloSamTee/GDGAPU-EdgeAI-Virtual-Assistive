package com.example.gdg_edge_ai

import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterActivity() {
    private val volumeChannel = "gdg_edge_ai/volume_keys"
    private var eventSink: EventChannel.EventSink? = null

	override fun configureFlutterEngine(flutterEngine: io.flutter.embedding.engine.FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)
		EventChannel(flutterEngine.dartExecutor.binaryMessenger, volumeChannel)
			.setStreamHandler(object : EventChannel.StreamHandler {
				override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
					eventSink = events
				}

				override fun onCancel(arguments: Any?) {
					eventSink = null
				}
			})
	}

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (keyCode != KeyEvent.KEYCODE_VOLUME_UP &&
            keyCode != KeyEvent.KEYCODE_VOLUME_DOWN
        ) {
            return super.onKeyDown(keyCode, event)
        }

        if (event?.repeatCount != 0) return true

        val eventType = if (keyCode == KeyEvent.KEYCODE_VOLUME_UP) {
            "action"
        } else {
            "switchTab"
        }
        eventSink?.success(mapOf("type" to eventType))

        return true
    }
	override fun onDestroy() {
		super.onDestroy()
	}
}
