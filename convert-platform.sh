#!/bin/bash

set -e

application_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
output_dir=${application_dir}/output
files_dir=${application_dir}/files
build_log=${output_dir}/build.log

target_boot_dir=${output_dir}/boot
target_rootfs_dir=${output_dir}/rootfs

bootloader_toolchain=$1

[ ! -d "${target_boot_dir}" ] && \
    { log "Error: boot location not mounted."; exit 1; }
[ ! -d "${target_rootfs_dir}" ] && \
    { log "Error: embedded content not mounted."; exit 1; }

platform_arch="unknown"
platform_type="unknown"

util_find_kernel_image() {
  kernel_image_path=""
  for image in vmlinuz zImage bzImage; do
      kernel_image_path=$(sudo find ${1} -name ${image}* ! -name '*-rescue-*')

      if [ -n "${kernel_image_path}" ]; then
        break
      fi
  done
  echo -n ${kernel_image_path}
}

# Yes, I know!
generic_raspberrypi() {
  ${application_dir}/convert-platform-rpi.sh ${bootloader_toolchain}
}

generic_x86() {
  true
}

# Assumption made that this is called from generic()
generic_arm() {
  # DTB naming is a very platform specific thing and hard to probe in cases
  # where multiple DTB`s files are present on target, which is quite common
  # on hacker-board type of boards. This should probably come in via
  # a configuration file along with other platform specific configuration.
  if [ "${platform_type}" == "bbb" ]; then
    dtb_name="am335x-boneblack.dtb"
  else
    log "\tSorry, we have no way of knowing which DTB file your board is \n\t \
        using and it needs to be provided in this switch."
    exit 1
  fi

  kernel_devicetree=$(basename $(find ${target_rootfs_dir}/boot -name ${dtb_name}))
  sed -i '/^kernel_devicetree/s/=.*$/='${kernel_devicetree//\//\\/}'/' mender_grubenv_defines

  log "\tInstalling GRUB2 EFI "
  sudo install -d ${target_boot_dir}/EFI/BOOT
  sudo install -m 0644 ${files_dir}/efi-arm/grub-efi-bootarm.efi ${target_boot_dir}/EFI/BOOT/grub.efi

  # Erase/create the fstab file.
  sudo install -b -m 644 /dev/null ${target_rootfs_dir}/etc/fstab

  # Add Mender specific entries to fstab.
  cat <<- EOF > ${target_rootfs_dir}/etc/fstab
# stock fstab - you probably want to override this with a machine specific one

/dev/root            /                    auto       defaults              1  1
debugfs              /sys/kernel/debug    debugfs    defaults              0  0
proc                 /proc                proc       defaults              0  0
devpts               /dev/pts             devpts     mode=0620,gid=5       0  0
tmpfs                /run                 tmpfs      mode=0755,nodev,nosuid,strictatime 0  0
tmpfs                /var/volatile        tmpfs      defaults              0  0

/dev/mmcblk0p1   /boot/efi            auto       defaults,sync    0  0
/dev/mmcblk0p4   /data                auto       defaults         0  0
EOF
}

generic() {
  log "\tBuilding GRUB2 boot scripts and tools."
  local grubenv_dir=$output_dir/grubenv
  local grubenv_repo_vc_dir=$grubenv_dir/.git

  if [ ! -d $grubenv_repo_vc_dir ]; then
    git clone -b 1.2.0 https://github.com/mendersoftware/grub-mender-grubenv.git $grubenv_dir >> "$build_log" 2>&1
  fi

  cd $grubenv_dir

  # Remove old defines & settings.
  make --quiet distclean >> "$build_log" 2>&1

  cp mender_grubenv_defines.example mender_grubenv_defines

  # Linux kernel image type and naming varies between different platforms, this
  # also applies to DTB file name. lets do a little dance and try to figure
  # out the file-name.
  #
  # The wildcard at the end is important, because it is common to suffix the
  # Linux kernel version to the image type/name, e.g:
  #
  #    vmlinuz-4.14-x86_64
  #    vmlinuz-3.10.0-862.el7.x86_64
  #
  kernel_imagetype=""
  initrd_image_path=""
  for boot in ${target_boot_dir} ${target_rootfs_dir}; do
    kernel_imagetype=$(util_find_kernel_image ${boot})
    if [ -n "${kernel_imagetype}" ] && [ "${boot}" == "${target_boot_dir}" ]; then
      sudo cp ${kernel_imagetype} ${target_rootfs_dir}/boot

      # Chances are high there is a initramfs image as well here.
      initrd_image_path=$(sudo find ${target_boot_dir} -name initramfs-* ! -name '*-rescue-*')
      if [ -n "${initrd_image_path}" ]; then
        sudo cp ${initrd_image_path} ${target_rootfs_dir}/boot
      fi
      break;
    elif [ -n "${kernel_imagetype}" ]; then
      break;
    fi
  done

  if [ -n "${kernel_imagetype}" ]; then
    kernel_imagetype=$(basename ${kernel_imagetype})
    log "\tFound Linux kernel image: \n\n\t${kernel_imagetype}\n"
    sed -i '/^kernel_imagetype/s/=.*$/='${kernel_imagetype}'/' mender_grubenv_defines
  fi

  if [ -n "${initrd_image_path}" ]; then
    initrd_imagetype=$(basename ${initrd_image_path})
    log "\tFound initramfs image: \n\n\t${initrd_imagetype}\n"
    sed -i '/^initrd_imagetype/s/=.*$/='${initrd_imagetype}'/' mender_grubenv_defines
  fi

  if [ "${platform_arch}" == "arm" ]; then
    generic_arm
  fi

  make --quiet >> "$build_log" 2>&1
  log "\tInstalling GRUB2 boot scripts and tools."
  sudo make --quiet DESTDIR=${target_rootfs_dir} install >> "$build_log" 2>&1
}

# Raspberry Pi specific boot firmware file
if [ -e ${target_boot_dir}/start_x.elf ]; then
  platform_arch="arm"
  platform_type="raspberrypi"
# MLO is the Beaglebone Black first stage bootloader
elif [ -e ${target_rootfs_dir}/opt/backup/uboot/MLO ]; then
  platform_arch="arm"
  platform_type="bbb"
else
  if file ${target_rootfs_dir}/bin/ls | grep --quiet ARM; then
    platform_arch="arm"
  elif file ${target_rootfs_dir}/bin/ls | grep --quiet x86; then
    platform_arch="x86"
  else
    log "\Unsupported architecture"
    exit 1
  fi

  platform_type="generic"
fi

log "\tArchitecture: ${platform_arch}"
log "\tPlatform: ${platform_type}"

if [ "${platform_type}" == "raspberrypi" ]; then
  generic_raspberrypi
else
  generic
fi

if [ "${platform_type}" == "bbb" ]; then
  ${application_dir}/convert-platform-bbb.sh
fi
