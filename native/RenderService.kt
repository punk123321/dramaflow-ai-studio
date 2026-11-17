package com.dramaflow.aistudio

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

/**
 * Keeps the app alive while a video is being rendered, so the render goes on
 * when the screen turns off or the app is in the background. It does no
 * rendering itself: it shows an ongoing notification with the progress and
 * holds a CPU wake lock. It stops as soon as the render (or the whole queue)
 * is finished or cancelled.
 *
 * The phone's maker may still stop background work (battery savers); the
 * notification and wake lock make that less likely, they do not guarantee it.
 */
class RenderService : Service() {
    private var wake: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val text = intent?.getStringExtra("text") ?: "Render"
        val percent = intent?.getIntExtra("percent", -1) ?: -1
        val notification = build(text, percent)
        try {
            if (Build.VERSION.SDK_INT >= 29) {
                startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (e: Exception) {
            // The system refused a foreground service (for example started from the
            // background). The render itself still runs while the app is open.
            stopSelf()
            return START_NOT_STICKY
        }
        if (wake == null) {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            wake = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "dramaflow:render").apply {
                setReferenceCounted(false)
                acquire(6L * 60L * 60L * 1000L)
            }
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        wake?.let { if (it.isHeld) it.release() }
        wake = null
        super.onDestroy()
    }

    private fun build(text: String, percent: Int): Notification {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26 && nm.getNotificationChannel(CHANNEL) == null) {
            nm.createNotificationChannel(NotificationChannel(CHANNEL, "Render", NotificationManager.IMPORTANCE_LOW))
        }
        val open = packageManager.getLaunchIntentForPackage(packageName)?.let {
            PendingIntent.getActivity(this, 0, it, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        }
        val b = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL) else Notification.Builder(this)
        b.setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle("DramaFlow · ဗီဒီယို ထုတ်နေတယ်")
            .setContentText(if (percent in 0..100) "$text · $percent%" else text)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
        if (percent in 0..100) b.setProgress(100, percent, false) else b.setProgress(0, 0, true)
        if (open != null) b.setContentIntent(open)
        return b.build()
    }

    companion object {
        const val CHANNEL = "df_render"
        const val NOTIFICATION_ID = 4107
    }
}
