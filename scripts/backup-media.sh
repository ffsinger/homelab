#!/bin/bash

# Check if already opened
if [ ! -e /dev/mapper/backup ]; then
    # Check if device exists
    if [ ! -e /dev/disk/by-uuid/${BACKUP_LUKS_UUID} ]; then
        echo "Error: backup device with UUID ${BACKUP_LUKS_UUID} not found"
        exit 1
    fi
    sudo cryptsetup open /dev/disk/by-uuid/${BACKUP_LUKS_UUID} backup
    echo "Device opened as /dev/mapper/backup"
else
    echo "Device already opened"
fi

# Check if already mounted
if ! mountpoint -q /mnt/backup; then
    sudo mount -t ext4 /dev/mapper/backup /mnt/backup
    echo "Mounted at /mnt/backup"
else
    echo "Already mounted at /mnt/backup"
fi

# Backup media folder
sudo rsync -a --delete --info=progress2 /data/downloads/media /mnt/backup/

# Print remaining space on backup drive
echo "Remaining space on backup drive:"
sudo df -h /mnt/backup

# Unmount and close device
sudo umount /mnt/backup
sudo cryptsetup close backup
