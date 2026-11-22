package com.lazaaq.tutles;

import java.util.List;
import java.util.Map;

/**
 * Collage: equal cells in {@code cols x rows} with a gap around and between them, each photo
 * cropped to fill its cell. Geometry matches {@code CollageGeometry} in lib/collage.dart and
 * {@code CollageSpec} in ios/Runner/ImageEncoder.swift.
 */
public final class CollageGeometry {
    public static final int DEFAULT_LONG_SIDE = 4096;

    public final int width;
    public final int height;
    /** Cells {x, y, w, h}, row by row from the top left. */
    public final int[][] cells;

    CollageGeometry(int width, int height, int[][] cells) {
        this.width = width;
        this.height = height;
        this.cells = cells;
    }

    /** Options from the channel arguments {@code {cols, rows, gap, color, ratio}}. */
    public static final class Spec {
        public final int cols;
        public final int rows;
        /** Gap as a fraction of the canvas' long side. */
        public final double gap;
        /** 0xRRGGBB, always opaque. */
        public final int rgb;
        /** Canvas width / height. */
        public final double ratio;
        /** Crop position per photo: x0, y0, x1, y1, … (0 = left/top, 1 = right/bottom). */
        public final double[] crops;

        public Spec(int cols, int rows, double gap, int rgb, double ratio, double[] crops) {
            this.cols = cols;
            this.rows = rows;
            this.gap = gap;
            this.rgb = rgb;
            this.ratio = ratio;
            this.crops = crops;
        }

        /** Crop position {x, y} of photo {@code i}; missing = centre. */
        public double[] crop(int i) {
            return new double[] {at(2 * i), at(2 * i + 1)};
        }

        private double at(int k) {
            return k < crops.length ? Math.max(0, Math.min(1, crops[k])) : 0.5;
        }

        /** {@code {cols, rows, gap, color, ratio, crops}}; null when malformed. */
        public static Spec from(Map<?, ?> m) {
            if (m == null) return null;
            Object c = m.get("cols"), r = m.get("rows"), g = m.get("gap"), col = m.get("color"), ra = m.get("ratio");
            if (!(c instanceof Number) || !(r instanceof Number) || !(ra instanceof Number)) return null;
            int cols = ((Number) c).intValue(), rows = ((Number) r).intValue();
            double ratio = ((Number) ra).doubleValue();
            if (cols < 1 || cols > 5 || rows < 1 || rows > 5 || ratio <= 0) return null;
            Object cr = m.get("crops");
            int n = 0;
            double[] crops = new double[cr instanceof List ? ((List<?>) cr).size() : 0];
            if (cr instanceof List) for (Object v : (List<?>) cr) if (v instanceof Number) crops[n++] = ((Number) v).doubleValue();
            return new Spec(cols, rows,
                    g instanceof Number ? Math.max(0, Math.min(((Number) g).doubleValue(), 0.25)) : 0,
                    col instanceof Number ? ((Number) col).intValue() & 0xFFFFFF : 0xFFFFFF,
                    ratio, java.util.Arrays.copyOf(crops, n));
        }

        public int argb() {
            return 0xFF000000 | rgb;
        }

        /** Canvas with long side {@code longSide}; leftover pixels are spread evenly. */
        public CollageGeometry geometry(int longSide) {
            int w = ratio >= 1 ? longSide : Math.max(1, (int) Math.round(longSide * ratio));
            int h = ratio >= 1 ? Math.max(1, (int) Math.round(longSide / ratio)) : longSide;
            int g = (int) Math.round(gap * Math.max(w, h));
            int[][] xs = split(w, cols, g);
            int[][] ys = split(h, rows, g);
            int[][] cells = new int[cols * rows][];
            for (int j = 0; j < rows; j++) {
                for (int i = 0; i < cols; i++) {
                    cells[j * cols + i] = new int[] {xs[i][0], ys[j][0], xs[i][1], ys[j][1]};
                }
            }
            return new CollageGeometry(w, h, cells);
        }

        /** {start, size} of {@code n} cells along {@code total} px. */
        private static int[][] split(int total, int n, int g) {
            int avail = Math.max(n, total - (n + 1) * g);
            int[][] out = new int[n][];
            for (int i = 0; i < n; i++) {
                int a = (int) Math.round((double) avail * i / n);
                int b = (int) Math.round((double) avail * (i + 1) / n);
                out[i] = new int[] {g + i * g + a, b - a};
            }
            return out;
        }
    }

    /** Centre crop; see {@link #cover(int, int, int, int, double, double)}. */
    public static int[] cover(int iw, int ih, int cw, int ch) {
        return cover(iw, ih, cw, ch, 0.5, 0.5);
    }

    /**
     * Part {x, y, w, h} of an {@code iw x ih} image that fills a {@code cw x ch} cell; the cut-off
     * rest is split by the crop position ({@code fx}, {@code fy}), 0.5 = centre.
     */
    public static int[] cover(int iw, int ih, int cw, int ch, double fx, double fy) {
        if ((long) iw * ch > (long) ih * cw) {
            int sw = Math.max(1, (int) Math.round((double) ih * cw / ch));
            return new int[] {(int) Math.floor((iw - sw) * Math.max(0, Math.min(1, fx))), 0, sw, ih};
        }
        int sh = Math.max(1, (int) Math.round((double) iw * ch / cw));
        return new int[] {0, (int) Math.floor((ih - sh) * Math.max(0, Math.min(1, fy))), iw, sh};
    }
}
