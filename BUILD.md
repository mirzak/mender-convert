Tutorial how to convert Ubuntu images
=====================================

This document is specific to Ubuntu on generic 64-bit PCs.

Note that you do not actually have to do all this as there are already
pre-compiled binaries in the repository and the lengthy instructions below are
only on how to re-create the binaries. You can use the instructions that are in
the README.md if you simply want build images based on the pre-compiled binaries.

Though check at the end of this document on instructions for how to provision
device and deploying Mender updates.

What this tool does can be summarized with the following:

- Input is a raw image of an Ubuntu rootfilesystem created with the e2image utility.
- Mounts the file-system image over the loopback interface to be able to manipulate content.
- Install Mender client binaries and configuration files
- Platform specific adjustments
    - This is for customization by the end user, e.g prepare U-boot binary and other tools
- Package manipulated root file-systems and platform specific binaries. Output is:
    - `mender` artifact, that is the input file to the Mender client
    - `ext*` image containing the updated filesystem image
- The images created will then be installed on the target by scripting similar to the 
  ubuntu_image_to_disk.sh script.

## Creating input images

Provided here is a script called ubuntu_image_from_disk.sh that can be
used to create the initial image files. Note that this should be run
from a live Ubuntu install CD or USB running on the target system
containing the file system of interest. Note specifically that the
file system being imaged must not be mounted during this process

WARNING: As with all partition manipulation tools, using this script
incorrectly can result in lost data. Please review the script carefully
to ensure proper usage.

## Fetching sources and building

There are three different repositories that are needed:

- image-conversion-tool
- mender
- mender-artifact

For all build steps below, please create a fresh directory to build in and
set the UBUNTU_MENDER_DIR environment variable as follows:

    $ export UBUNTU_MENDER_DIR=<full-path-to-build-dir-here>
    $ cd ${UBUNTU_MENDER_DIR}

### Installing golang

Most build host distributions have golang support through their standard package
managers or some other mechanism. In particular, if you are using Ubuntu 16.04 (recommended)
there are several options detailed here: https://github.com/golang/go/wiki/Ubuntu

Note that we have tested the snap version of Golang as documented above.

If you would rather use a local installation directly from the Google upstream,
do the following:

    $ wget https://dl.google.com/go/go1.9.4.linux-amd64.tar.gz
    $ sudo tar -C /usr/local -xzf go1.9.4.linux-amd64.tar.gz
    $ export PATH=${PATH}:/usr/local/go/bin

Verify that it works by running:

    $ go version
    go version go1.9.4 linux/amd64

## Building the Mender client and artifact tool

Now that we have golang setup we can fetch and build the Mender client.

    $ export GOPATH=${UBUNTU_MENDER_DIR}/golang
    $ mkdir ${GOPATH}
    $ cd ${GOPATH}
    $ go get -d github.com/mendersoftware/mender
    $ cd ${GOPATH}/src/github.com/mendersoftware/mender
    $ git checkout 1.5.0
    $ make clean
    $ CC=gcc \
      GOOS=linux \
      GOARCH=amd64 make build
    $ strip mender

A pre-built 64-bit binary is provided in this repository under
bin/ubuntu/

We also need the mender-artifact tool to run on your build host. A
pre-built 64-bit binary is available in this repository under
bin/ubuntu/. Additionally, should you require it, instructions are
available for
[compiling it from source](https://docs.mender.io/1.5/artifacts/modifying-a-mender-artifact#compiling-mender-artifact).

## Running the image-conversion-tool.

    $ cd ${UBUNTU_MENDER_DIR}/image-conversion-tool
    $ ./convert-image.sh -d mr33 -n v1.0.0 \
      -i ${OPENWRT_MENDER_DIR}/LEDE-MR33/openwrt/bin/targets/ipq806x/generic/openwrt-ipq806x-meraki_mr33-squashfs-sysupgrade.bin \
      -m ${OPENWRT_MENDER_DIR}/golang/src/github.com/mendersoftware/mender/mender -t files/mender-token

Above should have produced:

    $ ls -alh output/mr33-v1.0.0.*
    -rw-r--r-- 1 mirzak mirzak 5.4M Jul 24 10:40 output/mr33-v1.0.0.mender
    -rw-r--r-- 1 mirzak mirzak  17M Jul 24 10:40 output/mr33-v1.0.0.ubi

Now it is time for us to provision the device with our custom software and we
will be using `mr33-v1.0.0.ubi` for this.

Next we need to put our device in "Firstboot - Temporary Install - RAM Boot" mode,
instructions can be found in this document, [Flashing Instructions for the MR33](https://drive.google.com/drive/folders/1jJa8LzYnY830v3nBZdOgAk0YQK6OdbSS).

Once the device is booted in RAM Boot mode it is time to transfer our `mr33-v1.0.0.ubi`
file to the device

    $ cd ${OPENWRT_MENDER_DIR}/image-conversion-tool
    $ scp output/mr33-v1.0.0.ubi root@192.168.1.69:/tmp

NOTE! Remember to replace IP address from above with the actual address.

Once the `mr33-v1.0.0.ubi` file has been transfered to the device we can execute
the following on the device:

    # sysupgrade -F /tmp/mr33-v1.0.0.ubi

Above command will reboot device and boot in to our customer firmware. That is it.

To perform an Mender update in stand-alone mode, we need to transfer the `mr33-v1.0.0.mender`
file to a system running our custom firmware.

    $ scp output/mr33-v1.0.0.mender root@192.168.1.69:/tmp

Once the file has been transfered we can run the following command on the device:

    # mender -rootfs /tmp/mr33-v1.0.0.mender

The device will reboot once the new artifacts is installed. When running in
standalone mode you must also "commit" the update once the device has started
with:

    # mender -commit

Otherwise Mender will roll-back on the next reboot. This is otherwise managed
by the Mender daemon when running in "managed" mode.
