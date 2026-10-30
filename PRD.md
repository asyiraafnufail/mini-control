# PRD: MiniControl (macOS Menu Bar)

## 1. Ringkasan
Aplikasi status bar native ultra-ringan macOS Intel (x86_64).
Fitur utama:
- Realtime CPU stress level via icon heartbeat 3 warna.
- Toggle Intel Turbo Boost on/off.

## 2. Target Kinerja & Batasan
- Platform: macOS 13 Ventura - macOS 15 Sequoia (Intel x86_64).
- Framework: Pure Swift + AppKit (`NSStatusItem`, `NSMenu`). No SwiftUI, no Electron.
- RAM: < 15 MB (target 8-12 MB).
- CPU overhead: < 0.05% average (event-driven saat memungkinkan).
- Binary size: < 3 MB.

## 3. Spesifikasi Fitur

### 3.1. Menu Bar Indicator (Heartbeat)
- Host: `NSStatusItem` di `NSStatusBar.system`.
- Visual: Icon heartbeat (`waveform.path.ecg` SF Symbol atau custom vector template).
- Threshold warna:
  - Hijau: CPU load 0% - 49% (Normal).
  - Kuning: CPU load 50% - 79% (Sedang).
  - Merah: CPU load 80% - 100% (Tinggi/Stress).
- Polling timer: `DispatchSourceTimer` (coalesced), default 2.0s interval.

### 3.2. CPU Sampling Engine
- API: Mach kernel host API (`host_processor_info` + `PROCESSOR_CPU_LOAD_INFO`).
- Diff delta tick antara `user + system + nice` vs `total`.
- Direct memory compute, 0 disk I/O, no child process spawn (`top`/`ps`).

### 3.3. Charging Wattage Monitor (IOKit)
- **Data Source**: IOKit `AppleSmartBattery` via `IOServiceGetMatchingServices` + `IOPSCopyPowerSourcesInfo`.
- **Informasi yang Ditampilkan**:
  - Adapter Input: Nilai rated charger (e.g. `65W`, `96W`, `140W`) via `AdapterDetails.Watts`.
  - Instantaneous Charge Rate: `(Amperage * Voltage) / 1,000,000` = Net charging power dalam Watt realtime (e.g. `+45.2W`).
  - Battery Health & Status: Charging / Discharging / AC Attached.
- **Optimasi Efisiensi**:
  - Event-driven via `IOPSNotificationCreateRunLoopSource` (hanya update saat ada perubahan power source/state).
  - Nol polling tambahan untuk battery saat tidak charging.

### 3.4. Turbo Boost Controller (Intel)
- Mekanisme: Tulis MSR `0x1A0` (`IA32_MISC_ENABLE`) bit 38.
  - Bit 38 = `1` -> Turbo Boost Disabled.
  - Bit 38 = `0` -> Turbo Boost Enabled.
- Privilege: Privileged Helper Tool via `SMAppService` (modern macOS 13+ native API, pengganti `SMJobBless` legacy) + MSR kext interface.
- Fallback/Safety: State revert saat reboot.

### 3.5. Menu Dropdown
Struktur `NSMenu`:
1. Header Status CPU: `CPU Load: XX%` (Heartbeat indicator).
2. Header Power/Battery:
   - AC Connected: `Charging: XX.X W (Adapter: YY W)`
   - Discharging: `Battery: ZZ% (Discharging: -XX.X W)`
3. Separator.
4. Toggle Item: `[✓] Enable Turbo Boost` (toggle hardware clock limit).
5. Separator.
6. Submenu `Appearance`:
   - Show Watt in Menu Bar: `[✓/ ]` (opsi tampilkan angka Watt di samping icon heartbeat).
   - Polling Interval: `1s` | `2s` (default) | `5s`.
7. `Quit`.

## 4. Arsitektur Teknis
```
[ MiniControl.app (User Space - AppKit) ]
  ├── StatusItemController (Render NSImage warna icon + label Watt opsional)
  ├── CPUMonitor (Mach Kernel Host API loop via GCD Timer)
  ├── PowerMonitor (IOKit CFRunLoopSource event-driven + AppleSmartBattery)
  └── TurboBoostClient (IPC ke Privileged Helper)
            │
            ▼ (XPC Service via SMAppService - macOS 13+ standard)
[ Privileged Helper Tool (launchd daemon) ]
  └── MSR Controller (Direct MSR driver access)
```

## 5. Non-Functional Requirements
- Zero memory leak (ARC strictly verified).
- Battery friendly (timer coalescing, pause loop saat screen sleep / display off via `NSWorkspace` notifications).
- Dynamic appearance (Dark / Light mode support via template image tinting).
