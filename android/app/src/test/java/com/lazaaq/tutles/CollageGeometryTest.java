package com.lazaaq.tutles;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;

import java.util.HashMap;
import java.util.Map;
import org.junit.Test;

public class CollageGeometryTest {
    private static int[] geo(int cols, int rows, double ratio, int longSide, double gap) {
        CollageGeometry g = new CollageGeometry.Spec(cols, rows, gap, 0, ratio, new double[0]).geometry(longSide);
        int[] out = new int[2 + 4 * g.cells.length];
        out[0] = g.width;
        out[1] = g.height;
        for (int i = 0; i < g.cells.length; i++) System.arraycopy(g.cells[i], 0, out, 2 + 4 * i, 4);
        return out;
    }

    /** Same cases as test/collage_test.dart and ios/EncoderTests/main.swift. */
    @Test
    public void sharedCases() {
        assertArrayEquals(new int[] {1000, 1000, 20, 20, 470, 960, 510, 20, 470, 960}, geo(2, 1, 1, 1000, 0.02));
        assertArrayEquals(new int[] {1920, 1080, 19, 19, 615, 1042, 653, 19, 614, 1042, 1286, 19, 615, 1042},
                geo(3, 1, 16.0 / 9, 1920, 0.01));
        assertArrayEquals(new int[] {800, 1000, 30, 30, 740, 293, 30, 353, 740, 294, 30, 677, 740, 293},
                geo(1, 3, 0.8, 1000, 0.03));
        assertArrayEquals(new int[] {1001, 1001, 20, 20, 471, 471, 511, 20, 470, 471, 20, 511, 471, 470, 511, 511,
                470, 470}, geo(2, 2, 1, 1001, 0.02));
        assertArrayEquals(new int[] {1000, 1000, 0, 0, 200, 1000, 200, 0, 200, 1000, 400, 0, 200, 1000, 600, 0,
                200, 1000, 800, 0, 200, 1000}, geo(5, 1, 1, 1000, 0));
        assertArrayEquals(new int[] {900, 1600, 80, 80, 740, 680, 80, 840, 740, 680}, geo(1, 2, 9.0 / 16, 1600, 0.05));
    }

    @Test
    public void coverCases() {
        assertArrayEquals(new int[] {1250, 0, 1500, 3000}, CollageGeometry.cover(4000, 3000, 500, 1000));
        assertArrayEquals(new int[] {0, 1250, 3000, 1500}, CollageGeometry.cover(3000, 4000, 1000, 500));
        assertArrayEquals(new int[] {0, 0, 1000, 1000}, CollageGeometry.cover(1000, 1000, 300, 300));
        assertArrayEquals(new int[] {0, 0, 1200, 799}, CollageGeometry.cover(1200, 800, 601, 400));
        // Crop position: 0 = left/top, 1 = right/bottom.
        assertArrayEquals(new int[] {0, 0, 1500, 3000}, CollageGeometry.cover(4000, 3000, 500, 1000, 0, 0));
        assertArrayEquals(new int[] {2500, 0, 1500, 3000}, CollageGeometry.cover(4000, 3000, 500, 1000, 1, 1));
        assertArrayEquals(new int[] {750, 0, 1500, 3000}, CollageGeometry.cover(4000, 3000, 500, 1000, 0.3, 0.9));
        assertArrayEquals(new int[] {0, 1875, 3000, 1500}, CollageGeometry.cover(3000, 4000, 1000, 500, 0.1, 0.75));
        assertArrayEquals("clamped", new int[] {0, 2500, 3000, 1500},
                CollageGeometry.cover(3000, 4000, 1000, 500, 0.5, 2));
    }

    @Test
    public void specFromChannelArguments() {
        Map<String, Object> m = new HashMap<>();
        m.put("cols", 1);
        m.put("rows", 3);
        m.put("gap", 0.01);
        m.put("color", 0x1F2A44);
        m.put("ratio", 0.5625);
        m.put("crops", java.util.Arrays.asList(0.2, 1));
        CollageGeometry.Spec s = CollageGeometry.Spec.from(m);
        assertArrayEquals(new double[] {0.2, 1}, s.crop(0), 0);
        assertArrayEquals("missing = centre", new double[] {0.5, 0.5}, s.crop(1), 0);
        assertEquals(1, s.cols);
        assertEquals(3, s.rows);
        assertEquals(0.01, s.gap, 1e-12);
        assertEquals(0xFF1F2A44, s.argb());
        assertEquals(0.5625, s.ratio, 1e-12);

        m.put("gap", 5);  // clamped
        assertEquals(0.25, CollageGeometry.Spec.from(m).gap, 1e-12);
        m.put("cols", 0);
        assertNull(CollageGeometry.Spec.from(m));
        m.put("cols", 2);
        m.remove("ratio");
        assertNull(CollageGeometry.Spec.from(m));
        assertNull(CollageGeometry.Spec.from(null));
    }
}
