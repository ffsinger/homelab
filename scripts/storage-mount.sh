#!/bin/bash

# Check if already opened
if [ ! -e /dev/mapper/data ]; then
    sudo cryptsetup open /dev/disk/by-uuid/${DATA_LUKS_UUID} data --key-file /etc/luks-keys/data_drive.key
    echo "Device opened as /dev/mapper/data"
else
    echo "Device already opened"
fi

# Check if already mounted
if ! mountpoint -q /data; then
    sudo mount -t ext4 /dev/mapper/data /data
    echo "Mounted at /data"
else
    echo "Already mounted at /data"
fi
