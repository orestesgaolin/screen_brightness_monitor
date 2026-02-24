package dev.roszkowski.screen_brightness_monitor

import android.content.ContentResolver
import android.database.ContentObserver
import android.net.Uri
import android.provider.Settings
import androidx.test.core.app.ApplicationProvider
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.ArgumentCaptor
import org.mockito.kotlin.*
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [30])
class ScreenBrightnessMonitorTest {

    private lateinit var monitor: ScreenBrightnessMonitor
    private val context get() = ApplicationProvider.getApplicationContext<android.app.Application>()
    private val contentResolver get() = context.contentResolver

    @Before
    fun setUp() {
        // Set an initial brightness value so getUriFor and getInt work out of the box.
        Settings.System.putInt(contentResolver, Settings.System.SCREEN_BRIGHTNESS, 128)
        monitor = ScreenBrightnessMonitor(context)
    }

    @After
    fun tearDown() {
        monitor.stopObserving()
    }

    // ── brightness getter ────────────────────────────────────────────────

    @Test
    fun `brightness returns system setting value`() {
        Settings.System.putInt(contentResolver, Settings.System.SCREEN_BRIGHTNESS, 128)
        assertEquals(128, monitor.brightness)
    }

    @Test
    fun `brightness returns zero when system value is zero`() {
        Settings.System.putInt(contentResolver, Settings.System.SCREEN_BRIGHTNESS, 0)
        assertEquals(0, monitor.brightness)
    }

    @Test
    fun `brightness returns 255 when system value is max`() {
        Settings.System.putInt(contentResolver, Settings.System.SCREEN_BRIGHTNESS, 255)
        assertEquals(255, monitor.brightness)
    }

    @Test
    fun `brightness reflects updated value`() {
        Settings.System.putInt(contentResolver, Settings.System.SCREEN_BRIGHTNESS, 50)
        assertEquals(50, monitor.brightness)

        Settings.System.putInt(contentResolver, Settings.System.SCREEN_BRIGHTNESS, 200)
        assertEquals(200, monitor.brightness)
    }

    // ── startObserving ───────────────────────────────────────────────────

    @Test
    fun `startObserving registers content observer`() {
        // Use a spy to verify registration
        val spyResolver = spy(contentResolver)
        val spyContext = mock<android.content.Context> {
            on { this.contentResolver } doReturn spyResolver
        }
        val spyMonitor = ScreenBrightnessMonitor(spyContext)

        spyMonitor.startObserving { }

        verify(spyResolver).registerContentObserver(
            any<Uri>(),
            eq(false),
            any<ContentObserver>()
        )
    }

    @Test
    fun `startObserving invokes callback with current brightness on change`() {
        val spyResolver = spy(contentResolver)
        val spyContext = mock<android.content.Context> {
            on { this.contentResolver } doReturn spyResolver
        }
        val spyMonitor = ScreenBrightnessMonitor(spyContext)
        val observerCaptor = ArgumentCaptor.forClass(ContentObserver::class.java)
        var receivedBrightness = -1

        Settings.System.putInt(contentResolver, Settings.System.SCREEN_BRIGHTNESS, 200)

        spyMonitor.startObserving { brightness -> receivedBrightness = brightness }

        verify(spyResolver).registerContentObserver(
            any<Uri>(),
            eq(false),
            observerCaptor.capture()
        )

        // Simulate brightness change notification
        observerCaptor.value.onChange(false)

        assertEquals(200, receivedBrightness)
    }

    @Test
    fun `startObserving replaces previous observer`() {
        val spyResolver = spy(contentResolver)
        val spyContext = mock<android.content.Context> {
            on { this.contentResolver } doReturn spyResolver
        }
        val spyMonitor = ScreenBrightnessMonitor(spyContext)

        spyMonitor.startObserving { }
        spyMonitor.startObserving { }

        // First call registers, then stopObserving unregisters, then second call registers again
        verify(spyResolver, times(1)).unregisterContentObserver(any())
        verify(spyResolver, times(2)).registerContentObserver(
            any<Uri>(),
            eq(false),
            any<ContentObserver>()
        )
    }

    @Test
    fun `startObserving replaces callback so old one is not invoked`() {
        val spyResolver = spy(contentResolver)
        val spyContext = mock<android.content.Context> {
            on { this.contentResolver } doReturn spyResolver
        }
        val spyMonitor = ScreenBrightnessMonitor(spyContext)
        val observerCaptor = ArgumentCaptor.forClass(ContentObserver::class.java)
        var oldCalled = false
        var newValue = -1

        Settings.System.putInt(contentResolver, Settings.System.SCREEN_BRIGHTNESS, 100)

        spyMonitor.startObserving { oldCalled = true }
        spyMonitor.startObserving { brightness -> newValue = brightness }

        verify(spyResolver, atLeastOnce()).registerContentObserver(
            any<Uri>(),
            eq(false),
            observerCaptor.capture()
        )

        // Trigger the latest observer
        observerCaptor.allValues.last().onChange(false)

        assertFalse(oldCalled)
        assertEquals(100, newValue)
    }

    // ── stopObserving ────────────────────────────────────────────────────

    @Test
    fun `stopObserving unregisters content observer`() {
        val spyResolver = spy(contentResolver)
        val spyContext = mock<android.content.Context> {
            on { this.contentResolver } doReturn spyResolver
        }
        val spyMonitor = ScreenBrightnessMonitor(spyContext)

        spyMonitor.startObserving { }
        spyMonitor.stopObserving()

        verify(spyResolver).unregisterContentObserver(any())
    }

    @Test
    fun `stopObserving is safe to call when not observing`() {
        val spyResolver = spy(contentResolver)
        val spyContext = mock<android.content.Context> {
            on { this.contentResolver } doReturn spyResolver
        }
        val spyMonitor = ScreenBrightnessMonitor(spyContext)

        // Should not throw
        spyMonitor.stopObserving()

        verify(spyResolver, never()).unregisterContentObserver(any())
    }

    @Test
    fun `callback is not invoked after stopObserving`() {
        val spyResolver = spy(contentResolver)
        val spyContext = mock<android.content.Context> {
            on { this.contentResolver } doReturn spyResolver
        }
        val spyMonitor = ScreenBrightnessMonitor(spyContext)
        val observerCaptor = ArgumentCaptor.forClass(ContentObserver::class.java)
        var callbackInvoked = false

        spyMonitor.startObserving { callbackInvoked = true }

        verify(spyResolver).registerContentObserver(
            any<Uri>(),
            eq(false),
            observerCaptor.capture()
        )

        val capturedObserver = observerCaptor.value
        spyMonitor.stopObserving()

        // Manually fire the observer after stop — callback should NOT fire
        capturedObserver.onChange(false)

        assertFalse(callbackInvoked)
    }

    @Test
    fun `multiple stopObserving calls do not throw`() {
        val spyResolver = spy(contentResolver)
        val spyContext = mock<android.content.Context> {
            on { this.contentResolver } doReturn spyResolver
        }
        val spyMonitor = ScreenBrightnessMonitor(spyContext)

        spyMonitor.startObserving { }
        spyMonitor.stopObserving()
        spyMonitor.stopObserving()

        verify(spyResolver, times(1)).unregisterContentObserver(any())
    }
}
