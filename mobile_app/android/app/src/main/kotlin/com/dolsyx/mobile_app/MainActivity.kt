package com.dolsyx.mobile_app

import android.app.PictureInPictureParams
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.res.Configuration
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.util.Rational
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

class MainActivity : FlutterFragmentActivity() {
    private val SCREEN_SHARE_CHANNEL = "com.dolsyx/screen_share"
    private val PIP_CHANNEL = "com.dolsyx/pip"
    private val SHARE_CHANNEL = "com.dolsyx/share"
    private val RINGTONE_CHANNEL = "com.dolsyx/ringtones"
    private val VIDEO_THUMBNAIL_CHANNEL = "com.dolsyx/video_thumbnail"
    private val thumbnailExecutor = Executors.newFixedThreadPool(4)

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

    private fun resolveUriPath(uriStr: String): String {
        return try {
            val uri = Uri.parse(uriStr)
            if ("content".equals(uri.scheme, ignoreCase = true)) {
                val inputStream = contentResolver.openInputStream(uri)
                val ext = contentResolver.getType(uri)?.let { mime ->
                    if (mime.contains("video")) ".mp4" else if (mime.contains("image")) ".jpg" else ".tmp"
                } ?: ".tmp"
                val tempFile = java.io.File.createTempFile("shared_media_", ext, cacheDir)
                tempFile.deleteOnExit()
                val outputStream = java.io.FileOutputStream(tempFile)
                inputStream?.use { input ->
                    outputStream.use { output ->
                        input.copyTo(output)
                    }
                }
                tempFile.absolutePath
            } else {
                uri.path ?: uriStr
            }
        } catch (e: Exception) {
            uriStr
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
                    val resolvedPath = resolveUriPath(uri.toString())
                    initialSharedData = mapOf("type" to "media", "uris" to listOf(resolvedPath))
                }
            }
        } else if (Intent.ACTION_SEND_MULTIPLE == action && intent.hasExtra(Intent.EXTRA_STREAM)) {
            val uris = intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
            if (!uris.isNullOrEmpty()) {
                val resolvedPaths = uris.map { resolveUriPath(it.toString()) }
                initialSharedData = mapOf("type" to "media", "uris" to resolvedPaths)
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
                "resolveContentUri" -> {
                    val uriStr = call.argument<String>("uri") ?: ""
                    result.success(resolveUriPath(uriStr))
                }
                else -> result.notImplemented()
            }
        }

        val securityChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.dolsyx/security")
        securityChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "enableSecure" -> {
                    window.addFlags(android.view.WindowManager.LayoutParams.FLAG_SECURE)
                    result.success(true)
                }
                "disableSecure" -> {
                    window.clearFlags(android.view.WindowManager.LayoutParams.FLAG_SECURE)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // Ringtone / Notification sound lister via RingtoneManager
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, RINGTONE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getNotificationSounds" -> {
                    result.success(getSystemSounds(RingtoneManager.TYPE_NOTIFICATION))
                }
                "getRingtones" -> {
                    result.success(getSystemSounds(RingtoneManager.TYPE_RINGTONE))
                }
                "playTone" -> {
                    val uriStr = call.argument<String>("uri")
                    try {
                        activeRingtone?.stop()
                        if (uriStr != null && uriStr.isNotEmpty()) {
                            val uri = Uri.parse(uriStr)
                            val ringtone = RingtoneManager.getRingtone(this, uri)
                            ringtone?.play()
                            activeRingtone = ringtone
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("PLAY_ERROR", e.message, null)
                    }
                }
                "stopTone" -> {
                    try {
                        activeRingtone?.stop()
                        activeRingtone = null
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("STOP_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // Fast video thumbnail & duration extractor using hardware MediaMetadataRetriever
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, VIDEO_THUMBNAIL_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getVideoThumbnail" -> {
                    val path = call.argument<String>("path")
                    val quality = call.argument<Int>("quality") ?: 65
                    if (path == null) {
                        result.success(null)
                        return@setMethodCallHandler
                    }
                    thumbnailExecutor.execute {
                        try {
                            val retriever = MediaMetadataRetriever()
                            retriever.setDataSource(path)
                            val bitmap = retriever.getFrameAtTime(1000000, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                                ?: retriever.frameAtTime
                            val durationMsStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                            val durationMs = durationMsStr?.toLongOrNull() ?: 0L
                            val totalSec = durationMs / 1000
                            val min = totalSec / 60
                            val sec = totalSec % 60
                            val formattedDuration = String.format("%d:%02d", min, sec)
                            retriever.release()

                            if (bitmap != null) {
                                val stream = ByteArrayOutputStream()
                                bitmap.compress(Bitmap.CompressFormat.JPEG, quality, stream)
                                val bytes = stream.toByteArray()
                                bitmap.recycle()
                                runOnUiThread {
                                    result.success(mapOf(
                                        "bytes" to bytes,
                                        "duration" to formattedDuration
                                    ))
                                }
                            } else {
                                runOnUiThread {
                                    result.success(mapOf(
                                        "bytes" to null,
                                        "duration" to formattedDuration
                                    ))
                                }
                            }
                        } catch (e: Exception) {
                            runOnUiThread {
                                result.success(mapOf(
                                    "bytes" to null,
                                    "duration" to "0:00"
                                ))
                            }
                        }
                    }
                }
                "getVideoDuration" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.success("0:00")
                        return@setMethodCallHandler
                    }
                    thumbnailExecutor.execute {
                        try {
                            val retriever = MediaMetadataRetriever()
                            retriever.setDataSource(path)
                            val durationMsStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                            val durationMs = durationMsStr?.toLongOrNull() ?: 0L
                            val totalSec = durationMs / 1000
                            val min = totalSec / 60
                            val sec = totalSec % 60
                            retriever.release()
                            runOnUiThread {
                                result.success(String.format("%d:%02d", min, sec))
                            }
                        } catch (e: Exception) {
                            runOnUiThread {
                                result.success("0:00")
                            }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private var activeRingtone: android.media.Ringtone? = null

    private fun getSystemSounds(type: Int): List<Map<String, String>> {
        val list = mutableListOf<Map<String, String>>()
        try {
            val manager = RingtoneManager(this)
            manager.setType(type)
            val cursor = manager.cursor
            while (cursor.moveToNext()) {
                val title = cursor.getString(RingtoneManager.TITLE_COLUMN_INDEX) ?: continue
                val uri = manager.getRingtoneUri(cursor.position)?.toString() ?: continue
                list.add(mapOf("title" to title, "uri" to uri))
            }
            cursor.close()
        } catch (e: Exception) {
            // return empty list on permission error
        }
        return list
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
