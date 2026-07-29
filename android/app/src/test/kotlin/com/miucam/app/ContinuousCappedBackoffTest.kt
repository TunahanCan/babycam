package com.miucam.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class ContinuousCappedBackoffTest {
    private val backoff = ContinuousCappedBackoff(
        baseDelayMs = 250L,
        maxDelayMs = 30_000L
    )

    @Test
    fun `delay grows exponentially and caps without a terminal attempt`() {
        val expected = listOf(
            250L,
            500L,
            1_000L,
            2_000L,
            4_000L,
            8_000L,
            16_000L,
            30_000L,
            30_000L,
            30_000L
        )

        assertEquals(
            expected,
            (1L..expected.size.toLong()).map(backoff::delayMs)
        )
        assertEquals(30_000L, backoff.delayMs(1_000_000L))
        assertEquals(30_000L, backoff.delayMs(Long.MAX_VALUE))
    }

    @Test
    fun `attempt counter saturates instead of overflowing`() {
        assertEquals(1L, backoff.nextAttempt(0L))
        assertEquals(42L, backoff.nextAttempt(41L))
        assertEquals(Long.MAX_VALUE, backoff.nextAttempt(Long.MAX_VALUE))
    }

    @Test
    fun `invalid policy and attempt values are rejected`() {
        assertThrows(IllegalArgumentException::class.java) {
            ContinuousCappedBackoff(baseDelayMs = 0L, maxDelayMs = 1L)
        }
        assertThrows(IllegalArgumentException::class.java) {
            ContinuousCappedBackoff(baseDelayMs = 2L, maxDelayMs = 1L)
        }
        assertThrows(IllegalArgumentException::class.java) {
            backoff.nextAttempt(-1L)
        }
        assertThrows(IllegalArgumentException::class.java) {
            backoff.delayMs(0L)
        }
    }
}
