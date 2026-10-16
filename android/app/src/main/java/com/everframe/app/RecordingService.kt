package com.everframe.app

import android.annotation.SuppressLint
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.lifecycle.LifecycleService
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.launch

class RecordingService : LifecycleService() {
    private val model get() = (application as EverFrameApplication).model
    private var wakeLock: PowerManager.WakeLock? = null
    private var started = false

    @SuppressLint("WakelockTimeout") // 服务停止、系统销毁及异常路径均释放；持续录像不设置固定时限。
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        super.onStartCommand(intent, flags, startId)
        if (intent?.action == ACTION_STOP) {
            model.stopRecording()
            if (!model.recorder.active) stopSelf()
            return START_NOT_STICKY
        }
        if (started) {
            if (model.recordingServicePending && model.recorder.foreground && !model.recorder.active) {
                model.recordingServicePending = false
                model.recorder.start()
            }
            return START_NOT_STICKY
        }
        // 禁止后台启动录像或在系统重建服务后自动录制。
        if (!model.recorder.foreground || !model.recordingServicePending) { stopSelf(); return START_NOT_STICKY }
        try {
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(NotificationChannel(CHANNEL, "持续录像", NotificationManager.IMPORTANCE_LOW))
            val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val stop = PendingIntent.getService(this, 1, Intent(this, RecordingService::class.java).setAction(ACTION_STOP), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val notification = NotificationCompat.Builder(this, CHANNEL)
                .setSmallIcon(android.R.drawable.ic_menu_camera).setContentTitle("EverFrame 正在录制")
                .setContentText("锁屏后继续有声录像，点击返回或停止")
                .setContentIntent(open).setOngoing(true).setSilent(true)
                .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
                .addAction(android.R.drawable.ic_media_pause, "停止录制", stop).build()
            ServiceCompat.startForeground(this, 1, notification,
                if (Build.VERSION.SDK_INT >= 30) ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE else 0)
            wakeLock = getSystemService(PowerManager::class.java).newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "EverFrame:Recording")
            wakeLock?.acquire()
            started = true
            model.recorder.attachService(this)
            model.recordingServicePending = false
            model.recorder.start()
            lifecycleScope.launch {
                model.recorder.state.collect {
                    if (!model.recorder.active && !model.recorder.sessionRequested) stopSelf()
                }
            }
        } catch (_: Exception) {
            wakeLock?.let { if (it.isHeld) it.release() }; wakeLock = null
            model.recorder.detachService()
            model.startRecordingFallback()
            stopSelf()
        }
        return START_NOT_STICKY
    }
    override fun onDestroy() {
        if (started) model.recorder.detachService()
        wakeLock?.let { if (it.isHeld) it.release() }; wakeLock = null
        super.onDestroy()
    }
    companion object {
        private const val CHANNEL = "recording"
        private const val ACTION_STOP = "com.everframe.app.STOP_RECORDING"
    }
}
