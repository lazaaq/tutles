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

print("\(passed) passed, \(failed) failed")
exit(failed == 0 ? 0 : 1)
