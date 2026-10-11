package expo.modules.smssender

import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.telephony.SmsManager
import android.telephony.SubscriptionManager
import android.telephony.TelephonyManager
import androidx.core.content.ContextCompat
import expo.modules.kotlin.Promise
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference

class SmsSenderModule : Module() {
  private val mainHandler = Handler(Looper.getMainLooper())

  override fun definition() = ModuleDefinition {
    Name("SmsSender")

    Events("onDelivered")

    AsyncFunction("getDeviceInfo") {
      val context = appContext.reactContext ?: return@AsyncFunction emptyMap<String, Any?>()

      val batteryIntent = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
      val level = batteryIntent?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
      val scale = batteryIntent?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
      val batteryPct = if (level >= 0 && scale > 0) (level * 100 / scale) else null

      val status = batteryIntent?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
      val isCharging = status == BatteryManager.BATTERY_STATUS_CHARGING || status == BatteryManager.BATTERY_STATUS_FULL

      val telephonyManager = context.getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
      val signalLevel = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
        telephonyManager?.signalStrength?.level
      } else {
        null
      }

      mapOf(
        "battery" to batteryPct,
        "isCharging" to isCharging,
        "signal" to signalLevel
      )
    }

    AsyncFunction("getSimCards") {
      val context = appContext.reactContext ?: return@AsyncFunction emptyList<Map<String, Any?>>()
      if (ContextCompat.checkSelfPermission(context, android.Manifest.permission.READ_PHONE_STATE)
          != PackageManager.PERMISSION_GRANTED) {
        return@AsyncFunction emptyList<Map<String, Any?>>()
      }

      val subscriptionManager = context.getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as? SubscriptionManager
      val activeSubscriptions = subscriptionManager?.activeSubscriptionInfoList ?: emptyList()

      activeSubscriptions.map { subInfo ->
        val phoneNumber: String? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
          try {
            subscriptionManager?.getPhoneNumber(subInfo.subscriptionId)
          } catch (_: Exception) {
            subInfo.number
          }
        } else {
          @Suppress("DEPRECATION")
          subInfo.number
        }

        mapOf(
          "subscriptionId" to subInfo.subscriptionId,
          "displayName" to (subInfo.displayName?.toString() ?: "SIM ${subInfo.simSlotIndex + 1}"),
          "carrierName" to (subInfo.carrierName?.toString() ?: ""),
          "slotIndex" to subInfo.simSlotIndex,
          "number" to (phoneNumber ?: "")
        )
      }
    }

    AsyncFunction("sendSms") { to: String, body: String, subId: Int?, id: String?, promise: Promise ->
      val context = appContext.reactContext
      if (context == null) {
        promise.resolve(mapOf("status" to "failed", "error" to "Application context unavailable"))
        return@AsyncFunction
      }

      if (ContextCompat.checkSelfPermission(context, android.Manifest.permission.SEND_SMS)
          != PackageManager.PERMISSION_GRANTED) {
        promise.resolve(mapOf("status" to "failed", "error" to "SEND_SMS permission not granted"))
        return@AsyncFunction
      }

      try {
        val smsManager = getSmsManager(context, subId)
        val parts = smsManager.divideMessage(body)
        val numParts = parts.size

        if (numParts == 0) {
          promise.resolve(mapOf("status" to "failed", "error" to "Empty message content"))
          return@AsyncFunction
        }

        val actionSent = "expo.modules.smssender.SMS_SENT_${UUID.randomUUID()}"
        val actionDelivered = "expo.modules.smssender.SMS_DELIVERED_${UUID.randomUUID()}"

        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
          PendingIntent.FLAG_ONE_SHOT or PendingIntent.FLAG_IMMUTABLE
        } else {
          PendingIntent.FLAG_ONE_SHOT
        }

        val sentIntents = ArrayList<PendingIntent>(numParts)
        val deliveredIntents = ArrayList<PendingIntent>(numParts)
        val baseCode = UUID.randomUUID().hashCode()

        for (i in 0 until numParts) {
          val sentIntent = Intent(actionSent).apply {
            setPackage(context.packageName)
            putExtra("part_index", i)
            putExtra("total_parts", numParts)
          }
          sentIntents.add(PendingIntent.getBroadcast(context, baseCode + i, sentIntent, flags))

          val deliveredIntent = Intent(actionDelivered).apply {
            setPackage(context.packageName)
            putExtra("part_index", i)
            putExtra("id", id ?: "")
          }
          deliveredIntents.add(PendingIntent.getBroadcast(context, baseCode + numParts + i, deliveredIntent, flags))
        }

        val partsReported = AtomicInteger(0)
        val firstFailureError = AtomicReference<String?>(null)
        val hasResolved = AtomicBoolean(false)
        val deliveredPartsReported = AtomicInteger(0)

        lateinit var sentReceiver: BroadcastReceiver
        lateinit var deliveredReceiver: BroadcastReceiver

        // Safety timeout to resolve if broadcast is dropped by OS
        val timeoutRunnable = Runnable {
          if (hasResolved.compareAndSet(false, true)) {
            try {
              context.unregisterReceiver(sentReceiver)
            } catch (_: Exception) {}
            promise.resolve(mapOf("status" to "failed", "error" to "SMS delivery confirmation timed out"))
          }
        }

        sentReceiver = object : BroadcastReceiver() {
          override fun onReceive(recvContext: Context?, intent: Intent?) {
            val code = resultCode
            if (code != Activity.RESULT_OK) {
              val errorMsg = mapResultCodeToError(code)
              firstFailureError.compareAndSet(null, errorMsg)
            }

            if (partsReported.incrementAndGet() >= numParts) {
              if (hasResolved.compareAndSet(false, true)) {
                mainHandler.removeCallbacks(timeoutRunnable)
                try {
                  context.unregisterReceiver(sentReceiver)
                } catch (_: Exception) {}

                val failure = firstFailureError.get()
                if (failure != null) {
                  promise.resolve(mapOf("status" to "failed", "error" to failure))
                } else {
                  promise.resolve(mapOf("status" to "sent"))
                }
              }
            }
          }
        }

        deliveredReceiver = object : BroadcastReceiver() {
          override fun onReceive(recvContext: Context?, intent: Intent?) {
            val reportedId = intent?.getStringExtra("id") ?: id ?: ""
            if (resultCode == Activity.RESULT_OK && reportedId.isNotEmpty()) {
              sendEvent("onDelivered", mapOf("id" to reportedId))
            }

            if (deliveredPartsReported.incrementAndGet() >= numParts) {
              try {
                context.unregisterReceiver(deliveredReceiver)
              } catch (_: Exception) {}
            }
          }
        }

        ContextCompat.registerReceiver(
          context,
          sentReceiver,
          IntentFilter(actionSent),
          ContextCompat.RECEIVER_NOT_EXPORTED
        )

        ContextCompat.registerReceiver(
          context,
          deliveredReceiver,
          IntentFilter(actionDelivered),
          ContextCompat.RECEIVER_NOT_EXPORTED
        )

        // Clean up deliveredReceiver after 90 seconds if carrier never emits delivery report
        mainHandler.postDelayed({
          try {
            context.unregisterReceiver(deliveredReceiver)
          } catch (_: Exception) {}
        }, 90_000)

        // 30 seconds timeout for send ack
        mainHandler.postDelayed(timeoutRunnable, 30_000)

        if (numParts == 1) {
          smsManager.sendTextMessage(to, null, parts[0], sentIntents[0], deliveredIntents[0])
        } else {
          smsManager.sendMultipartTextMessage(to, null, parts, sentIntents, deliveredIntents)
        }
      } catch (e: Exception) {
        promise.resolve(mapOf("status" to "failed", "error" to (e.message ?: "Failed to dispatch SMS")))
      }
    }
  }

  private fun getSmsManager(context: Context, subId: Int?): SmsManager {
    return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      val baseManager = context.getSystemService(SmsManager::class.java)
      if (subId != null && subId >= 0) {
        baseManager.createForSubscriptionId(subId)
      } else {
        baseManager
      }
    } else {
      if (subId != null && subId >= 0) {
        @Suppress("DEPRECATION")
        SmsManager.getSmsManagerForSubscriptionId(subId)
      } else {
        @Suppress("DEPRECATION")
        SmsManager.getDefault()
      }
    }
  }

  private fun mapResultCodeToError(resultCode: Int): String {
    return when (resultCode) {
      SmsManager.RESULT_ERROR_GENERIC_FAILURE -> "Generic carrier failure (check SIM airtime or balance)"
      SmsManager.RESULT_ERROR_RADIO_OFF -> "Radio turned off (airplane mode enabled)"
      SmsManager.RESULT_ERROR_NULL_PDU -> "Null PDU error"
      SmsManager.RESULT_ERROR_NO_SERVICE -> "No cellular network service available"
      SmsManager.RESULT_ERROR_LIMIT_EXCEEDED -> "SMS rate limit exceeded by Android system"
      else -> "SMS send failed with Android error code $resultCode"
    }
  }
}
