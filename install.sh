#!/bin/bash

# Proxmox VE Theme Manager Installer
# One-line install: curl -sSL https://raw.githubusercontent.com/yourusername/pve-themes/main/install.sh | bash

set -e

REPO_BASE_URL="https://raw.githubusercontent.com/yourusername/pve-themes/main"
PVE_MANAGER_PATH="/usr/share/pve-manager"
PVE_IMAGES_PATH="$PVE_MANAGER_PATH/images"
PVE_INDEX_TEMPLATE="$PVE_MANAGER_PATH/index.html.tpl"
BACKUP_DIR="/tmp/pve-theme-backup-$(date +%Y%m%d_%H%M%S)"
THEME_MANAGER_DIR="/opt/pve-themes"

# Available themes
AVAILABLE_THEMES=("modern-dark" "ocean-blue" "forest-green" "minimal-light")

echo "🎨 Proxmox VE Theme Manager Installer"
echo "====================================="

# Support for non-interactive mode via environment variables
AUTO_INSTALL=${AUTO_INSTALL:-false}
THEME_CHOICE=${THEME_CHOICE:-1}  # Default to modern-dark
ACTION=${ACTION:-install}        # install, backup, or menu

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --auto)
            AUTO_INSTALL=true
            shift
            ;;
        --theme)
            THEME_CHOICE="$2"
            shift 2
            ;;
        --backup-only)
            ACTION="backup"
            AUTO_INSTALL=true
            shift
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

show_help() {
    cat << EOF
🎨 Proxmox VE Theme Manager Installer

Usage:
    # Interactive mode (default)
    bash <(curl -fsSL http://10.0.10.41:3000/Marleybop/pve-themes/raw/branch/main/install.sh)
    
    # Auto-install with theme selection (seamless one-liner)
    bash -c "\$(curl -fsSL http://10.0.10.41:3000/Marleybop/pve-themes/raw/branch/main/install.sh)" -- --auto --theme 2
    
    # Backup only (seamless)
    bash -c "\$(curl -fsSL http://10.0.10.41:3000/Marleybop/pve-themes/raw/branch/main/install.sh)" -- --backup-only

Options:
    --auto              Run without interactive prompts
    --theme <1-4>       Theme to install (1=modern-dark, 2=ocean-blue, 3=forest-green, 4=minimal-light)
    --backup-only       Create backup only, no installation
    --help              Show this help

Available themes:
    1. modern-dark      - Sleek dark theme with blue accents
    2. ocean-blue       - Ocean-inspired adaptive theme
    3. forest-green     - Nature-themed green palette
    4. minimal-light    - Clean minimal design
EOF
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "❌ Error: This script must be run as root"
        echo "Please run: sudo bash <(curl -sSL your-install-url)"
        exit 1
    fi
}

check_proxmox() {
    if [[ ! -d "$PVE_MANAGER_PATH" ]]; then
        echo "❌ Error: Proxmox VE not found. Is this running on a Proxmox VE server?"
        exit 1
    fi
    echo "✅ Proxmox VE installation detected"
}

create_backup() {
    echo "📦 Creating backup of original Proxmox files..."
    echo "🗂️  Backup directory: $BACKUP_DIR"
    echo ""
    
    mkdir -p "$BACKUP_DIR"
    echo "✅ Created backup directory: $BACKUP_DIR"
    
    if [[ -f "$PVE_INDEX_TEMPLATE" ]]; then
        cp "$PVE_INDEX_TEMPLATE" "$BACKUP_DIR/index.html.tpl.original"
        local backup_size=$(du -h "$BACKUP_DIR/index.html.tpl.original" | cut -f1)
        echo "✅ Backed up index.html.tpl ($backup_size) → $BACKUP_DIR/index.html.tpl.original"
    else
        echo "⚠️  Warning: $PVE_INDEX_TEMPLATE not found - skipping backup"
    fi
    
    # Show backup contents
    echo ""
    echo "📋 Backup contents:"
    ls -la "$BACKUP_DIR/" | sed 's/^/   /'
    echo ""
    echo "🛡️  BACKUP COMPLETE! Your original files are safely stored."
    echo "🔄 To restore later: cp $BACKUP_DIR/index.html.tpl.original $PVE_INDEX_TEMPLATE"
    echo ""
}

install_theme_manager() {
    echo "⬇️  Installing theme manager..."
    
    # Create theme manager directory
    mkdir -p "$THEME_MANAGER_DIR/themes"
    
    # Download theme manager script
    curl -sSL "$REPO_BASE_URL/pve-theme-manager.sh" -o "$THEME_MANAGER_DIR/pve-theme-manager.sh"
    chmod +x "$THEME_MANAGER_DIR/pve-theme-manager.sh"
    
    # Download all available themes
    for theme in "${AVAILABLE_THEMES[@]}"; do
        echo "📥 Downloading $theme theme..."
        curl -sSL "$REPO_BASE_URL/themes/$theme.css" -o "$THEME_MANAGER_DIR/themes/$theme.css"
    done
    
    # Create symlink for easy access
    ln -sf "$THEME_MANAGER_DIR/pve-theme-manager.sh" /usr/local/bin/pve-theme
    
    echo "✅ Theme manager installed to $THEME_MANAGER_DIR"
}

select_theme() {
    if [[ "$AUTO_INSTALL" == "true" ]]; then
        if [[ "$THEME_CHOICE" =~ ^[1-4]$ ]] && [ "$THEME_CHOICE" -le "${#AVAILABLE_THEMES[@]}" ]; then
            selected_theme="${AVAILABLE_THEMES[$((THEME_CHOICE-1))]}"
            echo "🎨 Auto-selected theme: $selected_theme"
            return 0
        else
            echo "❌ Invalid theme choice: $THEME_CHOICE. Using default: modern-dark"
            selected_theme="modern-dark"
            return 0
        fi
    fi
    
    echo ""
    echo "📋 Available themes:"
    for i in "${!AVAILABLE_THEMES[@]}"; do
        echo "  $((i+1)). ${AVAILABLE_THEMES[i]}"
    done
    echo ""
    
    while true; do
        read -p "Select a theme to install (1-${#AVAILABLE_THEMES[@]}): " choice
        if [[ "$choice" =~ ^[1-9]+$ ]] && [ "$choice" -le "${#AVAILABLE_THEMES[@]}" ]; then
            selected_theme="${AVAILABLE_THEMES[$((choice-1))]}"
            break
        else
            echo "❌ Invalid choice. Please enter a number between 1 and ${#AVAILABLE_THEMES[@]}."
        fi
    done
    
    echo "✅ Selected theme: $selected_theme"
}

apply_theme() {
    local theme_name="$1"
    echo "🎨 Applying $theme_name theme..."
    
    # Copy theme file to PVE images directory
    cp "$THEME_MANAGER_DIR/themes/$theme_name.css" "$PVE_IMAGES_PATH/pve-theme-active.css"
    
    echo "✅ Theme applied"
}

patch_template() {
    echo "🔧 Patching index.html.tpl..."
    
    # Check if already patched
    if grep -q "pve-theme-active.css" "$PVE_INDEX_TEMPLATE" 2>/dev/null; then
        echo "⚠️  Theme manager already installed, skipping patch"
        return 0
    fi
    
    # Create the theme switching script
    local theme_script='<script>
(function() {
    var link = document.createElement("link");
    link.rel = "stylesheet";
    link.type = "text/css";
    link.href = "/pve2/images/pve-theme-active.css";
    document.getElementsByTagName("head")[0].appendChild(link);
    
    function updateThemeClass() {
        var isDark = document.querySelector("link[href*=\"theme-crisp\"]") || 
                    document.querySelector("link[href*=\"theme-gray\"]") ||
                    document.querySelector("link[href*=\"theme-dark\"]");
        if (isDark) {
            document.body.classList.add("proxmox-theme-dark");
        } else {
            document.body.classList.remove("proxmox-theme-dark");
        }
    }
    
    var observer = new MutationObserver(updateThemeClass);
    observer.observe(document.head, { childList: true, subtree: true });
    updateThemeClass();
})();
</script>'
    
    # Add script before closing head tag
    if grep -q "</head>" "$PVE_INDEX_TEMPLATE"; then
        sed -i "s|</head>|$theme_script\n</head>|" "$PVE_INDEX_TEMPLATE"
        echo "✅ Added theme manager script to index.html.tpl"
    else
        echo "❌ Could not find </head> tag in index.html.tpl"
        exit 1
    fi
}

restart_service() {
    echo "🔄 Restarting pveproxy service..."
    systemctl restart pveproxy
    echo "✅ Service restarted"
}

show_completion() {
    echo ""
    echo "🎉 Proxmox VE Theme Manager installed successfully!"
    echo ""
    echo "📋 What was installed:"
    echo "   • Theme manager script: $THEME_MANAGER_DIR/pve-theme-manager.sh"
    echo "   • ${#AVAILABLE_THEMES[@]} custom themes in $THEME_MANAGER_DIR/themes/"
    echo "   • Theme switching script in index.html.tpl"
    echo "   • Active theme: $selected_theme"
    echo ""
    echo "📁 Backup location: $BACKUP_DIR"
    echo ""
    echo "🔧 Theme Manager Commands:"
    echo "   pve-theme list                    - List available themes"
    echo "   pve-theme install <theme-name>    - Install a theme"
    echo "   pve-theme restore                 - Restore original theme"
    echo "   pve-theme status                  - Show current status"
    echo ""
    echo "🌐 Access your Proxmox web interface - the $selected_theme theme is now active!"
    echo "   • Light/Dark mode support varies by theme"
    echo "   • Themes automatically adapt to Proxmox's built-in theme selector"
    echo ""
    echo "📚 Available themes:"
    for theme in "${AVAILABLE_THEMES[@]}"; do
        echo "   • $theme"
    done
}

show_main_menu() {
    if [[ "$AUTO_INSTALL" == "true" ]]; then
        case "$ACTION" in
            backup)
                return 2  # Backup only
                ;;
            install|*)
                return 1  # Install themes
                ;;
        esac
    fi
    
    echo ""
    echo "📋 What would you like to do?"
    echo "=============================="
    echo "1. Install Theme Manager & Apply Theme"
    echo "2. Create Backup Only"  
    echo "3. Exit"
    echo ""
    
    while true; do
        read -p "Select an option (1-3): " choice
        case $choice in
            1)
                return 1  # Install themes
                ;;
            2)
                return 2  # Backup only
                ;;
            3)
                echo "👋 Goodbye!"
                exit 0
                ;;
            *)
                echo "❌ Invalid choice. Please enter 1, 2, or 3."
                ;;
        esac
    done
}

install_full_system() {
    echo "🚀 Installing Theme Manager..."
    create_backup
    install_theme_manager
    select_theme
    apply_theme "$selected_theme"
    patch_template
    restart_service
    show_completion
}

backup_only() {
    echo ""
    echo "🛡️  BACKUP-ONLY MODE SELECTED"
    echo "==============================="
    echo "This will create a backup of your original Proxmox files WITHOUT"
    echo "making any changes to your system. You can install themes later."
    echo ""
    
    create_backup
    
    echo "🎉 BACKUP-ONLY OPERATION COMPLETE!"
    echo ""
    echo "📁 Your backup is stored at:"
    echo "   $BACKUP_DIR"
    echo ""
    echo "🔍 Backup contains:"
    echo "   • index.html.tpl.original (your original Proxmox template)"
    echo ""
    echo "💡 Next steps:"
    echo "   • Your Proxmox system is unchanged"
    echo "   • To install themes later: run this installer again and choose option 1"
    echo "   • To restore backup: cp $BACKUP_DIR/index.html.tpl.original $PVE_INDEX_TEMPLATE"
    echo ""
}

main() {
    check_root
    check_proxmox
    
    show_main_menu
    menu_choice=$?
    
    case $menu_choice in
        1)
            install_full_system
            ;;
        2)
            backup_only
            ;;
    esac
}

# Handle script interruption
trap 'echo "❌ Installation interrupted"; exit 1' INT TERM

main "$@"