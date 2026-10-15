package com.everframe.app

import android.content.Context
import android.content.Intent
import android.media.*
import android.os.Build
import android.os.Bundle
import android.os.ParcelFileDescriptor
import android.speech.*
import androidx.annotation.RequiresApi
import androidx.core.content.ContextCompat
import kotlinx.coroutines.*
import java.io.File
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/** 仅使用系统端侧识别。服务不支持文件、中文或时间戳时失败，不转成在线或麦克风识别。 */
class AndroidTranscription(private val context: Context) {
    fun availability(): String = when {
        Build.VERSION.SDK_INT < 34 -> "本机系统低于 Android 14，缺少词级时间戳接口；可导入带时间戳的转写 JSON"
        !SpeechRecognizer.isOnDeviceRecognitionAvailable(context) -> "本机没有系统端侧语音识别服务；可导入转写 JSON"
        else -> "检测到端侧识别服务；离线中文、文件输入与时间戳仍需在本机实测。系统服务可能不支持所需能力"
    }
    suspend fun transcribe(file: File, clip: Clip): Transcript {
        require(Build.VERSION.SDK_INT >= 34 && SpeechRecognizer.isOnDeviceRecognitionAvailable(context)) { availability() }
        require(file.parentFile!!.usableSpace > 1_500_000_000) { "空间不足，暂停转写" }
        val segments = mutableListOf<TranscriptSegment>()
        withTimeout(clip.duration.toLong().coerceAtLeast(60) * 6000L) { withContext(Dispatchers.IO) { decodeChunks(file) { pcm, rate, channels, offset, seconds ->
            currentCoroutineContext().ensureActive()
            segments += withContext(Dispatchers.Main) {
                if (Build.VERSION.SDK_INT >= 34) recognize(pcm, rate, channels, offset, seconds)
                else error("本机缺少词级时间戳接口")
            }
        } } }
        return Transcript(clip.id, segments = segments).validated(clip.duration)
    }
    @RequiresApi(34)
    private suspend fun recognize(file: File, rate: Int, channels: Int, offset: Double, seconds: Double): List<TranscriptSegment> = withTimeout(90000) {
        val recognizer = SpeechRecognizer.createOnDeviceSpeechRecognizer(context)
        val descriptor = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
        try {
            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, "zh-CN")
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
                putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE, descriptor)
                putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_CHANNEL_COUNT, channels)
                putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_ENCODING, AudioFormat.ENCODING_PCM_16BIT)
                putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_SAMPLING_RATE, rate)
                putExtra(RecognizerIntent.EXTRA_REQUEST_WORD_TIMING, true)
                putExtra(RecognizerIntent.EXTRA_SEGMENTED_SESSION, RecognizerIntent.EXTRA_AUDIO_SOURCE)
            }
            suspendCancellableCoroutine<Unit> { cont ->
                recognizer.checkRecognitionSupport(intent, ContextCompat.getMainExecutor(context), object : RecognitionSupportCallback {
                    override fun onSupportResult(support: RecognitionSupport) {
                        val available = support.installedOnDeviceLanguages.any { it.equals("zh-CN", true) || it.equals("cmn-Hans-CN", true) }
                        if (cont.isActive) {
                            if (available) cont.resume(Unit)
                            else cont.resumeWithException(IllegalStateException("未安装离线中文识别模型，请先在系统语音设置下载；不会使用在线识别"))
                        }
                    }
                    override fun onError(error: Int) { if (cont.isActive) cont.resumeWithException(IllegalStateException("端侧服务不支持所需识别能力（$error）")) }
                })
            }
            suspendCancellableCoroutine { cont ->
                recognizer.setRecognitionListener(object : RecognitionListener {
                    override fun onReadyForSpeech(params: Bundle?) {}
                    override fun onBeginningOfSpeech() {}
                    override fun onRmsChanged(rmsdB: Float) {}
                    override fun onBufferReceived(buffer: ByteArray?) {}
                    override fun onEndOfSpeech() {}
                    override fun onPartialResults(partialResults: Bundle?) {}
                    override fun onEvent(eventType: Int, params: Bundle?) {}
                    override fun onError(error: Int) { if (cont.isActive) cont.resumeWithException(IllegalStateException("录像文件转写失败（$error）；本机服务可能不支持文件输入，未生成内容")) }
                    private val recognized = mutableListOf<RecognitionPart>()
                    override fun onResults(results: Bundle?) {
                        if (cont.isActive) cont.resumeWithException(IllegalStateException("服务未使用文件分段识别模式，无法确认完整文件已识别"))
                    }
                    override fun onSegmentResults(results: Bundle) {
                        if (!cont.isActive) return
                        val parts = results.getParcelableArrayList(SpeechRecognizer.RECOGNITION_PARTS, RecognitionPart::class.java).orEmpty()
                        if (parts.isEmpty()) cont.resumeWithException(IllegalStateException("识别服务未返回词级时间戳，无法建立可靠时间轴"))
                        else recognized.addAll(parts)
                    }
                    override fun onEndOfSegmentedSession() {
                        if (!cont.isActive) return
                        try {
                            require(recognized.isNotEmpty()) { "文件未识别到带时间戳的讲话，未生成内容" }
                            val list = recognized.mapIndexed { index, part ->
                                val start = part.timestampMillis / 1000.0
                                val end = recognized.getOrNull(index + 1)?.timestampMillis?.div(1000.0) ?: seconds
                                require(start >= 0 && start < seconds && end > start && end <= seconds + 0.1) { "识别服务返回无效时间戳" }
                                TranscriptSegment(offset + start, offset + minOf(end, seconds), part.formattedText.toString())
                            }
                            cont.resume(list)
                        } catch (e: Exception) { cont.resumeWithException(e) }
                    }
                })
                recognizer.startListening(intent)
            }
        } finally { recognizer.cancel(); recognizer.destroy(); descriptor.close() }
    }
    // MediaCodec 解码为 PCM；每次最多保存 55 秒，串行识别后立即删除，不上传音频。
    private suspend fun decodeChunks(input: File, consume: suspend (File, Int, Int, Double, Double) -> Unit) {
        val extractor = MediaExtractor()
        var decoder: MediaCodec? = null
        val temp = File(context.cacheDir, "speech-${java.util.UUID.randomUUID()}").apply { mkdirs() }
        var output: java.io.FileOutputStream? = null
        try {
            extractor.setDataSource(input.path)
            val track = (0 until extractor.trackCount).firstOrNull { extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true }
                ?: error("录像没有音轨")
            extractor.selectTrack(track)
            val format = extractor.getTrackFormat(track)
            decoder = MediaCodec.createDecoderByType(requireNotNull(format.getString(MediaFormat.KEY_MIME))).apply { configure(format, null, null, 0); start() }
            var rate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            var channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            var offset = 0.0
            val pcm = File(temp, "chunk.pcm")
            var size = 0L
            output = pcm.outputStream()
            var inputEnded = false; var outputEnded = false
            val info = MediaCodec.BufferInfo()
            while (!outputEnded) {
                currentCoroutineContext().ensureActive()
                if (!inputEnded) {
                    val index = decoder.dequeueInputBuffer(10000)
                    if (index >= 0) {
                        val buffer = requireNotNull(decoder.getInputBuffer(index)); val length = extractor.readSampleData(buffer, 0)
                        if (length < 0) { decoder.queueInputBuffer(index, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM); inputEnded = true }
                        else { decoder.queueInputBuffer(index, 0, length, extractor.sampleTime, 0); extractor.advance() }
                    }
                }
                val index = decoder.dequeueOutputBuffer(info, 10000)
                if (index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    val decoded = decoder.outputFormat
                    rate = decoded.getInteger(MediaFormat.KEY_SAMPLE_RATE); channels = decoded.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                    require(!decoded.containsKey(MediaFormat.KEY_PCM_ENCODING) || decoded.getInteger(MediaFormat.KEY_PCM_ENCODING) == AudioFormat.ENCODING_PCM_16BIT) { "本机解码器未输出16位PCM" }
                }
                if (index >= 0) {
                    val buffer = requireNotNull(decoder.getOutputBuffer(index)); buffer.position(info.offset); buffer.limit(info.offset + info.size)
                    val bytesPerSecond = rate * channels * 2
                    while (buffer.hasRemaining()) {
                        val count = minOf(buffer.remaining(), (55L * bytesPerSecond - size).toInt())
                        val bytes = ByteArray(count); buffer.get(bytes); output!!.write(bytes); size += count
                        if (size >= 55L * bytesPerSecond) {
                            output!!.close(); consume(pcm, rate, channels, offset, size.toDouble() / bytesPerSecond)
                            offset += size.toDouble() / bytesPerSecond; size = 0; output = pcm.outputStream()
                        }
                    }
                    outputEnded = info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                    decoder.releaseOutputBuffer(index, false)
                }
            }
            output!!.close(); output = null
            if (size > 0) consume(pcm, rate, channels, offset, size.toDouble() / (rate * channels * 2))
        } finally { output?.close(); runCatching { decoder?.stop() }; decoder?.release(); extractor.release(); temp.deleteRecursively() }
    }
}
