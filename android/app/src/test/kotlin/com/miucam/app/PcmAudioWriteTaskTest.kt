package com.miucam.app

import java.util.Collections
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PcmAudioWriteTaskTest {
    @Test
    fun `stopping a blocked playback executor completes every queued write`() {
        val executor = Executors.newSingleThreadExecutor()
        val running = CountDownLatch(1)
        val keepBlocked = CountDownLatch(1)
        val completions = Collections.synchronizedList(mutableListOf<Boolean>())
        val queuedWritesExecuted = AtomicInteger(0)
        try {
            executor.execute(PcmAudioWriteTask(
                write = {
                    running.countDown()
                    try {
                        keepBlocked.await()
                        true
                    } catch (_: InterruptedException) {
                        false
                    }
                },
                completion = { completions.add(it) }
            ))
            assertTrue(running.await(5, TimeUnit.SECONDS))
            repeat(5) {
                executor.execute(PcmAudioWriteTask(
                    write = { queuedWritesExecuted.incrementAndGet(); true },
                    completion = { completions.add(it) }
                ))
            }

            val discarded = executor.shutdownNow()
            assertEquals(5, discarded.size)
            discarded.forEach { assertTrue((it as PcmAudioWriteTask).cancelBeforeRun()) }

            assertTrue(executor.awaitTermination(5, TimeUnit.SECONDS))
            assertEquals(0, queuedWritesExecuted.get())
            assertEquals(List(6) { false }, completions)
        } finally {
            keepBlocked.countDown()
            executor.shutdownNow()
        }
    }

    @Test
    fun `cancelled write never executes and completes only once`() {
        val completions = mutableListOf<Boolean>()
        var writes = 0
        val task = PcmAudioWriteTask(
            write = { writes += 1; true },
            completion = { completions.add(it) }
        )

        assertTrue(task.cancelBeforeRun())
        assertFalse(task.cancelBeforeRun())
        task.run()

        assertEquals(0, writes)
        assertEquals(listOf(false), completions)
    }

    @Test
    fun `completed write cannot be cancelled or executed again`() {
        val completions = mutableListOf<Boolean>()
        var writes = 0
        val task = PcmAudioWriteTask(
            write = { writes += 1; true },
            completion = { completions.add(it) }
        )

        task.run()
        assertFalse(task.cancelBeforeRun())
        task.run()

        assertEquals(1, writes)
        assertEquals(listOf(true), completions)
    }

    @Test
    fun `running write owns its completion until the write finishes`() {
        val completions = mutableListOf<Boolean>()
        lateinit var task: PcmAudioWriteTask
        task = PcmAudioWriteTask(
            write = {
                assertFalse(task.cancelBeforeRun())
                assertTrue(completions.isEmpty())
                true
            },
            completion = { completions.add(it) }
        )

        task.run()

        assertEquals(listOf(true), completions)
    }

    @Test
    fun `unexpected worker failure still completes the channel write`() {
        val completions = mutableListOf<Boolean>()
        val failure = IllegalStateException("track failed")
        val task = PcmAudioWriteTask(
            write = { throw failure },
            completion = { completions.add(it) }
        )

        try {
            task.run()
            throw AssertionError("Expected worker failure")
        } catch (error: IllegalStateException) {
            assertTrue(error === failure)
        }

        assertEquals(listOf(false), completions)
        assertFalse(task.cancelBeforeRun())
    }
}
