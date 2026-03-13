#!/bin/bash
#
# PICASSO - WebP Image Conversion Tool v2.0
# A comprehensive TUI tool for batch converting images to WebP format
#
# Usage: picasso [preset] [directory] [options]
#         picasso wizard
#         picasso --help
#

set -e

# --- Configuration ---
APP_NAME="picasso"
APP_VERSION="2.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$HOME/.config/picasso"
CONFIG_FILE="$CONFIG_DIR/config.json"
ENGINE_SCRIPT="$SCRIPT_DIR/picasso_engine.pl"
LOG_FILE="/tmp/picasso_$$.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
NC='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'

# --- Utility Functions ---

print_banner() {
    echo -e "${CYAN}"
    echo "  ╔══════════════════════════════════════════════════════════════╗"
    echo "  ║                                                              ║"
    echo "  ║  # #####  #  ####    ##    ####   ####   ####                ║"
    echo "  ║  # #    # # #    #  #  #  #      #      #    #               ║"
    echo "  ║  # #    # # #      #    #  ####   ####  #    #               ║"
    echo "  ║  # #####  # #      ######      #      # #    #               ║"
    echo "  ║  # #      # #    # #    # #    # #    # #    #               ║"
    echo "  ║  # #      #  ####  #    #  ####   ####   ####                ║"
    echo "  ║                                                              ║"
    echo "  ║           WebP Image Conversion Tool v${APP_VERSION}                ║"
    echo "  ║                                                              ║"
    echo "  ╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_status() { echo -e "${BLUE}[*]${NC} $1"; }
print_success() { echo -e "${GREEN}[✓]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }
print_info() { echo -e "${CYAN}[i]${NC} $1"; }

command_exists() { command -v "$1" &> /dev/null; }

check_whiptail() {
    if ! command_exists whiptail; then
        print_error "whiptail is not installed"
        echo "Install with: sudo apt-get install whiptail"
        exit 1
    fi
}

check_cwebp() {
    if ! command_exists cwebp; then
        print_error "cwebp is not installed"
        echo "Install with: sudo apt-get install webp"
        exit 1
    fi
}

ensure_config() {
    mkdir -p "$CONFIG_DIR"
    if [ ! -f "$CONFIG_FILE" ]; then
        create_default_config
    fi
}

create_default_config() {
    cat > "$CONFIG_FILE" << 'CONFIGEOF'
{
  "version": "2.0.0",
  "presets": {
    "webready": {
      "description": "Optimized for web - smallest size with acceptable quality",
      "input_formats": ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "tif"],
      "output_format": "webp",
      "quality": 65,
      "method": 6,
      "alpha_quality": 80,
      "lossless": false,
      "file_handling": {
        "mode": "preserve",
        "delete_originals": false,
        "move_originals_to": null,
        "backup_enabled": false,
        "backup_folder": "originals_backup"
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
  },
  "default_preset": "webready"
}
CONFIGEOF
    print_success "Created default configuration"
}

# --- JSON Helpers using Perl ---

get_preset_names() {
    perl -MJSON -e '
        local $/;
        open my $fh, "<", $ARGV[0] or die "Cannot open config: $!";
        my $data = decode_json(<$fh>);
        print join("\n", sort keys %{$data->{presets}});
    ' "$CONFIG_FILE" 2>/dev/null
}

get_preset_value() {
    local preset="$1"
    local key="$2"
    local default="${3:-}"
    perl -MJSON -e '
        my ($file, $preset, $key, $default) = @ARGV;
        local $/;
        open my $fh, "<", $file or die "Cannot open config: $!";
        my $data = decode_json(<$fh>);
        my $val = $data->{presets}->{$preset};
        for my $k (split /\./, $key) {
            $val = $val->{$k} if ref $val eq "HASH";
        }
        print defined $val ? $val : ($default // "");
    ' "$CONFIG_FILE" "$preset" "$key" "$default" 2>/dev/null
}

get_preset_description() {
    local preset="$1"
    perl -MJSON -e '
        my ($file, $preset) = @ARGV;
        local $/;
        open my $fh, "<", $file or die "Cannot open config: $!";
        my $data = decode_json(<$fh>);
        print $data->{presets}->{$preset}->{description} // "No description";
    ' "$CONFIG_FILE" "$preset" 2>/dev/null
}

save_preset() {
    local name="$1"
    shift
    perl -MJSON -e '
        my ($file, $name, @args) = @ARGV;
        local $/;
        
        open my $fh, "<", $file or die "Cannot open config: $!";
        my $data = decode_json(<$fh>);
        close $fh;
        
        my %preset;
        while (@args) {
            my $k = shift @args;
            my $v = shift @args;
            # Handle nested keys like "file_handling.mode"
            my @parts = split /\./, $k;
            if (@parts > 1) {
                my $ref = \%preset;
                for my $p (@parts[0..$#parts-1]) {
                    $ref->{$p} //= {};
                    $ref = $ref->{$p};
                }
                $ref->{$parts[-1]} = $v;
            } else {
                $preset{$k} = $v;
            }
        }
        
        $data->{presets}->{$name} = \%preset;
        
        open my $wh, ">", $file or die "Cannot write config: $!";
        print $wh encode_json($data);
        close $wh;
    ' "$CONFIG_FILE" "$name" "$@"
}

delete_preset() {
    local name="$1"
    perl -MJSON -e '
        my ($file, $name) = @ARGV;
        local $/;
        
        open my $fh, "<", $file or die "Cannot open config: $!";
        my $data = decode_json(<$fh>);
        close $fh;
        
        delete $data->{presets}->{$name};
        
        open my $wh, ">", $file or die "Cannot write config: $!";
        print $wh encode_json($data);
        close $wh;
    ' "$CONFIG_FILE" "$name"
}

# --- Main Menu ---

show_main_menu() {
    local choice
    choice=$(whiptail --title "PICASSO v${APP_VERSION} - Main Menu" --menu \
        "Select an option:" 22 75 10 \
        "1" "🚀 Quick Convert - Run preset on folder" \
        "2" "🔧 Wizard - Create/edit presets (full options)" \
        "3" "⚡ Quick Wizard - Fast preset creation" \
        "4" "📋 List Presets - View all saved presets" \
        "5" "🗑️ Delete Preset - Remove a preset" \
        "6" "🔄 Optimize WebP - Re-compress existing WebP files" \
        "7" "⚙️ Settings - Application configuration" \
        "8" "📦 Check Dependencies" \
        "9" "❓ Help & About" \
        "0" "Exit" \
        3>&1 1>&2 2>&3)
    
    exit_status=$?
    if [ $exit_status -ne 0 ]; then exit 0; fi
    
    case "$choice" in
        1) show_convert_menu ;;
        2) show_full_wizard ;;
        3) show_quick_wizard ;;
        4) show_list_presets ;;
        5) show_delete_preset ;;
        6) show_optimize_webp ;;
        7) show_settings ;;
        8) check_dependencies_tui ;;
        9) show_help_tui ;;
        0) exit 0 ;;
    esac
}

# --- Quick Convert Menu ---

show_convert_menu() {
    local presets
    presets=$(get_preset_names)
    
    if [ -z "$presets" ]; then
        whiptail --title "No Presets" --msgbox \
            "No presets found. Please create one using the Wizard first." 10 50
        show_main_menu
        return
    fi
    
    local menu_items=()
    while IFS= read -r preset; do
        local desc
        desc=$(get_preset_description "$preset")
        menu_items+=("$preset" "$desc")
    done <<< "$presets"
    
    local selected_preset
    selected_preset=$(whiptail --title "Select Preset" --menu \
        "Choose a conversion preset:" 20 75 12 \
        "${menu_items[@]}" \
        3>&1 1>&2 2>&3)
    
    if [ $? -ne 0 ]; then show_main_menu; return; fi
    
    local target_dir
    target_dir=$(whiptail --title "Select Directory" --inputbox \
        "Enter the path to the directory containing images:" 10 70 \
        "$(pwd)" 3>&1 1>&2 2>&3)
    
    if [ $? -ne 0 ]; then show_main_menu; return; fi
    
    if [ ! -d "$target_dir" ]; then
        whiptail --title "Error" --msgbox "Directory does not exist: $target_dir" 10 50
        show_convert_menu
        return
    fi
    
    run_conversion "$selected_preset" "$target_dir"
}

# --- Full Wizard (Expanded) ---

show_full_wizard() {
    local preset_name quality method alpha_quality
    local file_mode move_folder backup_folder
    local output_mode output_subfolder custom_output_path
    local resize_enabled resize_width resize_height resize_max
    local preserve_exif preserve_icc strip_metadata
    local lossless_mode append_suffix
    
    # STEP 1: Preset Name
    preset_name=$(whiptail --title "Wizard Step 1/10: Preset Name" --inputbox \
        "Enter a name for this preset:" 10 60 \
        3>&1 1>&2 2>&3)
    
    if [ $? -ne 0 ]; then show_main_menu; return; fi
    
    # Check for existing preset
    if get_preset_value "$preset_name" "quality" &>/dev/null; then
        whiptail --title "Existing Preset" --yesno \
            "Preset '$preset_name' already exists. Overwrite?" 8 50
        if [ $? -ne 0 ]; then show_main_menu; return; fi
    fi
    
    # STEP 2: Conversion Mode
    local conv_mode
    conv_mode=$(whiptail --title "Wizard Step 2/10: Conversion Mode" --menu \
        "Select conversion mode:" 18 70 5 \
        "Standard" "Normal quality-based compression" \
        "Lossless" "Perfect quality, larger files (PNG source)" \
        "Near-Lossless" "Almost lossless, smaller than lossless" \
        "Optimize" "Re-optimize existing WebP files" \
        3>&1 1>&2 2>&3)
    
    if [ $? -ne 0 ]; then show_main_menu; return; fi
    
    case "$conv_mode" in
        "Lossless")
            lossless_mode="true"
            quality=100
            method=6
            ;;
        "Near-Lossless")
            lossless_mode="false"
            quality=$(whiptail --title "Near-Lossless Quality" --inputbox \
                "Enter near-lossless quality (60-100):" 10 50 "90" 3>&1 1>&2 2>&3)
            method=6
            ;;
        "Optimize")
            lossless_mode="false"
            # Optimization mode specific options
            quality=$(whiptail --title "Optimization Quality" --inputbox \
                "Re-compress at quality (0-100):" 10 50 "75" 3>&1 1>&2 2>&3)
            method=6
            ;;
        *)
            lossless_mode="false"
            # STEP 3: Quality Selection
            local quality_preset
            quality_preset=$(whiptail --title "Wizard Step 3/10: Quality" --menu \
                "Select quality level:" 20 70 7 \
                "Minimum (50)" "Smallest files, noticeable quality loss" \
                "Low (60)" "Small files, acceptable for thumbnails" \
                "Web (65)" "Web optimized, good balance" \
                "Medium (75)" "Balanced quality and size" \
                "High (85)" "High quality, larger files" \
                "Maximum (90)" "Very high quality" \
                "Custom" "Enter a custom value" \
                3>&1 1>&2 2>&3)
            
            if [ $? -ne 0 ]; then show_main_menu; return; fi
            
            case "$quality_preset" in
                "Minimum (50)") quality=50 ;;
                "Low (60)") quality=60 ;;
                "Web (65)") quality=65 ;;
                "Medium (75)") quality=75 ;;
                "High (85)") quality=85 ;;
                "Maximum (90)") quality=90 ;;
                "Custom")
                    quality=$(whiptail --title "Custom Quality" --inputbox \
                        "Enter quality (0-100):" 10 50 "75" 3>&1 1>&2 2>&3)
                    ;;
            esac
            ;;
    esac
    
    # STEP 4: Compression Method
    if [ "$lossless_mode" != "true" ]; then
        method=$(whiptail --title "Wizard Step 4/10: Compression Method" --menu \
            "Select compression speed vs size tradeoff:" 18 70 5 \
            "0" "Fastest - Quick conversion, larger files" \
            "2" "Fast - Good for bulk operations" \
            "4" "Medium - Balanced (recommended)" \
            "5" "Slow - Better compression" \
            "6" "Slowest - Maximum compression" \
            3>&1 1>&2 2>&3)
        
        if [ $? -ne 0 ]; then show_main_menu; return; fi
    fi
    
    # STEP 5: Alpha Quality
    alpha_quality=$(whiptail --title "Wizard Step 5/10: Alpha Quality" --inputbox \
        "Alpha channel quality for transparent PNGs (0-100):\n100 = lossless transparency" 12 60 \
        "90" 3>&1 1>&2 2>&3)
    
    if [ $? -ne 0 ]; then alpha_quality=90; fi
    
    # STEP 6: File Handling Mode
    file_mode=$(whiptail --title "Wizard Step 6/10: Original Files" --radiolist \
        "What should happen to original files?" 18 70 5 \
        "preserve" "Keep originals in place (safest)" ON \
        "delete" "Delete originals after conversion (dangerous!)" OFF \
        "move" "Move originals to a folder" OFF \
        "backup" "Create backup before conversion" OFF \
        3>&1 1>&2 2>&3)
    
    if [ $? -ne 0 ]; then show_main_menu; return; fi
    
    case "$file_mode" in
        "move")
            move_folder=$(whiptail --title "Move Destination" --inputbox \
                "Enter folder name to move originals to:" 10 60 \
                "old_images" 3>&1 1>&2 2>&3)
            if [ $? -ne 0 ]; then move_folder="old_images"; fi
            ;;
        "backup")
            backup_folder=$(whiptail --title "Backup Folder" --inputbox \
                "Enter backup folder name:" 10 60 \
                "originals_backup" 3>&1 1>&2 2>&3)
            if [ $? -ne 0 ]; then backup_folder="originals_backup"; fi
            ;;
        "delete")
            whiptail --title "⚠️ Warning" --yesno \
                "WARNING: This will DELETE original files!\nThis action cannot be undone.\n\nAre you sure?" 12 50
            if [ $? -ne 0 ]; then
                file_mode="preserve"
                print_status "Changed to preserve mode for safety"
            fi
            ;;
    esac
    
    # STEP 7: Output Location
    output_mode=$(whiptail --title "Wizard Step 7/10: Output Location" --radiolist \
        "Where should converted files be saved?" 18 70 5 \
        "subfolder" "Create subfolder in source directory" ON \
        "same_directory" "Save in same directory as source" OFF \
        "custom_path" "Save to a different directory" OFF \
        "flatten" "Flatten all to single output folder" OFF \
        3>&1 1>&2 2>&3)
    
    if [ $? -ne 0 ]; then show_main_menu; return; fi
    
    case "$output_mode" in
        "subfolder")
            output_subfolder=$(whiptail --title "Subfolder Name" --inputbox \
                "Enter subfolder name for converted images:" 10 60 \
                "webp" 3>&1 1>&2 2>&3)
            if [ $? -ne 0 ]; then output_subfolder="webp"; fi
            ;;
        "same_directory")
            output_subfolder=""
            append_suffix=$(whiptail --title "Filename Suffix" --inputbox \
                "Add suffix to filenames? (leave empty for no suffix):" 10 60 \
                "" 3>&1 1>&2 2>&3)
            ;;
        "custom_path")
            custom_output_path=$(whiptail --title "Custom Output Path" --inputbox \
                "Enter full output directory path:" 10 60 \
                "./converted_output" 3>&1 1>&2 2>&3)
            if [ $? -ne 0 ]; then custom_output_path="./converted_output"; fi
            ;;
        "flatten")
            output_subfolder=$(whiptail --title "Output Folder" --inputbox \
                "All images will be saved to this folder (flat structure):" 10 60 \
                "all_converted" 3>&1 1>&2 2>&3)
            ;;
    esac
    
    # STEP 8: Resizing Options
    whiptail --title "Wizard Step 8/10: Resizing" --yesno \
        "Enable image resizing?" 8 50
    
    if [ $? -eq 0 ]; then
        resize_enabled="true"
        local resize_mode
        resize_mode=$(whiptail --title "Resize Mode" --radiolist \
            "How would you like to resize?" 15 60 3 \
            "dimensions" "Set exact width and height" ON \
            "max_dimension" "Set maximum dimension (maintains aspect)" OFF \
            "percentage" "Scale by percentage" OFF \
            3>&1 1>&2 2>&3)
        
        case "$resize_mode" in
            "dimensions")
                resize_width=$(whiptail --title "Width" --inputbox \
                    "Enter maximum width (px):" 10 50 "1920" 3>&1 1>&2 2>&3)
                resize_height=$(whiptail --title "Height" --inputbox \
                    "Enter maximum height (px):" 10 50 "1080" 3>&1 1>&2 2>&3)
                ;;
            "max_dimension")
                resize_max=$(whiptail --title "Max Dimension" --inputbox \
                    "Maximum dimension in pixels (width or height):" 10 50 "1200" 3>&1 1>&2 2>&3)
                ;;
            "percentage")
                resize_max=$(whiptail --title "Scale Percentage" --inputbox \
                    "Scale to percentage (e.g., 50 = half size):" 10 50 "50" 3>&1 1>&2 2>&3)
                ;;
        esac
    else
        resize_enabled="false"
    fi
    
    # STEP 9: Metadata Options
    whiptail --title "Wizard Step 9/10: Metadata" --yesno \
        "Preserve metadata (EXIF, ICC profiles)?" 8 50
    
    if [ $? -eq 0 ]; then
        preserve_exif="true"
        preserve_icc="true"
        strip_metadata="false"
    else
        strip_metadata=$(whiptail --title "Strip Metadata" --yesno \
            "Strip all metadata? (Good for privacy/smaller files)" 8 50 && echo "true" || echo "false")
        preserve_exif="false"
        preserve_icc="false"
    fi
    
    # STEP 10: Description and Save
    local description
    description=$(whiptail --title "Wizard Step 10/10: Description" --inputbox \
        "Enter a description for this preset:" 10 60 \
        "Quality $quality, $file_mode mode" 3>&1 1>&2 2>&3)
    
    if [ $? -ne 0 ]; then
        description="Quality $quality, $file_mode mode"
    fi
    
    # Build summary
    local summary="════════════════════════════════════════════════\n"
    summary+="                PRESET SUMMARY\n"
    summary+="════════════════════════════════════════════════\n\n"
    summary+="Preset Name: $preset_name\n"
    summary+="Description: $description\n\n"
    summary+="─── Compression ───\n"
    summary+="Mode: $conv_mode\n"
    summary+="Quality: $quality\n"
    summary+="Method: $method\n"
    summary+="Alpha Quality: $alpha_quality\n\n"
    summary+="─── File Handling ───\n"
    summary+="Originals: $file_mode\n"
    
    [ -n "$move_folder" ] && summary+="Move to: $move_folder\n"
    [ -n "$backup_folder" ] && summary+="Backup to: $backup_folder\n"
    
    summary+="\n─── Output ───\n"
    summary+="Mode: $output_mode\n"
    [ -n "$output_subfolder" ] && summary+="Subfolder: $output_subfolder\n"
    [ -n "$custom_output_path" ] && summary+="Custom Path: $custom_output_path\n"
    [ -n "$append_suffix" ] && summary+="Suffix: $append_suffix\n"
    
    [ "$resize_enabled" = "true" ] && summary+="\n─── Resizing ───\nEnabled: Yes\n"
    
    summary+="\n────────────────────────────────────────────────\n"
    summary+="Save this preset?"
    
    whiptail --title "Confirm & Save" --yesno "$summary" 28 65
    
    if [ $? -ne 0 ]; then
        whiptail --title "Cancelled" --msgbox "Preset not saved." 8 40
        show_main_menu
        return
    fi
    
    # Save preset with all options
    save_preset "$preset_name" \
        "description" "$description" \
        "quality" "$quality" \
        "method" "$method" \
        "alpha_quality" "$alpha_quality" \
        "lossless" "$lossless_mode" \
        "file_handling.mode" "$file_mode" \
        "file_handling.delete_originals" "$([ "$file_mode" = "delete" ] && echo "true" || echo "false")" \
        "file_handling.move_originals_to" "${move_folder:-}" \
        "file_handling.backup_enabled" "$([ "$file_mode" = "backup" ] && echo "true" || echo "false")" \
        "file_handling.backup_folder" "${backup_folder:-}" \
        "output.mode" "$output_mode" \
        "output.subfolder_name" "${output_subfolder:-}" \
        "output.custom_path" "${custom_output_path:-}" \
        "output.append_suffix" "${append_suffix:-}" \
        "output.preserve_structure" "$([ "$output_mode" != "flatten" ] && echo "true" || echo "false")" \
        "output.flatten" "$([ "$output_mode" = "flatten" ] && echo "true" || echo "false")" \
        "resizing.enabled" "$resize_enabled" \
        "resizing.width" "${resize_width:-}" \
        "resizing.height" "${resize_height:-}" \
        "resizing.max_dimension" "${resize_max:-}" \
        "metadata.preserve_exif" "$preserve_exif" \
        "metadata.preserve_icc" "$preserve_icc" \
        "metadata.strip_all" "$strip_metadata"
    
    whiptail --title "Success" --msgbox "Preset '$preset_name' saved successfully!" 10 50
    
    # Ask to test
    whiptail --title "Test Preset?" --yesno "Test this preset on a folder now?" 8 50
    
    if [ $? -eq 0 ]; then
        local test_dir
        test_dir=$(whiptail --title "Select Directory" --inputbox \
            "Enter test directory path:" 10 60 "$(pwd)" 3>&1 1>&2 2>&3)
        if [ -d "$test_dir" ]; then
            run_conversion "$preset_name" "$test_dir"
        fi
    fi
    
    show_main_menu
}

# --- Quick Wizard ---

show_quick_wizard() {
    local preset_name quality file_mode output_mode
    
    preset_name=$(whiptail --title "Quick Wizard" --inputbox \
        "Preset name:" 10 50 3>&1 1>&2 2>&3)
    [ $? -ne 0 ] && show_main_menu && return
    
    quality=$(whiptail --title "Quick Wizard - Quality" --menu \
        "Select quality:" 15 50 5 \
        "Web (65)" "Web optimized" \
        "Medium (75)" "Balanced" \
        "High (90)" "High quality" \
        3>&1 1>&2 2>&3)
    [ $? -ne 0 ] && quality="75"
    quality=$(echo "$quality" | grep -o '[0-9]*')
    
    file_mode=$(whiptail --title "Quick Wizard - Files" --radiolist \
        "Original files:" 12 50 3 \
        "preserve" "Keep originals" ON \
        "backup" "Create backup" OFF \
        "delete" "Delete originals" OFF \
        3>&1 1>&2 2>&3)
    [ $? -ne 0 ] && file_mode="preserve"
    
    output_mode=$(whiptail --title "Quick Wizard - Output" --inputbox \
        "Output subfolder name:" 10 50 "webp" 3>&1 1>&2 2>&3)
    [ $? -ne 0 ] && output_mode="webp"
    
    save_preset "$preset_name" \
        "description" "Quick preset - Quality $quality" \
        "quality" "$quality" \
        "method" "4" \
        "alpha_quality" "90" \
        "file_handling.mode" "$file_mode" \
        "output.subfolder_name" "$output_mode"
    
    whiptail --title "Created" --msgbox "Preset '$preset_name' created!" 8 40
    show_main_menu
}

# --- List Presets ---

show_list_presets() {
    local presets
    presets=$(get_preset_names)
    
    if [ -z "$presets" ]; then
        whiptail --title "No Presets" --msgbox "No presets found." 8 40
        show_main_menu
        return
    fi
    
    local text="Saved Presets:\n\n"
    while IFS= read -r preset; do
        local desc quality
        desc=$(get_preset_description "$preset")
        quality=$(get_preset_value "$preset" "quality")
        file_mode=$(get_preset_value "$preset" "file_handling.mode")
        text+="• ${BOLD}$preset${NC}\n"
        text+="  $desc\n"
        text+="  [Q:$quality | Mode:$file_mode]\n\n"
    done <<< "$presets"
    
    whiptail --title "Saved Presets" --msgbox "$text" 25 70
    show_main_menu
}

# --- Delete Preset ---

show_delete_preset() {
    local presets
    presets=$(get_preset_names)
    
    if [ -z "$presets" ]; then
        whiptail --title "No Presets" --msgbox "No presets to delete." 8 40
        show_main_menu
        return
    fi
    
    local menu_items=()
    while IFS= read -r preset; do
        menu_items+=("$preset" "")
    done <<< "$presets"
    
    local to_delete
    to_delete=$(whiptail --title "Delete Preset" --menu \
        "Select preset to delete:" 15 60 10 \
        "${menu_items[@]}" \
        3>&1 1>&2 2>&3)
    
    if [ $? -eq 0 ]; then
        whiptail --title "Confirm Delete" --yesno \
            "Delete preset '$to_delete'?" 8 50
        if [ $? -eq 0 ]; then
            delete_preset "$to_delete"
            whiptail --title "Deleted" --msgbox "Preset deleted." 8 40
        fi
    fi
    
    show_main_menu
}

# --- Optimize WebP ---

show_optimize_webp() {
    local target_dir
    target_dir=$(whiptail --title "Optimize WebP - Select Directory" --inputbox \
        "Enter directory containing WebP files to optimize:" 10 60 \
        "$(pwd)" 3>&1 1>&2 2>&3)
    
    if [ $? -ne 0 ] || [ ! -d "$target_dir" ]; then
        show_main_menu
        return
    fi
    
    local quality
    quality=$(whiptail --title "Optimization Quality" --inputbox \
        "Re-compress at quality (0-100):\nLower = smaller files, more quality loss" 12 50 \
        "75" 3>&1 1>&2 2>&3)
    
    [ -z "$quality" ] && quality=75
    
    local backup_choice
    whiptail --title "Backup" --yesno "Create backup of original WebP files?" 8 50
    if [ $? -eq 0 ]; then
        save_preset "_optimize_temp" \
            "description" "Temporary optimization" \
            "quality" "$quality" \
            "method" "6" \
            "input_formats" "webp" \
            "file_handling.mode" "backup" \
            "file_handling.backup_folder" "original_webp" \
            "output.mode" "same_directory"
    else
        save_preset "_optimize_temp" \
            "description" "Temporary optimization" \
            "quality" "$quality" \
            "method" "6" \
            "input_formats" "webp" \
            "file_handling.mode" "preserve" \
            "output.mode" "same_directory"
    fi
    
    run_conversion "_optimize_temp" "$target_dir"
    delete_preset "_optimize_temp"
}

# --- Settings ---

show_settings() {
    local choice
    choice=$(whiptail --title "Settings" --menu \
        "Application Settings:" 15 60 5 \
        "1" "View config file location" \
        "2" "Edit config file (advanced)" \
        "3" "Reset to default presets" \
        "4" "Back" \
        3>&1 1>&2 2>&3)
    
    case "$choice" in
        1) whiptail --title "Config Location" --msgbox \
            "Configuration file:\n$CONFIG_FILE" 10 50 ;;
        2) if command_exists nano; then
               whiptail --title "Edit Config" --yesno "Open in nano?" 8 40
               [ $? -eq 0 ] && nano "$CONFIG_FILE"
           fi ;;
        3) whiptail --title "Reset" --yesno "Reset all presets to defaults?" 8 50
           [ $? -eq 0 ] && create_default_config ;;
    esac
    
    show_main_menu
}

# --- Dependencies Check ---

check_dependencies_tui() {
    local text="Dependency Check:\n\n"
    local all_ok=true
    
    if command_exists cwebp; then
        text+="✓ cwebp (WebP encoder) - installed\n"
    else
        text+="✗ cwebp - MISSING\n"; all_ok=false
    fi
    
    if command_exists perl; then
        text+="✓ perl - installed\n"
    else
        text+="✗ perl - MISSING\n"; all_ok=false
    fi
    
    if command_exists whiptail; then
        text+="✓ whiptail - installed\n"
    else
        text+="✗ whiptail - MISSING\n"; all_ok=false
    fi
    
    if perl -MJSON -e 1 2>/dev/null; then
        text+="✓ JSON perl module - installed\n"
    else
        text+="✗ JSON perl module - MISSING\n"; all_ok=false
    fi
    
    if perl -MTerm::ProgressBar -e 1 2>/dev/null; then
        text+="✓ Term::ProgressBar - installed\n"
    else
        text+="! Term::ProgressBar - optional\n"
    fi
    
    text+="\n"
    
    if [ "$all_ok" = true ]; then
        text+="All required dependencies installed!"
    else
        text+="Install missing: sudo apt-get install webp whiptail libjson-perl"
    fi
    
    whiptail --title "Dependencies" --msgbox "$text" 20 60
    show_main_menu
}

# --- Help ---

show_help_tui() {
    whiptail --title "Help - PICASSO v${APP_VERSION}" --msgbox \
        "PICASSO - WebP Image Conversion Tool

Usage:
  picasso                    Interactive TUI
  picasso wizard             Full preset wizard
  picasso <preset> <dir>     Run preset on directory

Features:
  • Multiple output modes
  • Flexible file handling
  • Metadata preservation
  • Batch optimization
  • Parallel processing

Quick Start:
  1. Run 'picasso wizard'
  2. Create your preset
  3. Run 'picasso mypreset ./images/'

Config: ~/.config/picasso/config.json" 20 65
    show_main_menu
}

# --- Run Conversion ---

run_conversion() {
    local preset="$1"
    local target_dir="$2"
    
    # Get preset values
    local quality method alpha_quality lossless
    local file_mode backup_folder move_folder delete_originals backup_enabled
    local output_mode output_subfolder custom_path append_suffix flatten preserve_structure
    local resize_enabled resize_width resize_height resize_max
    local preserve_exif preserve_icc strip_all
    
    quality=$(get_preset_value "$preset" "quality" "75")
    method=$(get_preset_value "$preset" "method" "4")
    alpha_quality=$(get_preset_value "$preset" "alpha_quality" "90")
    lossless=$(get_preset_value "$preset" "lossless" "false")
    
    file_mode=$(get_preset_value "$preset" "file_handling.mode" "preserve")
    delete_originals=$(get_preset_value "$preset" "file_handling.delete_originals" "false")
    move_folder=$(get_preset_value "$preset" "file_handling.move_originals_to" "")
    backup_folder=$(get_preset_value "$preset" "file_handling.backup_folder" "originals_backup")
    backup_enabled=$(get_preset_value "$preset" "file_handling.backup_enabled" "false")
    
    output_mode=$(get_preset_value "$preset" "output.mode" "subfolder")
    output_subfolder=$(get_preset_value "$preset" "output.subfolder_name" "webp")
    custom_path=$(get_preset_value "$preset" "output.custom_path" "")
    append_suffix=$(get_preset_value "$preset" "output.append_suffix" "")
    flatten=$(get_preset_value "$preset" "output.flatten" "false")
    preserve_structure=$(get_preset_value "$preset" "output.preserve_structure" "true")
    
    resize_enabled=$(get_preset_value "$preset" "resizing.enabled" "false")
    resize_width=$(get_preset_value "$preset" "resizing.width" "")
    resize_height=$(get_preset_value "$preset" "resizing.height" "")
    resize_max=$(get_preset_value "$preset" "resizing.max_dimension" "")
    
    preserve_exif=$(get_preset_value "$preset" "metadata.preserve_exif" "true")
    preserve_icc=$(get_preset_value "$preset" "metadata.preserve_icc" "true")
    strip_all=$(get_preset_value "$preset" "metadata.strip_all" "false")
    
    # Count images
    local image_count
    image_count=$(find "$target_dir" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.gif" -o -iname "*.bmp" -o -iname "*.tiff" -o -iname "*.tif" -o -iname "*.webp" \) 2>/dev/null | wc -l)
    
    if [ "$image_count" -eq 0 ]; then
        whiptail --title "No Images" --msgbox "No compatible images found in:\n$target_dir" 10 50
        return 1
    fi
    
    # Build confirm text
    local confirm_text="Ready to Convert:\n\n"
    confirm_text+="Preset: $preset\n"
    confirm_text+="Directory: $target_dir\n"
    confirm_text+="Images Found: $image_count\n\n"
    confirm_text+="Quality: $quality | Method: $method\n"
    confirm_text+="File Mode: $file_mode\n"
    
    case "$output_mode" in
        "subfolder") confirm_text+="Output: $target_dir/$output_subfolder/\n" ;;
        "same_directory") confirm_text+="Output: Same directory\n" ;;
        "custom_path") confirm_text+="Output: $custom_path\n" ;;
        "flatten") confirm_text+="Output: $output_subfolder (flat)\n" ;;
    esac
    
    if [ "$delete_originals" = "true" ]; then
        confirm_text+="\n⚠️ WARNING: Originals will be DELETED!"
    elif [ "$backup_enabled" = "true" ]; then
        confirm_text+="\nBackup: $target_dir/$backup_folder/"
    fi
    
    whiptail --title "Confirm Conversion" --yesno "$confirm_text" 20 65
    if [ $? -ne 0 ]; then return 1; fi
    
    # Execution options
    local exec_mode parallel cores verbose logging
    
    exec_mode=$(whiptail --title "Execution Mode" --radiolist \
        "How to run?" 12 50 2 \
        "foreground" "Run in foreground" ON \
        "background" "Run in background" OFF \
        3>&1 1>&2 2>&3)
    [ $? -ne 0 ] && exec_mode="foreground"
    
    whiptail --title "Parallel Processing" --yesno \
        "Use all CPU cores? ($(nproc) available)" 8 50
    if [ $? -eq 0 ]; then
        parallel="true"
        cores=$(nproc)
    else
        parallel="false"
        cores=1
    fi
    
    whiptail --title "Verbose Mode" --yesno "Show detailed output?" 8 50
    verbose=$([ $? -eq 0 ] && echo "true" || echo "false")
    
    whiptail --title "Logging" --yesno "Save log to /tmp/picasso.log?" 8 50
    logging=$([ $? -eq 0 ] && echo "true" || echo "false")
    
    # Clear and run
    clear
    print_banner
    echo ""
    print_status "Starting conversion..."
    echo ""
    echo "  Preset:      $preset"
    echo "  Directory:   $target_dir"
    echo "  Images:      $image_count"
    echo "  Quality:     $quality"
    echo "  Method:      $method"
    echo "  Parallel:    $cores cores"
    echo "  File Mode:   $file_mode"
    echo "  Output:      $([ -n "$output_subfolder" ] && echo "$target_dir/$output_subfolder/" || echo "Same directory")"
    echo ""
    
    if [ "$exec_mode" = "background" ]; then
        nohup perl "$ENGINE_SCRIPT" \
            "$target_dir" "$quality" "$method" "$alpha_quality" \
            "$delete_originals" "$output_subfolder" "$backup_enabled" \
            "$backup_folder" "$cores" "$verbose" \
            "$file_mode" "$move_folder" "$output_mode" "$custom_path" \
            "$flatten" "$preserve_structure" "$append_suffix" \
            "$resize_enabled" "$resize_width" "$resize_height" "$resize_max" \
            "$lossless" "$preserve_exif" "$preserve_icc" "$strip_all" \
            > "$LOG_FILE" 2>&1 &
        
        print_success "Background process started (PID: $!)"
        echo "  Log: $LOG_FILE"
    else
        if [ "$logging" = "true" ]; then
            perl "$ENGINE_SCRIPT" \
                "$target_dir" "$quality" "$method" "$alpha_quality" \
                "$delete_originals" "$output_subfolder" "$backup_enabled" \
                "$backup_folder" "$cores" "$verbose" \
                "$file_mode" "$move_folder" "$output_mode" "$custom_path" \
                "$flatten" "$preserve_structure" "$append_suffix" \
                "$resize_enabled" "$resize_width" "$resize_height" "$resize_max" \
                "$lossless" "$preserve_exif" "$preserve_icc" "$strip_all" \
                2>&1 | tee "$LOG_FILE"
        else
            perl "$ENGINE_SCRIPT" \
                "$target_dir" "$quality" "$method" "$alpha_quality" \
                "$delete_originals" "$output_subfolder" "$backup_enabled" \
                "$backup_folder" "$cores" "$verbose" \
                "$file_mode" "$move_folder" "$output_mode" "$custom_path" \
                "$flatten" "$preserve_structure" "$append_suffix" \
                "$resize_enabled" "$resize_width" "$resize_height" "$resize_max" \
                "$lossless" "$preserve_exif" "$preserve_icc" "$strip_all"
        fi
        
        echo ""
        print_success "Conversion complete!"
        read -p "Press Enter to return to menu..."
    fi
}

# --- CLI Mode ---

show_cli_help() {
    print_banner
    cat << EOF

Usage: picasso [OPTIONS] [preset] [directory]

Commands:
  (none)          Launch interactive TUI menu
  wizard          Open full preset wizard
  quick           Open quick wizard
  list            List all saved presets
  optimize <dir>  Optimize WebP files in directory

Options:
  -h, --help      Show this help message
  -v, --version   Show version
  --dry-run       Preview without converting
  --verbose       Show detailed output
  --parallel N    Use N CPU cores
  --log           Save to log file
  --background    Run in background

Examples:
  picasso                         # Interactive mode
  picasso webready ./photos/      # Convert with preset
  picasso medium . --parallel 8   # Use 8 cores
  picasso optimize ./webps/       # Optimize WebPs

EOF
}

# --- Main Entry Point ---

main() {
    ensure_config
    
    case "${1:-}" in
        "") check_whiptail; check_cwebp; show_main_menu ;;
        wizard) check_whiptail; show_full_wizard ;;
        quick) check_whiptail; show_quick_wizard ;;
        list) get_preset_names | while read p; do echo "• $p"; done ;;
        optimize)
            if [ -n "${2:-}" ] && [ -d "$2" ]; then
                save_preset "_opt" "quality" "75" "method" "6" "input_formats" "webp"
                cli_convert "_opt" "$2"
                delete_preset "_opt"
            fi
            ;;
        -h|--help) show_cli_help ;;
        -v|--version) echo "PICASSO v$APP_VERSION" ;;
        *)
            if [ -n "${2:-}" ]; then
                cli_convert "$1" "$2" "${@:3}"
            else
                print_error "Missing directory"
                echo "Usage: picasso <preset> <directory>"
                exit 1
            fi
            ;;
    esac
}

cli_convert() {
    local preset="$1"
    local target_dir="$2"
    shift 2
    
    local quality
    quality=$(get_preset_value "$preset" "quality")
    
    if [ -z "$quality" ]; then
        print_error "Preset '$preset' not found"
        exit 1
    fi
    
    [ ! -d "$target_dir" ] && print_error "Directory not found: $target_dir" && exit 1
    
    print_status "Converting with preset '$preset'..."
    perl "$ENGINE_SCRIPT" "$target_dir" "$quality" \
        "$(get_preset_value "$preset" "method" "4")" \
        "$(get_preset_value "$preset" "alpha_quality" "90")" \
        "$(get_preset_value "$preset" "file_handling.delete_originals" "false")" \
        "$(get_preset_value "$preset" "output.subfolder_name" "webp")" \
        "$(get_preset_value "$preset" "file_handling.backup_enabled" "false")" \
        "$(get_preset_value "$preset" "file_handling.backup_folder" "backup")" \
        "$(nproc)" "false"
    
    print_success "Done!"
}

main "$@"
