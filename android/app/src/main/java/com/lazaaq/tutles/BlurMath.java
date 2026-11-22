package com.lazaaq.tutles;

/** Pixel maths for {@link BlurSpec}, without Android classes so it runs in JUnit. */
public final class BlurMath {
    private BlurMath() {}

    /** Radii of three box blurs that together approximate a Gaussian of {@code sigma}. */
    public static int[] boxRadii(double sigma) {
        final int n = 3;
        double ideal = Math.sqrt(12 * sigma * sigma / n + 1);
        int wl = (int) Math.floor(ideal);
        if (wl % 2 == 0) wl--;
        if (wl < 1) wl = 1;
        int wu = wl + 2;
        double mIdeal = (12 * sigma * sigma - n * wl * wl - 4.0 * n * wl - 3.0 * n) / (-4.0 * wl - 4);
        int m = (int) Math.round(mIdeal);
        int[] r = new int[n];
        for (int i = 0; i < n; i++) r[i] = ((i < m ? wl : wu) - 1) / 2;
        return r;
    }

    /** Gaussian-like blur of ARGB pixels in place; edges are clamped. */
    public static void blurArgb(int[] px, int w, int h, double sigma) {
        if (sigma <= 0 || w <= 0 || h <= 0) return;
        int[] tmp = new int[px.length];
        for (int r : boxRadii(sigma)) {
            if (r <= 0) continue;
            boxArgb(px, tmp, w, h, r, 1, w); // rows
            boxArgb(tmp, px, h, w, r, w, 1); // columns
        }
    }

    /**
     * One box pass along lines: {@code lines} lines of {@code len} pixels, pixel k of line l at
     * {@code l * lineStep + k * step}.
     */
    private static void boxArgb(int[] src, int[] dst, int len, int lines, int r, int step, int lineStep) {
        int div = 2 * r + 1;
        for (int l = 0; l < lines; l++) {
            int base = l * lineStep;
            int sa = 0, sr = 0, sg = 0, sb = 0;
            for (int k = -r; k <= r; k++) {
                int c = src[base + clamp(k, len) * step];
                sa += c >>> 24;
                sr += (c >> 16) & 0xFF;
                sg += (c >> 8) & 0xFF;
                sb += c & 0xFF;
            }
            for (int k = 0; k < len; k++) {
                dst[base + k * step] = ((sa / div) << 24) | ((sr / div) << 16) | ((sg / div) << 8) | (sb / div);
                int add = src[base + clamp(k + r + 1, len) * step];
                int sub = src[base + clamp(k - r, len) * step];
                sa += (add >>> 24) - (sub >>> 24);
                sr += ((add >> 16) & 0xFF) - ((sub >> 16) & 0xFF);
                sg += ((add >> 8) & 0xFF) - ((sub >> 8) & 0xFF);
                sb += (add & 0xFF) - (sub & 0xFF);
            }
        }
    }

    /** Gaussian-like blur of a float grid in place; edges are clamped. */
    public static void blurFloat(float[] a, int w, int h, double sigma) {
        if (sigma <= 0 || w <= 0 || h <= 0) return;
        float[] tmp = new float[a.length];
        for (int r : boxRadii(sigma)) {
            if (r <= 0) continue;
            boxFloat(a, tmp, w, h, r, 1, w);
            boxFloat(tmp, a, h, w, r, w, 1);
        }
    }

    private static void boxFloat(float[] src, float[] dst, int len, int lines, int r, int step, int lineStep) {
        float div = 2 * r + 1;
        for (int l = 0; l < lines; l++) {
            int base = l * lineStep;
            double s = 0;
            for (int k = -r; k <= r; k++) s += src[base + clamp(k, len) * step];
            for (int k = 0; k < len; k++) {
                dst[base + k * step] = (float) (s / div);
                s += src[base + clamp(k + r + 1, len) * step] - src[base + clamp(k - r, len) * step];
            }
        }
    }

    private static int clamp(int k, int len) {
        return k < 0 ? 0 : (k >= len ? len - 1 : k);
    }

    /**
     * Mixes low-resolution layers into {@code band}: {@code inside} where the mask is 1,
     * {@code outside} where it is 0; a null layer means the band's own (sharp) pixel, a null mask
     * means 0 everywhere. Layers are sampled bilinearly. Band pixel (i, j) is pixel
     * ({@code bx + i}, {@code by + j}) of the region the layers ({@code lw x lh}, scale
     * {@code sx, sy}) cover.
     */
    public static void composite(int[] band, int bw, int bh, int bx, int by, int[] inside, int[] outside,
            float[] mask, int lw, int lh, double sx, double sy) {
        for (int j = 0; j < bh; j++) {
            double v = Math.max(0, (by + j + 0.5) * sy - 0.5);
            int y0 = clamp((int) v, lh);
            int y1 = clamp(y0 + 1, lh);
            double fy = y0 == lh - 1 ? 0 : v - y0;
            for (int i = 0; i < bw; i++) {
                double u = Math.max(0, (bx + i + 0.5) * sx - 0.5);
                int x0 = clamp((int) u, lw);
                int x1 = clamp(x0 + 1, lw);
                double fx = x0 == lw - 1 ? 0 : u - x0;
                int i00 = y0 * lw + x0, i10 = y0 * lw + x1, i01 = y1 * lw + x0, i11 = y1 * lw + x1;
                double m = mask == null ? 0
                        : lerp(lerp(mask[i00], mask[i10], fx), lerp(mask[i01], mask[i11], fx), fy);
                if (m < 0.002) m = 0;
                if (m > 1) m = 1;
                if (outside == null && m == 0) continue;
                if (inside == null && m == 1) continue;
                int o = band[j * bw + i];
                int out = 0;
                for (int shift = 0; shift <= 24; shift += 8) {
                    int c = (o >>> shift) & 0xFF;
                    double a = inside == null ? c : sample(inside, i00, i10, i01, i11, fx, fy, shift);
                    double b = outside == null ? c : sample(outside, i00, i10, i01, i11, fx, fy, shift);
                    int mixed = (int) Math.round(b + (a - b) * m);
                    out |= Math.max(0, Math.min(255, mixed)) << shift;
                }
                band[j * bw + i] = out;
            }
        }
    }

    private static double sample(int[] px, int i00, int i10, int i01, int i11, double fx, double fy, int shift) {
        return lerp(
                lerp((px[i00] >>> shift) & 0xFF, (px[i10] >>> shift) & 0xFF, fx),
                lerp((px[i01] >>> shift) & 0xFF, (px[i11] >>> shift) & 0xFF, fx), fy);
    }

    private static double lerp(double a, double b, double t) {
        return a + (b - a) * t;
    }
}
