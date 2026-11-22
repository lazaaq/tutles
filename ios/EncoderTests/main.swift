// macOS test harness for ios/Runner/ImageEncoder.swift (same ImageIO / Core Graphics code path
// as the iOS app). Run via tool/test_ios_encoder.sh.
//
// usage: encoder-tests <work-dir>

import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
let fixtures = URL(fileURLWithPath: args[1])
let out = fixtures.appendingPathComponent("out", isDirectory: true)
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

var passed = 0
var failed = 0

func check(_ cond: Bool, _ msg: @autoclosure () -> String) {
  if !cond {
    failed += 1
    print("    FAIL: \(msg())")
  }
}

func test(_ name: String, _ body: () throws -> Void) {
  let before = failed
  do { try body() } catch {
    failed += 1
    print("    FAIL: threw \(error.localizedDescription)")
  }
  if failed == before { passed += 1; print("  ok   \(name)") } else { print("  FAIL \(name)") }
}

struct Info {
  let width: Int
  let height: Int
  let orientation: Int
  let type: String
  let props: [String: Any]
  var exif: [String: Any] { props[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:] }
  var tiff: [String: Any] { props[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:] }
  var longSide: Int { max(width, height) }
}

func info(_ url: URL) -> Info? {
  guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
    let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any]
  else { return nil }
  return Info(
    width: p[kCGImagePropertyPixelWidth as String] as? Int ?? 0,
    height: p[kCGImagePropertyPixelHeight as String] as? Int ?? 0,
    orientation: p[kCGImagePropertyOrientation as String] as? Int ?? 1,
    type: CGImageSourceGetType(src) as String? ?? "",
    props: p)
}

// MARK: - ImageEncoder (regular photos)

print("ImageEncoder (macOS)")

/// Synthetic photo: gradient pixels, given EXIF orientation, GPS + TIFF metadata.
func makePhoto(_ url: URL, type: UTType, width: Int, height: Int, orientation: Int) {
  let ctx = CGContext(
    data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  for y in stride(from: 0, to: height, by: 8) {
    for x in stride(from: 0, to: width, by: 8) {
      ctx.setFillColor(red: CGFloat(x) / CGFloat(width), green: CGFloat(y) / CGFloat(height),
                       blue: CGFloat((x * y) % 255) / 255, alpha: 1)
      ctx.fill(CGRect(x: x, y: y, width: 8, height: 8))
    }
  }
  let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)!
  let props: [String: Any] = [
    kCGImagePropertyOrientation as String: orientation,
    kCGImagePropertyTIFFDictionary as String: [
      kCGImagePropertyTIFFMake as String: "Apple", kCGImagePropertyTIFFModel as String: "iPhone 11",
    ],
    kCGImagePropertyGPSDictionary as String: [
      kCGImagePropertyGPSLatitude as String: 8.65, kCGImagePropertyGPSLatitudeRef as String: "S",
      kCGImagePropertyGPSLongitude as String: 115.2, kCGImagePropertyGPSLongitudeRef as String: "E",
    ],
    kCGImagePropertyExifDictionary as String: [
      kCGImagePropertyExifDateTimeOriginal as String: "2023:03:30 10:11:12",
    ],
  ]
  CGImageDestinationAddImage(dest, ctx.makeImage()!, props as CFDictionary)
  CGImageDestinationFinalize(dest)
}

let photoJpg = fixtures.appendingPathComponent("photo.jpg")
let photoRot = fixtures.appendingPathComponent("photo-rot.jpg")
let photoPng = fixtures.appendingPathComponent("photo.png")
makePhoto(photoJpg, type: .jpeg, width: 1200, height: 800, orientation: 1)
makePhoto(photoRot, type: .jpeg, width: 1200, height: 800, orientation: 6)
makePhoto(photoPng, type: .png, width: 640, height: 480, orientation: 1)
let heicWritable = (CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []).contains(UTType.heic.identifier)

func encodePhoto(_ src: URL, _ name: String, _ f: ImageFormat, quality: Int = 85, maxSide: Int = 0) throws
  -> (URL, Int)
{
  let dst = out.appendingPathComponent(name)
  try? FileManager.default.removeItem(at: dst)
  let n = try ImageEncoder.encode(source: src, to: dst, format: f, quality: quality, maxSide: maxSide)
  return (dst, n)
}

test("JPEG -> JPEG keeps size, GPS, TIFF and date") {
  let (u, n) = try encodePhoto(photoJpg, "p1.jpg", .jpeg)
  let i = info(u)!
  check(i.type == UTType.jpeg.identifier, "type \(i.type)")
  check(i.width == 1200 && i.height == 800, "size \(i.width)x\(i.height)")
  check(n > 0 && n == ((try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1), "byte count")
  let gps = i.props[kCGImagePropertyGPSDictionary as String] as? [String: Any] ?? [:]
  check(gps[kCGImagePropertyGPSLatitudeRef as String] as? String == "S", "GPS kept")
  check(i.tiff[kCGImagePropertyTIFFModel as String] as? String == "iPhone 11", "model kept")
  check(i.exif[kCGImagePropertyExifDateTimeOriginal as String] as? String == "2023:03:30 10:11:12", "date kept")
}

test("orientation 6 applied to pixels, output orientation 1") {
  let (u, _) = try encodePhoto(photoRot, "p2.jpg", .jpeg)
  let i = info(u)!
  check(i.width == 800 && i.height == 1200, "size \(i.width)x\(i.height)")
  check(i.orientation == 1, "orientation \(i.orientation)")
}

test("maxSide downsizes, never upscales") {
  let (a, _) = try encodePhoto(photoRot, "p3.jpg", .jpeg, maxSide: 600)
  let ia = info(a)!
  check(ia.longSide == 600 && ia.width == 400, "downsized \(ia.width)x\(ia.height)")
  let (b, _) = try encodePhoto(photoJpg, "p4.jpg", .jpeg, maxSide: 5000)
  check(info(b)!.longSide == 1200, "no upscale")
}

test("lower JPEG quality gives a smaller file") {
  let (_, hi) = try encodePhoto(photoJpg, "q95.jpg", .jpeg, quality: 95)
  let (_, lo) = try encodePhoto(photoJpg, "q50.jpg", .jpeg, quality: 50)
  check(lo < hi, "q50 \(lo) < q95 \(hi)")
}

test("JPEG -> PNG, quality ignored") {
  let (u, a) = try encodePhoto(photoJpg, "p5.png", .png, quality: 50)
  let (_, b) = try encodePhoto(photoJpg, "p6.png", .png, quality: 100)
  check(info(u)!.type == UTType.png.identifier, "type")
  check(a == b, "PNG size independent of quality: \(a) vs \(b)")
}

test("PNG -> JPEG") {
  let (u, _) = try encodePhoto(photoPng, "p7.jpg", .jpeg)
  let i = info(u)!
  check(i.type == UTType.jpeg.identifier && i.width == 640 && i.height == 480, "\(i.type) \(i.width)x\(i.height)")
}

test("JPEG -> HEIC (when this Mac can write HEIC)") {
  guard heicWritable else { print("         skipped: no HEIC encoder"); return }
  let (u, n) = try encodePhoto(photoRot, "p8.heic", .heic, maxSide: 1000)
  let i = info(u)!
  check(i.type == UTType.heic.identifier, "type \(i.type)")
  check(i.width == 667 && i.height == 1000, "size \(i.width)x\(i.height)")
  let (_, jpg) = try encodePhoto(photoRot, "p8.jpg", .jpeg, maxSide: 1000)
  check(n < jpg, "HEIC \(n) smaller than JPEG \(jpg)")
  // and back: HEIC -> JPEG
  let (back, _) = try encodePhoto(u, "p9.jpg", .jpeg)
  check(info(back)!.width == 667, "HEIC decodes")
}

test("format rules for 'same' and explicit formats") {
  check(ImageFormat.parse("same", sourceExtension: "HEIC") == .heic, "HEIC stays HEIC")
  check(ImageFormat.parse(nil, sourceExtension: "heif") == .heic, "heif")
  check(ImageFormat.parse("same", sourceExtension: "PNG") == .png, "png")
  check(ImageFormat.parse("same", sourceExtension: "JPG") == .jpeg, "jpg")
  check(ImageFormat.parse("same", sourceExtension: "webp") == .jpeg, "webp -> jpeg on iOS")
  check(ImageFormat.parse("same", sourceExtension: "") == .jpeg, "no extension")
  check(ImageFormat.parse("png", sourceExtension: "HEIC") == .png, "explicit wins")
  check(ImageFormat.parse("webp", sourceExtension: "PNG") == .png, "unknown explicit -> same as source")
  check(ImageFormat.heic.fileExtension == "HEIC" && ImageFormat.jpeg.fileExtension == "JPG", "extensions")
}

test("unreadable file throws a readable error") {
  let bad = fixtures.appendingPathComponent("bad.jpg")
  try Data("not an image".utf8).write(to: bad)
  do {
    _ = try encodePhoto(bad, "bad-out.jpg", .jpeg)
    check(false, "should throw")
  } catch {
    check(!error.localizedDescription.isEmpty, "message")
  }
}

// MARK: - Border

print("BorderSpec (macOS)")

/// Same cases as test/image_jobs_test.dart and BorderLayoutTest.java.
test("border layout matches the shared cases") {
  typealias C = (w: Int, h: Int, f: Double, r: Double, m: Int, want: [Int])
  let cases: [C] = [
    (1200, 800, 0.05, 0, 0, [1320, 920, 60, 60, 1200, 800]),
    (1200, 800, 0.05, 1, 0, [1320, 1320, 60, 260, 1200, 800]),
    (800, 1200, 0.05, 0.8, 0, [1056, 1320, 128, 60, 800, 1200]),
    (1200, 800, 0.02, 9.0 / 16, 1000, [562, 1000, 10, 319, 541, 361]),
    (1000, 1000, 0.1, 0, 600, [600, 600, 50, 50, 500, 500]),
    (1200, 800, 0, 0, 0, [1200, 800, 0, 0, 1200, 800]),
  ]
  for c in cases {
    let l = BorderSpec(fraction: c.f, rgb: 0, ratio: c.r).layout(width: c.w, height: c.h, maxSide: c.m)
    let got = [l.canvasWidth, l.canvasHeight, l.x, l.y, l.width, l.height]
    check(got == c.want, "\(c.w)x\(c.h) f\(c.f) r\(c.r) m\(c.m): \(got) != \(c.want)")
  }
}

test("border channel argument parsing") {
  let b = BorderSpec.from(["width": 0.05, "color": 0xF3EBDD, "ratio": 0.8])
  check(b == BorderSpec(fraction: 0.05, rgb: 0xF3EBDD, ratio: 0.8), "parsed \(String(describing: b))")
  check(BorderSpec.from(nil) == nil, "absent -> nil")
  check(BorderSpec.from(["color": 0]) == nil, "no width -> nil")
}

/// RGB of one pixel (origin top-left) of an encoded file.
func pixel(_ url: URL, _ x: Int, _ y: Int) -> (Int, Int, Int) {
  let src = CGImageSourceCreateWithURL(url as CFURL, nil)!
  let img = CGImageSourceCreateImageAtIndex(src, 0, nil)!
  var buf = [UInt8](repeating: 0, count: 4)
  let ctx = CGContext(
    data: &buf, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
  ctx.draw(img, in: CGRect(x: -x, y: -(img.height - 1 - y), width: img.width, height: img.height))
  return (Int(buf[0]), Int(buf[1]), Int(buf[2]))
}

func encodeBorder(_ src: URL, _ name: String, _ f: ImageFormat, _ b: BorderSpec, maxSide: Int = 0) throws -> URL {
  let dst = out.appendingPathComponent(name)
  try? FileManager.default.removeItem(at: dst)
  try ImageEncoder.encode(source: src, to: dst, format: f, quality: 90, maxSide: maxSide, border: b)
  return dst
}

test("white border on JPEG: canvas size, border colour, metadata kept") {
  let u = try encodeBorder(photoJpg, "b1.jpg", .jpeg, BorderSpec(fraction: 0.05, rgb: 0xFFFFFF, ratio: 0))
  let i = info(u)!
  check(i.width == 1320 && i.height == 920, "size \(i.width)x\(i.height)")
  let (r, g, b) = pixel(u, 10, 10)
  check(r > 245 && g > 245 && b > 245, "corner is white: \(r),\(g),\(b)")
  check(i.tiff[kCGImagePropertyTIFFModel as String] as? String == "iPhone 11", "model kept")
  check(i.orientation == 1, "orientation \(i.orientation)")
}

test("square black border on rotated photo, limited by maxSide") {
  let u = try encodeBorder(photoRot, "b2.jpg", .jpeg, BorderSpec(fraction: 0.05, rgb: 0, ratio: 1), maxSide: 1000)
  let i = info(u)!
  check(i.width == 1000 && i.height == 1000, "size \(i.width)x\(i.height)")
  let (r, g, b) = pixel(u, 30, 500)
  check(r < 10 && g < 10 && b < 10, "left band is black: \(r),\(g),\(b)")
  let (cr, cg, cb) = pixel(u, 500, 500)
  check(cr + cg + cb > 30, "centre is photo, not border: \(cr),\(cg),\(cb)")
}

test("cream 4:5 border keeps PNG format") {
  let u = try encodeBorder(photoPng, "b3.png", .png, BorderSpec(fraction: 0.02, rgb: 0xF3EBDD, ratio: 0.8))
  let i = info(u)!
  check(i.type == UTType.png.identifier, "type \(i.type)")
  check(i.width == 666 && i.height == 833, "size \(i.width)x\(i.height)")
  let (r, g, b) = pixel(u, 2, 2)
  check(abs(r - 0xF3) <= 2 && abs(g - 0xEB) <= 2 && abs(b - 0xDD) <= 2, "cream: \(r),\(g),\(b)")
}

// MARK: - Blur

print("BlurSpec (macOS)")

/// Same cases as test/blur_test.dart and BlurSpecTest.java.
test("blur sigmas match the shared cases") {
  func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }
  let a = BlurSpec(strength: 0.02, background: 0.01, feather: 0.012, strokes: [])
  check(near(a.sigma(width: 4000, height: 3000), 80), "sigma 4000x3000")
  check(near(a.backgroundSigma(width: 4000, height: 3000), 40), "background 4000x3000")
  check(near(a.featherSigma(width: 4000, height: 3000), 48), "feather 4000x3000")
  let b = BlurSpec(strength: 0.005, background: 0, feather: 0.004, strokes: [])
  check(near(b.sigma(width: 800, height: 1200), 6), "sigma 800x1200")
  check(b.backgroundSigma(width: 800, height: 1200) == 0, "background 0")
  check(near(b.featherSigma(width: 800, height: 1200), 4.8), "feather 800x1200")
  check(near(BlurSpec(strength: 0.05, strokes: []).sigma(width: 1000, height: 1000), 50), "sigma 1000x1000")
}

test("blur channel argument parsing") {
  let arg: [String: Any] = [
    "strength": 0.02, "background": 0.005, "feather": 0.008,
    "strokes": [
      ["radius": 0.05, "erase": false, "points": [0.1, 0.2, 0.3, 0.4]],
      ["radius": 0.02, "erase": true, "points": [0.5, 0.5, 0.9]],  // odd count: last dropped
      ["radius": 0.02, "points": []],  // empty: skipped
    ],
  ]
  let b = BlurSpec.from(arg)
  check(
    b == BlurSpec(strength: 0.02, background: 0.005, feather: 0.008, strokes: [
      .init(radius: 0.05, erase: false, points: [0.1, 0.2, 0.3, 0.4]),
      .init(radius: 0.02, erase: true, points: [0.5, 0.5]),
    ]), "parsed \(String(describing: b))")
  check(BlurSpec.from(nil) == nil, "absent -> nil")
  check(BlurSpec.from(["strength": 0, "strokes": arg["strokes"]!]) == nil, "strength 0, background 0 -> nil")
  check(
    BlurSpec.from(["strength": 0.02, "background": 0.01])
      == BlurSpec(strength: 0.02, background: 0.01, feather: BlurSpec.defaultFeather, strokes: []),
    "background only: no strokes needed, default feather")
  check(BlurSpec.from(["strength": 0.02, "strokes": arg["strokes"]!])?.feather == BlurSpec.defaultFeather,
    "feather defaults")
  check(
    BlurSpec.from(["strength": 0.02, "strokes": [["radius": 0.1, "erase": true, "points": [0.5, 0.5]]]]) == nil,
    "eraser only -> nil")
  check(
    BlurSpec.from(["strength": 3, "background": -1, "feather": 2, "strokes": [["radius": 4, "points": [0.5, 0.5]]]])
      == BlurSpec(strength: 0.1, background: 0, feather: 0.1, strokes: [.init(radius: 1, erase: false, points: [0.5, 0.5])]),
    "clamped")
}

/// RGBA bytes of an image, rows top to bottom.
func rgba(_ img: CGImage) -> [UInt8] {
  var buf = [UInt8](repeating: 0, count: img.width * img.height * 4)
  let ctx = CGContext(
    data: &buf, width: img.width, height: img.height, bitsPerComponent: 8, bytesPerRow: img.width * 4,
    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
  ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
  return buf
}

func grayAt(_ img: CGImage, _ x: Int, _ y: Int) -> Int {
  var buf = [UInt8](repeating: 0, count: 1)
  let ctx = CGContext(
    data: &buf, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 1,
    space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
  ctx.draw(img, in: CGRect(x: -x, y: -(img.height - 1 - y), width: img.width, height: img.height))
  return Int(buf[0])
}

test("mask: stroke, dot and eraser in photo coordinates (origin top-left)") {
  let spec = BlurSpec(strength: 0.02, strokes: [
    .init(radius: 0.05, erase: false, points: [0.1, 0.25, 0.4, 0.25]),  // top-left band
    .init(radius: 0.05, erase: false, points: [0.8, 0.75]),  // dot bottom-right
    .init(radius: 0.05, erase: true, points: [0.4, 0.25]),  // erase the band's right end
  ])
  let m = try spec.mask(width: 200, height: 100)
  check(m.width == 200 && m.height == 100, "size")
  check(grayAt(m, 40, 25) == 255, "band painted: \(grayAt(m, 40, 25))")
  check(grayAt(m, 40, 75) == 0, "below band clear: \(grayAt(m, 40, 75))")
  check(grayAt(m, 160, 75) == 255, "dot: \(grayAt(m, 160, 75))")
  check(grayAt(m, 80, 25) == 0, "erased: \(grayAt(m, 80, 25))")
  check(grayAt(m, 31, 25) == 255 && grayAt(m, 2, 25) == 0, "radius 10 px round cap")
}

/// Black/white 2 px checkerboard: blurring makes it grey.
func checker(_ w: Int, _ h: Int) -> CGImage {
  let ctx = CGContext(
    data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
  ctx.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
  ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
  ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
  for y in stride(from: 0, to: h, by: 2) {
    for x in stride(from: (y / 2) % 2 * 2, to: w, by: 4) { ctx.fill(CGRect(x: x, y: y, width: 2, height: 2)) }
  }
  return ctx.makeImage()!
}

/// Spread of the red channel in a square around (cx, cy), origin top-left.
func spread(_ px: [UInt8], _ w: Int, _ cx: Int, _ cy: Int, _ r: Int = 6) -> Int {
  var lo = 255
  var hi = 0
  for y in (cy - r)...(cy + r) {
    for x in (cx - r)...(cx + r) {
      let v = Int(px[(y * w + x) * 4])
      lo = min(lo, v)
      hi = max(hi, v)
    }
  }
  return hi - lo
}

test("apply blurs only inside the strokes, same size") {
  let img = checker(400, 300)
  let spec = BlurSpec(strength: 0.01, feather: 0.004, strokes: [.init(radius: 0.1, erase: false, points: [0.25, 0.5])])
  let out = try spec.apply(to: img)
  check(out.width == 400 && out.height == 300, "size \(out.width)x\(out.height)")
  let a = rgba(img)
  let b = rgba(out)
  check(spread(a, 400, 100, 150) > 200, "source is sharp")
  check(spread(b, 400, 100, 150) < 40, "centre of the dot is blurred: \(spread(b, 400, 100, 150))")
  let mid = Int(b[(150 * 400 + 100) * 4])
  // Core Image blurs in linear light: half white averages to ~188 in sRGB, not 128.
  check(mid > 100 && mid < 220, "blurred to grey: \(mid)")
  var same = true
  for y in 100..<200 { for x in 250..<350 where abs(Int(a[(y * 400 + x) * 4]) - Int(b[(y * 400 + x) * 4])) > 2 { same = false } }
  check(same, "outside the dot unchanged")
}

test("background blur: sharp subject, blurred rest") {
  let img = checker(400, 300)
  let spec = BlurSpec(
    strength: 0, background: 0.01, feather: 0.004,
    strokes: [.init(radius: 0.1, erase: false, points: [0.25, 0.5])])
  let b = rgba(try spec.apply(to: img))
  check(spread(b, 400, 100, 150, 4) > 200, "subject stays sharp: \(spread(b, 400, 100, 150, 4))")
  check(spread(b, 400, 300, 150) < 40, "rest blurred: \(spread(b, 400, 300, 150))")
}

test("softer edge reaches further out") {
  let img = checker(400, 300)
  func edgeSpread(_ feather: Double) throws -> Int {
    let spec = BlurSpec(
      strength: 0.01, feather: feather, strokes: [.init(radius: 0.1, erase: false, points: [0.25, 0.5])])
    // 10 px outside the 40 px dot.
    return spread(rgba(try spec.apply(to: img)), 400, 100, 100, 3)
  }
  let hard = try edgeSpread(0.001)
  let soft = try edgeSpread(0.04)
  check(hard > 200, "hard edge: outside untouched \(hard)")
  check(soft < hard - 40, "soft edge blurs outside a bit: \(soft) < \(hard)")
}

test("JPEG with blur then border: size, metadata, blurred area") {
  let dst = out.appendingPathComponent("blur1.jpg")
  try? FileManager.default.removeItem(at: dst)
  let blur = BlurSpec(strength: 0.02, strokes: [.init(radius: 0.1, erase: false, points: [0.5, 0.5])])
  try ImageEncoder.encode(
    source: photoJpg, to: dst, format: .jpeg, quality: 90, maxSide: 0,
    border: BorderSpec(fraction: 0.05, rgb: 0xFFFFFF, ratio: 0), blur: blur)
  let i = info(dst)!
  check(i.width == 1320 && i.height == 920, "size \(i.width)x\(i.height)")
  check(i.tiff[kCGImagePropertyTIFFModel as String] as? String == "iPhone 11", "model kept")
  let (r, g, b) = pixel(dst, 10, 10)
  check(r > 245 && g > 245 && b > 245, "border still white: \(r),\(g),\(b)")
}

test("blur on rotated photo uses upright coordinates and maxSide") {
  let dst = out.appendingPathComponent("blur2.png")
  try? FileManager.default.removeItem(at: dst)
  // Top half of the upright (portrait) photo.
  let blur = BlurSpec(strength: 0.03, strokes: [.init(radius: 0.2, erase: false, points: [0.0, 0.2, 1.0, 0.2])])
  try ImageEncoder.encode(source: photoRot, to: dst, format: .png, quality: 90, maxSide: 600, blur: blur)
  let plain = out.appendingPathComponent("blur2-plain.png")
  try? FileManager.default.removeItem(at: plain)
  try ImageEncoder.encode(source: photoRot, to: plain, format: .png, quality: 90, maxSide: 600)
  let i = info(dst)!
  check(i.width == 400 && i.height == 600, "size \(i.width)x\(i.height)")
  func img(_ u: URL) -> CGImage { CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(u as CFURL, nil)!, 0, nil)! }
  let a = rgba(img(plain))
  let b = rgba(img(dst))
  func diff(_ y0: Int, _ y1: Int) -> Int {
    var d = 0
    for y in y0..<y1 { for x in 0..<400 { d = max(d, abs(Int(a[(y * 400 + x) * 4 + 2]) - Int(b[(y * 400 + x) * 4 + 2]))) } }
    return d
  }
  check(diff(100, 140) > 20, "top changed: \(diff(100, 140))")
  check(diff(450, 600) <= 2, "bottom unchanged: \(diff(450, 600))")
}

// MARK: - Collage

print("CollageSpec (macOS)")

/// Same cases as test/collage_test.dart and CollageGeometryTest.java.
test("collage geometry matches the shared cases") {
  typealias C = (c: Int, r: Int, ratio: Double, long: Int, gap: Double, want: [Int])
  let cases: [C] = [
    (2, 1, 1, 1000, 0.02, [1000, 1000, 20, 20, 470, 960, 510, 20, 470, 960]),
    (3, 1, 16.0 / 9, 1920, 0.01, [1920, 1080, 19, 19, 615, 1042, 653, 19, 614, 1042, 1286, 19, 615, 1042]),
    (1, 3, 0.8, 1000, 0.03, [800, 1000, 30, 30, 740, 293, 30, 353, 740, 294, 30, 677, 740, 293]),
    (2, 2, 1, 1001, 0.02, [1001, 1001, 20, 20, 471, 471, 511, 20, 470, 471, 20, 511, 471, 470, 511, 511, 470, 470]),
    (5, 1, 1, 1000, 0, [1000, 1000, 0, 0, 200, 1000, 200, 0, 200, 1000, 400, 0, 200, 1000, 600, 0, 200, 1000, 800, 0, 200, 1000]),
    (1, 2, 9.0 / 16, 1600, 0.05, [900, 1600, 80, 80, 740, 680, 80, 840, 740, 680]),
  ]
  for c in cases {
    let g = CollageSpec(cols: c.c, rows: c.r, gap: c.gap, rgb: 0, ratio: c.ratio).geometry(longSide: c.long)
    let got = [g.width, g.height] + g.cells.flatMap { [$0.x, $0.y, $0.w, $0.h] }
    check(got == c.want, "\(c.c)x\(c.r) r\(c.ratio) \(c.long) g\(c.gap): \(got) != \(c.want)")
  }
  func cover(_ a: Int, _ b: Int, _ c: Int, _ d: Int, _ fx: Double = 0.5, _ fy: Double = 0.5) -> [Int] {
    let r = CollageSpec.cover(a, b, c, d, fx, fy)
    return [r.x, r.y, r.w, r.h]
  }
  check(cover(4000, 3000, 500, 1000) == [1250, 0, 1500, 3000], "cover wide")
  check(cover(3000, 4000, 1000, 500) == [0, 1250, 3000, 1500], "cover tall")
  check(cover(1000, 1000, 300, 300) == [0, 0, 1000, 1000], "cover same")
  check(cover(1200, 800, 601, 400) == [0, 0, 1200, 799], "cover rounding")
  check(cover(4000, 3000, 500, 1000, 0, 0) == [0, 0, 1500, 3000], "crop left")
  check(cover(4000, 3000, 500, 1000, 1, 1) == [2500, 0, 1500, 3000], "crop right")
  check(cover(4000, 3000, 500, 1000, 0.3, 0.9) == [750, 0, 1500, 3000], "crop 0.3")
  check(cover(3000, 4000, 1000, 500, 0.1, 0.75) == [0, 1875, 3000, 1500], "crop 0.75 down")
  check(cover(3000, 4000, 1000, 500, 0.5, 2) == [0, 2500, 3000, 1500], "crop clamped")
}

test("collage channel arguments") {
  let c = CollageSpec.from(["cols": 1, "rows": 3, "gap": 0.01, "color": 0x1F2A44, "ratio": 0.5625, "crops": [0.2, 1.0]])
  check(
    c == CollageSpec(cols: 1, rows: 3, gap: 0.01, rgb: 0x1F2A44, ratio: 0.5625, crops: [0.2, 1.0]),
    "parsed \(String(describing: c))")
  if let c { check(c.crop(0) == (0.2, 1.0) && c.crop(1) == (0.5, 0.5), "crop per photo, missing = centre") }
  check(CollageSpec.from(["cols": 0, "rows": 1, "ratio": 1]) == nil, "cols 0")
  check(CollageSpec.from(["cols": 2, "rows": 1]) == nil, "no ratio")
}

test("collage renders photos into cells over the gap colour, first photo's metadata") {
  let spec = CollageSpec(cols: 2, rows: 1, gap: 0.05, rgb: 0x000000, ratio: 1)
  let (img, props) = try spec.render(sources: [photoJpg, photoRot], longSide: 600)
  check(img.width == 600 && img.height == 600, "size \(img.width)x\(img.height)")
  let px = rgba(img)
  func at(_ x: Int, _ y: Int) -> (Int, Int, Int) {
    let i = (y * 600 + x) * 4
    return (Int(px[i]), Int(px[i + 1]), Int(px[i + 2]))
  }
  let gap = at(10, 300)
  check(gap.0 < 5 && gap.1 < 5 && gap.2 < 5, "outer gap is black: \(gap)")
  let mid = at(300, 300)
  check(mid.0 < 5 && mid.1 < 5 && mid.2 < 5, "middle gap is black: \(mid)")
  let a = at(150, 300)
  let b = at(450, 300)
  check(a.0 + a.1 + a.2 > 30 && b.0 + b.1 + b.2 > 30, "cells hold photos: \(a) \(b)")
  let tiff = props[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
  check(tiff[kCGImagePropertyTIFFModel as String] as? String == "iPhone 11", "first photo metadata")

  let dst = out.appendingPathComponent("collage.jpg")
  try? FileManager.default.removeItem(at: dst)
  let n = try ImageEncoder.write(img, metadataFrom: props, to: dst, format: .jpeg, quality: 90)
  let i = info(dst)!
  check(n > 0 && i.width == 600 && i.height == 600 && i.orientation == 1, "written \(i.width)x\(i.height)")
}

test("crop position picks the part of the photo") {
  // A 1200x800 photo in a square cell: left crop vs right crop differ, centre in between.
  func cellPixels(_ fx: Double) throws -> [UInt8] {
    let spec = CollageSpec(cols: 1, rows: 1, gap: 0, rgb: 0, ratio: 1, crops: [fx, 0.5])
    return rgba(try spec.render(sources: [photoJpg], longSide: 400).0)
  }
  let left = try cellPixels(0)
  let right = try cellPixels(1)
  // makePhoto: red grows from left to right.
  check(Int(left[(200 * 400 + 200) * 4]) + 40 < Int(right[(200 * 400 + 200) * 4]), "right crop is redder")
}

test("rotated photo is upright in its cell") {
  // One cell with the photo's own ratio: same pixels as the photo encoded alone.
  let spec = CollageSpec(cols: 1, rows: 1, gap: 0, rgb: 0xFFFFFF, ratio: 800.0 / 1200)
  let (img, _) = try spec.render(sources: [photoRot], longSide: 1200)
  let alone = out.appendingPathComponent("rot-alone.png")
  try? FileManager.default.removeItem(at: alone)
  try ImageEncoder.encode(source: photoRot, to: alone, format: .png, quality: 90, maxSide: 0)
  let a = rgba(CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(alone as CFURL, nil)!, 0, nil)!)
  let b = rgba(img)
  check(img.width == 800 && img.height == 1200, "size \(img.width)x\(img.height)")
  var d = 0
  for (x, y) in [(100, 100), (700, 200), (400, 600), (50, 1150)] {
    let i = (y * 800 + x) * 4
    d = max(d, abs(Int(a[i]) - Int(b[i])) + abs(Int(a[i + 1]) - Int(b[i + 1])))
  }
  check(d < 30, "same pixels as the upright photo: \(d)")
}

print("\(passed) passed, \(failed) failed")
exit(failed == 0 ? 0 : 1)
