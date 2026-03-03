import AVFoundation
import Flutter
import Photos
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, FlutterStreamHandler {
  private let methodChannelName = "paint_timelapse/video_export"
  private let progressChannelName = "paint_timelapse/video_export_progress"
  private let exportMethod = "exportMp4ToGallery"
  private var progressSink: FlutterEventSink?
  private var channelsConfigured = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    configureChannels(binaryMessenger: engineBridge.applicationRegistrar.messenger())
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    progressSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    progressSink = nil
    return nil
  }

  private func configureChannels(binaryMessenger: FlutterBinaryMessenger) {
    if channelsConfigured {
      return
    }
    channelsConfigured = true

    let progressChannel = FlutterEventChannel(
      name: progressChannelName,
      binaryMessenger: binaryMessenger
    )
    progressChannel.setStreamHandler(self)

    let methodChannel = FlutterMethodChannel(
      name: methodChannelName,
      binaryMessenger: binaryMessenger
    )
    methodChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      guard call.method == self.exportMethod else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard
        let args = call.arguments as? [String: Any],
        let exportId = args["exportId"] as? String,
        let fileName = args["fileName"] as? String,
        let rawPath = args["rawPath"] as? String,
        let frameCount = args["frameCount"] as? Int,
        let width = args["width"] as? Int,
        let height = args["height"] as? Int,
        let frameDurationMs = args["frameDurationMs"] as? Int,
        !exportId.isEmpty,
        !fileName.isEmpty,
        !rawPath.isEmpty,
        frameCount > 0,
        width > 0,
        height > 0,
        frameDurationMs > 0
      else {
        result(
          FlutterError(
            code: "invalid_args",
            message: "Missing or invalid export arguments",
            details: nil
          )
        )
        return
      }

      self.exportVideo(
        exportId: exportId,
        fileName: fileName,
        rawPath: rawPath,
        frameCount: frameCount,
        width: width,
        height: height,
        frameDurationMs: frameDurationMs,
        flutterResult: result
      )
    }
  }

  private func exportVideo(
    exportId: String,
    fileName: String,
    rawPath: String,
    frameCount: Int,
    width: Int,
    height: Int,
    frameDurationMs: Int,
    flutterResult: @escaping FlutterResult
  ) {
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        let rawURL = URL(fileURLWithPath: rawPath)
        if !FileManager.default.fileExists(atPath: rawURL.path) {
          throw NSError(
            domain: "TimelapseExport",
            code: 10,
            userInfo: [NSLocalizedDescriptionKey: "Raw frame file not found"]
          )
        }

        let outputURL = FileManager.default.temporaryDirectory
          .appendingPathComponent("\(exportId).mp4")
        if FileManager.default.fileExists(atPath: outputURL.path) {
          try? FileManager.default.removeItem(at: outputURL)
        }

        try self.encodeMp4FromRawFrames(
          rawURL: rawURL,
          outputURL: outputURL,
          width: width,
          height: height,
          frameCount: frameCount,
          frameDurationMs: frameDurationMs,
          exportId: exportId
        )

        self.saveVideoToPhotoLibrary(
          exportId: exportId,
          fileName: fileName,
          outputURL: outputURL
        ) { saveResult in
          DispatchQueue.main.async {
            switch saveResult {
            case .success(let location):
              flutterResult(location)
            case .failure(let error):
              flutterResult(
                FlutterError(
                  code: "export_failed",
                  message: error.localizedDescription,
                  details: nil
                )
              )
            }
          }
        }
      } catch {
        DispatchQueue.main.async {
          flutterResult(
            FlutterError(
              code: "export_failed",
              message: error.localizedDescription,
              details: nil
            )
          )
        }
      }
    }
  }

  private func encodeMp4FromRawFrames(
    rawURL: URL,
    outputURL: URL,
    width: Int,
    height: Int,
    frameCount: Int,
    frameDurationMs: Int,
    exportId: String
  ) throws {
    let frameByteCount = width * height * 4
    let minBytes = Int64(frameByteCount) * Int64(frameCount)
    let fileSize = (try FileManager.default.attributesOfItem(atPath: rawURL.path)[.size] as? NSNumber)?
      .int64Value ?? 0
    if fileSize < minBytes {
      throw NSError(
        domain: "TimelapseExport",
        code: 11,
        userInfo: [NSLocalizedDescriptionKey: "Raw frame file is incomplete"]
      )
    }

    let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
    let bitRate = max(1_000_000, width * height * 6)
    let outputSettings: [String: Any] = [
      AVVideoCodecKey: AVVideoCodecType.h264,
      AVVideoWidthKey: width,
      AVVideoHeightKey: height,
      AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: bitRate,
        AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
      ],
    ]

    let input = AVAssetWriterInput(mediaType: .video, outputSettings: outputSettings)
    input.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
      assetWriterInput: input,
      sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height,
        kCVPixelBufferCGImageCompatibilityKey as String: true,
        kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
      ]
    )

    guard writer.canAdd(input) else {
      throw NSError(
        domain: "TimelapseExport",
        code: 12,
        userInfo: [NSLocalizedDescriptionKey: "Could not configure video writer input"]
      )
    }
    writer.add(input)

    if !writer.startWriting() {
      throw writer.error ?? NSError(
        domain: "TimelapseExport",
        code: 13,
        userInfo: [NSLocalizedDescriptionKey: "Could not start writing MP4"]
      )
    }
    writer.startSession(atSourceTime: .zero)

    let handle = try FileHandle(forReadingFrom: rawURL)
    defer {
      try? handle.close()
    }

    for frameIndex in 0..<frameCount {
      autoreleasepool {
        while !input.isReadyForMoreMediaData {
          Thread.sleep(forTimeInterval: 0.002)
        }
      }

      let data = try handle.read(upToCount: frameByteCount) ?? Data()
      if data.count != frameByteCount {
        throw NSError(
          domain: "TimelapseExport",
          code: 14,
          userInfo: [NSLocalizedDescriptionKey: "Failed to read frame bytes"]
        )
      }

      let pixelBuffer = try makePixelBufferFromRgbaData(data, width: width, height: height)
      let frameTime = CMTime(value: CMTimeValue(frameIndex * frameDurationMs), timescale: 1000)
      if !adaptor.append(pixelBuffer, withPresentationTime: frameTime) {
        throw writer.error ?? NSError(
          domain: "TimelapseExport",
          code: 15,
          userInfo: [NSLocalizedDescriptionKey: "Failed to append frame to MP4"]
        )
      }

      emitProgress(
        exportId: exportId,
        progress: (Double(frameIndex + 1) / Double(frameCount)) * 0.95
      )
    }

    input.markAsFinished()
    let semaphore = DispatchSemaphore(value: 0)
    writer.finishWriting {
      semaphore.signal()
    }
    semaphore.wait()

    if writer.status != .completed {
      throw writer.error ?? NSError(
        domain: "TimelapseExport",
        code: 16,
        userInfo: [NSLocalizedDescriptionKey: "Failed to finalize MP4 file"]
      )
    }
  }

  private func makePixelBufferFromRgbaData(
    _ data: Data,
    width: Int,
    height: Int
  ) throws -> CVPixelBuffer {
    var maybeBuffer: CVPixelBuffer?
    let attrs: [CFString: Any] = [
      kCVPixelBufferCGImageCompatibilityKey: true,
      kCVPixelBufferCGBitmapContextCompatibilityKey: true,
    ]
    let status = CVPixelBufferCreate(
      kCFAllocatorDefault,
      width,
      height,
      kCVPixelFormatType_32BGRA,
      attrs as CFDictionary,
      &maybeBuffer
    )
    guard status == kCVReturnSuccess, let buffer = maybeBuffer else {
      throw NSError(
        domain: "TimelapseExport",
        code: 17,
        userInfo: [NSLocalizedDescriptionKey: "Failed to allocate pixel buffer"]
      )
    }

    CVPixelBufferLockBaseAddress(buffer, [])
    defer {
      CVPixelBufferUnlockBaseAddress(buffer, [])
    }
    guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
      throw NSError(
        domain: "TimelapseExport",
        code: 18,
        userInfo: [NSLocalizedDescriptionKey: "Pixel buffer base address unavailable"]
      )
    }

    let dst = baseAddress.assumingMemoryBound(to: UInt8.self)
    data.withUnsafeBytes { (rawBuffer: UnsafeRawBufferPointer) in
      guard let src = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return }
      let pixelCount = width * height
      var srcIndex = 0
      var dstIndex = 0
      for _ in 0..<pixelCount {
        let r = src[srcIndex]
        let g = src[srcIndex + 1]
        let b = src[srcIndex + 2]
        let a = src[srcIndex + 3]
        dst[dstIndex] = b
        dst[dstIndex + 1] = g
        dst[dstIndex + 2] = r
        dst[dstIndex + 3] = a
        srcIndex += 4
        dstIndex += 4
      }
    }

    return buffer
  }

  private func saveVideoToPhotoLibrary(
    exportId: String,
    fileName: String,
    outputURL: URL,
    completion: @escaping (Result<String, Error>) -> Void
  ) {
    requestPhotoAddPermission { granted in
      if !granted {
        completion(
          .failure(
            NSError(
              domain: "TimelapseExport",
              code: 19,
              userInfo: [NSLocalizedDescriptionKey: "Photo permission denied"]
            )
          )
        )
        return
      }

      var localIdentifier: String?
      PHPhotoLibrary.shared().performChanges({
        let request = PHAssetCreationRequest.forAsset()
        request.addResource(with: .video, fileURL: outputURL, options: nil)
        localIdentifier = request.placeholderForCreatedAsset?.localIdentifier
      }, completionHandler: { success, error in
        try? FileManager.default.removeItem(at: outputURL)

        if success {
          self.emitProgress(exportId: exportId, progress: 1.0)
          completion(.success(localIdentifier ?? fileName))
          return
        }

        completion(
          .failure(
            error ??
              NSError(
                domain: "TimelapseExport",
                code: 20,
                userInfo: [NSLocalizedDescriptionKey: "Failed to save video to Photos"]
              )
          )
        )
      })
    }
  }

  private func requestPhotoAddPermission(_ completion: @escaping (Bool) -> Void) {
    if #available(iOS 14, *) {
      PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
        completion(status == .authorized || status == .limited)
      }
      return
    }

    PHPhotoLibrary.requestAuthorization { status in
      completion(status == .authorized)
    }
  }

  private func emitProgress(exportId: String, progress: Double) {
    DispatchQueue.main.async {
      let clamped = min(max(progress, 0.0), 1.0)
      self.progressSink?([
        "exportId": exportId,
        "progress": clamped,
      ])
    }
  }
}
