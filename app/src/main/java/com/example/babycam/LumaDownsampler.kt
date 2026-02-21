package com.example.babycam

import java.nio.ByteBuffer

/**
 * YUV luma kanalını stride farkındalığı ile aşağı örnekleyen yardımcı sınıf.
 */
class LumaDownsampler(private val sampleStep: Int) {

    private var reusableSampleBuffer: DoubleArray? = null

    fun downsample(
        yBuffer: ByteBuffer,
        width: Int,
        height: Int,
        rowStride: Int
    ): DoubleArray {
        val sampledRows = (height + sampleStep - 1) / sampleStep
        val sampledColumns = (width + sampleStep - 1) / sampleStep
        val requiredSize = sampledRows * sampledColumns

        yBuffer.rewind()

        val buffer = reusableSampleBuffer
        val output = if (buffer != null && buffer.size >= requiredSize) {
            buffer
        } else {
            DoubleArray(requiredSize).also { reusableSampleBuffer = it }
        }

        var index = 0
        var row = 0
        while (row < height) {
            var col = 0
            val rowStart = row * rowStride
            while (col < width) {
                val value = yBuffer.get(rowStart + col).toInt() and 0xFF
                output[index++] = value.toDouble()
                col += sampleStep
            }
            row += sampleStep
        }

        return if (index == output.size) {
            output
        } else {
            output.copyOf(index)
        }
    }
}
