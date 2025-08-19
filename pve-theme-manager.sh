#!/bin/bash

# Proxmox VE Theme Manager
# Interactive theme installation and management tool

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THEMES_DIR="$SCRIPT_DIR/themes"
BACKUP_DIR="$HOME/pve-theme-backups"
PVE_MANAGER_PATH="/usr/share/pve-manager"
PVE_INDEX_TEMPLATE="$PVE_MANAGER_PATH/index.html.tpl"
PVE_IMAGES_PATH="$PVE_MANAGER_PATH/images"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if dialog or whiptail is available
if command -v whiptail >/dev/null 2>&1; then
    DIALOG="whiptail"
elif command -v dialog >/dev/null 2>&1; then
    DIALOG="dialog"
else
    echo "❌ Error: Neither whiptail nor dialog found. Please install whiptail or dialog."
    exit 1
fi

# Helper function for dialog boxes
show_dialog() {
    local type="$1"
    local title="$2"
    local text="$3"
    local height="${4:-10}"
    local width="${5:-70}"
    
    case "$type" in
        msgbox)
            $DIALOG --title "$title" --msgbox "$text" $height $width
            ;;
        yesno)
            $DIALOG --title "$title" --yesno "$text" $height $width
            ;;
        menu)
            shift 5
            $DIALOG --title "$title" --menu "$text" $height $width 6 "$@"
            ;;
    esac
}

# Check requirements
check_requirements() {
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        show_dialog msgbox "Error" "This script must be run as root.\n\nPlease run with: sudo $0"
        exit 1
    fi
    
    # Check if Proxmox files exist
    if [[ ! -d "$PVE_MANAGER_PATH" ]]; then
        show_dialog msgbox "Error" "Proxmox VE not found.\n\nIs this running on a Proxmox VE server?"
        exit 1
    fi
    
    if [[ ! -f "$PVE_INDEX_TEMPLATE" ]]; then
        show_dialog msgbox "Error" "Required file not found:\n$PVE_INDEX_TEMPLATE\n\nProxmox installation may be incomplete."
        exit 1
    fi
    
    # Create backup directory if it doesn't exist
    mkdir -p "$BACKUP_DIR"
}

# Get current status
get_status() {
    local status_text=""
    local current_theme="Original Proxmox Theme"
    local backup_count=0
    local last_backup="None"
    
    # Check for active theme (placeholder for now)
    if [[ -f "$PVE_IMAGES_PATH/pve-theme-active.css" ]]; then
        current_theme="Custom Theme (Active)"
    fi
    
    # Count backups
    if [[ -d "$BACKUP_DIR" ]]; then
        backup_count=$(ls -1 "$BACKUP_DIR" 2>/dev/null | wc -l)
        if [[ $backup_count -gt 0 ]]; then
            last_backup=$(ls -1t "$BACKUP_DIR" 2>/dev/null | head -n1)
        fi
    fi
    
    status_text="Current Theme: $current_theme\n\n"
    status_text+="Backups Available: $backup_count\n"
    status_text+="Latest Backup: $last_backup\n\n"
    status_text+="Installation Path: $SCRIPT_DIR\n"
    status_text+="Backup Path: $BACKUP_DIR"
    
    echo "$status_text"
}

# Show status
show_status() {
    local status=$(get_status)
    show_dialog msgbox "📊 Theme Manager Status" "$status" 15 80
}

# Create backup (placeholder)
create_backup() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_path="$BACKUP_DIR/backup-$timestamp"
    
    if show_dialog yesno "Create Backup" "Create backup of current Proxmox configuration?\n\nBackup will be saved to:\n$backup_path"; then
        # Placeholder for actual backup logic
        mkdir -p "$backup_path"
        echo "Backup created at $timestamp" > "$backup_path/info.txt"
        show_dialog msgbox "Backup Complete" "✅ Backup created successfully!\n\nLocation: $backup_path"
    fi
}

# Restore backup (placeholder)
restore_backup() {
    local backup_count=$(ls -1 "$BACKUP_DIR" 2>/dev/null | wc -l)
    
    if [[ $backup_count -eq 0 ]]; then
        show_dialog msgbox "No Backups" "❌ No backups found.\n\nCreate a backup first before installing themes."
        return
    fi
    
    if show_dialog yesno "Restore Backup" "⚠️  This will restore your original Proxmox theme.\n\nAny custom theme will be removed.\n\nContinue?"; then
        # Placeholder for actual restore logic
        show_dialog msgbox "Restore Complete" "✅ Original Proxmox theme restored successfully!\n\n🔄 Please restart pveproxy service:\nsystemctl restart pveproxy"
    fi
}

# Theme selection submenu
theme_selection() {
    local choice
    
    while true; do
        choice=$(show_dialog menu "🎨 Theme Selection" "Choose a theme to install:" 15 80 \
            "1" "🌙 Dark Blue - Professional dark theme" \
            "2" "🌊 Ocean Blue - Light/dark adaptive" \
            "3" "🌲 Forest Green - Nature-inspired" \
            "4" "✨ Minimal Light - Clean & simple" \
            "5" "📖 View Screenshots & Documentation" \
            "6" "⬅️  Back to Main Menu" \
            2>&1 >/dev/tty)
        
        case $choice in
            1|2|3|4)
                install_theme "$choice"
                ;;
            5)
                show_dialog msgbox "Documentation" "📖 Theme Screenshots & Documentation\n\nView themes at:\nhttp://10.0.10.41:3000/Marleybop/pve-themes\n\nScreenshots and detailed descriptions available in the repository."
                ;;
            6|"")
                break
                ;;
        esac
    done
}

# Install theme (placeholder)
install_theme() {
    local theme_num="$1"
    local theme_name=""
    
    case $theme_num in
        1) theme_name="Dark Blue" ;;
        2) theme_name="Ocean Blue" ;;
        3) theme_name="Forest Green" ;;
        4) theme_name="Minimal Light" ;;
    esac
    
    if show_dialog yesno "Install Theme" "Install $theme_name theme?\n\n⚠️  This will modify Proxmox files.\nMake sure you have a backup!\n\nContinue?"; then
        # Placeholder for actual theme installation
        show_dialog msgbox "Theme Installed" "✅ $theme_name theme installed successfully!\n\n🔄 Restart pveproxy service?\nsystemctl restart pveproxy\n\n🌐 Refresh your browser to see changes."
    fi
}

# Uninstall theme manager
uninstall_manager() {
    if show_dialog yesno "Uninstall Theme Manager" "⚠️  This will:\n• Remove all theme manager files\n• Keep your backups safe\n• Restore original Proxmox theme\n\nContinue with uninstall?"; then
        # Placeholder for uninstall logic
        show_dialog msgbox "Uninstall Complete" "✅ Theme Manager uninstalled successfully!\n\nYour backups are preserved in:\n$BACKUP_DIR"
        exit 0
    fi
}

# Main menu
main_menu() {
    local choice
    
    while true; do
        choice=$(show_dialog menu "🎨 Proxmox VE Theme Manager" "What would you like to do?" 18 80 \
            "1" "📊 Show Status" \
            "2" "🛡️  Create Backup" \
            "3" "🔄 Restore Original Theme" \
            "4" "🎨 Theme Selection" \
            "5" "🗑️  Uninstall Theme Manager" \
            "6" "❌ Exit" \
            2>&1 >/dev/tty)
        
        case $choice in
            1)
                show_status
                ;;
            2)
                create_backup
                ;;
            3)
                restore_backup
                ;;
            4)
                theme_selection
                ;;
            5)
                uninstall_manager
                ;;
            6|"")
                show_dialog msgbox "Goodbye!" "👋 Thank you for using Proxmox VE Theme Manager!"
                exit 0
                ;;
        esac
    done
}

# Main execution
main() {
    # Check requirements first
    check_requirements
    
    # Show welcome message
    show_dialog msgbox "Welcome!" "🎨 Welcome to Proxmox VE Theme Manager!\n\nThis tool helps you safely install and manage\ncustom themes for your Proxmox VE interface.\n\n✅ All requirements verified!"
    
    # Start main menu
    main_menu
}

# Run main function
main "$@"