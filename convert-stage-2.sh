#!/bin/bash

#    Copyright 2018 Northern.tech AS
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
output_dir=${MENDER_CONVERSION_OUTPUT_DIR:-${application_dir}}/output

meta_mender_revision="https://raw.githubusercontent.com/mendersoftware/meta-mender/sumo/"
mender_client_revision="https://raw.githubusercontent.com/mendersoftware/mender/1.5.x/"

show_help() {
    cat << EOF

Mender executables, service and configuration files installer.

Usage: $(basename $0) [options]

    Options: [acdmorstT]

        -a - Mender artifact info
        -t - Device type, e.g raspberrypi3
        -d - Target data directory
        -r - Target rootfs directory
        -o - Mender Demo server IP
        -s - Mender Production URL
        -c - Mender Production Certificate
        -m - Mender client binary file
        -T - Hosted Mender token

    Examples:

        $(basename $0) -r rootfs-dir -d data-dir -m mender
                -a mender-image-1.4.0 -t beaglebone -s 192.168.10.2

EOF
    exit 1
}

tenant_token="dummy"
server_url="https://docker.mender.io"

mender_update_poll_interval_seconds="1800"
mender_inventory_poll_interval_seconds="1800"
mender_retry_poll_interval_seconds="300"

create_client_files() {
    cat <<- EOF > $output_dir/mender.service
[Unit]
Description=Mender OTA update service
After=systemd-resolved.service

[Service]
Type=idle
User=root
Group=root
ExecStartPre=/bin/mkdir -p -m 0700 /data/mender
ExecStartPre=/bin/ln -sf /etc/mender/tenant.conf /var/lib/mender/authtentoken
ExecStart=/usr/bin/mender -daemon
Restart=on-abort

[Install]
WantedBy=multi-user.target
EOF

    cat <<- EOF > $output_dir/mender.conf
{
    "InventoryPollIntervalSeconds": ${mender_inventory_poll_interval_seconds},
    "RetryPollIntervalSeconds": ${mender_retry_poll_interval_seconds},
    "UpdatePollIntervalSeconds": ${mender_update_poll_interval_seconds},
    "RootfsPartA": "/dev/mmcblk0p2",
    "RootfsPartB": "/dev/mmcblk0p3",
    "ServerCertificate": "/etc/mender/server.crt",
    "ServerURL": "${server_url}",
    "TenantToken": "${tenant_token}"
}
EOF

     cat <<- EOF > $output_dir/artifact_info
artifact_name=${artifact_name}
EOF

    # Version file
    echo -n "2" > $output_dir/version

    cat <<- EOF > $output_dir/device_type
device_type=${device_type}
EOF

    cat <<- EOF > $output_dir/fw_env.config
/dev/mmcblk0 0x400000 0x4000
/dev/mmcblk0 0x800000 0x4000
EOF
}

get_mender_files_from_upstream() {
    wget -O ${output_dir}/mender-device-identity \
        ${mender_client_revision}/support/mender-device-identity

    wget -O ${output_dir}/mender-inventory-hostinfo \
        ${mender_client_revision}/support/mender-inventory-hostinfo

    wget -O ${output_dir}/mender-inventory-network \
        ${mender_client_revision}/support/mender-inventory-network

    wget -O ${output_dir}/fw_printenv \
        ${meta_mender_revision}/meta-mender-core/recipes-bsp/grub/files/fw_printenv

    wget -O ${output_dir}/server.crt \
        ${meta_mender_revision}/meta-mender-demo/recipes-mender/mender/files/server.crt
}

install_files() {
    local local_rootfs_dir=$1
    local local_data_dir=$2

    # Prepare 'data' partition
    sudo install -d -m 755 ${local_data_dir}/mender
    sudo install -d -m 755 ${local_data_dir}/uboot

    sudo install -m 0644 ${output_dir}/device_type ${local_data_dir}/mender
    sudo install -m 0644 ${output_dir}/fw_env.config ${local_data_dir}/uboot

    sudo ln -sf /data/uboot/fw_env.config ${local_rootfs_dir}/etc/fw_env.config

    sudo install -d ${local_rootfs_dir}/data
    sudo install -d ${local_rootfs_dir}/uboot

    sudo install -d ${local_rootfs_dir}/usr/share/mender/identity
    sudo install -d ${local_rootfs_dir}/usr/share/mender/inventory
    sudo install -d ${local_rootfs_dir}/etc/mender
    sudo install -d ${local_rootfs_dir}/etc/mender/scripts

    sudo ln -sf /data/mender ${local_rootfs_dir}/var/lib/mender

    sudo install -m 0755 ${mender} ${local_rootfs_dir}/usr/bin/mender
    sudo install -m 0755 ${output_dir}/fw_printenv ${local_rootfs_dir}/sbin/fw_printenv
    sudo install -m 0755 ${output_dir}/fw_printenv ${local_rootfs_dir}/sbin/fw_setenv

    sudo install -t ${local_rootfs_dir}/usr/share/mender/identity -m 0755 \
        ${output_dir}/mender-device-identity

    sudo install -t ${local_rootfs_dir}/usr/share/mender/inventory -m 0755 \
        ${output_dir}/mender-inventory-network

    sudo install -t ${local_rootfs_dir}/usr/share/mender/inventory -m 0755 \
        ${output_dir}/mender-inventory-hostinfo

    sudo install -m 0644 ${output_dir}/mender.service ${local_rootfs_dir}/lib/systemd/system

    # Enable menderd service starting on boot.
    sudo ln -sf /lib/systemd/system/mender.service \
        ${local_rootfs_dir}/etc/systemd/system/multi-user.target.wants/mender.service

    sudo install -m 0644 ${output_dir}/mender.conf ${local_rootfs_dir}/etc/mender
    sudo install -m 0444 ${output_dir}/server.crt ${local_rootfs_dir}/etc/mender
    sudo install -m 0644 ${output_dir}/artifact_info ${local_rootfs_dir}/etc/mender
    sudo install -m 0644 ${output_dir}/version ${local_rootfs_dir}/etc/mender/scripts

    if [ -n "${mender_demo_ip}" ]; then
        echo "${mender_demo_ip} docker.mender.io s3.docker.mender.io" | sudo tee -a ${local_rootfs_dir}/etc/hosts
    fi

    if [ -n "${mender_production_cert}" ]; then
        sudo install -m 0444 ${mender_production_cert} ${local_rootfs_dir}/etc/mender
    fi
}

do_add_mender() {
    if [ -z "${rootfs_dir}" ]; then
        echo "Target root file-system not set. Aborting."
        show_help
    fi

    if [ -z "${data_dir}" ]; then
        echo "Data target path not set. Aborting."
        show_help
    fi

    if [ -z "${mender}" ]; then
        echo "Mender client binary not set. Aborting."
        show_help
    fi

    if [ -z "${device_type}" ]; then
        echo "Device device_type not set. Aborting."
        show_help
    fi

    if [ -z "${artifact_name}" ]; then
        echo "artifact_name info not set. Aborting."
        show_help
    fi

    if [ -z "${mender_production_url}" ] && [ -z "${mender_demo_ip}" ] && \
        [ -z "${mender_hosted_token}" ]; then
        echo "No server type specified"
        show_help
    fi

    if [ -n "${mender_production_url}" ] && [ -n "${mender_demo_ip}" ]; then
        echo "Incompatible server type choice"
        show_help
    fi

    # TODO: more error checking of server types
    if [ -n "${mender_hosted_token}" ]; then
        tenant_token=$(cat ${mender_hosted_token} | tr -d '\n')
        server_url="https://hosted.mender.io"
    fi

    if [ -n "${mender_production_url}" ]; then
        server_url=${mender_production_url}
    fi

    if [ -n "${mender_demo_ip}" ]; then
        mender_update_poll_interval_seconds="5"
        mender_inventory_poll_interval_seconds="5"
        mender_retry_poll_interval_seconds="30"
    fi

    get_mender_files_from_upstream

    # Create all necessary client's files.
    create_client_files

    # Create all required paths and install files.
    install_files ${rootfs_dir} ${data_dir}
}

echo "Running: $(basename $0)"

echo "args: $#"

while getopts ":ha:c:d:m:o:r:s:t:T:" arg; do
    case $arg in
    o)
        mender_demo_ip=${OPTARG}
        ;;
    c)
        mender_production_cert=${OPTARG}
        ;;
    s)
        mender_production_url=${OPTARG}
        ;;
    T)
        mender_hosted_token=${OPTARG}
        ;;
    r)
        rootfs_dir=${OPTARG}
        ;;
    d)
        data_dir=${OPTARG}
        ;;
    m)
        mender=${OPTARG}
        ;;
    t)
        device_type=${OPTARG}
        ;;
    a)
        artifact_name=${OPTARG}
        ;;
    h | *) # Display help.
        echo "unknown optargs ${arg}: ${OPTARG}"
        show_help
        ;;
    esac
done

do_add_mender
