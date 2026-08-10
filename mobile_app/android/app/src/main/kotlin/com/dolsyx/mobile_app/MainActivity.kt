package com.dolsyx.mobile_app

import android.app.PictureInPictureParams
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.res.Configuration
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.util.Rational
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val SCREEN_SHARE_CHANNEL = "com.dolsyx/screen_share"
    private val PIP_CHANNEL = "com.dolsyx/pip"
    private val SHARE_CHANNEL = "com.dolsyx/share"

    private var isCallActive = false
    private var pipMethodChannel: MethodChannel? = null
    private var shareMethodChannel: MethodChannel? = null
    private var initialSharedData: Map<String, Any?>? = null

    private val taskRemovedReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            pipMethodChannel?.invokeMethod("onCallTaskRemoved", null)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
        val filter = IntentFilter("com.dolsyx.ACTION_CALL_ENDED_TASK_REMOVED")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(taskRemovedReceiver, filter, RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(taskRemovedReceiver, filter)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        try {
            unregisterReceiver(taskRemovedReceiver)
        } catch (_: Exception) {}
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
        initialSharedData?.let { data ->
            shareMethodChannel?.invokeMethod("onSharedDataReceived", data)
        }
    }

    private fun handleIntent(intent: Intent?) {
        if (intent == null) return
        val action = intent.action
        val type = intent.type ?: ""

        if (Intent.ACTION_SEND == action) {
            if ("text/plain" == type) {
                val sharedText = intent.getStringExtra(Intent.EXTRA_TEXT)
                if (!sharedText.isNullOrEmpty()) {
                    initialSharedData = mapOf("type" to "text", "text" to sharedText)
                }
            } else if (intent.hasExtra(Intent.EXTRA_STREAM)) {
                val uri = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
                if (uri != null) {
                    initialSharedData = mapOf("type" to "media", "uris" to listOf(uri.toString()))
                }
            }
        } else if (Intent.ACTION_SEND_MULTIPLE == action && intent.hasExtra(Intent.EXTRA_STREAM)) {
            val uris = intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
            if (!uris.isNullOrEmpty()) {
                val uriStrings = uris.map { it.toString() }
                initialSharedData = mapOf("type" to "media", "uris" to uriStrings)
            }
        }
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SCREEN_SHARE_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "startScreenShareService") {
                val serviceIntent = Intent(this, ScreenCaptureService::class.java)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    startForegroundService(serviceIntent)
                } else {
                    startService(serviceIntent)
                }
                result.success(null)
            } else if (call.method == "stopScreenShareService") {
                val serviceIntent = Intent(this, ScreenCaptureService::class.java)
                stopService(serviceIntent)
                result.success(null)
            } else {
                result.notImplemented()
            }
        }

        pipMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PIP_CHANNEL)
        pipMethodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "enterPip" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        try {
                            val params = PictureInPictureParams.Builder()
                                .setAspectRatio(Rational(9, 16))
                                .build()
                            enterPictureInPictureMode(params)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("PIP_ERROR", e.message, null)
                        }
                    } else {
                        result.success(false)
                    }
                }
                "setCallActive" -> {
                    val active = call.argument<Boolean>("active") ?: false
                    isCallActive = active
                    updateCallState(active)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        shareMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SHARE_CHANNEL)
        shareMethodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialSharedData" -> {
                    result.success(initialSharedData)
                    initialSharedData = null
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun updateCallState(active: Boolean) {
        val serviceIntent = Intent(this, CallForegroundService::class.java)
        if (active) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(serviceIntent)
            } else {
                startService(serviceIntent)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                try {
                    val params = PictureInPictureParams.Builder()
                        .setAspectRatio(Rational(9, 16))
                        .setAutoEnterEnabled(true)
                        .build()
                    setPictureInPictureParams(params)
                } catch (_: Exception) {}
            }
        } else {
            stopService(serviceIntent)
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (isCallActive && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                val params = PictureInPictureParams.Builder()
                    .setAspectRatio(Rational(9, 16))
                    .build()
                enterPictureInPictureMode(params)
            } catch (_: Exception) {}
        }
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        pipMethodChannel?.invokeMethod("onPipChanged", isInPictureInPictureMode)
    }
}
