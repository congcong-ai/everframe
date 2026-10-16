package com.everframe.app

import org.junit.Assert.*
import org.junit.Test
import kotlinx.serialization.encodeToString
import java.time.Instant

class CoreTests {
    private val now = Instant.parse("2026-10-15T10:00:00Z").toEpochMilli()
    private fun clip(startMinutesAgo: Int, endMinutesAgo: Int? = 0, size: Long = 1_000_000_000, locked: Boolean = false, pending: Boolean = false): Clip = Clip(
        fileName = "test.mp4", startAt = Instant.ofEpochMilli(now - startMinutesAgo * 60000L).toString(),
        endAt = endMinutesAgo?.let { Instant.ofEpochMilli(now - it * 60000L).toString() }, fileSize = size, locked = locked, pendingLock = pending)
    @Test fun `窗口保护完整相交段及边界`() {
        assertTrue(clip(20, 9).overlaps(now - 600000, now))
        assertTrue(clip(20, 10).overlaps(now - 600000, now))
        assertTrue(clip(1, null).overlaps(now - 600000, now))
        assertFalse(clip(30, 11).overlaps(now - 600000, now))
    }
    @Test fun `循环清理从最老开始直到达到配额`() {
        val old = clip(30, 20); val recent = clip(20, 10); val latest = clip(10, 0)
        assertEquals(listOf(old.id), StoragePolicy.candidates(listOf(latest, old, recent), Settings(maxStorageGB = 2.0), now, 20_000_000_000))
    }
    @Test fun `正在写入及各种保护均不可循环删除`() {
        val clips = listOf(clip(20, null), clip(30, 20, locked = true), clip(30, 20, pending = true), clip(30, 20))
        assertEquals(emptyList<String>(), StoragePolicy.candidates(clips, Settings(maxStorageGB = 0.3), now, 0, setOf(clips.last().id)))
    }
    @Test fun `低空间清理按释放量计算`() {
        val clips = listOf(clip(30, 20), clip(20, 10), clip(10, 0))
        assertEquals(clips.take(2).map { it.id }, StoragePolicy.candidates(clips, Settings(minimumFreeGB = 2.0), now, 0))
    }
    @Test fun `过期未保护片段会清理`() {
        val expired = clip(8 * 24 * 60, 7 * 24 * 60)
        assertEquals(listOf(expired.id), StoragePolicy.candidates(listOf(expired), Settings(), now, 20_000_000_000))
    }
    @Test fun `空间充足不删除新片段`() {
        assertTrue(StoragePolicy.candidates(listOf(clip(10, 0)), Settings(), now, 20_000_000_000).isEmpty())
    }
    @Test fun `停止优先于切段续录`() {
        val intent = RecordingIntent(); intent.start()
        assertTrue(intent.mayContinue(true, true)); intent.stop(); assertFalse(intent.mayContinue(true, true))
    }
    @Test fun `后台及错误均不允许自动续录`() {
        val intent = RecordingIntent(); intent.start()
        assertFalse(intent.mayContinue(false, true)); assertFalse(intent.mayContinue(true, false))
    }
    @Test fun `持续服务允许锁屏后跨段续录但停止和失败优先`() {
        val intent = RecordingIntent(); intent.start()
        assertTrue(intent.mayContinue(false, true, serviceActive = true))
        assertFalse(intent.mayContinue(false, true, serviceActive = false))
        assertFalse(intent.mayContinue(false, false, serviceActive = true))
        intent.stop()
        assertFalse(intent.mayContinue(false, true, serviceActive = true))
        assertFalse(intent.mayContinue(true, true, serviceActive = true))
    }
    @Test fun `录制空闲一分钟及触摸重置停止后台取消`() {
        val idle = RecordingIdleDeadline()
        idle.reset(true, true, 100_000)
        assertFalse(idle.expired(159_999)); assertTrue(idle.expired(160_000))
        idle.reset(true, true, 150_000)
        assertFalse(idle.expired(160_000)); assertTrue(idle.expired(210_000))
        idle.reset(false, true, 200_000); assertFalse(idle.expired(1_000_000))
        idle.reset(true, false, 200_000); assertFalse(idle.expired(1_000_000))
    }
    @Test fun `默认关闭AI与实验转写`() {
        assertFalse(Settings().aiEnabled); assertFalse(Settings().experimentalSystemSpeech)
    }
    @Test fun `拒绝无效设置`() {
        assertThrows(IllegalArgumentException::class.java) { Settings(segmentMinutes = 1).validated() }
        assertThrows(IllegalArgumentException::class.java) { Settings(maxStorageGB = Double.NaN).validated() }
        assertThrows(IllegalArgumentException::class.java) { Settings(retentionDays = 0).validated() }
    }
    @Test fun `转写必须有有效真实时间戳`() {
        Transcript("id", segments = listOf(TranscriptSegment(1.0, 2.0, "中文测试"))).validated(10.0)
        assertThrows(IllegalArgumentException::class.java) { Transcript("id", segments = emptyList()).validated(10.0) }
        assertThrows(IllegalArgumentException::class.java) { Transcript("id", segments = listOf(TranscriptSegment(10.0, 20.0, "越界"))).validated(10.0) }
        assertThrows(IllegalArgumentException::class.java) { Transcript("id", segments = listOf(TranscriptSegment(Double.NaN, 2.0, "错误"))).validated(10.0) }
    }
    @Test fun `AI范围与分数严格校验`() {
        val analysis = ClipAnalysis("摘要", listOf("工作"), 80, true, "思考", listOf(AIEvent(0.0, 2.0, "标题", "摘要", 90)), emptyList())
        assertEquals(analysis, analysis.validated(10.0))
        assertThrows(IllegalArgumentException::class.java) { analysis.copy(importance_score = 101).validated(10.0) }
        assertThrows(IllegalArgumentException::class.java) { analysis.copy(timeline = listOf(AIEvent(2.0, 1.0, "错误", "", 1))).validated(10.0) }
    }
    @Test fun `数据往返保留保护状态并采用ISO日期`() {
        val value = clip(10, null, pending = true)
        val text = json.encodeToString(value)
        assertTrue(text.contains("2026-10-15")); assertEquals(value, json.decodeFromString<Clip>(text))
    }
}

class SharedProtocolTests {
    @Test fun `共享中文样例可以被Android严格解码`() {
        val transcript = json.decodeFromString<Transcript>(javaClass.getResource("/transcript.zh-CN.json")!!.readText()).validated(60.0)
        val analysis = json.decodeFromString<ClipAnalysis>(javaClass.getResource("/analysis.zh-CN.json")!!.readText()).validated(60.0)
        assertEquals(55.0, transcript.segments[1].start, 0.0)
        assertEquals(75, analysis.importance_score)
    }
}
