package com.example.babycam

import android.graphics.ImageFormat
import android.graphics.Rect
import android.graphics.YuvImage
import androidx.camera.core.ImageProxy
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer

object ImageUtils {

    fun imageProxyToJpeg(image: ImageProxy, quality: Int = 70): ByteArray? {
        if (image.format != ImageFormat.YUV_420_888) {
            return null
        }
        // CameraX'ten gelen YUV_420_888 formatını önce NV21'e çeviriyoruz çünkü Android'in
        // YuvImage sınıfı yalnızca NV21 ve YUY2 formatlarını doğrudan JPEG'e sıkıştırabiliyor.
        val nv21 = yuv420888ToNv21(image) ?: return null
        val yuvImage = YuvImage(nv21, ImageFormat.NV21, image.width, image.height, null)
        val out = ByteArrayOutputStream()
        // JPEG kalite parametresi ile akış band genişliği arasında denge kuruyoruz.
        yuvImage.compressToJpeg(Rect(0, 0, image.width, image.height), quality, out)
        return out.toByteArray()
    }

    private fun yuv420888ToNv21(image: ImageProxy): ByteArray? {
        val width = image.width
        val height = image.height
        val ySize = width * height
        val uvSize = width * height / 2
        val nv21 = ByteArray(ySize + uvSize)

        val yPlane = image.planes[0]
        val uPlane = image.planes[1]
        val vPlane = image.planes[2]

        // Y düzlemi (luma) NV21 tamponunun başına doğrudan kopyalanabilir.
        copyPlane(yPlane.buffer, yPlane.rowStride, width, height, nv21, 0)

        val uvHeight = height / 2
        val uBuffer = uPlane.buffer.duplicate().apply { position(0) }
        val vBuffer = vPlane.buffer.duplicate().apply { position(0) }
        val uRowStride = uPlane.rowStride
        val vRowStride = vPlane.rowStride
        val uPixelStride = uPlane.pixelStride
        val vPixelStride = vPlane.pixelStride

        var outputOffset = ySize
        for (row in 0 until uvHeight) {
            val uRowStart = row * uRowStride
            val vRowStart = row * vRowStride
            for (col in 0 until width / 2) {
                // NV21 formatında V ve U bileşenleri birbirini takip eder (VU VU ...).
                // Pixel stride değerleri, düzlemlerin interleave edilme şeklini belirlediği için
                // her bir örneği doğru konumdan okumak kritik önem taşır.
                val uIndex = uRowStart + col * uPixelStride
                val vIndex = vRowStart + col * vPixelStride
                nv21[outputOffset++] = getByteAt(vBuffer, vIndex)
                nv21[outputOffset++] = getByteAt(uBuffer, uIndex)
            }
        }
        return nv21
    }

    private fun copyPlane(
        buffer: ByteBuffer,
        rowStride: Int,
        width: Int,
        height: Int,
        out: ByteArray,
        offset: Int
    ) {
        var outputOffset = offset
        val bytesPerPixel = 1
        val planeBuffer = buffer.duplicate().apply { position(0) }
        for (row in 0 until height) {
            planeBuffer.position(row * rowStride)
            // rowStride değeri width * bytesPerPixel'den büyük olabilir, bu yüzden her satırın
            // gerçek başlangıcına seek edip sadece görüntü genişliği kadar veri çekiyoruz.
            planeBuffer.get(out, outputOffset, width * bytesPerPixel)
            outputOffset += width * bytesPerPixel
        }
    }

    private fun getByteAt(buffer: ByteBuffer, index: Int): Byte {
        return if (buffer.hasArray()) {
            buffer.array()[buffer.arrayOffset() + index]
        } else {
            buffer.duplicate().apply { position(index) }.get()
        }
    }
}
