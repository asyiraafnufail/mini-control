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

3. **Intel Turbo Boost Toggle & Status Indicator**:
   - Indicator di menu bar:
     - ⚡ (Kuning): Turbo Boost **ON** (clockspeed maksimal diizinkan).
     - ⚡⃠ (Abu-abu): Turbo Boost **OFF** (CPU dibatasi base clock untuk menghemat suhu/baterai).
   - Toggle instan via dropdown menu atau hotkey `Cmd+T`.
   - Helper tool ringan (`/usr/local/bin/minicontrol-tb`) untuk kontrol MSR register tingkat hardware.

4. **Real-time CPU History Graph View**:
   - Mini sparkline graph langsung di dropdown menu (30 sample terakhir).
   - Dynamic gradient & guideline batas 50% dan 80%.
   - Render native via CoreGraphics dengan alokasi memori minimal.

5. **Zero-Power Sleep Aware**:
   - Berhenti total saat layar/mesin sleep (`screensDidSleepNotification`), konsumsi CPU 0.00%.

## Struktur Direktori

```
mini-control/
├── Package.swift                     # Konfigurasi Swift Package Manager
├── Makefile                          # Script build & bundle .app otomatis
├── PRD.md                            # Product Requirement Document
├── scripts/
│   ├── tb_toggle.sh                  # Skrip kontrol MSR / kext Turbo Boost
│   └── install_helper.sh             # Skrip instalasi root helper daemon
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
            ├── HeartbeatIcon.swift           # Vector ECG renderer (cached)
            └── CPUHistoryGraphView.swift     # Realtime sparkline graph view
```

## Cara Build & Menjalankan

### 1. Kompilasi & Jalankan Aplikasi:
```bash
make run
```

### 2. Pasang Helper Turbo Boost (Akses Hardware MSR):
Untuk mengizinkan aplikasi mengubah frekuensi hardware Intel tanpa pop-up password:
```bash
sudo make install-helper
```
