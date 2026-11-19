package dev.itai.itatranscript

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.IBinder

/**
 * A foreground service, so microphone capture keeps running while the screen is locked (FR-022).
 *
 * NOTE: written without the Android SDK on the authoring machine; not yet built or run.
 */
class CaptureService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(
        intent: Intent?,
        flags: Int,
        startId: Int,
    ): Int {
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL, "Live captions", NotificationManager.IMPORTANCE_LOW),
        )
        val notification =
            Notification
                .Builder(this, CHANNEL)
                .setContentTitle("Live captions are running")
                .setSmallIcon(android.R.drawable.ic_btn_speak_now)
                .setOngoing(true)
                .build()
        startForeground(ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
        return START_NOT_STICKY
    }

    companion object {
        private const val CHANNEL = "captions"
        private const val ID = 1
    }
}
