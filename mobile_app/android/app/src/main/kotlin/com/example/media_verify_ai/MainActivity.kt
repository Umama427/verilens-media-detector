package com.example.media_verify_ai

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaRecorder
import android.os.Build
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "verilens/android_audio"
        private const val REQ_RECORD_AUDIO = 4101
        private const val REQ_PICK_AUDIO = 4102
        private const val MAX_AUDIO_BYTES = 14 * 1024 * 1024
    }

    private var recorder: MediaRecorder? = null
    private var recordingFile: File? = null
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingPickResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startRecording" -> handleStartRecording(result)
                "stopRecording" -> {
                    val discard = call.argument<Boolean>("discard") ?: false
                    handleStopRecording(discard, result)
                }
                "pickAudio" -> handlePickAudio(result)
                else -> result.notImplemented()
            }
        }
    }

    private fun handleStartRecording(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED
        ) {
            if (pendingPermissionResult != null) {
                result.error("BUSY", "Permission prompt already active.", null)
                return
            }
            pendingPermissionResult = result
            requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), REQ_RECORD_AUDIO)
            return
        }
        startRecorderNow(result)
    }

    private fun startRecorderNow(result: MethodChannel.Result) {
        try {
            releaseRecorder()
            val outFile = File(cacheDir, "verilens_voice_${System.currentTimeMillis()}.m4a")
            val mr = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                MediaRecorder(this)
            } else {
                @Suppress("DEPRECATION")
                MediaRecorder()
            }
            mr.setAudioSource(MediaRecorder.AudioSource.MIC)
            mr.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            mr.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            mr.setAudioEncodingBitRate(96000)
            mr.setAudioSamplingRate(44100)
            mr.setOutputFile(outFile.absolutePath)
            mr.prepare()
            mr.start()
            recorder = mr
            recordingFile = outFile
            result.success(true)
        } catch (e: Exception) {
            releaseRecorder()
            result.error("RECORDER_ERROR", e.message ?: "Could not start microphone recording.", null)
        }
    }

    private fun handleStopRecording(discard: Boolean, result: MethodChannel.Result) {
        val outFile = recordingFile
        try {
            recorder?.stop()
        } catch (_: Exception) {
        } finally {
            releaseRecorder()
        }

        if (discard || outFile == null || !outFile.exists()) {
            try { outFile?.delete() } catch (_: Exception) {}
            recordingFile = null
            result.success(null)
            return
        }

        try {
            val bytes = outFile.readBytes()
            outFile.delete()
            recordingFile = null
            if (bytes.isEmpty()) {
                result.error("EMPTY_AUDIO", "Recording was too short. Speak for at least 1 second.", null)
                return
            }
            if (bytes.size > MAX_AUDIO_BYTES) {
                result.error("TOO_LARGE", "Recording exceeds 14 MB upload limit.", null)
                return
            }
            result.success(
                mapOf(
                    "bytes" to bytes,
                    "fileName" to "live_voice_recording.m4a",
                    "mimeType" to "audio/mp4"
                )
            )
        } catch (e: Exception) {
            result.error("READ_ERROR", e.message ?: "Failed to read recorded audio.", null)
        }
    }

    private fun handlePickAudio(result: MethodChannel.Result) {
        if (pendingPickResult != null) {
            result.error("BUSY", "Audio picker is already open.", null)
            return
        }
        pendingPickResult = result
        try {
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "audio/*"
                putExtra(
                    Intent.EXTRA_MIME_TYPES,
                    arrayOf("audio/*", "application/ogg")
                )
            }
            startActivityForResult(intent, REQ_PICK_AUDIO)
        } catch (e: Exception) {
            pendingPickResult = null
            result.error("PICKER_ERROR", e.message ?: "Could not open audio file picker.", null)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        if (requestCode == REQ_RECORD_AUDIO) {
            val res = pendingPermissionResult
            pendingPermissionResult = null
            if (res != null) {
                val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
                if (granted) {
                    startRecorderNow(res)
                } else {
                    res.error("PERMISSION_DENIED", "Microphone permission is required to record voice.", null)
                }
            }
            return
        }
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == REQ_PICK_AUDIO) {
            val res = pendingPickResult
            pendingPickResult = null
            if (res == null) return
            if (resultCode != Activity.RESULT_OK || data?.data == null) {
                res.success(null)
                return
            }
            val uri = data.data!!
            try {
                var fileName = "voice_clip.m4a"
                contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val idx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                        if (idx >= 0) {
                            val name = cursor.getString(idx)
                            if (!name.isNullOrBlank()) fileName = name
                        }
                    }
                }
                val mime = contentResolver.getType(uri) ?: "audio/mpeg"
                val bytes = contentResolver.openInputStream(uri)?.use { it.readBytes() }
                if (bytes == null || bytes.isEmpty()) {
                    res.error("EMPTY_FILE", "Selected audio file could not be read.", null)
                    return
                }
                if (bytes.size > MAX_AUDIO_BYTES) {
                    res.error("TOO_LARGE", "Audio file exceeds 14 MB upload limit.", null)
                    return
                }
                res.success(
                    mapOf(
                        "bytes" to bytes,
                        "fileName" to fileName,
                        "mimeType" to mime
                    )
                )
            } catch (e: Exception) {
                res.error("PICK_READ_ERROR", e.message ?: "Failed to read audio file.", null)
            }
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    private fun releaseRecorder() {
        try { recorder?.reset() } catch (_: Exception) {}
        try { recorder?.release() } catch (_: Exception) {}
        recorder = null
    }

    override fun onDestroy() {
        releaseRecorder()
        super.onDestroy()
    }
}