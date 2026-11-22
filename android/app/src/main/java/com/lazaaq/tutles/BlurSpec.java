package com.lazaaq.tutles;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Map;

/**
 * Gaussian blur: {@code strength} inside brush strokes, {@code background} outside (0 = sharp),
 * with a soft edge of {@code feather}. Geometry matches {@code BlurOptions} in lib/blur.dart and
 * {@code BlurSpec} in ios/Runner/ImageEncoder.swift.
 */
public final class BlurSpec {
    public static final double DEFAULT_FEATHER = 0.012;
    public static final double MAX_STRENGTH = 0.1;

    public static final class Stroke {
        /** Brush radius as a fraction of the photo's long side. */
        public final double radius;
        /** Eraser: removes blur painted by earlier strokes. */
        public final boolean erase;
        /** x0, y0, x1, y1, … relative to the upright photo (0..1, origin top-left). */
        public final double[] points;

        public Stroke(double radius, boolean erase, double[] points) {
            this.radius = radius;
            this.erase = erase;
            this.points = points;
        }
    }

    /** Blur sigma inside the strokes, as a fraction of the photo's long side. */
    public final double strength;
    /** Blur sigma outside the strokes; 0 = sharp. */
    public final double background;
    /** Sigma of the soft edge (the mask is blurred), as a fraction of the long side. */
    public final double feather;
    public final List<Stroke> strokes;

    public BlurSpec(double strength, double background, double feather, List<Stroke> strokes) {
        this.strength = strength;
        this.background = background;
        this.feather = feather;
        this.strokes = Collections.unmodifiableList(new ArrayList<>(strokes));
    }

    public boolean hasPaint() {
        for (Stroke s : strokes) if (!s.erase) return true;
        return false;
    }

    /** The result differs from the photo. */
    public boolean changesPhoto() {
        return background > 0 || (strength > 0 && hasPaint());
    }

    /**
     * From the channel argument {@code {strength, background, feather, strokes: [{radius, erase,
     * points}]}}; null when absent, malformed, or nothing would change.
     */
    public static BlurSpec from(Object arg) {
        if (!(arg instanceof Map)) return null;
        Map<?, ?> m = (Map<?, ?>) arg;
        Object s = m.get("strength");
        if (!(s instanceof Number) || ((Number) s).doubleValue() < 0) return null;
        Object list = m.get("strokes");
        List<Stroke> strokes = new ArrayList<>();
        for (Object item : list instanceof List ? (List<?>) list : Collections.emptyList()) {
            if (!(item instanceof Map)) continue;
            Map<?, ?> d = (Map<?, ?>) item;
            Object r = d.get("radius");
            Object raw = d.get("points");
            if (!(r instanceof Number) || ((Number) r).doubleValue() <= 0 || !(raw instanceof List)) continue;
            List<Double> pts = new ArrayList<>();
            for (Object p : (List<?>) raw) if (p instanceof Number) pts.add(((Number) p).doubleValue());
            int n = pts.size() / 2 * 2;
            if (n == 0) continue;
            double[] points = new double[n];
            for (int i = 0; i < n; i++) points[i] = pts.get(i);
            boolean erase = Boolean.TRUE.equals(d.get("erase"));
            strokes.add(new Stroke(Math.min(((Number) r).doubleValue(), 1), erase, points));
        }
        BlurSpec spec = new BlurSpec(
                clamp(((Number) s).doubleValue()),
                clamp(m.get("background") instanceof Number ? ((Number) m.get("background")).doubleValue() : 0),
                clamp(m.get("feather") instanceof Number ? ((Number) m.get("feather")).doubleValue() : DEFAULT_FEATHER),
                strokes);
        return spec.changesPhoto() ? spec : null;
    }

    private static double clamp(double v) {
        return Math.max(0, Math.min(v, MAX_STRENGTH));
    }

    public double sigma(int w, int h) {
        return strength * Math.max(w, h);
    }

    public double backgroundSigma(int w, int h) {
        return background * Math.max(w, h);
    }

    public double featherSigma(int w, int h) {
        return feather * Math.max(w, h);
    }

    /**
     * Pixel rectangle {left, top, right, bottom} (right/bottom exclusive) that the blur can
     * change: painted strokes plus three feather sigmas, clipped to the photo. null when empty.
     */
    public int[] bounds(int w, int h) {
        double longSide = Math.max(w, h);
        double pad = 3 * featherSigma(w, h);
        double l = Double.MAX_VALUE, t = Double.MAX_VALUE, r = -Double.MAX_VALUE, b = -Double.MAX_VALUE;
        for (Stroke s : strokes) {
            if (s.erase) continue;
            double e = s.radius * longSide + pad;
            for (int i = 0; i < s.points.length; i += 2) {
                double x = s.points[i] * w;
                double y = s.points[i + 1] * h;
                l = Math.min(l, x - e);
                t = Math.min(t, y - e);
                r = Math.max(r, x + e);
                b = Math.max(b, y + e);
            }
        }
        if (l == Double.MAX_VALUE) return null;
        int left = (int) Math.max(0, Math.floor(l));
        int top = (int) Math.max(0, Math.floor(t));
        int right = (int) Math.min(w, Math.ceil(r));
        int bottom = (int) Math.min(h, Math.ceil(b));
        if (left >= right || top >= bottom) return null;
        return new int[] {left, top, right, bottom};
    }

    /**
     * Coverage (0..1, hard edge anti-aliased over one cell) on a grid of {@code mw x mh} cells:
     * cell (i, j) is centred on photo pixel coordinate ({@code (i + 0.5) / sx + ox},
     * {@code (j + 0.5) / sy + oy}). Strokes apply in order; erasers clear earlier paint.
     */
    public float[] mask(int w, int h, int ox, int oy, int mw, int mh, double sx, double sy) {
        float[] m = new float[mw * mh];
        double longSide = Math.max(w, h);
        double s = (sx + sy) / 2;
        for (Stroke st : strokes) {
            double r = st.radius * longSide * s;
            int n = st.points.length / 2;
            for (int k = 0; k < Math.max(1, n - 1); k++) {
                int k2 = Math.min(k + 1, n - 1); // single point: zero-length segment = dot
                segment(m, mw, mh,
                        (st.points[2 * k] * w - ox) * sx, (st.points[2 * k + 1] * h - oy) * sy,
                        (st.points[2 * k2] * w - ox) * sx, (st.points[2 * k2 + 1] * h - oy) * sy,
                        r, st.erase);
            }
        }
        return m;
    }

    private static void segment(float[] m, int mw, int mh, double ax, double ay, double bx, double by,
            double r, boolean erase) {
        int x0 = (int) Math.max(0, Math.floor(Math.min(ax, bx) - r - 1));
        int y0 = (int) Math.max(0, Math.floor(Math.min(ay, by) - r - 1));
        int x1 = (int) Math.min(mw - 1, Math.ceil(Math.max(ax, bx) + r + 1));
        int y1 = (int) Math.min(mh - 1, Math.ceil(Math.max(ay, by) + r + 1));
        double dx = bx - ax, dy = by - ay;
        double len2 = dx * dx + dy * dy;
        for (int j = y0; j <= y1; j++) {
            double py = j + 0.5;
            for (int i = x0; i <= x1; i++) {
                double px = i + 0.5;
                double t = len2 == 0 ? 0 : Math.max(0, Math.min(1, ((px - ax) * dx + (py - ay) * dy) / len2));
                double ex = px - (ax + t * dx), ey = py - (ay + t * dy);
                double cov = r - Math.sqrt(ex * ex + ey * ey) + 0.5;
                if (cov <= 0) continue;
                float c = (float) Math.min(1, cov);
                int idx = j * mw + i;
                m[idx] = erase ? Math.min(m[idx], 1 - c) : Math.max(m[idx], c);
            }
        }
    }
}
