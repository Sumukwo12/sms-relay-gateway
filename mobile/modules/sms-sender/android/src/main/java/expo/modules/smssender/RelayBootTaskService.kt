package expo.modules.smssender

import android.content.Intent
import com.facebook.react.HeadlessJsTaskService
import com.facebook.react.bridge.Arguments
import com.facebook.react.jstasks.HeadlessJsTaskConfig

/** Runs the "SmsRelayBoot" JS task (see index.ts) without opening the app. */
class RelayBootTaskService : HeadlessJsTaskService() {
  override fun getTaskConfig(intent: Intent?): HeadlessJsTaskConfig =
    HeadlessJsTaskConfig("SmsRelayBoot", Arguments.createMap(), 60_000, true)
}
