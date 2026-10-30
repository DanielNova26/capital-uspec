package com.todogestion.app

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Recovery storage only for offline visits. Never resets shared login keys. */
class VisitasSecureStorage(context: Context) {
    private val prefs = context.getSharedPreferences("VisitasOfflineSecureV2", Context.MODE_PRIVATE)
    private val alias = "com.todogestion.app.visitas.offline.v2"

    private fun secret(create: Boolean): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val existing = store.getKey(alias, null)
        if (existing != null) return existing as SecretKey
        check(create) { "Missing offline key" }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").run {
            init(KeyGenParameterSpec.Builder(alias,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256).build())
            generateKey()
        }
    }

    fun read(key: String): String? {
        val value = prefs.getString(key, null) ?: return null
        val bytes = Base64.decode(value, Base64.NO_WRAP)
        require(bytes.size >= 28)
        return Cipher.getInstance("AES/GCM/NoPadding").run {
            init(Cipher.DECRYPT_MODE, secret(false), GCMParameterSpec(128, bytes.copyOfRange(0, 12)))
            updateAAD(key.toByteArray(Charsets.UTF_8))
            String(doFinal(bytes.copyOfRange(12, bytes.size)), Charsets.UTF_8)
        }
    }

    fun write(key: String, value: String) {
        // Do not replace the key if records exist but its Keystore entry is lost.
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, secret(prefs.all.isEmpty()))
        cipher.updateAAD(key.toByteArray(Charsets.UTF_8))
        val bytes = cipher.iv + cipher.doFinal(value.toByteArray(Charsets.UTF_8))
        check(prefs.edit().putString(key, Base64.encodeToString(bytes, Base64.NO_WRAP)).commit())
    }

    fun delete(key: String) {
        check(prefs.edit().remove(key).commit())
    }
}
