#!/bin/bash

# Proxmox VE Theme Uninstaller
# Removes themes and restores original Proxmox appearance

set -e

PVE_MANAGER_PATH="/usr/share/pve-manager"
PVE_IMAGES_PATH="$PVE_MANAGER_PATH/images"
PVE_INDEX_TEMPLATE="$PVE_MANAGER_PATH/index.html.tpl"

echo "🗑️  Proxmox VE Theme Uninstaller"
echo "================================"

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "❌ Error: This script must be run as root"
        exit 1
    fi
}

check_proxmox() {
    if [[ ! -d "$PVE_MANAGER_PATH" ]]; then
        echo "❌ Error: Proxmox VE not found"
        exit 1
    fi
    echo "✅ Proxmox VE installation detected"
}

find_backup() {
    local backup_file=""
    
    # Look for backup in common locations
    for dir in /tmp/pve-theme-backup-* /root/pve-theme-backup-* .; do
        if [[ -f "$dir/index.html.tpl.original" ]]; then
            backup_file="$dir/index.html.tpl.original"
            echo "📦 Found backup: $backup_file"
            break
        fi
    done
    
    if [[ -z "$backup_file" ]]; then
        echo "⚠️  No backup found. Creating clean template..."
        create_clean_template
    else
        restore_from_backup "$backup_file"
    fi
}

restore_from_backup() {
    local backup_file="$1"
    echo "🔄 Restoring from backup..."
    cp "$backup_file" "$PVE_INDEX_TEMPLATE"
    echo "✅ Restored index.html.tpl"
}

create_clean_template() {
    echo "🧹 Removing theme scripts from index.html.tpl..."
    
    # Remove theme-related script blocks
    sed -i '/<script>/,/<\/script>/{/solarized\.css\|proxmox-theme-dark\|updateThemeClass/d}' "$PVE_INDEX_TEMPLATE" 2>/dev/null || true
    
    # Remove empty script blocks
    sed -i '/<script>[\s]*<\/script>/d' "$PVE_INDEX_TEMPLATE" 2>/dev/null || true
    
    echo "✅ Cleaned index.html.tpl"
}

remove_theme_files() {
    echo "🗑️  Removing theme files..."
    
    # Remove solarized theme
    if [[ -f "$PVE_IMAGES_PATH/solarized.css" ]]; then
        rm "$PVE_IMAGES_PATH/solarized.css"
        echo "✅ Removed solarized.css"
    fi
    
    # Remove any other theme files
    find "$PVE_IMAGES_PATH" -name "*.theme.css" -delete 2>/dev/null || true
    
    echo "✅ All theme files removed"
}

restart_service() {
    echo "🔄 Restarting pveproxy service..."
    systemctl restart pveproxy
    echo "✅ Service restarted"
}

show_completion() {
    echo ""
    echo "✅ Uninstallation completed successfully!"
    echo ""
    echo "🌐 Your Proxmox web interface has been restored to the original theme."
    echo "🔄 Please refresh your browser to see the changes."
}

main() {
    echo "Starting uninstallation..."
    
    check_root
    check_proxmox
    find_backup
    remove_theme_files
    restart_service
    show_completion
}

main "$@"