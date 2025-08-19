#!/bin/bash

# Proxmox VE Theme Manager Installer
# Quick installer for the theme management system

set -e

REPO_URL="http://10.0.10.41:3000/Marleybop/pve-themes/raw/branch/main"
INSTALL_DIR="$HOME/pve-theme-manager"

echo "🎨 Proxmox VE Theme Manager Installer"
echo "====================================="

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo "❌ Error: This script must be run as root"
    echo "Please run: sudo bash <(curl -fsSL $REPO_URL/install.sh)"
    exit 1
fi

# Check if Proxmox is installed
if [[ ! -d "/usr/share/pve-manager" ]]; then
    echo "❌ Error: Proxmox VE not found. Is this running on a Proxmox VE server?"
    exit 1
fi

echo "✅ Proxmox VE detected"

# Create installation directory
echo "📦 Installing to: $INSTALL_DIR"
mkdir -p "$INSTALL_DIR/themes"

# Download main script
echo "⬇️  Downloading theme manager..."
curl -fsSL "$REPO_URL/pve-theme-manager.sh" -o "$INSTALL_DIR/pve-theme-manager.sh"
chmod +x "$INSTALL_DIR/pve-theme-manager.sh"

# Create symlink for easy access
ln -sf "$INSTALL_DIR/pve-theme-manager.sh" /usr/local/bin/pve-theme

echo ""
echo "🎉 Installation completed successfully!"
echo ""
echo "🚀 Run the theme manager with:"
echo "   pve-theme"
echo "   OR"
echo "   $INSTALL_DIR/pve-theme-manager.sh"
echo ""
echo "📖 Documentation: $REPO_URL"

# Ask if user wants to run it now
read -p "Would you like to run the theme manager now? (y/N): " -r
if [[ $REPLY =~ ^[Yy]$ ]]; then
    exec "$INSTALL_DIR/pve-theme-manager.sh"
fi