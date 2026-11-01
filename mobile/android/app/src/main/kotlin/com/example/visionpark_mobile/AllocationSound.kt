package com.example.visionpark_mobile

import android.app.Activity
import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.Ringtone
import android.media.RingtoneManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** Best-effort foreground feedback, independent of parking and speech services. */
class AllocationSound(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "visionpark/allocation_sound")
    private val handler = Handler(Looper.getMainLooper())
    private var ringtone: Ringtone? = null
    private val stopPlayback = Runnable { stop() }

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "play" -> result.success(play())
                else -> result.notImplemented()
            }
        }
    }

    private fun play(): Boolean {
        return try {
            if (activity.isFinishing || activity.isDestroyed || !activity.hasWindowFocus()) return false
            val audio = activity.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return false
            if (audio.ringerMode != AudioManager.RINGER_MODE_NORMAL ||
                audio.getStreamVolume(AudioManager.STREAM_NOTIFICATION) == 0) return false
            if (RingtoneManager.getActualDefaultRingtoneUri(activity, RingtoneManager.TYPE_NOTIFICATION) == null) return false
            stop()
            val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION) ?: return false
            val sound = RingtoneManager.getRingtone(activity, uri) ?: return false
            ringtone = sound
            sound.audioAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) sound.isLooping = false
            sound.play()
            // Even a long user-selected notification tone stays brief.
            handler.postDelayed(stopPlayback, 2500)
            true
        } catch (_: Exception) {
            stop()
            false
        }
    }

    fun stop() {
        handler.removeCallbacks(stopPlayback)
        try { ringtone?.stop() } catch (_: Exception) { /* Optional feedback only. */ }
        ringtone = null
    }

    fun dispose() {
        stop()
        channel.setMethodCallHandler(null)
    }
}
