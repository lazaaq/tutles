package com.lazaaq.tutles;

import java.util.Locale;
import java.util.function.Predicate;

/** Output format rules for saving edited photos (pure Java, unit-tested). */
public final class ImageFormats {
    private ImageFormats() {}

    public static final String JPEG = "jpeg";
    public static final String PNG = "png";
    public static final String WEBP = "webp";

    private static String ext(String name) {
        int dot = name == null ? -1 : name.lastIndexOf('.');
        return dot < 0 ? "" : name.substring(dot + 1).toLowerCase(Locale.ROOT);
    }

    /**
     * {@code format} "jpeg" / "png" / "webp" is used as is; "same" (or anything else) keeps the
     * source format when Android can write it. HEIC/HEIF and others become JPEG.
     */
    public static String resolve(String format, String sourceName) {
        if (JPEG.equals(format) || PNG.equals(format) || WEBP.equals(format)) return format;
        switch (ext(sourceName)) {
            case "png": return PNG;
            case "webp": return WEBP;
            default: return JPEG;
        }
    }

    public static String extension(String format) {
        switch (format) {
            case PNG: return "png";
            case WEBP: return "webp";
            default: return "jpg";
        }
    }

    public static String mime(String format) {
        switch (format) {
            case PNG: return "image/png";
            case WEBP: return "image/webp";
            default: return "image/jpeg";
        }
    }

    /** Output name: source base name + new extension ("IMG_1.HEIC" -> "IMG_1.jpg"). */
    public static String outputName(String sourceName, String format) {
        String name = sourceName == null || sourceName.isEmpty() ? "photo" : sourceName;
        int dot = name.lastIndexOf('.');
        String base = dot > 0 ? name.substring(0, dot) : name;
        return base + "." + extension(format);
    }

    /** {@code first} if free, else "base (1).ext", "base (2).ext", … */
    public static String uniqueName(String first, Predicate<String> exists) {
        if (!exists.test(first)) return first;
        int dot = first.lastIndexOf('.');
        String base = dot > 0 ? first.substring(0, dot) : first;
        String ext = dot > 0 ? first.substring(dot) : "";
        for (int n = 1; ; n++) {
            String candidate = base + " (" + n + ")" + ext;
            if (!exists.test(candidate)) return candidate;
        }
    }

    /** User-facing message for a conversion failure. */
    public static String errorMessage(Throwable t) {
        if (t instanceof OutOfMemoryError) {
            return "Foto terlalu besar untuk memori perangkat. Pilih ukuran yang lebih kecil.";
        }
        String m = t.getMessage();
        return m == null || m.isEmpty() ? t.getClass().getSimpleName() : m;
    }
}
