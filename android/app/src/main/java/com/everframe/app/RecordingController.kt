package com.everframe.app

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.view.Surface
import androidx.camera.core.*
import androidx.camera.core.resolutionselector.AspectRatioStrategy
import androidx.camera.core.resolutionselector.ResolutionSelector
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.video.*
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

class RecordingController(private val context: Context, private val repo: ClipRepository,
    private val scope: CoroutineScope, private val settings: () -> Settings,
    val notice: (String) -> Unit) {
    val state = MutableStateFlow(RecorderState.RECOVERING)
    val elapsed = MutableStateFlow(0L)
    val dual = MutableStateFlow(false)
    val lens = MutableStateFlow(CameraSelector.LENS_FACING_BACK)
    var foreground = false
    private var serviceOwner: LifecycleOwner? = null
    val backgroundRecording = MutableStateFlow(false)
    val sessionRequested get() = intent.continueSession
    private val canCapture get() = foreground || backgroundRecording.value
    fun attachService(owner: LifecycleOwner) {
        serviceOwner = owner; backgroundRecording.value = true; capture = null
    }
    fun detachService() {
        if (serviceOwner == null) return
        serviceOwner = null; backgroundRecording.value = false
        if (active) stop("持续录像服务已停止，请返回前台检查文件并手动开始")
        capture = null; provider?.unbindAll()
    }
    var debugSegmentSeconds = 0
    private var provider: ProcessCameraProvider? = null
    private var capture: VideoCapture<Recorder>? = null
    private var observedOwner: LifecycleOwner? = null
    private var observedCameras: List<CameraInfo> = emptyList()
    private var recording: Recording? = null
    private var owner: LifecycleOwner? = null
    private var preview: PreviewView? = null
    private var previewUseCase: Preview? = null
    private val intent = RecordingIntent()
    private var timer: Job? = null
    private var watchdog: Job? = null
    private var started = 0L
    private var segmentStarted = 0L
    private var segmentFailure: String? = null
    private var lastStatus = 0L
    private var lastMediaDuration = 0L
    private var binding = false
    private var generation = 0
    var afterClip: (() -> Unit)? = null
    val active get() = state.value in listOf(RecorderState.PREPARING, RecorderState.RECORDING, RecorderState.FINALIZING)
    fun ready() { state.value = RecorderState.IDLE }
    fun attach(owner: LifecycleOwner, view: PreviewView) {
        if ((this.owner !== owner || preview !== view) && !backgroundRecording.value) { if (active) stop("取景页面重建，已停止录像"); capture = null }
        this.owner = owner; preview = view
        if (backgroundRecording.value) previewUseCase?.setSurfaceProvider(view.surfaceProvider)
    }
    fun permissions() = listOf(Manifest.permission.CAMERA, Manifest.permission.RECORD_AUDIO).all {
        ContextCompat.checkSelfPermission(context, it) == PackageManager.PERMISSION_GRANTED
    }
    private suspend fun cameraProvider(): ProcessCameraProvider = provider ?: withTimeout(20000) { suspendCancellableCoroutine { continuation ->
        val future = ProcessCameraProvider.getInstance(context)
        future.addListener({ try { val p = future.get(); provider = p; if (continuation.isActive) continuation.resume(p) }
            catch (e: Exception) { if (continuation.isActive) continuation.resumeWithException(e) } }, ContextCompat.getMainExecutor(context))
    } }
    private fun concurrentPair(p: ProcessCameraProvider): List<CameraInfo>? = p.availableConcurrentCameraInfos.firstOrNull { group ->
        group.any { it.lensFacing == CameraSelector.LENS_FACING_BACK } && group.any { it.lensFacing == CameraSelector.LENS_FACING_FRONT }
    }
    private suspend fun bind(expectedGeneration: Int = generation) {
        val p = cameraProvider()
        check(expectedGeneration == generation && canCapture) { "准备已取消，请手动重新开始" }
        observedOwner?.let { old -> observedCameras.forEach { it.cameraState.removeObservers(old) } }
        observedCameras = emptyList()
        p.unbindAll()
        val view = requireNotNull(preview) { "取景器尚未就绪" }
        val lifecycle = requireNotNull(serviceOwner ?: owner) { "页面尚未就绪" }
        val surface = Preview.Builder().setTargetRotation(Surface.ROTATION_0)
            .setResolutionSelector(ResolutionSelector.Builder().setAspectRatioStrategy(AspectRatioStrategy.RATIO_16_9_FALLBACK_AUTO_STRATEGY).build()).build()
        surface.surfaceProvider = view.surfaceProvider
        previewUseCase = surface
        val recorder = Recorder.Builder().setQualitySelector(QualitySelector.from(Quality.HD, FallbackStrategy.lowerQualityOrHigherThan(Quality.HD))).build()
        val video = VideoCapture.Builder(recorder).setTargetRotation(Surface.ROTATION_0).setMirrorMode(MirrorMode.MIRROR_MODE_OFF).build()
        if (dual.value) {
            val pair = requireNotNull(concurrentPair(p)) { "本机不支持前后并发摄像头，已返回单镜头" }
            val group = UseCaseGroup.Builder().addUseCase(surface).addUseCase(video).build()
            val concurrent = p.bindToLifecycle(listOf(
                ConcurrentCamera.SingleCameraConfig(pair.first { it.lensFacing == CameraSelector.LENS_FACING_BACK }.cameraSelector,
                    group, CompositionSettings.Builder().setAlpha(1f).setOffset(0f, 0.5f).setScale(1f, 0.5f).build(), lifecycle),
                ConcurrentCamera.SingleCameraConfig(pair.first { it.lensFacing == CameraSelector.LENS_FACING_FRONT }.cameraSelector,
                    group, CompositionSettings.Builder().setAlpha(1f).setOffset(0f, -0.5f).setScale(1f, 0.5f).build(), lifecycle)
            ))
            observedCameras = concurrent.cameras.map { it.cameraInfo }
        } else {
            val camera = p.bindToLifecycle(lifecycle, CameraSelector.Builder().requireLensFacing(lens.value).build(), surface, video)
            observedCameras = listOf(camera.cameraInfo)
        }
        observedOwner = lifecycle
        observedCameras.forEach { info -> info.cameraState.observe(lifecycle) { status ->
            if (status.error != null && active) stop("摄像头中断，已停止记录")
        } }
        capture = video
    }
    fun configure(switchLens: Boolean = false, toggleDual: Boolean = false) {
        if (binding || state.value == RecorderState.RECOVERING) return
        if (active) { notice("请先停止并等待保存，再切换镜头或双录模式"); return }
        if (!permissions()) { notice("请先授予摄像头和麦克风权限"); return }
        binding = true
        state.value = RecorderState.PREPARING
        val token = generation
        scope.launch {
            try {
                if (toggleDual) {
                    if (!dual.value && concurrentPair(cameraProvider()) == null) {
                        notice("本机没有可用的前后并发摄像头组合，继续使用单镜头")
                        state.value = RecorderState.IDLE; return@launch
                    }
                    dual.value = !dual.value
                }
                if (switchLens) { dual.value = false; lens.value = if (lens.value == CameraSelector.LENS_FACING_BACK) CameraSelector.LENS_FACING_FRONT else CameraSelector.LENS_FACING_BACK }
                bind(token); state.value = RecorderState.IDLE
            } catch (e: Exception) { dual.value = false; capture = null; provider?.unbindAll(); state.value = RecorderState.ERROR; notice(e.message ?: "摄像头配置失败") }
            finally { binding = false }
        }
    }
    fun start() {
        if (active || binding || state.value == RecorderState.RECOVERING || !foreground) return
        if (!permissions()) { notice("录像需要摄像头与麦克风权限，请在系统设置中开启"); return }
        intent.start(); started = android.os.SystemClock.elapsedRealtime(); elapsed.value = 0
        beginSegment()
    }
    private fun beginSegment() {
        val token = ++generation
        state.value = RecorderState.PREPARING
        scope.launch {
            var clip: Clip? = null
            try {
                withContext(Dispatchers.IO) { if (repo.clean(settings())) notice("尚未达到存储目标，请导出或清理素材；已保护片段不会自动删除")
                    require(repo.freeBytes > 1_000_000_000) { "剩余空间低于 1 GB，请先导出或清理素材" } }
                if (!intent.continueSession || !canCapture || token != generation) return@launch
                if (capture == null) bind(token)
                if (!intent.continueSession || !canCapture || token != generation) { if (token == generation) state.value = RecorderState.IDLE; return@launch }
                val current = withContext(Dispatchers.IO) { repo.create() }
                clip = current
                if (!intent.continueSession || !canCapture || token != generation) {
                    withContext(Dispatchers.IO) { repo.discardUnstarted(current) }
                    if (token == generation) state.value = RecorderState.IDLE
                    return@launch
                }
                segmentFailure = null
                if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                    throw SecurityException("麦克风权限已撤回，请在系统设置重新授权")
                }
                recording = requireNotNull(capture).output.prepareRecording(context,
                    FileOutputOptions.Builder(repo.file(current)).setFileSizeLimit(3_800_000_000L).build())
                    .withAudioEnabled().start(ContextCompat.getMainExecutor(context)) { event ->
                        when (event) {
                            is VideoRecordEvent.Start -> {
                                if (!intent.continueSession || !canCapture) { recording?.stop(); return@start }
                                state.value = RecorderState.RECORDING
                                segmentStarted = android.os.SystemClock.elapsedRealtime(); lastStatus = segmentStarted; lastMediaDuration = 0L
                            }
                            is VideoRecordEvent.Status -> {
                                val mediaDuration = event.recordingStats.recordedDurationNanos
                                if (mediaDuration > lastMediaDuration) { lastStatus = android.os.SystemClock.elapsedRealtime(); lastMediaDuration = mediaDuration }
                                if (event.recordingStats.audioStats.audioState in listOf(AudioStats.AUDIO_STATE_ENCODER_ERROR, AudioStats.AUDIO_STATE_SOURCE_ERROR, AudioStats.AUDIO_STATE_SOURCE_SILENCED)) stop("麦克风或音频编码中断，已停止并保护当前文件")
                            }
                            is VideoRecordEvent.Finalize -> {
                                recording = null; timer?.cancel(); watchdog?.cancel()
                                state.value = RecorderState.FINALIZING
                                scope.launch {
                                  try {
                                    val normal = !event.hasError() || event.error == VideoRecordEvent.Finalize.ERROR_FILE_SIZE_LIMIT_REACHED
                                    val error = if (normal) segmentFailure else "录像结束错误（${event.error}），原文件已保护"
                                    val ok = withContext(Dispatchers.IO) { repo.finalize(current.id, current, error) }
                                    if (!ok) { intent.stop(); notice(error ?: "文件音视频检查未通过，原文件已保护") }
                                    withContext(Dispatchers.IO) { runCatching { repo.clean(settings()) } }
                                    state.value = if (ok) RecorderState.IDLE else RecorderState.ERROR
                                    if (intent.mayContinue(foreground, ok, backgroundRecording.value)) beginSegment() else { intent.stop(); afterClip?.invoke() }
                                  } catch (e: Exception) {
                                    intent.stop(); state.value = RecorderState.ERROR
                                    notice("录像已结束，但索引保存失败；原文件保留，请检查空间并重启恢复")
                                  }
                                }
                            }
                        }
                    }
                timer?.cancel()
                timer = scope.launch {
                    while (isActive) {
                        delay(1000)
                        elapsed.value = TimeUnit.MILLISECONDS.toSeconds(android.os.SystemClock.elapsedRealtime() - started)
                        if (state.value == RecorderState.RECORDING && android.os.SystemClock.elapsedRealtime() - lastStatus > 20000) { stop("录像数据长时间没有更新，已停止并保护当前文件"); break }
                        val free = withContext(Dispatchers.IO) {
                            if (elapsed.value % 15L == 0L) runCatching {
                                if (repo.clean(settings())) notice("尚未达到存储目标，请导出或清理素材；已保护片段不会自动删除")
                            }.onFailure { notice("循环清理失败，请检查存储空间；保护素材不会强制删除") }
                            repo.freeBytes
                        }
                        if (free <= 1_000_000_000) { stop("剩余空间低于 1 GB，已安全停止"); break }
                        if (state.value == RecorderState.RECORDING && android.os.SystemClock.elapsedRealtime() - segmentStarted >=
                            (if (BuildConfig.DEBUG && debugSegmentSeconds > 0) debugSegmentSeconds else settings().segmentMinutes * 60) * 1000L) {
                            finishSegment(); break
                        }
                    }
                }
                watchdog = scope.launch { delay(20000); if (state.value == RecorderState.PREPARING) stop("摄像头启动超时，请检查设备") }
            } catch (e: Exception) {
                if (token != generation) { clip?.let { withContext(Dispatchers.IO) { repo.discardUnstarted(it) } }; return@launch }
                intent.stop(); recording?.close(); recording = null
                clip?.let { withContext(Dispatchers.IO) { runCatching { repo.finalize(it.id, it, "录像未能启动") } } }
                state.value = RecorderState.ERROR; notice(e.message ?: "无法开始录像")
            }
        }
    }
    private fun finishSegment() {
        if (recording == null || state.value == RecorderState.FINALIZING) return
        state.value = RecorderState.FINALIZING; recording?.stop()
        watchdog?.cancel()
        watchdog = scope.launch { delay(20000); if (state.value == RecorderState.FINALIZING) { intent.stop(); notice("录像保存超时；请等待，原文件将在下次启动恢复检查") } }
    }
    fun stop(reason: String? = null) {
        intent.stop(); timer?.cancel()
        if (reason != null) { if (recording != null) segmentFailure = reason; notice(reason) }
        if (recording != null) finishSegment()
        else if (state.value != RecorderState.RECOVERING && state.value != RecorderState.FINALIZING) { generation++; if (!binding) state.value = RecorderState.IDLE }
    }
    fun background() {
        foreground = false
        if (!backgroundRecording.value) stop(if (active) "持续录像服务不可用，离开前台已停止；返回后请手动开始" else null)
    }
    fun release() { stop(); provider?.unbindAll() }
}
