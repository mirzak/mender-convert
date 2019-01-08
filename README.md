Mender Image Conversion Tool - Ubuntu Edition
=============================================

Mender is an open source over-the-air (OTA) software updater for embedded Linux
devices. Mender comprises a client running at the embedded device, as well as
a server that manages deployments across many devices.

This repository contains the the Mender Image Conversion tool which is able to
convert pre-built disk images in to a Mender compatible format containing all
binaries necessary to run the Mender software updater.

We have initially targeted Ubuntu on an x86-64 PC host for this
version of the tools. This tool can certainly be extended to support
additional image formats and contributions are welcome.

![Mender logo](https://mender.io/user/pages/05.resources/06.digital-assets/logo.png)

## Summary

The functionality of this tools, in brief, is as follows:

- The input is a raw image of an Ubuntu root filesystem created with
  the e2image utility.
- This image is copied to a temporary directory. Note that this
  requires more disk space on your build system but has the advantage
  that the input image is unmodified.
- The file-system image is mount over the loopback interface to be
  able to manipulate its content.
- The Mender client binaries and configuration files are installed.
- The updated root filesystem is packaged into the following:
    - `sdimg` file. This is a single binary containing all the
      partitions required for a full running system.
    - `mender` artifact, that is the input file to the Mender client
      or uploaded to the Mender server for deployment.
- The `sdimg` file can be written to the target storage media using
  the `dd` command.

## Creating input images

The system containing the master root filesystem should be booted
using a Live CD. Testing has been done using the Ubuntu install disk
using the Live CD mode.

Once the system for which you wish to create an image is booted you
will need to review the block devices attached to the system to determine
which one is the appropriate device. Note that the Ubuntu Install Live
mode is not writable, even if deployed to a USB key so you will likely
need a separate USB storage device to contain the output image. You can
use a standard USB key for this purpose but the read and write speeds
are a limiting factor; we recommend using a standard USB hard drive
formatted as EXT4.

Ensure that the file system being imaged is not mounted and run a command
such as the following:

# e2image -rap <dev-node-to-root-filesystem> <full-path-to-image-file>

dev-node-to-root-filesystem will generally be of the form /dev/sda1
where "sda" refers to the first block device and "1" refers to the
first partition on the device.

full-path-to-image-file should include the directory of your external
storage media to ensure that is where the image is place.

WARNING: As with all partition manipulation tools, using this command
incorrectly can result in lost data. Please review your command line
options carefully to ensure proper usage.

## Getting started with conversion of images.

Install dependencies on your build system.  Note, these instructions
are based on Debian derivatives build should be applicable on any
major Linux distribution.

	$ sudo apt-get install mtools parted mtd-utils e2fsprogs u-boot-tools pigz

## Stages of the Mender Conversion Tool

The Mender conversion tool is provided as a set of shell scripts that are run
in stages.  You should not need to modify them, except for convert-stage-3.sh,
but a brief understanding of their functionality is included here for reference:

- mender-conversion-tool

This is the primary entry script which is responsible for parsing command line
options and invoking the sub-scripts in the order required. This is the script
you will invoke to start a conversion:

```
$ mender-conversion-tool -h
Usage: mender-conversion-tool options (:hc:d:i:m:n:o:s:t:R:)
    -c - Server certificate (Only for Mender Production setup)
    -D - Data partition size in MB
    -d - Device type (/data/mender/device_type)
    -i - Path to image to convert
    -m - Path to Mender client binary
    -n - Mender artifact_name (/etc/mender/artifact_name)
    -o - Demo mode, takes demo server IP address as an argument
    -s - Server URL (Only for Mender Production setup)
    -S - Swap partition size in MB
    -t - File containing Hosted Mender token (Hosted Mender mode)
    -R - Root file-system partition size in MB
    -p - Platform (currently either rpi-ubuntu or pc-ubuntu)
    -h - Prints this text
```

- convert-stage-1.sh

Extracts file-system images and information from the input image. This
script also mounts the root file-system from the input image using
`mount -loop`.

- convert-stage-2.sh

Installs all Mender client binaries and configuration files on the
mounted root file-system

- convert-stage-3.sh

Customization script. If your use case requires specific adjustments
to the target partitions, this script can be modified to meet thos
requirements.

- convert-stage-4.sh

This script contains changes specific to a particular platform
specific changes.

- convert-stage-99.sh

This is the final stage which brings all the components together into
an installable image.  The output is:

- Root file-system image (with all modifications)
- Data file-system image (pre-populated with files for Mender client)
- Complete disk image containing an appropriate partition table and
  the appropriate file system images
- Mender artifacts that can be uploaded to the Mender management
  server to deploy updates OTA

## Configuring the Mender server to be used.

The majority of this tools configuration is explained by the help text
shown above, or by invoking the script with the `-h`
option. Configuration of the Mender server requires more
detail. Mender supports three different server setups:

- Mender Demo - https://docs.mender.io/development/getting-started/create-a-test-environment
- Mender Production - https://docs.mender.io/development/administration/production-installation
- Hosted Mender - https://hosted.mender.io

The Mender client configuration is different for each type.

### Mender Demo Server

If you are using the Mender demo server and the meta-mender-demo layer, you only need to provide the IP address of your server using the `-o` option.

```
mender-conversion-tool <options> -o 192.168.0.128
```

### Mender Demo Server

If you are using the Mender production server without the
meta-mender-demo layer, you need to provide the URL address of your
server using the `-s` option. If you are not using a CA-signed
certificate on your server, you should provide the certificate here
using the `c` option to ensure that the Mender client can properly
connect using TLS.

```
mender-conversion-tool <options> -c server.crt -s https://custom.mender.com
```

### Mender Demo Server

If you are using Hosted Mender (without the meta-mender-demo layer,
you only need to provide your tenant token. This information is
available from the web interface of Hosted Mender here:

* https://hosted.mender.io/ui/#/settings/my-organization

This token should be stored in a text file on your build system and the
path to that file provided using the `-t` option

```
mender-conversion-tool <options> -t mender.token
```

## Output

All temporary files that are created during the conversion and the final output
images are stored in the `output` directory in this repository.

The files of interest after a conversion are in the `output` directory
with a `.mender` and a `.sdimg` extension.

## Provisioning a system with output images

The system on which to install the output image should be booted using
a Live CD. Testing has been done using the Ubuntu install disk using
the Live CD mode. You will need to copy the `.sdimg` output file to a
USB disk to be able to access it from the target system.

Once the system for which you wish to create an image is booted you
will need to review the block devices attached to the system to determine
which one is the appropriate device.

Ensure that the block device being provisioned has no partitions
mounted.  Then you runa command such as the following:

# dd if=<full-path-to-image-file> of=<dev-node-to-root-filesystem>

dev-node-to-root-filesystem will generally be of the form /dev/sda
where "sda" refers to a block device. Note that unlike the above case,
we are not providing a partition number with this command as it will be
using the entire device.

WARNING: As with all partition manipulation tools, using this command
incorrectly can result in lost data. Please review your command line
options carefully to ensure proper usage.

## Contributing

We welcome and ask for your contribution. If you would like to contribute to
Mender, please read our guide on how to best get started [contributing code or
documentation](https://github.com/mendersoftware/mender/blob/master/CONTRIBUTING.md).

## License

Mender is licensed under the Apache License, Version 2.0. See
[LICENSE](https://github.com/mendersoftware/artifacts/blob/master/LICENSE) for the
full license text.

## Security disclosure

We take security very seriously. If you come across any issue regarding
security, please disclose the information by sending an email to
[security@mender.io](security@mender.io). Please do not create a new public
issue. We thank you in advance for your cooperation.

## Connect with us

* Join our [Google
  group](https://groups.google.com/a/lists.mender.io/forum/#!forum/mender)
* Follow us on [Twitter](https://twitter.com/mender_io?target=_blank). Please
  feel free to tweet us questions.
* Fork us on [Github](https://github.com/mendersoftware)
* Email us at [contact@mender.io](mailto:contact@mender.io)
