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
    local warnings=()
    
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
    
    # Check for index.html.tpl - warn but don't exit
    if [[ ! -f "$PVE_INDEX_TEMPLATE" ]]; then
        warnings+=("⚠️  Missing: $PVE_INDEX_TEMPLATE")
        warnings+=("   This may indicate a corrupted Proxmox installation")
        warnings+=("   or the file was accidentally deleted.")
        warnings+=("")
        warnings+=("✅ You can still use the restore function if you have backups.")
    fi
    
    # Check if images directory exists
    if [[ ! -d "$PVE_IMAGES_PATH" ]]; then
        warnings+=("⚠️  Missing: $PVE_IMAGES_PATH")
        warnings+=("   Proxmox images directory not found.")
    fi
    
    # Create backup directory if it doesn't exist
    mkdir -p "$BACKUP_DIR"
    
    # Show warnings if any
    if [[ ${#warnings[@]} -gt 0 ]]; then
        local warning_text=""
        for warning in "${warnings[@]}"; do
            warning_text+="$warning\n"
        done
        warning_text+="\n🤔 Continue anyway?"
        
        if ! show_dialog yesno "⚠️  System Warnings" "$warning_text" 18 80; then
            show_dialog msgbox "Cancelled" "Operation cancelled by user.\n\nFix the issues above and try again."
            exit 1
        fi
    fi
}

# Get current status
get_status() {
    local status_text=""
    local current_theme="Original Proxmox Theme"
    local backup_count=0
    local last_backup="None"
    local theme_files_present=0
    
    # Check for active theme files
    local active_themes=()
    
    for css_file in "$PVE_IMAGES_PATH"/*.theme.css "$PVE_IMAGES_PATH"/pve-theme-*.css "$PVE_IMAGES_PATH"/solarized.css; do
        if [[ -f "$css_file" ]]; then
            local filename=$(basename "$css_file")
            active_themes+=("$filename")
            theme_files_present=$((theme_files_present + 1))
        fi
    done
    
    if [[ $theme_files_present -gt 0 ]]; then
        if [[ $theme_files_present -eq 1 ]]; then
            current_theme="Custom Theme: ${active_themes[0]}"
        else
            current_theme="Multiple Custom Themes ($theme_files_present files)"
        fi
    fi
    
    # Check if index.html.tpl has been modified (rough check)
    local template_modified="❌ File Missing"
    if [[ -f "$PVE_INDEX_TEMPLATE" ]]; then
        if grep -q "pve-theme\|solarized\|theme-" "$PVE_INDEX_TEMPLATE" 2>/dev/null; then
            template_modified="Yes (likely modified for themes)"
        else
            template_modified="No (appears original)"
        fi
    fi
    
    # Count backups and get latest
    if [[ -d "$BACKUP_DIR" ]]; then
        backup_count=$(ls -1d "$BACKUP_DIR"/backup-* 2>/dev/null | wc -l)
        if [[ $backup_count -gt 0 ]]; then
            local latest_backup_dir=$(ls -1td "$BACKUP_DIR"/backup-* 2>/dev/null | head -n1)
            last_backup=$(basename "$latest_backup_dir")
            
            # Try to get more info from the latest backup
            if [[ -f "$latest_backup_dir/backup-info.json" ]]; then
                local backup_date=$(grep '"date"' "$latest_backup_dir/backup-info.json" | cut -d'"' -f4 2>/dev/null || echo "Unknown")
                last_backup="$last_backup ($backup_date)"
            fi
        fi
    fi
    
    # Build status message
    status_text="🎨 Current Theme: $current_theme\n\n"
    status_text+="📄 Template Modified: $template_modified\n"
    if [[ $theme_files_present -gt 0 ]]; then
        status_text+="🎯 Theme Files Present: $theme_files_present\n"
        status_text+="   $(printf '%s, ' "${active_themes[@]}" | sed 's/, $//')\n"
    fi
    status_text+="\n🛡️  Backup Information:\n"
    status_text+="   Available Backups: $backup_count\n"
    status_text+="   Latest Backup: $last_backup\n\n"
    status_text+="📁 Paths:\n"
    status_text+="   Manager: $SCRIPT_DIR\n"
    status_text+="   Backups: $BACKUP_DIR\n"
    status_text+="   Proxmox: $PVE_MANAGER_PATH"
    
    echo "$status_text"
}

# Show status
show_status() {
    local status=$(get_status)
    show_dialog msgbox "📊 Theme Manager Status" "$status" 15 80
}

# Create backup
create_backup() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_path="$BACKUP_DIR/backup-$timestamp"
    
    if show_dialog yesno "Create Backup" "Create backup of current Proxmox configuration?\n\nThis will backup:\n• index.html.tpl template file\n• Any existing theme CSS files\n\nBackup location:\n$backup_path"; then
        
        # Create backup directory
        mkdir -p "$backup_path"
        
        local backup_log="$backup_path/backup.log"
        local backup_info="$backup_path/backup-info.json"
        local success=true
        local files_backed_up=0
        
        echo "Starting backup at $(date)" > "$backup_log"
        
        # Backup index.html.tpl
        if [[ -f "$PVE_INDEX_TEMPLATE" ]]; then
            if cp "$PVE_INDEX_TEMPLATE" "$backup_path/index.html.tpl.original" 2>>"$backup_log"; then
                local file_size=$(du -h "$backup_path/index.html.tpl.original" | cut -f1)
                echo "✅ Backed up index.html.tpl ($file_size)" >> "$backup_log"
                files_backed_up=$((files_backed_up + 1))
            else
                echo "❌ Failed to backup index.html.tpl" >> "$backup_log"
                success=false
            fi
        else
            echo "⚠️  index.html.tpl not found at $PVE_INDEX_TEMPLATE - skipping" >> "$backup_log"
            echo "   File may have been deleted or Proxmox installation is incomplete" >> "$backup_log"
        fi
        
        # Backup any existing theme CSS files we might have added
        mkdir -p "$backup_path/theme-files"
        local theme_files_found=0
        
        # Look for common theme file patterns in images directory
        for css_file in "$PVE_IMAGES_PATH"/*.theme.css "$PVE_IMAGES_PATH"/pve-theme-*.css "$PVE_IMAGES_PATH"/solarized.css; do
            if [[ -f "$css_file" ]]; then
                local filename=$(basename "$css_file")
                if cp "$css_file" "$backup_path/theme-files/" 2>>"$backup_log"; then
                    local file_size=$(du -h "$backup_path/theme-files/$filename" | cut -f1)
                    echo "✅ Backed up theme file: $filename ($file_size)" >> "$backup_log"
                    theme_files_found=$((theme_files_found + 1))
                    files_backed_up=$((files_backed_up + 1))
                else
                    echo "❌ Failed to backup theme file: $filename" >> "$backup_log"
                fi
            fi
        done
        
        if [[ $theme_files_found -eq 0 ]]; then
            echo "ℹ️  No existing theme files found to backup" >> "$backup_log"
        fi
        
        # Create backup metadata
        cat > "$backup_info" <<EOF
{
    "timestamp": "$timestamp",
    "date": "$(date)",
    "files_backed_up": $files_backed_up,
    "theme_files_found": $theme_files_found,
    "backup_path": "$backup_path",
    "proxmox_version": "$(pveversion 2>/dev/null || echo 'Unknown')",
    "success": $success
}
EOF
        
        echo "Backup completed at $(date)" >> "$backup_log"
        
        # Show results
        if [[ $success == true ]]; then
            local message="✅ Backup created successfully!\n\n"
            message+="📁 Location: $backup_path\n"
            message+="📄 Files backed up: $files_backed_up\n"
            if [[ $theme_files_found -gt 0 ]]; then
                message+="🎨 Theme files found: $theme_files_found\n"
            fi
            message+="\n💡 View details: $backup_log"
            
            show_dialog msgbox "Backup Complete" "$message" 15 80
        else
            show_dialog msgbox "Backup Error" "❌ Backup completed with errors!\n\nSome files may not have been backed up.\nCheck the log for details:\n$backup_log" 12 80
        fi
    fi
}

# Restore backup
restore_backup() {
    local backup_count=$(ls -1 "$BACKUP_DIR" 2>/dev/null | wc -l)
    
    if [[ $backup_count -eq 0 ]]; then
        show_dialog msgbox "No Backups" "❌ No backups found.\n\nCreate a backup first before installing themes."
        return
    fi
    
    # Get list of available backups
    local backup_list=()
    local counter=1
    
    for backup_dir in "$BACKUP_DIR"/backup-*; do
        if [[ -d "$backup_dir" ]]; then
            local backup_name=$(basename "$backup_dir")
            local backup_date=""
            
            # Try to get date from backup-info.json
            if [[ -f "$backup_dir/backup-info.json" ]]; then
                backup_date=$(grep '"date"' "$backup_dir/backup-info.json" | cut -d'"' -f4 2>/dev/null || echo "Unknown")
            else
                # Fallback to directory timestamp
                backup_date=$(echo "$backup_name" | sed 's/backup-//' | sed 's/_/ /' | sed 's/\(..\)\(..\)\(..\)/20\3-\1-\2/')
            fi
            
            backup_list+=("$counter" "$backup_name ($backup_date)")
            counter=$((counter + 1))
        fi
    done
    
    if [[ ${#backup_list[@]} -eq 0 ]]; then
        show_dialog msgbox "No Valid Backups" "❌ No valid backup directories found."
        return
    fi
    
    # Show backup selection menu
    local selected_backup
    selected_backup=$(show_dialog menu "Select Backup to Restore" "Choose which backup to restore:" 15 80 "${backup_list[@]}" 2>&1 >/dev/tty)
    
    if [[ -z "$selected_backup" ]]; then
        return  # User cancelled
    fi
    
    # Get the selected backup directory
    local backup_index=$((selected_backup - 1))
    local selected_dir=$(ls -1d "$BACKUP_DIR"/backup-* | sed -n "$((backup_index + 1))p")
    
    if [[ ! -d "$selected_dir" ]]; then
        show_dialog msgbox "Error" "❌ Selected backup directory not found."
        return
    fi
    
    # Confirm restore
    local backup_name=$(basename "$selected_dir")
    if ! show_dialog yesno "Confirm Restore" "⚠️  This will restore backup: $backup_name\n\nThis will:\n• Restore original index.html.tpl\n• Remove any custom theme CSS files\n• Revert to original Proxmox theme\n\nContinue?"; then
        return
    fi
    
    # Perform restore
    local restore_log="/tmp/pve-theme-restore-$(date +%s).log"
    local success=true
    local files_restored=0
    
    echo "Starting restore at $(date)" > "$restore_log"
    echo "Restoring from: $selected_dir" >> "$restore_log"
    
    # Restore index.html.tpl
    if [[ -f "$selected_dir/index.html.tpl.original" ]]; then
        if cp "$selected_dir/index.html.tpl.original" "$PVE_INDEX_TEMPLATE" 2>>"$restore_log"; then
            echo "✅ Restored index.html.tpl" >> "$restore_log"
            files_restored=$((files_restored + 1))
        else
            echo "❌ Failed to restore index.html.tpl" >> "$restore_log"
            success=false
        fi
    else
        echo "⚠️  Original index.html.tpl not found in backup" >> "$restore_log"
        success=false
    fi
    
    # Remove theme CSS files that we know we added
    local theme_files_removed=0
    for css_file in "$PVE_IMAGES_PATH"/*.theme.css "$PVE_IMAGES_PATH"/pve-theme-*.css; do
        if [[ -f "$css_file" ]]; then
            local filename=$(basename "$css_file")
            if rm "$css_file" 2>>"$restore_log"; then
                echo "✅ Removed theme file: $filename" >> "$restore_log"
                theme_files_removed=$((theme_files_removed + 1))
            else
                echo "⚠️  Could not remove theme file: $filename" >> "$restore_log"
            fi
        fi
    done
    
    # Also check for solarized.css (common theme file)
    if [[ -f "$PVE_IMAGES_PATH/solarized.css" ]]; then
        if rm "$PVE_IMAGES_PATH/solarized.css" 2>>"$restore_log"; then
            echo "✅ Removed solarized.css" >> "$restore_log"
            theme_files_removed=$((theme_files_removed + 1))
        else
            echo "⚠️  Could not remove solarized.css" >> "$restore_log"
        fi
    fi
    
    echo "Restore completed at $(date)" >> "$restore_log"
    
    # Show results and ask about service restart
    if [[ $success == true ]]; then
        local message="✅ Restore completed successfully!\n\n"
        message+="📄 Files restored: $files_restored\n"
        if [[ $theme_files_removed -gt 0 ]]; then
            message+="🗑️  Theme files removed: $theme_files_removed\n"
        fi
        message+="\n💡 Restore log: $restore_log"
        
        show_dialog msgbox "Restore Complete" "$message" 15 80
        
        # Ask about restarting pveproxy
        if show_dialog yesno "Restart Service" "🔄 Restart pveproxy service now to apply changes?\n\nThis will briefly interrupt the web interface."; then
            if systemctl restart pveproxy 2>>"$restore_log"; then
                show_dialog msgbox "Service Restarted" "✅ pveproxy service restarted successfully!\n\n🌐 Refresh your browser to see the original Proxmox theme."
            else
                show_dialog msgbox "Service Error" "❌ Failed to restart pveproxy service.\n\nPlease restart manually:\nsudo systemctl restart pveproxy"
            fi
        else
            show_dialog msgbox "Manual Restart Needed" "⚠️  Remember to restart pveproxy service:\nsudo systemctl restart pveproxy\n\nThen refresh your browser."
        fi
    else
        show_dialog msgbox "Restore Error" "❌ Restore completed with errors!\n\nCheck the log for details:\n$restore_log" 12 80
    fi
}

# Get available themes dynamically
get_available_themes() {
    local themes=()
    local counter=1
    
    if [[ ! -d "$THEMES_DIR" ]]; then
        echo "No themes directory found"
        return 1
    fi
    
    for theme_file in "$THEMES_DIR"/*.css; do
        if [[ -f "$theme_file" ]]; then
            local filename=$(basename "$theme_file" .css)
            local display_name=$(echo "$filename" | sed 's/-/ /g' | sed 's/\b\w/\u&/g')
            
            # Add some emoji based on theme name
            local emoji="🎨"
            case "$filename" in
                *dark*|*blue*) emoji="🌙" ;;
                *green*|*emerald*) emoji="🟢" ;;
                *orange*|*sunset*) emoji="🌅" ;;
                *gray*|*grey*|*minimal*) emoji="⚪" ;;
                *red*) emoji="🔴" ;;
                *purple*|*violet*) emoji="🟣" ;;
            esac
            
            themes+=("$counter" "$emoji $display_name")
            counter=$((counter + 1))
        fi
    done
    
    printf '%s\n' "${themes[@]}"
}

# Theme selection submenu
theme_selection() {
    local choice
    local theme_menu_items
    
    while true; do
        # Get available themes dynamically
        theme_menu_items=($(get_available_themes))
        
        if [[ ${#theme_menu_items[@]} -eq 0 ]]; then
            show_dialog msgbox "No Themes Found" "❌ No theme files found in:\n$THEMES_DIR\n\nPlease reinstall the theme manager."
            return
        fi
        
        # Add documentation and back options
        local total_themes=$((${#theme_menu_items[@]} / 2))
        local doc_option=$((total_themes + 1))
        local back_option=$((total_themes + 2))
        
        theme_menu_items+=("$doc_option" "📖 View Screenshots & Documentation")
        theme_menu_items+=("$back_option" "⬅️  Back to Main Menu")
        
        choice=$(show_dialog menu "🎨 Theme Selection" "Choose a theme to install:" 20 80 "${theme_menu_items[@]}" 2>&1 >/dev/tty)
        
        if [[ -z "$choice" ]]; then
            break
        elif [[ "$choice" -eq "$doc_option" ]]; then
            show_dialog msgbox "Documentation & Screenshots" "📖 Theme Screenshots & Documentation\n\nView detailed screenshots and theme descriptions at:\nhttp://10.0.10.41:3000/Marleybop/pve-themes\n\n🎨 Themes found: $total_themes\n\nAll themes are original designs by PVE Theme Manager." 18 80
        elif [[ "$choice" -eq "$back_option" ]]; then
            break
        elif [[ "$choice" -ge 1 && "$choice" -le "$total_themes" ]]; then
            install_theme "$choice"
        fi
    done
}

# Install theme
install_theme() {
    local theme_num="$1"
    
    # Get the theme file dynamically
    local counter=1
    local theme_file=""
    local theme_name=""
    
    for theme_path in "$THEMES_DIR"/*.css; do
        if [[ -f "$theme_path" ]]; then
            if [[ $counter -eq $theme_num ]]; then
                theme_file=$(basename "$theme_path")
                theme_name=$(basename "$theme_path" .css | sed 's/-/ /g' | sed 's/\b\w/\u&/g')
                break
            fi
            counter=$((counter + 1))
        fi
    done
    
    if [[ -z "$theme_file" ]]; then
        show_dialog msgbox "Error" "Invalid theme selection."
        return
    fi
    
    # Check if theme file exists
    local source_theme="$THEMES_DIR/$theme_file"
    if [[ ! -f "$source_theme" ]]; then
        show_dialog msgbox "Error" "Theme file not found:\n$source_theme\n\nPlease reinstall the theme manager."
        return
    fi
    
    # Check if backup exists - recommend creating one
    local backup_count=$(ls -1d "$BACKUP_DIR"/backup-* 2>/dev/null | wc -l)
    if [[ $backup_count -eq 0 ]]; then
        if show_dialog yesno "No Backup Found" "⚠️  No backups found!\n\nIt's strongly recommended to create a backup before installing themes.\n\nCreate backup now?"; then
            create_backup
        else
            if ! show_dialog yesno "Continue Without Backup?" "⚠️  Are you sure you want to install a theme without a backup?\n\nThis could make recovery difficult if something goes wrong.\n\nContinue anyway?"; then
                return
            fi
        fi
    fi
    
    # Final confirmation
    if ! show_dialog yesno "Install $theme_name Theme" "Install $theme_name theme?\n\nThis will:\n• Copy theme CSS file to Proxmox\n• Modify index.html.tpl to load the theme\n• Enable the custom theme\n\nContinue?"; then
        return
    fi
    
    # Perform installation
    local install_log="/tmp/pve-theme-install-$(date +%s).log"
    local success=true
    local steps_completed=0
    
    echo "Starting theme installation at $(date)" > "$install_log"
    echo "Theme: $theme_name ($theme_file)" >> "$install_log"
    echo "Source: $source_theme" >> "$install_log"
    echo "" >> "$install_log"
    
    # Step 1: Copy theme CSS file
    echo "Step 1: Copying theme CSS file..." >> "$install_log"
    local target_css="$PVE_IMAGES_PATH/pve-theme-$theme_file"
    
    if cp "$source_theme" "$target_css" 2>>"$install_log"; then
        local file_size=$(du -h "$target_css" | cut -f1)
        echo "✅ Theme CSS copied successfully ($file_size)" >> "$install_log"
        echo "   Target: $target_css" >> "$install_log"
        steps_completed=$((steps_completed + 1))
    else
        echo "❌ Failed to copy theme CSS file" >> "$install_log"
        success=false
    fi
    
    # Step 2: Modify index.html.tpl
    if [[ $success == true ]]; then
        echo "" >> "$install_log"
        echo "Step 2: Modifying index.html.tpl..." >> "$install_log"
        
        # Check if file exists
        if [[ ! -f "$PVE_INDEX_TEMPLATE" ]]; then
            echo "❌ index.html.tpl not found at $PVE_INDEX_TEMPLATE" >> "$install_log"
            success=false
        else
            # Remove any existing theme script
            echo "   Removing existing theme scripts..." >> "$install_log"
            sed -i '/<script[^>]*pve-theme/,/<\/script>/d' "$PVE_INDEX_TEMPLATE" 2>>"$install_log"
            
            # Create temporary file with theme script
            local temp_script="/tmp/pve-theme-script-$(date +%s).js"
            cat > "$temp_script" << 'EOF'
<script>
// PVE Theme Manager
(function() {
    var link = document.createElement('link');
    link.rel = 'stylesheet';
    link.type = 'text/css';
    link.href = '/pve2/images/THEME_FILE_PLACEHOLDER';
    document.getElementsByTagName('head')[0].appendChild(link);
})();
</script>
EOF
            
            # Replace placeholder with actual theme file
            sed -i "s|THEME_FILE_PLACEHOLDER|pve-theme-$theme_file|" "$temp_script"
            
            # Insert before closing head tag
            if grep -q "</head>" "$PVE_INDEX_TEMPLATE"; then
                if sed -i -e "/<\/head>/e cat $temp_script" -e "/<\/head>/i\\" "$PVE_INDEX_TEMPLATE" 2>>"$install_log"; then
                    echo "✅ Theme script added to index.html.tpl" >> "$install_log"
                    steps_completed=$((steps_completed + 1))
                    rm -f "$temp_script"
                else
                    echo "❌ Failed to modify index.html.tpl" >> "$install_log"
                    rm -f "$temp_script"
                    success=false
                fi
            else
                echo "❌ Could not find </head> tag in index.html.tpl" >> "$install_log"
                rm -f "$temp_script"
                success=false
            fi
        fi
    fi
    
    echo "" >> "$install_log"
    echo "Installation completed at $(date)" >> "$install_log"
    echo "Success: $success" >> "$install_log"
    echo "Steps completed: $steps_completed/2" >> "$install_log"
    
    # Show results
    if [[ $success == true ]]; then
        local message="✅ $theme_name theme installed successfully!\n\n"
        message+="📄 Steps completed: $steps_completed/2\n"
        message+="🎨 Theme file: pve-theme-$theme_file\n"
        message+="\n💡 Installation log: $install_log"
        
        show_dialog msgbox "Installation Complete" "$message" 15 80
        
        # Ask about service restart
        if show_dialog yesno "Restart Service" "🔄 Restart pveproxy service now to apply the theme?\n\nThis will briefly interrupt the web interface."; then
            if systemctl restart pveproxy 2>>"$install_log"; then
                show_dialog msgbox "Service Restarted" "✅ pveproxy service restarted successfully!\n\n🌐 Refresh your browser to see the $theme_name theme."
            else
                show_dialog msgbox "Service Error" "❌ Failed to restart pveproxy service.\n\nPlease restart manually:\nsudo systemctl restart pveproxy"
            fi
        else
            show_dialog msgbox "Manual Restart Needed" "⚠️  Remember to restart pveproxy service:\nsudo systemctl restart pveproxy\n\nThen refresh your browser to see the theme."
        fi
    else
        show_dialog msgbox "Installation Error" "❌ Theme installation failed!\n\nCheck the log for details:\n$install_log\n\n🔄 You may want to restore from backup." 15 80
    fi
}

# Uninstall theme manager
uninstall_manager() {
    if show_dialog yesno "Uninstall Theme Manager" "⚠️  This will:\n• Remove all theme manager files\n• Remove symlink from /usr/local/bin/pve-theme\n• Restore original Proxmox theme\n• Keep your backups safe\n\nContinue with uninstall?"; then
        
        local uninstall_log="/tmp/pve-theme-uninstall-$(date +%s).log"
        echo "Starting uninstall at $(date)" > "$uninstall_log"
        
        # First restore original theme if any custom theme is active
        echo "Step 1: Restoring original theme..." >> "$uninstall_log"
        
        # Remove theme CSS files
        local theme_files_removed=0
        for css_file in "$PVE_IMAGES_PATH"/pve-theme-*.css; do
            if [[ -f "$css_file" ]]; then
                local filename=$(basename "$css_file")
                if rm "$css_file" 2>>"$uninstall_log"; then
                    echo "✅ Removed theme file: $filename" >> "$uninstall_log"
                    theme_files_removed=$((theme_files_removed + 1))
                else
                    echo "⚠️  Could not remove theme file: $filename" >> "$uninstall_log"
                fi
            fi
        done
        
        # Restore from backup if available
        local latest_backup_dir=$(ls -1td "$BACKUP_DIR"/backup-* 2>/dev/null | head -n1)
        if [[ -n "$latest_backup_dir" && -f "$latest_backup_dir/index.html.tpl.original" ]]; then
            if cp "$latest_backup_dir/index.html.tpl.original" "$PVE_INDEX_TEMPLATE" 2>>"$uninstall_log"; then
                echo "✅ Restored original index.html.tpl from backup" >> "$uninstall_log"
            else
                echo "⚠️  Could not restore index.html.tpl from backup" >> "$uninstall_log"
            fi
        else
            echo "⚠️  No backup found to restore index.html.tpl" >> "$uninstall_log"
        fi
        
        # Remove theme manager files
        echo "Step 2: Removing theme manager files..." >> "$uninstall_log"
        
        # Remove symlink
        if [[ -L "/usr/local/bin/pve-theme" ]]; then
            if rm "/usr/local/bin/pve-theme" 2>>"$uninstall_log"; then
                echo "✅ Removed symlink: /usr/local/bin/pve-theme" >> "$uninstall_log"
            else
                echo "⚠️  Could not remove symlink: /usr/local/bin/pve-theme" >> "$uninstall_log"
            fi
        fi
        
        # Remove installation directory
        local install_dir=$(dirname "$SCRIPT_DIR")
        if [[ "$install_dir" == *"pve-theme-manager"* ]]; then
            if rm -rf "$install_dir" 2>>"$uninstall_log"; then
                echo "✅ Removed installation directory: $install_dir" >> "$uninstall_log"
            else
                echo "⚠️  Could not remove installation directory: $install_dir" >> "$uninstall_log"
            fi
        fi
        
        echo "Uninstall completed at $(date)" >> "$uninstall_log"
        
        # Restart pveproxy
        if systemctl restart pveproxy 2>>"$uninstall_log"; then
            echo "✅ pveproxy service restarted" >> "$uninstall_log"
        else
            echo "⚠️  Could not restart pveproxy service" >> "$uninstall_log"
        fi
        
        show_dialog msgbox "Uninstall Complete" "✅ Theme Manager uninstalled successfully!\n\n📊 Summary:\n• Theme files removed: $theme_files_removed\n• Original theme restored\n• Manager files removed\n\n🛡️  Your backups are preserved in:\n$BACKUP_DIR\n\n📝 Uninstall log: $uninstall_log" 18 80
        
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