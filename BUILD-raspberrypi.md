Mender Image Conversion - Re-build binaries
===========================================

The following has been tested on a on a PC running Debian Stretch, but should
be applicable to most of the major Linux distributions.

This document will cover how to re-create the pre-built binaries for raspberrypi
that are part of this repository, that is:

```
$ ls -alh bin/raspberrypi/
total 7,5M
drwxr-xr-x 2 user user 4,0K 25 jul 22.26 .
drwxr-xr-x 3 user user 4,0K 25 jul 14.51 ..
-rw-r--r-- 1 user user  301 25 jul 14.51 boot.scr
-rwxr-xr-x 1 user user  31K 25 jul 15.06 fw_printenv
-rwxr-xr-x 1 user user 7,1M 25 jul 22.26 mender
-rw-r--r-- 1 user user 369K 25 jul 14.51 u-boot.bin
```

## boot.scr

The `boot.scr` file is a script that is loaded by the boot-loader (U-boot) and
which executes commands to make sure correct software is loaded. To re-create
it we start out with a plain-text file with the following content.

*boot.cmd*

    fdt addr ${fdt_addr} && fdt get value bootargs /chosen bootargs
    run mender_setup
    mmc dev ${mender_uboot_dev}
    load ${mender_uboot_root} ${kernel_addr_r} /boot/zImage
    bootz ${kernel_addr_r} - ${fdt_addr}
    run mender_try_to_recover

To convert it in to a format that is understood by the boot-loader (U-boot) we
must run this command:

    $ mkimage -A arm -T script -C none -n "Boot script" -d "boot.cmd" boot.scr

Above will create a `boot.scr` file at the location where it is executed.

**NOTE!** `mkimage` is part of the `uboot-tools` package but you should already
have this installed if you followed the instructions in the README.md.

## Mender

For this part you will need a cross-toolchain, install with:

    sudo apt-get install gcc-arm-linux-gnueabihf

Mender is written in [golang](https://golang.org/) and because of this we first
must setup an golang environment with a certain version.

    $ wget https://dl.google.com/go/go1.9.4.linux-amd64.tar.gz
    $ sudo tar -C /usr/local -xzf go1.9.4.linux-amd64.tar.gz
    $ export PATH=${PATH}:/usr/local/go/bin
    $ mkdir ${HOME}/golang
    $ export GOPATH=${HOME}/golang
    $ cd ${HOME}/golang

Make sure that golang works by running:

    $ go version
    go version go1.9.4 linux/amd64

Now that we have golang setup we can fetch Mender client source code

    $ go get github.com/mendersoftware/mender
    $ cd $GOPATH/src/github.com/mendersoftware/mender
    $ git checkout 1.5.0

And now we are ready to cross-compile the `mender` binary with:

    $ env CGO_ENABLED=1 \
      CC=arm-linux-gnueabihf-gcc \
      GOOS=linux \
      GOARCH=arm make build
    $ arm-linux-gnueabihf-strip mender

The `strip` command above will reduce the size of the binary by stripping away
symbols from the binary that are not needed on a production system.

The Mender binary is located at:

    $GOPATH/src/github.com/mendersoftware/mender/mender


## U-boot

For this part you will need a `cross-toolchain`, install with:

    sudo apt-get install gcc-arm-linux-gnueabihf

We need to fetch sources and setup build environment:

    $ git clone https://github.com/mirzak/u-boot-mender.git -b mender-rpi-2017.09
    $ cd u-boot-mender
    $ export ARCH=arm
    $ export CROSS_COMPILE=arm-linux-gnueabihf-

To compile the `u-boot.bin` file run:

    $ make rpi_3_32b_defconfig && make

The `u-boot.bin` can be located in the root directory of U-boot source code
(u-boot-mender), same location where you executed above commands.

To compile the `fw_printenv` file run:

    $ make envtools

It will be located at

    u-boot-mender/tools/env/fw_printenv

