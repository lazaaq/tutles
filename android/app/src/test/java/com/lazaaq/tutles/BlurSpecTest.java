package com.lazaaq.tutles;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import java.util.Arrays;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import org.junit.Test;

public class BlurSpecTest {
    private static Map<String, Object> stroke(double radius, boolean erase, Object... points) {
        Map<String, Object> m = new HashMap<>();
        m.put("radius", radius);
        m.put("erase", erase);
        m.put("points", Arrays.asList(points));
        return m;
    }

    private static Map<String, Object> arg(Object strength, Object... strokes) {
        Map<String, Object> m = new HashMap<>();
        m.put("strength", strength);
        m.put("strokes", Arrays.asList(strokes));
        return m;
    }

    private static BlurSpec spec(BlurSpec.Stroke... s) {
        return new BlurSpec(0.02, 0, 0.004, Arrays.asList(s));
    }

    /** Same cases as test/blur_test.dart and ios/EncoderTests/main.swift. */
    @Test
    public void sharedCases() {
        List<BlurSpec.Stroke> none = Collections.emptyList();
        BlurSpec a = new BlurSpec(0.02, 0.01, 0.012, none);
        assertEquals(80, a.sigma(4000, 3000), 1e-9);
        assertEquals(40, a.backgroundSigma(4000, 3000), 1e-9);
        assertEquals(48, a.featherSigma(4000, 3000), 1e-9);
        BlurSpec b = new BlurSpec(0.005, 0, 0.004, none);
        assertEquals(6, b.sigma(800, 1200), 1e-9);
        assertEquals(0, b.backgroundSigma(800, 1200), 0);
        assertEquals(4.8, b.featherSigma(800, 1200), 1e-9);
        assertEquals(50, new BlurSpec(0.05, 0, 0.004, none).sigma(1000, 1000), 1e-9);
    }

    @Test
    public void fromChannelArgument() {
        Map<String, Object> a = arg(0.02,
                stroke(0.05, false, 0.1, 0.2, 0.3, 0.4),
                stroke(0.02, true, 0.5, 0.5, 0.9), // odd count: last dropped
                stroke(0.02, false));              // empty: skipped
        a.put("background", 0.005);
        a.put("feather", 0.008);
        BlurSpec s = BlurSpec.from(a);
        assertEquals(0.02, s.strength, 1e-12);
        assertEquals(0.005, s.background, 1e-12);
        assertEquals(0.008, s.feather, 1e-12);
        assertEquals(2, s.strokes.size());
        assertArrayEquals(new double[] {0.1, 0.2, 0.3, 0.4}, s.strokes.get(0).points, 0);
        assertFalse(s.strokes.get(0).erase);
        assertArrayEquals(new double[] {0.5, 0.5}, s.strokes.get(1).points, 0);
        assertTrue(s.strokes.get(1).erase);
    }

    @Test
    public void fromRejectsEmptyAndClamps() {
        assertNull(BlurSpec.from(null));
        assertNull("strength 0, background 0", BlurSpec.from(arg(0, stroke(0.1, false, 0.5, 0.5))));
        assertNull("eraser only", BlurSpec.from(arg(0.02, stroke(0.1, true, 0.5, 0.5))));
        Map<String, Object> m = arg(3, stroke(4, false, 1, 0));  // Integers from Dart
        m.put("background", -1);
        m.put("feather", 2);
        BlurSpec s = BlurSpec.from(m);
        assertEquals(0.1, s.strength, 1e-12);
        assertEquals(0, s.background, 0);
        assertEquals(0.1, s.feather, 1e-12);
        assertEquals(1, s.strokes.get(0).radius, 1e-12);

        assertEquals("feather default", BlurSpec.DEFAULT_FEATHER,
                BlurSpec.from(arg(0.02, stroke(0.1, false, 0.5, 0.5))).feather, 0);
        Map<String, Object> bgOnly = new HashMap<>();
        bgOnly.put("strength", 0.02);
        bgOnly.put("background", 0.01);
        BlurSpec bg = BlurSpec.from(bgOnly);
        assertEquals("background only: no strokes needed", 0, bg.strokes.size());
        assertTrue(bg.changesPhoto());
    }

    @Test
    public void boundsCoverPaintPlusFeatherOnly() {
        BlurSpec s = spec(
                new BlurSpec.Stroke(0.05, false, new double[] {0.25, 0.5}),
                new BlurSpec.Stroke(0.3, true, new double[] {0.9, 0.9}));
        // 1000x500: radius 50 + 3 * 4 = 62 around (250, 250)
        assertArrayEquals(new int[] {188, 188, 312, 312}, s.bounds(1000, 500));
        BlurSpec edge = spec(new BlurSpec.Stroke(0.1, false, new double[] {0, 0, 1, 1}));
        assertArrayEquals("clipped", new int[] {0, 0, 1000, 500}, edge.bounds(1000, 500));
        assertNull(spec(new BlurSpec.Stroke(0.1, true, new double[] {0.5, 0.5})).bounds(100, 100));
    }

    @Test
    public void maskPaintsDotsLinesAndErases() {
        BlurSpec s = spec(
                new BlurSpec.Stroke(0.05, false, new double[] {0.1, 0.25, 0.4, 0.25}),
                new BlurSpec.Stroke(0.05, false, new double[] {0.8, 0.75}),
                new BlurSpec.Stroke(0.05, true, new double[] {0.4, 0.25}));
        float[] m = s.mask(200, 100, 0, 0, 200, 100, 1, 1);
        assertEquals(1, m[25 * 200 + 40], 0);   // band
        assertEquals(0, m[75 * 200 + 40], 0);   // below band
        assertEquals(1, m[75 * 200 + 160], 0);  // dot
        assertEquals(0, m[25 * 200 + 80], 0);   // erased
        assertEquals(1, m[25 * 200 + 11], 0);   // round cap, radius 10
        assertEquals(0, m[25 * 200 + 2], 0);

        // Half-size grid of the region starting at (100, 50): same dot at cell (30, 12.5).
        float[] half = s.mask(200, 100, 100, 50, 50, 25, 0.5, 0.5);
        assertEquals(1, half[12 * 50 + 30], 0);
        assertEquals(0, half[12 * 50 + 5], 0);
    }

    @Test
    public void boxRadiiApproximateTheSigma() {
        for (double sigma : new double[] {1, 3, 6, 10, 25}) {
            double var = 0;
            for (int r : BlurMath.boxRadii(sigma)) var += ((2 * r + 1) * (2 * r + 1) - 1) / 12.0;
            assertEquals("sigma " + sigma, sigma, Math.sqrt(var), sigma * 0.15 + 0.3);
        }
        assertArrayEquals(new int[] {0, 0, 0}, BlurMath.boxRadii(0.2));
    }

    @Test
    public void blurKeepsFlatAndSmoothsEdges() {
        int w = 40, h = 10;
        int[] flat = new int[w * h];
        Arrays.fill(flat, 0xFF336699);
        BlurMath.blurArgb(flat, w, h, 4);
        for (int c : flat) assertEquals(0xFF336699, c);

        int[] step = new int[w * h];
        for (int i = 0; i < step.length; i++) step[i] = i % w < w / 2 ? 0xFF000000 : 0xFFFFFFFF;
        BlurMath.blurArgb(step, w, h, 3);
        int mid = step[5 * w + w / 2] & 0xFF;
        assertTrue("edge is grey: " + mid, mid > 80 && mid < 180);
        assertEquals("far left stays black", 0, step[5 * w] & 0xFF);
        assertEquals("far right stays white", 255, step[5 * w + w - 1] & 0xFF);
        assertEquals("alpha kept", 0xFF, step[5 * w + w / 2] >>> 24);
    }

    @Test
    public void compositeFollowsTheMask() {
        // 4x2 band over a 2x1 low-res grid (scale 0.5): left half mask 0, right half mask 1.
        int[] band = new int[8];
        Arrays.fill(band, 0xFF000000);
        int[] low = {0xFFFFFFFF, 0xFFFFFFFF};
        float[] mask = {0, 1};
        BlurMath.composite(band, 4, 2, 0, 0, low, null, mask, 2, 1, 0.5, 0.5);
        assertEquals("mask 0 unchanged", 0xFF000000, band[0]);
        assertEquals("mask 1 is the blurred pixel", 0xFFFFFFFF, band[3]);
        int mid = band[1] & 0xFF;
        assertTrue("bilinear in between: " + mid, mid > 0 && mid < 255);
        assertEquals(band[1], band[5]);
    }

    @Test
    public void compositeOutsideLayer() {
        int[] outside = {0xFF808080, 0xFF808080};
        float[] mask = {0, 1};
        // Sharp inside (null), grey outside.
        int[] band = new int[4];
        Arrays.fill(band, 0xFF000000);
        BlurMath.composite(band, 4, 1, 0, 0, null, outside, mask, 2, 1, 0.5, 0.5);
        assertEquals("mask 0: outside layer", 0xFF808080, band[0]);
        assertEquals("mask 1: own sharp pixel", 0xFF000000, band[3]);
        // No mask at all: outside everywhere.
        Arrays.fill(band, 0xFF000000);
        BlurMath.composite(band, 4, 1, 0, 0, new int[] {-1, -1}, outside, null, 2, 1, 0.5, 0.5);
        for (int c : band) assertEquals(0xFF808080, c);
    }

    @Test
    public void softerEdgeSpreadsTheMask() {
        BlurSpec s = new BlurSpec(0.02, 0, 0.04, Arrays.asList(
                new BlurSpec.Stroke(0.1, false, new double[] {0.5, 0.5})));
        float[] hard = s.mask(100, 100, 0, 0, 100, 100, 1, 1);
        float[] soft = hard.clone();
        BlurMath.blurFloat(soft, 100, 100, s.featherSigma(100, 100));
        int out = 50 * 100 + 63; // 3 px outside the 10 px dot
        assertEquals(0, hard[out], 0);
        assertTrue("soft edge reaches out: " + soft[out], soft[out] > 0.05);
        assertTrue("centre still mostly blurred: " + soft[50 * 100 + 50], soft[50 * 100 + 50] > 0.8);
    }
}
