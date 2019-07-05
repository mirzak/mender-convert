#!/bin/bash

# Exit if any command exits with a non-zero exit status.
set -o errexit

root_dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )/../" && pwd )
if [ "${root_dir}" != "${PWD}" ]; then
    echo "You must execute $(basename $0) from the root directory: ${root_dir}"
    exit 1
fi

# Do not actually paste it here, this is just the default value that will
# end up in mender.conf if no token is specified using '--tenant-token'
tenant_token="Paste your Hosted Mender token here"
while (( "$#" )); do
  case "$1" in
    -t | --tenant-token)
      tenant_token="${2}"
      shift 2
      ;;
    *)
      echo "Sorry but the provided option is not supported: $1"
      echo "Usage:  $(basename $0) --tenant-token"
      exit 1
      ;;
  esac
done

mkdir -p rootfs_overlay_demo/etc/mender
cat <<- EOF > rootfs_overlay_demo/etc/mender/mender.conf
{
  "InventoryPollIntervalSeconds": 5,
  "RetryPollIntervalSeconds": 30,
  "ServerURL": "https://hosted.mender.io/",
  "TenantToken": "${tenant_token}",
  "UpdatePollIntervalSeconds": 5
}
EOF

echo "Configuration file written to: rootfs_overlay_demo/etc/mender"
