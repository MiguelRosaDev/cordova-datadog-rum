# cordova-datadog-rum

Native Cordova plugin integrating **Datadog Real User Monitoring (RUM)** for **OutSystems 11 (MABS 12 & MABS 13)** using **Kotlin** on Android and **Swift** on iOS.

- **Android SDK**: `com.datadoghq:dd-sdk-android-rum:3.16.0` & `com.datadoghq:dd-sdk-android-webview:3.16.0` (Kotlin, Gradle)
- **iOS SDK**: `DatadogCore`, `DatadogRUM`, `DatadogWebViewTracking` `3.22.0` (Swift, dual **CocoaPods** for MABS 12 / `cordova-ios 7` and **Swift Package Manager** for MABS 13 / `cordova-ios 8`)
- **JS Namespace**: `cordova.plugins.custom.DatadogRum`

---

## Project Structure

```text
cordova-datadog-rum/
├── .gitignore
├── LICENSE
├── Package.swift                 # Swift Package Manager manifest (MABS 13 / cordova-ios 8)
├── package.json                  # npm / Cordova plugin metadata (version & engines synced)
├── plugin.xml                    # Cordova manifest (Android Kotlin + iOS Swift MABS 12/13 + preferences)
├── README.md                     # Documentation, initialization guide & OutSystems 11 examples
├── www/
│   └── DatadogRum.js             # JS bridge (clobbers cordova.plugins.custom.DatadogRum)
└── src/
    ├── android/
    │   └── DatadogRum.kt         # Android implementation (Kotlin, CordovaPlugin)
    └── ios/
        └── DatadogRum.swift      # iOS implementation (Swift, CDVPlugin)
```

---

## How Plugin Initialization Works

Datadog's mobile SDK documentation recommends initializing the SDK as early as possible in the application lifecycle (`Application.onCreate()` on Android and `AppDelegate.application(_:didFinishLaunchingWithOptions:)` on iOS).

In **OutSystems 11 / Cordova (MABS)**, overriding `android:name` on `<application>` or replacing `AppDelegate` frequently conflicts with MABS itself and other native plugins (such as Firebase or Salesforce Marketing Cloud). In addition, enterprise OutSystems factories deploy across **DEV / QA / PRD** via LifeTime and often retrieve environment configuration or GDPR consent dynamically at runtime.

To cover both enterprise and startup-first use cases cleanly and without MABS conflicts, this plugin supports **two validated initialization modes**:

### Comparison of Initialization Modes

| Aspect | Mode 1: Runtime JS `initialize()` *(Recommended for OutSystems)* | Mode 2: Native Auto-Initialize (`DATADOG_AUTO_INITIALIZE="true"`) |
| :--- | :--- | :--- |
| **When it runs** | Inside OutSystems `OnApplicationReady` client action (after `deviceready`). | Inside native `pluginInitialize()` via `<param name="onload" value="true" />` (before `deviceready` and before `OnApplicationReady`). |
| **Where config lives** | OutSystems Server Action / Site Properties / Configuration Entity per LifeTime environment. | Build-time Extensibility Configurations (`variables` or `preferences.global`). |
| **Change env / kill-switch** | Instant per environment without a new mobile build. | Requires updating Extensibility Configurations and generating a new MABS build. |
| **GDPR Consent flow** | Pass `trackingConsent: "pending"` or initialize only after consent. | Set `DATADOG_TRACKING_CONSENT="pending"`, then call `setTrackingConsent("granted" \| "not_granted")` from OutSystems. |
| **Early native lifecycle** | Starts once the OutSystems runtime loads. | Captures native startup and WebView setup earlier. |

> **Important OutSystems / Cordova Detail (`trackViews: false` by default):**
> An OutSystems mobile app renders all screens inside a **single** native WebView (`MainActivity` on Android, `CDVViewController` on iOS). On Android, Datadog's default `ActivityViewTrackingStrategy` would record only a single view named `MainActivity` for the entire app session.
> Therefore, this plugin defaults to `trackViews: false` (`useViewTrackingStrategy(null)` on Android, `uiKitViewsPredicate = nil` on iOS) so your OutSystems screens can report accurate screen names via `startView()` / `stopView()` (or via `WebViewTracking` with the Browser RUM SDK). Set `trackViews: true` only if your app presents multiple native screens/Activities.

> **Idempotency:**
> Calling `initialize()` when the SDK is already initialized (for example, if auto-initialization already ran or `OnApplicationReady` re-executes) is safe and returns `{ initialized: true, alreadyInitialized: true, webViewTrackingEnabled: <boolean> }` without re-initializing or crashing.

> **Datadog Credentials Reminder:**
> In Datadog (`Digital Experience > Real User Monitoring > New Application`), you create separate **Android** and **iOS** Mobile RUM applications (or obtain platform-specific `applicationId`s with a RUM `clientToken`). When using **Mode 1**, pass the platform-appropriate `applicationId` (check `GetOperatingSystem()` in OutSystems) or configure per-platform preferences in **Mode 2**.

---

### Mode 1: Runtime Initialization from OutSystems `OnApplicationReady` *(Recommended)*

1. Keep `DATADOG_AUTO_INITIALIZE` at its default (`"false"`) in Extensibility Configurations.
2. Fetch your per-environment `ClientToken`, `ApplicationId` (Android vs iOS), `Env`, `Site`, and `SessionSampleRate` from a Server Action (or local cached configuration fetched once at startup — never hardcode secrets in client literals).
3. Call `cordova.plugins.custom.DatadogRum.initialize(config, onSuccess, onError)` in OutSystems **`OnApplicationReady`**.

```javascript
cordova.plugins.custom.DatadogRum.initialize(
    {
        clientToken: '<DATADOG_CLIENT_TOKEN>',
        applicationId: '<DATADOG_RUM_APPLICATION_ID>',
        env: 'production',
        site: 'EU1',                    // US1 | US3 | US5 | EU1 | AP1 | AP2 | UK1 | US1_FED | US2_FED
        service: 'my-outsystems-app',   // Optional (defaults to package/bundle ID)
        version: '1.0.0',               // Optional (defaults to native app version)
        trackingConsent: 'pending',     // 'granted' | 'not_granted' | 'pending'
        sessionSampleRate: 100,         // 0..100
        telemetrySampleRate: 20,        // 0..100
        trackViews: false,              // Keep false for OutSystems WebView screens
        trackUserInteractions: false,   // Keep false unless tracking native UI widgets
        trackBackgroundEvents: false,
        trackFrustrations: true,
        longTaskThresholdMs: 100,       // <= 0 disables long task tracking
        trackCrashReports: true,        // Android Core crash reports
        verbosity: 'none'               // 'debug' | 'warn' | 'error' | 'critical' | 'none'
    },
    function (result) {
        console.log('Datadog RUM initialized:', result);
    },
    function (error) {
        console.error('Datadog RUM init error:', error);
    }
);
```

When the user accepts or declines GDPR tracking consent:

```javascript
// User accepted analytics/monitoring
cordova.plugins.custom.DatadogRum.setTrackingConsent('granted');

// User declined (deletes buffered pending events and stops collection)
cordova.plugins.custom.DatadogRum.setTrackingConsent('not_granted');
```

---

### Mode 2: Native Auto-Initialization at App Startup (Extensibility Configurations)

If you want Datadog RUM initialized natively before `deviceready` (inside `pluginInitialize()` via `<param name="onload" value="true" />`), pass the variables in your OutSystems Wrapper module's **Extensibility Configurations**:

```json
{
    "plugin": {
        "url": "https://github.com/MiguelRosaDev/cordova-datadog-rum.git#v1.0.0",
        "variables": [
            { "name": "DATADOG_AUTO_INITIALIZE", "value": "true" },
            { "name": "DATADOG_CLIENT_TOKEN", "value": "<DATADOG_CLIENT_TOKEN>" },
            { "name": "DATADOG_APPLICATION_ID", "value": "<DATADOG_RUM_APPLICATION_ID>" },
            { "name": "DATADOG_ENV", "value": "production" },
            { "name": "DATADOG_SITE", "value": "EU1" },
            { "name": "DATADOG_SERVICE", "value": "my-outsystems-app" },
            { "name": "DATADOG_TRACKING_CONSENT", "value": "pending" },
            { "name": "DATADOG_SESSION_SAMPLE_RATE", "value": "100" }
        ]
    }
}
```

> **Different Application IDs for Android and iOS in Mode 2:**
> If your Android and iOS Datadog RUM apps use different `applicationId` values, you can override `DatadogApplicationId` per platform using the `preferences.android` and `preferences.ios` sections in Extensibility Configurations:
> ```json
> {
>     "plugin": {
>         "url": "https://github.com/MiguelRosaDev/cordova-datadog-rum.git#v1.0.0",
>         "variables": [
>             { "name": "DATADOG_AUTO_INITIALIZE", "value": "true" },
>             { "name": "DATADOG_CLIENT_TOKEN", "value": "<DATADOG_CLIENT_TOKEN>" },
>             { "name": "DATADOG_ENV", "value": "production" },
>             { "name": "DATADOG_SITE", "value": "EU1" }
>         ]
>     },
>     "preferences": {
>         "android": [
>             { "name": "DatadogApplicationId", "value": "<ANDROID_RUM_APP_ID>" }
>         ],
>         "ios": [
>             { "name": "DatadogApplicationId", "value": "<IOS_RUM_APP_ID>" }
>         ]
>     }
> }
> ```

#### Supported Extensibility Variables (`plugin.xml`)

| Variable | `config.xml` Preference | Default | Description |
| :--- | :--- | :--- | :--- |
| `DATADOG_AUTO_INITIALIZE` | `DatadogAutoInitialize` | `false` | Set `"true"` to initialize natively in `pluginInitialize()`. |
| `DATADOG_CLIENT_TOKEN` | `DatadogClientToken` | `""` | Datadog Client Token (required for auto-init). |
| `DATADOG_APPLICATION_ID` | `DatadogApplicationId` | `""` | Datadog Mobile RUM Application ID (required for auto-init). |
| `DATADOG_ENV` | `DatadogEnv` | `production` | Datadog environment tag (`dev`, `qa`, `staging`, `production`). |
| `DATADOG_SITE` | `DatadogSite` | `US1` | Datadog site (`US1`, `US3`, `US5`, `EU1`, `AP1`, `AP2`, `UK1`, `US1_FED`, `US2_FED`). |
| `DATADOG_SERVICE` | `DatadogService` | `""` | Optional service name override. |
| `DATADOG_VERSION` | `DatadogVersion` | `""` | Optional app version override. |
| `DATADOG_TRACKING_CONSENT` | `DatadogTrackingConsent` | `granted` | Initial GDPR consent (`granted`, `not_granted`, `pending`). |
| `DATADOG_SESSION_SAMPLE_RATE` | `DatadogSessionSampleRate` | `100` | Session sample rate (`0`–`100`). |
| `DATADOG_TELEMETRY_SAMPLE_RATE` | `DatadogTelemetrySampleRate` | `20` | Internal SDK telemetry sample rate (`0`–`100`). |
| `DATADOG_TRACK_VIEWS` | `DatadogTrackViews` | `false` | Native Activity/UIViewController auto view tracking. |
| `DATADOG_TRACK_USER_INTERACTIONS` | `DatadogTrackUserInteractions` | `false` | Native UI interaction auto tracking. |
| `DATADOG_TRACK_BACKGROUND_EVENTS` | `DatadogTrackBackgroundEvents` | `false` | Track RUM events while app is in background. |
| `DATADOG_TRACK_FRUSTRATIONS` | `DatadogTrackFrustrations` | `true` | Track frustration signals (error taps). |
| `DATADOG_LONG_TASK_THRESHOLD_MS` | `DatadogLongTaskThresholdMs` | `100` | Main-thread long task threshold in ms (`<= 0` disables). |
| `DATADOG_VERBOSITY` | `DatadogVerbosity` | `none` | Native SDK log verbosity (`debug`, `warn`, `error`, `critical`, `none`). |
| `DATADOG_WEBVIEW_ALLOWED_HOSTS` | `DatadogWebViewAllowedHosts` | `""` | Comma-separated hostnames for Hybrid WebViewTracking (e.g. `app.example.com,*.example.com`). |

---

## Hybrid WebView Tracking (Connecting Mobile RUM with Browser RUM)

Because OutSystems Mobile applications run inside a native WebView (`WKWebView` on iOS, Android `WebView` on Android), there are two ways to instrument your app with Datadog RUM:

1. **Pure Native Mobile RUM (using only this Cordova plugin)** — Recommended for most OutSystems Mobile apps:
   - Call `initialize()` once in `OnApplicationReady`.
   - Call `startView()` / `stopView()` on OutSystems screen navigation (`OnReady` / `OnDestroy`), plus `addAction()`, `addError()`, `startResource()`/`stopResource()`, and `setUser()`.
   - Zero dependency on the Datadog Browser RUM script; works completely offline and batches uploads natively.
2. **Unified Mobile + Browser RUM (`WebViewTracking`)** — Use when your WebView or embedded web pages ALSO load the [Datadog Browser RUM SDK](https://docs.datadoghq.com/real_user_monitoring/application_monitoring/browser/) (`@datadog/browser-rum` v4.2.0+):
   - Pass `webViewAllowedHosts` in `initialize()` (or set `DATADOG_WEBVIEW_ALLOWED_HOSTS`, or call `enableWebViewTracking(allowedHosts)`).
   - This plugin attaches `WebViewTracking.enable(...)` (`dd-sdk-android-webview` on Android / `DatadogWebViewTracking` on iOS) to the Cordova WebView.
   - Browser RUM views, XHR/Fetch resources, console errors, and user clicks originating from the allowed hosts are forwarded through the native bridge and correlated under the **same `@session.id`** as the native Mobile RUM session.

```javascript
cordova.plugins.custom.DatadogRum.enableWebViewTracking(
    ['my-outsystems-env.outsystemsenterprise.com', '*.example.com'],
    100,
    function () { console.log('WebView tracking enabled'); },
    function (err) { console.error(err); }
);
```

---

## OutSystems 11 Wrapper Integration Guide

Follow the OutSystems wrapper module architecture (dedicated `<Name>_Plugin` module exposing Client Actions with standard `IsSuccess` / `ErrorMessage` outputs, availability checks, browser fallbacks, and guaranteed `$resolve()`):

### 1. Extensibility Configurations (Wrapper Module)

Pin the plugin to an immutable release tag (`#v1.0.0`):

```json
{
    "plugin": {
        "url": "https://github.com/MiguelRosaDev/cordova-datadog-rum.git#v1.0.0"
    }
}
```

### 2. Availability Helper Action (`CheckDatadogRumPlugin`)

Create a public Client Action `CheckDatadogRumPlugin` with output `IsAvailable` (Boolean):

```javascript
$parameters.IsAvailable = (
    typeof window.cordova !== 'undefined' &&
    typeof window.cordova.plugins !== 'undefined' &&
    typeof window.cordova.plugins.custom !== 'undefined' &&
    typeof window.cordova.plugins.custom.DatadogRum !== 'undefined'
);
$resolve();
```

### 3. Client Action JavaScript Nodes

Every wrapper Client Action should expose `IsSuccess` (Boolean) and `ErrorMessage` (Text), check plugin availability first, provide a safe desktop/browser fallback, and **always call `$resolve()`** in every branch.

#### `DatadogRum_Initialize` (Call in `OnApplicationReady`)

Inputs: `ClientToken`, `ApplicationId`, `Env`, `Site`, `Service`, `TrackingConsent`, `SessionSampleRate`
Outputs: `IsSuccess`, `AlreadyInitialized`, `ErrorMessage`

```javascript
var plugin = window.cordova && cordova.plugins && cordova.plugins.custom &&
    cordova.plugins.custom.DatadogRum;

if (!plugin || typeof plugin.initialize !== 'function') {
    $parameters.IsSuccess = false;
    $parameters.AlreadyInitialized = false;
    $parameters.ErrorMessage = 'DatadogRum plugin is not available on this platform.';
    $resolve();
} else {
    plugin.initialize(
        {
            clientToken: $parameters.ClientToken,
            applicationId: $parameters.ApplicationId,
            env: $parameters.Env,
            site: $parameters.Site || 'EU1',
            service: $parameters.Service || undefined,
            trackingConsent: $parameters.TrackingConsent || 'pending',
            sessionSampleRate: $parameters.SessionSampleRate || 100,
            trackViews: false,
            trackUserInteractions: false
        },
        function (result) {
            $parameters.IsSuccess = true;
            $parameters.AlreadyInitialized = !!(result && result.alreadyInitialized);
            $parameters.ErrorMessage = '';
            $resolve();
        },
        function (error) {
            $parameters.IsSuccess = false;
            $parameters.AlreadyInitialized = false;
            $parameters.ErrorMessage = typeof error === 'string' ? error : String(error);
            $resolve();
        }
    );
}
```

#### `DatadogRum_StartView` (Call in Screen `OnReady` or Layout Block)

Inputs: `ViewKey`, `ViewName`, `AttributesJson` (optional JSON Text)
Outputs: `IsSuccess`, `ErrorMessage`

```javascript
var plugin = window.cordova && cordova.plugins && cordova.plugins.custom &&
    cordova.plugins.custom.DatadogRum;

if (!plugin || typeof plugin.startView !== 'function') {
    $parameters.IsSuccess = false;
    $parameters.ErrorMessage = 'DatadogRum plugin is not available on this platform.';
    $resolve();
} else {
    var attrs = {};
    if ($parameters.AttributesJson) {
        try {
            attrs = JSON.parse($parameters.AttributesJson);
        } catch (e) {
            attrs = {};
        }
    }

    plugin.startView(
        $parameters.ViewKey,
        $parameters.ViewName || $parameters.ViewKey,
        attrs,
        function () {
            $parameters.IsSuccess = true;
            $parameters.ErrorMessage = '';
            $resolve();
        },
        function (error) {
            $parameters.IsSuccess = false;
            $parameters.ErrorMessage = typeof error === 'string' ? error : String(error);
            $resolve();
        }
    );
}
```

#### `DatadogRum_AddAction`

Inputs: `ActionType` (`"tap"`, `"click"`, `"scroll"`, `"swipe"`, `"custom"`), `ActionName`, `AttributesJson`
Outputs: `IsSuccess`, `ErrorMessage`

```javascript
var plugin = window.cordova && cordova.plugins && cordova.plugins.custom &&
    cordova.plugins.custom.DatadogRum;

if (!plugin || typeof plugin.addAction !== 'function') {
    $parameters.IsSuccess = false;
    $parameters.ErrorMessage = 'DatadogRum plugin is not available on this platform.';
    $resolve();
} else {
    var attrs = {};
    if ($parameters.AttributesJson) {
        try { attrs = JSON.parse($parameters.AttributesJson); } catch (e) { attrs = {}; }
    }

    plugin.addAction(
        $parameters.ActionType || 'custom',
        $parameters.ActionName,
        attrs,
        function () {
            $parameters.IsSuccess = true;
            $parameters.ErrorMessage = '';
            $resolve();
        },
        function (error) {
            $parameters.IsSuccess = false;
            $parameters.ErrorMessage = typeof error === 'string' ? error : String(error);
            $resolve();
        }
    );
}
```

#### `DatadogRum_AddError`

Inputs: `Message`, `Source`, `Stacktrace`, `ErrorType`, `AttributesJson`
Outputs: `IsSuccess`, `ErrorMessage`

```javascript
var plugin = window.cordova && cordova.plugins && cordova.plugins.custom &&
    cordova.plugins.custom.DatadogRum;

if (!plugin || typeof plugin.addError !== 'function') {
    $parameters.IsSuccess = false;
    $parameters.ErrorMessage = 'DatadogRum plugin is not available on this platform.';
    $resolve();
} else {
    var attrs = {};
    if ($parameters.AttributesJson) {
        try { attrs = JSON.parse($parameters.AttributesJson); } catch (e) { attrs = {}; }
    }

    plugin.addError(
        {
            message: $parameters.Message,
            source: $parameters.Source || 'custom',
            stacktrace: $parameters.Stacktrace || null,
            errorType: $parameters.ErrorType || null,
            attributes: attrs
        },
        function () {
            $parameters.IsSuccess = true;
            $parameters.ErrorMessage = '';
            $resolve();
        },
        function (error) {
            $parameters.IsSuccess = false;
            $parameters.ErrorMessage = typeof error === 'string' ? error : String(error);
            $resolve();
        }
    );
}
```

#### `DatadogRum_SetUser` (Security & GDPR Best Practice)

> **Privacy / GDPR Guardrail**: Never send sensitive customer PII (NIF, IBAN, phone/MSISDN, passwords, OTPs, tokens) into RUM attributes, error messages, or user fields. Prefer an internal non-sensitive surrogate identifier (`UserId` / `CustomerId`) in `id`, and call `clearUser()` on logout.

```javascript
var plugin = window.cordova && cordova.plugins && cordova.plugins.custom &&
    cordova.plugins.custom.DatadogRum;

if (!plugin || typeof plugin.setUser !== 'function') {
    $parameters.IsSuccess = false;
    $parameters.ErrorMessage = 'DatadogRum plugin is not available on this platform.';
    $resolve();
} else {
    plugin.setUser(
        {
            id: $parameters.UserId, // Required in Datadog SDK v3 (use internal surrogate ID)
            name: $parameters.UserAlias || undefined,
            email: $parameters.UserEmail || undefined
        },
        function () {
            $parameters.IsSuccess = true;
            $parameters.ErrorMessage = '';
            $resolve();
        },
        function (error) {
            $parameters.IsSuccess = false;
            $parameters.ErrorMessage = typeof error === 'string' ? error : String(error);
            $resolve();
        }
    );
}
```

---

## Complete JavaScript API Reference

All methods are exposed under `cordova.plugins.custom.DatadogRum`.

### Lifecycle & Privacy

| Method | Signature | Description |
| :--- | :--- | :--- |
| `initialize` | `initialize(config, onSuccess, onError)` | Initializes Datadog Core + RUM (and optional WebViewTracking). Resolves with `{ initialized, alreadyInitialized, webViewTrackingEnabled }`. |
| `isInitialized` | `isInitialized(onSuccess, onError)` | Resolves with `true` or `false`. |
| `setTrackingConsent` | `setTrackingConsent(consent, onSuccess, onError)` | Updates GDPR consent: `"granted"`, `"not_granted"`, or `"pending"`. |
| `clearAllData` | `clearAllData(onSuccess, onError)` | Purges all unsent buffered data from local SDK storage. |

### Views & Timings

| Method | Signature | Description |
| :--- | :--- | :--- |
| `startView` | `startView(key, name?, attributes?, onSuccess?, onError?)` | Starts tracking a screen/view (`key` must match `stopView`). |
| `stopView` | `stopView(key, attributes?, onSuccess?, onError?)` | Stops tracking a previously started view. |
| `addTiming` | `addTiming(name, onSuccess?, onError?)` | Adds a custom timing metric relative to the active view's start time. |

### User Actions

| Method | Signature | Description |
| :--- | :--- | :--- |
| `addAction` | `addAction(type, name, attributes?, onSuccess?, onError?)` | Tracks a discrete action (`"tap"`, `"click"`, `"scroll"`, `"swipe"`, `"back"`, `"custom"`). |
| `startAction` | `startAction(type, name, attributes?, onSuccess?, onError?)` | Starts a continuous/duration action (auto-closes after 10s if not stopped). |
| `stopAction` | `stopAction(type, name, attributes?, onSuccess?, onError?)` | Stops a continuous action started with `startAction`. |

> Note: On iOS, Datadog's `RUMActionType` does not have a `.back` case; `"back"` is mapped to `.custom` on iOS and `RumActionType.BACK` on Android.

### Errors

| Method | Signature | Description |
| :--- | :--- | :--- |
| `addError` | `addError({ message, source?, stacktrace?, errorType?, attributes? }, onSuccess?, onError?)` | Records an error attached to the active view. Also supports positional arguments `(message, source, stacktrace, errorType, attributes, onSuccess, onError)`. |

Valid `source` values: `"source"`, `"network"`, `"webview"`, `"console"`, `"logger"`, `"custom"` (Android also supports `"agent"` and `"report"`, mapped to `.custom` on iOS).

### Resources (Custom Network Tracking)

| Method | Signature | Description |
| :--- | :--- | :--- |
| `startResource` | `startResource(key, method, url, attributes?, onSuccess?, onError?)` | Starts tracking a resource call (`method`: `GET`, `POST`, `PUT`, `DELETE`, `PATCH`, `HEAD`, `OPTIONS`, `TRACE`, `CONNECT`). |
| `stopResource` | `stopResource({ key, statusCode?, kind?, size?, attributes? }, onSuccess?, onError?)` | Stops a completed resource (`kind`: `document`, `xhr`, `beacon`, `fetch`, `css`, `js`, `image`, `font`, `media`, `native`, `other`). |
| `stopResourceWithError` | `stopResourceWithError({ key, statusCode?, message, source?, stacktrace?, errorType?, attributes? }, onSuccess?, onError?)` | Stops a failed resource and attaches error metadata. |

### Global Attributes, User Info, Sessions, Feature Flags & WebView

| Method | Signature | Description |
| :--- | :--- | :--- |
| `addAttribute` | `addAttribute(key, value, onSuccess?, onError?)` | Adds a global attribute attached to all subsequent RUM events (supports dot-notation nesting). |
| `removeAttribute` | `removeAttribute(key, onSuccess?, onError?)` | Removes a global attribute. |
| `setUser` | `setUser({ id, name?, email?, extraInfo? }, onSuccess?, onError?)` | Sets user context (`id` is mandatory in Datadog SDK v3). |
| `addUserExtraInfo` | `addUserExtraInfo(extraInfo, onSuccess?, onError?)` | Merges additional custom properties into the current user context. |
| `clearUser` | `clearUser(onSuccess?, onError?)` | Clears user context (recommended on logout; call `stopSession()` first if you want the active session to retain prior user info). |
| `getCurrentSessionId` | `getCurrentSessionId(onSuccess, onError?)` | Asynchronously returns the active RUM `session.id` (`string \| null`). |
| `stopSession` | `stopSession(onSuccess?, onError?)` | Ends the current RUM session; a new session starts on the next `startView` or `addAction`. |
| `addFeatureFlagEvaluation` | `addFeatureFlagEvaluation(name, value, onSuccess?, onError?)` | Records a feature flag evaluation scoped to the active view. |
| `enableWebViewTracking` | `enableWebViewTracking(allowedHosts, logsSampleRate?, onSuccess?, onError?)` | Bridges Datadog Browser RUM events from Cordova's WebView into the native Mobile RUM session for the specified hosts (`string[]` or comma-separated `string`). |

---

## Native Logging & Troubleshooting

For security and GDPR compliance, native logs never print client tokens, user details, or raw attribute payloads — only action names and status summaries.

- **Android** (`adb logcat`):
  ```bash
  adb logcat | grep "\[DatadogRum\]"
  ```
- **iOS** (Xcode Console / Console.app): Filter by `[DatadogRum]`.
- **Datadog SDK Verbose Diagnostics**: Pass `verbosity: "debug"` in `initialize()` (or `DATADOG_VERBOSITY="debug"`) during non-production troubleshooting to inspect Datadog SDK upload batches and intake responses.

### MABS 12 & MABS 13 Compatibility Notes

- **Android**: Targets `cordova-android >= 13.0.0`, enables Kotlin (`GradlePluginKotlinEnabled=true`, `GradlePluginKotlinVersion=1.9.24`), and pulls `dd-sdk-android-rum:3.16.0` + `dd-sdk-android-webview:3.16.0` directly from Maven Central (requires Android `minSdk >= 23`, satisfied by MABS 12+).
- **iOS (MABS 12 / `cordova-ios 7.1`)**: Uses `<podspec>` (`use_frameworks="true"`, `nospm="true"`) to install `DatadogCore`, `DatadogRUM`, and `DatadogWebViewTracking` `~> 3.22.0` via CocoaPods (requires iOS `15.0+`, satisfied by MABS 12+).
- **iOS (MABS 13 / `cordova-ios 8`)**: Declares `<platform name="ios" package="swift">` and a root `Package.swift` whose library product (`cordova-datadog-rum`) matches `plugin.xml` `id`. `cordova-ios 8` ignores `<pod nospm="true" />` and resolves `dd-sdk-ios` natively via Swift Package Manager.

---

## References

- [Datadog Real User Monitoring — Browser Documentation](https://docs.datadoghq.com/real_user_monitoring/application_monitoring/browser/)
- [Datadog Android SDK (`dd-sdk-android`)](https://github.com/DataDog/dd-sdk-android)
- [Datadog iOS SDK (`dd-sdk-ios`)](https://github.com/DataDog/dd-sdk-ios)

## License

MIT
