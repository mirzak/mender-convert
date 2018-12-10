#!/bin/bash

set -e

application_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

output_dir=${application_dir}/output

target_boot_dir=${output_dir}/boot
target_rootfs_dir=${output_dir}/rootfs

uboot_backup_dir=${target_rootfs_dir}/opt/backup/uboot

[[ ! -f $uboot_backup_dir/MLO || ! -f $uboot_backup_dir/u-boot.img ]] && \
{ log "Error: cannot find U-Boot related files."; exit 1; }

# TODO: Get rid of this, simply copy the initial blocks which
# contains MLO and u-boot.
sudo cp ${uboot_backup_dir}/MLO ${target_boot_dir}/MLO
sudo cp ${uboot_backup_dir}/u-boot.img ${target_boot_dir}/u-boot.img

# Fill uEnv.txt file.
cat <<- 'EOF' | sudo tee ${target_boot_dir}/uEnv.txt 2>&1 >/dev/null
bootdir=
grubfile=EFI/BOOT/grub.efi
grubaddr=0x80007fc0
loadgrub=fatload mmc 0:1 ${grubaddr} ${grubfile}
grubstart=bootefi ${grubaddr}
uenvcmd=mmc rescan; run loadgrub; run grubstart;
EOF

# Replace U-Boot default printenv/setenv commands.
sudo ln -fs /sbin/fw_printenv ${target_rootfs_dir}/usr/bin/fw_printenv
sudo ln -fs /sbin/fw_setenv ${target_rootfs_dir}/usr/bin/fw_setenv

#Replace U-Boot default images for Debian 9.5
if grep -q '9.5' ${target_rootfs_dir}/etc/debian_version ; then
 sudo cp ${application_dir}/files/uboot_debian_9.4/MLO ${target_boot_dir}/MLO
 sudo cp ${application_dir}/files/uboot_debian_9.4/u-boot.img ${target_boot_dir}/u-boot.img
fi
