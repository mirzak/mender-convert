#!/bin/sh

set -e

usage() {
  echo $*
  echo "$0 dev-node image-file"
  echo "Example: $0 /dev/sda1 foo.img"
  echo "Creates image-file from the partition pointed to by dev-node"
  exit 0
}

IMAGE_FILE="$2"
DEVICE_NODE="$1"

set -u

[ -z "${DEVICE_NODE}" ] && usage "A device node must be provided"
[ -z "${IMAGE_FILE}" ] && usage "An image file name must be provided"
[ ! -b "${DEVICE_NODE}" ] && usage "Error. ${DEVICE_NODE} is not a block device."
[ $(mount | grep ${DEVICE_NODE} | wc -l) -ne 0 ] && usage "Error. ${DEVICE_NODE} is mounted"
[ -e "${IMAGE_FILE}" ] && usage "Error. ${IMAGE_FILE} already exists. Exiting for safety."
    
echo "Creating image file ${IMAGE_FILE} from device ${DEVICE_NODE}"
e2image -ra -p "${DEVICE_NODE}" "${IMAGE_FILE}"
