#!/bin/bash

#    Copyright 2018 Northern.tech AS
#    Copyright 2018 Piper Networks Inc.
#
#    Licensed under the Apache License, Version 2.0 (the "License");
#    you may not use this file except in compliance with the License.
#    You may obtain a copy of the License at
#
#        http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS,
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    See the License for the specific language governing permissions and
#    limitations under the License.

application_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
output_dir=${MENDER_CONVERSION_OUTPUT_DIR:-${application_dir}}/output

set -e

echo "Running: $(basename $0)"
echo "args: $#"

align_partition_size() {
  local rvar_size=$1
  local rvar_alignment=$2

  size_in_bytes=$(( $rvar_size * 512 ))
  alignment_in_bytes=$(( $rvar_alignment * 512))
  remainder=$(( ${size_in_bytes} % ${alignment_in_bytes} ))

  if [ $remainder -ne 0 ]; then
    size_in_bytes=$(( $size_in_bytes - $remainder + $alignment_in_bytes ))
  fi

  local lsize=$(( $size_in_bytes / 512 ))

  echo $lsize
}

if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ] || [ -z "$5" ]; then
    echo "Usage:"
    echo "    $(basename $0) < rootfs part size > < data part size > < swap part size > < image-alignment > < platform >"
    exit 1
fi

rootfs_part_size=$1
data_part_size=$2
swap_part_size=$3
image_alignment=$4
mender_platform=$5

# Convert to 512 blocks
rootfs_part_size=$(expr ${rootfs_part_size} \* 1024 \* 2)
data_part_size=$(expr ${data_part_size} \* 1024 \* 2)
[ ${swap_part_size} -ne 0 ] && swap_part_size=$(expr ${swap_part_size} \* 1024 \* 2)

if [ ! -f ${output_dir}/rootfs/usr/bin/mender ]; then
    echo "Can not find Mender client on target root file-system"
    exit 1
fi

device_type=$(cat ${output_dir}/data/mender/device_type | sed 's/[^=]*=//')
artifact_name=$(cat ${output_dir}/rootfs/etc/mender/artifact_info | sed 's/[^=]*=//')

if [ -z "${device_type}" ]; then
    echo "Device type not found in root file-system. Aborting..."
    exit 1
fi

if [ -z "${artifact_name}" ]; then
    echo "Artifact name not found in root file-system. Aborting..."
    exit 1
fi

# Make sure that everything is flushed before we create the file-systems
sync

actual_rootfs_size=$(sudo du -s --block-size=512 ${output_dir}/rootfs | awk '{ print $1 }')

# 20 % free space, not to be confused with rootfs_part_size
rootfs_size=$(awk -v r1="$actual_rootfs_size" 'BEGIN{printf "%.0f", r1 * 1.20}')

if [ ${rootfs_size} -gt ${rootfs_part_size} ]; then
    echo "Error.  Specified partition size ${rootfs_part_size} is too small."
    echo "The original filesystem requires ${rootfs_size} blocks."
    exit 1
fi

echo "Creating a ext4 file-system image from modified root file-system"
dd if=/dev/zero of=${output_dir}/rootfs.ext4 seek=${rootfs_size} count=0 bs=512 status=none conv=sparse

# From mkfs.ext4 man page
#
# -F
#     Force mke2fs to create a filesystem, even if the specified device is not
#     a partition on a block special device, or if other parameters do not make
#     sense. In order to force mke2fs to create a filesystem even if the
#     filesystem appears to be in use or is mounted (a truly dangerous thing
#     to do), this option must be specified twice.
sudo mkfs.ext4 -FF ${output_dir}/rootfs.ext4
mkdir ${output_dir}/rootfs-output
sudo mount ${output_dir}/rootfs.ext4 ${output_dir}/rootfs-output
sudo rsync -SaqP --delete ${output_dir}/rootfs/ ${output_dir}/rootfs-output/
sudo umount ${output_dir}/rootfs-output
rmdir ${output_dir}/rootfs-output

# Do a file-system check and fix if there are any problems
(fsck.ext4 -fp ${output_dir}/rootfs.ext4 || true)

echo "Creating an ext4 file-system image of /data contents"
dd if=/dev/zero of=${output_dir}/data.ext4 seek=${data_part_size} count=0 bs=512 status=none conv=sparse
sudo mkfs.ext4 -F ${output_dir}/data.ext4
mkdir ${output_dir}/data-output
sudo mount ${output_dir}/data.ext4 ${output_dir}/data-output
sudo rsync -SaqP --delete ${output_dir}/data/ ${output_dir}/data-output/
sudo umount ${output_dir}/data-output
rmdir ${output_dir}/data-output

# Do a file-system check and fix if there are any problems
(fsck.ext4 -fp ${output_dir}/data.ext4 || true)

# Apply the label
e2label ${output_dir}/data.ext4 data

mender_artifact=${output_dir}/${device_type}-${artifact_name}.mender

echo "Writing Mender artifact to: ${mender_artifact}"

#Create Mender artifact
${application_dir}/bin/mender-artifact write rootfs-image \
    --update ${output_dir}/rootfs.ext4 \
    --output-path ${mender_artifact} \
    --artifact-name ${artifact_name} \
    --device-type ${device_type}

echo "Creating Mender compatible disk-image"

if [ ! -f ${output_dir}/boot-part-env ]; then
    echo "${output_dir}/boot-part-env: not found"
    exit 1
fi

. ${output_dir}/boot-part-env

# number of sectors, 12MB
#
# We should really use the value in boot_part_start as alignment but current
# integration of raspberrypi puts U-boot env at 8 MB offset so have to put the
# alignment further in at 12 MB, which is also the start of boot part.
if [ ${swap_part_size} -eq 0 ]; then
    # boot, rootfsa, rootfsb, data
    number_of_partitions="4"
else
    # the same 4 as above plus extended and swap
    number_of_partitions="6"
fi

sdimg_path=${output_dir}/${device_type}-${artifact_name}.sdimg
sdimg_size=$(expr ${image_alignment} \* ${number_of_partitions} + ${boot_part_size} + ${rootfs_part_size} \* 2 + ${data_part_size} + ${swap_part_size})

echo "Creating filesystem with :"
echo "    Boot partition $(expr ${boot_part_size} / 2) KiB"
echo "    RootFS         $(expr ${rootfs_part_size} / 2) KiB"
echo "    Data           $(expr ${data_part_size} / 2) KiB"
[ ${swap_part_size} -ne 0 ] && echo "    Swap           $(expr ${swap_part_size} / 2) KiB"

if [ ! -f ${output_dir}/boot.vfat ]; then
    echo "${output_dir}/boot.vfat: not found"
    exit 1
fi

# Initialize sdcard image file
dd if=/dev/zero of=${sdimg_path} bs=512 count=0 seek=${sdimg_size} conv=sparse

# Align sizes
boot_part_size=$(align_partition_size ${boot_part_size} ${image_alignment})
rootfs_part_size=$(align_partition_size ${rootfs_part_size} ${image_alignment})
data_part_size=$(align_partition_size ${data_part_size} ${image_alignment})
[ ${swap_part_size} -ne 0 ] && swap_part_size=$(align_partition_size ${swap_part_size} ${image_alignment})

boot_part_start=${image_alignment}
boot_part_end=$(expr ${boot_part_start} + ${boot_part_size} - 1)
rootfsa_start=$(expr ${boot_part_end} + ${image_alignment} + 1)
rootfsa_end=$(expr ${rootfsa_start} + ${rootfs_part_size} - 1)
rootfsb_start=$(expr ${rootfsa_end} + ${image_alignment} + 1)
rootfsb_end=$(expr ${rootfsb_start} + ${rootfs_part_size} - 1)
if [ ${swap_part_size} -eq 0 ]; then
    data_start=$(expr ${rootfsb_end} + ${image_alignment} + 1)
    data_end=$(expr ${data_start} + ${data_part_size} - 1)
else
    ext_start=$(expr ${rootfsb_end} + ${image_alignment} + 1)
    # Note that since the extended partition contains the data partition
    # rather than preceding it on the disk, we don't need to add 1 here.
    data_start=$(expr ${ext_start} + ${image_alignment})
    data_end=$(expr ${data_start} + ${data_part_size} - 1)
    swap_start=$(expr ${data_end} + ${image_alignment} + 1)
    swap_end=$(expr ${swap_start} + ${swap_part_size} - 1)
fi

echo "boot_start: ${boot_part_start}"
echo "rootfsa_start: ${rootfsa_start}"
echo "rootfsb_start: ${rootfsb_start}"
[ ${swap_part_size} -ne 0 ] && echo "ext_start: ${ext_start}"
echo "data_start: ${data_start}"
[ ${swap_part_size} -ne 0 ] && echo "swap_start: ${swap_start}"

# Create partition table
parted -s ${sdimg_path} mklabel msdos
# Create boot partition and mark it as bootable
parted -s ${sdimg_path} unit s mkpart primary fat32 ${boot_part_start} ${boot_part_end}
parted -s ${sdimg_path} set 1 boot on
parted -s ${sdimg_path} -- unit s mkpart primary ext2 ${rootfsa_start} ${rootfsa_end}
parted -s ${sdimg_path} -- unit s mkpart primary ext2 ${rootfsb_start} ${rootfsb_end}
if [ ${swap_part_size} -eq 0 ]; then
    parted -s ${sdimg_path} -- unit s mkpart primary ext2 ${data_start} ${data_end}
else
    parted -s ${sdimg_path} -- unit s mkpart extended ${ext_start} 100%
    parted -s ${sdimg_path} -- unit s mkpart logical ext2 ${data_start} ${data_end}
    parted -s ${sdimg_path} -- unit s mkpart logical linux-swap ${swap_start} ${swap_end}
fi
parted ${sdimg_path} print

# Burn Partitions
dd if=${output_dir}/boot.vfat of=${sdimg_path} conv=notrunc seek=${boot_part_start} conv=sparse
dd if=${output_dir}/rootfs.ext4 of=${sdimg_path} conv=notrunc seek=${rootfsa_start} conv=sparse
dd if=${output_dir}/rootfs.ext4 of=${sdimg_path} conv=notrunc seek=${rootfsb_start} conv=sparse
dd if=${output_dir}/data.ext4 of=${sdimg_path} conv=notrunc seek=${data_start} conv=sparse

declare -a mappings

add_partition_mappings() {
    if [[ -n "$1" ]]; then
        mapfile -t mappings < <( sudo -S kpartx -v -a $1 | grep 'loop' | cut -d' ' -f3 )
        [[ ${#mappings[@]} -eq 0 ]] && \
            { echo "Error: partition mappings failed. Aborting."; exit 1; } || \
                { echo "Mapped ${#mappings[@]} partition(s)."; }
    else
        echo "Error: no device passed. Aborting."
        exit 1
    fi

    sudo -S partprobe /dev/${mappings[0]%p*}
}

detach_mappings() {
    if [[ -z "$1" ]]; then
        echo "Error: no device passed. Aborting."
        exit 1
    fi
        
    for mapping in ${mappings[@]}
    do
        map_dev=/dev/mapper/"$mapping"
        is_mounted=`grep ${map_dev} /proc/self/mounts | wc -l`
        if [ ${is_mounted} -ne 0 ]; then
            echo "Unmounting detected mounted mapping: $mapping"
            sudo -S umount -l $map_dev
        fi
    done

    mapper=${mappings[0]%p*}
    echo "Detach mappings: /dev/$mapper"
    sudo -S kpartx -d /dev/$mapper &
    sudo -S losetup -d /dev/$mapper &
    wait
    sudo -S kpartx -d $1
}

pc_ubuntu_cleanup() {
    #
    # Mount the rootfs and boot partitions and install grub
    #
    MNT=${output_dir}/mnt-output
    mkdir ${MNT}

    sudo -S mount /dev/mapper/${mappings[1]} ${MNT}
    sudo -S mount /dev/mapper/${mappings[0]} ${MNT}/boot/grub
    for i in /dev /dev/pts /proc /sys /run; do
        sudo mount -B $i ${MNT}/$i
    done

    set -x
    sudo chroot ${MNT} grub-install --target=i386-pc \
         --modules "boot linux ext2 fat serial part_msdos part_gpt normal \
			iso9660 configfile search loadenv test cat echo \
			gcry_sha256 halt hashsum loadenv reboot biosdisk \
			serial terminal" \
         /dev/${mappings[0]%p*}
    set +x

    for i in /dev/pts /dev /proc /sys /run; do
        sudo umount ${MNT}/$i
    done
    sudo -S umount ${MNT}/boot/grub
    sudo -S umount ${MNT}
}

add_partition_mappings ${sdimg_path}
if [ ${swap_part_size} -ne 0 ]; then
    sudo mkswap /dev/mapper/${mappings[5]}
fi

# Platform specific cleanup
case "${mender_platform}" in
    "rpi-ubuntu" ) ;;
    "pc-ubuntu"  ) pc_ubuntu_cleanup;;
esac

detach_mappings ${sdimg_path}

#pigz -f -9 -n ${sdimg_path}
