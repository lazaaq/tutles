import Foundation
import ImageIO
import UniformTypeIdentifiers

/// No Flutter or Photos dependency, so it also runs on macOS:
/// `tool/test_ios_encoder.sh` compiles this file together with `ios/EncoderTests/main.swift`.

struct EncodeError: LocalizedError {
  let errorDescription: String?
  init(_ m: String) { errorDescription = m }
}

/// Output format for re-encoding regular (non-RAW) photos.
enum ImageFormat: String {
  case jpeg, heic, png

  var type: UTType {
    switch self {
    case .jpeg: return .jpeg
    case .heic: return .heic
    case .png: return .png
    }
  }

  /// Extension for the saved file, upper case like the iPhone camera ("IMG_0001.HEIC").
  var fileExtension: String {
    switch self {
    case .jpeg: return "JPG"
    case .heic: return "HEIC"
    case .png: return "PNG"
    }
  }

  /// Same-format output for a source file extension; formats iOS cannot write fall back to JPEG.
  static func matching(extension ext: String) -> ImageFormat {
    switch ext.lowercased() {
    case "heic", "heif", "hif": return .heic
    case "png": return .png
    default: return .jpeg
    }
  }

  /// "jpeg" / "heic" / "png", or "same" -> format of the source file.
  static func parse(_ name: String?, sourceExtension ext: String) -> ImageFormat {
    if let name, let f = ImageFormat(rawValue: name) { return f }
    return matching(extension: ext)
  }
}

/// Plain border around a photo. Geometry matches `BorderLayout` in lib/jobs.dart and Android.
struct BorderSpec: Equatable {
  /// Border on each side, as a fraction of the photo's long side.
  var fraction: Double
  /// 0xRRGGBB, always opaque.
  var rgb: Int
  /// Canvas width / height; 0 = photo plus border.
  var ratio: Double

  /// From the channel argument `{width, color, ratio}`; nil when absent or malformed.
  static func from(_ arg: Any?) -> BorderSpec? {
    guard let m = arg as? [String: Any], let w = (m["width"] as? NSNumber)?.doubleValue, w >= 0
    else { return nil }
    return BorderSpec(
      fraction: min(w, 1),
      rgb: (m["color"] as? NSNumber)?.intValue ?? 0xFFFFFF,
      ratio: max((m["ratio"] as? NSNumber)?.doubleValue ?? 0, 0))
  }

  struct Layout: Equatable {
    var canvasWidth: Int, canvasHeight: Int
    /// Photo rectangle inside the canvas, origin top-left.
    var x: Int, y: Int, width: Int, height: Int
  }

  /// Border on each side, widen/heighten to `ratio`, then shrink everything so the long
  /// side is at most `maxSide` (0 = no limit; never enlarged).
  func layout(width w: Int, height h: Int, maxSide: Int) -> Layout {
    let b = Int((fraction * Double(max(w, h))).rounded())
    var cw = w + 2 * b
    var ch = h + 2 * b
    if ratio > 0 {
      if Double(cw) / Double(ch) < ratio {
        cw = Int((Double(ch) * ratio).rounded())
      } else {
        ch = Int((Double(cw) / ratio).rounded())
      }
    }
    let long = max(cw, ch)
    let s = maxSide > 0 && long > maxSide ? Double(maxSide) / Double(long) : 1
    let canvasW = Int((Double(cw) * s).rounded())
    let canvasH = Int((Double(ch) * s).rounded())
    let iw = min(Int((Double(w) * s).rounded()), canvasW)
    let ih = min(Int((Double(h) * s).rounded()), canvasH)
    return Layout(
      canvasWidth: canvasW, canvasHeight: canvasH,
      x: (canvasW - iw) / 2, y: (canvasH - ih) / 2, width: iw, height: ih)
  }

  /// Draws `image` on a canvas filled with the border colour.
  func apply(to image: CGImage, maxSide: Int) throws -> CGImage {
    let l = layout(width: image.width, height: image.height, maxSide: maxSide)
    let space =
      image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
    guard
      let ctx = CGContext(
        data: nil, width: l.canvasWidth, height: l.canvasHeight, bitsPerComponent: 8, bytesPerRow: 0,
        space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { throw EncodeError("Foto terlalu besar untuk diberi bingkai") }
    ctx.setFillColor(
      CGColor(
        colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        components: [
          CGFloat((rgb >> 16) & 0xFF) / 255, CGFloat((rgb >> 8) & 0xFF) / 255,
          CGFloat(rgb & 0xFF) / 255, 1,
        ])!)
    ctx.fill(CGRect(x: 0, y: 0, width: l.canvasWidth, height: l.canvasHeight))
    ctx.interpolationQuality = .high
    // Core Graphics origin is bottom-left.
    ctx.draw(
      image,
      in: CGRect(x: l.x, y: l.canvasHeight - l.y - l.height, width: l.width, height: l.height))
    guard let out = ctx.makeImage() else {
      throw EncodeError("Gagal memberi bingkai")
    }
    return out
  }
}

/// Re-encodes any ImageIO-readable photo (JPEG, HEIC, PNG, …): orientation is applied to the
/// pixels, long side is limited to `maxSide` (0 = original, never upscaled), and EXIF/GPS/TIFF/IPTC
/// metadata is kept. With `border`, `maxSide` limits the bordered result.
enum ImageEncoder {
  @discardableResult
  static func encode(
    source: URL, to dest: URL, format: ImageFormat, quality: Int, maxSide: Int,
    border: BorderSpec? = nil
  ) throws -> Int {
    guard let src = CGImageSourceCreateWithURL(source as CFURL, nil),
      CGImageSourceGetCount(src) > 0
    else { throw EncodeError("File foto tidak bisa dibaca") }
    let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any] ?? [:]
    let w = props[kCGImagePropertyPixelWidth as String] as? Int ?? 0
    let h = props[kCGImagePropertyPixelHeight as String] as? Int ?? 0
    let long = max(w, h)
    guard long > 0 else { throw EncodeError("Ukuran foto tidak diketahui") }

    let target = maxSide > 0 && long > maxSide ? maxSide : long
    let opts: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,  // apply EXIF orientation
      kCGImageSourceThumbnailMaxPixelSize: target,
      kCGImageSourceShouldCacheImmediately: true,
    ]
    guard var image = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else {
      throw EncodeError("Gagal membaca foto")
    }
    if let border { image = try border.apply(to: image, maxSide: maxSide) }

    guard let out = CGImageDestinationCreateWithURL(
      dest as CFURL, format.type.identifier as CFString, 1, nil)
    else { throw EncodeError("Format \(format.fileExtension) tidak didukung perangkat ini") }
    var meta = metadataProperties(from: props, quality: quality)
    if format == .png { meta.removeValue(forKey: kCGImageDestinationLossyCompressionQuality as String) }
    CGImageDestinationAddImage(out, image, meta as CFDictionary)
    guard CGImageDestinationFinalize(out) else {
      throw EncodeError("Gagal menulis \(format.fileExtension)")
    }
    return (try? dest.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
  }

  static func metadataProperties(from src: [String: Any], quality: Int) -> [String: Any] {
    var out: [String: Any] = [:]
    let keep: [CFString] = [
      kCGImagePropertyExifDictionary, kCGImagePropertyExifAuxDictionary,
      kCGImagePropertyGPSDictionary, kCGImagePropertyTIFFDictionary,
      kCGImagePropertyIPTCDictionary,
    ]
    for k in keep {
      if let v = src[k as String] { out[k as String] = v }
    }
    // Pixels are already upright.
    out[kCGImagePropertyOrientation as String] = 1
    if var tiff = out[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
      tiff[kCGImagePropertyTIFFOrientation as String] = 1
      out[kCGImagePropertyTIFFDictionary as String] = tiff
    }
    if var exif = out[kCGImagePropertyExifDictionary as String] as? [String: Any] {
      exif.removeValue(forKey: kCGImagePropertyExifPixelXDimension as String)
      exif.removeValue(forKey: kCGImagePropertyExifPixelYDimension as String)
      // Newer cameras (e.g. Canon R6 II) only write ISOSpeed (0x8833); many viewers read
      // ISOSpeedRatings (0x8827).
      if exif[kCGImagePropertyExifISOSpeedRatings as String] == nil,
        let iso = exif[kCGImagePropertyExifISOSpeed as String]
      {
        exif[kCGImagePropertyExifISOSpeedRatings as String] = [iso]
      }
      out[kCGImagePropertyExifDictionary as String] = exif
    }
    out[kCGImageDestinationLossyCompressionQuality as String] =
      Double(min(max(quality, 1), 100)) / 100.0
    return out
  }
}
