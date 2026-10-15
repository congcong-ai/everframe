package com.everframe.app

import org.junit.Test
import org.junit.Assert.*

class WebTests {
    private fun read(raw: String) = HTTPParser.read(raw.byteInputStream())
    @Test fun `正确解析JSON请求`() {
        val r = read("POST /api/keep HTTP/1.1\r\nHost: 192.168.1.2:8080\r\nContent-Length: 14\r\nContent-Type: application/json\r\n\r\n{\"minutes\":10}")
        assertEquals("/api/keep", r.path); assertEquals("{\"minutes\":10}", r.body)
    }
    @Test fun `拒绝重复长度和分块传输`() {
        assertThrows(HTTPError::class.java) { read("POST /api/start HTTP/1.1\r\nHost: phone\r\nContent-Length: 0\r\nContent-Length: 2\r\n\r\n") }
        assertThrows(HTTPError::class.java) { read("POST / HTTP/1.1\r\nHost: phone\r\nTransfer-Encoding: chunked\r\n\r\n") }
    }
    @Test fun `拒绝超大与不完整请求`() {
        assertThrows(HTTPError::class.java) { read("POST / HTTP/1.1\r\nHost: phone\r\nContent-Length: 65537\r\n\r\n") }
        assertThrows(HTTPError::class.java) { read("POST / HTTP/1.1\r\nHost: phone\r\nContent-Length: 3\r\n\r\n{}") }
        assertThrows(HTTPError::class.java) { read("GET / HTTP/1.1\r\nHost: " + "a".repeat(17000) + "\r\n\r\n") }
    }
    @Test fun `拒绝路径穿越与非规范换行`() {
        assertThrows(HTTPError::class.java) { read("GET /../secrets HTTP/1.1\r\nHost: phone\r\n\r\n") }
        assertThrows(HTTPError::class.java) { read("GET / HTTP/1.1\nHost: phone\n\n") }
    }
    @Test fun `匿名无法访问且令牌过期作废`() {
        var clock = 1000L; val pairing = PairingStore { clock }
        assertFalse(pairing.authorized(null)); val token = pairing.pair(pairing.code)
        assertEquals(64, token.length); assertTrue(pairing.authorized("Bearer $token"))
        clock += 12 * 3600_000L; assertFalse(pairing.authorized("Bearer $token"))
    }
    @Test fun `五次错误后冷却及重新配对作废旧令牌`() {
        var clock = 1000L; val pairing = PairingStore { clock }
        val token = pairing.pair(pairing.code)
        repeat(5) { assertThrows(HTTPError::class.java) { pairing.pair("错误") } }
        assertThrows(HTTPError::class.java) { pairing.pair(pairing.code) }
        clock += 60001; assertTrue(pairing.pair(pairing.code).isNotBlank())
        pairing.reset(); assertFalse(pairing.authorized("Bearer $token"))
    }
    @Test fun `最多保留八个有效会话`() {
        val pairing = PairingStore(); val first = pairing.pair(pairing.code)
        repeat(8) { pairing.pair(pairing.code) }; assertFalse(pairing.authorized("Bearer $first"))
    }
}
