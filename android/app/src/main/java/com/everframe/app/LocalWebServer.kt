package com.everframe.app

import java.io.BufferedInputStream
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.concurrent.Executors
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.*

class HTTPError(val code: Int, override val message: String) : Exception(message)
data class WebRequest(val method: String, val path: String, val headers: Map<String, String>, val body: String)
data class WebResponse(val status: Int = 200, val body: String = "{\"ok\":true}", val type: String = "application/json; charset=utf-8")
class PairingStore(private val clock: () -> Long = System::currentTimeMillis) {
    private val random = SecureRandom()
    var code: String = ""; private set
    private val sessions = linkedMapOf<String, Long>()
    private var failures = 0
    private var blockedUntil = 0L
    init { reset() }
    @Synchronized fun reset() { code = "%06d".format(random.nextInt(1_000_000)); sessions.clear(); failures = 0; blockedUntil = 0 }
    @Synchronized fun pair(candidate: String): String {
        if (clock() < blockedUntil) throw HTTPError(429, "尝试过多，请一分钟后重试")
        if (!MessageDigest.isEqual(candidate.toByteArray(), code.toByteArray())) {
            failures++
            if (failures >= 5) { blockedUntil = clock() + 60000; failures = 0 }
            throw HTTPError(429, "配对码错误")
        }
        sessions.entries.removeAll { it.value <= clock() }
        if (sessions.size >= 8) sessions.remove(sessions.keys.first())
        val token = ByteArray(32).also(random::nextBytes).joinToString("") { "%02x".format(it.toInt() and 255) }
        sessions[token] = clock() + 12 * 3600_000L; failures = 0
        return token
    }
    @Synchronized fun authorized(header: String?) = header?.takeIf { it.startsWith("Bearer ") }?.removePrefix("Bearer ")?.let { (sessions[it] ?: 0) > clock() } ?: false
}
object HTTPParser {
    fun read(input: java.io.InputStream): WebRequest {
        var total = 0
        fun line(): String {
            val bytes = java.io.ByteArrayOutputStream()
            while (true) {
                val b = input.read(); if (b < 0) throw HTTPError(400, "请求不完整")
                total++; if (total > 16384 || bytes.size() > 4096) throw HTTPError(413, "请求头过大")
                if (b == 10) {
                    val data = bytes.toByteArray()
                    if (data.isEmpty() || data.last() != 13.toByte()) throw HTTPError(400, "请求行格式无效")
                    return String(data, 0, data.size - 1, Charsets.US_ASCII)
                }
                bytes.write(b)
            }
        }
        val first = line().split(' ')
        if (first.size != 3 || first[2] != "HTTP/1.1" || first[0] !in listOf("GET", "POST") || !first[1].startsWith('/') || first[1].contains("..")) throw HTTPError(400, "HTTP 请求无效")
        val headers = linkedMapOf<String, String>()
        while (true) {
            val raw = line(); if (raw.isEmpty()) break
            val index = raw.indexOf(':'); if (index <= 0) throw HTTPError(400, "请求头无效")
            val key = raw.substring(0, index).lowercase()
            if (!key.matches(Regex("[a-z0-9-]+")) || headers.containsKey(key)) throw HTTPError(400, "请求头重复或无效")
            headers[key] = raw.substring(index + 1).trim()
        }
        if (headers["host"].isNullOrBlank() || "transfer-encoding" in headers) throw HTTPError(400, "不支持的传输格式")
        val length = headers["content-length"]?.toIntOrNull() ?: if ("content-length" in headers) -1 else 0
        if (length !in 0..65536) throw HTTPError(413, "请求体过大或长度无效")
        val body = ByteArray(length)
        var offset = 0
        while (offset < length) { val count = input.read(body, offset, length - offset); if (count <= 0) throw HTTPError(400, "请求体不完整"); offset += count }
        return WebRequest(first[0], first[1], headers, body.toString(Charsets.UTF_8))
    }
}
class LocalWebServer(private val handle: suspend (WebRequest) -> WebResponse, private val notice: (String) -> Unit) {
    private var server: ServerSocket? = null
    private var workers: ThreadPoolExecutor? = null
    private var acceptor: java.util.concurrent.ExecutorService? = null
    private val sockets = java.util.concurrent.ConcurrentHashMap.newKeySet<Socket>()
    val port: Int get() = server?.localPort ?: 0
    fun start(address: String, port: Int = 8080) {
        close()
        val listener = ServerSocket().apply { reuseAddress = true; bind(java.net.InetSocketAddress(InetAddress.getByName(address), port), 8) }
        server = listener
        val pool = ThreadPoolExecutor(4, 4, 0, TimeUnit.SECONDS, ArrayBlockingQueue(8))
        workers = pool
        acceptor = Executors.newSingleThreadExecutor().also { executor -> executor.execute {
            try {
                while (!listener.isClosed) {
                    val socket = listener.accept(); socket.soTimeout = 5000
                    if (!socket.inetAddress.isSiteLocalAddress && !socket.inetAddress.isLoopbackAddress) { socket.close(); continue }
                    sockets.add(socket)
                    try { pool.execute { serve(socket) } } catch (_: java.util.concurrent.RejectedExecutionException) { sockets.remove(socket); socket.close() }
                }
            } catch (_: Exception) { if (!listener.isClosed) notice("电脑控制监听失败，请重新开启") }
        } }
    }
    private fun serve(socket: Socket) {
        socket.use {
            try {
                val response = try {
                    val request = HTTPParser.read(BufferedInputStream(it.getInputStream()))
                    runBlocking { withTimeout(6000) { withContext(Dispatchers.Main) { handle(request) } } }
                } catch (e: HTTPError) { WebResponse(e.code, kotlinx.serialization.json.buildJsonObject { put("error", kotlinx.serialization.json.JsonPrimitive(e.message)) }.toString()) }
                catch (_: Exception) { WebResponse(400, "{\"error\":\"请求未完成，请稍后重试\"}") }
                val bytes = response.body.toByteArray(Charsets.UTF_8)
                it.getOutputStream().apply {
                    write(("HTTP/1.1 ${response.status} Response\r\nContent-Type: ${response.type}\r\nContent-Length: ${bytes.size}\r\nConnection: close\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nContent-Security-Policy: default-src 'self'; script-src 'self'; style-src 'self'; frame-ancestors 'none'\r\n\r\n").toByteArray(Charsets.US_ASCII))
                    write(bytes); flush()
                }
            } catch (_: Exception) { } finally { sockets.remove(it) }
        }
    }
    fun close() { server?.close(); server = null; sockets.forEach { runCatching { it.close() } }; sockets.clear(); workers?.shutdownNow(); acceptor?.shutdownNow() }
}
