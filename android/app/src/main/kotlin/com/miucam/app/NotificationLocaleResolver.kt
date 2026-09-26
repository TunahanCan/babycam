package com.miucam.app

import java.util.Locale

/** Matches the canonical/legacy preference precedence used by the Dart UI. */
internal object NotificationLocaleResolver {
    fun resolve(
        canonical: String?,
        legacyLanguage: String?,
        legacyCountry: String?,
        parseCanonical: (String) -> Locale
    ): Locale? {
        // Empty is an explicit system-locale selection, even on an install
        // that still has the old separate language/country preferences.
        if (canonical == "") return null
        if (canonical != null) {
            try {
                return parseCanonical(canonical)
            } catch (_: Exception) {
                // Mirror the Dart reader's legacy fallback for invalid JSON.
            }
        }
        if (legacyLanguage.isNullOrBlank()) return null
        return if (legacyCountry.isNullOrBlank()) {
            Locale(legacyLanguage)
        } else {
            Locale(legacyLanguage, legacyCountry)
        }
    }
}
