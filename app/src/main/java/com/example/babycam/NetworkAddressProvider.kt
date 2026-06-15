package com.example.babycam

import java.net.Inet4Address
import java.net.NetworkInterface
import java.util.Collections

object NetworkAddressProvider {
    fun localHttpAddress(port: Int = BabyCamProtocol.HTTP_PORT): String? {
        val interfaces = Collections.list(NetworkInterface.getNetworkInterfaces())
        val address = interfaces
            .asSequence()
            .filter { it.isUp && !it.isLoopback }
            .flatMap { Collections.list(it.inetAddresses).asSequence() }
            .filterIsInstance<Inet4Address>()
            .firstOrNull { !it.isLoopbackAddress }
            ?.hostAddress
        return address?.let { "$it:$port" }
    }
}
