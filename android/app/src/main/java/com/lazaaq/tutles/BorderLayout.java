package com.lazaaq.tutles;

import java.util.Map;

/**
 * Plain border around a photo. Geometry matches {@code BorderLayout} in lib/jobs.dart and
 * {@code BorderSpec} in ios/Runner/ImageEncoder.swift.
 */
public final class BorderLayout {
    /** Canvas size. */
    public final int canvasWidth;
    public final int canvasHeight;
    /** Photo rectangle inside the canvas, origin top-left. */
    public final int x;
    public final int y;
    public final int width;
    public final int height;

    BorderLayout(int canvasWidth, int canvasHeight, int x, int y, int width, int height) {
        this.canvasWidth = canvasWidth;
        this.canvasHeight = canvasHeight;
        this.x = x;
        this.y = y;
        this.width = width;
        this.height = height;
    }

    /** Border options from the channel argument {@code {width, color, ratio}}. */
    public static final class Spec {
        /** Border on each side, as a fraction of the photo's long side. */
        public final double fraction;
        /** 0xRRGGBB, always opaque. */
        public final int rgb;
        /** Canvas width / height; 0 = photo plus border. */
        public final double ratio;

        public Spec(double fraction, int rgb, double ratio) {
            this.fraction = fraction;
            this.rgb = rgb;
            this.ratio = ratio;
        }

        /** null when absent or malformed. */
        public static Spec from(Object arg) {
            if (!(arg instanceof Map)) return null;
            Map<?, ?> m = (Map<?, ?>) arg;
            Object w = m.get("width");
            if (!(w instanceof Number) || ((Number) w).doubleValue() < 0) return null;
            Object c = m.get("color");
            Object r = m.get("ratio");
            return new Spec(
                    Math.min(((Number) w).doubleValue(), 1),
                    c instanceof Number ? ((Number) c).intValue() & 0xFFFFFF : 0xFFFFFF,
                    r instanceof Number ? Math.max(((Number) r).doubleValue(), 0) : 0);
        }

        /** Opaque ARGB colour for Canvas. */
        public int argb() {
            return 0xFF000000 | rgb;
        }
    }

    /**
     * Border on each side, widen/heighten to {@code ratio}, then shrink everything so the long
     * side is at most {@code maxSide} (0 = no limit; never enlarged).
     */
    public static BorderLayout compute(int w, int h, double fraction, double ratio, int maxSide) {
        int b = (int) Math.round(fraction * Math.max(w, h));
        int cw = w + 2 * b;
        int ch = h + 2 * b;
        if (ratio > 0) {
            if ((double) cw / ch < ratio) {
                cw = (int) Math.round(ch * ratio);
            } else {
                ch = (int) Math.round(cw / ratio);
            }
        }
        int longSide = Math.max(cw, ch);
        double s = maxSide > 0 && longSide > maxSide ? (double) maxSide / longSide : 1;
        int canvasW = (int) Math.round(cw * s);
        int canvasH = (int) Math.round(ch * s);
        int iw = Math.min((int) Math.round(w * s), canvasW);
        int ih = Math.min((int) Math.round(h * s), canvasH);
        return new BorderLayout(canvasW, canvasH, (canvasW - iw) / 2, (canvasH - ih) / 2, iw, ih);
    }

    @Override
    public String toString() {
        return canvasWidth + "x" + canvasHeight + " photo " + width + "x" + height + " at " + x + "," + y;
    }
}
