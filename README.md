<p align="center">
  <img src="picasso.png" alt="picasso logo" width="700">
</p>

# PICASSO - WebP Image Conversion Tool

<p align="center">
  <strong>A powerful TUI-based CLI tool for batch converting images to WebP format</strong>
</p>

<p align="center">
<pre>
# #####  #  ####    ##    ####   ####   #### 
# #    # # #    #  #  #  #      #      #    #
# #    # # #      #    #  ####   ####  #    #
# #####  # #      ######      #      # #    #
# #      # #    # #    # #    # #    # #    #
# #      #  ####  #    #  ####   ####   ####
</pre>
</p>

<p align="center">
  <a href="https://github.com/tux-tech/picasso">
    <img src="https://img.shields.io/badge/version-2.0.0-blue.svg" alt="Version">
  </a>
  <img src="https://img.shields.io/badge/platform-Linux-orange.svg" alt="Platform">
  <img src="https://img.shields.io/badge/license-MIT-green.svg" alt="License">
  <img src="https://img.shields.io/badge/language-Bash%20%7C%20Perl-purple.svg" alt="Language">
</p>

<p align="center">
  <a href="https://github.com/tux-tech/picasso/issues">Report Bug</a> •
  <a href="https://github.com/tux-tech/picasso/issues">Request Feature</a>
</p>

---

## ✨ Features

### Core Features
- **🖥️ Rich TUI Interface** - Interactive wizard-powered interface using `whiptail`
- **📁 Recursive Directory Processing** - Preserves folder structure during conversion
- **⚙️ Preset System** - Save and reuse conversion configurations
- **📊 Progress Tracking** - Real-time progress bars with ETA estimation
- **🔄 Multi-core Processing** - Parallel conversion utilizing all CPU cores
- **📦 Auto-Dependency Installation** - Installer handles all dependencies

### NEW in v2.0 - Advanced Options

#### 📂 Output Modes
| Mode | Description |
|------|-------------|
| **Subfolder** | Create a subfolder within source directory (default) |
| **Same Directory** | Save converted files alongside originals |
| **Custom Path** | Save to a completely different directory |
| **Flatten** | Put all converted images into a single folder |

#### 🗂️ File Handling Modes
| Mode | Description |
|------|-------------|
| **Preserve** | Keep originals in place (safest) |
| **Delete** | Remove originals after conversion |
| **Move** | Move originals to a specified folder |
| **Backup** | Create backup before conversion |

#### 🖼️ Image Options
- **Resizing** - Set exact dimensions or max dimension
- **Metadata Control** - Preserve or strip EXIF/ICC/XMP
- **Lossless Mode** - Perfect quality compression for PNGs
- **Near-Lossless** - Almost perfect with smaller files
- **WebP Optimization** - Re-compress existing WebP files

---

## 🚀 Installation

### Quick Install

```bash
# Clone the repository
git clone https://github.com/tux-tech/picasso.git
cd picasso

# Run the installer (auto-installs dependencies)
./install.sh
```

That's it! The installer will:
- ✅ **Auto-detect your package manager** (apt, dnf, yum, pacman)
- ✅ **Install all required dependencies** automatically
- ✅ **Set up the binary** in your PATH
- ✅ **Create configuration** with default presets

### Installation Options

The installer will ask:

1. **Local User (~/.local/bin)** - Recommended for personal use
2. **System Wide (/usr/local/bin)** - For all users (requires root)

### Installer Commands

```bash
./install.sh              # Full interactive installation
./install.sh --repair     # Repair existing installation
./install.sh --deps-only  # Only install dependencies
./install.sh --uninstall  # Remove PICASSO
./install.sh --help       # Show all options
```

### Post-Installation

If you chose local installation, add to your PATH:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

---

## 📋 Requirements

The installer handles these automatically, but for reference:

### Required Dependencies

| Package | Description |
|---------|-------------|
| `webp` | WebP encoder (cwebp) |
| `perl` | Perl interpreter |
| `whiptail` | TUI dialogs |
| `findutils` | File searching |

### Optional Dependencies

| Package | Description |
|---------|-------------|
| `libjson-perl` | JSON config parsing |
| `libterm-progressbar-perl` | Progress bars |

---

## 📖 Usage

### Interactive Mode (Recommended)

```bash
picasso
```

This opens the TUI menu with options:
1. **Quick Convert** - Run preset on folder
2. **Full Wizard** - 10-step preset creator
3. **Quick Wizard** - Fast 3-step preset
4. **List Presets** - View all saved presets
5. **Delete Preset** - Remove a preset
6. **Optimize WebP** - Re-compress existing WebPs
7. **Settings** - Configuration
8. **Check Dependencies** - System check
9. **Help & About** - Documentation

### Command Line Mode

```bash
# Convert with preset
picasso webready ./photos/

# With options
picasso large ./photos/ --verbose --log --parallel 8

# Optimize existing WebPs
picasso optimize ./webp_folder/

# List presets
picasso list

# Create preset via wizard
picasso wizard
```

---

## ⚙️ Presets

### Built-in Presets

| Preset | Quality | Mode | Description |
|--------|---------|------|-------------|
| `webready` | 65 | Subfolder | Web optimized, smallest files |
| `medium` | 75 | Subfolder | Balanced quality and size |
| `large` | 90 | Subfolder | High quality for archival |
| `backup-convert` | 75 | Backup | Creates backup + converts |
| `move-originals` | 75 | Move | Moves originals to folder |
| `export-folder` | 75 | Custom Path | Saves to separate directory |
| `delete-after-convert` | 75 | Delete | Removes originals |
| `optimize-webp` | 75 | Same Dir | Re-optimizes existing WebPs |
| `thumbnail` | 60 | Resize | Creates 300px thumbnails |
| `lossless` | 100 | Lossless | Perfect quality for PNGs |
| `strip-metadata` | 75 | Clean | Removes all metadata |

### Using the Full Wizard (10 Steps)

The wizard guides you through all options:

| Step | Option | Description |
|------|--------|-------------|
| 1 | Preset Name | Unique identifier |
| 2 | Conversion Mode | Standard/Lossless/Near-Lossless/Optimize |
| 3 | Quality | 0-100 or presets |
| 4 | Compression Method | 0-6 (speed vs size) |
| 5 | Alpha Quality | For transparent PNGs |
| 6 | File Handling | Preserve/Delete/Move/Backup |
| 7 | Output Location | Subfolder/Same/Custom/Flatten |
| 8 | Resizing | Optional dimensions |
| 9 | Metadata | Preserve or strip |
| 10 | Description | Save with notes |

---

## 📁 Output Mode Examples

### Subfolder Mode (Default)
```
photos/
├── vacation/
│   ├── beach.jpg
│   └── webp/           ← Converted here
│       └── beach.webp
└── family/
    ├── portrait.png
    └── webp/
        └── portrait.webp
```

### Same Directory Mode
```
photos/
├── vacation/
│   ├── beach.jpg        ← Original preserved
│   └── beach.webp       ← Converted here
└── family/
    ├── portrait.png
    └── portrait.webp
```

### Custom Path Mode
```
photos/                  ← Source
├── vacation/
│   └── beach.jpg
└── family/
    └── portrait.png

converted_output/        ← All output here
├── vacation/
│   └── beach.webp
└── family/
    └── portrait.webp
```

### Flatten Mode
```
photos/                  ← Source (nested)
├── vacation/
│   └── beach.jpg
└── family/
    └── portrait.png

all_converted/           ← Everything here
├── beach.webp
└── portrait.webp
```

---

## 🗂️ File Handling Examples

### Backup Mode
```
photos/
├── beach.jpg
├── webp/
│   └── beach.webp
└── originals_backup/    ← Backup created
    └── beach.jpg
```

### Move Mode
```
photos/
├── old_images/          ← Originals moved here
│   └── beach.jpg
└── beach.webp           ← Converted in place
```

### Delete Mode (⚠️ Dangerous!)
```
photos/
└── beach.webp           ← Original deleted!
```

---

## 🔄 WebP Optimization Mode

Optimize existing WebP files for smaller size:

```bash
picasso optimize ./webp_folder/
```

Or through the menu:
1. Run `picasso`
2. Select "Optimize WebP"
3. Choose directory
4. Set quality (lower = smaller)
5. Choose backup option

The optimizer:
- Re-encodes WebP files at specified quality
- Skips files that would become larger
- Creates backup if requested

---

## 📊 Examples

### Example 1: Website Optimization

```bash
picasso webready /var/www/html/images/

# Result: Smaller images in /var/www/html/images/webp/
```

### Example 2: Photo Archive with Backup

```bash
picasso backup-convert ./raw_photos/

# Result:
# ./raw_photos/webp/           - Converted images
# ./raw_photos/originals_backup/ - Original backups
```

### Example 3: Move Originals After Convert

```bash
picasso move-originals ./photos/

# Result:
# ./photos/old_images/ - Original JPGs
# ./photos/*.webp      - Converted files
```

### Example 4: Privacy-Focused Conversion

```bash
picasso strip-metadata ./private_photos/

# Result: Clean images with no EXIF/GPS data
```

---

## 🎯 Command Line Options

```
Usage: picasso [OPTIONS] [preset] [directory]

Commands:
  (none)          Launch interactive TUI menu
  wizard          Open full preset wizard (10 steps)
  quick           Open quick wizard (3 steps)
  list            List all saved presets
  optimize <dir>  Optimize WebP files in directory

Options:
  -h, --help      Show help message
  -v, --version   Show version information
  --dry-run       Preview changes without converting
  --verbose       Show detailed output
  --parallel N    Use N CPU cores
  --log           Save output to log file
  --background    Run in background

Examples:
  picasso                         # Interactive mode
  picasso webready ./photos/      # Convert with preset
  picasso large ./photos/ -p 8    # Use 8 cores
  picasso optimize ./webps/       # Optimize WebPs
```

---

## 🔧 Configuration

### Config File Location

```
~/.config/picasso/config.json
```

### Config Structure

```json
{
  "presets": {
    "mypreset": {
      "description": "My custom preset",
      "quality": 75,
      "method": 4,
      "alpha_quality": 90,
      "lossless": false,
      "file_handling": {
        "mode": "preserve",
        "delete_originals": false,
        "move_originals_to": null,
        "backup_enabled": false,
        "backup_folder": "backup"
      },
      "output": {
        "mode": "subfolder",
        "subfolder_name": "webp",
        "custom_path": null,
        "preserve_structure": true,
        "flatten": false,
        "append_suffix": null
      },
      "resizing": {
        "enabled": false,
        "width": null,
        "height": null,
        "max_dimension": null
      },
      "metadata": {
        "preserve_exif": true,
        "preserve_icc": true,
        "strip_all": false
      }
    }
  }
}
```

---

## 🛠️ Troubleshooting

### "command not found: picasso"

Add to PATH:
```bash
export PATH="$HOME/.local/bin:$PATH"
```

### Missing Dependencies

Run the installer - it handles everything:
```bash
./install.sh
```

Or manually:
```bash
# Debian/Ubuntu
sudo apt-get install webp whiptail libjson-perl libterm-progressbar-perl

# Fedora/RHEL
sudo dnf install libwebp-tools newt perl-JSON perl-Term-ProgressBar

# Arch
sudo pacman -S libwebp libnewt perl perl-json
```

### Repair Installation

```bash
./install.sh --repair
```

---

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

---

## 📝 License

MIT License - See [LICENSE](LICENSE) for details.

---

## 🙏 Acknowledgments

- Google's [WebP](https://developers.google.com/speed/webp) codec
- The Perl community
- [newt/whiptail](https://pagure.io/newt) for TUI dialogs

---

<p align="center">
  <a href="https://github.com/tux-tech/picasso">GitHub</a> •
  <a href="https://github.com/tux-tech/picasso/issues">Issues</a>
</p>

<p align="center">
  Made with ❤️ for the Linux community
</p>
