import UIKit
import Flutter
import AVFoundation
import HaishinKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterStreamHandler {
    private let rtmpConnection = RTMPConnection()
    private var rtmpStream: RTMPStream?
    private let scoreboardEffect = VolleyballScoreboardVisualEffect()
    private var eventSink: FlutterEventSink?

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
            case "initialize":
                let args = call.arguments as? [String: Any]
                let width = args?["width"] as? Int ?? 1920
                let height = args?["height"] as? Int ?? 1080
                let fps = args?["fps"] as? Int ?? 30
                let videoBitrate = args?["videoBitrate"] as? Int ?? 4500000

                self.setupHaishinKit(width: width, height: height, fps: fps, videoBitrate: videoBitrate)
                result(true)

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
                self.rtmpStream?.close()
                self.rtmpConnection.close()
                self.eventSink?(["status": "STOPPED"])
                result(true)

            default:
                result(FlutterMethodNotImplemented)
            }
        }

        GeneratedPluginRegistrant.register(with: self)
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    private func setupHaishinKit(width: Int, height: Int, fps: Int, videoBitrate: Int) {
        let stream = RTMPStream(connection: rtmpConnection)
        stream.videoSettings.videoSize = .init(width: width, height: height)
        stream.videoSettings.bitRate = videoBitrate
        stream.videoSettings.frameIntervalCode = fps
        stream.attachCamera(AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back))
        stream.attachAudio(AVCaptureDevice.default(for: .audio))

        // Register hardware video frame burn-in filter before VideoToolbox H.264 compression
        stream.registerVideoEffect(scoreboardEffect)

        self.rtmpStream = stream
    }

    private func startBroadcast(url: String, key: String) {
        self.eventSink?(["status": "CONNECTING"])
        rtmpConnection.connect(url)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.rtmpStream?.publish(key)
            self?.eventSink?(["status": "STREAMING"])
        }
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
