package com.everframe.app

import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import java.io.File
import kotlinx.serialization.encodeToString
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

data class MediaInfo(val duration: Double, val codec: String, val width: Int, val height: Int, val fps: Double = 0.0)

class ClipRepository(val root: File, private val inspect: (File) -> MediaInfo = ::inspectMedia) {
    val clipsDir = File(root, "Clips").apply { check(mkdirs() || isDirectory) }
    private val mutable = MutableStateFlow<List<Clip>>(emptyList())
    val clips = mutable.asStateFlow()
    private val pins = java.util.concurrent.ConcurrentHashMap<String, Int>()
    val pinned: Set<String> get() = pins.keys
    @Synchronized fun pin(id: String) { pins.compute(id) { _, count -> (count ?: 0) + 1 } }
    @Synchronized fun unpin(id: String) { pins.computeIfPresent(id) { _, count -> if (count <= 1) null else count - 1 } }
    private fun metadata(clip: Clip) = File(file(clip).path.removeSuffix(".mp4") + ".json")
    fun file(clip: Clip): File {
        val candidate = File(clipsDir, clip.fileName).canonicalFile
        require(candidate.parentFile == clipsDir.canonicalFile && candidate.extension == "mp4") { "素材路径无效" }
        return candidate
    }
    @Synchronized fun save(clip: Clip) {
        atomicWrite(metadata(clip), json.encodeToString(clip))
        mutable.value = (mutable.value.filterNot { it.id == clip.id } + clip).sortedByDescending { epoch(it.startAt) }
    }
    @Synchronized fun update(id: String, change: (Clip) -> Clip) { mutable.value.find { it.id == id }?.let { save(change(it)) } }
    @Synchronized fun discardUnstarted(clip: Clip) {
        if (!file(clip).exists()) { metadata(clip).delete(); mutable.value = mutable.value.filterNot { it.id == clip.id } }
    }
    @Synchronized fun create(): Clip = Clip(fileName = "${java.util.UUID.randomUUID()}.mp4").also(::save)
    @Synchronized fun lock(id: String, value: Boolean) = update(id) { if (it.isWriting) it.copy(pendingLock = value) else it.copy(locked = value) }
    @Synchronized fun keep(minutes: Int, now: Long = System.currentTimeMillis()) {
        require(minutes in listOf(10, 30, 60)) { "保留时长无效" }
        mutable.value.filter { it.overlaps(now - minutes * 60000L, now) }.forEach { lock(it.id, true) }
    }
    @Synchronized fun delete(id: String, confirmLocked: Boolean = false) {
        val clip = mutable.value.find { it.id == id } ?: return
        require(!clip.isWriting && !clip.pendingLock && id !in pinned) { "正在写入或分析的素材不能删除" }
        require(!clip.locked || confirmLocked) { "删除保留素材需要确认" }
        val video = file(clip)
        check(!video.exists() || video.delete()) { "录像删除失败" }
        check(!metadata(clip).exists() || metadata(clip).delete()) { "索引删除失败" }
        File(root, "$id.transcript.json").delete(); File(root, "$id.analysis.json").delete()
        mutable.value = mutable.value.filterNot { it.id == id }
    }
    @Synchronized fun clean(settings: Settings): Boolean {
        StoragePolicy.candidates(mutable.value, settings, System.currentTimeMillis(), freeBytes, pinned).forEach { delete(it) }
        return mutable.value.sumOf { it.fileSize } > settings.maxStorageGB * 1e9 || freeBytes < settings.minimumFreeGB * 1e9
    }
    val freeBytes get() = clipsDir.usableSpace
    @Synchronized fun recover() {
        mutable.value = clipsDir.listFiles().orEmpty().filter { it.extension == "json" }.mapNotNull {
            runCatching {
                json.decodeFromString<Clip>(it.readText()).also { value ->
                    java.util.UUID.fromString(value.id); epoch(value.createdAt); epoch(value.startAt); value.endAt?.let(::epoch)
                    require(value.duration.isFinite() && value.duration >= 0 && value.fileSize >= 0)
                    if (!file(value).exists()) it.delete()
                }
            }.getOrNull()
        }.filter { runCatching { file(it).exists() }.getOrDefault(false) }
        clipsDir.listFiles().orEmpty().filter { it.extension == "mp4" }.forEach { video ->
            val known = mutable.value.find { it.fileName == video.name }
            val clip = known ?: Clip(fileName = video.name, startAt = java.time.Instant.ofEpochMilli(video.lastModified()).toString(), locked = true)
            if (clip.isWriting || known == null) finalize(clip.id, clip, protect = true)
            else save(clip.copy(transcriptionStatus = if (clip.transcriptionStatus == "running") "pending" else clip.transcriptionStatus,
                aiStatus = if (clip.aiStatus == "running") "pending" else clip.aiStatus))
        }
    }
    // 必须重新读取最新 pendingLock，不能用开始录像时的旧对象覆盖保护。
    fun finalize(id: String, fallback: Clip, error: String? = null, protect: Boolean = false): Boolean {
        val video = file(fallback)
        // 媒体读取可能等待厂商编解码器，不能持有仓库锁阻塞主线程的保留/停止操作。
        val checked = runCatching {
            inspect(video).also { require(it.duration.isFinite() && it.duration > 0 && video.length() > 0) }
        }
        return synchronized(this) {
            val latest = mutable.value.find { it.id == id } ?: fallback
            val media = checked.getOrNull()
            if (media != null) {
                save(latest.copy(endAt = java.time.Instant.ofEpochMilli(epoch(latest.startAt) + (media.duration * 1000).toLong()).toString(),
                    duration = media.duration, fileSize = video.length(), codec = media.codec,
                    width = media.width, height = media.height, fps = media.fps,
                    locked = latest.locked || latest.pendingLock || protect || error != null, pendingLock = false, failure = error))
                error == null
            } else {
                save(latest.copy(endAt = nowISO(), fileSize = video.length(), locked = true, pendingLock = false,
                    failure = "${error ?: "录像封装或音轨校验失败"}；已保留原文件，不能保证可播放", transcriptionStatus = "failed", aiStatus = "failed"))
                false
            }
        }
    }
}
// 临时文件与目标在同一目录，写入并同步后原子替换；失败不覆盖旧JSON。
fun atomicWrite(file: File, text: String) {
    file.parentFile?.mkdirs()
    val temp = File.createTempFile(".${file.name}.", ".tmp", file.parentFile)
    try {
        java.io.FileOutputStream(temp).use { output -> output.write(text.toByteArray(Charsets.UTF_8)); output.fd.sync() }
        java.nio.file.Files.move(temp.toPath(), file.toPath(), java.nio.file.StandardCopyOption.ATOMIC_MOVE, java.nio.file.StandardCopyOption.REPLACE_EXISTING)
    } finally { temp.delete() }
}

fun inspectMedia(video: File): MediaInfo {
    val extractor = MediaExtractor()
    var retriever: MediaMetadataRetriever? = null
    try {
        extractor.setDataSource(video.path)
        val formats = (0 until extractor.trackCount).map { extractor.getTrackFormat(it) }
        val v = formats.first { it.getString(MediaFormat.KEY_MIME)?.startsWith("video/") == true }
        require(formats.any { it.getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true }) { "录像缺少音轨" }
        retriever = MediaMetadataRetriever().apply { setDataSource(video.path) }
        val duration = requireNotNull(retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)).toDouble() / 1000
        return MediaInfo(duration, v.getString(MediaFormat.KEY_MIME) ?: "unknown", v.getInteger(MediaFormat.KEY_WIDTH), v.getInteger(MediaFormat.KEY_HEIGHT),
            retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_CAPTURE_FRAMERATE)?.toDoubleOrNull() ?: 0.0)
    } finally { extractor.release(); retriever?.release() }
}
