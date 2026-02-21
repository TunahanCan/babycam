package com.example.babycam

/**
 * Ortam ses seviyesini zamanla takip ederek adaptif eşik hesaplamalarını ayrıştırır.
 */
class AudioAmbientTracker(
    private var ambientDb: Double = -55.0,
    private var ambientBandBalance: Double = -12.0
) {

    fun update(rmsDb: Double, bandBalanceDb: Double) {
        ambientDb = if (rmsDb < ambientDb) {
            ambientDb * 0.9 + rmsDb * 0.1
        } else {
            ambientDb * 0.995 + rmsDb * 0.005
        }

        ambientBandBalance = if (bandBalanceDb < ambientBandBalance) {
            ambientBandBalance * 0.85 + bandBalanceDb * 0.15
        } else {
            ambientBandBalance * 0.99 + bandBalanceDb * 0.01
        }
    }

    fun ambientDb(): Double = ambientDb
    fun ambientBandBalance(): Double = ambientBandBalance
}
