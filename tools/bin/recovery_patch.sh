set -e

# Credits to @salvogiangri UN1CA
HEX_PATCH()
{
    #_CHECK_NON_EMPTY_PARAM "FILE" "$1" || return 1
    #_CHECK_NON_EMPTY_PARAM "FROM" "$2" || return 1
    #_CHECK_NON_EMPTY_PARAM "TO" "$3" || return 1

    local FILE="$1"
    local FROM="$2"
    local TO="$3"

    if [ ! -f "$FILE" ]; then
        #LOGE "File not found: ${FILE//$WORK_DIR/}"
        return 1
    fi

    FROM="$(tr "[:upper:]" "[:lower:]" <<< "$FROM")"
    TO="$(tr "[:upper:]" "[:lower:]" <<< "$TO")"

    if ! xxd -p -c 0 "$FILE" | grep -q "$FROM"; then
        echo "No \"$FROM\" match in $FILE"
        return 1
    fi

    echo "Patching \"$FROM\" to \"$TO\" in $FILE"
    xxd -p -c 0 "$FILE" | sed "s/$FROM/$TO/" | xxd -r -p > "$FILE.tmp"
    mv "$FILE.tmp" "$FILE"

    return 0
}

if [ ! -f "$1" ]; then
  echo "cannot find file."
  exit 1
fi

OUT_FILE="$(realpath $1)"

echo "Dest file is $OUT_FILE"

TMP_DIR="$(mktemp -d)"
cd "$TMP_DIR"

magiskboot unpack "$OUT_FILE"
mkdir ramdisk_tmp; cd ramdisk_tmp
magiskboot cpio '../ramdisk.cpio' 'extract system/bin/adbd system/bin/adbd'
magiskboot cpio '../ramdisk.cpio' 'extract system/bin/recovery system/bin/recovery'
magiskboot cpio '../ramdisk.cpio' 'extract system/etc/init/hw/init.rc system/etc/init/hw/init.rc'
magiskboot cpio '../ramdisk.cpio' 'extract system/lib64/libselinux.so system/lib64/libselinux.so'
magiskboot cpio '../ramdisk.cpio' 'extract prop.default prop.default'

# Recovery patches for Samsung TP1A (A05s) recovery images

# Make SELinux permissive
# FILE: system/lib64/libselinux.so

# Function: security_setenforce
# From: mov w19, w0
# To: mov w19, wzr

HEX_PATCH "system/lib64/libselinux.so" "55d03bd5f303002a" "55d03bd5f3031f2a"

# Bypass package signature verification
# FILE: system/bin/recovery

# Function: verify_package
# From:
#   cmp x8,x9
#   b.ne 0x001f9204
# To:
#   nop
#   mov w19, #0x1

HEX_PATCH "system/bin/recovery" "1f0109eb41170054" "1f2003d533008052"

# From:
#   cmp x8, x9
#   b.eq 0x001f8dec
#   mov w0,#0x2
# To:
#   nop
#   b 0x001f8f10
#   mov w0,#0x2

HEX_PATCH "system/bin/recovery" "1f0109eba004005440008052" "1f2003d56e00001440008052"

# Disregard missing ZIP metadata
# FILE: system/bin/recovery

# Function: ReadMetadataFromPackage
# From: mov w19, wzr
# To: mov w19, #0x1

HEX_PATCH "system/bin/recovery" "f3031f2ad5000014" "33008052d5000014"
HEX_PATCH "system/bin/recovery" "f3031f2a950200b9c6ffff17" "33008052950200b9c6ffff17"

# Allow fastbootd
# FILE: system/bin/recovery

# Function: getFastbootdPermission
# From: mov w0, wzr
# To: mov w0, #0x1

HEX_PATCH "system/bin/recovery" "c2f90394e0031f2a" "c2f9039420008052"

# "Reboot to bootloader" reboots to download mode
# FILE: system/bin/recovery

# From: "bootloader"
# To: "download"

HEX_PATCH "system/bin/recovery" "626f6f746c6f6164657200" "646f776e6c6f6164000000"

# ADB always root
# FILE: system/bin/adbd

# Function: main
# From: b.ne 0x001964d4
# To: b 0x001964d4

HEX_PATCH "system/bin/adbd" "1f050071e1090054" "1f0500714f000014"

# Enable ADB by default
sed -i 's/persist\.sys\.usb\.config\=mtp/persist\.sys\.usb\.config\=mtp\,adb/g' "prop.default"
sed -i 's/ro\.adb\.secure\=1/ro\.adb\.secure\=0/g' "prop.default"
sed -i 's/ro\.debuggable\=0/ro\.debuggable\=1/g' "prop.default"

echo "on boot" >> "system/etc/init/hw/init.rc"
echo "    setprop service.adb.root 1" >> "system/etc/init/hw/init.rc"

# Spoof recovery SPL to 2023-08-01 to allow SPL downgrade
sed -i 's/ro\.build\.version\.security_patch\=.*/ro\.build\.version\.security_patch\=2023-08-01/g' "prop.default"

magiskboot cpio '../ramdisk.cpio' 'add 755 system/bin/adbd system/bin/adbd'
magiskboot cpio '../ramdisk.cpio' 'add 755 system/bin/recovery system/bin/recovery'
magiskboot cpio '../ramdisk.cpio' 'add 644 system/etc/init/hw/init.rc system/etc/init/hw/init.rc'
magiskboot cpio '../ramdisk.cpio' 'add 644 system/lib64/libselinux.so system/lib64/libselinux.so'
magiskboot cpio '../ramdisk.cpio' 'add 644 prop.default prop.default'
magiskboot cpio '../ramdisk.cpio' 'ln system/bin sbin'

cd ..
magiskboot repack "$OUT_FILE" recovery.img
mv recovery.img "$OUT_FILE"
