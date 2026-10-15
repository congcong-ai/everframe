package com.everframe.app

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.time.Instant
import java.util.UUID

val json = Json { ignoreUnknownKeys = true; encodeDefaults = true; prettyPrint = true }
fun nowISO(): String = Instant.now().toString()
fun epoch(value: String): Long = Instant.parse(value).toEpochMilli()

@Serializable
data class Clip(
    val id: String = UUID.randomUUID().toString(), val fileName: String,
    val createdAt: String = nowISO(), val startAt: String = nowISO(), val endAt: String? = null,
    val duration: Double = 0.0, val fileSize: Long = 0, val codec: String = "unknown",
    val width: Int = 0, val height: Int = 0, val fps: Double = 0.0,
    val locked: Boolean = false, val pendingLock: Boolean = false,
    val transcriptionStatus: String = "pending", val aiStatus: String = "pending",
    val summary: String? = null, val importanceScore: Int? = null, val failure: String? = null
) {
    val isWriting get() = endAt == null
    fun overlaps(since: Long, until: Long) = epoch(startAt) <= until && (endAt?.let(::epoch) ?: until) >= since
}
@Serializable
data class Settings(
    val segmentMinutes: Int = 10, val maxStorageGB: Double = 40.0, val retentionDays: Int = 7,
    val minimumFreeGB: Double = 15.0, val aiEnabled: Boolean = false,
    val autoAnalyze: Boolean = true, val wifiOnly: Boolean = true, val chargingOnly: Boolean = true,
    val model: String = "deepseek-flash", val webEnabled: Boolean = false,
    val experimentalSystemSpeech: Boolean = false
) {
    fun validated(): Settings {
        require(segmentMinutes in listOf(5, 10, 15, 30) && maxStorageGB in 0.3..500.0 &&
            retentionDays in 1..365 && minimumFreeGB in 1.0..100.0 && model.isNotBlank() && model.length < 100) { "设置超出允许范围" }
        return this
    }
}
object StoragePolicy {
    fun candidates(clips: List<Clip>, settings: Settings, now: Long, free: Long, pinned: Set<String> = emptySet()): List<String> {
        var remaining = free
        var used = clips.sumOf { it.fileSize }
        return clips.sortedBy { epoch(it.startAt) }.filter { clip ->
            if (clip.isWriting || clip.locked || clip.pendingLock || clip.id in pinned) false
            else if (epoch(clip.startAt) < now - settings.retentionDays * 86_400_000L || used > settings.maxStorageGB * 1e9 || remaining < settings.minimumFreeGB * 1e9) {
                used -= clip.fileSize; remaining += clip.fileSize; true
            } else false
        }.map { it.id }
    }
}
enum class RecorderState(val label: String) {
    RECOVERING("正在恢复素材"), IDLE("待机"), PREPARING("正在准备"), RECORDING("REC · 正在记录"), FINALIZING("正在保存"), ERROR("已停止，请检查提示")
}
// 续录意图独立于设备回调，停止和生命周期中断始终优先。
class RecordingIntent {
    var continueSession = false; private set
    fun start() { continueSession = true }
    fun stop() { continueSession = false }
    fun mayContinue(foreground: Boolean, successful: Boolean) = continueSession && foreground && successful
}
@Serializable data class TranscriptSegment(val start: Double, val end: Double, val text: String)
@Serializable data class Transcript(val clipID: String, val locale: String = "zh-CN", val segments: List<TranscriptSegment>) {
    fun validated(duration: Double): Transcript {
        require(segments.isNotEmpty() && segments.size <= 20000 && segments.all {
            it.start.isFinite() && it.end.isFinite() && it.start >= 0 && it.end > it.start && it.end <= duration + 1 && it.text.isNotBlank()
        }) { "转写为空或时间戳超出录像范围" }
        require(segments.zipWithNext().all { (a, b) -> a.start <= b.start }) { "转写时间戳顺序无效" }
        return this
    }
}
@Serializable data class AIEvent(val start: Double, val end: Double, val title: String, val summary: String, val importance_score: Int)
@Serializable data class Idea(val timestamp: Double, val text: String)
@Serializable data class ClipAnalysis(val summary: String, val topics: List<String>, val importance_score: Int,
    val suggested_review: Boolean, val review_reason: String, val timeline: List<AIEvent>, val ideas: List<Idea>) {
    fun validated(duration: Double): ClipAnalysis {
        require(summary.isNotBlank() && importance_score in 0..100 && timeline.size <= 100 && timeline.all {
            it.start.isFinite() && it.end.isFinite() && it.start >= 0 && it.end > it.start && it.end <= duration + 1 && it.importance_score in 0..100
        } && ideas.all { it.timestamp.isFinite() && it.timestamp >= 0 && it.timestamp <= duration + 1 }) { "AI JSON 字段或时间范围无效" }
        return this
    }
}
@Serializable data class DailyReview(val clipID: String, val reason: String)
@Serializable data class DailyPayload(val summary: String, val accomplishments: List<String>, val ideas: List<String>, val reviews: List<DailyReview>)
@Serializable data class DailySummary(val id: String, val generatedAt: String = nowISO(), val recordedSeconds: Double,
    val summary: String, val accomplishments: List<String>, val ideas: List<String>, val reviews: List<DailyReview>)
