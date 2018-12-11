#!/bin/bash

application_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

files_dir=${application_dir}/files
output_dir=${application_dir}/output
target_boot_dir=${output_dir}/boot
target_rootfs_dir=${output_dir}/rootfs
uboot_dir=${output_dir}/uboot-mender
build_log=${output_dir}/build.log

bootloader_toolchain=$1

[ ! -d "${target_boot_dir}" ] && \
    { log "Error: boot location not mounted."; exit 1; }
[ ! -d "${target_rootfs_dir}" ] && \
    { log "Error: embedded content not mounted."; exit 1; }

build_and_install_uboot_files() {
  local CROSS_COMPILE=${1}-
  local ARCH=arm
  local branch="mender-rpi-2017.09"
  local commit="988e0ec54"
  local uboot_repo_vc_dir=$uboot_dir/.git

  export CROSS_COMPILE=$CROSS_COMPILE
  export ARCH=$ARCH

  log "\tBuilding U-Boot related files."

  cd ${output_dir}

  if [ ! -d $uboot_repo_vc_dir ]; then
    git clone https://github.com/mendersoftware/uboot-mender.git -b $branch >> "$build_log" 2>&1
  fi

  cd ${uboot_dir}

  git checkout $commit >> "$build_log" 2>&1

  make --quiet distclean >> "$build_log"
  make --quiet rpi_3_32b_defconfig >> "$build_log" 2>&1
  make --quiet -j $(nproc) >> "$build_log" 2>&1
  make --quiet envtools >> "$build_log" 2>&1

  cat<<-'EOF' >boot.cmd
fdt addr ${fdt_addr} && fdt get value bootargs /chosen bootargs
run mender_setup
mmc dev ${mender_uboot_dev}
load ${mender_uboot_root} ${kernel_addr_r} /boot/zImage
bootz ${kernel_addr_r} - ${fdt_addr}
run mender_try_to_recover
EOF

  if [ ! -e $uboot_dir/tools/mkimage ]; then
    log "Error: cannot build U-Boot. Aborting"
    return 1
  fi

  $uboot_dir/tools/mkimage -A arm -T script -C none -n "Boot script" -d "boot.cmd" boot.scr >> "$build_log" 2>&1

  log "\tInstalling U-Boot related files."

  cp $uboot_dir/boot.scr ${target_boot_dir}
  cp $uboot_dir/u-boot.bin ${target_boot_dir}/kernel7.img

  sudo install -m 755 $uboot_dir/tools/env/fw_printenv ${target_rootfs_dir}/sbin/fw_printenv
  sudo ln -fs /sbin/fw_printenv ${target_rootfs_dir}/sbin/fw_setenv

  return 0
}

log "\tPerforming Raspberry specific changes"

sudo sed -i 's/\b[ ]root=[^ ]*/ root=\${mender_kernel_root}/' ${target_boot_dir}/cmdline.txt
sudo sed -i 's/\b[ ]console=tty1//' ${target_boot_dir}/cmdline.txt
sudo echo 'enable_uart=1' >> ${target_boot_dir}/config.txt

# If the the image that we are trying to convert has been booted once on a
# device, it will have removed the init_resize.sh init argument from cmdline.
#
# But we want it to run on our image as well to resize our data part so in
# case it is missing, add it back to cmdline.txt
if ! grep -q "init=/usr/lib/raspi-config/init_resize.sh" ${target_boot_dir}/cmdline.txt; then
  sudo echo -e ' init=/usr/lib/raspi-config/init_resize.sh' >> ${target_boot_dir}/cmdline.txt
fi

# Mask udisks2.service, otherwise it will mount the inactive part and we
# might write an update while it is mounted which often result in
# corruptions.
#
# TODO: Find a way to only blacklist mmcblk0pX devices instea of masking
# the service.
sudo ln -sf /dev/null ${target_rootfs_dir}/etc/systemd/system/udisks2.service

# Extract Linux kernel and install to /boot directory on rootfs
sudo cp ${target_boot_dir}/kernel7.img ${target_rootfs_dir}/boot/zImage

# Mountpoint for boot part
sudo mkdir -p ${target_rootfs_dir}/uboot

# dtoverlays seems to break U-boot for some reason, simply remove all of
# them as they do not actually work when U-boot is used.
sudo sed -i /^dtoverlay=/d ${target_boot_dir}/config.txt

# Raspberry Pi configuration files, applications expect to find this on
# the device and in some cases parse the options to determinate
# functionality.
sudo ln -fs /uboot/config.txt ${target_rootfs_dir}/boot/config.txt

# Override init script to expand the data part instead of rootfs, which it
# normally expands in standard Raspberry Pi distributions.
sudo install -m 755 ${files_dir}/init_resize.sh \
    ${target_rootfs_dir}/usr/lib/raspi-config/init_resize.sh

 # Add Mender specific entries to fstab.
cat <<- EOF > ${target_rootfs_dir}/etc/fstab
# stock fstab - you probably want to override this with a machine specific one

/dev/root            /                    auto       defaults              1  1
debugfs              /sys/kernel/debug    debugfs    defaults              0  0
proc                 /proc                proc       defaults              0  0
devpts               /dev/pts             devpts     mode=0620,gid=5       0  0
tmpfs                /run                 tmpfs      mode=0755,nodev,nosuid,strictatime 0  0
tmpfs                /var/volatile        tmpfs      defaults              0  0

/dev/mmcblk0p1   /uboot                   auto       defaults,sync    0  0
/dev/mmcblk0p4   /data                    auto       defaults         0  0
EOF

build_and_install_uboot_files ${bootloader_toolchain}
