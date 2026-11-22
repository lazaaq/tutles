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
/// - `render` {id, quality, maxSide, format, border?, blur?} -> {newId, inBytes, outBytes}
///   Reads the Photos asset `id` (iCloud download when needed), applies orientation, blurs the
///   `blur` strokes (see `BlurSpec`), draws the `border` {width, color, ratio} (see `BorderSpec`),
///   limits the long side of the result to
///   `maxSide` (0 = original, never enlarged) and saves a new asset with the same date, location
///   and metadata. `format` "same" keeps HEIC/PNG/JPEG. The original is never changed.
/// - `collage` {ids, quality, maxSide, cols, rows, gap, color, ratio, crops} -> {newId, inBytes, outBytes}
///   One new asset with the photos `ids` in a grid (see `CollageSpec`), long side `maxSide`
///   (0 = 4096); format, date, location and metadata follow the first photo.
final class PhotoRendererPlugin: NSObject, FlutterPlugin {
  private let queue = DispatchQueue(label: "tutles.render", qos: .userInitiated)

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "tutles/native", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(PhotoRendererPlugin(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "collage" { return handleCollage(call, result: result) }
    guard call.method == "render" else { return result(FlutterMethodNotImplemented) }
    guard let args = call.arguments as? [String: Any], let id = args["id"] as? String else {
      return result(FlutterError(code: "bad_args", message: "id wajib diisi", details: nil))
    }
    let quality = args["quality"] as? Int ?? 90
    let maxSide = args["maxSide"] as? Int ?? 0
    let format = args["format"] as? String
    let border = BorderSpec.from(args["border"])
    let blur = BlurSpec.from(args["blur"])
    if args["blur"] != nil && blur == nil {
      return result(FlutterError(code: "bad_args", message: "Area blur kosong", details: nil))
    }
    queue.async {
      do {
        let r = try autoreleasepool {
          try self.render(
            id: id, quality: quality, maxSide: maxSide, format: format, border: border, blur: blur)
        }
        DispatchQueue.main.async { result(r) }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "render_failed", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  private func handleCollage(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any], let ids = args["ids"] as? [String], ids.count >= 2,
      let spec = CollageSpec.from(args)
    else { return result(FlutterError(code: "bad_args", message: "Data kolase tidak lengkap", details: nil)) }
    let quality = args["quality"] as? Int ?? 90
    let maxSide = args["maxSide"] as? Int ?? 0
    queue.async {
      do {
        let r = try autoreleasepool {
          try self.collage(
            ids: ids, spec: spec, quality: quality,
            longSide: maxSide > 0 ? maxSide : CollageSpec.defaultLongSide)
        }
        DispatchQueue.main.async { result(r) }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "render_failed", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  /// One new asset from `ids`; format, date and location follow the first photo.
  private func collage(ids: [String], spec: CollageSpec, quality: Int, longSide: Int) throws -> [String: Any] {
    let fetched = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
    var byId: [String: PHAsset] = [:]
    fetched.enumerateObjects { a, _, _ in byId[a.localIdentifier] = a }
    let assets = try ids.map { id -> PHAsset in
      guard let a = byId[id] else { throw EncodeError("Foto tidak ditemukan") }
      return a
    }
    let fm = FileManager.default
    let tmpDir = fm.temporaryDirectory.appendingPathComponent("render", isDirectory: true)
    try? fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    var files: [URL] = []
    var outURL: URL?
    defer {
      for f in files { try? fm.removeItem(at: f) }
      if let outURL { try? fm.removeItem(at: outURL) }
    }
    var inBytes = 0
    var fmt = ImageFormat.jpeg
    for (i, asset) in assets.enumerated() {
      guard let res = photoResource(for: asset) else { throw EncodeError("Bukan foto") }
      let ext = (res.originalFilename as NSString).pathExtension
      if i == 0 { fmt = ImageFormat.matching(extension: ext) }
      let url = tmpDir.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext.isEmpty ? "jpg" : ext)
      files.append(url)
      try writeResource(res, to: url)
      inBytes += (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }
    let out = tmpDir.appendingPathComponent(UUID().uuidString).appendingPathExtension(fmt.fileExtension.lowercased())
    outURL = out
    let (image, props) = try spec.render(sources: files, longSide: longSide)
    let outBytes = try ImageEncoder.write(image, metadataFrom: props, to: out, format: fmt, quality: quality)

    let first = assets[0]
    let base = (originalName(for: first) as NSString).deletingPathExtension
    var newId: String?
    try PHPhotoLibrary.shared().performChangesAndWait {
      let req = PHAssetCreationRequest.forAsset()
      let o = PHAssetResourceCreationOptions()
      o.originalFilename = base + "_kolase." + fmt.fileExtension
      req.addResource(with: .photo, fileURL: out, options: o)
      req.creationDate = first.creationDate
      req.location = first.location
      newId = req.placeholderForCreatedAsset?.localIdentifier
    }
    return ["newId": newId ?? "", "inBytes": inBytes, "outBytes": outBytes]
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
    id: String, quality: Int, maxSide: Int, format: String?, border: BorderSpec?, blur: BlurSpec?
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
      source: inURL, to: outURL, format: fmt, quality: quality, maxSide: maxSide, border: border,
      blur: blur)

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
