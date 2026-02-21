package com.example.babycam

import kotlin.math.log10
import kotlin.math.max

/**
 * Ses analizi için gelişmiş özellik çıkarımı.
 *  - RMS ses seviyesi (dB)
 *  - Goertzel band enerjisi ile ağlama bandı yoğunluğu
 *  - Sıfır geçiş oranı (sesin çığlık/konuşma benzeri olup olmadığını anlamak için)
 *  - Adaptif ortam gürültü tahmini
 *
 * Çıktı olarak anlık ve yumuşatılmış "cryScore" döner.
 */

class AudioPatternAnalyzer(
    private val sampleRate: Int,
    private val cryBandFrequencies: DoubleArray = doubleArrayOf(400.0, 550.0, 700.0, 900.0, 1150.0, 1500.0),
    private val lowBandFrequencies: DoubleArray = doubleArrayOf(80.0, 120.0, 180.0, 250.0),
    private val highBandFrequencies: DoubleArray = doubleArrayOf(2200.0, 2600.0, 3200.0, 3800.0)
) {

    data class Analysis(
        val rmsDb: Double,
        val cryBandDb: Double,
        val bandBalanceDb: Double,
        val zeroCrossRate: Double,
        val instantaneousScore: Double,
        val smoothedScore: Double
    )

    private val ambientTracker = AudioAmbientTracker()
    private var smoothedScore = 0.0
    private val normalizer = AudioNormalizer()
    private val bandEnergyCalculator = AudioBandEnergyCalculator(sampleRate)

    fun analyze(samples: ShortArray, length: Int): Analysis {
        if (length <= 0) {
            return Analysis(
                rmsDb = -120.0,
                cryBandDb = -120.0,
                bandBalanceDb = -40.0,
                zeroCrossRate = 0.0,
                instantaneousScore = 0.0,
                smoothedScore = smoothedScore
            )
        }

        val normalization = normalizer.normalize(samples, length)
        val normalized = normalization.normalized
        val rmsDb = normalization.rmsDb

        // Goertzel algoritması belirli frekans bantlarının enerjisini FFT'ye göre çok daha
        // düşük maliyetle hesaplamamıza yardımcı oluyor. Bebek ağlamaları tipik olarak orta
        // frekanslarda yoğunlaştığı için cryBandFrequencies dizisini hedefliyoruz.
        val cryBandEnergy = bandEnergyCalculator.averageGoertzelPower(normalized, length, cryBandFrequencies)
        val refBandEnergy = max(
            bandEnergyCalculator.averageGoertzelPower(normalized, length, lowBandFrequencies) * 0.5 +
                bandEnergyCalculator.averageGoertzelPower(normalized, length, highBandFrequencies) * 0.5,
            1e-12
        )

        val cryBandDb = 10.0 * log10(cryBandEnergy + 1e-12)
        val refBandDb = 10.0 * log10(refBandEnergy)
        val bandBalanceDb = cryBandDb - refBandDb

        val zeroCrossRate = normalization.zeroCrossRate

        ambientTracker.update(rmsDb, bandBalanceDb)

        // Ortam gürültüsüne göre adaptif normalizasyon: dbBoost ve bandBoost değerleri
        // mevcut durumun arka planın ne kadar üzerine çıktığını temsil eder.
        val dbBoost = (rmsDb - ambientTracker.ambientDb()).coerceAtLeast(0.0)
        val bandBoost = (bandBalanceDb - ambientTracker.ambientBandBalance()).coerceAtLeast(0.0)
        val zeroCrossComponent = ((zeroCrossRate - 0.08) / 0.35).coerceIn(0.0, 1.0)

        val instantaneousScore =
            0.55 * (dbBoost / 22.0).coerceIn(0.0, 1.0) +
            0.35 * (bandBoost / 10.0).coerceIn(0.0, 1.0) +
            0.10 * zeroCrossComponent

        // Üstel hareketli ortalama, cryScore'un daha kararlı olmasını sağlarken ani artışları
        // da yeterince hızlı yakalar.
        smoothedScore = smoothedScore * 0.7 + instantaneousScore * 0.3

        return Analysis(
            rmsDb = rmsDb,
            cryBandDb = cryBandDb,
            bandBalanceDb = bandBalanceDb,
            zeroCrossRate = zeroCrossRate,
            instantaneousScore = instantaneousScore,
            smoothedScore = smoothedScore
        )
    }
}
