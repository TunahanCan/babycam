package com.example.babycam

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Basit bir log tamponu: uygulamanın farklı yerlerinden gelen logları tutar ve
 * ekranda gösterilebilmesi için StateFlow olarak sunar.
 */
object AppLogBuffer {

    private const val MAX_LOG_COUNT = 200

    private val formatter = SimpleDateFormat("HH:mm:ss", Locale.getDefault())
    private val _logs = MutableStateFlow<List<String>>(emptyList())
    val logs: StateFlow<List<String>> = _logs.asStateFlow()

    fun log(message: String) {
        // Mesaja hızlıca okunabilir bir zaman damgası ekliyoruz; bu sayede log akışında hangi
        // olayın ne zaman gerçekleştiği kolayca görülebiliyor.
        val timestamped = "${formatter.format(Date())} • $message"
        _logs.update { current ->
            // StateFlow'u kopyalayarak güncel tutuyoruz. Maksimum log sayısı aşılırsa en eski
            // kayıtları atıp daima son MAX_LOG_COUNT öğeyi koruyoruz.
            val updated = current + timestamped
            if (updated.size > MAX_LOG_COUNT)
            {
                updated.takeLast(MAX_LOG_COUNT)
            }
            else {
                updated
            }
        }
    }

    fun clear() {
        _logs.value = emptyList()
    }
}
