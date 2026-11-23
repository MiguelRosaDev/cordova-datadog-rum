var exec = require('cordova/exec');

// Must match the <feature> name in plugin.xml and the class registered
// for each native platform (Android Kotlin & iOS Swift).
var PLUGIN_NAME = 'DatadogRum';

function isFunction(value) {
    return typeof value === 'function';
}

function normalizeHosts(allowedHosts) {
    if (Array.isArray(allowedHosts)) {
        return allowedHosts
            .map(function (host) { return typeof host === 'string' ? host.trim() : ''; })
            .filter(function (host) { return host.length > 0; });
    }
    if (typeof allowedHosts === 'string') {
        return allowedHosts
            .split(',')
            .map(function (host) { return host.trim(); })
            .filter(function (host) { return host.length > 0; });
    }
    return [];
}

var DatadogRum = {
    /**
     * Initializes Datadog Core SDK and enables the RUM feature (and optionally WebView Tracking).
     * Idempotent: if already initialized, resolves with `{ initialized: true, alreadyInitialized: true }`.
     *
     * @param {Object}   config
     * @param {string}   config.clientToken              Datadog Client Token (required).
     * @param {string}   config.applicationId            Datadog RUM Application ID (required).
     * @param {string}   config.env                      Environment name, e.g. "production", "staging" (required).
     * @param {string}   [config.site="US1"]             Datadog site: US1, US3, US5, EU1, AP1, AP2, UK1, US1_FED, US2_FED.
     * @param {string}   [config.service]                Service name (defaults to bundle/package ID).
     * @param {string}   [config.version]                Optional application version override.
     * @param {string}   [config.variant]                Optional Android build variant / flavor.
     * @param {string}   [config.trackingConsent="granted"] GDPR tracking consent: "granted", "not_granted", or "pending".
     * @param {number}   [config.sessionSampleRate=100]  Session sample rate (0 to 100).
     * @param {number}   [config.telemetrySampleRate=20] Internal SDK telemetry sample rate (0 to 100).
     * @param {boolean}  [config.trackViews=false]       Enable native automatic Activity/UIViewController view tracking.
     * @param {boolean}  [config.trackUserInteractions=false] Enable native automatic tap/interaction tracking.
     * @param {boolean}  [config.trackBackgroundEvents=false] Track RUM events when app is in background.
     * @param {boolean}  [config.trackFrustrations=true] Enable frustration signals tracking.
     * @param {number}   [config.longTaskThresholdMs=100] Main-thread long task threshold in ms (<= 0 disables).
     * @param {boolean}  [config.trackCrashReports=true] Enable Android crash reporting in Core configuration.
     * @param {string}   [config.verbosity="none"]       SDK debug verbosity: "debug", "warn", "error", "critical", "none".
     * @param {string[]|string} [config.webViewAllowedHosts] Optional hosts to enable WebViewTracking immediately.
     * @param {number}   [config.webViewLogsSampleRate=100] WebView logs sample rate (0 to 100).
     * @param {Function} [onSuccess]
     * @param {Function} [onError]
     */
    initialize: function (config, onSuccess, onError) {
        var payload = config && typeof config === 'object' ? Object.assign({}, config) : {};
        if (payload.webViewAllowedHosts !== undefined) {
            payload.webViewAllowedHosts = normalizeHosts(payload.webViewAllowedHosts);
        }
        exec(onSuccess, onError, PLUGIN_NAME, 'initialize', [payload]);
    },

    /**
     * Checks whether the Datadog SDK has been initialized.
     *
     * @param {Function} onSuccess Receives boolean (`true` or `false`).
     * @param {Function} [onError]
     */
    isInitialized: function (onSuccess, onError) {
        exec(onSuccess, onError, PLUGIN_NAME, 'isInitialized', []);
    },

    /**
     * Updates the GDPR tracking consent at runtime.
     *
     * @param {string}   consent   "granted" | "not_granted" | "pending".
     * @param {Function} [onSuccess]
     * @param {Function} [onError]
     */
    setTrackingConsent: function (consent, onSuccess, onError) {
        exec(onSuccess, onError, PLUGIN_NAME, 'setTrackingConsent', [consent]);
    },

    /**
     * Clears all unsent data currently stored by the Datadog SDK.
     *
     * @param {Function} [onSuccess]
     * @param {Function} [onError]
     */
    clearAllData: function (onSuccess, onError) {
        exec(onSuccess, onError, PLUGIN_NAME, 'clearAllData', []);
    },

    /**
     * Starts a RUM View (typically called on screen navigation / OutSystems OnReady).
     *
     * @param {string}   key          Unique identifier for the view (e.g. "/Home" or "HomeScreen").
     * @param {string}   [name]       Human-readable view name (defaults to `key`).
     * @param {Object}   [attributes] Optional custom attributes map.
     * @param {Function} [onSuccess]
     * @param {Function} [onError]
     */
    startView: function (key, name, attributes, onSuccess, onError) {
        var viewName = name;
        var attrs = attributes;
        var success = onSuccess;
        var error = onError;

        if (isFunction(name)) {
            success = name;
            error = attributes;
            viewName = key;
            attrs = {};
        } else if (isFunction(attributes)) {
            success = attributes;
            error = onSuccess;
            attrs = {};
        }

        exec(success, error, PLUGIN_NAME, 'startView', [
            key,
            viewName || key,
            attrs && typeof attrs === 'object' ? attrs : {}
        ]);
    },

    /**
     * Stops a previously started RUM View (typically called on OutSystems OnDestroy).
     *
     * @param {string}   key          View key passed to `startView`.
     * @param {Object}   [attributes] Optional custom attributes map.
     * @param {Function} [onSuccess]
     * @param {Function} [onError]
     */
    stopView: function (key, attributes, onSuccess, onError) {
        var attrs = attributes;
        var success = onSuccess;
        var error = onError;

        if (isFunction(attributes)) {
            success = attributes;
            error = onSuccess;
            attrs = {};
        }

        exec(success, error, PLUGIN_NAME, 'stopView', [
            key,
            attrs && typeof attrs === 'object' ? attrs : {}
        ]);
    },

    /**
     * Adds a custom timing measurement relative to the current active RUM View start time.
     *
     * @param {string}   name        Custom timing name (e.g. "content_loaded").
     * @param {Function} [onSuccess]
     * @param {Function} [onError]
     */
    addTiming: function (name, onSuccess, onError) {
        exec(onSuccess, onError, PLUGIN_NAME, 'addTiming', [name]);
    },

    /**
     * Records a discrete RUM user action (e.g. tap, click, custom).
     *
     * @param {string}   type         "tap" | "click" | "scroll" | "swipe" | "back" | "custom".
     * @param {string}   name         Action name (e.g. "checkout_button_clicked").
     * @param {Object}   [attributes] Optional custom attributes map.
     * @param {Function} [onSuccess]
     * @param {Function} [onError]
     */
    addAction: function (type, name, attributes, onSuccess, onError) {
        var attrs = attributes;
        var success = onSuccess;
        var error = onError;

        if (isFunction(attributes)) {
            success = attributes;
            error = onSuccess;
            attrs = {};
        }

        exec(success, error, PLUGIN_NAME, 'addAction', [
            type || 'custom',
            name,
            attrs && typeof attrs === 'object' ? attrs : {}
        ]);
    },

    /**
     * Starts a continuous RUM user action (e.g. scroll, swipe). Must be closed with `stopAction`.
     *
     * @param {string}   type         "tap" | "click" | "scroll" | "swipe" | "back" | "custom".
     * @param {string}   name         Action name.
     * @param {Object}   [attributes] Optional custom attributes map.
     * @param {Function} [onSuccess]
     * @param {Function} [onError]
     */
    startAction: function (type, name, attributes, onSuccess, onError) {
        var attrs = attributes;
        var success = onSuccess;
        var error = onError;

        if (isFunction(attributes)) {
            success = attributes;
            error = onSuccess;
            attrs = {};
        }

        exec(success, error, PLUGIN_NAME, 'startAction', [
            type || 'custom',
            name,
            attrs && typeof attrs === 'object' ? attrs : {}
        ]);
    },

    /**
     * Stops a previously started continuous RUM user action.
     *
     * @param {string}   type         Action type matching `startAction`.
     * @param {string}   name         Action name.
     * @param {Object}   [attributes] Optional custom attributes map.
     * @param {Function} [onSuccess]
     * @param {Function} [onError]
     */
    stopAction: function (type, name, attributes, onSuccess, onError) {
        var attrs = attributes;
        var success = onSuccess;
        var error = onError;

        if (isFunction(attributes)) {
            success = attributes;
            error = onSuccess;
            attrs = {};
        }

        exec(success, error, PLUGIN_NAME, 'stopAction', [
            type || 'custom',
            name,
            attrs && typeof attrs === 'object' ? attrs : {}
        ]);
    },

    /**
     * Records a RUM error attached to the active view.
     * Supports either an options object `{ message, source, stacktrace, errorType, attributes }`
     * or positional arguments `(message, source, stacktrace, errorType, attributes, onSuccess, onError)`.
     *
     * @param {string|Object} messageOrOptions Error message or options object.
     * @param {string|Function} [source="custom"] Error source: "source" | "network" | "webview" | "console" | "logger" | "custom".
     * @param {string|Function} [stacktrace]      Optional stack trace string.
     * @param {string|Function} [errorType]       Optional error type/class name.
     * @param {Object|Function} [attributes]      Optional custom attributes map.
     * @param {Function}        [onSuccess]
     * @param {Function}        [onError]
     */
    addError: function (messageOrOptions, source, stacktrace, errorType, attributes, onSuccess, onError) {
        var message;
        var errSource = 'custom';
        var stack = null;
        var type = null;
        var attrs = {};
        var success = onSuccess;
        var error = onError;

        if (messageOrOptions && typeof messageOrOptions === 'object') {
            message = messageOrOptions.message;
            errSource = messageOrOptions.source || 'custom';
            stack = messageOrOptions.stacktrace || null;
            type = messageOrOptions.errorType || null;
            attrs = messageOrOptions.attributes && typeof messageOrOptions.attributes === 'object'
                ? messageOrOptions.attributes
                : {};
            success = source;
            error = stacktrace;
        } else {
            message = messageOrOptions;
            if (isFunction(source)) {
                success = source;
                error = stacktrace;
            } else {
                errSource = source || 'custom';
                if (isFunction(stacktrace)) {
                    success = stacktrace;
                    error = errorType;
                } else {
                    stack = stacktrace || null;
                    if (isFunction(errorType)) {
                        success = errorType;
                        error = attributes;
                    } else {
                        type = errorType || null;
                        if (isFunction(attributes)) {
                            success = attributes;
                            error = onSuccess;
                        } else {
                            attrs = attributes && typeof attributes === 'object' ? attributes : {};
                        }
                    }
                }
            }
        }

        exec(success, error, PLUGIN_NAME, 'addError', [
            message,
            errSource,
            stack,
            type,
            attrs
        ]);
    },

    /**
     * Starts tracking a custom network/resource request.
     *
     * @param {string}   key          Unique identifier for this resource call.
     * @param {string}   method       HTTP method: GET, POST, PUT, DELETE, PATCH, HEAD, OPTIONS, TRACE, CONNECT.
     * @param {string}   url          Resource URL.
     * @param {Object}   [attributes] Optional custom attributes map.
     * @param {Function} [onSuccess]
     * @param {Function} [onError]
     */
    startResource: function (key, method, url, attributes, onSuccess, onError) {
        var attrs = attributes;
        var success = onSuccess;
        var error = onError;

        if (isFunction(attributes)) {
            success = attributes;
            error = onSuccess;
            attrs = {};
        }

        exec(success, error, PLUGIN_NAME, 'startResource', [
            key,
            method || 'GET',
            url,
            attrs && typeof attrs === 'object' ? attrs : {}
        ]);
    },

    /**
     * Stops tracking a resource request that completed.
     * Supports either an options object `{ key, statusCode, kind, size, attributes }`
     * or positional arguments `(key, statusCode, kind, size, attributes, onSuccess, onError)`.
     *
     * @param {string|Object} keyOrOptions Resource key or options object.
     * @param {number|Function} [statusCode] HTTP status code (e.g. 200).
     * @param {string|Function} [kind="other"] Resource kind: document, xhr, beacon, fetch, css, js, image, font, media, native, other.
     * @param {number|Function} [size]       Response size in bytes.
     * @param {Object|Function} [attributes] Optional custom attributes map.
     * @param {Function}        [onSuccess]
     * @param {Function}        [onError]
     */
    stopResource: function (keyOrOptions, statusCode, kind, size, attributes, onSuccess, onError) {
        var key;
        var code = null;
        var resKind = 'other';
        var resSize = null;
        var attrs = {};
        var success = onSuccess;
        var error = onError;

        if (keyOrOptions && typeof keyOrOptions === 'object') {
            key = keyOrOptions.key;
            code = keyOrOptions.statusCode !== undefined ? keyOrOptions.statusCode : null;
            resKind = keyOrOptions.kind || 'other';
            resSize = keyOrOptions.size !== undefined ? keyOrOptions.size : null;
            attrs = keyOrOptions.attributes && typeof keyOrOptions.attributes === 'object'
                ? keyOrOptions.attributes
                : {};
            success = statusCode;
            error = kind;
        } else {
            key = keyOrOptions;
            code = statusCode !== undefined ? statusCode : null;
            resKind = kind || 'other';
            if (isFunction(size)) {
                success = size;
                error = attributes;
            } else {
                resSize = size !== undefined ? size : null;
                if (isFunction(attributes)) {
                    success = attributes;
                    error = onSuccess;
                } else {
                    attrs = attributes && typeof attributes === 'object' ? attributes : {};
                }
            }
        }

        exec(success, error, PLUGIN_NAME, 'stopResource', [
            key,
            code,
            resKind,
            resSize,
            attrs
        ]);
    },

    /**
     * Stops tracking a resource request that failed with an error.
     * Supports either an options object `{ key, statusCode, message, source, stacktrace, errorType, attributes }`
     * or positional arguments.
     *
     * @param {string|Object} keyOrOptions Resource key or options object.
     * @param {number|Function} [statusCode] HTTP status code (optional).
     * @param {string|Function} [message]    Error message explaining the failure.
     * @param {string}          [source="network"] Error source.
     * @param {string}          [stacktrace=""]    Optional stack trace.
     * @param {string}          [errorType]        Optional error type.
     * @param {Object}          [attributes]       Optional custom attributes map.
     * @param {Function}        [onSuccess]
     * @param {Function}        [onError]
     */
    stopResourceWithError: function (keyOrOptions, statusCode, message, source, stacktrace, errorType, attributes, onSuccess, onError) {
        var key;
        var code = null;
        var errMsg = '';
        var errSource = 'network';
        var stack = '';
        var type = null;
        var attrs = {};
        var success = onSuccess;
        var error = onError;

        if (keyOrOptions && typeof keyOrOptions === 'object') {
            key = keyOrOptions.key;
            code = keyOrOptions.statusCode !== undefined ? keyOrOptions.statusCode : null;
            errMsg = keyOrOptions.message || '';
            errSource = keyOrOptions.source || 'network';
            stack = keyOrOptions.stacktrace || '';
            type = keyOrOptions.errorType || null;
            attrs = keyOrOptions.attributes && typeof keyOrOptions.attributes === 'object'
                ? keyOrOptions.attributes
                : {};
            success = statusCode;
            error = message;
        } else {
            key = keyOrOptions;
            code = statusCode !== undefined ? statusCode : null;
            errMsg = message || '';
            if (isFunction(source)) {
                success = source;
                error = stacktrace;
            } else {
                errSource = source || 'network';
                if (isFunction(stacktrace)) {
                    success = stacktrace;
                    error = errorType;
                } else {
                    stack = stacktrace || '';
                    if (isFunction(errorType)) {
                        success = errorType;
                        error = attributes;
                    } else {
                        type = errorType || null;
                        if (isFunction(attributes)) {
                            success = attributes;
                            error = onSuccess;
                        } else {
                            attrs = attributes && typeof attributes === 'object' ? attributes : {};
                        }
                    }
                }
            }
        }

        exec(success, error, PLUGIN_NAME, 'stopResourceWithError', [
            key,
            code,
            errMsg,
            errSource,
            stack,
            type,
            attrs
        ]);
    },

    /**
     * Adds a global custom attribute attached to all subsequent RUM events.
     *
     * @param {string}   key         Attribute key (supports dot-notation nesting).
     * @param {*}        value       Attribute value (string, number, boolean, object, array).
     * @param {Function} [onSuccess]
     * @param {Function} [onError]
     */
    addAttribute: function (key, value, onSuccess, onError) {
        exec(onSuccess, onError, PLUGIN_NAME, 'addAttribute', [key, value]);
    },

    /**
     * Removes a previously added global custom attribute.
     *
     * @param {string}   key         Attribute key to remove.
     * @param {Function} [onSuccess]
     * @param {Function} [onError]
     */
    removeAttribute: function (key, onSuccess, onError) {
        exec(onSuccess, onError, PLUGIN_NAME, 'removeAttribute', [key]);
    },

    /**
     * Sets user information attached to all subsequent RUM events.
     * Note: Avoid passing raw customer PII unless approved by your privacy policy;
     * prefer non-sensitive surrogate IDs (e.g. UserId / CustomerId).
     *
     * @param {Object}   user
     * @param {string}   user.id         Unique user identifier (required in Datadog SDK v3).
     * @param {string}   [user.name]     Optional user display name / alias.
     * @param {string}   [user.email]    Optional user email.
     * @param {Object}   [user.extraInfo] Optional extra user attributes map.
     * @param {Function} [onSuccess]
     * @param {Function} [onError]
     */
    setUser: function (user, onSuccess, onError) {
        exec(onSuccess, onError, PLUGIN_NAME, 'setUser', [
            user && typeof user === 'object' ? user : {}
        ]);
    },

    /**
     * Appends custom properties to the current user info without replacing existing fields.
     *
     * @param {Object}   extraInfo   Additional user properties map.
     * @param {Function} [onSuccess]
     * @param {Function} [onError]
     */
    addUserExtraInfo: function (extraInfo, onSuccess, onError) {
        exec(onSuccess, onError, PLUGIN_NAME, 'addUserExtraInfo', [
            extraInfo && typeof extraInfo === 'object' ? extraInfo : {}
        ]);
    },

    /**
     * Clears the current user information (typically called on logout).
     *
     * @param {Function} [onSuccess]
     * @param {Function} [onError]
     */
    clearUser: function (onSuccess, onError) {
        exec(onSuccess, onError, PLUGIN_NAME, 'clearUser', []);
    },

    /**
     * Asynchronously retrieves the current active RUM session ID (or null if none/sampled out).
     *
     * @param {Function} onSuccess Receives `string | null`.
     * @param {Function} [onError]
     */
    getCurrentSessionId: function (onSuccess, onError) {
        exec(onSuccess, onError, PLUGIN_NAME, 'getCurrentSessionId', []);
    },

    /**
     * Stops the current RUM session. A new session starts on the next `startView` or `addAction`.
     *
     * @param {Function} [onSuccess]
     * @param {Function} [onError]
     */
    stopSession: function (onSuccess, onError) {
        exec(onSuccess, onError, PLUGIN_NAME, 'stopSession', []);
    },

    /**
     * Records a feature flag evaluation on the current active RUM View.
     *
     * @param {string}   name        Feature flag name.
     * @param {*}        value       Evaluated feature flag value (non-null).
     * @param {Function} [onSuccess]
     * @param {Function} [onError]
     */
    addFeatureFlagEvaluation: function (name, value, onSuccess, onError) {
        exec(onSuccess, onError, PLUGIN_NAME, 'addFeatureFlagEvaluation', [name, value]);
    },

    /**
     * Attaches Datadog WebViewTracking to the Cordova WebView so Datadog Browser RUM events
     * loaded from `allowedHosts` correlate with the native Mobile RUM session.
     *
     * @param {string[]|string} allowedHosts          Allowed hostnames or wildcard patterns (e.g. ["app.example.com", "*.example.com"]).
     * @param {number|Function} [logsSampleRate=100]  WebView logs sample rate (0 to 100).
     * @param {Function}        [onSuccess]
     * @param {Function}        [onError]
     */
    enableWebViewTracking: function (allowedHosts, logsSampleRate, onSuccess, onError) {
        var sampleRate = logsSampleRate;
        var success = onSuccess;
        var error = onError;

        if (isFunction(logsSampleRate)) {
            success = logsSampleRate;
            error = onSuccess;
            sampleRate = 100;
        }

        if (typeof sampleRate !== 'number' || isNaN(sampleRate)) {
            sampleRate = 100;
        }

        exec(success, error, PLUGIN_NAME, 'enableWebViewTracking', [
            normalizeHosts(allowedHosts),
            sampleRate
        ]);
    }
};

module.exports = DatadogRum;
