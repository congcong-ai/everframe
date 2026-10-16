package com.everframe.app

import android.os.Handler
import android.os.Looper
import android.view.MotionEvent
import android.view.ViewGroup
import android.view.Window
import android.widget.FrameLayout
import android.widget.TextView
import android.view.Gravity
import android.graphics.Color

// 只覆盖当前窗口亮度，不修改系统设置，也不需要 WRITE_SETTINGS 权限。
class RecordingScreenPower(private val window: Window) {
    private val handler = Handler(Looper.getMainLooper())
    private val idle = RecordingIdleDeadline()
    private val timeout = Runnable { if (idle.expired(android.os.SystemClock.elapsedRealtime())) dim() }
    private var active = false
    private var recording = false
    private var originalBrightness: Float? = null
    private var cover: FrameLayout? = null
    private var consumingWakeTouch = false
    fun setActive(value: Boolean) {
        active = value
        restore()
    }
    fun setRecording(value: Boolean) {
        if (recording == value) return
        recording = value
        if (!value) restore() else interaction()
    }
    private fun interaction() {
        handler.removeCallbacks(timeout)
        idle.reset(recording && originalBrightness == null, active, android.os.SystemClock.elapsedRealtime())
        if (idle.deadline != null) handler.postDelayed(timeout, 60_000)
    }
    fun dim() {
        if (!active || originalBrightness != null) return
        handler.removeCallbacks(timeout)
        originalBrightness = window.attributes.screenBrightness
        window.attributes = window.attributes.apply { screenBrightness = 0f }
        cover = FrameLayout(window.context).apply {
            setBackgroundColor(Color.BLACK)
            isClickable = true
            contentDescription = "屏幕已调至最低亮度，轻点恢复"
            setOnClickListener { restore() }
            addView(TextView(context).apply {
                text = "轻触恢复亮度 · 录制状态不变"; setTextColor(Color.LTGRAY); gravity = Gravity.CENTER
            }, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
            (window.decorView as ViewGroup).addView(this, ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        }
    }
    private fun restore() {
        originalBrightness?.let { value -> window.attributes = window.attributes.apply { screenBrightness = value } }
        originalBrightness = null
        cover?.let { (it.parent as? ViewGroup)?.removeView(it) }; cover = null
        interaction()
    }
    fun onTouch(event: MotionEvent): Boolean {
        if (event.actionMasked == MotionEvent.ACTION_DOWN && originalBrightness != null) {
            consumingWakeTouch = true; restore()
        }
        if (consumingWakeTouch) {
            if (event.actionMasked == MotionEvent.ACTION_UP || event.actionMasked == MotionEvent.ACTION_CANCEL) consumingWakeTouch = false
            return true
        }
        interaction()
        return false
    }
}
