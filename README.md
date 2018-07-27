Mender Image Conversion tool
============================

Mender is an open source over-the-air (OTA) software updater for embedded Linux
devices. Mender comprises a client running at the embedded device, as well as
a server that manages deployments across many devices.

This repository contains the the Mender Image Conversion tool which is able to
convert pre-built disk images in to a Mender compatible format containing all
binaries necessary to run the Mender software updater.

We have initially targeted pre-built images from Debian, Raspbian and Ubuntu
and testing has been focused on these. But the tool can certainly be extended
to support additional image formats and contributions are welcome.

![Mender logo](https://mender.io/user/pages/05.resources/06.digital-assets/logo.png)

## Getting started

Install dependencies (instructions are based Debian derivatives build should be
applicable on any major Linux distribution)

    sudo apt-get install mtools parted mtd-utils e2fsprogs u-boot-tools pigz

Mender supports three different server setups:

- Mender Demo - https://docs.mender.io/development/getting-started/create-a-test-environment
- Mender Production - https://docs.mender.io/development/administration/production-installation
- Hosted Mender - https://hosted.mender.io

Mender client configuration is different for each type.

Example using Mender Demo server:

```
./mender-conversion-tool -d raspberrypi3 -i files/2018-06-27-raspbian-stretch.img \
                 -n v1.0.0 -m bin/raspberrypi/mender -o 192.168.0.128
```

Example using Mender Production server:

```
./mender-conversion-tool -d raspberrypi3 -i files/2018-06-27-raspbian-stretch.img \
                 -n v1.0.0 -m bin/raspberrypi/mender -c server.crt \
                 -s https://custom.mender.com
```

Example using Hosted Mender:

```
./mender-conversion-tool -d raspberrypi3 -i files/2018-06-27-raspbian-stretch.img \
                 -n v1.0.0 -m bin/raspberrypi/mender -t mender.token
```

## Stages

The available scripts and what they do:

- mender-conversion-tool

Primary entry script which will call the below scripts in correct order and
with correct arguments. This is the one you want to use.

```
$ ./mender-conversion-tool -h
Usage: mender-conversion-tool options (:hc:d:i:m:n:o:s:t:R:)
    -c - Server certificate (Only for Mender Production setup)
    -d - Device type (/data/mender/device_type)
    -i - Path to image to convert
    -m - Path to Mender client binary
    -n - Mender artifact_name (/etc/mender/artifact_name)
    -o - Demo mode, takes demo server IP address as an argument
    -s - Server URL (Only for Mender Production setup)
    -t - File containing Hosted Mender token (Hosted Mender mode)
    -R - Root file-system
```

- convert-stage-1.sh

Extracts file-system images and information from input image. Also mounts the
root file-system from the input image using `mount -loop`.

- convert-stage-2.sh

Installs all Mender client binaries and configuration files on the mounted root
file-system

- convert-stage-3.sh

Placeholder script. Could be used to inject application binaries.

- convert-stage-4.sh

Platform specific changes. Even though the goal of this tool is to be generic
we can not completely avoid some platform specific adjustments.

- convert-stage-99.sh

Last stage which binds it all together. This script will output:

- Root file-system image (with all modifications)
- Data file-system image (pre-populated with files for Mender client)
- Complete disk image containing a MBR partition table and the appropriate file system images
- Mender artifacts that can be uploaded to the Mender management server to deploy updates OTA

## Output

All temporary files that are created during the conversion and the final output
images are stored in the `output` directory in this repository.

The files of interest after a conversion are:

```
$ ls -alh output/raspberrypi3-v1.0.0.*
-rw-r--r-- 1 user user 1,5G 25 jul 13.54 output/raspberrypi3-v1.0.0.mender
-rw-r--r-- 1 user user 2,9G 25 jul 13.55 output/raspberrypi3-v1.0.0.sdimg.gz
```

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
