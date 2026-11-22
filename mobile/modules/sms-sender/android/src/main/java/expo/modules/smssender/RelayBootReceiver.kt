package expo.modules.smssender

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.facebook.react.HeadlessJsTaskService

/**
 * Restarts the relay after the phone reboots (or the app is updated) when it
 * was running before, so the gateway doesn't stay offline until someone
 * opens the app. The JS side records the choice through setAutoStart.
 */
class RelayBootReceiver : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent) {
    if (intent.action != Intent.ACTION_BOOT_COMPLETED &&
        intent.action != Intent.ACTION_MY_PACKAGE_REPLACED) {
      return
    }
    if (!isAutoStartEnabled(context)) return

    // Runs the "SmsRelayBoot" headless task registered in index.ts, which
    // starts the foreground service. Boot broadcasts may start services.
    context.startService(Intent(context, RelayBootTaskService::class.java))
    HeadlessJsTaskService.acquireWakeLockNow(context)
  }

  companion object {
    private const val PREFS = "sms_relay"
    private const val KEY_AUTO_START = "auto_start"

    fun setAutoStart(context: Context, enabled: Boolean) {
      context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        .edit()
        .putBoolean(KEY_AUTO_START, enabled)
        .apply()
    }

    fun isAutoStartEnabled(context: Context): Boolean =
      context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(KEY_AUTO_START, false)
  }
}
