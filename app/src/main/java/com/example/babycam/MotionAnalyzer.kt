package com.example.babycam

import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import kotlin.math.abs

/**
 * Basit ama işe yarar hareket analizi:
 * - YUV_420_888 Y (luma) kanalı alınır.
 * - Her 4 pikselde bir örneklenir (downsample).
 * - İlk kare background olarak alınır.
 * - ∑|frame - background| ile hareket skoru hesaplanır.
 * - Background yavaşça güncellenir (running average).
 */
class MotionAnalyzer(
    private val onMotionScore: (score: Double) -> Unit,
    private val onFrameEncoded: ((ByteArray) -> Unit)? = null
) : ImageAnalysis.Analyzer {

    private var background: DoubleArray? = null
    private val sampleStep = 4
    private val lumaDownsampler = LumaDownsampler(sampleStep)
    private val motionScoreCalculator = MotionScoreCalculator()

    override fun analyze(image: ImageProxy) {
        try {
            val yPlane = image.planes.firstOrNull() ?: return
            val buffer = yPlane.buffer
            val width = image.width
            val height = image.height
            val rowStride = yPlane.rowStride

            // Luma kanalını ByteArray'e kopyalamak yerine doğrudan ByteBuffer üzerinden
            // örnekliyoruz; bu sayede her karede ek allocasyon yapılmadan GC baskısı azalıyor
            // ve düşük güçlü cihazlarda kare başına gecikme daha tutarlı kalıyor.
            val sampled = lumaDownsampler.downsample(buffer, width, height, rowStride)

            val backgroundBuffer = background
            if (backgroundBuffer == null || backgroundBuffer.size != sampled.size) {
                // İlk kareyi referans arka plan olarak alıyoruz. Kullanıcı kamerayı yeni
                // açtığında ortam statiktir; bu yüzden arka planı sıfırdan doldurmak en
                // doğru başlangıç kabulü olur.
                background = sampled.copyOf()
                motionScoreCalculator.reset()
                onMotionScore(0.0)
            } else {
                var diffSum = 0.0
                for (i in sampled.indices) {
                    // Her örnek noktasında mutlak farkı toplayarak hareket enerjisini
                    // ölçüyoruz. Bu değer ne kadar yüksekse arka plan ile mevcut kare
                    // arasındaki fark o kadar yüksek demektir.
                    val currentSample = sampled[i]
                    val bgValue = backgroundBuffer[i]
                    diffSum += abs(currentSample - bgValue)
                    // Arka planı yavaşça güncellemek (running average) yeni ışık değişimlerine
                    // uyum sağlamamızı sağlar. Küçük katsayılar ani değişimleri filtreler.
                    backgroundBuffer[i] = bgValue * 0.96 + currentSample * 0.04
                }

                // normalize edilen skor 0..1 aralığına sıkıştırılıyor. Bu skor daha sonra
                // adaptMotionScore ile ortam gürültüsüne göre dinamik olarak yeniden ölçekleniyor.
                val rawScore = (diffSum / (sampled.size * 255.0)).coerceIn(0.0, 1.0)
                val adaptiveScore = motionScoreCalculator.calculate(rawScore)
                onMotionScore(adaptiveScore)
            }
            onFrameEncoded?.let { callback ->
                ImageUtils.imageProxyToJpeg(image)?.let(callback)
            }
        } finally {
            image.close()
        }
    }

}
