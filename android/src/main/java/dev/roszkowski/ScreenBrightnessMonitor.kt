package dev.roszkowski.screen_brightness_monitor

import android.content.ContentResolver
import android.content.Context
import android.database.ContentObserver
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.Settings

import androidx.annotation.Keep/**
 * Monitors screen brightness and notifies registered callbacks of changes.
 *
 * @param context Android context used to access system settings.
 */
@Keep
class ScreenBrightnessMonitor(private val context: Context) {

    private val contentResolver: ContentResolver = context.contentResolver
    private val brightnessUri: Uri = Settings.System.getUriFor(Settings.System.SCREEN_BRIGHTNESS)
    private var contentObserver: ContentObserver? = null
    private var onBrightnessChanged: BrightnessCallback? = null

    /**
     * Returns the current screen brightness value (0–255).
     *
     * If the brightness cannot be read (e.g. missing permission), returns -1.
     */
    @get:Keep
    val brightness: Int
        get() = try {
            Settings.System.getInt(contentResolver, Settings.System.SCREEN_BRIGHTNESS)
        } catch (e: Settings.SettingNotFoundException) {
            -1
        }

    /**
     * Starts observing screen brightness changes.
     *
     * The [callback] will be invoked on the main thread whenever the system
     * brightness setting changes, receiving the new brightness value (0–255).
     *
     * Only one callback can be active at a time. Calling this method again
     * replaces the previous callback (and re-registers the observer).
     */
    @Keep
    fun startObserving(callback: BrightnessCallback) {
        // Stop any existing observer first.
        stopObserving()

        onBrightnessChanged = callback

        contentObserver = object : ContentObserver(Handler(Looper.getMainLooper())) {
            override fun onChange(selfChange: Boolean) {
                super.onChange(selfChange)
                onBrightnessChanged?.onBrightnessChanged(brightness)
            }
        }

        contentResolver.registerContentObserver(brightnessUri, false, contentObserver!!)
    }

    /**
     * Stops observing screen brightness changes and removes the callback.
     */
    @Keep
    fun stopObserving() {
        contentObserver?.let {
            contentResolver.unregisterContentObserver(it)
        }
        contentObserver = null
        onBrightnessChanged = null
    }
}

