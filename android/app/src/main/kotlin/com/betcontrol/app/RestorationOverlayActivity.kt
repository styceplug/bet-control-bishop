package com.betcontrol.app

import android.app.Activity
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

class RestorationOverlayActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // ── Show on lockscreen and turn screen on ─────────────────────────────
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                        WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                        WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
            )
        }

        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        hideSystemUI()
        setContentView(buildLayout())
    }

    private fun hideSystemUI() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.insetsController?.let {
                it.hide(WindowInsets.Type.statusBars() or WindowInsets.Type.navigationBars())
                it.systemBarsBehavior =
                    WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            }
        } else {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility = (
                    View.SYSTEM_UI_FLAG_FULLSCREEN or
                            View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                            View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or
                            View.SYSTEM_UI_FLAG_LAYOUT_STABLE or
                            View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                            View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                    )
        }
    }

    private fun buildLayout(): View {
        val root = LinearLayout(this)
        root.orientation = LinearLayout.VERTICAL
        root.gravity = Gravity.CENTER
        root.setBackgroundColor(Color.parseColor("#1A1A2E"))
        root.setPadding(dp(32), dp(48), dp(32), dp(48))
        root.layoutParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.MATCH_PARENT
        )

        // ── Shield icon ───────────────────────────────────────────────────────
        val icon = TextView(this)
        icon.text = "🛡️"
        icon.textSize = 72f
        icon.gravity = Gravity.CENTER
        val iconParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        )
        iconParams.bottomMargin = dp(24)
        icon.layoutParams = iconParams

        // ── Title ─────────────────────────────────────────────────────────────
        val title = TextView(this)
        title.text = "Protection Paused"
        title.textSize = 28f
        title.setTextColor(Color.WHITE)
        title.gravity = Gravity.CENTER
        title.typeface = Typeface.DEFAULT_BOLD
        val titleParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        )
        titleParams.bottomMargin = dp(16)
        title.layoutParams = titleParams

        // ── Subtitle ──────────────────────────────────────────────────────────
        val subtitle = TextView(this)
        subtitle.text =
            "Your phone restarted and BetControl needs to resume blocking gambling apps and sites.\n\nTap the button below to restore your protection."
        subtitle.textSize = 15f
        subtitle.setTextColor(Color.parseColor("#B0B0C8"))
        subtitle.gravity = Gravity.CENTER
        subtitle.setLineSpacing(0f, 1.5f)
        val subtitleParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        )
        subtitleParams.bottomMargin = dp(48)
        subtitle.layoutParams = subtitleParams

        // ── Warning box ───────────────────────────────────────────────────────
        val warningBox = LinearLayout(this)
        warningBox.orientation = LinearLayout.HORIZONTAL
        warningBox.gravity = Gravity.CENTER_VERTICAL
        warningBox.setBackgroundColor(Color.parseColor("#2A1A1A"))
        warningBox.setPadding(dp(16), dp(14), dp(16), dp(14))
        val warningBoxParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        )
        warningBoxParams.bottomMargin = dp(48)
        warningBox.layoutParams = warningBoxParams

        val warningText = TextView(this)
        warningText.text =
            "⚠️  Gambling apps and sites are currently unblocked until you restore protection."
        warningText.textSize = 13f
        warningText.setTextColor(Color.parseColor("#FF8C42"))
        warningText.setLineSpacing(0f, 1.4f)
        warningText.layoutParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        )
        warningBox.addView(warningText)

        // ── Restore button ────────────────────────────────────────────────────
        val restoreButton = Button(this)
        restoreButton.text = "Restore Protection Now"
        restoreButton.textSize = 16f
        restoreButton.setTextColor(Color.parseColor("#1A1A2E"))
        restoreButton.setBackgroundColor(Color.parseColor("#00D4AA"))
        restoreButton.typeface = Typeface.DEFAULT_BOLD
        restoreButton.setPadding(dp(24), dp(18), dp(24), dp(18))
        restoreButton.isAllCaps = false
        val btnParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        )
        btnParams.bottomMargin = dp(16)
        restoreButton.layoutParams = btnParams
        restoreButton.setOnClickListener { launchMainApp() }

        // ── Reassurance text ──────────────────────────────────────────────────
        val reassurance = TextView(this)
        reassurance.text =
            "You don't need to do anything in the app.\nBlocking resumes automatically the moment you tap above."
        reassurance.textSize = 12f
        reassurance.setTextColor(Color.parseColor("#606080"))
        reassurance.gravity = Gravity.CENTER
        reassurance.setLineSpacing(0f, 1.4f)
        reassurance.layoutParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        )

        root.addView(icon)
        root.addView(title)
        root.addView(subtitle)
        root.addView(warningBox)
        root.addView(restoreButton)
        root.addView(reassurance)

        return root
    }

    private fun launchMainApp() {
        val intent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        intent?.let { startActivity(it) }
        finish()
    }

    // ── Back button disabled — only exit is tapping Restore ───────────────────
    @Deprecated("Required override for pre-API 33 back press handling")
    override fun onBackPressed() {
        // Intentionally do nothing
    }

    // ── Re-apply immersive mode if user swipes status/nav bar ─────────────────
    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) hideSystemUI()
    }

    // ── Close if blocking is no longer active ─────────────────────────────────
    // Check both storage sources — ProtectionStateStore (device-protected)
    // may be empty on some devices (e.g. Infinix/XOS), so also check
    // flutter.is_blocking from FlutterSharedPreferences before closing.
    override fun onResume() {
        super.onResume()
        val flutterPrefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
        val flutterBlocking = flutterPrefs.getBoolean("flutter.is_blocking", false)
        val protectedActive = ProtectionStateStore.read(this).isActive
        if (!flutterBlocking && !protectedActive) {
            finish()
        }
    }

    private fun dp(value: Int): Int =
        (value * resources.displayMetrics.density).toInt()
}