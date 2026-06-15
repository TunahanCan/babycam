package com.example.babycam

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.SocketTimeoutException
import java.nio.charset.StandardCharsets

class BabyCamDiscovery(private val scope: CoroutineScope) {
    private var broadcasterJob: Job? = null
    private var listenerJob: Job? = null

    fun startBroadcasting(addressProvider: () -> String?) {
        stopBroadcasting()
        broadcasterJob = scope.launch(Dispatchers.IO) {
            DatagramSocket().use { socket ->
                socket.broadcast = true
                while (isActive) {
                    val address = addressProvider()
                    if (!address.isNullOrBlank()) {
                        val payload = BabyCamProtocol.discoveryPayload(address).toByteArray(StandardCharsets.UTF_8)
                        val packet = DatagramPacket(
                            payload,
                            payload.size,
                            InetAddress.getByName("255.255.255.255"),
                            BabyCamProtocol.DISCOVERY_PORT
                        )
                        socket.send(packet)
                    }
                    delay(2_000L)
                }
            }
        }
    }

    fun startListening(onServerFound: (String) -> Unit) {
        stopListening()
        listenerJob = scope.launch(Dispatchers.IO) {
            DatagramSocket(BabyCamProtocol.DISCOVERY_PORT).use { socket ->
                socket.broadcast = true
                socket.soTimeout = 1_000
                val buffer = ByteArray(1024)
                while (isActive) {
                    try {
                        val packet = DatagramPacket(buffer, buffer.size)
                        socket.receive(packet)
                        val payload = String(packet.data, packet.offset, packet.length, StandardCharsets.UTF_8)
                        BabyCamProtocol.parseDiscoveryAddress(payload)?.let(onServerFound)
                    } catch (_: SocketTimeoutException) {
                        // Poll isActive periodically.
                    }
                }
            }
        }
    }

    fun stopBroadcasting() {
        broadcasterJob?.cancel()
        broadcasterJob = null
    }

    fun stopListening() {
        listenerJob?.cancel()
        listenerJob = null
    }

    fun stopAll() {
        stopBroadcasting()
        stopListening()
    }
}
