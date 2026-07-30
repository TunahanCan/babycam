package com.miucam.app

import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PcmAudioOperationOwnerTest {
    @Test
    fun `late stop cannot clear a newer playback lease`() {
        val owner = PcmAudioOperationOwner()

        assertTrue(owner.claimStart(leaseId = 1L, operationId = 100L))
        assertTrue(owner.claimStart(leaseId = 2L, operationId = 102L))

        assertNull(
            owner.claimStop(
                leaseId = 1L,
                operationId = 101L,
                reset = false
            )
        )
        assertTrue(owner.owns(2L))

        assertFalse(
            owner.claimStop(
                leaseId = 1L,
                operationId = 103L,
                reset = false
            )!!
        )
        assertTrue(owner.owns(2L))
        assertTrue(owner.claimWrite(leaseId = 2L, operationId = 104L))
    }

    @Test
    fun `late failed start cleanup cannot release successor`() {
        val owner = PcmAudioOperationOwner()

        assertTrue(owner.claimStart(leaseId = 1L, operationId = 200L))
        assertTrue(owner.claimStart(leaseId = 2L, operationId = 201L))

        owner.releaseFailedStart(leaseId = 1L, operationId = 200L)

        assertTrue(owner.owns(2L))
    }

    @Test
    fun `process scoped owner survives activity handler recreation`() {
        val processOwner = PcmAudioOperationOwner()
        val firstActivityHandler = processOwner

        assertTrue(
            firstActivityHandler.claimStart(
                leaseId = 7L,
                operationId = 300L
            )
        )

        val recreatedActivityHandler = processOwner
        assertTrue(recreatedActivityHandler.owns(7L))
        assertTrue(
            recreatedActivityHandler.claimWrite(
                leaseId = 7L,
                operationId = 301L
            )
        )
    }

    @Test
    fun `reset invalidates current owner and rejects its future writes`() {
        val owner = PcmAudioOperationOwner()

        assertTrue(owner.claimStart(leaseId = 9L, operationId = 400L))
        assertTrue(
            owner.claimStop(
                leaseId = null,
                operationId = 401L,
                reset = true
            )!!
        )

        assertFalse(owner.owns(9L))
        assertFalse(owner.claimWrite(leaseId = 9L, operationId = 402L))
        assertTrue(owner.acceptsLegacyWrite())
    }
}
