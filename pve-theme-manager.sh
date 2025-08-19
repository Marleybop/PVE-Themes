#!/bin/bash

# Proxmox VE Theme Manager
# Manages themes for Proxmox VE web interface

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PVE_MANAGER_PATH="/usr/share/pve-manager"
PVE_IMAGES_PATH="$PVE_MANAGER_PATH/images"
PVE_INDEX_TEMPLATE="$PVE_MANAGER_PATH/index.html.tpl"
THEMES_DIR="$SCRIPT_DIR/themes"
ACTIVE_THEME_FILE="$PVE_IMAGES_PATH/pve-theme-active.css"

show_usage() {
    cat << EOF
🎨 Proxmox VE Theme Manager

Usage: $0 <command> [theme-name]

Commands:
    list                    List available themes
    install <theme-name>    Install/switch to a theme
    restore                 Restore original Proxmox theme
    status                  Show current theme status
    backup                  Create backup of original files
    preview <theme-name>    Show theme description

Examples:
    $0 list
    $0 install modern-dark
    $0 install ocean-blue
    $0 restore
    $0 status

Available themes:
EOF
    list_themes_short
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "❌ Error: This script must be run as root" >&2
        echo "Try: sudo $0 $*"
        exit 1
    fi
}

check_proxmox() {
    if [[ ! -d "$PVE_MANAGER_PATH" ]]; then
        echo "❌ Error: Proxmox VE not found. Is this running on a Proxmox VE server?" >&2
        exit 1
    fi
}

list_themes() {
    if [[ ! -d "$THEMES_DIR" ]]; then
        echo "❌ No themes directory found at $THEMES_DIR"
        return 1
    fi
    
    echo "🎨 Available Themes:"
    echo "==================="
    
    local themes=($(find "$THEMES_DIR" -name "*.css" -exec basename {} .css \; | sort))
    
    if [[ ${#themes[@]} -eq 0 ]]; then
        echo "No themes found"
        return 1
    fi
    
    for theme in "${themes[@]}"; do
        local status="  "
        if [[ -f "$ACTIVE_THEME_FILE" ]] && cmp -s "$THEMES_DIR/$theme.css" "$ACTIVE_THEME_FILE" 2>/dev/null; then
            status="🟢"
        fi
        
        case "$theme" in
            "modern-dark")
                echo "$status $theme - Sleek dark theme with modern gradients and shadows"
                ;;
            "ocean-blue")
                echo "$status $theme - Ocean-inspired blue theme with light/dark modes"
                ;;
            "forest-green")
                echo "$status $theme - Nature-inspired green theme with organic feel"
                ;;
            "minimal-light")
                echo "$status $theme - Clean, minimal design with subtle styling"
                ;;
            *)
                echo "$status $theme - Custom theme"
                ;;
        esac
    done
}

list_themes_short() {
    local themes=($(find "$THEMES_DIR" -name "*.css" -exec basename {} .css \; | sort))
    for theme in "${themes[@]}"; do
        echo "    • $theme"
    done
}

preview_theme() {
    local theme_name="$1"
    
    if [[ -z "$theme_name" ]]; then
        echo "❌ Theme name required"
        show_usage
        exit 1
    fi
    
    if [[ ! -f "$THEMES_DIR/$theme_name.css" ]]; then
        echo "❌ Theme '$theme_name' not found"
        list_themes
        exit 1
    fi
    
    echo "🔍 Theme Preview: $theme_name"
    echo "=============================="
    
    case "$theme_name" in
        "modern-dark")
            echo "🌙 Modern Dark Theme"
            echo "• Sleek dark interface with blue accents"
            echo "• Modern gradients and subtle shadows"
            echo "• Optimized for dark mode usage"
            echo "• Perfect for late-night administration"
            ;;
        "ocean-blue")
            echo "🌊 Ocean Blue Theme"
            echo "• Ocean-inspired blue color palette"
            echo "• Adaptive light and dark modes"
            echo "• Smooth transitions and hover effects"
            echo "• Calming, professional appearance"
            ;;
        "forest-green")
            echo "🌲 Forest Green Theme"
            echo "• Nature-inspired green color scheme"
            echo "• Organic feel with natural tones"
            echo "• Eye-friendly for extended use"
            echo "• Subtle nature-themed accents"
            ;;
        "minimal-light")
            echo "✨ Minimal Light Theme"
            echo "• Clean, distraction-free interface"
            echo "• Modern typography and spacing"
            echo "• Subtle borders and shadows"
            echo "• Focus on content and functionality"
            ;;
        *)
            echo "Custom theme: $theme_name"
            ;;
    esac
}

install_theme() {
    local theme_name="$1"
    
    if [[ -z "$theme_name" ]]; then
        echo "❌ Theme name required"
        show_usage
        exit 1
    fi
    
    local theme_file="$THEMES_DIR/$theme_name.css"
    
    if [[ ! -f "$theme_file" ]]; then
        echo "❌ Theme '$theme_name' not found"
        echo ""
        list_themes
        exit 1
    fi
    
    echo "🎨 Installing theme: $theme_name"
    
    # Copy theme to active location
    cp "$theme_file" "$ACTIVE_THEME_FILE"
    echo "✅ Theme files updated"
    
    # Restart pveproxy to apply changes
    restart_pveproxy
    
    echo "🎉 Theme '$theme_name' installed successfully!"
    echo "🌐 Refresh your browser to see the changes"
}

restore_original() {
    echo "🔄 Restoring original Proxmox theme..."
    
    # Remove active theme file
    if [[ -f "$ACTIVE_THEME_FILE" ]]; then
        rm "$ACTIVE_THEME_FILE"
        echo "✅ Removed custom theme"
    fi
    
    # Look for backup and restore if available
    local backup_file=""
    for dir in /tmp/pve-theme-backup-* /root/pve-theme-backup-*; do
        if [[ -f "$dir/index.html.tpl.original" ]]; then
            backup_file="$dir/index.html.tpl.original"
            break
        fi
    done
    
    if [[ -n "$backup_file" ]]; then
        cp "$backup_file" "$PVE_INDEX_TEMPLATE"
        echo "✅ Restored original index.html.tpl from backup"
    else
        echo "⚠️  No backup found - theme loader may still be active"
        echo "   Manual cleanup may be required"
    fi
    
    restart_pveproxy
    echo "🎉 Original Proxmox theme restored!"
}

show_status() {
    echo "📊 Proxmox VE Theme Manager Status"
    echo "=================================="
    echo "Manager Path: $SCRIPT_DIR"
    echo "Themes Path: $THEMES_DIR"
    echo ""
    
    if [[ -f "$ACTIVE_THEME_FILE" ]]; then
        # Try to identify current theme
        local current_theme="unknown"
        for theme_file in "$THEMES_DIR"/*.css; do
            if [[ -f "$theme_file" ]] && cmp -s "$theme_file" "$ACTIVE_THEME_FILE" 2>/dev/null; then
                current_theme=$(basename "$theme_file" .css)
                break
            fi
        done
        echo "🎨 Active Theme: $current_theme"
    else
        echo "🎨 Active Theme: Original Proxmox theme"
    fi
    
    echo ""
    local theme_count=$(find "$THEMES_DIR" -name "*.css" 2>/dev/null | wc -l)
    echo "📦 Available Themes: $theme_count"
    
    if [[ $theme_count -gt 0 ]]; then
        list_themes_short
    fi
    
    echo ""
    echo "🔧 Service Status:"
    if systemctl is-active --quiet pveproxy; then
        echo "   ✅ pveproxy service is running"
    else
        echo "   ❌ pveproxy service is not running"
    fi
}

restart_pveproxy() {
    echo "🔄 Restarting pveproxy service..."
    systemctl restart pveproxy
    sleep 2
    echo "✅ Service restarted"
}

main() {
    if [[ $# -eq 0 ]]; then
        show_usage
        exit 1
    fi
    
    check_root
    check_proxmox
    
    case "$1" in
        list|ls)
            list_themes
            ;;
        install|apply)
            install_theme "$2"
            ;;
        restore|reset)
            restore_original
            ;;
        status|info)
            show_status
            ;;
        preview|show)
            preview_theme "$2"
            ;;
        backup)
            echo "Backup functionality is handled during initial installation"
            echo "Backups are stored in /tmp/pve-theme-backup-* directories"
            ;;
        -h|--help|help)
            show_usage
            ;;
        *)
            echo "❌ Unknown command: $1"
            echo ""
            show_usage
            exit 1
            ;;
    esac
}

main "$@"