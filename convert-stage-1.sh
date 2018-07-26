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

set -e

application_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
output_dir=${application_dir}/output

# Takes following arguments
#
#  $1 - path to src image
#  $2 - sector start (in 512 blocks)
#  $3 - size (in 512 blocks)
#  $4 - output filename
extract_file_from_image() {
    local cmd="dd if=$1 of=${output_dir}/$4 skip=$2 bs=512 count=$3 status=progress conv=sparse"

    echo "Running command:"
    echo "    ${cmd}"
    $(${cmd})
}

echo "Running: $(basename $0)"

if [ -z "$1" ]; then
    echo "usage:"
    echo "    $0 < image to convert >"
    exit 1
fi

image_to_convert=$1

image_boot_part=$(fdisk -l ${image_to_convert} | grep FAT32 || true)

rm -rf ${output_dir}
mkdir ${output_dir}

echo "${image_to_convert}"
fdisk -l ${image_to_convert}

if [ -n "${image_boot_part}" ]; then
    echo "Found a boot partition"
    boot_part_start=$(echo ${image_boot_part} | awk '{print $2}')
    boot_part_end=$(echo ${image_boot_part} | awk '{print $3}')
    boot_part_size=$(echo ${image_boot_part} | awk '{print $4}')

    echo "boot_part_start=${boot_part_start}" >> ${output_dir}/boot-part-env
    echo "boot_part_end=${boot_part_end}" >> ${output_dir}/boot-part-env
    echo "boot_part_size=${boot_part_size}" >> ${output_dir}/boot-part-env

    echo "Extracting boot partition to ${output_dir}/boot.vfat"
    extract_file_from_image \
        ${image_to_convert} \
        ${boot_part_start} \
        ${boot_part_size} \
        "boot.vfat"
fi

image_rootfs_part=$(fdisk -l ${image_to_convert} | grep 'Linux$' | tr -d '*')

if [ -n "${image_rootfs_part}" ]; then
    rootfs_part_start=$(echo ${image_rootfs_part} | awk '{print $2}')
    rootfs_part_end=$(echo ${image_rootfs_part} | awk '{print $3}')
    rootfs_part_size=$(echo ${image_rootfs_part} | awk '{print $4}')

    echo "Extracting root file-system partition to ${output_dir}/rootfs.img"
    extract_file_from_image \
        ${image_to_convert} \
        ${rootfs_part_start} \
        ${rootfs_part_size} \
        "rootfs.img"
fi

mkdir -p ${output_dir}/rootfs
sudo mount -o loop ${output_dir}/rootfs.img ${output_dir}/rootfs
