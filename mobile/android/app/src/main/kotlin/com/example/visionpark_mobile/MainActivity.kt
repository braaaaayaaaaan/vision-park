package com.example.visionpark_mobile

import android.content.ActivityNotFoundException
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var allocationSound: AllocationSound? = null
    private var channel: MethodChannel? = null
    private var linkReady = false
    private var pendingLink: String? = null

    private fun emailIntent(): Intent =
        Intent.makeMainSelectorActivity(Intent.ACTION_MAIN, Intent.CATEGORY_APP_EMAIL)

    private fun canOpenEmail(): Boolean {
        val intent = emailIntent()
        return (intent.selector ?: intent).resolveActivity(packageManager) != null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        allocationSound?.dispose()
        allocationSound = AllocationSound(this, flutterEngine.dartExecutor.binaryMessenger)
        pendingLink = intent?.dataString
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "visionpark/email_verification")
        channel?.setMethodCallHandler { call, result ->
            val prefs = getSharedPreferences("visionpark_registration", MODE_PRIVATE)
            when (call.method) {
                "initialLink" -> {
                    linkReady = true
                    result.success(pendingLink)
                    pendingLink = null
                    intent?.data = null
                }
                "readPendingEmail" -> {
                    val age = System.currentTimeMillis() - prefs.getLong("saved_at", 0L)
                    result.success(if (age in 0L..604800000L) prefs.getString("email", null) else null)
                }
                "savePendingEmail" -> {
                    val email = call.arguments as? String
                    val edit = prefs.edit().clear()
                    if (email != null && email.length <= 254) {
                        edit.putString("email", email).putLong("saved_at", System.currentTimeMillis())
                    }
                    if (edit.commit()) result.success(null)
                    else result.error("storage_unavailable", "Unable to save registration reminder.", null)
                }
                "canOpenEmail" -> result.success(canOpenEmail())
                "openEmail" -> {
                    try {
                        if (canOpenEmail()) {
                            startActivity(emailIntent().addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                            result.success(true)
                        } else result.success(false)
                    } catch (_: ActivityNotFoundException) { result.success(false) }
                    catch (_: SecurityException) { result.success(false) }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onPause() {
        allocationSound?.stop()
        super.onPause()
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        allocationSound?.dispose()
        allocationSound = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        pendingLink = intent.dataString
        if (linkReady && pendingLink != null) {
            channel?.invokeMethod("verificationLink", pendingLink)
            pendingLink = null
            intent.data = null
        }
    }
}
