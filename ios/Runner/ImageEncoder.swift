import CoreImage
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

/// Gaussian blur: `strength` inside brush strokes, `background` outside (0 = sharp), with a soft
/// edge of `feather`. Geometry matches `BlurOptions` in lib/blur.dart and `BlurSpec.java`.
struct BlurSpec: Equatable {
  struct Stroke: Equatable {
    /// Brush radius as a fraction of the photo's long side.
    var radius: Double
    /// Eraser: removes blur painted by earlier strokes.
    var erase: Bool
    /// x0, y0, x1, y1, … relative to the upright photo (0...1, origin top-left).
    var points: [Double]
  }

  static let defaultFeather = 0.012
  static let maxStrength = 0.1

  /// Blur sigma inside the strokes, as a fraction of the photo's long side.
  var strength: Double
  /// Blur sigma outside the strokes; 0 = sharp.
  var background: Double = 0
  /// Sigma of the soft edge (the mask is blurred), as a fraction of the long side.
  var feather: Double = BlurSpec.defaultFeather
  var strokes: [Stroke]

  /// The result differs from the photo.
  var changesPhoto: Bool { background > 0 || (strength > 0 && strokes.contains { !$0.erase }) }

  /// From the channel argument `{strength, background, feather, strokes: [{radius, erase,
  /// points}]}`; nil when absent, malformed, or nothing would change.
  static func from(_ arg: Any?) -> BlurSpec? {
    guard let m = arg as? [String: Any], let s = (m["strength"] as? NSNumber)?.doubleValue, s >= 0
    else { return nil }
    func clamp(_ v: Double, _ hi: Double) -> Double { min(max(v, 0), hi) }
    var strokes: [Stroke] = []
    for item in m["strokes"] as? [Any] ?? [] {
      guard let d = item as? [String: Any], let r = (d["radius"] as? NSNumber)?.doubleValue, r > 0,
        let raw = d["points"] as? [Any]
      else { continue }
      var pts = raw.compactMap { ($0 as? NSNumber)?.doubleValue }
      if pts.count % 2 == 1 { pts.removeLast() }
      if pts.isEmpty { continue }
      strokes.append(Stroke(radius: min(r, 1), erase: (d["erase"] as? NSNumber)?.boolValue ?? false, points: pts))
    }
    let spec = BlurSpec(
      strength: clamp(s, maxStrength),
      background: clamp((m["background"] as? NSNumber)?.doubleValue ?? 0, maxStrength),
      feather: clamp((m["feather"] as? NSNumber)?.doubleValue ?? defaultFeather, maxStrength),
      strokes: strokes)
    return spec.changesPhoto ? spec : nil
  }

  func sigma(width w: Int, height h: Int) -> Double { strength * Double(max(w, h)) }

  func backgroundSigma(width w: Int, height h: Int) -> Double { background * Double(max(w, h)) }

  func featherSigma(width w: Int, height h: Int) -> Double { feather * Double(max(w, h)) }

  /// Hard-edged coverage mask (white = blur), same size as the photo, origin bottom-left as
  /// usual for Core Graphics.
  func mask(width w: Int, height h: Int) throws -> CGImage {
    guard
      let ctx = CGContext(
        data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
    else { throw EncodeError("Foto terlalu besar untuk di-blur") }
    ctx.setFillColor(gray: 0, alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    let long = Double(max(w, h))
    for s in strokes {
      let v: CGFloat = s.erase ? 0 : 1
      ctx.setFillColor(gray: v, alpha: 1)
      ctx.setStrokeColor(gray: v, alpha: 1)
      let r = s.radius * long
      let pts = stride(from: 0, to: s.points.count, by: 2).map {
        CGPoint(x: s.points[$0] * Double(w), y: (1 - s.points[$0 + 1]) * Double(h))
      }
      if pts.count == 1 {
        ctx.fillEllipse(in: CGRect(x: pts[0].x - r, y: pts[0].y - r, width: 2 * r, height: 2 * r))
      } else {
        ctx.setLineWidth(2 * r)
        ctx.beginPath()
        ctx.addLines(between: pts)
        ctx.strokePath()
      }
    }
    guard let out = ctx.makeImage() else { throw EncodeError("Gagal membuat area blur") }
    return out
  }

  /// `image` blurred by `strength` inside the strokes and `background` outside, same size.
  func apply(to image: CGImage) throws -> CGImage {
    let w = image.width
    let h = image.height
    let space =
      image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
    let src = CIImage(cgImage: image)
    let extent = src.extent
    func blurred(_ sigma: Double) -> CIImage {
      sigma > 0 ? src.clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: extent) : src
    }
    let inside = blurred(sigma(width: w, height: h))
    let outside = blurred(backgroundSigma(width: w, height: h))
    var out = outside
    if strokes.contains(where: { !$0.erase }) {
      // Mask values are coverage, not colour: no colour management.
      let mask = CIImage(cgImage: try mask(width: w, height: h), options: [.colorSpace: NSNull()])
        .clampedToExtent()
        .applyingGaussianBlur(sigma: featherSigma(width: w, height: h))
        .cropped(to: extent)
      out = inside.applyingFilter(
        "CIBlendWithMask",
        parameters: [kCIInputBackgroundImageKey: outside, kCIInputMaskImageKey: mask])
    }
    let ctx = CIContext(options: [.cacheIntermediates: false])
    guard let cg = ctx.createCGImage(out, from: extent, format: .RGBA8, colorSpace: space) else {
      throw EncodeError("Gagal mem-blur foto")
    }
    return cg
  }
}

/// Collage: equal cells in `cols` x `rows` with a `gap` around and between them, each photo
/// cropped to fill its cell. Geometry matches `CollageGeometry` in lib/collage.dart and
/// `CollageGeometry.java` on Android.
struct CollageSpec: Equatable {
  static let defaultLongSide = 4096

  var cols: Int
  var rows: Int
  /// Gap as a fraction of the canvas' long side.
  var gap: Double
  /// 0xRRGGBB of the gaps, always opaque.
  var rgb: Int
  /// Canvas width / height.
  var ratio: Double
  /// Crop position per photo: x0, y0, x1, y1, … (0 = left/top, 1 = right/bottom); missing = 0.5.
  var crops: [Double] = []

  /// Crop position of photo `i`.
  func crop(_ i: Int) -> (Double, Double) {
    func at(_ k: Int) -> Double { k < crops.count ? min(max(crops[k], 0), 1) : 0.5 }
    return (at(2 * i), at(2 * i + 1))
  }

  /// From the channel arguments `{cols, rows, gap, color, ratio, crops}`; nil when malformed.
  static func from(_ m: [String: Any]) -> CollageSpec? {
    guard let c = (m["cols"] as? NSNumber)?.intValue, let r = (m["rows"] as? NSNumber)?.intValue,
      (1...5).contains(c), (1...5).contains(r),
      let ratio = (m["ratio"] as? NSNumber)?.doubleValue, ratio > 0
    else { return nil }
    return CollageSpec(
      cols: c, rows: r, gap: min(max((m["gap"] as? NSNumber)?.doubleValue ?? 0, 0), 0.25),
      rgb: ((m["color"] as? NSNumber)?.intValue ?? 0xFFFFFF) & 0xFFFFFF, ratio: ratio,
      crops: (m["crops"] as? [Any] ?? []).compactMap { ($0 as? NSNumber)?.doubleValue })
  }

  struct Rect: Equatable {
    var x: Int, y: Int, w: Int, h: Int
  }

  struct Geometry: Equatable {
    var width: Int, height: Int
    /// Row by row from the top left.
    var cells: [Rect]
  }

  /// Canvas with long side `longSide`; leftover pixels from rounding are spread evenly.
  func geometry(longSide: Int) -> Geometry {
    let w = ratio >= 1 ? longSide : max(1, Int((Double(longSide) * ratio).rounded()))
    let h = ratio >= 1 ? max(1, Int((Double(longSide) / ratio).rounded())) : longSide
    let g = Int((gap * Double(max(w, h))).rounded())
    func split(_ total: Int, _ n: Int) -> [(Int, Int)] {
      let avail = max(n, total - (n + 1) * g)
      func edge(_ i: Int) -> Int { Int((Double(avail * i) / Double(n)).rounded()) }
      return (0..<n).map { i in (g + i * g + edge(i), edge(i + 1) - edge(i)) }
    }
    let xs = split(w, cols)
    let ys = split(h, rows)
    return Geometry(
      width: w, height: h,
      cells: ys.flatMap { y in xs.map { x in Rect(x: x.0, y: y.0, w: x.1, h: y.1) } })
  }

  /// Part of an `iw` x `ih` image that fills a `cw` x `ch` cell; the cut-off rest is split by
  /// the crop position (`fx`, `fy`), 0.5 = centre.
  static func cover(_ iw: Int, _ ih: Int, _ cw: Int, _ ch: Int, _ fx: Double = 0.5, _ fy: Double = 0.5) -> Rect {
    if iw * ch > ih * cw {
      let sw = max(1, Int((Double(ih * cw) / Double(ch)).rounded()))
      return Rect(x: Int((Double(iw - sw) * min(max(fx, 0), 1)).rounded(.down)), y: 0, w: sw, h: ih)
    }
    let sh = max(1, Int((Double(iw * ch) / Double(cw)).rounded()))
    return Rect(x: 0, y: Int((Double(ih - sh) * min(max(fy, 0), 1)).rounded(.down)), w: iw, h: sh)
  }

  /// Draws the photo files `sources` (orientation applied) into the cells, in order.
  /// Returns the canvas and the metadata of the first photo.
  func render(sources: [URL], longSide: Int) throws -> (CGImage, [String: Any]) {
    let geo = geometry(longSide: longSide)
    let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
    guard
      let ctx = CGContext(
        data: nil, width: geo.width, height: geo.height, bitsPerComponent: 8, bytesPerRow: 0,
        space: srgb, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { throw EncodeError("Kolase terlalu besar") }
    ctx.setFillColor(
      CGColor(
        colorSpace: srgb,
        components: [
          CGFloat((rgb >> 16) & 0xFF) / 255, CGFloat((rgb >> 8) & 0xFF) / 255, CGFloat(rgb & 0xFF) / 255, 1,
        ])!)
    ctx.fill(CGRect(x: 0, y: 0, width: geo.width, height: geo.height))
    ctx.interpolationQuality = .high
    var firstProps: [String: Any] = [:]
    for (i, url) in sources.enumerated() where i < geo.cells.count {
      let cell = geo.cells[i]
      guard let src = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(src) > 0
      else { throw EncodeError("File foto tidak bisa dibaca") }
      let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any] ?? [:]
      if i == 0 { firstProps = props }
      var w = props[kCGImagePropertyPixelWidth as String] as? Int ?? 0
      var h = props[kCGImagePropertyPixelHeight as String] as? Int ?? 0
      if (5...8).contains(props[kCGImagePropertyOrientation as String] as? Int ?? 1) { swap(&w, &h) }
      guard w > 0, h > 0 else { throw EncodeError("Ukuran foto tidak diketahui") }
      // Decode just big enough to fill the cell.
      let scale = min(1, max(Double(cell.w) / Double(w), Double(cell.h) / Double(h)))
      let opts: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: max(1, Int((Double(max(w, h)) * scale).rounded(.up))),
        kCGImageSourceShouldCacheImmediately: true,
      ]
      guard let img = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else {
        throw EncodeError("Gagal membaca foto")
      }
      let (fx, fy) = crop(i)
      let c = CollageSpec.cover(img.width, img.height, cell.w, cell.h, fx, fy)
      guard let part = img.cropping(to: CGRect(x: c.x, y: c.y, width: c.w, height: c.h)) else {
        throw EncodeError("Gagal memotong foto")
      }
      // Core Graphics origin is bottom-left.
      ctx.draw(part, in: CGRect(x: cell.x, y: geo.height - cell.y - cell.h, width: cell.w, height: cell.h))
    }
    guard let out = ctx.makeImage() else { throw EncodeError("Gagal membuat kolase") }
    return (out, firstProps)
  }
}

/// Re-encodes any ImageIO-readable photo (JPEG, HEIC, PNG, …): orientation is applied to the
/// pixels, long side is limited to `maxSide` (0 = original, never upscaled), and EXIF/GPS/TIFF/IPTC
/// metadata is kept. `blur` is applied first, then `border`; `maxSide` limits the final result.
enum ImageEncoder {
  @discardableResult
  static func encode(
    source: URL, to dest: URL, format: ImageFormat, quality: Int, maxSide: Int,
    border: BorderSpec? = nil, blur: BlurSpec? = nil
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
    if let blur { image = try blur.apply(to: image) }
    if let border { image = try border.apply(to: image, maxSide: maxSide) }
    return try write(image, metadataFrom: props, to: dest, format: format, quality: quality)
  }

  /// Writes an upright `image` with the metadata of `props` (see `metadataProperties`).
  /// Returns the file size.
  @discardableResult
  static func write(
    _ image: CGImage, metadataFrom props: [String: Any], to dest: URL, format: ImageFormat, quality: Int
  ) throws -> Int {
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
