package com.meteor.kikoeruflutter

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

/**
 * Home screen widget provider for KikoFlu Edge.
 * Displays current track info and playback controls.
 * State is communicated from Dart via home_widget plugin (shared preferences).
 */
class KikoFluWidgetProvider : AppWidgetProvider() {

    companion object {
        const val ACTION_PLAY_PAUSE = "com.meteor.kikoeruflutter.action.PLAY_PAUSE"
        const val ACTION_NEXT = "com.meteor.kikoeruflutter.action.NEXT"
        const val ACTION_PREV = "com.meteor.kikoeruflutter.action.PREV"
        const val ACTION_OPEN_APP = "com.meteor.kikoeruflutter.action.OPEN_APP"

        const val KEY_TITLE = "widget_track_title"
        const val KEY_ARTIST = "widget_track_artist"
        const val KEY_IS_PLAYING = "widget_is_playing"
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    override fun onEnabled(context: Context) {
        super.onEnabled(context)
    }

    override fun onDisabled(context: Context) {
        super.onDisabled(context)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)

        when (intent.action) {
            ACTION_PLAY_PAUSE -> {
                val openAppIntent = getOpenAppIntent(context)
                openAppIntent.action = "com.meteor.kikoeruflutter.TOGGLE_PLAYBACK"
                openAppIntent.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                context.startActivity(openAppIntent)
            }
            ACTION_NEXT -> {
                val openAppIntent = getOpenAppIntent(context)
                openAppIntent.action = "com.meteor.kikoeruflutter.SKIP_NEXT"
                openAppIntent.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                context.startActivity(openAppIntent)
            }
            ACTION_PREV -> {
                val openAppIntent = getOpenAppIntent(context)
                openAppIntent.action = "com.meteor.kikoeruflutter.SKIP_PREV"
                openAppIntent.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                context.startActivity(openAppIntent)
            }
            ACTION_OPEN_APP -> {
                val openAppIntent = getOpenAppIntent(context)
                openAppIntent.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                context.startActivity(openAppIntent)
            }
        }
    }

    private fun getOpenAppIntent(context: Context): Intent {
        return Intent(context, MainActivity::class.java)
    }

    private fun updateAppWidget(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int
    ) {
        val views = RemoteViews(context.packageName, R.layout.widget_layout)

        // Read widget state from home_widget shared prefs
        val prefs = context.getSharedPreferences(
            "home_widget_prefs",
            Context.MODE_PRIVATE
        )
        val title = prefs.getString(KEY_TITLE, "No track") ?: "No track"
        val artist = prefs.getString(KEY_ARTIST, "") ?: ""
        val isPlaying = prefs.getBoolean(KEY_IS_PLAYING, false)

        views.setTextViewText(R.id.widget_track_title, title)
        views.setTextViewText(R.id.widget_track_artist, artist)

        // Set play/pause icon
        if (isPlaying) {
            views.setImageViewResource(R.id.widget_play_pause, android.R.drawable.ic_media_pause)
        } else {
            views.setImageViewResource(R.id.widget_play_pause, android.R.drawable.ic_media_play)
        }

        // Set up PendingIntents for control buttons
        val playPauseIntent = Intent(context, KikoFluWidgetProvider::class.java).apply {
            action = ACTION_PLAY_PAUSE
        }
        views.setOnClickPendingIntent(
            R.id.widget_play_pause,
            PendingIntent.getBroadcast(
                context,
                0,
                playPauseIntent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
        )

        val nextIntent = Intent(context, KikoFluWidgetProvider::class.java).apply {
            action = ACTION_NEXT
        }
        views.setOnClickPendingIntent(
            R.id.widget_next,
            PendingIntent.getBroadcast(
                context,
                1,
                nextIntent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
        )

        val prevIntent = Intent(context, KikoFluWidgetProvider::class.java).apply {
            action = ACTION_PREV
        }
        views.setOnClickPendingIntent(
            R.id.widget_prev,
            PendingIntent.getBroadcast(
                context,
                2,
                prevIntent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
        )

        // Open app on background tap
        val openIntent = Intent(context, KikoFluWidgetProvider::class.java).apply {
            action = ACTION_OPEN_APP
        }
        views.setOnClickPendingIntent(
            android.R.id.background,
            PendingIntent.getBroadcast(
                context,
                3,
                openIntent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
        )

        appWidgetManager.updateAppWidget(appWidgetId, views)
    }
}
