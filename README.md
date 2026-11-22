# tutles

Aplikasi Android dan iOS untuk edit foto sederhana. Semua diproses di perangkat, tanpa internet.
Saudara dari [rawa](https://github.com/lazaaq/rawa-manage-photos) (kelola foto: kompres, format, sortir).

## Fitur

- **Bingkai**: pilih beberapa foto, atur ketebalan (0–15%), warna, dan rasio (1:1, 4:5, 9:16, …)
  di editor layar penuh, lalu simpan sebagai foto baru. Foto asli tidak diubah; tanggal, lokasi,
  dan EXIF tetap terbawa.
- **Blur**: usap bagian foto dengan jari untuk mem-blur (wajah, plat nomor, …). Ada ukuran kuas,
  penghapus, urungkan/ulangi, zoom dua jari, kekuatan 0–10 untuk area yang diusap dan untuk area
  lain (misalnya latar blur, wajah tajam), serta kelembutan tepi 0–10. Tiap foto punya area
  sendiri; hasil disimpan sebagai foto baru seperti Bingkai.
- **Kolase**: 2–5 foto menjadi satu foto baru: mendatar 2–5 (bertumpuk dari atas ke bawah),
  vertikal 2–3 (berjajar ke samping), atau grid 2×2, dengan jarak, warna, dan rasio yang bisa
  diatur. Foto mengisi kotaknya; geser foto untuk memilih bagian yang terlihat. Urutan sesuai
  urutan dipilih; tanggal, lokasi, dan EXIF mengikuti foto pertama.

## Build

Butuh Flutter 3.47 atau lebih baru, JDK 17, dan Xcode untuk iOS.

```bash
flutter pub get
flutter test
tool/test_ios_encoder.sh                      # encoder iOS, dijalankan di macOS
(cd android && ./gradlew :app:testDebugUnitTest)
flutter build apk --release --target-platform android-arm,android-arm64
```

Tanpa `android/key.properties`, build release ditandatangani dengan debug key.

## Lisensi

[MIT](LICENSE)
