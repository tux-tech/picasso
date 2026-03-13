#!/bin/bash
#
# PICASSO - WebP Image Conversion Tool Installer v2.0
# Idempotent installer - run repeatedly to fix/repair installation
# Automatically installs all required dependencies
#
# Compatible with: Debian 13, Ubuntu, and most Linux distributions
#

set -e

# --- Configuration ---
APP_NAME="picasso"
APP_VERSION="2.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_BIN="$HOME/.local/bin"
SYSTEM_BIN="/usr/local/bin"
CONFIG_DIR="$HOME/.config/picasso"
CONFIG_FILE="$CONFIG_DIR/config.json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'

# Print functions
print_header() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                                                              ║"
    echo "║  # #####  #  ####    ##    ####   ####   ####                ║"
    echo "║  # #    # # #    #  #  #  #      #      #    #               ║"
    echo "║  # #    # # #      #    #  ####   ####  #    #               ║"
    echo "║  # #####  # #      ######      #      # #    #               ║"
    echo "║  # #      # #    # #    # #    # #    # #    #               ║"
    echo "║  # #      #  ####  #    #  ####   ####   ####                ║"
    echo "║                                                              ║"
    echo "║       WebP Image Conversion Tool - Installer v${APP_VERSION}       ║"
    echo "║                                                              ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_status() { echo -e "${BLUE}[*]${NC} $1"; }
print_success() { echo -e "${GREEN}[✓]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }
print_install() { echo -e "${MAGENTA}[+]${NC} $1"; }

command_exists() { command -v "$1" &> /dev/null; }

# Detect package manager
detect_package_manager() {
    if command_exists apt-get; then
        PKG_MANAGER="apt"
        PKG_INSTALL="apt-get install -y"
        PKG_UPDATE="apt-get update"
    elif command_exists dnf; then
        PKG_MANAGER="dnf"
        PKG_INSTALL="dnf install -y"
        PKG_UPDATE="dnf check-update"
    elif command_exists yum; then
        PKG_MANAGER="yum"
        PKG_INSTALL="yum install -y"
        PKG_UPDATE="yum check-update"
    elif command_exists pacman; then
        PKG_MANAGER="pacman"
        PKG_INSTALL="pacman -S --noconfirm"
        PKG_UPDATE="pacman -Sy"
    else
        PKG_MANAGER="unknown"
    fi
    echo "$PKG_MANAGER"
}

# Check if running as root or with sudo
check_privileges() {
    if [ "$(id -u)" -eq 0 ]; then
        IS_ROOT=true
        SUDO=""
    elif command_exists sudo; then
        IS_ROOT=false
        SUDO="sudo"
    else
        IS_ROOT=false
        SUDO=""
    fi
}

# Install system dependencies
install_system_dependencies() {
    print_status "Checking system dependencies..."
    
    local missing_deps=()
    local needs_install=false
    
    # Check each dependency
    if ! command_exists cwebp; then
        missing_deps+=("webp")
        needs_install=true
    fi
    
    if ! command_exists perl; then
        missing_deps+=("perl")
        needs_install=true
    fi
    
    if ! command_exists whiptail; then
        missing_deps+=("whiptail")
        needs_install=true
    fi
    
    if ! command_exists find; then
        missing_deps+=("findutils")
        needs_install=true
    fi
    
    if [ "$needs_install" = true ]; then
        echo ""
        print_warning "Missing dependencies: ${missing_deps[*]}"
        echo ""
        
        # Check if we can install
        detect_package_manager
        
        if [ "$PKG_MANAGER" = "unknown" ]; then
            print_error "Could not detect package manager. Please install manually:"
            echo "  Debian/Ubuntu: sudo apt-get install webp whiptail perl findutils"
            echo "  Fedora/RHEL:   sudo dnf install libwebp-tools newt perl findutils"
            echo "  Arch:          sudo pacman -S libwebp libnewt perl findutils"
            exit 1
        fi
        
        # Check privileges
        check_privileges
        
        if [ "$IS_ROOT" = false ] && [ -z "$SUDO" ]; then
            print_error "Need root privileges to install dependencies."
            echo "Run with: sudo ./install.sh"
            exit 1
        fi
        
        print_install "Installing dependencies using $PKG_MANAGER..."
        echo ""
        
        # Build package list based on distro
        local pkg_list=""
        case "$PKG_MANAGER" in
            apt)
                pkg_list="webp libnewt0.52 perl findutils libjson-perl libterm-progressbar-perl"
                print_status "Updating package lists..."
                $SUDO $PKG_UPDATE 2>/dev/null || true
                ;;
            dnf|yum)
                pkg_list="libwebp-tools newt perl findutils perl-JSON perl-Term-ProgressBar"
                ;;
            pacman)
                pkg_list="libwebp libnewt perl findutils perl-json perl-term-progressbar"
                ;;
        esac
        
        print_install "Installing: $pkg_list"
        echo ""
        
        if $SUDO $PKG_INSTALL $pkg_list; then
            echo ""
            print_success "All dependencies installed successfully"
        else
            print_error "Failed to install some dependencies"
            print_warning "Attempting to continue anyway..."
        fi
    else
        print_success "All system dependencies are installed"
    fi
}

# Install Perl modules
install_perl_modules() {
    print_status "Checking Perl modules..."
    
    local modules_ok=true
    local modules_to_install=()
    
    # Check JSON
    if ! perl -MJSON -e 1 2>/dev/null; then
        modules_to_install+=("JSON")
        modules_ok=false
    fi
    
    # Check Term::ProgressBar (optional)
    if ! perl -MTerm::ProgressBar -e 1 2>/dev/null; then
        print_warning "Term::ProgressBar not found (progress bars will be basic)"
        # Don't fail on optional module
    fi
    
    if [ "$modules_ok" = false ]; then
        detect_package_manager
        check_privileges
        
        print_install "Installing missing Perl modules..."
        
        case "$PKG_MANAGER" in
            apt)
                $SUDO apt-get install -y libjson-perl 2>/dev/null || true
                ;;
            dnf|yum)
                $SUDO $PKG_INSTALL perl-JSON 2>/dev/null || true
                ;;
            pacman)
                $SUDO $PKG_INSTALL perl-json 2>/dev/null || true
                ;;
            *)
                # Fallback to CPAN
                print_warning "Installing via CPAN (may take a moment)..."
                for mod in "${modules_to_install[@]}"; do
                    $SUDO perl -MCPAN -e "install $mod" 2>/dev/null || true
                done
                ;;
        esac
        
        # Verify again
        if perl -MJSON -e 1 2>/dev/null; then
            print_success "Perl modules installed"
        else
            print_warning "Could not install JSON module via package manager"
            print_warning "Attempting CPAN installation..."
            $SUDO perl -MCPAN -e 'install JSON' 2>/dev/null || {
                print_warning "Manual install may be required: perl -MCPAN -e 'install JSON'"
            }
        fi
    else
        print_success "All required Perl modules are installed"
    fi
}

# Create configuration
create_config() {
    print_status "Setting up configuration..."
    
    mkdir -p "$CONFIG_DIR"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        if [ -f "$SCRIPT_DIR/config.json" ]; then
            cp "$SCRIPT_DIR/config.json" "$CONFIG_FILE"
            print_success "Created configuration from template"
        else
            # Create default config
            cat > "$CONFIG_FILE" << 'EOF'
{
  "version": "2.0.0",
  "presets": {
    "webready": {
      "description": "Optimized for web - smallest size with acceptable quality",
      "quality": 65,
      "method": 6,
      "alpha_quality": 80,
      "file_handling": {"mode": "preserve"},
      "output": {"mode": "subfolder", "subfolder_name": "webp"}
    },
    "medium": {
      "description": "Balanced quality and size",
      "quality": 75,
      "method": 4,
      "alpha_quality": 90,
      "file_handling": {"mode": "preserve"},
      "output": {"mode": "subfolder", "subfolder_name": "webp"}
    },
    "large": {
      "description": "High quality for archival",
      "quality": 90,
      "method": 6,
      "alpha_quality": 100,
      "file_handling": {"mode": "preserve"},
      "output": {"mode": "subfolder", "subfolder_name": "webp"}
    }
  },
  "default_preset": "webready"
}
EOF
            print_success "Created default configuration"
        fi
    else
        print_success "Configuration already exists (preserved)"
    fi
}

# Set script permissions
set_permissions() {
    print_status "Setting script permissions..."
    
    chmod +x "$SCRIPT_DIR/picasso.sh" 2>/dev/null || true
    chmod +x "$SCRIPT_DIR/picasso_engine.pl" 2>/dev/null || true
    
    print_success "Scripts made executable"
}

# Select installation type
select_install_type() {
    echo ""
    echo -e "${BOLD}Select Installation Type:${NC}"
    echo ""
    echo "  1) Local User (~/.local/bin)"
    echo "     - No elevated privileges required for future runs"
    echo "     - Only accessible by current user"
    echo "     - Recommended for personal use"
    echo ""
    echo "  2) System Wide (/usr/local/bin)"
    echo "     - Accessible by all users"
    echo "     - Requires root privileges"
    echo ""
    
    read -p "Select [1-2] (default: 1): " choice
    
    case "$choice" in
        2)
            INSTALL_TYPE="system"
            TARGET_BIN="$SYSTEM_BIN"
            ;;
        *)
            INSTALL_TYPE="local"
            TARGET_BIN="$LOCAL_BIN"
            ;;
    esac
}

# Perform installation
do_install() {
    print_status "Installing PICASSO..."
    
    # Create target directory
    if [ ! -d "$TARGET_BIN" ]; then
        mkdir -p "$TARGET_BIN"
        print_status "Created directory: $TARGET_BIN"
    fi
    
    # Create symlink
    local symlink_target="$TARGET_BIN/$APP_NAME"
    
    # Remove old symlink if exists
    rm -f "$symlink_target" 2>/dev/null
    
    # Create new symlink
    if ln -sf "$SCRIPT_DIR/picasso.sh" "$symlink_target"; then
        print_success "Created symlink: $symlink_target"
        print_success "Linked to: $SCRIPT_DIR/picasso.sh"
    else
        print_error "Failed to create symlink"
        exit 1
    fi
    
    # Store installation info
    cat > "$CONFIG_DIR/.install_info" << EOF
INSTALL_DIR=$SCRIPT_DIR
INSTALL_TYPE=$INSTALL_TYPE
INSTALL_DATE=$(date)
INSTALL_VERSION=$APP_VERSION
EOF
    
    print_success "Installation info saved"
}

# Verify PATH
verify_path() {
    if [ "$INSTALL_TYPE" = "local" ]; then
        if [[ ":$PATH:" != *":$LOCAL_BIN:"* ]]; then
            echo ""
            print_warning "$LOCAL_BIN is not in your PATH"
            echo ""
            echo -e "${YELLOW}Add this to your ~/.bashrc:${NC}"
            echo ""
            echo "    export PATH=\"\$HOME/.local/bin:\$PATH\""
            echo ""
            echo -e "${YELLOW}Then run: source ~/.bashrc${NC}"
            echo ""
            
            # Offer to add it automatically
            read -p "Add to PATH automatically? [y/N]: " addpath
            if [[ "$addpath" =~ ^[Yy]$ ]]; then
                echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
                print_success "Added to ~/.bashrc"
                print_warning "Run 'source ~/.bashrc' or open a new terminal"
            fi
        fi
    fi
}

# Verify installation
verify_installation() {
    print_status "Verifying installation..."
    
    local errors=0
    
    # Check symlink
    if [ -L "$TARGET_BIN/$APP_NAME" ]; then
        print_success "Symlink verified"
    else
        print_error "Symlink not found"
        errors=$((errors + 1))
    fi
    
    # Check scripts exist
    if [ -f "$SCRIPT_DIR/picasso.sh" ]; then
        print_success "Main script found"
    else
        print_error "Main script not found"
        errors=$((errors + 1))
    fi
    
    if [ -f "$SCRIPT_DIR/picasso_engine.pl" ]; then
        print_success "Engine script found"
    else
        print_error "Engine script not found"
        errors=$((errors + 1))
    fi
    
    # Check config
    if [ -f "$CONFIG_FILE" ]; then
        print_success "Configuration found"
    else
        print_error "Configuration not found"
        errors=$((errors + 1))
    fi
    
    # Check executable
    if [ -x "$TARGET_BIN/$APP_NAME" ]; then
        print_success "Binary is executable"
    else
        print_error "Binary is not executable"
        errors=$((errors + 1))
    fi
    
    return $errors
}

# Print success message
print_success_message() {
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                    Installation Complete!                    ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BOLD}Installation Details:${NC}"
    echo "    Version:      $APP_VERSION"
    echo "    Install Type: $INSTALL_TYPE"
    echo "    Binary:       $TARGET_BIN/$APP_NAME"
    echo "    Config:       $CONFIG_FILE"
    echo "    Scripts:      $SCRIPT_DIR"
    echo ""
    echo -e "${BOLD}Quick Start:${NC}"
    echo "    $APP_NAME              # Launch interactive TUI"
    echo "    $APP_NAME wizard       # Create/edit presets"
    echo "    $APP_NAME webready .   # Convert images in current folder"
    echo ""
    echo -e "${BOLD}Features:${NC}"
    echo "    • Multiple output modes (subfolder, same_dir, custom_path)"
    echo "    • Flexible file handling (preserve, delete, move, backup)"
    echo "    • Image resizing options"
    echo "    • Metadata control"
    echo "    • WebP optimization mode"
    echo ""
    echo -e "${DIM}Run this installer anytime to repair or update.${NC}"
    echo ""
}

# Uninstall function
do_uninstall() {
    print_status "Uninstalling PICASSO..."
    
    rm -f "$LOCAL_BIN/$APP_NAME" 2>/dev/null && print_success "Removed $LOCAL_BIN/$APP_NAME"
    rm -f "$SYSTEM_BIN/$APP_NAME" 2>/dev/null && print_success "Removed $SYSTEM_BIN/$APP_NAME"
    
    echo ""
    read -p "Remove configuration files? [y/N]: " rmconfig
    if [[ "$rmconfig" =~ ^[Yy]$ ]]; then
        rm -rf "$CONFIG_DIR"
        print_success "Removed configuration directory"
    fi
    
    echo ""
    print_success "Uninstall complete"
}

# Repair mode
do_repair() {
    print_status "Repairing PICASSO installation..."
    echo ""
    
    # Read existing install info if available
    if [ -f "$CONFIG_DIR/.install_info" ]; then
        source "$CONFIG_DIR/.install_info"
        print_status "Found previous installation: $INSTALL_TYPE"
        print_status "Original location: $INSTALL_DIR"
    fi
    
    # Run through all steps
    install_system_dependencies
    install_perl_modules
    create_config
    set_permissions
    
    # Set target based on existing or default
    if [ -n "$INSTALL_TYPE" ]; then
        if [ "$INSTALL_TYPE" = "system" ]; then
            TARGET_BIN="$SYSTEM_BIN"
        else
            TARGET_BIN="$LOCAL_BIN"
        fi
    else
        TARGET_BIN="$LOCAL_BIN"
        INSTALL_TYPE="local"
    fi
    
    do_install
    
    if verify_installation; then
        echo ""
        print_success "Repair complete!"
    else
        print_warning "Some issues remain - check errors above"
    fi
}

# Show help
show_help() {
    echo "PICASSO Installer v${APP_VERSION}"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "This installer will:"
    echo "  • Install all required dependencies automatically"
    echo "  • Set up PICASSO for local or system-wide use"
    echo "  • Create/repair configuration files"
    echo ""
    echo "Options:"
    echo "  --help, -h      Show this help message"
    echo "  --uninstall, -u Remove PICASSO from system"
    echo "  --repair, -r    Repair existing installation"
    echo "  --deps-only     Only install dependencies"
    echo ""
    echo "Run without options for interactive installation."
    echo ""
    echo "The installer is idempotent - run it repeatedly to repair."
}

# Install dependencies only
do_deps_only() {
    install_system_dependencies
    install_perl_modules
    print_success "Dependencies installed"
}

# Main function
main() {
    print_header
    
    case "${1:-}" in
        --uninstall|-u)
            do_uninstall
            exit 0
            ;;
        --repair|-r)
            do_repair
            exit 0
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        --deps-only)
            do_deps_only
            exit 0
            ;;
    esac
    
    # Full installation flow
    install_system_dependencies
    install_perl_modules
    create_config
    set_permissions
    select_install_type
    do_install
    verify_path
    
    if verify_installation; then
        print_success_message
    else
        print_warning "Installation completed with some issues"
    fi
}

main "$@"
