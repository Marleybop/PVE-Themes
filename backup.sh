#!/bin/bash

# Proxmox VE Backup Script
# Simple backup utility for Proxmox files before theme installation

set -e

echo "🛡️  Proxmox VE Backup Script"
echo "============================"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo "❌ Error: This script must be run as root"
    exit 1
fi

# Check if Proxmox is installed
if [[ ! -d "/usr/share/pve-manager" ]]; then
    echo "❌ Error: Proxmox VE not found. Is this running on a Proxmox VE server?"
    exit 1
fi

echo "✅ Proxmox VE installation detected"

# Create timestamped backup directory
BACKUP_DIR="/tmp/pve-backup-$(date +%Y%m%d_%H%M%S)"
echo "📦 Creating backup directory: $BACKUP_DIR"
mkdir -p "$BACKUP_DIR"

# Backup the main template file
PVE_INDEX_TEMPLATE="/usr/share/pve-manager/index.html.tpl"

if [[ -f "$PVE_INDEX_TEMPLATE" ]]; then
    cp "$PVE_INDEX_TEMPLATE" "$BACKUP_DIR/index.html.tpl.original"
    BACKUP_SIZE=$(du -h "$BACKUP_DIR/index.html.tpl.original" | cut -f1)
    echo "✅ Backed up index.html.tpl ($BACKUP_SIZE)"
else
    echo "⚠️  Warning: $PVE_INDEX_TEMPLATE not found"
    exit 1
fi

# Show backup contents
echo ""
echo "📋 Backup completed successfully!"
echo "📁 Location: $BACKUP_DIR"
echo "📄 Files:"
ls -la "$BACKUP_DIR/" | sed 's/^/   /'

echo ""
echo "🔄 To restore later:"
echo "   cp $BACKUP_DIR/index.html.tpl.original $PVE_INDEX_TEMPLATE"
echo "   systemctl restart pveproxy"