package com.example.babycam

/**
 * Hareket skorunu ortam gürültüsüne göre normalleştiren ve yumuşatan sınıf.
 */
class MotionScoreCalculator(
    private var motionNoiseEstimate: Double = 0.02,
    private var smoothedMotion: Double = 0.0
) {

    fun reset() {
        motionNoiseEstimate = 0.02
        smoothedMotion = 0.0
    }

    fun calculate(rawScore: Double): Double {
        motionNoiseEstimate = if (rawScore < motionNoiseEstimate) {
            motionNoiseEstimate * 0.9 + rawScore * 0.1
        } else {
            motionNoiseEstimate * 0.995 + rawScore * 0.005
        }

        val adjusted = (rawScore - motionNoiseEstimate).coerceAtLeast(0.0)
        val dynamicRange = (1.0 - motionNoiseEstimate).coerceAtLeast(1e-3)
        val normalized = (adjusted / dynamicRange).coerceIn(0.0, 1.0)

        smoothedMotion = smoothedMotion * 0.65 + normalized * 0.35
        return smoothedMotion
    }
}
