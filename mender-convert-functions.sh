#!/bin/bash

# Partition alignment value in bytes (4MB).
declare -i partition_alignment="4194304"

declare -i image_overhead="${partition_alignment}"

# Number of required heads in a final image.
declare -i -r heads=255
# Number of required sectors in a final image.
declare -i -r sectors=63

declare -a mender_disk_partitions=("boot" "primary" "secondary" "data")
declare -a raw_disk_partitions=("boot" "rootfs")

tool_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
files_dir=${tool_dir}/files
output_dir=${tool_dir}/output
build_log=${output_dir}/build.log

embedded_base_dir=$output_dir/embedded
sdimg_base_dir=$output_dir/sdimg

embedded_boot_dir=$embedded_base_dir/boot
embedded_rootfs_dir=$embedded_base_dir/rootfs
sdimg_boot_dir=$sdimg_base_dir/boot
sdimg_primary_dir=$sdimg_base_dir/primary
sdimg_secondary_dir=$sdimg_base_dir/secondary
sdimg_data_dir=$sdimg_base_dir/data

logsetup() {
  [ ! -f $build_log ] && { touch $build_log; }
  echo -n "" > $build_log
  exec > >(tee -a $build_log)
  exec 2>&1
}

log() {
  echo -e "$*"
}

# Takes following arguments:
#
#  $1 -relative file path
get_path() {
  echo "$(cd "$(dirname "$1")"; pwd)/$(basename "$1")"
}

get_part_number_from_device() {
  case "$1" in
    /dev/*[0-9]p[1-9])
      echo ${1##*[0-9]p}
      ;;
    /dev/[sh]d[a-z][1-9])
      echo ${1##*d[a-z]}
      ;;
    ubi[0-9]_[0-9])
      echo ${1##*[0-9]_}
      ;;
    [a-z]*\.sdimg[1-9])
      echo ${1##*\.sdimg}
      ;;
    /dev/mapper/*[0-9]p[1-9])
      echo ${1##*[0-9]p}
      ;;
    *)
      log "Could not determine partition number from $1"
      exit 1
      ;;
  esac
}

# Takes following arguments:
#
#  $1 - raw disk image
#  $2 - boot partition start offset (in sectors)
#  $3 - boot partition size (in sectors)
create_single_disk_partition_table() {
  local device=$1
  local bootstart=$2
  local stopsector=$(( $3 - 1 ))

  sed -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' << EOF | sudo fdisk $device &> /dev/null
	d # delete partition
	n # new partition
	p # primary partition
	1 # partion number 1
	${bootstart}
	+${stopsector}
	a # set boot flag
	w # write the partition table
	q # and we're done
EOF
}

# Takes following arguments:
#
#  $1 - raw disk image
#  $2 - root filesystem partition start offset (in sectors)
#  $3 - root filesystem partition size (in sectors)
create_double_disk_partition_table() {
  local device=$1
  local rootfsstart=$2
  local rootfsstop=$(( $3 - 1 ))

  sed -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' << EOF | sudo fdisk $device &> /dev/null
	d # delete partition
	2
	n
	p
	2
	${rootfsstart}
	+${rootfsstop}
	w # write the partition table
	q # and we're done
EOF
}

# Takes following arguments:
#
#  $1 - raw_disk image path
#
# Calculates following values:
#
#  $2 - number of partitions
#  $3 - size of the sector (in bytes)
#  $4 - boot partition start offset (in sectors)
#  $5 - boot partition size (in sectors)
#  $6 - root filesystem partition start offset (in sectors)
#  $7 - root filesystem partition size (in sectors)
#  $8 - boot flag
#  $9 - id (type) of the second partition (root)
get_image_info() {
  local limage=$1
  local rvar_count=$2
  local rvar_sectorsize=$3
  local rvar_bootstart=$4
  local rvar_bootsize=$5
  local rvar_rootfsstart=$6
  local rvar_rootfssize=$7
  local rvar_bootflag=$8
  local rvar_rootid=$9

  declare -A parts
  local lcount=0
  #         NR  partition number
  #      START  start of the partition in sectors
  #        END  end of the partition in sectors
  #    SECTORS  number of sectors
  #       SIZE  human readable size
  #       NAME  partition name
  #       UUID  partition UUID
  #       TYPE  partition type (a string, a UUID, or hex)
  #      FLAGS  partition flags
  #     SCHEME  partition table type (dos, gpt, ...)
  for part in $(partx -o NR -g -r ${limage}); do
      parts[$part,"START"]=$(partx -o START -g -r --nr $part ${limage})
      parts[$part,"END"]=$(partx -o END -g -r --nr $part ${limage})
      parts[$part,"SECTORS"]=$(partx -o SECTORS -g -r --nr $part ${limage})
      parts[$part,"NAME"]=$(partx -o NAME -g -r --nr $part ${limage})
      parts[$part,"UUID"]=$(partx -o UUID -g -r --nr $part ${limage})
      parts[$part,"TYPE"]=$(partx -o TYPE -g -r --nr $part ${limage})
      parts[$part,"FLAGS"]=$(partx -o FLAGS -g -r --nr $part ${limage})
      parts[$part,"SCHEME"]=$(partx -o SCHEME -g -r --nr $part ${limage})
      ((++lcount))
  done

  local lfdisk="$(fdisk -u -l ${limage})"
  local lsectorsize=($(echo "${lfdisk}" | grep '^Sector' | cut -d' ' -f4))

  eval $rvar_count="'$lcount'"
  eval $rvar_sectorsize="'$lsectorsize'"
  eval $rvar_bootstart="'${parts[1,"START"]}'"
  eval $rvar_bootsize="'${parts[1,"SECTORS"]}'"
  eval $rvar_rootfsstart="'${parts[2,"START"]}'"
  eval $rvar_rootfssize="'${parts[2,"SECTORS"]}'"
  eval $rvar_rootid="'${parts[2,"TYPE"]}'"

  [[ $lcount -gt 2 ]] && \
      { log "Unsupported type of source image. Aborting."; return 1; } || \
      { return 0; }
}

# Takes following arguments:
#
#  $1 - raw disk image path
#
# Calculates following values:
#
#  $2 - number of partitions
#  $3 - size of the sector (in bytes)
#  $4 - rootfs A partition start offset (in sectors)
#  $5 - rootfs A partition size (in sectors)
#  $6 - rootfs B partition start offset (in sectors)
#  $7 - rootfs B partition size (in sectors)
get_mender_disk_info() {
  local limage=$1
  local rvar_count=$2
  local rvar_sectorsize=$3
  local rvar_rootfs_a_start=$4
  local rvar_rootfs_a_size=$5
  local rvar_rootfs_b_start=$6
  local rvar_rootfs_b_size=$7

  local lsubname=${limage:0:8}
  local lfdisk="$(fdisk -u -l ${limage})"

  local lparts=($(echo "${lfdisk}" | grep "^${lsubname}" | cut -d' ' -f1))
  local lcount=${#lparts[@]}

  if [[ $lcount -ne 4 ]]; then
    log "Error: invalid Mender disk image. Aborting."
    return 1
  else
    local lsectorsize=($(echo "${lfdisk}" | grep '^Sector' | cut -d' ' -f4))

    local lrootfs_a_info="$(echo "${lfdisk}" | grep "^${lparts[1]}")"
    local lrootfs_b_info="$(echo "${lfdisk}" | grep "^${lparts[2]}")"

    idx_start=2
    idx_size=4

    local lrootfs_a_start=($(echo "${lrootfs_a_info}" | tr -s ' ' | cut -d' ' -f${idx_start}))
    local lrootfs_a_size=($(echo "${lrootfs_a_info}" | tr -s ' ' | cut -d' ' -f${idx_size}))
    local lrootfs_b_start=($(echo "${lrootfs_b_info}" | tr -s ' ' | cut -d' ' -f${idx_start}))
    local lrootfs_b_size=($(echo "${lrootfs_b_info}" | tr -s ' ' | cut -d' ' -f${idx_size}))

    eval $rvar_count="'$lcount'"
    eval $rvar_sectorsize="'$lsectorsize'"
    eval $rvar_rootfs_a_start="'$lrootfs_a_start'"
    eval $rvar_rootfs_a_size="'$lrootfs_a_size'"
    eval $rvar_rootfs_b_start="'$lrootfs_b_start'"
    eval $rvar_rootfs_b_size="'$lrootfs_b_size'"

    return 0
  fi
}

# Takes following arguments:
#
#  $1 - size variable to be aligned in sectors
#  $2 - size of the sector
#
align_partition_size() {
  # Final size is aligned with reference to 'partition_alignment' variable.
  local rvar_size=$1
  local -n ref=$1

  local size_in_bytes=$(( $ref * $2 ))
  local reminder=$(( ${size_in_bytes} % ${partition_alignment} ))

  if [ $reminder -ne 0 ]; then
    size_in_bytes=$(( $size_in_bytes - $reminder + ${partition_alignment} ))
  fi

  local lsize=$(( $size_in_bytes / $2 ))

  eval $rvar_size="'$lsize'"
}

# Takes following arguments:
#
#  $1 - raw_disk image
#
# Returns:
#
#  $2 - boot partition start offset (in sectors)
#  $3 - boot partition size (in sectors)
#  $4 - root filesystem start offset (in sectors)
#  $5 - root filesystem partition size (in sectors)
#  $6 - sector size (in bytes)
#  $7 - number of detected partitions
#  $8 - id (type) of the second partition (root)
analyse_raw_disk_image() {
  local image=$1
  local count=
  local sectorsize=
  local bootstart=
  local bootsize=
  local rootfsstart=
  local rootfssize=
  local rootid=
  local bootflag=

  local rvar_bootstart=$2
  local rvar_bootsize=$3
  local rvar_rootfsstart=$4
  local rvar_rootfssize=$5
  local rvar_sectorsize=$6
  local rvar_partitions=$7
  local rvar_rootfsid=$8

  get_image_info $image count sectorsize bootstart bootsize rootfsstart \
                 rootfssize bootflag rootid

  [[ $? -ne 0 ]] && \
      { log "Error: invalid/unsupported raw disk image. Aborting."; exit 1; }

  # Hackish way of saying that we only found one partition and we call it
  # "boot part" but lets assign the same values to "rootfs part".
  #
  # get_image_info needs to be smarter and should return an array with part
  # information. It should be a higher level decision what the parts actually
  # are, and if get_image_info is able to provide this we can simply drop
  # this function and call get_image_info directly.
  if [[ $count -eq 1 ]]; then
    rootfssize=$bootsize
    rootfsstart=$bootstart
  fi

  eval $rvar_bootstart="'$bootstart'"
  eval $rvar_bootsize="'$bootsize'"
  eval $rvar_rootfsstart="'$rootfsstart'"
  eval $rvar_rootfssize="'$rootfssize'"
  eval $rvar_sectorsize="'$sectorsize'"
  eval $rvar_partitions="'$count'"
  eval $rvar_rootfsid="'$rootid'"
}

# Takes following arguments:
#
#  $1 - boot partition start offset (in sectors)
#  $2 - boot partition size (in sectors)
#  $3 - root filesystem partition size (in sectors)
#  $4 - data partition size (in MB)
#  $5 - sector size (in bytes)
#
#  Returns:
#
#  $6 - aligned data partition size (in sectors)
#  $7 - final .sdimg file size (in bytes)
calculate_mender_disk_size() {
  local rvar_datasize=$6
  local rvar_sdimgsize=$7

  local datasize=$(( ($4 * 1024 * 1024) / $5 ))

  align_partition_size datasize $5

  local sdimgsize=$(( ($1 + $2 + 2 * ${3} +  $datasize) * $5 ))

  eval $rvar_datasize="'$datasize'"
  eval $rvar_sdimgsize="'$sdimgsize'"
}

# Takes following arguments:
#  $1 - aligned root filesystem partition size (in sectors)
#  $2 - aligned data partition size (in sectors)
#  $3 - aligned swap partition size (in sectors)
#  $4 - sector size (in bytes)
#
#  Returns:
#  $5 - final LVM volume group size (in bytes)
calculate_mender_lvm_vg_size() {
  local rvar_lvm_lg_size=$5

  # One extra block for LVM overhead
  local lvm_lg_size=$(( ((2 * $1) + $2 + $3) * $4 + $partition_alignment ))
  eval $rvar_lvm_lg_size="'$lvm_lg_size'"
}

# Takes following arguments:
#
#  $1 - raw disk image
unmount_partitions() {
  log "Check if device is mounted..."
  is_mounted=`grep ${1} /proc/self/mounts | wc -l`
  if [ ${is_mounted} -ne 0 ]; then
    sudo umount ${1}?*
  fi
}

# Takes following arguments:
#
#  $1 - raw disk image path
#  $2 - raw disk image size
create_mender_disk() {
  local lfile=$1
  local lsize=$2

  log "\tGenerating a blank image..."

  # Generates a sparse image
  dd if=/dev/zero of=${lfile} seek=${lsize} bs=1 count=0 >> "$build_log" 2>&1
}

# Takes following arguments:
#
#  $1 - raw disk image path
#  $2 - raw disk image size
#  $3 - boot partition start offset
#  $4 - boot partition size
#  $5 - root file-system partition size
#  $6 - data partition size
#  $7 - sector size
format_mender_disk() {
  local lfile=$1
  local lsize=$2

  log "\tGenerating MBR partition table image..."

  cylinders=$(( ${lsize} / ${heads} / ${sectors} / ${7} ))
  rootfs_size=$(( $5 - 1 ))
  pboot_offset=$(( ${4} - 1 ))
  primary_start=$(( ${3} + ${pboot_offset} + 1 ))
  secondary_start=$(( ${primary_start} + ${rootfs_size} + 1 ))
  data_start=$(( ${secondary_start} + ${rootfs_size} + 1 ))
  data_offset=$(( ${6} - 1 ))

  sed -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' << EOF | sudo fdisk ${lfile} &> /dev/null
	o # clear the in memory partition table
	x
	h
	${heads}
	s
	${sectors}
	c
	${cylinders}
	r
	n # new partition
	p # primary partition
	1 # partition number 1
	${3}  # default - start at beginning of disk
	+${pboot_offset} # 16 MB boot parttion
	t
	c
	a
	n # new partition
	p # primary partition
	2 # partion number 2
	${primary_start}	# start immediately after preceding partition
	+${rootfs_size}
	n # new partition
	p # primary partition
	3 # partion number 3
	${secondary_start}	# start immediately after preceding partition
	+${rootfs_size}
	n # new partition
	p # primary partition
	${data_start}		# start immediately after preceding partition
	+${data_offset}
	p # print the in-memory partition table
	w # write the partition table
	q # and we're done
EOF
  log "\tChanges in partition table applied."
}

# Takes following arguments:
#
#  $1 - raw disk file
#
# Returns:
#
#  $2 - number of detected partitions
verify_mender_disk() {
  local lfile=$1
  local rvar_no_of_parts=$2

  local limage=$(basename $lfile)
  local partitions=($(fdisk -l -u ${limage} | cut -d' ' -f1 | grep 'sdimg[1-9]\{1\}$'))

  local no_of_parts=${#partitions[@]}

  [[ $no_of_parts -eq 4 ]] || \
      { log "Error: incorrect number of partitions: $no_of_parts. Aborting."; return 1; }

  eval $rvar_no_of_parts=="'$no_of_parts='"

  return 0
}

# Takes following arguments:
#
#  $1 - raw disk image
#  $2 - partition mappings holder
create_device_maps() {
  local -n mappings=$2

  if [[ -n "$1" ]]; then
    mapfile -t mappings < <( sudo kpartx -v -a $1 | grep 'loop' | cut -d' ' -f3 )
    [[ ${#mappings[@]} -eq 0 ]] \
        && { log "Error: partition mappings failed. Aborting."; exit 1; }
  else
    log "Error: no device passed. Aborting."
    exit 1
  fi

  sudo partprobe /dev/${mappings[0]%p*}
}

# Takes following arguments:
#
#  $1 - partition mappings holder
detach_device_maps() {
  local mappings=($@)

  [ ${#mappings[@]} -eq 0 ] && { log "\tPartition mappings cleaned."; return; }

  local mapper=${mappings[0]%p*}

  for mapping in ${mappings[@]}
  do
    map_dev=/dev/mapper/"$mapping"
    is_mounted=`grep ${map_dev} /proc/self/mounts | wc -l`
    if [ ${is_mounted} -ne 0 ]; then
      sudo umount -l $map_dev
    fi
  done

  sudo kpartx -d /dev/$mapper &
  sudo losetup -d /dev/$mapper &
  wait && sync
}

make_mender_lvm_filesystem() {
  log "\tWriting file-system part..."
  dd if=${output_dir}/rootfs.img of=/dev/mender/rootfsa conv=sparse >> "$build_log" 2>&1
  log "\tWriting data part..."
  dd if=${output_dir}/data.img of=/dev/mender/data conv=sparse >> "$build_log" 2>&1
}

# Takes following arguments:
#
#  $1 - partition mappings holder
make_mender_lvm_disk() {
  local mappings=($@)

  for mapping in ${mappings[@]}
  do
    map_dev=/dev/mapper/"$mapping"
    part_no=$(get_part_number_from_device $map_dev)

    if [[ part_no -eq 1 ]]; then
      log "\tWriting boot part..."
      dd if=${output_dir}/boot.img of=$map_dev conv=sparse >> "$build_log" 2>&1
    elif [[ part_no -eq 2 ]]; then
      log "\tWriting LVM..."
      dd if=${output_dir}/vg.img of=$map_dev conv=sparse >> "$build_log" 2>&1
    fi
  done
}

# Takes following arguments:
#
#  $1 - partition mappings holder
make_mender_disk_filesystem() {
  local mappings=($@)

  for mapping in ${mappings[@]}
  do
    map_dev=/dev/mapper/"$mapping"
    part_no=$(get_part_number_from_device $map_dev)

    label=${mender_disk_partitions[${part_no} - 1]}

    if [[ part_no -eq 1 ]]; then
      log "\tWriting boot part..."
      dd if=${output_dir}/boot.img of=$map_dev conv=sparse >> "$build_log" 2>&1
    elif [[ part_no -eq 2 ]]; then
      log "\tWriting file-system part..."
      dd if=${output_dir}/rootfs.img of=$map_dev conv=sparse >> "$build_log" 2>&1
    elif [[ part_no -eq 4 ]]; then
      log "\tWriting data part..."
      dd if=${output_dir}/data.img of=$map_dev conv=sparse >> "$build_log" 2>&1
    fi
  done
}

# Takes following arguments:
#
#  $1 - partition mappings holder
mount_raw_disk() {
  local mappings=($@)

  if [ ${#mappings[@]} -eq 1 ]; then
    local path=$embedded_rootfs_dir
    mkdir -p $path
    sudo mount /dev/mapper/"${mappings[0]}" $path
    return
  fi

  for mapping in ${mappings[@]}
  do
    local part_no=${mapping#*p*p}
    local path=$embedded_base_dir/${raw_disk_partitions[${part_no} - 1]}
    mkdir -p $path
    sudo mount /dev/mapper/"${mapping}" $path 2>&1 >/dev/null
  done
}

# Takes following arguments:
#
#  $1 - partition mappings holder
mount_mender_disk() {
  local mappings=($@)

  for mapping in ${mappings[@]}
  do
    local part_no=${mapping#*p*p}
    local path=$sdimg_base_dir/${mender_disk_partitions[${part_no} - 1]}
    mkdir -p $path
    sudo mount /dev/mapper/"${mapping}" $path 2>&1 >/dev/null
  done
}

# Takes following arguments
#
#  $1 - path to source raw disk image
#  $2 - sector start (in 512 blocks)
#  $3 - size (in 512 blocks)

extract_file_from_image() {
  local cmd="dd if=$1 of=${output_dir}/$4 skip=$2 bs=512 count=$3 conv=sparse"
  $(${cmd} >> "$build_log" 2>&1)
}

extract_root_from_lvm() {
    local image=$1
    local target=$2

    local available_loop=$(losetup -f)

    # Map LVM volume group to free loop device
    losetup ${available_loop} ${image} >> "$build_log" 2>&1

    # It seems that we can reach pvs output without our parts being registered.
    # losetup does not have a "wait" flag, waiting one seconds seems to cover it
    # for now.
    sleep 1

    # Find out the name of the LVM volume group
    vg_name=$(sudo pvs -t 2>/dev/null | grep ${available_loop} | awk '{print $2}')

    # Active it!
    sudo vgchange -a y ${vg_name} >> "$build_log" 2>&1

    local cmd="dd if=/dev/${vg_name}/root of=${output_dir}/${target} conv=sparse"
    $(${cmd} >> "$build_log" 2>&1)

    sudo vgchange -a n ${vg_name} >> "$build_log" 2>&1
    sudo losetup -d ${available_loop} >> "$build_log" 2>&1
}

# Takes following arguments
#
#  $1 - device type
#  $2 - boot partition storage offset in bytes
#  $3 - boot partition size in sectors
#  $4 - rootfs partition size in sectors
#  $5 - sector size in bytes

create_test_config_file() {
  local device_type=$1
  local boot_offset=$2
  local boot_size_mb=$(( ((($3 * $5) / 1024) / 1024) ))
  local rootfs_size_mb=$(( ((($4 * $5) / 1024) / 1024) ))

  cp ${files_dir}/variables.template ${output_dir}/${device_type}_variables.cfg

  sed -i '/^MENDER_BOOT_PART_SIZE_MB/s/=.*$/="'${boot_size_mb}'"/' ${output_dir}/${device_type}_variables.cfg
  sed -i '/^MENDER_DEVICE_TYPE/s/=.*$/="'${device_type}'"/' ${output_dir}/${device_type}_variables.cfg
  sed -i '/^MENDER_UBOOT_ENV_STORAGE_DEVICE_OFFSET/s/=.*$/="'${boot_offset}'"/' ${output_dir}/${device_type}_variables.cfg
  sed -i '/^MENDER_CALC_ROOTFS_SIZE/s/=.*$/="'${rootfs_size_mb}'"/' ${output_dir}/${device_type}_variables.cfg
  sed -i '/^MENDER_MACHINE/s/=.*$/="'${device_type}'"/' ${output_dir}/${device_type}_variables.cfg
  sed -i '/^DEPLOY_DIR_IMAGE/s/=.*$/="'${output_dir//\//\\/}'"/' ${output_dir}/${device_type}_variables.cfg
}

# Takes following arguments
#
#  $1 - device type
#  $2 - parameter name to change
#  $3 - parameter value
update_test_config_file() {
  local device_type=$1

  [ ! -f "${output_dir}/${device_type}_variables.cfg" ] && \
      { log "Error: test configuration file '${device_type}_variables.cfg' not found. Aborting."; return 1; }

  shift

  while test ${#} -gt 0
  do
    case "$1" in
      "artifact-name")
        sed -i '/^MENDER_ARTIFACT_NAME/s/=.*$/="'${2}'"/' ${output_dir}/${device_type}_variables.cfg
        ;;
      "distro-feature")
        sed -i '/^DISTRO_FEATURES/s/=.*$/="'${2}'"/' ${output_dir}/${device_type}_variables.cfg
        ;;
      "mount-location")
        sed -i '/^MENDER_BOOT_PART_MOUNT_LOCATION/s/=.*$/="'${2}'"/' ${output_dir}/${device_type}_variables.cfg
        ;;
    esac
    shift 2
  done

  return 0
}
