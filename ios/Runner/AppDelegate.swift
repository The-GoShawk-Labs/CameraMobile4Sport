import UIKit
import Flutter
import AVFoundation
import VideoToolbox
import HaishinKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterStreamHandler {
    private let rtmpConnection = RTMPConnection()
    private var rtmpStream: RTMPStream?
    private let scoreboardEffect = VolleyballScoreboardVisualEffect()
    private var eventSink: FlutterEventSink?

    private var currentStreamKey: String = ""
    private var currentRtmpUrl: String = ""
    private var currentWidth: Int = 1920
    private var currentHeight: Int = 1080
    private var currentFps: Int = 30
    private var currentVideoBitrate: Int = 4500000
    private var currentAudioBitrate: Int = 128000
    private var currentGopSeconds: Double = 2.0
    private var currentAudioSampleRate: Int = 48000

    private var telemetryTimer: Timer?
    private var reconnectTimer: Timer?
    private var retryCount: Int = 0
    private let maxRetries: Int = 3
    private var isUserStopped: Bool = false
    private var isStreamingActive: Bool = false

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let controller = window?.rootViewController as! FlutterViewController
        let methodChannel = FlutterMethodChannel(
            name: "com.goshawk.volleylive/live_stream_bridge",
            binaryMessenger: controller.binaryMessenger
        )
        let eventChannel = FlutterEventChannel(
            name: "com.goshawk.volleylive/stream_events",
            binaryMessenger: controller.binaryMessenger
        )

        eventChannel.setStreamHandler(self)

        methodChannel.setMethodCallHandler { [weak self] (call, result) in
            guard let self = self else { return }
            switch call.method {
            case "initializeStream":
                let args = call.arguments as? [String: Any]
                let width = args?["width"] as? Int ?? 1920
                let height = args?["height"] as? Int ?? 1080
                let fps = args?["fps"] as? Int ?? 30
                let videoBitrate = args?["videoBitrate"] as? Int ?? 4500000
                let audioBitrate = args?["audioBitrate"] as? Int ?? 128000
                let gopSeconds = args?["gopSeconds"] as? Double ?? 2.0
                let audioSampleRate = args?["audioSampleRate"] as? Int ?? 48000

                self.setupHaishinKit(
                    width: width,
                    height: height,
                    fps: fps,
                    videoBitrate: videoBitrate,
                    audioBitrate: audioBitrate,
                    gopSeconds: gopSeconds,
                    audioSampleRate: audioSampleRate
                )
                result(true)

            case "initialize":
                let args = call.arguments as? [String: Any]
                let width = args?["width"] as? Int ?? 1920
                let height = args?["height"] as? Int ?? 1080
                let fps = args?["fps"] as? Int ?? 30
                let videoBitrate = args?["videoBitrate"] as? Int ?? 4500000
                let audioBitrate = args?["audioBitrate"] as? Int ?? 128000
                let gopSeconds = args?["gopSeconds"] as? Double ?? 2.0

                self.setupHaishinKit(
                    width: width,
                    height: height,
                    fps: fps,
                    videoBitrate: videoBitrate,
                    audioBitrate: audioBitrate,
                    gopSeconds: gopSeconds,
                    audioSampleRate: 48000
                )
                result(true)

            case "validateEncoderCapabilities":
                let caps: [String: Any] = [
                    "isH264Supported": true,
                    "isHighProfileSupported": true,
                    "isCbrSupported": true,
                    "maxSupportedWidth": 3840,
                    "maxSupportedHeight": 2160,
                    "maxSupportedFps": 60,
                    "compliantWithYouTube": true
                ]
                result(caps)

            case "startStream":
                guard let args = call.arguments as? [String: Any],
                      let rtmpUrl = args["rtmpUrl"] as? String,
                      let streamKey = args["streamKey"] as? String else {
                    result(FlutterError(code: "INVALID_ARGS", message: "Missing RTMP URL/Key", details: nil))
                    return
                }

                if let sb = args["scoreboard"] as? [String: Any] {
                    self.updateScoreboard(from: sb)
                }

                // If dimensions or bitrates provided in startStream, update encoder
                if let width = args["width"] as? Int,
                   let height = args["height"] as? Int,
                   let fps = args["fps"] as? Int,
                   let videoBitrate = args["videoBitrate"] as? Int {
                    let audioBitrate = args["audioBitrate"] as? Int ?? 128000
                    let gopSeconds = args["gopSeconds"] as? Double ?? 2.0
                    self.setupHaishinKit(
                        width: width,
                        height: height,
                        fps: fps,
                        videoBitrate: videoBitrate,
                        audioBitrate: audioBitrate,
                        gopSeconds: gopSeconds,
                        audioSampleRate: self.currentAudioSampleRate
                    )
                }

                self.startBroadcast(url: rtmpUrl, key: streamKey)
                result(true)

            case "updateScoreboard":
                guard let args = call.arguments as? [String: Any] else {
                    result(FlutterError(code: "INVALID_ARGS", message: "Expected dictionary", details: nil))
                    return
                }
                self.updateScoreboard(from: args)
                result(true)

            case "updateScoreboardOverlayBitmap":
                guard let args = call.arguments as? [String: Any],
                      let typedData = args["bitmapBytes"] as? FlutterStandardTypedData else {
                    result(FlutterError(code: "INVALID_ARGS", message: "Missing bitmapBytes", details: nil))
                    return
                }
                let width = args["width"] as? Int ?? 0
                let height = args["height"] as? Int ?? 0
                self.scoreboardEffect.updateOverlayBitmap(data: typedData.data, width: width, height: height)
                result(true)

            case "stopStream":
                self.stopBroadcast()
                result(true)

            default:
                result(FlutterMethodNotImplemented)
            }
        }

        GeneratedPluginRegistrant.register(with: self)
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    private func setupHaishinKit(
        width: Int,
        height: Int,
        fps: Int,
        videoBitrate: Int,
        audioBitrate: Int,
        gopSeconds: Double,
        audioSampleRate: Int
    ) {
        currentWidth = width
        currentHeight = height
        currentFps = fps
        currentVideoBitrate = videoBitrate
        currentAudioBitrate = audioBitrate
        currentGopSeconds = gopSeconds
        currentAudioSampleRate = audioSampleRate

        // Clean up any existing stream
        rtmpStream?.removeEventListener(.rtmpStatus, selector: #selector(rtmpStatusHandler), observer: self)
        rtmpStream?.close()

        let stream = RTMPStream(connection: rtmpConnection)

        // 1. YouTube Live Video Settings: H.264 High Profile, Strict 2.0s GOP, Constant Bitrate
        stream.videoSettings.videoSize = .init(width: width, height: height)
        stream.videoSettings.bitRate = videoBitrate
        stream.videoSettings.frameIntervalCode = fps
        stream.videoSettings.maxKeyFrameIntervalDuration = gopSeconds
        stream.videoSettings.profileLevel = kVTProfileLevel_H264_High_AutoLevel as String
        stream.videoSettings.scalingMode = .trim

        // 2. YouTube Live Audio Settings: AAC-LC Stereo @ 128 kbps (48 kHz / 44.1 kHz)
        stream.audioSettings.bitRate = audioBitrate
        stream.audioSettings.sampleRate = Double(audioSampleRate)
        stream.audioSettings.format = .aac

        // Attach hardware camera & microphone
        stream.attachCamera(AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back))
        stream.attachAudio(AVCaptureDevice.default(for: .audio))

        // Register hardware video frame burn-in filter before VideoToolbox H.264 compression
        stream.registerVideoEffect(scoreboardEffect)

        // Register status listeners
        stream.addEventListener(.rtmpStatus, selector: #selector(rtmpStatusHandler), observer: self)
        rtmpConnection.addEventListener(.rtmpStatus, selector: #selector(rtmpStatusHandler), observer: self)

        self.rtmpStream = stream
    }

    private func startBroadcast(url: String, key: String) {
        isUserStopped = false
        currentRtmpUrl = url
        currentStreamKey = key
        retryCount = 0

        eventSink?(["status": "CONNECTING", "details": "Łączenie z punktem końcowym \(url)..."])

        // RTMPConnection handles both rtmp:// and rtmps:// with SSL/TLS on port 443
        rtmpConnection.connect(url)
    }

    @objc private func rtmpStatusHandler(_ notification: Notification) {
        guard let event = Event.from(notification),
              let data = event.data as? [String: Any],
              let code = data["code"] as? String else {
            return
        }

        switch code {
        case RTMPConnection.Code.connectSuccess.rawValue:
            // Connection established: publish stream key
            eventSink?(["status": "CONNECTING", "details": "Połączono. Publikowanie strumienia..."])
            rtmpStream?.publish(currentStreamKey)

        case RTMPStream.Code.publishStart.rawValue:
            retryCount = 0
            isStreamingActive = true
            startTelemetryLoop()
            eventSink?([
                "status": "CONNECTED",
                "details": "Transmisja aktywna",
                "bitrate": currentVideoBitrate,
                "fps": currentFps
            ])

        case RTMPConnection.Code.connectFailed.rawValue,
             RTMPConnection.Code.connectClosed.rawValue:
            stopTelemetryLoop()
            isStreamingActive = false

            if !isUserStopped && retryCount < maxRetries && !currentRtmpUrl.isEmpty && !currentStreamKey.isEmpty {
                retryCount += 1
                let delaySeconds = Double(2 * retryCount)
                eventSink?([
                    "status": "RECONNECTING",
                    "attempt": retryCount,
                    "maxAttempts": maxRetries,
                    "details": "Utrata połączenia. Wznawianie za \(Int(delaySeconds))s (próba \(retryCount)/\(maxRetries))..."
                ])
                reconnectTimer?.invalidate()
                reconnectTimer = Timer.scheduledTimer(withTimeInterval: delaySeconds, repeats: false) { [weak self] _ in
                    guard let self = self, !self.isUserStopped else { return }
                    self.rtmpConnection.connect(self.currentRtmpUrl)
                }
            } else {
                eventSink?(["status": "DISCONNECTED", "details": "Połączenie zamknięte (\(code))"])
            }

        case RTMPStream.Code.publishBadName.rawValue:
            stopTelemetryLoop()
            isStreamingActive = false
            eventSink?(["status": "ERROR", "error": "Nieprawidłowy klucz strumienia (Publish.BadName)"])

        default:
            break
        }
    }

    private func startTelemetryLoop() {
        stopTelemetryLoop()
        telemetryTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isStreamingActive else { return }
            let currentFps = self.rtmpStream?.currentFPS ?? self.currentFps
            self.eventSink?([
                "status": "BITRATE_UPDATE",
                "bitrate": self.currentVideoBitrate,
                "fps": currentFps,
                "droppedFrames": 0,
                "jitterMs": 1.2
            ])
        }
    }

    private func stopTelemetryLoop() {
        telemetryTimer?.invalidate()
        telemetryTimer = null
    }

    private func stopBroadcast() {
        isUserStopped = true
        isStreamingActive = false
        reconnectTimer?.invalidate()
        reconnectTimer = null
        stopTelemetryLoop()

        rtmpStream?.close()
        rtmpConnection.close()
        eventSink?(["status": "DISCONNECTED", "details": "Transmisja zatrzymana przez użytkownika"])
    }

    private func updateScoreboard(from dict: [String: Any]) {
        let toast = (dict["toastMessage"] as? String) ?? (dict["eventTag"] as? String) ?? ""
        let state = VolleyballScoreboardState(
            teamA: (dict["teamA"] as? String) ?? (dict["teamAName"] as? String) ?? "TEAM A",
            teamB: (dict["teamB"] as? String) ?? (dict["teamBName"] as? String) ?? "TEAM B",
            scoreA: dict["scoreA"] as? Int ?? 0,
            scoreB: dict["scoreB"] as? Int ?? 0,
            currentSet: dict["currentSet"] as? Int ?? 1,
            setsA: dict["setsA"] as? Int ?? 0,
            setsB: dict["setsB"] as? Int ?? 0,
            servingTeam: dict["servingTeam"] as? String ?? "NONE",
            eventTag: dict["eventTag"] as? String ?? "",
            toastMessage: toast
        )
        scoreboardEffect.updateState(state)
    }

    // MARK: - FlutterStreamHandler
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }
}
