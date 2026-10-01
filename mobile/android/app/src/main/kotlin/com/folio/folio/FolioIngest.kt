package com.folio.folio

import android.content.Context
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import kotlin.concurrent.thread

object FolioIngest {
    private val money = Regex("(?i)(\\brs\\.?\\s*\\d|\\blkr\\s*\\d)")
    private val verb = Regex("(?i)\\b(debited|debit|credited|credit|withdrawn|withdrawal|deposited|deposit|purchase|purchased|spent)\\b")
    private val otp = Regex("(?i)\\b(otp|one[- ]time password|verification code)\\b")

    fun looksFinancial(text: String): Boolean {
        return money.containsMatchIn(text) && verb.containsMatchIn(text) && !otp.containsMatchIn(text)
    }

    fun post(context: Context, body: String, sender: String) {
        if (!looksFinancial(body)) return
        thread(name = "folio-ingest") { send(context, body, sender) }
    }

    fun send(context: Context, body: String, sender: String) {
        if (!looksFinancial(body)) return
        val prefs = context.getSharedPreferences("folio_native", Context.MODE_PRIVATE)
        if (!prefs.getBoolean("enabled", true)) return
        val token = prefs.getString("token", null) ?: return
        val base = prefs.getString("api_base", null) ?: return
        var connection: HttpURLConnection? = null
        try {
            val root = base.trimEnd('/')
            connection = (URL("$root/sms/ingest").openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                setRequestProperty("Authorization", "Bearer $token")
                setRequestProperty("Content-Type", "application/json")
                doOutput = true
                connectTimeout = 8000
                readTimeout = 8000
            }
            val payload = JSONObject()
            payload.put("body", body)
            payload.put("sender", sender)
            payload.put("manual", false)
            connection.outputStream.use { it.write(payload.toString().toByteArray()) }
            connection.responseCode
        } catch (_: Exception) {
        } finally {
            connection?.disconnect()
        }
    }
}
