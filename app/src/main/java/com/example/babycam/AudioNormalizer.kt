package com.example.babycam

import kotlin.math.log10
import kotlin.math.sqrt

data class NormalizationResult(
    val normalized: DoubleArray,
    val rmsDb: Double,
    val zeroCrossRate: Double
)

/**
 * Ses sinyalini normalize edip temel istatistikleri (RMS ve sıfır geçiş oranı) tek adımda toplar.
 */
class AudioNormalizer {

    private var reusableNormalizedBuffer: DoubleArray? = null

    fun normalize(samples: ShortArray, length: Int): NormalizationResult {
        val normalized = obtainNormalizedBuffer(length)
        var sumSquares = 0.0
        var zeroCrossCount = 0
        var previous = samples[0] / 32768.0
        normalized[0] = previous
        sumSquares += previous * previous

        for (i in 1 until length) {
            val sample = samples[i] / 32768.0
            normalized[i] = sample
            sumSquares += sample * sample
            if ((sample >= 0 && previous < 0) || (sample < 0 && previous >= 0)) {
                zeroCrossCount++
            }
            previous = sample
        }

        val rms = sqrt(sumSquares / length).coerceAtLeast(1e-9)
        val rmsDb = 20.0 * log10(rms)
        val zeroCrossRate = zeroCrossCount.toDouble() / (length - 1).coerceAtLeast(1)

        return NormalizationResult(normalized, rmsDb, zeroCrossRate)
    }

    private fun obtainNormalizedBuffer(requiredSize: Int): DoubleArray {
        val buffer = reusableNormalizedBuffer
        return if (buffer != null && buffer.size >= requiredSize) {
            buffer
        } else {
            DoubleArray(requiredSize).also { reusableNormalizedBuffer = it }
        }
    }
}
