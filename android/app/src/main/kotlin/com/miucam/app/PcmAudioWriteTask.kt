package com.miucam.app

import java.util.concurrent.atomic.AtomicInteger

/** Completes a platform write even when executor shutdown removes it from the queue. */
internal class PcmAudioWriteTask(
    private val write: () -> Boolean,
    private val completion: (Boolean) -> Unit
) : Runnable {
    private val state = AtomicInteger(QUEUED)

    override fun run() {
        if (!state.compareAndSet(QUEUED, RUNNING)) return
        var accepted = false
        try {
            accepted = write()
        } finally {
            state.set(COMPLETED)
            completion(accepted)
        }
    }

    fun cancelBeforeRun(): Boolean {
        if (!state.compareAndSet(QUEUED, COMPLETED)) return false
        completion(false)
        return true
    }

    private companion object {
        const val QUEUED = 0
        const val RUNNING = 1
        const val COMPLETED = 2
    }
}
