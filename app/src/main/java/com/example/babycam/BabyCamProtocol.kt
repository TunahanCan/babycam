package com.example.babycam

object BabyCamProtocol {
    const val HTTP_PORT = 8080
    const val DISCOVERY_PORT = 45678
    const val DISCOVERY_SERVICE = "babycam.v1"

    const val PACKET_METADATA: Byte = 0
    const val PACKET_AUDIO_PCM16LE: Byte = 1
    const val PACKET_VIDEO_MJPEG: Byte = 2
    const val PACKET_ALERT_TEXT: Byte = 3

    fun discoveryPayload(address: String): String =
        "{\"service\":\"$DISCOVERY_SERVICE\",\"version\":1,\"address\":\"$address\",\"video\":\"mjpeg\",\"audio\":\"pcm16le\"}"

    fun parseDiscoveryAddress(payload: String): String? {
        if (!payload.contains("\"service\":\"$DISCOVERY_SERVICE\"")) return null
        val marker = "\"address\":\""
        val start = payload.indexOf(marker)
        if (start < 0) return null
        val valueStart = start + marker.length
        val valueEnd = payload.indexOf('"', valueStart)
        return payload.substring(valueStart, valueEnd).takeIf { valueEnd > valueStart }
    }
}
