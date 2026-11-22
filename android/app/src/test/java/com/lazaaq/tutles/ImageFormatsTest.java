package com.lazaaq.tutles;

import static org.junit.Assert.assertEquals;

import org.junit.Test;

public class ImageFormatsTest {
    @Test
    public void sameFormatKeepsWhatAndroidCanWrite() {
        assertEquals("jpeg", ImageFormats.resolve("same", "IMG_1.JPG"));
        assertEquals("png", ImageFormats.resolve("same", "S.PNG"));
        assertEquals("webp", ImageFormats.resolve("same", "a.webp"));
        assertEquals("jpeg", ImageFormats.resolve("same", "IMG_2.HEIC"));
        assertEquals("jpeg", ImageFormats.resolve(null, "noext"));
        assertEquals("png", ImageFormats.resolve("png", "IMG_1.JPG"));
    }

    @Test
    public void namesAndMime() {
        assertEquals("IMG_2.jpg", ImageFormats.outputName("IMG_2.HEIC", "jpeg"));
        assertEquals("photo.png", ImageFormats.outputName("", "png"));
        assertEquals("image/webp", ImageFormats.mime("webp"));
        assertEquals("a (2).jpg", ImageFormats.uniqueName("a.jpg", n -> n.equals("a.jpg") || n.equals("a (1).jpg")));
    }

    @Test
    public void outOfMemoryHasReadableMessage() {
        assertEquals("Foto terlalu besar untuk memori perangkat. Pilih ukuran yang lebih kecil.",
                ImageFormats.errorMessage(new OutOfMemoryError()));
        assertEquals("boom", ImageFormats.errorMessage(new IllegalStateException("boom")));
    }
}
