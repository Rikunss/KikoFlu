import Flutter
import UIKit
import AVFoundation
import AVKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var floatingLyricManager: FloatingLyricManager?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
    floatingLyricManager = FloatingLyricManager(controller: controller)

    // Register audio conversion channel (WAV → ALAC)
    registerAudioConversionChannel(controller: controller)
    
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // MARK: - WAV to ALAC Conversion (via AVFoundation)

  private func registerAudioConversionChannel(controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "com.kikoeru.flutter/audio_conversion",
      binaryMessenger: controller.binaryMessenger
    )

    channel.setMethodCallHandler { [weak self] (call, result) in
      guard call.method == "convertWav" else {
        result(FlutterMethodNotImplemented)
        return
      }

      guard let args = call.arguments as? [String: Any],
            let inputPath = args["inputPath"] as? String,
            let outputPath = args["outputPath"] as? String,
            let format = args["format"] as? String else {
        result(FlutterError(code: "INVALID_ARGS", message: "inputPath, outputPath, format required", details: nil))
        return
      }

      switch format {
      case "alac":
        self?.convertWavToAlac(inputPath: inputPath, outputPath: outputPath, result: result)
      case "aac":
        self?.convertWavToAac(inputPath: inputPath, outputPath: outputPath, result: result)
      default:
        result(FlutterError(code: "UNSUPPORTED_FORMAT", message: "Format not supported on iOS: \(format)", details: nil))
      }
    }
  }

  private func convertWavToAlac(inputPath: String, outputPath: String, result: @escaping FlutterResult) {
    DispatchQueue.global(qos: .utility).async {
      let inputURL = URL(fileURLWithPath: inputPath)
      let outputURL = URL(fileURLWithPath: outputPath)

      // Ensure output directory exists
      try? FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )

      let asset = AVAsset(url: inputURL)
      guard let reader = try? AVAssetReader(asset: asset) else {
        result(FlutterError(code: "READ_ERROR", message: "Cannot create AVAssetReader", details: nil))
        return
      }

      // Find audio track
      guard let audioTrack = asset.tracks(withMediaType: .audio).first else {
        result(FlutterError(code: "NO_AUDIO", message: "No audio track found", details: nil))
        return
      }

      // Reader settings: output PCM
      let outputSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
        AVNumberOfChannelsKey: 2,
        AVSampleRateKey: 44100
      ]
      let readerOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
      guard reader.canAdd(readerOutput) else {
        result(FlutterError(code: "READER_ERROR", message: "Cannot add reader output", details: nil))
        return
      }
      reader.add(readerOutput)

      // Writer settings: ALAC (Apple Lossless)
      let writer: AVAssetWriter
      do {
        // Remove existing file if present
        if FileManager.default.fileExists(atPath: outputPath) {
          try FileManager.default.removeItem(at: outputURL)
        }
        writer = try AVAssetWriter(outputURL: outputURL, fileType: .m4a)
      } catch {
        result(FlutterError(code: "WRITER_ERROR", message: "Cannot create AVAssetWriter", details: nil))
        return
      }

      let writerSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatAppleLossless,
        AVSampleRateKey: 44100,
        AVNumberOfChannelsKey: 2,
        AVEncoderBitDepthHintKey: 16
      ]
      let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: writerSettings)
      writerInput.expectsMediaDataInRealTime = false
      guard writer.canAdd(writerInput) else {
        result(FlutterError(code: "WRITER_ERROR", message: "Cannot add writer input", details: nil))
        return
      }
      writer.add(writerInput)

      // Start encoding
      reader.startReading()
      writer.startWriting()
      writer.startSession(atSourceTime: .zero)

      let encodingGroup = DispatchGroup()
      encodingGroup.enter()

      writerInput.requestMediaDataWhenReady(on: DispatchQueue.global(qos: .utility)) {
        while writerInput.isReadyForMoreMediaData {
          guard let sampleBuffer = readerOutput.copyNextSampleBuffer() else {
            writerInput.markAsFinished()
            encodingGroup.leave()
            return
          }
          writerInput.append(sampleBuffer)
        }
      }

      // Wait for encoding to complete
      _ = encodingGroup.wait(timeout: .now() + 300)

      writer.finishWriting {
        if reader.status == .completed && writer.status == .completed {
          // Get file sizes for logging
          let originalSize = (try? FileManager.default.attributesOfItem(atPath: inputPath))?[.size] as? Int64 ?? 0
          let convertedSize = (try? FileManager.default.attributesOfItem(atPath: outputPath))?[.size] as? Int64 ?? 0
          let savedPercent = originalSize > 0
            ? String(format: "%.1f", (1.0 - Double(convertedSize) / Double(originalSize)) * 100)
            : "?"
          print("[AudioConversion] WAV→ALAC success: \(originalSize) → \(convertedSize) bytes (-\(savedPercent)%)")

          // Delete original WAV
          try? FileManager.default.removeItem(at: inputURL)

          result("success")
        } else {
          let errorMsg = writer.error?.localizedDescription ?? reader.error?.localizedDescription ?? "Unknown error"
          print("[AudioConversion] WAV→ALAC failed: \(errorMsg)")
          result(FlutterError(code: "ENCODE_ERROR", message: errorMsg, details: nil))
        }
      }
    }
  }

  private func convertWavToAac(inputPath: String, outputPath: String, result: @escaping FlutterResult) {
    DispatchQueue.global(qos: .utility).async {
      let inputURL = URL(fileURLWithPath: inputPath)
      let outputURL = URL(fileURLWithPath: outputPath)

      try? FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )

      let asset = AVAsset(url: inputURL)
      guard let reader = try? AVAssetReader(asset: asset) else {
        result(FlutterError(code: "READ_ERROR", message: "Cannot create AVAssetReader", details: nil))
        return
      }

      guard let audioTrack = asset.tracks(withMediaType: .audio).first else {
        result(FlutterError(code: "NO_AUDIO", message: "No audio track found", details: nil))
        return
      }

      // Reader: output PCM
      let outputSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
        AVNumberOfChannelsKey: 2,
        AVSampleRateKey: 44100
      ]
      let readerOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
      guard reader.canAdd(readerOutput) else {
        result(FlutterError(code: "READER_ERROR", message: "Cannot add reader output", details: nil))
        return
      }
      reader.add(readerOutput)

      // Writer: AAC (256 kbps)
      let writer: AVAssetWriter
      do {
        if FileManager.default.fileExists(atPath: outputPath) {
          try FileManager.default.removeItem(at: outputURL)
        }
        writer = try AVAssetWriter(outputURL: outputURL, fileType: .m4a)
      } catch {
        result(FlutterError(code: "WRITER_ERROR", message: "Cannot create AVAssetWriter", details: nil))
        return
      }

      let writerSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: 44100,
        AVNumberOfChannelsKey: 2,
        AVEncoderBitRateKey: 256000
      ]
      let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: writerSettings)
      writerInput.expectsMediaDataInRealTime = false
      guard writer.canAdd(writerInput) else {
        result(FlutterError(code: "WRITER_ERROR", message: "Cannot add writer input", details: nil))
        return
      }
      writer.add(writerInput)

      reader.startReading()
      writer.startWriting()
      writer.startSession(atSourceTime: .zero)

      let encodingGroup = DispatchGroup()
      encodingGroup.enter()

      writerInput.requestMediaDataWhenReady(on: DispatchQueue.global(qos: .utility)) {
        while writerInput.isReadyForMoreMediaData {
          guard let sampleBuffer = readerOutput.copyNextSampleBuffer() else {
            writerInput.markAsFinished()
            encodingGroup.leave()
            return
          }
          writerInput.append(sampleBuffer)
        }
      }

      _ = encodingGroup.wait(timeout: .now() + 300)

      writer.finishWriting {
        if reader.status == .completed && writer.status == .completed {
          print("[AudioConversion] WAV->AAC success")
          try? FileManager.default.removeItem(at: inputURL)
          result("success")
        } else {
          let errorMsg = writer.error?.localizedDescription ?? reader.error?.localizedDescription ?? "Unknown error"
          print("[AudioConversion] WAV->AAC failed: \(errorMsg)")
          result(FlutterError(code: "ENCODE_ERROR", message: errorMsg, details: nil))
        }
      }
    }
  }
}

// MARK: - Network Speed Monitor
class NetworkSpeedMonitor {
    private var previousBytesIn: UInt64 = 0
    private var previousBytesOut: UInt64 = 0
    private var timer: Timer?
    var onSpeedUpdate: ((String) -> Void)?
    
    func start() {
        // Initialize with current values
        let (bytesIn, bytesOut) = getNetworkBytes()
        previousBytesIn = bytesIn
        previousBytesOut = bytesOut
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.update()
        }
    }
    
    func stop() {
        timer?.invalidate()
        timer = nil
    }
    
    private func update() {
        let (bytesIn, bytesOut) = getNetworkBytes()
        let downloadSpeed = bytesIn >= previousBytesIn ? bytesIn - previousBytesIn : 0
        let uploadSpeed = bytesOut >= previousBytesOut ? bytesOut - previousBytesOut : 0
        previousBytesIn = bytesIn
        previousBytesOut = bytesOut
        
        let downStr = formatSpeed(downloadSpeed)
        let upStr = formatSpeed(uploadSpeed)
        onSpeedUpdate?("↓\(downStr) ↑\(upStr)")
    }
    
    private func getNetworkBytes() -> (UInt64, UInt64) {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return (0, 0)
        }
        defer { freeifaddrs(ifaddr) }
        
        var bytesIn: UInt64 = 0
        var bytesOut: UInt64 = 0
        
        var ptr = firstAddr
        while true {
            let name = String(cString: ptr.pointee.ifa_name)
            // Include Wi-Fi (en0) and cellular (pdp_ip0) interfaces
            if name.hasPrefix("en") || name.hasPrefix("pdp_ip") {
                if let data = ptr.pointee.ifa_data {
                    let networkData = data.assumingMemoryBound(to: if_data.self)
                    bytesIn += UInt64(networkData.pointee.ifi_ibytes)
                    bytesOut += UInt64(networkData.pointee.ifi_obytes)
                }
            }
            if let next = ptr.pointee.ifa_next {
                ptr = next
            } else {
                break
            }
        }
        
        return (bytesIn, bytesOut)
    }
    
    private func formatSpeed(_ bytesPerSecond: UInt64) -> String {
        let kb = Double(bytesPerSecond) / 1024.0
        if kb < 1024 {
            return String(format: "%.0f KB/s", kb)
        }
        let mb = kb / 1024.0
        return String(format: "%.1f MB/s", mb)
    }
}

// MARK: - FPS Monitor
// Uses Apple's recommended approach: read the display's current frame interval
// via (targetTimestamp - timestamp) each CADisplayLink callback.
// This reports the refresh rate the system is actually driving — correctly
// shows 120Hz on ProMotion when the display is running fast (e.g. during
// scrolling/animations) and 60Hz when idle.
// Note: CADisplayLink's presence on the RunLoop keeps ProMotion at ≥60Hz;
// this is an inherent iOS limitation shared by all CADisplayLink-based monitors.
class FPSMonitor {
    private var displayLink: CADisplayLink?
    private var lastReportTime: CFTimeInterval = 0
    private var fpsReadings: [Double] = []

    var onFPSUpdate: ((Int) -> Void)?

    func start() {
        stop()
        displayLink = CADisplayLink(target: self, selector: #selector(tick))
        // Request the full range so we receive callbacks at whatever rate the
        // system is currently driving (up to 120Hz on ProMotion devices).
        if #available(iOS 15.0, *) {
            let maxFPS = Float(UIScreen.main.maximumFramesPerSecond)
            displayLink?.preferredFrameRateRange = CAFrameRateRange(
                minimum: 1, maximum: maxFPS, preferred: 0)
        }
        displayLink?.add(to: .main, forMode: .common)
        lastReportTime = 0
        fpsReadings.removeAll()
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        fpsReadings.removeAll()
        lastReportTime = 0
    }

    @objc private func tick(link: CADisplayLink) {
        // Apple-recommended way to read the current display refresh rate.
        let frameDuration = link.targetTimestamp - link.timestamp
        if frameDuration > 0 {
            fpsReadings.append(1.0 / frameDuration)
        }

        let now = CACurrentMediaTime()
        if lastReportTime == 0 {
            lastReportTime = now
            return
        }

        // Report averaged FPS every ~1 second
        if now - lastReportTime >= 1.0 {
            if !fpsReadings.isEmpty {
                let avg = fpsReadings.reduce(0, +) / Double(fpsReadings.count)
                onFPSUpdate?(Int(round(avg)))
                fpsReadings.removeAll()
            }
            lastReportTime = now
        }
    }
}

class FloatingLyricManager: NSObject, AVPictureInPictureControllerDelegate {
    private var pipController: AVPictureInPictureController?
    private var playerLayer: AVPlayerLayer?
    private var player: AVPlayer?
    private var lyricView: UILabel?
    private var fpsLabel: UILabel?
    private var networkSpeedLabel: UILabel?
    private var channel: FlutterMethodChannel
    
    private var fpsMonitor = FPSMonitor()
    private var networkSpeedMonitor = NetworkSpeedMonitor()
    private var showFPS: Bool = false
    private var showNetworkSpeed: Bool = false
    
    // Cached subtitle style for info labels (follows lyric style except font size)
    private var infoTextColor: UIColor = .white
    private var infoCornerRadius: CGFloat = 4
    
    // Base64 of a 1-second black MP4 video
    private let dummyVideoBase64 = "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"

    init(controller: FlutterViewController) {
        channel = FlutterMethodChannel(name: "com.kikoeru.flutter/floating_lyric", binaryMessenger: controller.binaryMessenger)
        super.init()
        
        channel.setMethodCallHandler { [weak self] (call, result) in
            self?.handleMethodCall(call, result: result)
        }
        
        setupAudioSession()
        setupPlayer(in: controller.view)
    }
    
    private func setupAudioSession() {
        do {
            // Use .playback category with .mixWithOthers option to allow background audio from other apps (or our own main player)
            // However, for PiP to work, we generally need to be the "active" audio session or at least compatible.
            // Since we have a main audio player in Flutter (just_audio), we need to be careful not to interrupt it.
            // The main player likely sets the category to .playback.
            // We should try to use the existing session configuration or ensure we don't conflict.
            
            // Actually, for PiP to work, the AVPlayerLayer must be attached to a player that is "playing".
            // If we set .mixWithOthers, it might help with not pausing the main audio.
            try AVAudioSession.sharedInstance().setCategory(.playback, options: .mixWithOthers)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Audio session setup failed: \(error)")
        }
    }
    
    private func setupPlayer(in view: UIView) {
        guard let data = Data(base64Encoded: dummyVideoBase64) else { return }
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("pip_video.mp4")
        try? data.write(to: fileURL)
        
        let playerItem = AVPlayerItem(url: fileURL)
        player = AVPlayer(playerItem: playerItem)
        player?.isMuted = true
        player?.allowsExternalPlayback = true
        // Important: prevent this player from pausing other audio
        if #available(iOS 10.0, *) {
            player?.automaticallyWaitsToMinimizeStalling = false
        }
        // Loop the video
        player?.actionAtItemEnd = .none
        NotificationCenter.default.addObserver(self,
                                             selector: #selector(playerItemDidReachEnd(notification:)),
                                             name: .AVPlayerItemDidPlayToEndTime,
                                             object: player?.currentItem)
        
        playerLayer = AVPlayerLayer(player: player)
        playerLayer?.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        playerLayer?.opacity = 0.01
        view.layer.addSublayer(playerLayer!)
        
        if AVPictureInPictureController.isPictureInPictureSupported() {
            pipController = AVPictureInPictureController(playerLayer: playerLayer!)
            pipController?.delegate = self
            // Hide controls
            pipController?.setValue(1, forKey: "controlsStyle")
        }
    }
    
    @objc func playerItemDidReachEnd(notification: Notification) {
        if let playerItem = notification.object as? AVPlayerItem {
            playerItem.seek(to: CMTime.zero, completionHandler: nil)
        }
    }
    
    private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "show":
            let args = call.arguments as? [String: Any]
            let text = args?["text"] as? String ?? "Lyrics"
            show(text: text, args: args)
            result(true)
        case "hide":
            hide()
            result(true)
        case "updateText":
            let args = call.arguments as? [String: Any]
            let text = args?["text"] as? String ?? ""
            updateText(text)
            result(true)
        case "updateStyle":
            let args = call.arguments as? [String: Any]
            updateStyle(args: args)
            result(true)
        case "setFPSEnabled":
            let args = call.arguments as? [String: Any]
            let enabled = args?["enabled"] as? Bool ?? false
            setFPSEnabled(enabled)
            result(true)
        case "setNetworkSpeedEnabled":
            let args = call.arguments as? [String: Any]
            let enabled = args?["enabled"] as? Bool ?? false
            setNetworkSpeedEnabled(enabled)
            result(true)
        case "hasPermission":
            result(true)
        case "requestPermission":
            result(true)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func show(text: String, args: [String: Any]?) {
        if pipController?.isPictureInPictureActive == true {
            updateText(text)
            updateStyle(args: args)
            return
        }
        
        player?.play()
        pipController?.startPictureInPicture()
        prepareLyricView(text: text)
        updateStyle(args: args)
    }
    
    private func hide() {
        pipController?.stopPictureInPicture()
        player?.pause()
        stopMonitors()
    }
    
    private func setFPSEnabled(_ enabled: Bool) {
        showFPS = enabled
        if enabled {
            fpsMonitor.onFPSUpdate = { [weak self] fps in
                self?.updateFPSLabel(fps)
            }
            if pipController?.isPictureInPictureActive == true {
                fpsMonitor.start()
                ensureFPSLabel()
            }
        } else {
            fpsMonitor.stop()
            DispatchQueue.main.async {
                self.fpsLabel?.removeFromSuperview()
                self.fpsLabel = nil
            }
        }
    }
    
    private func setNetworkSpeedEnabled(_ enabled: Bool) {
        showNetworkSpeed = enabled
        if enabled {
            networkSpeedMonitor.onSpeedUpdate = { [weak self] speed in
                self?.updateNetworkSpeedLabel(speed)
            }
            if pipController?.isPictureInPictureActive == true {
                networkSpeedMonitor.start()
                ensureNetworkSpeedLabel()
            }
        } else {
            networkSpeedMonitor.stop()
            DispatchQueue.main.async {
                self.networkSpeedLabel?.removeFromSuperview()
                self.networkSpeedLabel = nil
            }
        }
    }
    
    private func stopMonitors() {
        fpsMonitor.stop()
        networkSpeedMonitor.stop()
    }
    
    private func startMonitorsIfNeeded() {
        if showFPS {
            fpsMonitor.onFPSUpdate = { [weak self] fps in
                self?.updateFPSLabel(fps)
            }
            fpsMonitor.start()
        }
        if showNetworkSpeed {
            networkSpeedMonitor.onSpeedUpdate = { [weak self] speed in
                self?.updateNetworkSpeedLabel(speed)
            }
            networkSpeedMonitor.start()
        }
    }
    
    private func ensureFPSLabel() {
        DispatchQueue.main.async {
            guard self.showFPS else { return }
            if self.fpsLabel == nil {
                let label = UILabel()
                label.textColor = self.infoTextColor.withAlphaComponent(0.8)
                label.backgroundColor = .clear
                label.font = UIFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
                label.textAlignment = .center
                label.layer.cornerRadius = self.infoCornerRadius
                label.clipsToBounds = true
                self.fpsLabel = label
            }
            if let window = UIApplication.shared.windows.first, self.fpsLabel?.superview == nil {
                if let label = self.fpsLabel {
                    window.addSubview(label)
                    window.bringSubviewToFront(label)
                    self.layoutInfoLabels(in: window)
                }
            }
        }
    }
    
    private func ensureNetworkSpeedLabel() {
        DispatchQueue.main.async {
            guard self.showNetworkSpeed else { return }
            if self.networkSpeedLabel == nil {
                let label = UILabel()
                label.textColor = self.infoTextColor.withAlphaComponent(0.8)
                label.backgroundColor = .clear
                label.font = UIFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
                label.textAlignment = .center
                label.layer.cornerRadius = self.infoCornerRadius
                label.clipsToBounds = true
                self.networkSpeedLabel = label
            }
            if let window = UIApplication.shared.windows.first, self.networkSpeedLabel?.superview == nil {
                if let label = self.networkSpeedLabel {
                    window.addSubview(label)
                    window.bringSubviewToFront(label)
                    self.layoutInfoLabels(in: window)
                }
            }
        }
    }
    
    private func layoutInfoLabels(in window: UIWindow) {
        let margin: CGFloat = 4
        let height: CGFloat = 16
        if let label = fpsLabel {
            let width: CGFloat = 50
            label.frame = CGRect(
                x: margin,
                y: window.bounds.height - height - margin,
                width: width,
                height: height
            )
        }
        if let label = networkSpeedLabel {
            let width: CGFloat = 140
            label.frame = CGRect(
                x: window.bounds.width - width - margin,
                y: window.bounds.height - height - margin,
                width: width,
                height: height
            )
        }
    }
    
    private func updateFPSLabel(_ fps: Int) {
        DispatchQueue.main.async {
            self.fpsLabel?.text = "\(fps) FPS"
        }
    }
    
    private func updateNetworkSpeedLabel(_ speed: String) {
        DispatchQueue.main.async {
            self.networkSpeedLabel?.text = speed
        }
    }
    
    private func updateText(_ text: String) {
        DispatchQueue.main.async {
            self.lyricView?.text = text
            self.lyricView?.setNeedsLayout()
        }
    }
    
    private func updateStyle(args: [String: Any]?) {
        guard let args = args else { return }
        
        DispatchQueue.main.async {
            guard let view = self.lyricView else { return }
            
            if let fontSize = args["fontSize"] as? Double {
                view.font = UIFont.systemFont(ofSize: CGFloat(fontSize), weight: .medium)
            }
            
            if let textColorInt = args["textColor"] as? Int {
                let color = self.colorFromInt(textColorInt)
                view.textColor = color
                self.infoTextColor = color
            }
            
            if let backgroundColorInt = args["backgroundColor"] as? Int {
                view.backgroundColor = self.colorFromInt(backgroundColorInt)
            }
            
            if let cornerRadius = args["cornerRadius"] as? Double {
                view.layer.cornerRadius = CGFloat(cornerRadius)
                self.infoCornerRadius = CGFloat(cornerRadius)
            }
            
            // Sync style to info labels (text color + corner radius, no background)
            self.applyStyleToInfoLabels()
        }
    }
    
    private func colorFromInt(_ argb: Int) -> UIColor {
        let a = CGFloat((argb >> 24) & 0xFF) / 255.0
        let r = CGFloat((argb >> 16) & 0xFF) / 255.0
        let g = CGFloat((argb >> 8) & 0xFF) / 255.0
        let b = CGFloat(argb & 0xFF) / 255.0
        return UIColor(red: r, green: g, blue: b, alpha: a)
    }
    
    private func applyStyleToInfoLabels() {
        for label in [fpsLabel, networkSpeedLabel] {
            guard let label = label else { continue }
            label.textColor = infoTextColor.withAlphaComponent(0.8)
            label.layer.cornerRadius = infoCornerRadius
        }
    }
    
    private func prepareLyricView(text: String) {
        if lyricView == nil {
            lyricView = UILabel()
            lyricView?.textColor = .white
            lyricView?.backgroundColor = UIColor(white: 0.0, alpha: 0.3) // Default style
            lyricView?.font = UIFont.systemFont(ofSize: 20, weight: .medium)
            lyricView?.textAlignment = .center
            lyricView?.numberOfLines = 0
            lyricView?.layer.cornerRadius = 8
            lyricView?.clipsToBounds = true
            // Remove shadow
            lyricView?.shadowColor = .clear
            lyricView?.shadowOffset = .zero
        }
        lyricView?.text = text
    }
    
    // MARK: - AVPictureInPictureControllerDelegate
    
    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        // Add view to the PiP window
        // Note: This relies on the fact that the PiP window becomes available in windows list
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let window = UIApplication.shared.windows.first {
                if let view = self.lyricView {
                    view.frame = window.bounds
                    view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                    window.addSubview(view)
                    window.bringSubviewToFront(view)
                }
                // Add info labels and start monitors
                self.startMonitorsIfNeeded()
                if self.showFPS { self.ensureFPSLabel() }
                if self.showNetworkSpeed { self.ensureNetworkSpeedLabel() }
            }
        }
    }
    
    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        lyricView?.removeFromSuperview()
        fpsLabel?.removeFromSuperview()
        networkSpeedLabel?.removeFromSuperview()
        stopMonitors()
        player?.pause()
        channel.invokeMethod("onClose", arguments: nil)
    }
    
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        print("PiP failed: \(error)")
    }
}
