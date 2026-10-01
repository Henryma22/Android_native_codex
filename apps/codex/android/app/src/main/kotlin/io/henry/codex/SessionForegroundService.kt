package io.henry.codex

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder

/**
 * Keeps a notification visible while one or more local app-server sessions
 * are running in the application process. It is deliberately not a process
 * owner: individual session clients stop their own process IDs, while the
 * explicit notification Stop action is the only global stop boundary.
 */
internal class SessionForegroundService : Service() {
    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, buildNotification())
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            HostProcessRuntime.stopAll()
            CompatibilityProcessRuntime.stopAll()
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelfResult(startId)
            return START_NOT_STICKY
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        // Service teardown is not a process teardown. A stopService() call can
        // race with another session acquiring a lease; killing every entry
        // here would make an unrelated app-server disappear. The explicit
        // notification STOP action above is the only global stop boundary.
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Codex local session",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Keeps an approved local Codex app-server session visible."
        }
        getSystemService(NotificationManager::class.java)
            ?.createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification {
        val openIntent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or immutableFlag(),
        )
        val stopIntent = Intent(this, SessionForegroundService::class.java).apply {
            action = ACTION_STOP
        }
        val stopPendingIntent = PendingIntent.getService(
            this,
            STOP_REQUEST_CODE,
            stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or immutableFlag(),
        )
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.stat_notify_sync)
                .setContentTitle("Codex local session")
                .setContentText("An approved local app-server session is running")
                .setContentIntent(pendingIntent)
                .addAction(
                    android.R.drawable.ic_menu_close_clear_cancel,
                    "Stop",
                    stopPendingIntent,
                )
                .setOngoing(true)
                .build()
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
                .setSmallIcon(android.R.drawable.stat_notify_sync)
                .setContentTitle("Codex local session")
                .setContentText("An approved local app-server session is running")
                .setContentIntent(pendingIntent)
                .addAction(
                    android.R.drawable.ic_menu_close_clear_cancel,
                    "Stop",
                    stopPendingIntent,
                )
                .setOngoing(true)
                .build()
        }
    }

    private fun immutableFlag(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_IMMUTABLE
        } else {
            0
        }

    private companion object {
        const val ACTION_STOP = "io.henry.codex.action.STOP_SESSION"
        const val CHANNEL_ID = "codex-local-session"
        const val NOTIFICATION_ID = 4101
        const val STOP_REQUEST_CODE = 4102
    }
}
