#!/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

################################################################################
# LYNX ISO BUILDER SCRIPT
################################################################################
#
# PURPOSE:
#   This script creates a customized Raspberry Pi OS 64-bit ARM image with Lynx cryptocurrency
#   node software pre-installed and configured. It downloads a base Raspberry Pi
#   OS 64-bit ARM image, modifies it to include Lynx node setup, and creates a ready-to-use
#   image file for distribution.
#
# AUTHOR: Lynx Development Team
# VERSION: 2.0
# LAST UPDATED: 2025
# DOCUMENTATION: https://docs.getlynx.io/
#
################################################################################
#
# FUNCTIONALITY OVERVIEW:
#   This script performs the following operations in sequence:
#
#   1. IMAGE ACQUISITION:
#      - Downloads latest Raspberry Pi OS Lite 64-bit ARM image (if no URL provided)
#      - Or downloads a specific image from provided URL
#      - Extracts the compressed .xz image file
#      - Validates the image file integrity
#
#   2. IMAGE MODIFICATION:
#      - Detects partition offsets (boot and root partitions)
#      - Mounts partitions safely with proper error handling
#      - Creates rc.local script for automatic Lynx node setup
#      - Configures the image to download and run install.sh on first boot
#
#   3. OUTPUT GENERATION:
#      - Creates final image with date-stamped filename
#      - Compresses the image using high-compression xz
#      - Produces ready-to-distribute .img.xz file
#
################################################################################
#
# USAGE:
#   ./iso-builder.sh                    # Download and use latest Raspberry Pi OS 64-bit ARM
#   ./iso-builder.sh "URL_TO_IMAGE.XZ"  # Use specific image URL
#
# EXAMPLES:
#   ./iso-builder.sh
#   ./iso-builder.sh "https://downloads.raspberrypi.org/raspios_lite_arm64/images/raspios_lite_arm64-2023-05-03/2023-05-03-raspios-bullseye-arm64-lite.img.xz"
#
################################################################################
#
# SYSTEM REQUIREMENTS:
#   - Linux system (tested on Debian/Ubuntu)
#   - Root privileges (required for mounting operations)
#   - Internet connection (for downloading images)
#   - Sufficient disk space (at least 8GB free space recommended)
#   - 64-bit ARM-compatible system (for 64-bit ARM image processing)
#
# DEPENDENCIES:
#   - bash, wget, curl, unxz, xz
#   - mount, umount, losetup
#   - fdisk, stat, file
#   - mkdir, mv, chmod
#
################################################################################
#
# SECURITY FEATURES:
#   - Validates downloaded files before processing
#   - Checks partition offsets to prevent mounting errors
#   - Uses safe file operations (no wildcards)
#   - Proper error handling and cleanup
#   - Loop device management to prevent conflicts
#
################################################################################
#
# OUTPUT FILES:
#   - YYYY-MM-DD-Lynx-RPI-ISO.img (extracted and modified 64-bit ARM image)
#   - YYYY-MM-DD-Lynx-RPI-ISO.img.xz (final compressed distribution file)
#
# TEMPORARY FILES:
#   - Downloaded .xz file (deleted after extraction)
#   - Mount points: /mnt/lynx1, /mnt/lynx2 (cleaned up after use)
#   - Loop devices (detached after processing)
#
################################################################################
#
# FIRST BOOT BEHAVIOR:
#   When the created image boots for the first time:
#   1. Displays IP address information
#   2. Waits 60 seconds for network initialization
#   3. Tests network connectivity (ping 8.8.8.8)
#   4. Downloads and executes install.sh from GitHub
#   5. Sets up Lynx node automatically
#   6. Reboots if network is unavailable (retries every 60 seconds)
#
################################################################################
#
# TROUBLESHOOTING:
#   - "No .img file found": Check if download/extraction succeeded
#   - "Failed to mount": Check loop device conflicts (use losetup -D)
#   - "Invalid disk image": Verify downloaded file integrity
#   - "Partition offset exceeds image size": Corrupted or wrong image file
#   - "Overlapping loop device": Clean up with losetup -D and umount -f
#
# COMMON COMMANDS:
#   losetup -a                    # Check attached loop devices
#   losetup -D                    # Detach all loop devices
#   umount -f /mnt/lynx1 /mnt/lynx2  # Force unmount
#   file *.img                    # Check image file type
#   fdisk -l *.img               # View partition information
#
################################################################################
#
# NETWORK REQUIREMENTS:
#   - Outbound HTTPS access to GitHub (for install.sh download)
#   - Outbound HTTP/HTTPS to Raspberry Pi Foundation (for OS downloads)
#   - ICMP access for network connectivity testing (ping 8.8.8.8)
#
# REMOTE RESOURCES:
#   - GitHub: https://raw.githubusercontent.com/getlynx/Lynx/refs/heads/main/contrib/installer/install.sh
#   - Raspberry Pi Foundation: https://downloads.raspberrypi.org/
#
################################################################################
#
# EXIT CODES:
#   0 - Success
#   1 - Error (various conditions with descriptive messages)
#
# LOGGING:
#   - All operations output to stdout/stderr
#   - Progress indicators for downloads
#   - Detailed error messages for troubleshooting
#
################################################################################
#
# WARNING:
#   This script requires root privileges and performs system-level operations.
#   Ensure you have sufficient disk space and are running on a compatible system.
#   The script will modify mounted filesystems and create loop devices.
#
################################################################################

# If the download URL of the target img is not supplied, then find the latest release
if [ -z "$1" ]; then
    echo "No target URL provided, finding the latest Raspberry Pi OS Lite release..."
    
    # Base URL for Raspberry Pi OS Lite releases
    base_url="https://downloads.raspberrypi.org/raspios_lite_arm64/images/"
    
    # Function to get the latest release directory
    get_latest_release() {
        local url="$1"
        local latest_dir=""
        local latest_date=""
        
        # Get the directory listing and find the latest release folder
        while IFS= read -r line; do
            # Look for directory links that match the pattern raspios_lite_arm*-YYYY-MM-DD
            if [[ $line =~ href=\"(raspios_lite_arm[^-]*-[0-9]{4}-[0-9]{2}-[0-9]{2})/\" ]]; then
                local dir_name="${BASH_REMATCH[1]}"
                local date_part=$(echo "$dir_name" | grep -o '[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}')
                
                # Compare dates to find the latest
                if [[ "$date_part" > "$latest_date" ]]; then
                    latest_date="$date_part"
                    latest_dir="$dir_name"
                fi
            fi
        done < <(curl -s "$url")
        
        echo "$latest_dir"
    }
    
    # Function to get the latest .xz file from a release directory
    get_latest_xz_file() {
        local release_dir="$1"
        local release_url="${base_url}${release_dir}/"
        local latest_xz=""
        local latest_date=""
        
        # Get the directory listing and find the latest .xz file
        while IFS= read -r line; do
            # Look for .xz files that match the pattern YYYY-MM-DD-raspios-*.img.xz
            if [[ $line =~ href=\"([0-9]{4}-[0-9]{2}-[0-9]{2}-raspios-[^.]*\.img\.xz)\" ]]; then
                local xz_file="${BASH_REMATCH[1]}"
                local date_part=$(echo "$xz_file" | grep -o '^[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}')
                
                # Compare dates to find the latest
                if [[ "$date_part" > "$latest_date" ]]; then
                    latest_date="$date_part"
                    latest_xz="$xz_file"
                fi
            fi
        done < <(curl -s "$release_url")
        
        echo "${release_url}${latest_xz}"
    }
    
    # Get the latest release directory
    latest_release_dir=$(get_latest_release "$base_url")
    
    if [ -z "$latest_release_dir" ]; then
        echo "Error: Could not find any release directories"
        exit 1
    fi
    
    echo "Found latest release directory: $latest_release_dir"
    
    # Get the latest .xz file from the latest release
    target=$(get_latest_xz_file "$latest_release_dir")
    
    if [ -z "$target" ]; then
        echo "Error: Could not find any .xz files in the latest release"
        exit 1
    fi

    echo "Downloading the latest OS package. This is the new modified target OS."
    echo "Latest .xz file found: $target"
    
    # Check if extracted file already exists
    downloaded_file=$(basename "$target")
    img_file=$(basename "$downloaded_file" .xz)
    if [ -f "$img_file" ]; then
        echo "Extracted image file $img_file already exists, skipping download and extraction."
    else
        wget --progress=bar:force "$target"
    fi
else
    echo "Downloading the supplied OS package. This is the new modified target OS."
    target="$1"
    
    # Check if extracted file already exists
    downloaded_file=$(basename "$target")
    img_file=$(basename "$downloaded_file" .xz)
    if [ -f "$img_file" ]; then
        echo "Extracted image file $img_file already exists, skipping download and extraction."
    else
        wget --progress=bar:force "$target"
    fi
fi

# Unpack the downloaded file
echo "Target OS downloaded, unpacking the compressed file."
if [ -f "$downloaded_file" ]; then
    unxz "$downloaded_file"
elif [ ! -f "$img_file" ]; then
    echo "Error: Neither downloaded file $downloaded_file nor extracted file $img_file found"
    exit 1
else
    echo "Using existing extracted file $img_file"
fi

# Create the dir for the image we are gonna mount.
mkdir -p /mnt/lynx1
mkdir -p /mnt/lynx2

# Get the correct offset values for the partitions
echo "Detecting partition offsets..."
img_file=$(basename "$downloaded_file" .xz)
if [ ! -f "$img_file" ]; then
    echo "Error: Extracted image file $img_file not found"
    exit 1
fi

# Validate that it's actually a disk image
if ! file "$img_file" | grep -q "DOS/MBR boot sector\|Linux.*boot sector"; then
    echo "Error: $img_file is not a valid disk image"
    exit 1
fi

# Get partition information using fdisk with error handling
if ! fdisk_output=$(fdisk -l "$img_file" 2>&1); then
    echo "Error: Failed to read partition table: $fdisk_output"
    exit 1
fi

# Get image file size for validation
image_size=$(stat -c %s "$img_file")
if [ -z "$image_size" ] || [ "$image_size" -le 0 ]; then
    echo "Error: Could not determine image file size"
    exit 1
fi

# Extract boot partition offset (first partition, usually vfat)
boot_offset=$(echo "$fdisk_output" | grep -A 10 "Device" | grep -E "^.*img1" | awk '{print $2 * 512}')
if [ -z "$boot_offset" ] || ! [[ "$boot_offset" =~ ^[0-9]+$ ]] || [ "$boot_offset" -lt 0 ]; then
    echo "Error: Could not detect valid boot partition offset"
    exit 1
fi

# Extract root partition offset (second partition, usually ext4)
root_offset=$(echo "$fdisk_output" | grep -A 10 "Device" | grep -E "^.*img2" | awk '{print $2 * 512}')
if [ -z "$root_offset" ] || ! [[ "$root_offset" =~ ^[0-9]+$ ]] || [ "$root_offset" -lt 0 ]; then
    echo "Error: Could not detect valid root partition offset"
    exit 1
fi

# Validate that offsets are within image file bounds
if [ "$boot_offset" -ge "$image_size" ]; then
    echo "Error: Boot partition offset ($boot_offset) exceeds image file size ($image_size)"
    exit 1
fi

if [ "$root_offset" -ge "$image_size" ]; then
    echo "Error: Root partition offset ($root_offset) exceeds image file size ($image_size)"
    exit 1
fi

# Validate that root offset is after boot offset
if [ "$root_offset" -le "$boot_offset" ]; then
    echo "Error: Root partition offset ($root_offset) must be after boot partition offset ($boot_offset)"
    exit 1
fi

echo "Boot partition offset: $boot_offset"
echo "Root partition offset: $root_offset"
echo "Image file size: $image_size"

# Mount single partition from image of entire disk (device) - Ask Ubuntu
echo "Mounting the target virtual OS."

# Ensure mount points and loop devices are clean
echo "Cleaning up any existing mounts and loop devices..."
umount /mnt/lynx1 2>/dev/null || true
umount /mnt/lynx2 2>/dev/null || true

# Detach any existing loop devices for this image
if losetup -a | grep -q "$img_file"; then
    echo "Detaching existing loop devices for $img_file"
    losetup -a | grep "$img_file" | awk -F: '{print $1}' | xargs -r losetup -d
fi

# Mount boot partition
echo "Mounting boot partition..."
if ! mount -v -o offset="$boot_offset" -t vfat "$img_file" /mnt/lynx1; then
    echo "Error: Failed to mount boot partition"
    exit 1
fi

# Verify boot partition is mounted and has expected structure
if [ ! -f "/mnt/lynx1/bootcode.bin" ] && [ ! -f "/mnt/lynx1/cmdline.txt" ] && [ ! -f "/mnt/lynx1/config.txt" ]; then
    echo "Warning: Boot partition doesn't have expected boot files, but continuing..."
else
    echo "Boot partition mounted successfully"
fi

# Unmount boot partition since we don't need it for this script
echo "Unmounting boot partition (not needed for this operation)..."
umount /mnt/lynx1

# Mount root partition
echo "Mounting root partition..."
if ! mount -v -o offset="$root_offset" -t ext4 "$img_file" /mnt/lynx2; then
    echo "Error: Failed to mount root partition"
    exit 1
fi

# Verify root partition is mounted and has expected structure
if [ ! -d "/mnt/lynx2/etc" ]; then
    echo "Error: Root partition doesn't have expected structure"
    umount /mnt/lynx2
    exit 1
fi

echo "Root partition mounted successfully"

echo "Setting up the rc.local file on the target OS."
echo "#!/bin/sh -e
#
# Print the IP address
_IP=\$(hostname -I) || true
if [ \"\$_IP\" ]; then
  printf \"My IP address is %s\n\" \"\$_IP\"
fi

printf \"\n\n\n\n\n\n\n\nLynx initialization will start in 60 seconds.\n\n\n\n\n\n\"
sleep 60

# Ping Google NS server to test public network access
if timeout 10 /bin/ping -c 1 8.8.8.8
then
        sleep 30
        wget -qO /usr/local/bin/install.sh https://raw.githubusercontent.com/getlynx/Lynx/refs/heads/main/contrib/installer/install.sh && chmod +x /usr/local/bin/install.sh && /usr/local/bin/install.sh
else
        echo \"Network access was not detected. For best results, connect an ethernet cable to your home or work wifi router. This device will reboot and try again in 60 seconds. For more information, visit https://docs.getlynx.io/lynx-core/lynxci/iso-for-raspberry-pi\"
        sleep 60
        reboot
fi
exit 0
" > /mnt/lynx2/etc/rc.local

# Set proper permissions for rc.local
chmod 755 /mnt/lynx2/etc/rc.local

# Clean up mounts and loop devices
echo "Unmounting partitions and cleaning up loop devices..."
umount /mnt/lynx2 2>/dev/null || true
umount /mnt/lynx1 2>/dev/null || true

# Detach loop devices for this image
if losetup -a | grep -q "$img_file"; then
    echo "Detaching loop devices for $img_file"
    losetup -a | grep "$img_file" | awk -F: '{print $1}' | xargs -r losetup -d
fi

currentDate=$(date +%F)
mv "$img_file" "$currentDate"-Lynx-RPI-ISO.img

echo "Compressing the modified target OS. This might take a while due to the high level of compression used with xz."
echo "Compression progress:"
xz -9 -v "$currentDate"-Lynx-RPI-ISO.img

echo "The file $currentDate-Lynx-RPI-ISO.img.xz is now ready for distribution."
