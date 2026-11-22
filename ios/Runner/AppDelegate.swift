import Flutter
import ImageIO
import Photos
import UIKit
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PhotoRendererPlugin") {
      PhotoRendererPlugin.register(with: registrar)
    }
  }
}

/// Channel `tutles/native`:
/// - `render` {id, quality, maxSide, format, border} -> {newId, inBytes, outBytes}
///   Reads the Photos asset `id` (iCloud download when needed), applies orientation, draws the
///   `border` {width, color, ratio} (see `BorderSpec`), limits the long side of the result to
///   `maxSide` (0 = original, never enlarged) and saves a new asset with the same date, location
///   and metadata. `format` "same" keeps HEIC/PNG/JPEG. The original is never changed.
final class PhotoRendererPlugin: NSObject, FlutterPlugin {
  private let queue = DispatchQueue(label: "tutles.render", qos: .userInitiated)

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "tutles/native", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(PhotoRendererPlugin(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "render" else { return result(FlutterMethodNotImplemented) }
    guard let args = call.arguments as? [String: Any], let id = args["id"] as? String else {
      return result(FlutterError(code: "bad_args", message: "id wajib diisi", details: nil))
    }
    let quality = args["quality"] as? Int ?? 90
    let maxSide = args["maxSide"] as? Int ?? 0
    let format = args["format"] as? String
    let border = BorderSpec.from(args["border"])
    queue.async {
      do {
        let r = try autoreleasepool {
          try self.render(id: id, quality: quality, maxSide: maxSide, format: format, border: border)
        }
        DispatchQueue.main.async { result(r) }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "render_failed", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  /// Regular photo resource (the edited version when there is one).
  private func photoResource(for asset: PHAsset) -> PHAssetResource? {
    let all = PHAssetResource.assetResources(for: asset)
    return all.first { $0.type == .fullSizePhoto } ?? all.first { $0.type == .photo }
  }

  /// Original file name (not "FullSizeRender.jpg" of an edit).
  private func originalName(for asset: PHAsset) -> String {
    let all = PHAssetResource.assetResources(for: asset)
    return (all.first { $0.type == .photo } ?? all.first)?.originalFilename ?? "IMG.JPG"
  }

  private func writeResource(_ res: PHAssetResource, to url: URL) throws {
    let opts = PHAssetResourceRequestOptions()
    opts.isNetworkAccessAllowed = true  // download from iCloud when needed
    let sem = DispatchSemaphore(value: 0)
    var failure: Error?
    PHAssetResourceManager.default().writeData(for: res, toFile: url, options: opts) { err in
      failure = err
      sem.signal()
    }
    sem.wait()
    if let failure { throw failure }
  }

  private func render(
    id: String, quality: Int, maxSide: Int, format: String?, border: BorderSpec?
  ) throws -> [String: Any] {
    guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
    else { throw EncodeError("Foto tidak ditemukan") }
    guard let res = photoResource(for: asset) else { throw EncodeError("Bukan foto") }

    let fm = FileManager.default
    let tmpDir = fm.temporaryDirectory.appendingPathComponent("render", isDirectory: true)
    try? fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    let srcExt = (res.originalFilename as NSString).pathExtension
    let fmt = ImageFormat.parse(format, sourceExtension: srcExt)
    let inURL = tmpDir.appendingPathComponent(UUID().uuidString)
      .appendingPathExtension(srcExt.isEmpty ? "jpg" : srcExt)
    let outURL = tmpDir.appendingPathComponent(UUID().uuidString)
      .appendingPathExtension(fmt.fileExtension.lowercased())
    defer {
      try? fm.removeItem(at: inURL)
      try? fm.removeItem(at: outURL)
    }

    try writeResource(res, to: inURL)
    let inBytes = (try? inURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    let outBytes = try ImageEncoder.encode(
      source: inURL, to: outURL, format: fmt, quality: quality, maxSide: maxSide, border: border)

    let base = (originalName(for: asset) as NSString).deletingPathExtension
    var newId: String?
    try PHPhotoLibrary.shared().performChangesAndWait {
      let req = PHAssetCreationRequest.forAsset()
      let o = PHAssetResourceCreationOptions()
      o.originalFilename = base + "." + fmt.fileExtension
      req.addResource(with: .photo, fileURL: outURL, options: o)
      req.creationDate = asset.creationDate
      req.location = asset.location
      newId = req.placeholderForCreatedAsset?.localIdentifier
    }
    return ["newId": newId ?? "", "inBytes": inBytes, "outBytes": outBytes]
  }
}
