package com.miucam.app

/**
 * Exponential retry schedule that never becomes terminal while its owner still
 * wants the resource. Delays stop growing at [maxDelayMs], preventing both
 * busy-loops and overflow during long-running foreground-service sessions.
 */
internal class ContinuousCappedBackoff(
    private val baseDelayMs: Long,
    val maxDelayMs: Long
) {
    init {
        require(baseDelayMs > 0) { "baseDelayMs must be positive" }
        require(maxDelayMs >= baseDelayMs) {
            "maxDelayMs must be greater than or equal to baseDelayMs"
        }
    }

    fun nextAttempt(previousAttempt: Long): Long {
        require(previousAttempt >= 0) { "previousAttempt must not be negative" }
        return if (previousAttempt == Long.MAX_VALUE) {
            Long.MAX_VALUE
        } else {
            previousAttempt + 1
        }
    }

    fun delayMs(attempt: Long): Long {
        require(attempt > 0) { "attempt must be positive" }
        var delay = baseDelayMs
        var remainingDoublings = attempt - 1
        while (remainingDoublings > 0 && delay < maxDelayMs) {
            delay = if (delay > maxDelayMs / 2) {
                maxDelayMs
            } else {
                minOf(delay * 2, maxDelayMs)
            }
            remainingDoublings -= 1
        }
        return delay
    }
}
