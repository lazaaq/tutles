package com.lazaaq.tutles;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;

import java.util.HashMap;
import java.util.Map;
import org.junit.Test;

public class BorderLayoutTest {
    private static int[] layout(int w, int h, double f, double r, int m) {
        BorderLayout l = BorderLayout.compute(w, h, f, r, m);
        return new int[] {l.canvasWidth, l.canvasHeight, l.x, l.y, l.width, l.height};
    }

    /** Same cases as test/image_jobs_test.dart and ios/EncoderTests/main.swift. */
    @Test
    public void sharedCases() {
        assertArrayEquals(new int[] {1320, 920, 60, 60, 1200, 800}, layout(1200, 800, 0.05, 0, 0));
        assertArrayEquals(new int[] {1320, 1320, 60, 260, 1200, 800}, layout(1200, 800, 0.05, 1, 0));
        assertArrayEquals(new int[] {1056, 1320, 128, 60, 800, 1200}, layout(800, 1200, 0.05, 0.8, 0));
        assertArrayEquals(new int[] {562, 1000, 10, 319, 541, 361}, layout(1200, 800, 0.02, 9.0 / 16, 1000));
        assertArrayEquals(new int[] {600, 600, 50, 50, 500, 500}, layout(1000, 1000, 0.1, 0, 600));
        assertArrayEquals(new int[] {1200, 800, 0, 0, 1200, 800}, layout(1200, 800, 0, 0, 0));
    }

    @Test
    public void maxSideNeverEnlarges() {
        assertArrayEquals(new int[] {1320, 920, 60, 60, 1200, 800}, layout(1200, 800, 0.05, 0, 5000));
    }

    @Test
    public void specFromChannelArgument() {
        Map<String, Object> m = new HashMap<>();
        m.put("width", 0.05);
        m.put("color", 0xF3EBDD);
        m.put("ratio", 0.8);
        BorderLayout.Spec s = BorderLayout.Spec.from(m);
        assertEquals(0.05, s.fraction, 1e-9);
        assertEquals(0xF3EBDD, s.rgb);
        assertEquals(0.8, s.ratio, 1e-9);
        assertEquals(0xFFF3EBDD, s.argb());
    }

    @Test
    public void specRejectsMissingWidthAndClampsValues() {
        assertNull(BorderLayout.Spec.from(null));
        Map<String, Object> m = new HashMap<>();
        m.put("color", 0);
        assertNull(BorderLayout.Spec.from(m));

        m.put("width", 3);           // Integer from Dart, out of range
        m.put("color", 0xFFFFFFFFL); // Long with alpha bits
        m.put("ratio", -1);
        BorderLayout.Spec s = BorderLayout.Spec.from(m);
        assertEquals(1.0, s.fraction, 1e-9);
        assertEquals(0xFFFFFF, s.rgb);
        assertEquals(0.0, s.ratio, 1e-9);
    }
}
