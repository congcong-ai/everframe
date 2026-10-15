package com.everframe.app

import org.junit.Test
import org.junit.Assert.*
import org.junit.Rule
import org.junit.rules.TemporaryFolder
import java.io.File

// 测真实文件与索引；注入的媒体检查只模拟设备返回，不冒充真实MP4验证。
class RepositoryTests {
    @get:Rule val temp = TemporaryFolder()
    private fun repo(valid: Boolean = true) = ClipRepository(temp.root) {
        if (!valid) error("无法封装")
        MediaInfo(60.0, "video/avc", 720, 1280, 30.0)
    }
    @Test fun `当前段保留持久化且旧回调不能覆盖pendingLock`() {
        val repository = repo(); val stale = repository.create()
        repository.file(stale).writeBytes(ByteArray(32))
        repository.keep(10)
        val persisted = json.decodeFromString<Clip>(File(repository.file(stale).path.removeSuffix(".mp4") + ".json").readText())
        assertTrue(persisted.pendingLock)
        assertTrue(repository.finalize(stale.id, stale))
        assertTrue(repository.clips.value.single().locked); assertFalse(repository.clips.value.single().pendingLock)
    }
    @Test fun `异常退出与损坏文件保守保护且不删除原件`() {
        val repository = repo(false); val clip = repository.create(); repository.file(clip).writeText("损坏视频")
        repository.recover()
        val recovered = repository.clips.value.single()
        assertTrue(recovered.locked); assertNotNull(recovered.failure); assertFalse(recovered.isWriting)
        assertEquals("损坏视频", repository.file(clip).readText())
    }
    @Test fun `孤立视频及损坏索引不会导致视频丢失`() {
        val repository = repo()
        File(repository.clipsDir, "orphan.mp4").writeText("视频夹具")
        File(repository.clipsDir, "orphan.json").writeText("{坏掉的JSON")
        repository.recover()
        assertTrue(repository.clips.value.single().locked)
        assertTrue(File(repository.clipsDir, "orphan.mp4").exists())
    }
    @Test fun `无视频的孤立索引不会显示为正常素材`() {
        val repository = repo(); repository.create(); repository.recover()
        assertTrue(repository.clips.value.isEmpty())
    }
    @Test fun `保护删除需要确认且引用计数最后释放才允许删除`() {
        val repository = repo(); val clip = repository.create(); repository.file(clip).writeText("夹具")
        repository.finalize(clip.id, clip); repository.lock(clip.id, true)
        assertThrows(IllegalArgumentException::class.java) { repository.delete(clip.id) }
        repository.pin(clip.id); repository.pin(clip.id); repository.unpin(clip.id)
        assertThrows(IllegalArgumentException::class.java) { repository.delete(clip.id, true) }
        repository.unpin(clip.id); repository.delete(clip.id, true)
        assertFalse(repository.file(clip).exists()); assertTrue(repository.clips.value.isEmpty())
    }
    @Test fun `拒绝私有目录路径穿越`() {
        assertThrows(IllegalArgumentException::class.java) { repo().file(Clip(fileName = "../secrets.mp4")) }
    }
    @Test fun `元数据原子替换且不残留临时文件`() {
        val file = File(temp.root, "settings.json")
        atomicWrite(file, "旧版本"); atomicWrite(file, "新版本")
        assertEquals("新版本", file.readText()); assertEquals(listOf("settings.json"), temp.root.listFiles()!!.map { it.name })
    }
    @Test fun `媒体检查等待时仍可保护且结束读取最新保护状态`() {
        val inspecting = java.util.concurrent.CountDownLatch(1)
        val finish = java.util.concurrent.CountDownLatch(1)
        val repository = ClipRepository(temp.root) {
            inspecting.countDown(); check(finish.await(5, java.util.concurrent.TimeUnit.SECONDS))
            MediaInfo(60.0, "video/avc", 720, 1280)
        }
        val clip = repository.create(); repository.file(clip).writeText("模拟设备文件")
        val threads = java.util.concurrent.Executors.newFixedThreadPool(2)
        try {
            val finalizing = threads.submit<Boolean> { repository.finalize(clip.id, clip) }
            assertTrue(inspecting.await(5, java.util.concurrent.TimeUnit.SECONDS))
            threads.submit { repository.keep(10) }.get(3, java.util.concurrent.TimeUnit.SECONDS)
            finish.countDown(); assertTrue(finalizing.get(5, java.util.concurrent.TimeUnit.SECONDS))
            assertTrue(repository.clips.value.single().locked)
        } finally { finish.countDown(); threads.shutdownNow() }
    }

}
