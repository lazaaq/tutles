package com.lazaaq.tutles

import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ImageDecoder
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Rect
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.provider.MediaStore
import androidx.exifinterface.media.ExifInterface
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * Native photo renderer.
 *
 * Channel `tutles/native`:
 * - `render` {id, quality, maxSide, format, border} -> {newId, inBytes, outBytes}
 *   Reads the gallery photo `id` (MediaStore _ID, same as photo_manager), applies EXIF
 *   orientation to the pixels, draws the `border` {width, color, ratio} (see [BorderLayout]),
 *   limits the long side of the result to `maxSide` (0 = original, never enlarged) and saves a
 *   new photo in Pictures/tutles with the same date and EXIF. `format` "same" keeps JPG/PNG/WEBP;
 *   HEIC and others become JPG. The original is never changed.
 */
class PhotoRenderer(private val context: Context) : MethodChannel.MethodCallHandler {
    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val isScopedStorage = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q
    private val filesUri: Uri = MediaStore.Files.getContentUri("external")

    companion object {
        private const val ALBUM = "tutles"

        private val EXIF_TAGS = listOf(
            ExifInterface.TAG_DATETIME, ExifInterface.TAG_DATETIME_ORIGINAL,
            ExifInterface.TAG_DATETIME_DIGITIZED, ExifInterface.TAG_OFFSET_TIME,
            ExifInterface.TAG_OFFSET_TIME_ORIGINAL, ExifInterface.TAG_OFFSET_TIME_DIGITIZED,
            ExifInterface.TAG_SUBSEC_TIME_ORIGINAL, ExifInterface.TAG_MAKE, ExifInterface.TAG_MODEL,
            ExifInterface.TAG_LENS_MAKE, ExifInterface.TAG_LENS_MODEL,
            ExifInterface.TAG_F_NUMBER, ExifInterface.TAG_APERTURE_VALUE, ExifInterface.TAG_EXPOSURE_TIME,
            ExifInterface.TAG_SHUTTER_SPEED_VALUE, ExifInterface.TAG_PHOTOGRAPHIC_SENSITIVITY,
            ExifInterface.TAG_FOCAL_LENGTH, ExifInterface.TAG_FOCAL_LENGTH_IN_35MM_FILM,
            ExifInterface.TAG_EXPOSURE_BIAS_VALUE, ExifInterface.TAG_FLASH,
            ExifInterface.TAG_WHITE_BALANCE, ExifInterface.TAG_ARTIST, ExifInterface.TAG_COPYRIGHT,
            ExifInterface.TAG_GPS_LATITUDE, ExifInterface.TAG_GPS_LATITUDE_REF,
            ExifInterface.TAG_GPS_LONGITUDE, ExifInterface.TAG_GPS_LONGITUDE_REF,
            ExifInterface.TAG_GPS_ALTITUDE, ExifInterface.TAG_GPS_ALTITUDE_REF,
            ExifInterface.TAG_GPS_TIMESTAMP, ExifInterface.TAG_GPS_DATESTAMP,
        )
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "render" -> {
                val id = call.argument<String>("id")?.toLongOrNull()
                    ?: return result.error("bad_args", "id wajib diisi", null)
                val quality = call.argument<Int>("quality") ?: 90
                val maxSide = call.argument<Int>("maxSide") ?: 0
                val format = call.argument<String>("format")
                val border = BorderLayout.Spec.from(call.argument<Any>("border"))
                executor.execute {
                    try {
                        val value = render(id, quality, maxSide, format, border)
                        main.post { result.success(value) }
                    } catch (t: Throwable) {
                        main.post { result.error("render_failed", ImageFormats.errorMessage(t), null) }
                    }
                }
            }
            else -> result.notImplemented()
        }
    }

    // ------------------------------------------------------------- source

    private data class Source(
        val uri: Uri,
        val name: String,
        val size: Long,
        /** Android 9: absolute file path. */
        val dataPath: String?,
        val dateTaken: Long?,
    )

    @Suppress("DEPRECATION")
    private fun querySource(id: Long): Source {
        val uri = ContentUris.withAppendedId(filesUri, id)
        val projection = arrayOf(
            MediaStore.MediaColumns.DISPLAY_NAME,
            MediaStore.MediaColumns.SIZE,
            MediaStore.MediaColumns.DATA,
            MediaStore.Images.ImageColumns.DATE_TAKEN,
        )
        context.contentResolver.query(uri, projection, null, null, null)?.use { c ->
            if (c.moveToFirst()) {
                val path = c.getString(2)
                return Source(
                    uri = uri,
                    name = c.getString(0) ?: path?.substringAfterLast('/') ?: "photo",
                    size = c.getLong(1),
                    dataPath = if (isScopedStorage) null else path,
                    dateTaken = if (c.isNull(3)) null else c.getLong(3),
                )
            }
        }
        throw IllegalStateException("Foto tidak ditemukan")
    }

    /** Android 10+: ask for the original GPS data (needs ACCESS_MEDIA_LOCATION). */
    private fun readUri(src: Source): Uri = if (isScopedStorage) {
        try { MediaStore.setRequireOriginal(src.uri) } catch (_: Throwable) { src.uri }
    } else src.uri

    private fun openFd(src: Source): ParcelFileDescriptor {
        src.dataPath?.let { path ->
            val f = File(path)
            if (f.canRead()) return ParcelFileDescriptor.open(f, ParcelFileDescriptor.MODE_READ_ONLY)
        }
        return context.contentResolver.openFileDescriptor(readUri(src), "r")
            ?: throw IllegalStateException("Tidak bisa membuka foto")
    }

    // ------------------------------------------------------------- render

    private fun render(
        id: Long, quality: Int, maxSide: Int, format: String?, border: BorderLayout.Spec?,
    ): Map<String, Any> {
        val src = querySource(id)
        val fmt = ImageFormats.resolve(format, src.name)
        val tmp = File(context.cacheDir, "${UUID.randomUUID()}.${ImageFormats.extension(fmt)}")
        try {
            val (bmp, rotated) = decode(src, maxSide)
            var bitmap = if (rotated) bmp else applyOrientation(bmp, sourceOrientation(src))
            // Pixels are upright now; every gallery shows them right even if it ignores EXIF.
            if (border != null) bitmap = addBorder(bitmap, border, maxSide)
            if (fmt == ImageFormats.JPEG && bitmap.hasAlpha()) bitmap = flattenOnWhite(bitmap)
            tmp.outputStream().use { bitmap.compress(compressFormat(fmt), quality.coerceIn(1, 100), it) }
            val width = bitmap.width
            val height = bitmap.height
            bitmap.recycle()

            copyExif(src, tmp, width, height)
            val newId = insert(tmp, src, fmt)
            return mapOf("newId" to newId, "inBytes" to src.size, "outBytes" to tmp.length())
        } finally {
            tmp.delete()
        }
    }

    /** Photo centred on a canvas in the border colour; the canvas is limited to [maxSide]. */
    private fun addBorder(bmp: Bitmap, spec: BorderLayout.Spec, maxSide: Int): Bitmap {
        val l = BorderLayout.compute(bmp.width, bmp.height, spec.fraction, spec.ratio, maxSide)
        val out = Bitmap.createBitmap(l.canvasWidth, l.canvasHeight, Bitmap.Config.ARGB_8888)
        Canvas(out).apply {
            drawColor(spec.argb())
            drawBitmap(bmp, null, Rect(l.x, l.y, l.x + l.width, l.y + l.height), Paint(Paint.FILTER_BITMAP_FLAG))
        }
        bmp.recycle()
        return out
    }

    @Suppress("DEPRECATION")
    private fun compressFormat(fmt: String): Bitmap.CompressFormat = when (fmt) {
        ImageFormats.PNG -> Bitmap.CompressFormat.PNG
        ImageFormats.WEBP ->
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) Bitmap.CompressFormat.WEBP_LOSSY
            else Bitmap.CompressFormat.WEBP
        else -> Bitmap.CompressFormat.JPEG
    }

    /** JPEG has no transparency: white background, not black. */
    private fun flattenOnWhite(bmp: Bitmap): Bitmap {
        val out = Bitmap.createBitmap(bmp.width, bmp.height, Bitmap.Config.ARGB_8888)
        Canvas(out).apply {
            drawColor(Color.WHITE)
            drawBitmap(bmp, 0f, 0f, null)
        }
        bmp.recycle()
        return out
    }

    private fun sampleFor(long: Int, maxSide: Int): Int {
        var sample = 1
        if (maxSide > 0) while (long / (sample * 2) >= maxSide) sample *= 2
        return sample
    }

    /** @return bitmap + whether the decoder already rotated the pixels per EXIF. */
    private fun decode(src: Source, maxSide: Int): Pair<Bitmap, Boolean> {
        // 1) BitmapFactory: JPEG, PNG, WEBP, and HEIC on most phones. Ignores EXIF orientation.
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        openFd(src).use { BitmapFactory.decodeFileDescriptor(it.fileDescriptor, null, bounds) }
        if (bounds.outWidth > 0 && bounds.outHeight > 0) {
            val opts = BitmapFactory.Options().apply {
                inSampleSize = sampleFor(max(bounds.outWidth, bounds.outHeight), maxSide)
                inPreferredConfig = Bitmap.Config.ARGB_8888
            }
            val bmp = openFd(src).use { BitmapFactory.decodeFileDescriptor(it.fileDescriptor, null, opts) }
            if (bmp != null) return Pair(fit(bmp, maxSide), false)
        }

        // 2) ImageDecoder (applies orientation itself).
        val source = src.dataPath?.let { ImageDecoder.createSource(File(it)) }
            ?: ImageDecoder.createSource(context.contentResolver, readUri(src))
        val bmp = try {
            ImageDecoder.decodeBitmap(source) { decoder, info, _ ->
                decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                val w = info.size.width
                val h = info.size.height
                val long = max(w, h)
                if (maxSide in 1 until long) {
                    val s = maxSide.toFloat() / long
                    decoder.setTargetSize((w * s).roundToInt(), (h * s).roundToInt())
                }
            }
        } catch (t: Throwable) {
            throw IllegalStateException("Format foto ini tidak didukung di perangkat ini")
        }
        return Pair(bmp, true)
    }

    private fun fit(bmp: Bitmap, maxSide: Int): Bitmap {
        val long = max(bmp.width, bmp.height)
        if (maxSide <= 0 || long <= maxSide) return bmp
        val s = maxSide.toFloat() / long
        val scaled = Bitmap.createScaledBitmap(bmp, (bmp.width * s).roundToInt(), (bmp.height * s).roundToInt(), true)
        if (scaled != bmp) bmp.recycle()
        return scaled
    }

    private fun sourceOrientation(src: Source): Int = try {
        openFd(src).use {
            ExifInterface(it.fileDescriptor)
                .getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
        }
    } catch (_: Throwable) {
        ExifInterface.ORIENTATION_NORMAL
    }

    /** Rotate/mirror pixels per EXIF Orientation (1..8). */
    private fun applyOrientation(bmp: Bitmap, orientation: Int): Bitmap {
        val m = Matrix()
        when (orientation) {
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> m.setScale(-1f, 1f)
            ExifInterface.ORIENTATION_ROTATE_180 -> m.setRotate(180f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> m.setScale(1f, -1f)
            ExifInterface.ORIENTATION_TRANSPOSE -> { m.setRotate(90f); m.postScale(-1f, 1f) }
            ExifInterface.ORIENTATION_ROTATE_90 -> m.setRotate(90f)
            ExifInterface.ORIENTATION_TRANSVERSE -> { m.setRotate(-90f); m.postScale(-1f, 1f) }
            ExifInterface.ORIENTATION_ROTATE_270 -> m.setRotate(-90f)
            else -> return bmp
        }
        val out = Bitmap.createBitmap(bmp, 0, 0, bmp.width, bmp.height, m, true)
        if (out != bmp) bmp.recycle()
        return out
    }

    private fun copyExif(src: Source, out: File, width: Int, height: Int) {
        try {
            val srcExif = openFd(src).use { ExifInterface(it.fileDescriptor) }
            val dst = ExifInterface(out.absolutePath)
            for (tag in EXIF_TAGS) {
                srcExif.getAttribute(tag)?.let { v -> try { dst.setAttribute(tag, v) } catch (_: Throwable) {} }
            }
            dst.setAttribute(ExifInterface.TAG_ORIENTATION, "1") // pixels already rotated
            dst.setAttribute(ExifInterface.TAG_PIXEL_X_DIMENSION, width.toString())
            dst.setAttribute(ExifInterface.TAG_PIXEL_Y_DIMENSION, height.toString())
            dst.setAttribute(ExifInterface.TAG_SOFTWARE, "tutles")
            dst.saveAttributes()
        } catch (_: Throwable) {
            // Metadata is optional; the photo is still saved.
        }
    }

    // --------------------------------------------------------------- save

    private fun insert(file: File, src: Source, fmt: String): String =
        if (isScopedStorage) insertScoped(file, src, fmt) else insertLegacy(file, src, fmt)

    /** Android 9: write to Pictures/tutles, then register in MediaStore. */
    @Suppress("DEPRECATION")
    private fun insertLegacy(file: File, src: Source, fmt: String): String {
        val dir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES), ALBUM)
            .apply { mkdirs() }
        val target = File(dir, ImageFormats.uniqueName(ImageFormats.outputName(src.name, fmt)) { File(dir, it).exists() })
        file.copyTo(target)
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DATA, target.absolutePath)
            put(MediaStore.Images.Media.DISPLAY_NAME, target.name)
            put(MediaStore.Images.Media.MIME_TYPE, ImageFormats.mime(fmt))
            put(MediaStore.Images.Media.SIZE, target.length())
            src.dateTaken?.let { put(MediaStore.Images.Media.DATE_TAKEN, it) }
            put(MediaStore.Images.Media.DATE_ADDED, System.currentTimeMillis() / 1000)
            put(MediaStore.Images.Media.DATE_MODIFIED, target.lastModified() / 1000)
        }
        val newUri = try {
            context.contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
        } catch (_: Throwable) { null }
        if (newUri == null) {
            target.delete()
            throw IllegalStateException("Gagal menyimpan foto ke galeri")
        }
        MediaScannerConnection.scanFile(context, arrayOf(target.absolutePath), arrayOf(ImageFormats.mime(fmt)), null)
        return ContentUris.parseId(newUri).toString()
    }

    /** Android 10+: scoped storage via MediaStore. */
    private fun insertScoped(file: File, src: Source, fmt: String): String {
        val cr = context.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, ImageFormats.outputName(src.name, fmt))
            put(MediaStore.Images.Media.MIME_TYPE, ImageFormats.mime(fmt))
            put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/$ALBUM/")
            src.dateTaken?.let { put(MediaStore.Images.Media.DATE_TAKEN, it) }
            put(MediaStore.Images.Media.IS_PENDING, 1)
        }
        val collection = MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val newUri = cr.insert(collection, values) ?: throw IllegalStateException("Gagal menyimpan foto")
        try {
            cr.openOutputStream(newUri)?.use { out -> file.inputStream().use { it.copyTo(out) } }
                ?: throw IllegalStateException("Gagal menulis foto")
            cr.update(newUri, ContentValues().apply { put(MediaStore.Images.Media.IS_PENDING, 0) }, null, null)
        } catch (t: Throwable) {
            cr.delete(newUri, null, null)
            throw t
        }
        return ContentUris.parseId(newUri).toString()
    }
}
