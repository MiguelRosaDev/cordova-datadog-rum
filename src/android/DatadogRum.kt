package com.outsystems.plugins.datadogrum

import android.util.Log
import android.webkit.WebView
import com.datadog.android.Datadog
import com.datadog.android.DatadogSite
import com.datadog.android.core.configuration.Configuration
import com.datadog.android.privacy.TrackingConsent
import com.datadog.android.rum.GlobalRumMonitor
import com.datadog.android.rum.Rum
import com.datadog.android.rum.RumActionType
import com.datadog.android.rum.RumConfiguration
import com.datadog.android.rum.RumErrorSource
import com.datadog.android.rum.RumResourceKind
import com.datadog.android.rum.RumResourceMethod
import com.datadog.android.rum.tracking.ActivityViewTrackingStrategy
import com.datadog.android.webview.WebViewTracking
import org.apache.cordova.CallbackContext
import org.apache.cordova.CordovaPlugin
import org.apache.cordova.PluginResult
import org.json.JSONArray
import org.json.JSONObject
import java.util.Locale

/**
 * DatadogRum: Native Android implementation in Kotlin for OutSystems 11 (MABS 12 & MABS 13).
 *
 * Wraps the official Datadog Android SDK (`dd-sdk-android-rum` & `dd-sdk-android-webview`).
 * Security note: Never log client tokens, PII, or raw user attribute payloads to Logcat.
 */
class DatadogRum : CordovaPlugin() {

    companion object {
        private const val TAG = "[DatadogRum]"
        private const val DEFAULT_ENV = "production"
        private const val DEFAULT_SITE = "US1"
        private const val DEFAULT_CONSENT = "granted"
        private const val DEFAULT_SESSION_SAMPLE_RATE = 100f
        private const val DEFAULT_TELEMETRY_SAMPLE_RATE = 20f
        private const val DEFAULT_LONG_TASK_THRESHOLD_MS = 100L
        private const val NOT_INITIALIZED_ERROR =
            "Datadog RUM SDK is not initialized. Configure DATADOG_CLIENT_TOKEN and " +
                "DATADOG_ANDROID_APPLICATION_ID (or DATADOG_APPLICATION_ID) in Extensibility Configurations, " +
                "or call initialize() at runtime."
    }

    private data class InitOptions(
        val clientToken: String,
        val applicationId: String,
        val env: String,
        val site: DatadogSite,
        val service: String?,
        val version: String?,
        val variant: String,
        val trackingConsent: TrackingConsent,
        val sessionSampleRate: Float,
        val telemetrySampleRate: Float,
        val trackViews: Boolean,
        val trackUserInteractions: Boolean,
        val trackBackgroundEvents: Boolean,
        val trackFrustrations: Boolean,
        val longTaskThresholdMs: Long,
        val trackCrashReports: Boolean,
        val verbosity: Int,
        val webViewAllowedHosts: List<String>,
        val webViewLogsSampleRate: Float
    )

    override fun pluginInitialize() {
        super.pluginInitialize()
        Log.d(TAG, "Plugin loaded")

        val autoInitialize = preferences.getBoolean("DatadogAutoInitialize", true)
        if (!autoInitialize) {
            Log.d(TAG, "Auto-initialize disabled; waiting for JS initialize() call")
            return
        }

        val clientToken = cleanPreference("DatadogAndroidClientToken")
            .ifEmpty { cleanPreference("DatadogClientToken") }
        val applicationId = cleanPreference("DatadogAndroidApplicationId")
            .ifEmpty { cleanPreference("DatadogApplicationId") }
        if (clientToken.isEmpty() || applicationId.isEmpty()) {
            Log.w(
                TAG,
                "Auto-initialize skipped: missing credentials (set DATADOG_CLIENT_TOKEN and " +
                    "DATADOG_ANDROID_APPLICATION_ID / DATADOG_APPLICATION_ID in Extensibility Configurations)"
            )
            return
        }

        val options = InitOptions(
            clientToken = clientToken,
            applicationId = applicationId,
            env = cleanPreference("DatadogEnv").ifEmpty { DEFAULT_ENV },
            site = parseSite(cleanPreference("DatadogSite").ifEmpty { DEFAULT_SITE }),
            service = cleanPreference("DatadogService").ifEmpty { null },
            version = cleanPreference("DatadogVersion").ifEmpty { null },
            variant = "",
            trackingConsent = parseTrackingConsent(
                cleanPreference("DatadogTrackingConsent").ifEmpty { DEFAULT_CONSENT }
            ),
            sessionSampleRate = parseFloatPreference(
                "DatadogSessionSampleRate",
                DEFAULT_SESSION_SAMPLE_RATE
            ).coerceIn(0f, 100f),
            telemetrySampleRate = parseFloatPreference(
                "DatadogTelemetrySampleRate",
                DEFAULT_TELEMETRY_SAMPLE_RATE
            ).coerceIn(0f, 100f),
            trackViews = preferences.getBoolean("DatadogTrackViews", false),
            trackUserInteractions = preferences.getBoolean("DatadogTrackUserInteractions", false),
            trackBackgroundEvents = preferences.getBoolean("DatadogTrackBackgroundEvents", false),
            trackFrustrations = preferences.getBoolean("DatadogTrackFrustrations", true),
            longTaskThresholdMs = parseLongPreference(
                "DatadogLongTaskThresholdMs",
                DEFAULT_LONG_TASK_THRESHOLD_MS
            ),
            trackCrashReports = true,
            verbosity = parseVerbosity(cleanPreference("DatadogVerbosity")),
            webViewAllowedHosts = parseCommaSeparatedHosts(cleanPreference("DatadogWebViewAllowedHosts")),
            webViewLogsSampleRate = 100f
        )

        try {
            val result = performInitialize(options)
            Log.d(
                TAG,
                "Auto-initialization finished: initialized=${result.optBoolean("initialized")}, " +
                    "webViewTrackingEnabled=${result.optBoolean("webViewTrackingEnabled")}"
            )
        } catch (e: Exception) {
            Log.e(TAG, "Auto-initialization failed: ${e.message}", e)
        }
    }

    override fun execute(
        action: String,
        args: JSONArray,
        callbackContext: CallbackContext
    ): Boolean {
        Log.d(TAG, "execute: action=$action")

        return try {
            when (action) {
                "initialize" -> {
                    handleInitialize(args, callbackContext)
                    true
                }
                "isInitialized" -> {
                    handleIsInitialized(callbackContext)
                    true
                }
                "setTrackingConsent" -> {
                    handleSetTrackingConsent(args, callbackContext)
                    true
                }
                "clearAllData" -> {
                    handleClearAllData(callbackContext)
                    true
                }
                "startView" -> {
                    handleStartView(args, callbackContext)
                    true
                }
                "stopView" -> {
                    handleStopView(args, callbackContext)
                    true
                }
                "addTiming" -> {
                    handleAddTiming(args, callbackContext)
                    true
                }
                "addAction" -> {
                    handleAddAction(args, callbackContext)
                    true
                }
                "startAction" -> {
                    handleStartAction(args, callbackContext)
                    true
                }
                "stopAction" -> {
                    handleStopAction(args, callbackContext)
                    true
                }
                "addError" -> {
                    handleAddError(args, callbackContext)
                    true
                }
                "startResource" -> {
                    handleStartResource(args, callbackContext)
                    true
                }
                "stopResource" -> {
                    handleStopResource(args, callbackContext)
                    true
                }
                "stopResourceWithError" -> {
                    handleStopResourceWithError(args, callbackContext)
                    true
                }
                "addAttribute" -> {
                    handleAddAttribute(args, callbackContext)
                    true
                }
                "removeAttribute" -> {
                    handleRemoveAttribute(args, callbackContext)
                    true
                }
                "setUser" -> {
                    handleSetUser(args, callbackContext)
                    true
                }
                "addUserExtraInfo" -> {
                    handleAddUserExtraInfo(args, callbackContext)
                    true
                }
                "clearUser" -> {
                    handleClearUser(callbackContext)
                    true
                }
                "getCurrentSessionId" -> {
                    handleGetCurrentSessionId(callbackContext)
                    true
                }
                "stopSession" -> {
                    handleStopSession(callbackContext)
                    true
                }
                "addFeatureFlagEvaluation" -> {
                    handleAddFeatureFlagEvaluation(args, callbackContext)
                    true
                }
                "enableWebViewTracking" -> {
                    handleEnableWebViewTracking(args, callbackContext)
                    true
                }
                else -> {
                    Log.w(TAG, "Unknown action: $action")
                    false
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Exception during execute($action): ${e.message}", e)
            callbackContext.error("DatadogRum error: ${e.message}")
            true
        }
    }

    // ==================== LIFECYCLE & CONFIGURATION ====================

    private fun handleInitialize(args: JSONArray, callbackContext: CallbackContext) {
        val configObj = args.optJSONObject(0)
        if (configObj == null) {
            callbackContext.error("initialize requires a configuration object.")
            return
        }

        val clientToken = optTrimmedString(configObj, "clientToken")
        val applicationId = optTrimmedString(configObj, "applicationId")
        val env = optTrimmedString(configObj, "env")

        if (clientToken.isEmpty()) {
            callbackContext.error("Configuration 'clientToken' is required.")
            return
        }
        if (applicationId.isEmpty()) {
            callbackContext.error("Configuration 'applicationId' is required.")
            return
        }
        if (env.isEmpty()) {
            callbackContext.error("Configuration 'env' is required.")
            return
        }

        val sessionSampleRate = optDouble(
            configObj,
            "sessionSampleRate",
            DEFAULT_SESSION_SAMPLE_RATE.toDouble()
        ).coerceIn(0.0, 100.0).toFloat()

        val telemetrySampleRate = optDouble(
            configObj,
            "telemetrySampleRate",
            DEFAULT_TELEMETRY_SAMPLE_RATE.toDouble()
        ).coerceIn(0.0, 100.0).toFloat()

        val webViewLogsSampleRate = optDouble(
            configObj,
            "webViewLogsSampleRate",
            100.0
        ).coerceIn(0.0, 100.0).toFloat()

        val options = InitOptions(
            clientToken = clientToken,
            applicationId = applicationId,
            env = env,
            site = parseSite(optTrimmedString(configObj, "site").ifEmpty { DEFAULT_SITE }),
            service = optTrimmedString(configObj, "service").ifEmpty { null },
            version = optTrimmedString(configObj, "version").ifEmpty { null },
            variant = optTrimmedString(configObj, "variant"),
            trackingConsent = parseTrackingConsent(
                optTrimmedString(configObj, "trackingConsent").ifEmpty { DEFAULT_CONSENT }
            ),
            sessionSampleRate = sessionSampleRate,
            telemetrySampleRate = telemetrySampleRate,
            trackViews = configObj.optBoolean("trackViews", false),
            trackUserInteractions = configObj.optBoolean("trackUserInteractions", false),
            trackBackgroundEvents = configObj.optBoolean("trackBackgroundEvents", false),
            trackFrustrations = configObj.optBoolean("trackFrustrations", true),
            longTaskThresholdMs = configObj.optLong("longTaskThresholdMs", DEFAULT_LONG_TASK_THRESHOLD_MS),
            trackCrashReports = configObj.optBoolean("trackCrashReports", true),
            verbosity = parseVerbosity(optTrimmedString(configObj, "verbosity")),
            webViewAllowedHosts = extractHosts(configObj.opt("webViewAllowedHosts")),
            webViewLogsSampleRate = webViewLogsSampleRate
        )

        cordova.threadPool.execute {
            try {
                val result = performInitialize(options)
                callbackContext.success(result)
            } catch (e: Exception) {
                Log.e(TAG, "initialize failed: ${e.message}", e)
                callbackContext.error("DatadogRum initialize failed: ${e.message}")
            }
        }
    }

    private fun performInitialize(options: InitOptions): JSONObject {
        if (Datadog.isInitialized()) {
            Log.d(TAG, "SDK already initialized; skipping re-initialization")
            val webViewEnabled = if (options.webViewAllowedHosts.isNotEmpty()) {
                attachWebViewTracking(options.webViewAllowedHosts, options.webViewLogsSampleRate)
            } else {
                false
            }
            return JSONObject().apply {
                put("initialized", true)
                put("alreadyInitialized", true)
                put("webViewTrackingEnabled", webViewEnabled)
            }
        }

        val appContext = cordova.activity?.applicationContext
            ?: throw IllegalStateException("Android applicationContext is unavailable.")

        Datadog.setVerbosity(options.verbosity)

        val coreBuilder = Configuration.Builder(
            clientToken = options.clientToken,
            env = options.env,
            variant = options.variant,
            service = options.service
        )
            .useSite(options.site)
            .setCrashReportsEnabled(options.trackCrashReports)

        options.version?.let { coreBuilder.setVersion(it) }

        val sdkCore = Datadog.initialize(
            context = appContext,
            configuration = coreBuilder.build(),
            trackingConsent = options.trackingConsent
        ) ?: throw IllegalStateException("Datadog.initialize returned null; check env and configuration.")

        val rumBuilder = RumConfiguration.Builder(options.applicationId)
            .setSessionSampleRate(options.sessionSampleRate)
            .setTelemetrySampleRate(options.telemetrySampleRate)
            .trackBackgroundEvents(options.trackBackgroundEvents)
            .trackFrustrations(options.trackFrustrations)
            .trackLongTasks(options.longTaskThresholdMs)

        if (options.trackViews) {
            rumBuilder.useViewTrackingStrategy(ActivityViewTrackingStrategy(trackExtras = false))
        } else {
            // In Cordova/OutSystems apps, UI runs in a single WebView Activity.
            // Disabling automatic Activity tracking avoids polluting RUM with only "MainActivity"
            // so OutSystems screens can call startView/stopView (or use WebViewTracking).
            rumBuilder.useViewTrackingStrategy(null)
        }

        if (options.trackUserInteractions) {
            rumBuilder.trackUserInteractions()
        }

        Rum.enable(rumBuilder.build(), sdkCore)

        val webViewEnabled = if (options.webViewAllowedHosts.isNotEmpty()) {
            attachWebViewTracking(options.webViewAllowedHosts, options.webViewLogsSampleRate)
        } else {
            false
        }

        Log.d(
            TAG,
            "Initialized Datadog RUM (site=${options.site.name}, env=${options.env}, " +
                "consent=${options.trackingConsent.name}, trackViews=${options.trackViews}, " +
                "webViewTracking=$webViewEnabled)"
        )

        return JSONObject().apply {
            put("initialized", true)
            put("alreadyInitialized", false)
            put("webViewTrackingEnabled", webViewEnabled)
        }
    }

    private fun handleIsInitialized(callbackContext: CallbackContext) {
        callbackContext.sendPluginResult(
            PluginResult(PluginResult.Status.OK, Datadog.isInitialized())
        )
    }

    private fun handleSetTrackingConsent(args: JSONArray, callbackContext: CallbackContext) {
        if (!requireInitialized(callbackContext)) return
        val rawConsent = optStringArg(args, 0)
        if (rawConsent.isEmpty()) {
            callbackContext.error("Tracking consent is required ('granted', 'not_granted', or 'pending').")
            return
        }
        val consent = parseTrackingConsentStrict(rawConsent)
        if (consent == null) {
            callbackContext.error("Invalid tracking consent '$rawConsent'. Expected 'granted', 'not_granted', or 'pending'.")
            return
        }
        Datadog.setTrackingConsent(consent)
        Log.d(TAG, "setTrackingConsent: consent=${consent.name}")
        callbackContext.success()
    }

    private fun handleClearAllData(callbackContext: CallbackContext) {
        if (!requireInitialized(callbackContext)) return
        Datadog.clearAllData()
        Log.d(TAG, "clearAllData: completed")
        callbackContext.success()
    }

    // ==================== VIEWS ====================

    private fun handleStartView(args: JSONArray, callbackContext: CallbackContext) {
        if (!requireInitialized(callbackContext)) return
        val key = optStringArg(args, 0)
        if (key.isEmpty()) {
            callbackContext.error("startView requires a non-empty 'key'.")
            return
        }
        val name = optStringArg(args, 1).ifEmpty { key }
        val attributes = jsonObjectToMap(args.optJSONObject(2))

        GlobalRumMonitor.get().startView(key = key, name = name, attributes = attributes)
        Log.d(TAG, "startView: key=$key")
        callbackContext.success()
    }

    private fun handleStopView(args: JSONArray, callbackContext: CallbackContext) {
        if (!requireInitialized(callbackContext)) return
        val key = optStringArg(args, 0)
        if (key.isEmpty()) {
            callbackContext.error("stopView requires a non-empty 'key'.")
            return
        }
        val attributes = jsonObjectToMap(args.optJSONObject(1))

        GlobalRumMonitor.get().stopView(key = key, attributes = attributes)
        Log.d(TAG, "stopView: key=$key")
        callbackContext.success()
    }

    private fun handleAddTiming(args: JSONArray, callbackContext: CallbackContext) {
        if (!requireInitialized(callbackContext)) return
        val name = optStringArg(args, 0)
        if (name.isEmpty()) {
            callbackContext.error("addTiming requires a non-empty 'name'.")
            return
        }

        GlobalRumMonitor.get().addTiming(name = name)
        Log.d(TAG, "addTiming: name=$name")
        callbackContext.success()
    }

    // ==================== ACTIONS ====================

    private fun handleAddAction(args: JSONArray, callbackContext: CallbackContext) {
        if (!requireInitialized(callbackContext)) return
        val type = parseActionType(optStringArg(args, 0))
        val name = optStringArg(args, 1)
        if (name.isEmpty()) {
            callbackContext.error("addAction requires a non-empty 'name'.")
            return
        }
        val attributes = jsonObjectToMap(args.optJSONObject(2))

        GlobalRumMonitor.get().addAction(type = type, name = name, attributes = attributes)
        Log.d(TAG, "addAction: type=${type.name}")
        callbackContext.success()
    }

    private fun handleStartAction(args: JSONArray, callbackContext: CallbackContext) {
        if (!requireInitialized(callbackContext)) return
        val type = parseActionType(optStringArg(args, 0))
        val name = optStringArg(args, 1)
        if (name.isEmpty()) {
            callbackContext.error("startAction requires a non-empty 'name'.")
            return
        }
        val attributes = jsonObjectToMap(args.optJSONObject(2))

        GlobalRumMonitor.get().startAction(type = type, name = name, attributes = attributes)
        Log.d(TAG, "startAction: type=${type.name}")
        callbackContext.success()
    }

    private fun handleStopAction(args: JSONArray, callbackContext: CallbackContext) {
        if (!requireInitialized(callbackContext)) return
        val type = parseActionType(optStringArg(args, 0))
        val name = optStringArg(args, 1)
        if (name.isEmpty()) {
            callbackContext.error("stopAction requires a non-empty 'name'.")
            return
        }
        val attributes = jsonObjectToMap(args.optJSONObject(2))

        GlobalRumMonitor.get().stopAction(type = type, name = name, attributes = attributes)
        Log.d(TAG, "stopAction: type=${type.name}")
        callbackContext.success()
    }

    // ==================== ERRORS ====================

    private fun handleAddError(args: JSONArray, callbackContext: CallbackContext) {
        if (!requireInitialized(callbackContext)) return
        val message = optStringArg(args, 0)
        if (message.isEmpty()) {
            callbackContext.error("addError requires a non-empty 'message'.")
            return
        }
        val source = parseErrorSource(optStringArg(args, 1))
        val stacktrace = optNullableStringArg(args, 2)
        val errorType = optNullableStringArg(args, 3)
        val attributes = jsonObjectToMap(args.optJSONObject(4)).toMutableMap()
        if (!errorType.isNullOrBlank() && !attributes.containsKey("error_type")) {
            attributes["error_type"] = errorType
        }

        GlobalRumMonitor.get().addErrorWithStacktrace(
            message = message,
            source = source,
            stacktrace = stacktrace,
            attributes = attributes
        )
        Log.d(TAG, "addError: source=${source.name}")
        callbackContext.success()
    }

    // ==================== RESOURCES ====================

    private fun handleStartResource(args: JSONArray, callbackContext: CallbackContext) {
        if (!requireInitialized(callbackContext)) return
        val key = optStringArg(args, 0)
        val method = parseResourceMethod(optStringArg(args, 1))
        val url = optStringArg(args, 2)
        if (key.isEmpty() || url.isEmpty()) {
            callbackContext.error("startResource requires non-empty 'key' and 'url'.")
            return
        }
        val attributes = jsonObjectToMap(args.optJSONObject(3))

        GlobalRumMonitor.get().startResource(
            key = key,
            method = method,
            url = url,
            attributes = attributes
        )
        Log.d(TAG, "startResource: method=${method.name}")
        callbackContext.success()
    }

    private fun handleStopResource(args: JSONArray, callbackContext: CallbackContext) {
        if (!requireInitialized(callbackContext)) return
        val key = optStringArg(args, 0)
        if (key.isEmpty()) {
            callbackContext.error("stopResource requires a non-empty 'key'.")
            return
        }
        val statusCode = if (args.isNull(1)) null else args.optInt(1)
        val kind = parseResourceKind(optStringArg(args, 2))
        val size = if (args.isNull(3)) null else args.optLong(3)
        val attributes = jsonObjectToMap(args.optJSONObject(4))

        GlobalRumMonitor.get().stopResource(
            key = key,
            statusCode = statusCode,
            size = size,
            kind = kind,
            attributes = attributes
        )
        Log.d(TAG, "stopResource: kind=${kind.name}")
        callbackContext.success()
    }

    private fun handleStopResourceWithError(args: JSONArray, callbackContext: CallbackContext) {
        if (!requireInitialized(callbackContext)) return
        val key = optStringArg(args, 0)
        val statusCode = if (args.isNull(1)) null else args.optInt(1)
        val message = optStringArg(args, 2)
        val source = parseErrorSource(optStringArg(args, 3).ifEmpty { "network" })
        val stacktrace = optNullableStringArg(args, 4).orEmpty()
        val errorType = optNullableStringArg(args, 5)
        val attributes = jsonObjectToMap(args.optJSONObject(6))

        if (key.isEmpty() || message.isEmpty()) {
            callbackContext.error("stopResourceWithError requires non-empty 'key' and 'message'.")
            return
        }

        GlobalRumMonitor.get().stopResourceWithError(
            key = key,
            statusCode = statusCode,
            message = message,
            source = source,
            stackTrace = stacktrace,
            errorType = errorType,
            attributes = attributes
        )
        Log.d(TAG, "stopResourceWithError: source=${source.name}")
        callbackContext.success()
    }

    // ==================== GLOBAL ATTRIBUTES ====================

    private fun handleAddAttribute(args: JSONArray, callbackContext: CallbackContext) {
        if (!requireInitialized(callbackContext)) return
        val key = optStringArg(args, 0)
        if (key.isEmpty()) {
            callbackContext.error("addAttribute requires a non-empty 'key'.")
            return
        }
        val rawValue = if (args.isNull(1)) null else jsonValueToKotlin(args.opt(1))
        GlobalRumMonitor.get().addAttribute(key, rawValue)
        Log.d(TAG, "addAttribute: key=$key")
        callbackContext.success()
    }

    private fun handleRemoveAttribute(args: JSONArray, callbackContext: CallbackContext) {
        if (!requireInitialized(callbackContext)) return
        val key = optStringArg(args, 0)
        if (key.isEmpty()) {
            callbackContext.error("removeAttribute requires a non-empty 'key'.")
            return
        }
        GlobalRumMonitor.get().removeAttribute(key)
        Log.d(TAG, "removeAttribute: key=$key")
        callbackContext.success()
    }

    // ==================== USER INFO ====================

    private fun handleSetUser(args: JSONArray, callbackContext: CallbackContext) {
        if (!requireInitialized(callbackContext)) return
        val userObj = args.optJSONObject(0)
        if (userObj == null) {
            callbackContext.error("setUser requires a user object with an 'id'.")
            return
        }
        val id = optTrimmedString(userObj, "id")
        if (id.isEmpty()) {
            callbackContext.error("setUser requires a non-empty 'id' (mandatory in Datadog SDK v3).")
            return
        }
        val name = optTrimmedString(userObj, "name").ifEmpty { null }
        val email = optTrimmedString(userObj, "email").ifEmpty { null }
        val extraInfo = jsonObjectToMap(userObj.optJSONObject("extraInfo"))

        Datadog.setUserInfo(id = id, name = name, email = email, extraInfo = extraInfo)
        Log.d(TAG, "setUser: updated")
        callbackContext.success()
    }

    private fun handleAddUserExtraInfo(args: JSONArray, callbackContext: CallbackContext) {
        if (!requireInitialized(callbackContext)) return
        val extraObj = args.optJSONObject(0)
        if (extraObj == null) {
            callbackContext.error("addUserExtraInfo requires an object map.")
            return
        }
        Datadog.addUserProperties(jsonObjectToMap(extraObj))
        Log.d(TAG, "addUserExtraInfo: updated")
        callbackContext.success()
    }

    private fun handleClearUser(callbackContext: CallbackContext) {
        if (!requireInitialized(callbackContext)) return
        Datadog.clearUserInfo()
        Log.d(TAG, "clearUser: cleared")
        callbackContext.success()
    }

    // ==================== SESSION & FEATURE FLAGS ====================

    private fun handleGetCurrentSessionId(callbackContext: CallbackContext) {
        if (!requireInitialized(callbackContext)) return
        GlobalRumMonitor.get().getCurrentSessionId { sessionId ->
            callbackContext.sendPluginResult(PluginResult(PluginResult.Status.OK, sessionId))
        }
    }

    private fun handleStopSession(callbackContext: CallbackContext) {
        if (!requireInitialized(callbackContext)) return
        GlobalRumMonitor.get().stopSession()
        Log.d(TAG, "stopSession: stopped")
        callbackContext.success()
    }

    private fun handleAddFeatureFlagEvaluation(args: JSONArray, callbackContext: CallbackContext) {
        if (!requireInitialized(callbackContext)) return
        val name = optStringArg(args, 0)
        if (name.isEmpty()) {
            callbackContext.error("addFeatureFlagEvaluation requires a non-empty 'name'.")
            return
        }
        val value = if (args.isNull(1)) null else jsonValueToKotlin(args.opt(1))
        if (value == null) {
            callbackContext.error("addFeatureFlagEvaluation requires a non-null 'value'.")
            return
        }
        GlobalRumMonitor.get().addFeatureFlagEvaluation(name = name, value = value)
        Log.d(TAG, "addFeatureFlagEvaluation: name=$name")
        callbackContext.success()
    }

    // ==================== HYBRID WEBVIEW TRACKING ====================

    private fun handleEnableWebViewTracking(args: JSONArray, callbackContext: CallbackContext) {
        if (!requireInitialized(callbackContext)) return
        val hosts = extractHosts(args.opt(0))
        if (hosts.isEmpty()) {
            callbackContext.error("enableWebViewTracking requires at least one allowed host.")
            return
        }
        val logsSampleRate = args.optDouble(1, 100.0)
            .let { if (it.isNaN()) 100.0 else it }
            .coerceIn(0.0, 100.0)
            .toFloat()

        val activity = cordova.activity
        if (activity == null) {
            callbackContext.error("Android Activity is unavailable.")
            return
        }

        activity.runOnUiThread {
            try {
                val nativeWebView = webView?.engine?.view as? WebView
                if (nativeWebView == null) {
                    callbackContext.error("Cordova native Android WebView is unavailable.")
                    return@runOnUiThread
                }
                WebViewTracking.enable(
                    webView = nativeWebView,
                    allowedHosts = hosts,
                    logsSampleRate = logsSampleRate
                )
                Log.d(TAG, "enableWebViewTracking: enabled for ${hosts.size} host(s)")
                callbackContext.success()
            } catch (e: Exception) {
                Log.e(TAG, "enableWebViewTracking failed: ${e.message}", e)
                callbackContext.error("enableWebViewTracking failed: ${e.message}")
            }
        }
    }

    private fun attachWebViewTracking(hosts: List<String>, logsSampleRate: Float): Boolean {
        val activity = cordova.activity ?: return false
        val nativeWebView = webView?.engine?.view as? WebView ?: return false
        activity.runOnUiThread {
            try {
                WebViewTracking.enable(
                    webView = nativeWebView,
                    allowedHosts = hosts,
                    logsSampleRate = logsSampleRate
                )
                Log.d(TAG, "WebViewTracking attached for ${hosts.size} host(s)")
            } catch (e: Exception) {
                Log.e(TAG, "WebViewTracking attach failed: ${e.message}", e)
            }
        }
        return true
    }

    // ==================== HELPERS ====================

    private fun requireInitialized(callbackContext: CallbackContext): Boolean {
        if (!Datadog.isInitialized()) {
            Log.w(TAG, NOT_INITIALIZED_ERROR)
            callbackContext.error(NOT_INITIALIZED_ERROR)
            return false
        }
        return true
    }

    private fun cleanPreference(key: String): String {
        val value = preferences.getString(key, "")?.trim().orEmpty()
        return if (value.startsWith("$")) "" else value
    }

    private fun parseFloatPreference(key: String, defaultValue: Float): Float {
        return cleanPreference(key).toFloatOrNull() ?: defaultValue
    }

    private fun parseLongPreference(key: String, defaultValue: Long): Long {
        return cleanPreference(key).toLongOrNull() ?: defaultValue
    }

    private fun optStringArg(args: JSONArray, index: Int): String {
        if (index >= args.length() || args.isNull(index)) return ""
        return args.optString(index, "").trim()
    }

    private fun optNullableStringArg(args: JSONArray, index: Int): String? {
        if (index >= args.length() || args.isNull(index)) return null
        val value = args.optString(index, "")
        return value.ifEmpty { null }
    }

    private fun optTrimmedString(obj: JSONObject, key: String): String {
        if (!obj.has(key) || obj.isNull(key)) return ""
        return obj.optString(key, "").trim()
    }

    private fun optDouble(obj: JSONObject, key: String, defaultValue: Double): Double {
        if (!obj.has(key) || obj.isNull(key)) return defaultValue
        val value = obj.optDouble(key, defaultValue)
        return if (value.isNaN()) defaultValue else value
    }

    private fun parseCommaSeparatedHosts(raw: String): List<String> {
        if (raw.isEmpty()) return emptyList()
        return raw.split(",").map { it.trim() }.filter { it.isNotEmpty() }
    }

    private fun extractHosts(raw: Any?): List<String> {
        return when (raw) {
            is JSONArray -> {
                val list = mutableListOf<String>()
                for (i in 0 until raw.length()) {
                    val host = raw.optString(i, "").trim()
                    if (host.isNotEmpty()) list.add(host)
                }
                list
            }
            is String -> parseCommaSeparatedHosts(raw)
            else -> emptyList()
        }
    }

    private fun parseSite(raw: String): DatadogSite {
        return when (raw.trim().lowercase(Locale.US)) {
            "us3", "us3.datadoghq.com" -> DatadogSite.US3
            "us5", "us5.datadoghq.com" -> DatadogSite.US5
            "eu1", "eu", "datadoghq.eu", "app.datadoghq.eu" -> DatadogSite.EU1
            "ap1", "ap1.datadoghq.com" -> DatadogSite.AP1
            "ap2", "ap2.datadoghq.com" -> DatadogSite.AP2
            "uk1", "uk1.datadoghq.com" -> DatadogSite.UK1
            "us1_fed", "us1-fed", "ddog-gov.com", "app.ddog-gov.com" -> DatadogSite.US1_FED
            "us2_fed", "us2-fed", "us2.ddog-gov.com" -> DatadogSite.US2_FED
            else -> DatadogSite.US1
        }
    }

    private fun parseTrackingConsent(raw: String): TrackingConsent {
        return parseTrackingConsentStrict(raw) ?: TrackingConsent.GRANTED
    }

    private fun parseTrackingConsentStrict(raw: String): TrackingConsent? {
        return when (raw.trim().lowercase(Locale.US)) {
            "granted" -> TrackingConsent.GRANTED
            "not_granted", "notgranted", "not-granted" -> TrackingConsent.NOT_GRANTED
            "pending" -> TrackingConsent.PENDING
            else -> null
        }
    }

    private fun parseVerbosity(raw: String): Int {
        return when (raw.trim().lowercase(Locale.US)) {
            "verbose" -> Log.VERBOSE
            "debug" -> Log.DEBUG
            "info" -> Log.INFO
            "warn", "warning" -> Log.WARN
            "error" -> Log.ERROR
            "critical", "assert" -> Log.ASSERT
            else -> Int.MAX_VALUE
        }
    }

    private fun parseActionType(raw: String): RumActionType {
        return when (raw.trim().lowercase(Locale.US)) {
            "tap" -> RumActionType.TAP
            "click" -> RumActionType.CLICK
            "scroll" -> RumActionType.SCROLL
            "swipe" -> RumActionType.SWIPE
            "back" -> RumActionType.BACK
            else -> RumActionType.CUSTOM
        }
    }

    private fun parseErrorSource(raw: String): RumErrorSource {
        return when (raw.trim().lowercase(Locale.US)) {
            "network" -> RumErrorSource.NETWORK
            "source" -> RumErrorSource.SOURCE
            "console" -> RumErrorSource.CONSOLE
            "logger" -> RumErrorSource.LOGGER
            "agent" -> RumErrorSource.AGENT
            "webview" -> RumErrorSource.WEBVIEW
            "report" -> RumErrorSource.REPORT
            else -> RumErrorSource.CUSTOM
        }
    }

    private fun parseResourceMethod(raw: String): RumResourceMethod {
        return when (raw.trim().uppercase(Locale.US)) {
            "POST" -> RumResourceMethod.POST
            "HEAD" -> RumResourceMethod.HEAD
            "PUT" -> RumResourceMethod.PUT
            "DELETE" -> RumResourceMethod.DELETE
            "PATCH" -> RumResourceMethod.PATCH
            "TRACE" -> RumResourceMethod.TRACE
            "OPTIONS" -> RumResourceMethod.OPTIONS
            "CONNECT" -> RumResourceMethod.CONNECT
            else -> RumResourceMethod.GET
        }
    }

    private fun parseResourceKind(raw: String): RumResourceKind {
        return when (raw.trim().lowercase(Locale.US)) {
            "beacon" -> RumResourceKind.BEACON
            "fetch" -> RumResourceKind.FETCH
            "xhr" -> RumResourceKind.XHR
            "document" -> RumResourceKind.DOCUMENT
            "native" -> RumResourceKind.NATIVE
            "image" -> RumResourceKind.IMAGE
            "js" -> RumResourceKind.JS
            "font" -> RumResourceKind.FONT
            "css" -> RumResourceKind.CSS
            "media" -> RumResourceKind.MEDIA
            "unknown" -> RumResourceKind.UNKNOWN
            else -> RumResourceKind.OTHER
        }
    }

    private fun jsonObjectToMap(jsonObject: JSONObject?): Map<String, Any?> {
        if (jsonObject == null) return emptyMap()
        val map = mutableMapOf<String, Any?>()
        val keys = jsonObject.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            val value = jsonObject.opt(key)
            map[key] = jsonValueToKotlin(value)
        }
        return map
    }

    private fun jsonArrayToList(jsonArray: JSONArray): List<Any?> {
        val list = mutableListOf<Any?>()
        for (i in 0 until jsonArray.length()) {
            list.add(jsonValueToKotlin(jsonArray.opt(i)))
        }
        return list
    }

    private fun jsonValueToKotlin(value: Any?): Any? {
        return when (value) {
            null, JSONObject.NULL -> null
            is JSONObject -> jsonObjectToMap(value)
            is JSONArray -> jsonArrayToList(value)
            else -> value
        }
    }
}
