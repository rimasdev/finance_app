package com.folio.folio

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony

class SmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return
        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
        if (messages.isEmpty()) return
        val body = messages.joinToString("") { it.messageBody ?: "" }
        val sender = messages.first().originatingAddress ?: ""
        val pending = goAsync()
        Thread {
            try {
                FolioIngest.send(context, body, sender)
            } finally {
                pending.finish()
            }
        }.start()
    }
}
