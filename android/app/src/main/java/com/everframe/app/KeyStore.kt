package com.everframe.app

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class APIKeyStore(context: Context) {
    private val prefs = context.getSharedPreferences("ai_secrets", Context.MODE_PRIVATE)
    private val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
    private fun alias(provider: String): String = "everframe.${AIService.fromId(provider).id}"
    private fun valueName(provider: String): String = if (provider == AIService.DEEPSEEK.id) "value" else "${provider}_value"
    private fun ivName(provider: String): String = if (provider == AIService.DEEPSEEK.id) "iv" else "${provider}_iv"
    private fun key(provider: String): SecretKey = (store.getKey(alias(provider), null) as? SecretKey) ?: KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
        init(KeyGenParameterSpec.Builder(alias(provider), KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
    }.generateKey()
    fun save(provider: String, value: String) {
        AIService.fromId(provider)
        if (value.isBlank()) { check(prefs.edit().remove(valueName(provider)).remove(ivName(provider)).commit()); return }
        require(value.trim().length in 10..512 && value.trim().all { it.code in 33..126 }) { "API Key 格式无效，不能包含空白或控制字符" }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding"); cipher.init(Cipher.ENCRYPT_MODE, key(provider))
        check(prefs.edit().putString(ivName(provider), Base64.encodeToString(cipher.iv, Base64.NO_WRAP))
            .putString(valueName(provider), Base64.encodeToString(cipher.doFinal(value.trim().toByteArray()), Base64.NO_WRAP)).commit()) { "密钥保存失败" }
    }
    fun read(provider: String): String {
        AIService.fromId(provider)
        val data = prefs.getString(valueName(provider), null) ?: return ""
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(provider), GCMParameterSpec(128, Base64.decode(prefs.getString(ivName(provider), ""), Base64.NO_WRAP)))
        return cipher.doFinal(Base64.decode(data, Base64.NO_WRAP)).toString(Charsets.UTF_8)
    }
}
