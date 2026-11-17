# RPI-Display-Driver — Modern Raspberry Pi Driver for 3.5" MPI3501 Touch Display

Modern, one-command driver and installer suite for the **MPI3501 3.5-inch Raspberry Pi Touch Screen LCD** (480×320, **Ilitek ILI9486** controller, 74HC4040 16-bit SPI bridge, **XPT2046 / HR2046** resistive touch) on **Raspberry Pi 4B / 5 / 3B+ / Zero 2W** running **Raspberry Pi OS Bookworm (Debian 12)** and **Trixie (Debian 13)**.

Companion repository to [UNOQ_MPI3501](https://github.com/jagdishtripathy/UNOQ_MPI3501) (Arduino UNO Q driver for the same display).

---

## Why `goodtft/LCD-show` Fails on Latest Raspberry Pi OS (White Screen / Boot Loop)

An audit of [`goodtft/LCD-show/LCD35-show`](https://github.com/goodtft/LCD-show/blob/master/LCD35-show) and `system_config.sh` shows **5 critical bugs** on modern Raspberry Pi OS (Debian 12 Bookworm & Debian 13 Trixie):

| # | Bug in `goodtft/LCD-show` | What Happens on Raspberry Pi 4B (Bookworm / Trixie) | How `RPI-Display-Driver` Fixes It |
|---|---|---|---|
| **1** | Copies `tft35a.dtbo` to `/boot/overlays/` (`cp ./usr/tft35a-overlay.dtb /boot/overlays/tft35a.dtbo`) | On Bookworm+, the FAT32 boot partition is mounted at **`/boot/firmware/overlays/`**, not `/boot/overlays/`. The bootloader never finds `tft35a.dtbo`, so the display stays a **solid white screen**. | Automatically detects `/boot/firmware/overlays/` (and `/boot/overlays/` on legacy OS) and compiles `mpi3501.dtbo` directly into the active boot partition. |
| **2** | Uses `rpi-fbcp` + `libraspberrypi-dev` (`bcm_host` / `dispmanx`) | `libraspberrypi-dev` and Broadcom `dispmanx` were **removed** in Bookworm 64-bit. `apt-get install` and `cmake` fail. | Uses the mainline Linux kernel **TinyDRM `ili9486`** driver (`waveshare,rpi-lcd-35`)—no `fbcp` daemon needed. |
| **3** | Installs `99-fbturbo.conf` (`Driver "fbturbo"`) and forces Console boot (`B2`) + `.bash_profile` `startx` | `fbturbo` does not exist on modern 64-bit Raspberry Pi OS, causing Xorg to crash on boot, and `.bash_profile` `startx` breaks SSH logins. | Uses the native Xorg **`modesetting`** DRM driver with `MatchDriver "ili9486"` and `Option "PrimaryGPU" "true"`, keeping clean `lightdm` Desktop autologin (`B4`). |
| **4** | Installs a hardcoded Debian 10 `.deb` (`xserver-xorg-input-evdev_2.10.6`) after pinging `mirrors.zju.edu.cn` | Fails with Xorg ABI mismatch on modern Xorg and aborts before finishing touch setup. | Uses the modern built-in **`libinput`** X11 driver with exact 3×3 homogeneous `CalibrationMatrix` values for all 4 rotations. |
| **5** | Uses ASCII string comparison (`[[ "$deb_version" < "12.10" ]]`) in Bash | In ASCII, `"12.2" > "12.10"`, triggering the wrong OS branches. | Cleanly detects actual boot paths and display stack capabilities regardless of point-release numbering. |

---

## Hardware & Pinout Reference (26-Pin Header)

Mount the 26-pin female header of the MPI3501 onto **Pins 1 to 26** of the Raspberry Pi 4B's 40-pin header (aligned with **Pin 1** near the microSD card slot / USB-C power port, leaving Pins 27–40 uncovered).

| RPi Physical Pin | BCM GPIO | Signal | Function |
|---|---|---|---|
| **Pin 1, 17** | — | **3.3V** | 3.3V Logic Supply |
| **Pin 2, 4** | — | **5V** | 5V Backlight & AMS1117-3.3 Regulator |
| **Pin 6, 9, 14, 20, 25** | — | **GND** | Common Ground |
| **Pin 11** | `GPIO 17` | **T_IRQ** | Touch Pen-Down Interrupt (Active LOW) |
| **Pin 18** | `GPIO 24` | **LCD_DC (RS)** | LCD Data / Command Select |
| **Pin 19** | `GPIO 10` | **SPI0 MOSI** | SPI Master Out Slave In |
| **Pin 21** | `GPIO 9` | **SPI0 MISO** | SPI Master In Slave Out (Touch Data) |
| **Pin 22** | `GPIO 25` | **LCD_RST** | LCD Hardware Reset (Active LOW) |
| **Pin 23** | `GPIO 11` | **SPI0 SCLK** | SPI Clock |
| **Pin 24** | `GPIO 8` (`CE0`) | **LCD_CS** | LCD Chip Select |
| **Pin 26** | `GPIO 7` (`CE1`) | **T_CS** | Touch Chip Select (XPT2046 / HR2046) |

*(Note: Unlike generic `piscreen` overlays, our custom `mpi3501-overlay.dts` does **not** claim `GPIO 22` / Pin 15, leaving it free for your projects).*

---

## Installation (Choose Method A or Method B)

### Method A: Windows 1-Click SD Card Setup (Zero SSH / Zero HDMI Needed!)

Use this method right after flashing Raspberry Pi OS in **Raspberry Pi Imager** on Windows—or even on the SD card you already flashed that gave you the white screen:

1. Insert your Raspberry Pi microSD card into your Windows PC.
2. Double-click **`sdcard-setup-windows.bat`** in this folder (or run `.\sdcard-setup-windows.ps1` in PowerShell).
3. Safely eject the microSD card, insert it into your Raspberry Pi 4B with the 3.5" MPI3501 display attached, and power on.
4. **What happens automatically:**
   * The 3.5" screen turns on immediately during the first boot.
   * A one-time systemd hook (`/boot/firmware/mpi3501-setup.sh`) automatically runs `MPI3501-show`, compiles and installs `mpi3501.dtbo`, switches Wayland to X11, configures the `ili9486` PrimaryGPU and XPT2046 touch calibration, cleans itself up from `cmdline.txt`, and reboots straight into the **Raspberry Pi OS Desktop on the 3.5" display**!

---

### Method B: One-Command Install on the Raspberry Pi (via SSH or Terminal)

Just like `LCD-show`, you can clone this repository on your Raspberry Pi and run a single command:

```bash
git clone https://github.com/jagdishtripathy/RPI-Display-Driver.git
cd RPI-Display-Driver
chmod +x MPI3501-show MPI3501-hdmi MPI3501-rotate MPI3501-diag LCD35-show LCD-hdmi
sudo ./MPI3501-show
```

*(For compatibility with `goodtft/LCD-show` muscle memory, `sudo ./LCD35-show` and `sudo ./LCD-hdmi` also work as drop-in aliases!)*

---

## Global Commands (Available Anywhere After Installation)

Once installed, four global commands are registered in `/usr/local/bin`:

### 1. Rotate Display & Touchscreen Together
```bash
sudo mpi3501-rotate 180   # 480x320 Landscape (Default)
sudo mpi3501-rotate 0     # 480x320 Landscape (Flipped 180°)
sudo mpi3501-rotate 90    # 320x480 Portrait
sudo mpi3501-rotate 270   # 320x480 Portrait (Flipped 180°)
```
You can also use named orientations:
```bash
sudo mpi3501-rotate landscape
sudo mpi3501-rotate landscape-flipped
sudo mpi3501-rotate portrait
sudo mpi3501-rotate portrait-flipped
```

### 2. Switch Back to HDMI Monitor
```bash
sudo mpi3501-hdmi
```
Restores `dtoverlay=vc4-kms-v3d`, removes the SPI PrimaryGPU override, and reboots to your HDMI display.

### 3. Switch Back to the 3.5" MPI3501 Display
```bash
sudo mpi3501-show
```

### 4. Run 4-Corner Touchscreen Calibration (Optional Fine-Tuning)
```bash
sudo mpi3501-calibrate
```
Reads raw XPT2046 ADC coordinates directly from `/dev/input/event*` as you tap the 4 corners (**Top-Left**, **Top-Right**, **Bottom-Left**, **Bottom-Right**), computes the exact 3×3 `libinput` `CalibrationMatrix` for your specific panel, saves it permanently to `/etc/X11/xorg.conf.d/99-mpi3501-touch.conf`, and applies it live to the running X11 session.

### 5. Run Hardware & Driver Diagnostics
```bash
mpi3501-diag
```
Prints the board model, kernel version, active `config.txt` overlays, SPI0 driver bindings (`ili9486` on `spi0.0` and `ads7846` on `spi0.1`), DRM cards (`/dev/dri/card*`), framebuffers (`/dev/fb*`), and XPT2046 touch input status.

---

## Repository Structure

```text
RPI-Display-Driver/
├── overlays/
│   ├── mpi3501-overlay.dts      Custom Device Tree Overlay source (ILI9486 DRM + XPT2046 Touch)
│   └── mpi3501.dtbo             Pre-compiled Device Tree Overlay binary (no dtc needed)
├── MPI3501-show                 One-command Linux installer & display activator
├── MPI3501-hdmi                 One-command switch back to HDMI monitor
├── MPI3501-rotate               One-command display + touch rotation utility
├── MPI3501-calibrate            Interactive 4-corner touchscreen calibration utility
├── MPI3501-diag                 Hardware, SPI, DRM, and touch diagnostics tool
├── LCD35-show                   Alias for MPI3501-show (drop-in replacement for LCD-show)
├── LCD-hdmi                     Alias for MPI3501-hdmi
├── sdcard-setup-windows.bat     1-Click Windows SD card patcher & auto-boot installer
├── sdcard-setup-windows.ps1     PowerShell implementation for Windows SD card setup
├── .gitattributes               Enforces LF line endings on all Linux scripts & DTS files
├── LICENSE                      MIT License
└── README.md                    Documentation
```

---

## License

MIT License — see [LICENSE](LICENSE) for details.
