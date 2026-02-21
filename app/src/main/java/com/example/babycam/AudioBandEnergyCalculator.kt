package com.example.babycam

import kotlin.math.PI
import kotlin.math.cos

/**
 * Goertzel tabanlı band enerjisi hesaplamasını ayrıştırarak yeniden kullanılabilir hale getirir.
 */
class AudioBandEnergyCalculator(private val sampleRate: Int) {

    fun averageGoertzelPower(samples: DoubleArray, length: Int, frequencies: DoubleArray): Double {
        if (frequencies.isEmpty()) return 0.0
        var total = 0.0
        for (freq in frequencies) {
            total += goertzelPower(samples, length, freq)
        }
        return total / frequencies.size
    }

    private fun goertzelPower(samples: DoubleArray, length: Int, targetFrequency: Double): Double {
        val normalizedFrequency = 2.0 * PI * targetFrequency / sampleRate
        val coeff = 2.0 * cos(normalizedFrequency)
        var sPrev = 0.0
        var sPrev2 = 0.0
        for (i in 0 until length) {
            val s = samples[i] + coeff * sPrev - sPrev2
            sPrev2 = sPrev
            sPrev = s
        }
        return sPrev2 * sPrev2 + sPrev * sPrev - coeff * sPrev * sPrev2
    }
}
