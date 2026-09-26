package com.miucam.app

import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class NotificationLocaleResolverTest {
    @Test
    fun `canonical locale overrides legacy preferences and preserves script`() {
        val saved = "{\"language\":\"zh\",\"script\":\"Hant\",\"country\":\"TW\"}"
        val expected = Locale.forLanguageTag("zh-Hant-TW")

        val actual = NotificationLocaleResolver.resolve(saved, "tr", "TR") { value ->
            assertEquals(saved, value)
            expected
        }

        assertEquals(expected, actual)
        assertEquals("Hant", actual?.script)
    }

    @Test
    fun `explicit system locale overrides legacy language`() {
        val actual = NotificationLocaleResolver.resolve("", "tr", "TR") {
            throw AssertionError("System locale must not be parsed")
        }

        assertNull(actual)
    }

    @Test
    fun `install without canonical preference keeps legacy locale`() {
        val actual = NotificationLocaleResolver.resolve(null, "en", "GB") {
            throw AssertionError("Missing canonical value must not be parsed")
        }

        assertEquals(Locale("en", "GB"), actual)
    }

    @Test
    fun `malformed canonical preference falls back to legacy locale`() {
        val actual = NotificationLocaleResolver.resolve("broken-json", "fr", null) {
            throw IllegalArgumentException("Invalid JSON")
        }

        assertEquals(Locale.FRENCH, actual)
    }

    @Test
    fun `missing preferences use system locale`() {
        val actual = NotificationLocaleResolver.resolve(null, null, null) {
            throw AssertionError("Missing canonical value must not be parsed")
        }

        assertNull(actual)
    }
}
