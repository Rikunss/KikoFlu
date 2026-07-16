package com.meteor.kikoeruflutter

import android.content.Intent
import android.content.SharedPreferences
import android.graphics.drawable.Icon
import android.preference.PreferenceManager
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import androidx.annotation.RequiresApi

/**
 * Quick Settings tile for toggling App Lock on/off.
 *
 * Reads the app lock state from SharedPreferences (same backing store as
 * Flutter's `shared_preferences` plugin) and toggles it on tap.
 * Sends a local broadcast so [MainActivity] can notify the Flutter side
 * to update its UI state accordingly.
 */
@RequiresApi(24)
class AppLockTileService : TileService() {

    companion object {
        const val ACTION_TOGGLE = "com.meteor.kikoeruflutter.APP_LOCK_TOGGLE"
        const val EXTRA_ENABLED = "enabled"

        private const val KEY_ENABLED = "app_lock_enabled"
        private const val KEY_BIOMETRIC = "app_lock_biometric"
        private const val KEY_PIN_HASH = "app_lock_pin_hash"
    }

    private var prefs: SharedPreferences? = null

    override fun onCreate() {
        super.onCreate()
        prefs = PreferenceManager.getDefaultSharedPreferences(this)
    }

    override fun onStartListening() {
        updateTile()
    }

    override fun onClick() {
        val sp = prefs ?: return

        val currentlyEnabled = sp.getBoolean(KEY_ENABLED, false)
        val newState = !currentlyEnabled

        if (newState) {
            val hasPin = sp.contains(KEY_PIN_HASH)
            if (!hasPin) {
                updateTile()
                return
            }
        }

        sp.edit().putBoolean(KEY_ENABLED, newState).apply()
        if (!newState) {
            sp.edit().putBoolean(KEY_BIOMETRIC, false).apply()
        }

        updateTile()

        sendBroadcast(Intent(ACTION_TOGGLE).apply {
            putExtra(EXTRA_ENABLED, newState)
        })

        unlockAndRun {
        }
    }

    private fun updateTile() {
        val sp = prefs ?: return
        val enabled = sp.getBoolean(KEY_ENABLED, false)
        val hasPin = sp.contains(KEY_PIN_HASH)
        val tile = qsTile ?: return

        tile.state = if (enabled) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.label = "App Lock"
        tile.contentDescription = if (enabled) "App Lock is on" else "App Lock is off"

        if (!hasPin) {
            tile.subtitle = "Not set up"
            tile.state = Tile.STATE_UNAVAILABLE
        } else if (enabled) {
            tile.subtitle = "On"
        } else {
            tile.subtitle = "Off"
        }

        tile.icon = Icon.createWithResource(this, R.drawable.ic_lock)
        tile.updateTile()
    }
}
