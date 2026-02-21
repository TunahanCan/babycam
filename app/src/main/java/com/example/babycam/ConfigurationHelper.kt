package com.example.babycam

import android.content.Context
import android.util.Log
import androidx.core.content.edit

object ConfigurationHelper {
    private const val TAG = "ConfigurationHelper"
    private const val GENERAL_CONFIG = "config"
    private const val TELEGRAM_CONFIG = "telegram_config"

    // Telegram credentials - will be read from BuildConfig when app is built
    // or from SharedPreferences if set by user
    fun getTelegramBotToken(context: Context = android.app.Application()): String {
        return try {
            // Try to get from BuildConfig first (available after build)
            try {
                val buildConfigToken = Class.forName("com.example.babycam.BuildConfig")
                    .getDeclaredField("TELEGRAM_BOT_TOKEN")
                    .get(null) as String
                if (buildConfigToken.isNotEmpty()) return buildConfigToken
            } catch (_: Exception) {
                // BuildConfig not available yet, continue
            }
            // Fallback to SharedPreferences
            context.getSharedPreferences(TELEGRAM_CONFIG, Context.MODE_PRIVATE)
                .getString("bot_token", "") ?: ""
        } catch (_: Exception) {
            Log.w(TAG, "Error reading bot token")
            ""
        }
    }

    fun getTelegramChatId(context: Context = android.app.Application()): String {
        return try {
            // Try to get from BuildConfig first (available after build)
            try {
                val buildConfigChatId = Class.forName("com.example.babycam.BuildConfig")
                    .getDeclaredField("TELEGRAM_CHAT_ID")
                    .get(null) as String
                if (buildConfigChatId.isNotEmpty()) return buildConfigChatId
            } catch (_: Exception) {
                // BuildConfig not available yet, continue
            }
            // Fallback to SharedPreferences
            context.getSharedPreferences(TELEGRAM_CONFIG, Context.MODE_PRIVATE)
                .getString("chat_id", "") ?: ""
        } catch (_: Exception) {
            Log.w(TAG, "Error reading chat id")
            ""
        }
    }

    @Suppress("UNUSED")
    fun setTelegramBotToken(context: Context, token: String) {
        context.getSharedPreferences(TELEGRAM_CONFIG, Context.MODE_PRIVATE).edit {
            putString("bot_token", token)
        }
    }

    @Suppress("UNUSED")
    fun setTelegramChatId(context: Context, chatId: String) {
        context.getSharedPreferences(TELEGRAM_CONFIG, Context.MODE_PRIVATE).edit {
            putString("chat_id", chatId)
        }
    }

    @Suppress("UNUSED")
    fun setMotionThreshold(context: Context, threshold: Double) {
        context.getSharedPreferences(GENERAL_CONFIG, Context.MODE_PRIVATE).edit {
            putFloat("motion_threshold", threshold.toFloat())
        }
    }

    fun getMotionThreshold(context: Context): Double {
        return context.getSharedPreferences(GENERAL_CONFIG, Context.MODE_PRIVATE)
            .getFloat("motion_threshold", 0.22f).toDouble()
    }

    @Suppress("UNUSED")
    fun setMotionWindowMs(context: Context, windowMs: Long) {
        context.getSharedPreferences(GENERAL_CONFIG, Context.MODE_PRIVATE).edit {
            putLong("motion_window_ms", windowMs)
        }
    }

    fun getMotionWindowMs(context: Context): Long {
        return context.getSharedPreferences(GENERAL_CONFIG, Context.MODE_PRIVATE)
            .getLong("motion_window_ms", 3000L)
    }

    @Suppress("UNUSED")
    fun setMotionMinDurationMs(context: Context, durationMs: Long) {
        context.getSharedPreferences(GENERAL_CONFIG, Context.MODE_PRIVATE).edit {
            putLong("motion_min_duration_ms", durationMs)
        }
    }

    fun getMotionMinDurationMs(context: Context): Long {
        return context.getSharedPreferences(GENERAL_CONFIG, Context.MODE_PRIVATE)
            .getLong("motion_min_duration_ms", 2000L)
    }

    @Suppress("UNUSED")
    fun setCryScoreThreshold(context: Context, threshold: Double) {
        context.getSharedPreferences(GENERAL_CONFIG, Context.MODE_PRIVATE).edit {
            putFloat("cry_score_threshold", threshold.toFloat())
        }
    }

    fun getCryScoreThreshold(context: Context): Double {
        return context.getSharedPreferences(GENERAL_CONFIG, Context.MODE_PRIVATE)
            .getFloat("cry_score_threshold", 0.65f).toDouble()
    }

    @Suppress("UNUSED")
    fun setCryMinDurationMs(context: Context, durationMs: Long) {
        context.getSharedPreferences(GENERAL_CONFIG, Context.MODE_PRIVATE).edit {
            putLong("cry_min_duration_ms", durationMs)
        }
    }

    fun getCryMinDurationMs(context: Context): Long {
        return context.getSharedPreferences(GENERAL_CONFIG, Context.MODE_PRIVATE)
            .getLong("cry_min_duration_ms", 1500L)
    }

    @Suppress("UNUSED")
    fun setCryWindowMs(context: Context, windowMs: Long) {
        context.getSharedPreferences(GENERAL_CONFIG, Context.MODE_PRIVATE).edit {
            putLong("cry_window_ms", windowMs)
        }
    }

    fun getCryWindowMs(context: Context): Long {
        return context.getSharedPreferences(GENERAL_CONFIG, Context.MODE_PRIVATE)
            .getLong("cry_window_ms", 5000L)
    }

    @Suppress("UNUSED")
    fun resetToDefaults(context: Context) {
        try {
            context.getSharedPreferences(GENERAL_CONFIG, Context.MODE_PRIVATE).edit {
                clear()
            }
            Log.d(TAG, "Configuration reset to defaults")
        } catch (e: Exception) {
            Log.e(TAG, "Error resetting configuration", e)
        }
    }
}

