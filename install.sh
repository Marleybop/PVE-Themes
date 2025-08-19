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
    echo "📦 Creating backup of original files..."
    mkdir -p "$BACKUP_DIR"
    
    if [[ -f "$PVE_INDEX_TEMPLATE" ]]; then
        cp "$PVE_INDEX_TEMPLATE" "$BACKUP_DIR/index.html.tpl.original"
        echo "✅ Backed up index.html.tpl to $BACKUP_DIR"
    fi
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

main() {
    echo "Starting installation..."
    
    check_root
    check_proxmox
    create_backup
    install_theme_manager
    select_theme
    apply_theme "$selected_theme"
    patch_template
    restart_service
    show_completion
}

# Handle script interruption
trap 'echo "❌ Installation interrupted"; exit 1' INT TERM

main "$@"