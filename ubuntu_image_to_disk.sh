#!/bin/sh

set -e

usage() {
  echo $*
  echo "$0 image-file dev-node"
  echo "Example: $0 foo.img /dev/sda1"
  echo "Overwrites the partition pointed to by dev-node with the contents of image-file"
  exit 0
}

IMAGE_FILE="$1"
DEVICE_NODE="$2"

set -u

[ -z "${DEVICE_NODE}" ] && usage "A device node must be provided"
[ -z "${IMAGE_FILE}" ] && usage "An image file name must be provided"
[ ! -b "${DEVICE_NODE}" ] && usage "Error. ${DEVICE_NODE} is not a block device."
[ $(mount | grep ${DEVICE_NODE} | wc -l) -ne 0 ] && usage "Error. ${DEVICE_NODE} is mounted"
[ ! -f "${IMAGE_FILE}" ] && usage "Error. ${IMAGE_FILE} is not a regular file."
    
echo "Writing image file ${IMAGE_FILE} to device ${DEVICE_NODE}"
e2image -ra -p "${IMAGE_FILE}" "${DEVICE_NODE}"
