package com.everframe.app

import android.app.Application
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import androidx.core.content.ContextCompat
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.BatteryManager
import android.os.Build
import android.os.PowerManager
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.*
import java.io.File
import java.time.LocalDate
import java.time.ZoneId

class AppModel(application: Application) : AndroidViewModel(application) {
    private val context = application
    private val root = File(context.filesDir, "EverFrame").apply { mkdirs() }
    val repo = ClipRepository(root)
    val settings = MutableStateFlow(runCatching { json.decodeFromString<Settings>(File(root, "settings.json").readText()).validated() }.getOrDefault(Settings()))
    val message = MutableStateFlow("")
    val warning = MutableStateFlow("")
    val analysisState = MutableStateFlow("AI 已关闭")
    val webAddress = MutableStateFlow("")
    val pairing = PairingStore()
    val analyses = MutableStateFlow<Map<String, ClipAnalysis>>(emptyMap())
    val daily = MutableStateFlow<DailySummary?>(null)
    val recorder = RecordingController(context, repo, viewModelScope, { settings.value }, ::warn)
    val speech = AndroidTranscription(context)
    private val keyStore = APIKeyStore(context)
    private val ai = DeepSeek()
    private val web = LocalWebServer(::handleWeb, ::notice)
    private var analysisJob: Job? = null
    private var thermalStatus = 0
    private var recovered = false
    private val power = context.getSystemService(PowerManager::class.java)
    private val thermalListener = if (Build.VERSION.SDK_INT >= 29) PowerManager.OnThermalStatusChangedListener { status ->
        thermalStatus = status
        if (status >= PowerManager.THERMAL_STATUS_SEVERE) { analysisJob?.cancel(); warn("设备温度较高，转写与 AI 已暂停") }
        if (status >= PowerManager.THERMAL_STATUS_CRITICAL) { stopWeb(); warn("设备温度过高，电脑控制已暂停") }
        if (status >= PowerManager.THERMAL_STATUS_EMERGENCY) { recordingServicePending = false; recorder.stop("设备严重过热，已停止记录") }
    } else null
    init {
        if (Build.VERSION.SDK_INT >= 29 && thermalListener != null) { power.addThermalStatusListener(context.mainExecutor, thermalListener); thermalStatus = power.currentThermalStatus }
        recorder.afterClip = { scheduleAnalysis() }
        viewModelScope.launch {
            try {
                withContext(Dispatchers.IO) {
                    context.cacheDir.listFiles().orEmpty().filter { it.name.startsWith("speech-") }.forEach { it.deleteRecursively() }
                    repo.recover()
                    analyses.value = repo.clips.value.mapNotNull { c -> runCatching { c.id to json.decodeFromString<ClipAnalysis>(File(root, "${c.id}.analysis.json").readText()).validated(c.duration) }.getOrNull() }.toMap()
                    daily.value = runCatching { json.decodeFromString<DailySummary>(File(root, "${LocalDate.now()}.daily.json").readText()) }.getOrNull()
                }
                recovered = true; recorder.ready()
            } catch (_: Exception) { recorder.state.value = RecorderState.ERROR; notice("素材恢复失败，请检查本机空间；原文件未删除") }
        }
        viewModelScope.launch {
            while (isActive) { delay(15000); if (recorder.foreground) { refreshWeb(); scheduleAnalysis() } }
        }
    }
    private fun safeError(error: Exception, fallback: String): String = when (error) {
        is kotlinx.serialization.SerializationException -> "JSON结构不符合协议，未接受该结果；不会显示完整原文"
        is java.io.IOException -> "网络或文件操作失败，请检查连接与存储空间"
        else -> error.message ?: fallback
    }
    fun notice(text: String) { message.value = text }
    fun warn(text: String) { warning.value = text }
    fun foreground() { recorder.foreground = true; refreshWeb(); scheduleAnalysis() }
    fun background() { recordingServicePending = false; recorder.background(); analysisJob?.cancel(); stopWeb() }
    fun attempt(block: () -> Unit) { try { block() } catch (e: Exception) { notice(safeError(e, "操作失败")) } }
    fun updateSettings(value: Settings) {
        value.validated(); atomicWrite(File(root, "settings.json"), json.encodeToString(value)); settings.value = value
        if (!value.aiEnabled) { analysisJob?.cancel(); analysisState.value = "AI 已关闭" }
        refreshWeb(); scheduleAnalysis()
    }
    fun saveKey(value: String) = attempt { keyStore.save(value); notice(if (value.isBlank()) "已移除 API Key" else "API Key 已安全保存") }
    fun testKey() { viewModelScope.launch { try { ai.test(settings.value, keyStore.read()); notice("DeepSeek 连接成功") } catch (e: Exception) { notice(safeError(e, "连接失败")) } } }
    private fun allowedAnalysis(): Boolean {
        if (!recovered || !settings.value.aiEnabled || !recorder.foreground || thermalStatus >= 3 || recorder.active) return false
        val network = context.getSystemService(ConnectivityManager::class.java)
        val caps = network.getNetworkCapabilities(network.activeNetwork)
        if (settings.value.wifiOnly && caps?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) != true) return false
        val battery = context.registerReceiver(null, IntentFilter(android.content.Intent.ACTION_BATTERY_CHANGED))
        val charging = (battery?.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) ?: 0) != 0
        return !settings.value.chargingOnly || charging
    }
    fun importTranscript(id: String, input: String) {
        attempt {
            require(input.length <= 2_000_000) { "转写文件超出2MB限制" }
            val clip = requireNotNull(repo.clips.value.find { it.id == id && !it.isWriting && it.failure == null }) { "只能为完整录像导入转写" }
            val transcript = json.decodeFromString<Transcript>(input)
            require(transcript.clipID == id && transcript.locale == "zh-CN") { "clipID 或语言与素材不符" }
            transcript.validated(clip.duration)
            atomicWrite(File(root, "$id.transcript.json"), json.encodeToString(transcript))
            repo.update(id) { it.copy(transcriptionStatus = "completed", aiStatus = "pending") }
            notice("已导入并校验转写；启用 AI 后只发送文字"); scheduleAnalysis()
        }
    }
    fun retry(id: String) { attempt { repo.update(id) { it.copy(aiStatus = "pending", transcriptionStatus = if (File(root, "$id.transcript.json").exists()) "completed" else "pending") }; scheduleAnalysis() } }
    fun scheduleAnalysis() {
        if (analysisJob?.isActive == true) return
        if (!allowedAnalysis()) { analysisState.value = if (!settings.value.aiEnabled) "AI 已关闭" else "等待前台待机、合适温度、Wi-Fi 与充电条件"; return }
        analysisJob = viewModelScope.launch {
            try {
                require(keyStore.read().isNotBlank()) { "请先保存自己的 API Key" }
                for (clip in repo.clips.value.sortedBy { it.startAt }.filter { !it.isWriting && it.failure == null && it.aiStatus == "pending" }) {
                    if (!allowedAnalysis()) break
                    repo.pin(clip.id)
                    try {
                        analysisState.value = "正在转写 / 分析片段"
                        val transcriptFile = File(root, "${clip.id}.transcript.json")
                        val transcript = if (transcriptFile.exists()) json.decodeFromString<Transcript>(withContext(Dispatchers.IO) { transcriptFile.readText() }).validated(clip.duration)
                        else {
                            require(settings.value.experimentalSystemSpeech) { "请导入转写 JSON；系统文件转写尚未经本机验证，需在设置中主动开启实验功能" }
                            repo.update(clip.id) { it.copy(transcriptionStatus = "running") }
                            speech.transcribe(repo.file(clip), clip).also {
                                withContext(Dispatchers.IO) { atomicWrite(transcriptFile, json.encodeToString(it)) }
                            }
                        }
                        repo.update(clip.id) { it.copy(transcriptionStatus = "completed", aiStatus = "running") }
                        ensureActive(); require(allowedAnalysis()) { "分析条件已改变，请稍后重试" }
                        val result = ai.analyze(transcript, clip.duration, settings.value, keyStore.read())
                        ensureActive()
                        withContext(Dispatchers.IO) { atomicWrite(File(root, "${clip.id}.analysis.json"), json.encodeToString(result)) }
                        analyses.value = analyses.value + (clip.id to result)
                        repo.update(clip.id) { it.copy(aiStatus = "completed", summary = result.summary, importanceScore = result.importance_score) }
                    } catch (e: CancellationException) {
                        repo.update(clip.id) { it.copy(aiStatus = "pending", transcriptionStatus = if (File(root, "${clip.id}.transcript.json").exists()) "completed" else "pending") }; throw e
                    } catch (e: Exception) {
                        repo.update(clip.id) { it.copy(aiStatus = "failed", transcriptionStatus = if (File(root, "${clip.id}.transcript.json").exists()) "completed" else "failed") }
                        notice(safeError(e, "分析失败，不影响录像"))
                    } finally { repo.unpin(clip.id) }
                }
                analysisState.value = "分析队列已完成；失败片段可手动重试"
            } catch (e: CancellationException) { analysisState.value = "分析已暂停"; throw e }
            catch (e: Exception) { analysisState.value = safeError(e, "分析不可用") }
        }
    }
    fun stopRecording() { recordingServicePending = false; recorder.stop() }
    var recordingServicePending = false
    fun startRecording() {
        if (!recovered) { notice("素材尚未完成恢复，请等待或检查空间后重启"); return }
        if (thermalStatus >= 5) { notice("设备严重过热，请冷却后再开始"); return }
        if (recordingServicePending || recorder.active || !recorder.foreground) return
        if (!recorder.permissions()) { notice("请先允许摄像头和麦克风权限"); return }
        analysisJob?.cancel()
        recordingServicePending = true
        try { ContextCompat.startForegroundService(context, Intent(context, RecordingService::class.java)) }
        catch (_: Exception) { startRecordingFallback() }
    }
    fun startRecordingFallback() {
        recordingServicePending = false
        warn("系统未允许持续录像服务，已改为前台录制；无操作1分钟自动调暗，锁屏或离开应用会停录")
        if (recorder.foreground) recorder.start()
    }
    fun generateDaily() {
        if (analysisJob?.isActive == true) { notice("请等待当前分析完成"); return }
        if (!allowedAnalysis()) { notice("请先启用 AI，保持前台待机并满足 Wi-Fi、充电和温度条件"); return }
        analysisJob = viewModelScope.launch {
            try {
                analysisState.value = "正在生成今日总结"
                val day = LocalDate.now()
                val clips = todayClips(day).filter { it.id in analyses.value }
                val result = ai.summarize(day.toString(), clips, analyses.value.filterKeys { id -> clips.any { it.id == id } }, settings.value, keyStore.read())
                ensureActive(); withContext(Dispatchers.IO) { atomicWrite(File(root, "${result.id}.daily.json"), json.encodeToString(result)) }
                daily.value = result; analysisState.value = "今日总结已保存"
            } catch (e: CancellationException) { analysisState.value = "总结已暂停"; throw e }
            catch (e: Exception) { notice(safeError(e, "总结失败")); analysisState.value = "总结失败，可重试" }
        }
    }
    fun todayClips(day: LocalDate = LocalDate.now()) = repo.clips.value.filter { java.time.Instant.parse(it.startAt).atZone(ZoneId.systemDefault()).toLocalDate() == day }
    fun wifiAddress(): String? {
        val cm = context.getSystemService(ConnectivityManager::class.java)
        return cm.allNetworks.firstNotNullOfOrNull { network ->
            if (cm.getNetworkCapabilities(network)?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true)
                cm.getLinkProperties(network)?.linkAddresses?.map { it.address }?.firstOrNull { it is java.net.Inet4Address && it.isSiteLocalAddress }?.hostAddress else null
        }
    }
    private fun refreshWeb() {
        if (!settings.value.webEnabled || !recorder.foreground || thermalStatus >= 4) { stopWeb(); return }
        val address = wifiAddress()
        if (address == null) { stopWeb(); return }
        if (webAddress.value == "http://$address:8080") return
        try { pairing.reset(); web.start(address); webAddress.value = "http://$address:8080" }
        catch (_: Exception) { stopWeb(); notice("电脑控制无法监听8080端口，请检查网络或端口占用") }
    }
    private fun stopWeb() { web.close(); webAddress.value = ""; pairing.reset() }
    private suspend fun handleWeb(r: WebRequest): WebResponse {
        fun encoded(element: JsonElement) = WebResponse(body = element.toString())
        if (!settings.value.webEnabled || !recorder.foreground || thermalStatus >= 4) throw HTTPError(503, "请保持手机前台且温度正常")
        val expectedHost = webAddress.value.removePrefix("http://")
        if (r.headers["host"] != expectedHost) throw HTTPError(403, "主机不匹配")
        if (r.method == "GET" && r.path in listOf("/", "/app.js", "/style.css")) {
            val name = if (r.path == "/") "index.html" else r.path.drop(1)
            return WebResponse(body = context.assets.open(name).bufferedReader().use { it.readText() }, type = when {
                name.endsWith("html") -> "text/html; charset=utf-8"; name.endsWith("js") -> "text/javascript; charset=utf-8"; else -> "text/css; charset=utf-8"
            })
        }
        if (r.method == "POST") {
            if (r.headers["content-type"]?.startsWith("application/json") != true) throw HTTPError(400, "只接受JSON")
            if (r.headers["origin"] != null && r.headers["origin"] != "http://$expectedHost") throw HTTPError(403, "来源不匹配")
        }
        val body = if (r.body.isBlank()) JsonObject(emptyMap()) else runCatching { json.parseToJsonElement(r.body).jsonObject }.getOrElse { throw HTTPError(400, "JSON格式错误") }
        if (r.method == "POST" && r.path == "/api/pair") return encoded(buildJsonObject { put("token", pairing.pair(body["code"]?.jsonPrimitive?.content ?: "")) })
        if (!pairing.authorized(r.headers["authorization"])) throw HTTPError(401, "请先配对")
        if (recorder.state.value == RecorderState.RECOVERING) throw HTTPError(503, "正在恢复素材")
        try {
            when (r.method to r.path) {
                "GET" to "/api/status" -> return encoded(buildJsonObject {
                    put("name", "EverFrame"); put("recording", recorder.state.value == RecorderState.RECORDING)
                    put("busy", recorder.state.value in listOf(RecorderState.PREPARING, RecorderState.FINALIZING)); put("elapsed", recorder.elapsed.value)
                    put("todaySeconds", todayClips().sumOf { it.duration }); put("usedBytes", repo.clips.value.sumOf { it.fileSize })
                    put("freeBytes", repo.freeBytes); put("ai", analysisState.value); put("message", message.value)
                })
                "POST" to "/api/start" -> { if (!recorder.permissions()) throw HTTPError(409, "请先在手机授予摄像头和麦克风权限"); startRecording() }
                "POST" to "/api/stop" -> stopRecording()
                "POST" to "/api/keep" -> repo.keep(body.getValue("minutes").jsonPrimitive.int)
                "GET" to "/api/clips" -> return encoded(json.encodeToJsonElement(repo.clips.value.take(500)))
                "GET" to "/api/settings" -> return encoded(json.encodeToJsonElement(settings.value))
                "POST" to "/api/settings" -> updateSettings(settings.value.copy(segmentMinutes = body.getValue("segmentMinutes").jsonPrimitive.int,
                    maxStorageGB = body.getValue("maxStorageGB").jsonPrimitive.double, retentionDays = body.getValue("retentionDays").jsonPrimitive.int,
                    minimumFreeGB = body.getValue("minimumFreeGB").jsonPrimitive.double))
                "GET" to "/api/timeline" -> return encoded(buildJsonArray { todayClips().forEach { clip -> analyses.value[clip.id]?.timeline?.forEach { e -> add(buildJsonObject {
                    put("clipID", clip.id); put("startAt", java.time.Instant.ofEpochMilli(epoch(clip.startAt) + (e.start * 1000).toLong()).toString())
                    put("endAt", java.time.Instant.ofEpochMilli(epoch(clip.startAt) + (e.end * 1000).toLong()).toString()); put("title", e.title); put("summary", e.summary); put("importance", e.importance_score)
                }) } } })
                "GET" to "/api/daily-summary" -> return encoded(json.encodeToJsonElement(daily.value?.takeIf { it.id == LocalDate.now().toString() }))
                "POST" to "/api/daily-summary" -> generateDaily()
                else -> {
                    val path = r.path.split('/').filter { it.isNotEmpty() }
                    if (r.method != "POST" || path.size != 4 || path[0] != "api" || path[1] != "clips" || path[3] !in listOf("lock", "unlock") || repo.clips.value.none { it.id == path[2] }) throw HTTPError(404, "接口或素材不存在")
                    repo.lock(path[2], path[3] == "lock")
                }
            }
        } catch (e: HTTPError) { throw e } catch (e: Exception) { throw HTTPError(400, e.message ?: "参数无效") }
        return WebResponse()
    }
    override fun onCleared() {
        recorder.release(); web.close()
        if (Build.VERSION.SDK_INT >= 29 && thermalListener != null) power.removeThermalStatusListener(thermalListener)
    }
}
