import Foundation
import WebKit

#if canImport(Cordova)
import Cordova
#endif

import DatadogCore
import DatadogRUM
import DatadogWebViewTracking

/**
 * DatadogRum: Native iOS implementation in Swift for OutSystems 11 (MABS 12 & MABS 13).
 *
 * Wraps the official Datadog iOS SDK (`DatadogCore`, `DatadogRUM`, `DatadogWebViewTracking`).
 *
 * Rules for OutSystems MABS (cordova-ios 7 & 8):
 * 1. Guard `import Cordova` with `#if canImport(Cordova)` for MABS 12 + MABS 13 SPM compatibility.
 * 2. Type `let pluginResult: CDVPluginResult = ...` explicitly and avoid optional chaining (`pluginResult?.`).
 * 3. Always log with `NSLog("%@", "\(tag) ...")` and never log client tokens, PII, or raw payloads.
 */
@objc(DatadogRum)
public class DatadogRum: CDVPlugin {

    private let tag = "[DatadogRum]"
    private let notInitializedError =
        "Datadog RUM SDK is not initialized. Call initialize() first or enable DATADOG_AUTO_INITIALIZE."

    private struct InitOptions {
        let clientToken: String
        let applicationId: String
        let env: String
        let site: String
        let service: String?
        let version: String?
        let trackingConsent: TrackingConsent
        let sessionSampleRate: Float
        let telemetrySampleRate: Float
        let trackViews: Bool
        let trackUserInteractions: Bool
        let trackBackgroundEvents: Bool
        let trackFrustrations: Bool
        let longTaskThresholdMs: Double
        let verbosity: String
        let webViewAllowedHosts: [String]
        let webViewLogsSampleRate: Float
    }

    public override func pluginInitialize() {
        super.pluginInitialize()
        NSLog("%@", "\(tag) Plugin loaded")

        let autoInitialize = boolSetting("datadogautoinitialize", defaultValue: false)
        if !autoInitialize {
            NSLog("%@", "\(tag) Auto-initialize disabled; waiting for JS initialize() call")
            return
        }

        let clientToken = cleanSetting("datadogclienttoken")
        let applicationId = cleanSetting("datadogapplicationid")
        if clientToken.isEmpty || applicationId.isEmpty {
            NSLog("%@", "\(tag) Auto-initialize enabled but clientToken or applicationId is missing")
            return
        }

        let envSetting = cleanSetting("datadogenv")
        let siteSetting = cleanSetting("datadogsite")
        let serviceSetting = cleanSetting("datadogservice")
        let versionSetting = cleanSetting("datadogversion")
        let consentSetting = cleanSetting("datadogtrackingconsent")

        let options = InitOptions(
            clientToken: clientToken,
            applicationId: applicationId,
            env: envSetting.isEmpty ? "production" : envSetting,
            site: siteSetting.isEmpty ? "US1" : siteSetting,
            service: serviceSetting.isEmpty ? nil : serviceSetting,
            version: versionSetting.isEmpty ? nil : versionSetting,
            trackingConsent: parseTrackingConsent(consentSetting.isEmpty ? "granted" : consentSetting),
            sessionSampleRate: clampRate(floatSetting("datadogsessionsamplerate", defaultValue: 100.0)),
            telemetrySampleRate: clampRate(floatSetting("datadogtelemetrysamplerate", defaultValue: 20.0)),
            trackViews: boolSetting("datadogtrackviews", defaultValue: false),
            trackUserInteractions: boolSetting("datadogtrackuserinteractions", defaultValue: false),
            trackBackgroundEvents: boolSetting("datadogtrackbackgroundevents", defaultValue: false),
            trackFrustrations: boolSetting("datadogtrackfrustrations", defaultValue: true),
            longTaskThresholdMs: doubleSetting("datadoglongtaskthresholdms", defaultValue: 100.0),
            verbosity: cleanSetting("datadogverbosity"),
            webViewAllowedHosts: parseCommaSeparatedHosts(cleanSetting("datadogwebviewallowedhosts")),
            webViewLogsSampleRate: 100.0
        )

        let result = performInitialize(options: options)
        let webViewEnabled = (result["webViewTrackingEnabled"] as? Bool) ?? false
        NSLog("%@", "\(tag) Auto-initialization finished: webViewTrackingEnabled=\(webViewEnabled)")
    }

    // ==================== LIFECYCLE & CONFIGURATION ====================

    @objc(initialize:)
    public func initialize(_ command: CDVInvokedUrlCommand) {
        NSLog("%@", "\(tag) execute: action=initialize")

        guard let config = command.arguments.first as? [String: Any] else {
            sendError("initialize requires a configuration object.", callbackId: command.callbackId)
            return
        }

        let clientToken = trimmedString(config["clientToken"])
        let applicationId = trimmedString(config["applicationId"])
        let env = trimmedString(config["env"])

        if clientToken.isEmpty {
            sendError("Configuration 'clientToken' is required.", callbackId: command.callbackId)
            return
        }
        if applicationId.isEmpty {
            sendError("Configuration 'applicationId' is required.", callbackId: command.callbackId)
            return
        }
        if env.isEmpty {
            sendError("Configuration 'env' is required.", callbackId: command.callbackId)
            return
        }

        let siteValue = trimmedString(config["site"])
        let serviceValue = trimmedString(config["service"])
        let versionValue = trimmedString(config["version"])
        let consentValue = trimmedString(config["trackingConsent"])

        let options = InitOptions(
            clientToken: clientToken,
            applicationId: applicationId,
            env: env,
            site: siteValue.isEmpty ? "US1" : siteValue,
            service: serviceValue.isEmpty ? nil : serviceValue,
            version: versionValue.isEmpty ? nil : versionValue,
            trackingConsent: parseTrackingConsent(consentValue.isEmpty ? "granted" : consentValue),
            sessionSampleRate: clampRate(floatValue(config["sessionSampleRate"], defaultValue: 100.0)),
            telemetrySampleRate: clampRate(floatValue(config["telemetrySampleRate"], defaultValue: 20.0)),
            trackViews: boolValue(config["trackViews"], defaultValue: false),
            trackUserInteractions: boolValue(config["trackUserInteractions"], defaultValue: false),
            trackBackgroundEvents: boolValue(config["trackBackgroundEvents"], defaultValue: false),
            trackFrustrations: boolValue(config["trackFrustrations"], defaultValue: true),
            longTaskThresholdMs: doubleValue(config["longTaskThresholdMs"], defaultValue: 100.0),
            verbosity: trimmedString(config["verbosity"]),
            webViewAllowedHosts: extractHosts(config["webViewAllowedHosts"]),
            webViewLogsSampleRate: clampRate(floatValue(config["webViewLogsSampleRate"], defaultValue: 100.0))
        )

        DispatchQueue.main.async {
            let result = self.performInitialize(options: options)
            let pluginResult: CDVPluginResult = CDVPluginResult(
                status: .ok,
                messageAs: result
            )
            self.commandDelegate.send(pluginResult, callbackId: command.callbackId)
        }
    }

    private func performInitialize(options: InitOptions) -> [AnyHashable: Any] {
        if Datadog.isInitialized() {
            NSLog("%@", "\(tag) SDK already initialized; skipping re-initialization")
            let webViewEnabled = options.webViewAllowedHosts.isEmpty
                ? false
                : attachWebViewTracking(hosts: options.webViewAllowedHosts, logsSampleRate: options.webViewLogsSampleRate)
            return [
                "initialized": true,
                "alreadyInitialized": true,
                "webViewTrackingEnabled": webViewEnabled
            ]
        }

        applyVerbosity(options.verbosity)

        var coreConfig = Datadog.Configuration(
            clientToken: options.clientToken,
            env: options.env,
            service: options.service,
            version: options.version
        )
        applySite(options.site, to: &coreConfig)

        Datadog.initialize(with: coreConfig, trackingConsent: options.trackingConsent)

        var rumConfig = RUM.Configuration(applicationID: options.applicationId)
        rumConfig.sessionSampleRate = options.sessionSampleRate
        rumConfig.telemetrySampleRate = options.telemetrySampleRate
        rumConfig.trackBackgroundEvents = options.trackBackgroundEvents
        rumConfig.trackFrustrations = options.trackFrustrations
        rumConfig.longTaskThreshold = options.longTaskThresholdMs > 0
            ? TimeInterval(options.longTaskThresholdMs) / 1000.0
            : nil

        if options.trackViews {
            rumConfig.uiKitViewsPredicate = DefaultUIKitRUMViewsPredicate()
        }
        if options.trackUserInteractions {
            rumConfig.uiKitActionsPredicate = DefaultUIKitRUMActionsPredicate()
        }

        RUM.enable(with: rumConfig)

        let webViewEnabled = options.webViewAllowedHosts.isEmpty
            ? false
            : attachWebViewTracking(hosts: options.webViewAllowedHosts, logsSampleRate: options.webViewLogsSampleRate)

        NSLog("%@", "\(tag) Initialized Datadog RUM (env=\(options.env), trackViews=\(options.trackViews), webViewTracking=\(webViewEnabled))")

        return [
            "initialized": true,
            "alreadyInitialized": false,
            "webViewTrackingEnabled": webViewEnabled
        ]
    }

    @objc(isInitialized:)
    public func isInitialized(_ command: CDVInvokedUrlCommand) {
        NSLog("%@", "\(tag) execute: action=isInitialized")
        let pluginResult: CDVPluginResult = CDVPluginResult(
            status: .ok,
            messageAs: Datadog.isInitialized()
        )
        commandDelegate.send(pluginResult, callbackId: command.callbackId)
    }

    @objc(setTrackingConsent:)
    public func setTrackingConsent(_ command: CDVInvokedUrlCommand) {
        NSLog("%@", "\(tag) execute: action=setTrackingConsent")
        guard requireInitialized(callbackId: command.callbackId) else { return }

        let rawConsent = trimmedString(command.arguments.first)
        guard !rawConsent.isEmpty else {
            sendError("Tracking consent is required ('granted', 'not_granted', or 'pending').", callbackId: command.callbackId)
            return
        }
        guard let consent = parseTrackingConsentStrict(rawConsent) else {
            sendError("Invalid tracking consent '\(rawConsent)'. Expected 'granted', 'not_granted', or 'pending'.", callbackId: command.callbackId)
            return
        }

        Datadog.set(trackingConsent: consent)
        NSLog("%@", "\(tag) setTrackingConsent: updated")
        sendOk(callbackId: command.callbackId)
    }

    @objc(clearAllData:)
    public func clearAllData(_ command: CDVInvokedUrlCommand) {
        NSLog("%@", "\(tag) execute: action=clearAllData")
        guard requireInitialized(callbackId: command.callbackId) else { return }

        Datadog.clearAllData()
        NSLog("%@", "\(tag) clearAllData: completed")
        sendOk(callbackId: command.callbackId)
    }

    // ==================== VIEWS ====================

    @objc(startView:)
    public func startView(_ command: CDVInvokedUrlCommand) {
        NSLog("%@", "\(tag) execute: action=startView")
        guard requireInitialized(callbackId: command.callbackId) else { return }

        let key = trimmedString(argument(at: 0, in: command))
        guard !key.isEmpty else {
            sendError("startView requires a non-empty 'key'.", callbackId: command.callbackId)
            return
        }
        let rawName = trimmedString(argument(at: 1, in: command))
        let name = rawName.isEmpty ? key : rawName
        let attributes = convertAttributes(argument(at: 2, in: command) as? [String: Any])

        RUMMonitor.shared().startView(key: key, name: name, attributes: attributes)
        NSLog("%@", "\(tag) startView: key=\(key)")
        sendOk(callbackId: command.callbackId)
    }

    @objc(stopView:)
    public func stopView(_ command: CDVInvokedUrlCommand) {
        NSLog("%@", "\(tag) execute: action=stopView")
        guard requireInitialized(callbackId: command.callbackId) else { return }

        let key = trimmedString(argument(at: 0, in: command))
        guard !key.isEmpty else {
            sendError("stopView requires a non-empty 'key'.", callbackId: command.callbackId)
            return
        }
        let attributes = convertAttributes(argument(at: 1, in: command) as? [String: Any])

        RUMMonitor.shared().stopView(key: key, attributes: attributes)
        NSLog("%@", "\(tag) stopView: key=\(key)")
        sendOk(callbackId: command.callbackId)
    }

    @objc(addTiming:)
    public func addTiming(_ command: CDVInvokedUrlCommand) {
        NSLog("%@", "\(tag) execute: action=addTiming")
        guard requireInitialized(callbackId: command.callbackId) else { return }

        let name = trimmedString(argument(at: 0, in: command))
        guard !name.isEmpty else {
            sendError("addTiming requires a non-empty 'name'.", callbackId: command.callbackId)
            return
        }

        RUMMonitor.shared().addTiming(name: name)
        NSLog("%@", "\(tag) addTiming: name=\(name)")
        sendOk(callbackId: command.callbackId)
    }

    // ==================== ACTIONS ====================

    @objc(addAction:)
    public func addAction(_ command: CDVInvokedUrlCommand) {
        NSLog("%@", "\(tag) execute: action=addAction")
        guard requireInitialized(callbackId: command.callbackId) else { return }

        let type = parseActionType(trimmedString(argument(at: 0, in: command)))
        let name = trimmedString(argument(at: 1, in: command))
        guard !name.isEmpty else {
            sendError("addAction requires a non-empty 'name'.", callbackId: command.callbackId)
            return
        }
        let attributes = convertAttributes(argument(at: 2, in: command) as? [String: Any])

        RUMMonitor.shared().addAction(type: type, name: name, attributes: attributes)
        sendOk(callbackId: command.callbackId)
    }

    @objc(startAction:)
    public func startAction(_ command: CDVInvokedUrlCommand) {
        NSLog("%@", "\(tag) execute: action=startAction")
        guard requireInitialized(callbackId: command.callbackId) else { return }

        let type = parseActionType(trimmedString(argument(at: 0, in: command)))
        let name = trimmedString(argument(at: 1, in: command))
        guard !name.isEmpty else {
            sendError("startAction requires a non-empty 'name'.", callbackId: command.callbackId)
            return
        }
        let attributes = convertAttributes(argument(at: 2, in: command) as? [String: Any])

        RUMMonitor.shared().startAction(type: type, name: name, attributes: attributes)
        sendOk(callbackId: command.callbackId)
    }

    @objc(stopAction:)
    public func stopAction(_ command: CDVInvokedUrlCommand) {
        NSLog("%@", "\(tag) execute: action=stopAction")
        guard requireInitialized(callbackId: command.callbackId) else { return }

        let type = parseActionType(trimmedString(argument(at: 0, in: command)))
        let name = trimmedString(argument(at: 1, in: command))
        guard !name.isEmpty else {
            sendError("stopAction requires a non-empty 'name'.", callbackId: command.callbackId)
            return
        }
        let attributes = convertAttributes(argument(at: 2, in: command) as? [String: Any])

        RUMMonitor.shared().stopAction(type: type, name: name, attributes: attributes)
        sendOk(callbackId: command.callbackId)
    }

    // ==================== ERRORS ====================

    @objc(addError:)
    public func addError(_ command: CDVInvokedUrlCommand) {
        NSLog("%@", "\(tag) execute: action=addError")
        guard requireInitialized(callbackId: command.callbackId) else { return }

        let message = trimmedString(argument(at: 0, in: command))
        guard !message.isEmpty else {
            sendError("addError requires a non-empty 'message'.", callbackId: command.callbackId)
            return
        }
        let source = parseErrorSource(trimmedString(argument(at: 1, in: command)))
        let stacktrace = optionalString(argument(at: 2, in: command))
        let errorType = optionalString(argument(at: 3, in: command))
        let attributes = convertAttributes(argument(at: 4, in: command) as? [String: Any])

        RUMMonitor.shared().addError(
            message: message,
            type: errorType,
            stack: stacktrace,
            source: source,
            attributes: attributes
        )
        sendOk(callbackId: command.callbackId)
    }

    // ==================== RESOURCES ====================

    @objc(startResource:)
    public func startResource(_ command: CDVInvokedUrlCommand) {
        NSLog("%@", "\(tag) execute: action=startResource")
        guard requireInitialized(callbackId: command.callbackId) else { return }

        let key = trimmedString(argument(at: 0, in: command))
        let method = parseResourceMethod(trimmedString(argument(at: 1, in: command)))
        let url = trimmedString(argument(at: 2, in: command))
        guard !key.isEmpty && !url.isEmpty else {
            sendError("startResource requires non-empty 'key' and 'url'.", callbackId: command.callbackId)
            return
        }
        let attributes = convertAttributes(argument(at: 3, in: command) as? [String: Any])

        RUMMonitor.shared().startResource(
            resourceKey: key,
            httpMethod: method,
            urlString: url,
            attributes: attributes
        )
        sendOk(callbackId: command.callbackId)
    }

    @objc(stopResource:)
    public func stopResource(_ command: CDVInvokedUrlCommand) {
        NSLog("%@", "\(tag) execute: action=stopResource")
        guard requireInitialized(callbackId: command.callbackId) else { return }

        let key = trimmedString(argument(at: 0, in: command))
        guard !key.isEmpty else {
            sendError("stopResource requires a non-empty 'key'.", callbackId: command.callbackId)
            return
        }
        let statusCode = optionalInt(argument(at: 1, in: command))
        let kind = parseResourceKind(trimmedString(argument(at: 2, in: command)))
        let size = optionalInt64(argument(at: 3, in: command))
        let attributes = convertAttributes(argument(at: 4, in: command) as? [String: Any])

        RUMMonitor.shared().stopResource(
            resourceKey: key,
            statusCode: statusCode,
            kind: kind,
            size: size,
            attributes: attributes
        )
        sendOk(callbackId: command.callbackId)
    }

    @objc(stopResourceWithError:)
    public func stopResourceWithError(_ command: CDVInvokedUrlCommand) {
        NSLog("%@", "\(tag) execute: action=stopResourceWithError")
        guard requireInitialized(callbackId: command.callbackId) else { return }

        let key = trimmedString(argument(at: 0, in: command))
        let statusCode = optionalInt(argument(at: 1, in: command))
        let message = trimmedString(argument(at: 2, in: command))
        let stacktrace = optionalString(argument(at: 4, in: command))
        let errorType = optionalString(argument(at: 5, in: command))
        var attributes = convertAttributes(argument(at: 6, in: command) as? [String: Any])

        guard !key.isEmpty && !message.isEmpty else {
            sendError("stopResourceWithError requires non-empty 'key' and 'message'.", callbackId: command.callbackId)
            return
        }

        if let code = statusCode, attributes["http.status_code"] == nil {
            attributes["http.status_code"] = code
        }
        if let stack = stacktrace, !stack.isEmpty, attributes["error.stack"] == nil {
            attributes["error.stack"] = stack
        }

        RUMMonitor.shared().stopResourceWithError(
            resourceKey: key,
            message: message,
            type: errorType,
            response: nil,
            attributes: attributes
        )
        sendOk(callbackId: command.callbackId)
    }

    // ==================== GLOBAL ATTRIBUTES ====================

    @objc(addAttribute:)
    public func addAttribute(_ command: CDVInvokedUrlCommand) {
        NSLog("%@", "\(tag) execute: action=addAttribute")
        guard requireInitialized(callbackId: command.callbackId) else { return }

        let key = trimmedString(argument(at: 0, in: command))
        guard !key.isEmpty else {
            sendError("addAttribute requires a non-empty 'key'.", callbackId: command.callbackId)
            return
        }
        let rawValue = argument(at: 1, in: command)
        if let value = rawValue, !(value is NSNull) {
            RUMMonitor.shared().addAttribute(forKey: key, value: AnyEncodableValue(value))
        } else {
            RUMMonitor.shared().removeAttribute(forKey: key)
        }
        NSLog("%@", "\(tag) addAttribute: key=\(key)")
        sendOk(callbackId: command.callbackId)
    }

    @objc(removeAttribute:)
    public func removeAttribute(_ command: CDVInvokedUrlCommand) {
        NSLog("%@", "\(tag) execute: action=removeAttribute")
        guard requireInitialized(callbackId: command.callbackId) else { return }

        let key = trimmedString(argument(at: 0, in: command))
        guard !key.isEmpty else {
            sendError("removeAttribute requires a non-empty 'key'.", callbackId: command.callbackId)
            return
        }

        RUMMonitor.shared().removeAttribute(forKey: key)
        NSLog("%@", "\(tag) removeAttribute: key=\(key)")
        sendOk(callbackId: command.callbackId)
    }

    // ==================== USER INFO ====================

    @objc(setUser:)
    public func setUser(_ command: CDVInvokedUrlCommand) {
        NSLog("%@", "\(tag) execute: action=setUser")
        guard requireInitialized(callbackId: command.callbackId) else { return }

        guard let user = command.arguments.first as? [String: Any] else {
            sendError("setUser requires a user object with an 'id'.", callbackId: command.callbackId)
            return
        }
        let id = trimmedString(user["id"])
        guard !id.isEmpty else {
            sendError("setUser requires a non-empty 'id' (mandatory in Datadog SDK v3).", callbackId: command.callbackId)
            return
        }
        let name = optionalString(user["name"])
        let email = optionalString(user["email"])
        let extraInfo = convertAttributes(user["extraInfo"] as? [String: Any])

        Datadog.setUserInfo(id: id, name: name, email: email, extraInfo: extraInfo)
        NSLog("%@", "\(tag) setUser: updated")
        sendOk(callbackId: command.callbackId)
    }

    @objc(addUserExtraInfo:)
    public func addUserExtraInfo(_ command: CDVInvokedUrlCommand) {
        NSLog("%@", "\(tag) execute: action=addUserExtraInfo")
        guard requireInitialized(callbackId: command.callbackId) else { return }

        guard let rawMap = command.arguments.first as? [String: Any] else {
            sendError("addUserExtraInfo requires an object map.", callbackId: command.callbackId)
            return
        }
        let optionalExtraInfo = convertOptionalAttributes(rawMap)
        Datadog.addUserExtraInfo(optionalExtraInfo)
        NSLog("%@", "\(tag) addUserExtraInfo: updated")
        sendOk(callbackId: command.callbackId)
    }

    @objc(clearUser:)
    public func clearUser(_ command: CDVInvokedUrlCommand) {
        NSLog("%@", "\(tag) execute: action=clearUser")
        guard requireInitialized(callbackId: command.callbackId) else { return }

        Datadog.clearUserInfo()
        NSLog("%@", "\(tag) clearUser: cleared")
        sendOk(callbackId: command.callbackId)
    }

    // ==================== SESSION & FEATURE FLAGS ====================

    @objc(getCurrentSessionId:)
    public func getCurrentSessionId(_ command: CDVInvokedUrlCommand) {
        NSLog("%@", "\(tag) execute: action=getCurrentSessionId")
        guard requireInitialized(callbackId: command.callbackId) else { return }

        RUMMonitor.shared().currentSessionID { sessionId in
            let pluginResult: CDVPluginResult
            if let sessionId = sessionId {
                pluginResult = CDVPluginResult(status: .ok, messageAs: sessionId)
            } else {
                pluginResult = CDVPluginResult(status: .ok)
            }
            self.commandDelegate.send(pluginResult, callbackId: command.callbackId)
        }
    }

    @objc(stopSession:)
    public func stopSession(_ command: CDVInvokedUrlCommand) {
        NSLog("%@", "\(tag) execute: action=stopSession")
        guard requireInitialized(callbackId: command.callbackId) else { return }

        RUMMonitor.shared().stopSession()
        NSLog("%@", "\(tag) stopSession: stopped")
        sendOk(callbackId: command.callbackId)
    }

    @objc(addFeatureFlagEvaluation:)
    public func addFeatureFlagEvaluation(_ command: CDVInvokedUrlCommand) {
        NSLog("%@", "\(tag) execute: action=addFeatureFlagEvaluation")
        guard requireInitialized(callbackId: command.callbackId) else { return }

        let name = trimmedString(argument(at: 0, in: command))
        guard !name.isEmpty else {
            sendError("addFeatureFlagEvaluation requires a non-empty 'name'.", callbackId: command.callbackId)
            return
        }
        guard let rawValue = argument(at: 1, in: command), !(rawValue is NSNull) else {
            sendError("addFeatureFlagEvaluation requires a non-null 'value'.", callbackId: command.callbackId)
            return
        }

        RUMMonitor.shared().addFeatureFlagEvaluation(name: name, value: AnyEncodableValue(rawValue))
        NSLog("%@", "\(tag) addFeatureFlagEvaluation: name=\(name)")
        sendOk(callbackId: command.callbackId)
    }

    // ==================== HYBRID WEBVIEW TRACKING ====================

    @objc(enableWebViewTracking:)
    public func enableWebViewTracking(_ command: CDVInvokedUrlCommand) {
        NSLog("%@", "\(tag) execute: action=enableWebViewTracking")
        guard requireInitialized(callbackId: command.callbackId) else { return }

        let hosts = extractHosts(argument(at: 0, in: command))
        guard !hosts.isEmpty else {
            sendError("enableWebViewTracking requires at least one allowed host.", callbackId: command.callbackId)
            return
        }
        let logsSampleRate = clampRate(floatValue(argument(at: 1, in: command), defaultValue: 100.0))

        DispatchQueue.main.async {
            guard let wkWebView = self.webView as? WKWebView else {
                self.sendError("Cordova native WKWebView is unavailable.", callbackId: command.callbackId)
                return
            }
            WebViewTracking.enable(
                webView: wkWebView,
                hosts: Set(hosts),
                logsSampleRate: logsSampleRate
            )
            NSLog("%@", "\(self.tag) enableWebViewTracking: enabled for \(hosts.count) host(s)")
            self.sendOk(callbackId: command.callbackId)
        }
    }

    private func attachWebViewTracking(hosts: [String], logsSampleRate: Float) -> Bool {
        guard !hosts.isEmpty else { return false }
        guard let wkWebView = self.webView as? WKWebView else {
            NSLog("%@", "\(tag) WebViewTracking skipped: WKWebView unavailable")
            return false
        }
        let apply = {
            WebViewTracking.enable(
                webView: wkWebView,
                hosts: Set(hosts),
                logsSampleRate: logsSampleRate
            )
            NSLog("%@", "\(self.tag) WebViewTracking attached for \(hosts.count) host(s)")
        }
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
        return true
    }

    // ==================== HELPERS ====================

    private func requireInitialized(callbackId: String) -> Bool {
        if !Datadog.isInitialized() {
            NSLog("%@", "\(tag) \(notInitializedError)")
            sendError(notInitializedError, callbackId: callbackId)
            return false
        }
        return true
    }

    private func sendOk(callbackId: String) {
        let pluginResult: CDVPluginResult = CDVPluginResult(status: .ok)
        commandDelegate.send(pluginResult, callbackId: callbackId)
    }

    private func sendError(_ message: String, callbackId: String) {
        let pluginResult: CDVPluginResult = CDVPluginResult(
            status: .error,
            messageAs: message
        )
        commandDelegate.send(pluginResult, callbackId: callbackId)
    }

    private func argument(at index: Int, in command: CDVInvokedUrlCommand) -> Any? {
        guard index >= 0 && index < command.arguments.count else { return nil }
        return command.arguments[index]
    }

    private func cleanSetting(_ lowercaseKey: String) -> String {
        guard let raw = commandDelegate.settings[lowercaseKey] as? String else { return "" }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("$") ? "" : trimmed
    }

    private func boolSetting(_ lowercaseKey: String, defaultValue: Bool) -> Bool {
        let raw = cleanSetting(lowercaseKey).lowercased()
        if raw.isEmpty { return defaultValue }
        return raw == "true" || raw == "1" || raw == "yes"
    }

    private func floatSetting(_ lowercaseKey: String, defaultValue: Float) -> Float {
        let raw = cleanSetting(lowercaseKey)
        return Float(raw) ?? defaultValue
    }

    private func doubleSetting(_ lowercaseKey: String, defaultValue: Double) -> Double {
        let raw = cleanSetting(lowercaseKey)
        return Double(raw) ?? defaultValue
    }

    private func trimmedString(_ value: Any?) -> String {
        guard let str = value as? String else { return "" }
        return str.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func optionalString(_ value: Any?) -> String? {
        guard let str = value as? String else { return nil }
        let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func boolValue(_ value: Any?, defaultValue: Bool) -> Bool {
        if let boolVal = value as? Bool { return boolVal }
        if let numVal = value as? NSNumber { return numVal.boolValue }
        if let strVal = value as? String {
            let lowered = strVal.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if lowered == "true" || lowered == "1" { return true }
            if lowered == "false" || lowered == "0" { return false }
        }
        return defaultValue
    }

    private func floatValue(_ value: Any?, defaultValue: Float) -> Float {
        if let numVal = value as? NSNumber { return numVal.floatValue }
        if let strVal = value as? String, let parsed = Float(strVal) { return parsed }
        return defaultValue
    }

    private func doubleValue(_ value: Any?, defaultValue: Double) -> Double {
        if let numVal = value as? NSNumber { return numVal.doubleValue }
        if let strVal = value as? String, let parsed = Double(strVal) { return parsed }
        return defaultValue
    }

    private func optionalInt(_ value: Any?) -> Int? {
        guard let value = value, !(value is NSNull) else { return nil }
        if let numVal = value as? NSNumber { return numVal.intValue }
        if let strVal = value as? String { return Int(strVal) }
        return nil
    }

    private func optionalInt64(_ value: Any?) -> Int64? {
        guard let value = value, !(value is NSNull) else { return nil }
        if let numVal = value as? NSNumber { return numVal.int64Value }
        if let strVal = value as? String { return Int64(strVal) }
        return nil
    }

    private func clampRate(_ rate: Float) -> Float {
        return min(max(rate, 0.0), 100.0)
    }

    private func parseCommaSeparatedHosts(_ raw: String) -> [String] {
        guard !raw.isEmpty else { return [] }
        return raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func extractHosts(_ raw: Any?) -> [String] {
        if let array = raw as? [Any] {
            return array.compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        if let str = raw as? String {
            return parseCommaSeparatedHosts(str)
        }
        return []
    }

    private func applySite(_ raw: String, to config: inout Datadog.Configuration) {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "us3", "us3.datadoghq.com":
            config.site = .us3
        case "us5", "us5.datadoghq.com":
            config.site = .us5
        case "eu1", "eu", "datadoghq.eu", "app.datadoghq.eu":
            config.site = .eu1
        case "ap1", "ap1.datadoghq.com":
            config.site = .ap1
        case "ap2", "ap2.datadoghq.com":
            config.site = .ap2
        case "uk1", "uk1.datadoghq.com":
            config.site = .uk1
        case "us1_fed", "us1-fed", "ddog-gov.com", "app.ddog-gov.com":
            config.site = .us1_fed
        case "us2_fed", "us2-fed", "us2.ddog-gov.com":
            config.site = .us2_fed
        default:
            config.site = .us1
        }
    }

    private func applyVerbosity(_ raw: String) {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "debug", "verbose":
            Datadog.verbosityLevel = .debug
        case "warn", "warning":
            Datadog.verbosityLevel = .warn
        case "error":
            Datadog.verbosityLevel = .error
        case "critical":
            Datadog.verbosityLevel = .critical
        default:
            Datadog.verbosityLevel = nil
        }
    }

    private func parseTrackingConsent(_ raw: String) -> TrackingConsent {
        return parseTrackingConsentStrict(raw) ?? .granted
    }

    private func parseTrackingConsentStrict(_ raw: String) -> TrackingConsent? {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "granted":
            return .granted
        case "not_granted", "notgranted", "not-granted":
            return .notGranted
        case "pending":
            return .pending
        default:
            return nil
        }
    }

    private func parseActionType(_ raw: String) -> RUMActionType {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "tap":
            return .tap
        case "click":
            return .click
        case "scroll":
            return .scroll
        case "swipe":
            return .swipe
        default:
            return .custom
        }
    }

    private func parseErrorSource(_ raw: String) -> RUMErrorSource {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "source":
            return .source
        case "network":
            return .network
        case "webview":
            return .webview
        case "console":
            return .console
        case "logger":
            return .logger
        default:
            return .custom
        }
    }

    private func parseResourceMethod(_ raw: String) -> RUMMethod {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "POST":
            return .post
        case "HEAD":
            return .head
        case "PUT":
            return .put
        case "DELETE":
            return .delete
        case "PATCH":
            return .patch
        case "TRACE":
            return .trace
        case "OPTIONS":
            return .options
        case "CONNECT":
            return .connect
        default:
            return .get
        }
    }

    private func parseResourceKind(_ raw: String) -> RUMResourceType {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "document":
            return .document
        case "xhr":
            return .xhr
        case "beacon":
            return .beacon
        case "fetch":
            return .fetch
        case "css":
            return .css
        case "js":
            return .js
        case "image":
            return .image
        case "font":
            return .font
        case "media":
            return .media
        case "native":
            return .native
        default:
            return .other
        }
    }

    private func convertAttributes(_ raw: [String: Any]?) -> [String: Encodable] {
        guard let raw = raw else { return [:] }
        var result: [String: Encodable] = [:]
        for (key, value) in raw {
            if !(value is NSNull) {
                result[key] = AnyEncodableValue(value)
            }
        }
        return result
    }

    private func convertOptionalAttributes(_ raw: [String: Any]) -> [String: Encodable?] {
        var result: [String: Encodable?] = [:]
        for (key, value) in raw {
            if value is NSNull {
                result[key] = nil
            } else {
                result[key] = AnyEncodableValue(value)
            }
        }
        return result
    }
}

/// Self-contained `Encodable` wrapper for arbitrary JSON payloads bridged from Cordova JS.
private struct AnyEncodableValue: Encodable {
    private let value: Any

    init(_ value: Any) {
        self.value = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case is NSNull:
            try container.encodeNil()
        case let string as String:
            try container.encode(string)
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                try container.encode(number.boolValue)
            } else {
                let doubleVal = number.doubleValue
                if doubleVal.isFinite &&
                    doubleVal.truncatingRemainder(dividingBy: 1) == 0 &&
                    doubleVal >= Double(Int64.min) &&
                    doubleVal <= Double(Int64.max) {
                    try container.encode(number.int64Value)
                } else {
                    try container.encode(doubleVal)
                }
            }
        case let array as [Any]:
            try container.encode(array.map { AnyEncodableValue($0) })
        case let dict as [String: Any]:
            let mapped = dict.mapValues { AnyEncodableValue($0) }
            try container.encode(mapped)
        default:
            try container.encode(String(describing: value))
        }
    }
}
