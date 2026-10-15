package com.everframe.app

import android.Manifest
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.Settings as SystemSettings
import android.view.WindowManager
import android.widget.MediaController
import android.widget.VideoView
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.camera.view.PreviewView
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.core.net.toUri
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

class MainActivity : ComponentActivity() {
    private val model: AppModel by viewModels()
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { EverFrameTheme { EverFrame(model) } }
        lifecycleScope.launch { model.recorder.state.collect { state ->
            if (state in listOf(RecorderState.PREPARING, RecorderState.RECORDING, RecorderState.FINALIZING)) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        } }
    }
    override fun onStart() { super.onStart(); model.foreground() }
    override fun onStop() { model.background(); super.onStop() }
}
@Composable fun EverFrameTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = lightColorScheme(primary = Color(0xFF315C51), secondary = Color(0xFF626E64),
        background = Color(0xFFF7F9F5), surface = Color(0xFFF7F9F5), surfaceVariant = Color(0xFFE8EEE7)), content = content)
}
fun clock(date: String): String = Instant.parse(date).atZone(ZoneId.systemDefault()).format(DateTimeFormatter.ofPattern("MM-dd HH:mm:ss"))
fun duration(seconds: Long) = "%02d:%02d:%02d".format(seconds / 3600, seconds % 3600 / 60, seconds % 60)
fun statusLabel(value: String) = when (value) { "pending" -> "等待"; "running" -> "处理中"; "completed" -> "已完成"; "failed" -> "失败，可重试"; else -> "未知" }
fun gb(bytes: Long) = "%.2f GB".format(bytes / 1e9)

@OptIn(ExperimentalMaterial3Api::class)
@Composable fun EverFrame(model: AppModel) {
    val context = LocalContext.current
    val activity = context as ComponentActivity
    val state by model.recorder.state.collectAsStateWithLifecycle()
    val clips by model.repo.clips.collectAsStateWithLifecycle()
    val settings by model.settings.collectAsStateWithLifecycle()
    val notice by model.message.collectAsStateWithLifecycle()
    val warning by model.warning.collectAsStateWithLifecycle()
    var tab by remember { mutableIntStateOf(0) }
    var pendingStart by remember { mutableStateOf(false) }
    var player by remember { mutableStateOf<Pair<Clip, Double>?>(null) }
    var deleting by remember { mutableStateOf<Clip?>(null) }
    var exportClip by remember { mutableStateOf<Clip?>(null) }
    var importClip by remember { mutableStateOf<Clip?>(null) }
    val export = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("video/mp4")) { uri ->
        val clip = exportClip; exportClip = null
        if (uri != null && clip != null) activity.lifecycleScope.launch {
            try {
                withContext(Dispatchers.IO) {
                    model.repo.file(clip).inputStream().use { input -> requireNotNull(context.contentResolver.openOutputStream(uri, "wt")).use { input.copyTo(it) } }
                }
                model.notice("录像已导出，请在目标位置检查音画")
            } catch (_: Exception) { model.notice("导出未完成，请检查目标存储空间") }
            finally { model.repo.unpin(clip.id) }
        } else if (clip != null) model.repo.unpin(clip.id)
    }
    val importer = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        val clip = importClip; importClip = null
        if (uri != null && clip != null) activity.lifecycleScope.launch {
            try {
                val input = withContext(Dispatchers.IO) { context.contentResolver.openInputStream(uri)!!.use {
                    val buffer = java.io.ByteArrayOutputStream(); val block = ByteArray(8192)
                    while (buffer.size() <= 2_000_000) { val count = it.read(block); if (count < 0) break; buffer.write(block, 0, count) }
                    val bytes = buffer.toByteArray(); require(bytes.size <= 2_000_000) { "转写文件超过2MB" }; bytes.toString(Charsets.UTF_8)
                } }
                model.importTranscript(clip.id, input)
            } catch (e: Exception) { model.notice(e.message ?: "读取转写失败") }
        }
    }
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { result ->
        if (result.values.all { it } && model.recorder.permissions()) {
            if (pendingStart) model.startRecording() else model.recorder.configure()
        } else model.notice("请允许摄像头与麦克风；拒绝后可到系统设置开启")
        pendingStart = false
    }
    fun request(start: Boolean) {
        if (model.recorder.permissions()) { if (start) model.startRecording() else model.recorder.configure() }
        else { pendingStart = start; permission.launch(arrayOf(Manifest.permission.CAMERA, Manifest.permission.RECORD_AUDIO)) }
    }
    Scaffold(bottomBar = {
        NavigationBar {
            listOf("记录" to Icons.Outlined.Videocam, "素材" to Icons.Outlined.VideoLibrary, "时间轴" to Icons.Outlined.Timeline, "设置" to Icons.Outlined.Settings).forEachIndexed { index, (label, icon) ->
                NavigationBarItem(selected = tab == index, onClick = { tab = index }, icon = { Icon(icon, label) }, label = { Text(label) })
            }
        }
    }) { padding ->
        Column(Modifier.fillMaxSize().padding(padding)) {
            if (warning.isNotEmpty()) Surface(color = MaterialTheme.colorScheme.errorContainer) {
                Row(Modifier.fillMaxWidth().padding(start = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(warning, Modifier.weight(1f), style = MaterialTheme.typography.bodySmall)
                    IconButton(onClick = { model.warn("") }) { Icon(Icons.Outlined.Close, "关闭警告") }
                }
            }
            if (notice.isNotEmpty()) Surface(color = MaterialTheme.colorScheme.secondaryContainer) {
                Row(Modifier.fillMaxWidth().padding(start = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(notice, Modifier.weight(1f), style = MaterialTheme.typography.bodySmall)
                    IconButton(onClick = { model.notice("") }) { Icon(Icons.Outlined.Close, "关闭提示") }
                }
            }
            Box(Modifier.weight(1f)) {
                // 保持取景 Surface 存活；切换功能页不重绑正在写入的摄像头。
                RecorderPage(model, Modifier.fillMaxSize().alpha(if (tab == 0) 1f else 0f), visible = tab == 0,
                    onPreview = { request(false) }, onStart = { request(true) })
                when (tab) {
                    1 -> ClipsPage(model, clips, onPlay = { player = it to 0.0 }, onDelete = { deleting = it },
                        onExport = { model.repo.pin(it.id); exportClip = it; export.launch("EverFrame-${it.id}.mp4") }, onImport = { importClip = it; importer.launch(arrayOf("application/json", "text/plain")) })
                    2 -> TimelinePage(model, onPlay = { clip, time -> player = clip to time })
                    3 -> SettingsPage(model, settings)
                }
            }
        }
    }
    deleting?.let { clip -> AlertDialog(onDismissRequest = { deleting = null }, title = { Text(if (clip.locked) "删除已保留的素材？" else "删除素材？") },
        text = { Text("这会永久删除本机原录像与相关转写，导出前请确认。") },
        confirmButton = { TextButton(onClick = { model.attempt { model.repo.delete(clip.id, true) }; deleting = null }) { Text("永久删除") } },
        dismissButton = { TextButton(onClick = { deleting = null }) { Text("取消") } }) }
    player?.let { (clip, seconds) ->
        DisposableEffect(clip.id) { model.repo.pin(clip.id); onDispose { model.repo.unpin(clip.id) } }
        AlertDialog(onDismissRequest = { player = null }, title = { Text(clock(clip.startAt)) }, text = {
            AndroidView(modifier = Modifier.fillMaxWidth().height(360.dp), factory = { ctx -> VideoView(ctx).apply {
                setMediaController(MediaController(ctx)); setVideoURI(Uri.fromFile(model.repo.file(clip)))
                setOnPreparedListener { seekTo((seconds * 1000).toInt()); start() }
                setOnErrorListener { _, _, _ -> model.notice("文件无法播放，原文件仍保留；可以导出检查"); true }
            } }, onRelease = { it.stopPlayback() })
        }, confirmButton = { TextButton(onClick = { player = null }) { Text("关闭播放") } })
    }
}
@Composable private fun RecorderPage(model: AppModel, modifier: Modifier, visible: Boolean, onPreview: () -> Unit, onStart: () -> Unit) {
    val state by model.recorder.state.collectAsStateWithLifecycle()
    val elapsed by model.recorder.elapsed.collectAsStateWithLifecycle()
    val dual by model.recorder.dual.collectAsStateWithLifecycle()
    val context = LocalContext.current
    Column(modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(state.label, color = if (state == RecorderState.RECORDING) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.primary, fontWeight = FontWeight.Bold)
                Text(duration(elapsed), style = MaterialTheme.typography.headlineMedium)
            }
            TextButton(enabled = visible && !model.recorder.active, onClick = { model.recorder.configure(toggleDual = true) }) { Text(if (dual) "双录已开" else "双录") }
        }
        Box(Modifier.weight(1f).fillMaxWidth().background(Color(0xFF17231F)), contentAlignment = Alignment.Center) {
            AndroidView(modifier = Modifier.fillMaxSize(), factory = { ctx -> PreviewView(ctx).apply {
                implementationMode = PreviewView.ImplementationMode.COMPATIBLE
                scaleType = PreviewView.ScaleType.FIT_CENTER
                model.recorder.attach(context as ComponentActivity, this)
            } })
            if (state == RecorderState.IDLE && elapsed == 0L) TextButton(onClick = onPreview, enabled = visible) { Text("点击开启取景", color = Color.White) }
        }
        Text("仅前台有声录像 · 默认720p · 分段间可能有短暂间隔", style = MaterialTheme.typography.labelSmall)
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf(10, 30, 60).forEach { minutes -> OutlinedButton(onClick = { model.attempt { model.repo.keep(minutes); model.notice("已保留与最近${minutes}分钟相交的完整片段") } }, modifier = Modifier.weight(1f), enabled = visible && state != RecorderState.RECOVERING) { Text("保留${minutes}分", style = MaterialTheme.typography.labelSmall) } }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            if (model.recorder.active) Button(onClick = { model.recorder.stop() }, modifier = Modifier.weight(1f), enabled = visible, colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error)) {
                Icon(Icons.Outlined.Stop, null); Text(if (state == RecorderState.FINALIZING) "取消续录，等待保存" else "停止记录")
            } else Button(onClick = onStart, modifier = Modifier.weight(1f), enabled = visible && state != RecorderState.RECOVERING) { Icon(Icons.Outlined.FiberManualRecord, null); Text("开始记录") }
            OutlinedIconButton(enabled = visible && !model.recorder.active, onClick = { model.recorder.configure(switchLens = true) }) { Icon(Icons.Outlined.Cameraswitch, "切换前后镜头") }
        }
    }
}
@Composable private fun ClipsPage(model: AppModel, clips: List<Clip>, onPlay: (Clip) -> Unit, onDelete: (Clip) -> Unit, onExport: (Clip) -> Unit, onImport: (Clip) -> Unit) {
    LazyColumn(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item { Text("本机素材", style = MaterialTheme.typography.headlineMedium); Text("${clips.size} 段 · ${gb(clips.sumOf { it.fileSize })} · 剩余 ${gb(model.repo.freeBytes)}") }
        if (clips.isEmpty()) item { EmptyState("每一段记录，都会留在这里", "开始录像后自动分段保存。重要内容可以保留和导出。") }
        items(clips, key = { it.id }) { clip -> Card(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(clock(clip.startAt), fontWeight = FontWeight.Bold)
                Text("${duration(clip.duration.toLong())} · ${gb(clip.fileSize)} · ${if (clip.locked || clip.pendingLock) "已保留" else "循环素材"}")
                Text(clip.summary ?: if (clip.isWriting) "正在写入，请等待保存" else "转写：${statusLabel(clip.transcriptionStatus)} · AI：${statusLabel(clip.aiStatus)}", style = MaterialTheme.typography.bodySmall)
                clip.failure?.let { Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall) }
                Row {
                    IconButton(enabled = !clip.isWriting, onClick = { onPlay(clip) }) { Icon(Icons.Outlined.PlayArrow, "播放") }
                    IconButton(onClick = { model.attempt { model.repo.lock(clip.id, !(clip.locked || clip.pendingLock)) } }) { Icon(if (clip.locked || clip.pendingLock) Icons.Outlined.Bookmark else Icons.Outlined.BookmarkBorder, "切换保留") }
                    IconButton(enabled = !clip.isWriting, onClick = { onExport(clip) }) { Icon(Icons.Outlined.FileUpload, "导出原录像") }
                    IconButton(enabled = !clip.isWriting, onClick = { onDelete(clip) }) { Icon(Icons.Outlined.DeleteOutline, "删除") }
                }
                if (!clip.isWriting && clip.failure == null) Row {
                    TextButton(onClick = { onImport(clip) }) { Text("导入转写") }
                    TextButton(onClick = { model.retry(clip.id) }) { Text("重试分析") }
                }
            }
        } }
    }
}
@Composable private fun TimelinePage(model: AppModel, onPlay: (Clip, Double) -> Unit) {
    val clips by model.repo.clips.collectAsStateWithLifecycle()
    val analyses by model.analyses.collectAsStateWithLifecycle()
    val daily by model.daily.collectAsStateWithLifecycle()
    val aiState by model.analysisState.collectAsStateWithLifecycle()
    val events = model.todayClips().flatMap { clip -> analyses[clip.id]?.timeline.orEmpty().map { clip to it } }.sortedBy { epoch(it.first.startAt) + (it.second.start * 1000).toLong() }
    LazyColumn(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item { Text("今日时间轴", style = MaterialTheme.typography.headlineMedium); Text(aiState); TextButton(onClick = { model.generateDaily() }) { Text("生成今日总结") } }
        daily?.takeIf { it.id == java.time.LocalDate.now().toString() }?.let { summary -> item { Card { Column(Modifier.padding(16.dp)) {
            Text("今日总结", style = MaterialTheme.typography.titleLarge); Text(summary.summary)
            summary.accomplishments.forEach { Text("• $it") }; summary.ideas.forEach { Text("想法：$it") }
            summary.reviews.forEach { review -> val clip = clips.find { it.id == review.clipID }; TextButton(enabled = clip != null, onClick = { clip?.let { onPlay(it, 0.0) } }) { Text(review.reason + if (clip == null) "（原素材已删除）" else "") } }
        } } } }
        if (events.isEmpty()) item { EmptyState("还没有整理好的时间轴", "可在设置中启用 AI。转写能力因设备而异，也可在素材页导入带时间戳的中文转写 JSON。") }
        items(events) { (clip, event) -> Card(onClick = { onPlay(clip, event.start) }, modifier = Modifier.fillMaxWidth()) {
            Column(Modifier.padding(16.dp)) { Text("${clock(clip.startAt)} + ${duration(event.start.toLong())}", style = MaterialTheme.typography.labelMedium); Text(event.title, fontWeight = FontWeight.Bold); Text(event.summary); Text("回看分数 ${event.importance_score}", color = MaterialTheme.colorScheme.primary) }
        } }
    }
}
@Composable private fun EmptyState(title: String, detail: String) {
    Column(Modifier.fillMaxWidth().padding(vertical = 40.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) { Text(title, style = MaterialTheme.typography.titleLarge); Text(detail, color = MaterialTheme.colorScheme.onSurfaceVariant) }
}
@Composable private fun SettingsPage(model: AppModel, settings: Settings) {
    val address by model.webAddress.collectAsStateWithLifecycle()
    val context = LocalContext.current
    var key by remember { mutableStateOf("") }
    var consent by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background).verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("设置", style = MaterialTheme.typography.headlineMedium)
        Text("录像与存储", style = MaterialTheme.typography.titleMedium)
        Text("分段时长")
        Row { listOf(5, 10, 15, 30).forEach { minute -> FilterChip(selected = settings.segmentMinutes == minute, onClick = { model.attempt { model.updateSettings(settings.copy(segmentMinutes = minute)) } }, label = { Text("${minute}分") }, modifier = Modifier.padding(end = 4.dp)) } }
        NumberSetting("录像配额（GB）", settings.maxStorageGB.toString()) { model.updateSettings(settings.copy(maxStorageGB = it.toDouble())) }
        NumberSetting("普通素材保留天数", settings.retentionDays.toString()) { model.updateSettings(settings.copy(retentionDays = it.toInt())) }
        NumberSetting("尽量保持剩余（GB）", settings.minimumFreeGB.toString()) { model.updateSettings(settings.copy(minimumFreeGB = it.toDouble())) }
        Text("保护片段不参与循环清理。实际剩余低于1GB时停止录像；无法保证修复被强杀时尚未封装的文件。", style = MaterialTheme.typography.bodySmall)
        HorizontalDivider()
        SettingSwitch("电脑控制（可信 Wi-Fi）", settings.webEnabled) { model.attempt { model.updateSettings(settings.copy(webEnabled = it)) } }
        if (settings.webEnabled) {
            Text(if (address.isBlank()) "等待前台与局域网 Wi-Fi" else "$address\n配对码：${model.pairing.code}", fontWeight = FontWeight.Bold)
            Text("手机与电脑连接同一可信 Wi-Fi，浏览器输入地址配对。HTTP 不加密，离开前台即关闭并作废会话。", style = MaterialTheme.typography.bodySmall)
        }
        HorizontalDivider()
        SettingSwitch("启用 AI（默认关闭）", settings.aiEnabled) { enabled -> if (enabled) consent = true else model.attempt { model.updateSettings(settings.copy(aiEnabled = false)) } }
        Text("${model.speech.availability()}\n仅使用端侧识别，不自动切换在线服务。基础录像不依赖 AI。", style = MaterialTheme.typography.bodySmall)
        SettingSwitch("实验：系统离线文件转写（需真机核验）", settings.experimentalSystemSpeech) { enabled -> model.attempt { model.updateSettings(settings.copy(experimentalSystemSpeech = enabled)) } }
        OutlinedTextField(value = key, onValueChange = { key = it }, label = { Text("自己的 DeepSeek API Key") }, visualTransformation = PasswordVisualTransformation(), singleLine = true, modifier = Modifier.fillMaxWidth())
        Row { TextButton(onClick = { model.saveKey(key); key = "" }) { Text("保存密钥") }; TextButton(onClick = { model.saveKey(""); key = "" }) { Text("移除密钥") }; TextButton(onClick = { model.testKey() }) { Text("测试连接") } }
        var modelName by remember(settings.model) { mutableStateOf(settings.model) }
        OutlinedTextField(value = modelName, onValueChange = { modelName = it }, label = { Text("DeepSeek 模型") }, singleLine = true, modifier = Modifier.fillMaxWidth())
        TextButton(onClick = { model.attempt { model.updateSettings(settings.copy(model = modelName)) } }) { Text("保存模型") }
        SettingSwitch("仅 Wi-Fi 分析", settings.wifiOnly) { model.attempt { model.updateSettings(settings.copy(wifiOnly = it)) } }
        SettingSwitch("仅充电时分析", settings.chargingOnly) { model.attempt { model.updateSettings(settings.copy(chargingOnly = it)) } }
        Text("开始录像、离开前台或温度较高时暂停分析。音视频保留本机；启用 AI 后，带时间戳文字将发送至 DeepSeek。", style = MaterialTheme.typography.bodySmall)
        if (BuildConfig.DEBUG) {
            HorizontalDivider(); Text("开发者测试（重启恢复）")
            Row { listOf(0, 30, 60).forEach { seconds -> TextButton(onClick = { model.recorder.debugSegmentSeconds = seconds; model.notice(if (seconds == 0) "已恢复正常分段" else "调试分段：${seconds}秒") }) { Text(if (seconds == 0) "正常" else "${seconds}秒") } } }
            TextButton(onClick = { model.recorder.stop("模拟低磁盘，已停止录像") }) { Text("模拟低磁盘停止") }
        }
        TextButton(onClick = { context.startActivity(Intent(SystemSettings.ACTION_APPLICATION_DETAILS_SETTINGS, "package:${context.packageName}".toUri())) }) { Text("打开系统权限设置") }
        Text("EverFrame ${BuildConfig.VERSION_NAME} · Android原生版\n本机优先，无账号、订阅与云同步。卸载会删除本机素材，请先导出。", style = MaterialTheme.typography.bodySmall)
    }
    if (consent) AlertDialog(onDismissRequest = { consent = false }, title = { Text("启用文字分析？") }, text = { Text("系统端侧服务将尝试转写已保存录像。带时间戳的转写文字与片段摘要会发送到 DeepSeek，使用你自己的 API Key；不会上传原始音视频。离线中文、文件输入与时间戳需本机验证，失败时不会伪造结果。") }, confirmButton = {
        TextButton(onClick = { model.attempt { model.updateSettings(settings.copy(aiEnabled = true)) }; consent = false }) { Text("同意并启用") }
    }, dismissButton = { TextButton(onClick = { consent = false }) { Text("取消") } })
}
@Composable private fun SettingSwitch(label: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) { Text(label, Modifier.weight(1f)); Switch(checked, onCheckedChange = onChange) }
}
@Composable private fun NumberSetting(label: String, value: String, save: (String) -> Unit) {
    var input by remember(value) { mutableStateOf(value) }; var error by remember { mutableStateOf(false) }
    Row(verticalAlignment = Alignment.CenterVertically) {
        OutlinedTextField(value = input, onValueChange = { input = it; error = false }, label = { Text(label) }, singleLine = true, isError = error, keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(keyboardType = androidx.compose.ui.text.input.KeyboardType.Decimal), modifier = Modifier.weight(1f))
        TextButton(onClick = { try { save(input); error = false } catch (_: Exception) { error = true } }) { Text("保存") }
    }
}
