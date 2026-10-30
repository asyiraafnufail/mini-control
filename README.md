# MiniControl

Aplikasi menu bar native ultra-ringan untuk macOS Ventura (13) hingga Sequoia (15).
Didesain khusus untuk efisiensi maksimum: **< 15 MB RAM** dan **< 0.05% CPU**.

## Fitur Utama

1. **Heartbeat CPU Stress Indicator**:
   - Icon denyut jantung (ECG) di menu bar dengan 3 warna dinamis:
     - 🟢 **Hijau**: Normal (< 50%)
     - 🟡 **Kuning**: Sedang (50% - 79%)
     - 🔴 **Merah**: Tinggi / Stress (>= 80%)
   - Menggunakan Mach Kernel Host API (`host_processor_info`) langsung di RAM (tanpa proses shell/disk I/O).

2. **Charging & Battery Watt Monitor**:
   - Menampilkan daya charging realtime dalam Watt (e.g. `+45.2W`) dan rated adapter charger (e.g. `65W`, `96W`).
   - Menampilkan daya discharge saat menggunakan baterai (e.g. `-12.5W`).
   - **Event-driven**: Terhubung via `IOPSNotificationCreateRunLoopSource` (0% polling saat status baterai statis).
   - Opsi menampilkan angka Watt langsung di samping icon menu bar.

3. **Intel Turbo Boost Toggle**:
   - Mengatur MSR `0x1A0` (`IA32_MISC_ENABLE`) bit 38 untuk mengunci thermal & clockspeed CPU Intel.

4. **Zero-Power Sleep Aware**:
   - Berhenti total saat layar/mesin sleep (`screensDidSleepNotification`), konsumsi CPU 0.00%.

## Struktur Direktori

```
mini-control/
├── Package.swift                     # Konfigurasi Swift Package Manager
├── Makefile                          # Script build & bundle .app otomatis
├── PRD.md                            # Product Requirement Document
├── Resources/
│   └── Info.plist                    # Bundle metadata (LSUIElement = true)
└── Sources/
    └── MiniControl/
        ├── main.swift                # Entrypoint aplikasi
        ├── AppDelegate.swift         # Lifecycle & observer sleep/wake
        ├── Controllers/
        │   ├── StatusBarController.swift     # Menu bar item & context menu
        │   └── TurboBoostController.swift    # Intel MSR & helper interface
        ├── Monitors/
        │   ├── CPUMonitor.swift              # Mach kernel host CPU sampler
        │   └── PowerMonitor.swift            # IOKit AppleSmartBattery event monitor
        └── Views/
            └── HeartbeatIcon.swift           # Vector ECG renderer (cached)
```

## Cara Build & Menjalankan

### Persyaratan:
- macOS 13.0+ (Ventura, Sonoma, atau Sequoia)
- Xcode Command Line Tools (`xcode-select --install`) atau Xcode

### Kompilasi & Jalankan:
```bash
# Build dan bundle menjadi MiniControl.app
make app

# Jalankan aplikasi
make run
```
