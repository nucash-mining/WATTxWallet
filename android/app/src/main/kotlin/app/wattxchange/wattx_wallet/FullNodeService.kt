package app.wattxchange.wattx_wallet

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
import android.util.Log

/**
 * Keeps the on-device node alive while the phone is locked or the app is in
 * the background.
 *
 * The daemon is a child process of the app. Without a foreground service,
 * Android freezes and then kills a backgrounded app within seconds of the
 * screen locking, taking the node with it, and the "Run as full node" switch
 * reads off the next time the app is opened. Owning the node from a
 * foreground service (with its ongoing notification) is what Android requires
 * for work that must keep running unattended.
 */
class FullNodeService : Service() {

    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startInForeground()
        // A partial wake lock keeps the CPU (not the screen) awake so the node
        // can keep syncing and relaying blocks while the phone sleeps. The user
        // opted into full-node mode; it is released the moment they turn it off.
        if (wakeLock == null) {
            wakeLock = (getSystemService(Context.POWER_SERVICE) as PowerManager)
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "wattx:fullnode")
                .apply { setReferenceCounted(false); acquire() }
        }
        // Restarted by the system after it reclaimed the process (START_STICKY):
        // bring the node back without waiting for the app to be opened.
        Thread({
            val err = FullNode.start(applicationContext)
            if (err != null) {
                Log.e(TAG, "node did not start: $err")
                stopSelf()
            }
        }, "wattxd-start").start()
        return START_STICKY
    }

    override fun onDestroy() {
        FullNode.stop()
        runCatching { wakeLock?.release() }
        wakeLock = null
        super.onDestroy()
    }

    private fun startInForeground() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Full node", NotificationManager.IMPORTANCE_LOW)
                    .apply { description = "Shown while the WATTx full node runs on this phone" }
            )
        }
        val open = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            Notification.Builder(this, CHANNEL_ID) else @Suppress("DEPRECATION") Notification.Builder(this)
        val notification = builder
            .setContentTitle("WATTx full node running")
            .setContentText("Validating the WATTx chain on this phone")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(open)
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    companion object {
        private const val TAG = "wattx-node"
        private const val CHANNEL_ID = "wattx_full_node"
        private const val NOTIFICATION_ID = 4021

        fun start(context: Context) {
            val i = Intent(context, FullNodeService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) context.startForegroundService(i)
            else context.startService(i)
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, FullNodeService::class.java))
        }
    }
}
