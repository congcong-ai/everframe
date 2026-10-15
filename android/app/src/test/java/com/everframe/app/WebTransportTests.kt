package com.everframe.app

import kotlinx.coroutines.*
import kotlinx.coroutines.test.setMain
import kotlinx.coroutines.test.resetMain
import org.junit.Test
import org.junit.Assert.*
import java.net.Socket
import java.util.concurrent.Executors

@OptIn(ExperimentalCoroutinesApi::class)
class WebTransportTests {
    @Test fun `真实TCP支持碎片请求并在关闭后释放端口`() {
        val dispatcher = Executors.newSingleThreadExecutor().asCoroutineDispatcher()
        Dispatchers.setMain(dispatcher)
        val server = LocalWebServer({ request -> WebResponse(body = "{\"path\":\"${request.path}\",\"body\":${request.body}}") }, {})
        try {
            server.start("127.0.0.1", 0)
            val port = server.port
            Socket("127.0.0.1", port).use { socket ->
                socket.soTimeout = 5000
                val request = "POST /api/keep HTTP/1.1\r\nHost: 127.0.0.1:$port\r\nContent-Length: 14\r\nContent-Type: application/json\r\n\r\n{\"minutes\":10}"
                val output = socket.getOutputStream()
                request.toByteArray().forEach { output.write(byteArrayOf(it)); output.flush() }
                val response = socket.getInputStream().bufferedReader().readText()
                assertTrue(response.startsWith("HTTP/1.1 200")); assertTrue(response.contains("\"minutes\":10")); assertTrue(response.contains("Connection: close"))
            }
            Socket("127.0.0.1", port).use { socket ->
                socket.soTimeout = 5000
                socket.getOutputStream().write("GET / HTTP/1.1\r\nHost: test\r\nContent-Length: 999999\r\n\r\n".toByteArray())
                assertTrue(socket.getInputStream().bufferedReader().readText().startsWith("HTTP/1.1 413"))
            }
            server.close()
            java.net.ServerSocket().use { it.reuseAddress = true; it.bind(java.net.InetSocketAddress("127.0.0.1", port)) }
        } finally { server.close(); Dispatchers.resetMain(); dispatcher.close() }
    }
}
