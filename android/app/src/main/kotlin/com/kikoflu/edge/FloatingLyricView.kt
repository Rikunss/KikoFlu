package com.kikoflu.edge

import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.util.TypedValue
import android.view.Gravity
import android.view.HapticFeedbackConstants
import android.view.MotionEvent
import android.view.ViewConfiguration
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.TextView

/**
 * Floating lyric view
 * Supports drag and long-press to close
 */
class FloatingLyricView(
    context: Context,
    private val windowManager: WindowManager,
    private val layoutParams: WindowManager.LayoutParams,
    private val onClose: () -> Unit
) : FrameLayout(context) {
    private val textView: TextView
    
    private var initialX: Int = 0
    private var initialY: Int = 0
    private var initialTouchX: Float = 0f
    private var initialTouchY: Float = 0f
    private var isDragging = false
    private var longPressTriggered = false
    private val dragThreshold = 10f
    private val longPressTimeout = ViewConfiguration.getLongPressTimeout().toLong()

    private val longPressRunnable = Runnable {
        longPressTriggered = true
        performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
        onClose()
    }

    var touchEnabled: Boolean = true

    private var currentBackgroundColor: Int = Color.parseColor("#F2000000")
    private var currentCornerRadius: Float = 16f

    init {
        updateBackground()
        clipChildren = false
        clipToPadding = false
        
        setPadding(
            dpToPx(20f).toInt(),
            dpToPx(10f).toInt(),
            dpToPx(20f).toInt(),
            dpToPx(10f).toInt()
        )
        elevation = dpToPx(12f)

        textView = TextView(context).apply {
            textSize = 16f
            setTextColor(Color.WHITE)
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.NORMAL)
            gravity = Gravity.CENTER
            maxLines = 6
            ellipsize = android.text.TextUtils.TruncateAt.END
            letterSpacing = 0.02f
        }

        addView(textView, LayoutParams(
            LayoutParams.WRAP_CONTENT,
            LayoutParams.WRAP_CONTENT
        ))
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        when (event.action) {
            MotionEvent.ACTION_DOWN -> {
                initialX = layoutParams.x
                initialY = layoutParams.y
                initialTouchX = event.rawX
                initialTouchY = event.rawY
                isDragging = false
                longPressTriggered = false
                removeCallbacks(longPressRunnable)
                postDelayed(longPressRunnable, longPressTimeout)
                return true
            }
            
            MotionEvent.ACTION_MOVE -> {
                val dx = event.rawX - initialTouchX
                val dy = event.rawY - initialTouchY
                
                if (!isDragging && (Math.abs(dx) > dragThreshold || Math.abs(dy) > dragThreshold)) {
                    removeCallbacks(longPressRunnable)
                    isDragging = true
                }
                
                if (isDragging) {
                    layoutParams.x = initialX + dx.toInt()
                    layoutParams.y = initialY + dy.toInt()
                    
                    try {
                        windowManager.updateViewLayout(this, layoutParams)
                    } catch (e: Exception) {
                    }
                }
                return true
            }
            
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                removeCallbacks(longPressRunnable)
                if (!isDragging && !longPressTriggered) {
                    performClick()
                }
                return true
            }
        }
        return super.onTouchEvent(event)
    }

    override fun performClick(): Boolean {
        super.performClick()
        return true
    }

    fun updateText(text: String) {
        textView.text = text
    }

    private fun updateBackground() {
        val drawable = GradientDrawable().apply {
            setColor(currentBackgroundColor)
            cornerRadius = dpToPx(currentCornerRadius)
        }
        background = drawable
    }

    fun updateStyle(
        fontSize: Float?,
        textColor: Int?,
        backgroundColor: Int?,
        cornerRadius: Float?,
        paddingHorizontal: Float?,
        paddingVertical: Float?
    ) {
        fontSize?.let {
            textView.textSize = it
        }
        textColor?.let {
            textView.setTextColor(it)
        }
        
        var backgroundChanged = false
        backgroundColor?.let {
            currentBackgroundColor = it
            backgroundChanged = true
        }
        cornerRadius?.let {
            currentCornerRadius = it
            backgroundChanged = true
        }
        
        if (backgroundChanged) {
            updateBackground()
        }

        if (paddingHorizontal != null || paddingVertical != null) {
            val pH = paddingHorizontal?.let { dpToPx(it).toInt() } ?: paddingLeft
            val pV = paddingVertical?.let { dpToPx(it).toInt() } ?: paddingTop
            setPadding(pH, pV, pH, pV)
        }
    }

    private fun dpToPx(dp: Float): Float {
        return TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            dp,
            resources.displayMetrics
        )
    }
}
