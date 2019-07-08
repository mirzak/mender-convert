mender-convert
==============

Mender is an open source over-the-air (OTA) software updater for embedded Linux devices. Mender comprises a client running at the embedded device, as well as a server that manages deployments across many devices.

This repository contains mender-convert, which is used to convert pre-built disk images (Debian, Ubuntu, Raspbian, etc) to a Mender compatible image by restructuring partition table and injecting the necessary files.

For a full list of tested devices and images please visit [Mender Hub](https://hub.mender.io/c/board-integrations/debian-family). If your device and image combination is not listed as supported, this does not necessarily mean that it will not work, it probably just means that none has tested and reported it back and usually only small tweaks are necessary to get this running on your device.

![Mender logo](https://mender.io/user/pages/resources/06.digital-assets/mender.io.png)

## Getting started

To start using Mender, we recommend that you begin with the Getting started
section in [the Mender documentation](https://docs.mender.io/).

For more detailed information about `mender-convert` please visit the
[Debian family](https://docs.mender.io/2.0/artifacts/debian-family) section in
[the Mender documentation](https://docs.mender.io/).

## Docker environment for mender-convert

In order to correctly set up partitions and bootloaders, mender-convert has many dependencies,
and their version and name vary between Linux distributions.

To make using mender-convert easier, a reference setup using a Ubuntu 19.04 Docker container
is provided.

You need to [install Docker Engine](https://docs.docker.com/install) to use this environment.


### Build the mender-convert container image

To build a container based on Ubuntu 18.04 with all required dependencies for mender-convert,
copy this directory to your workstation and change the current directory to it.

Then run

```bash
./docker-build
```

This will create a container image which you can use to run `mender-convert`
without polluting your host environment with the necessary dependencies.


### Use the mender-convert container image

Create a `input` directory in the root of where you cloned this repository.

```bash
mkdir input
```

Move your raw disk image into `input/`, e.g.

```bash
mv ~/Downloads/2019-04-08-raspbian-stretch-lite.img input/2019-04-08-raspbian-stretch-lite.img
```

Bootstrap the demo rootfs overlay that is configured to connect to
https://hosted.mender.io with polling intervals set appropriately for
demonstration purposes:

```
./scripts/bootstrap-rootfs-overlay-demo.sh --tenant-token <paste token from Hosted Mender>
```

Run mender-convert from inside the container with your desired options, e.g.

```bash
MENDER_ARTIFACT_NAME=release-1 ./docker-mender-convert \
    --disk-image input/2019-04-08-raspbian-stretch-lite.img \
    --config configs/raspberrypi3_config \
    --overlay rootfs_overlay_demo/
```

Conversion will take 10-30 minutes, depending on image size and resources available.
You can watch `work/convert.log` for progress and diagnostics information.

After it finishes, you can find your images in the `deploy` directory on your host machine!

## Contributing

We welcome and ask for your contribution. If you would like to contribute to Mender, please read our guide on how to best get started [contributing code or documentation](https://github.com/mendersoftware/mender/blob/master/CONTRIBUTING.md).

## License

Mender is licensed under the Apache License, Version 2.0. See [LICENSE](https://github.com/mendersoftware/mender-crossbuild/blob/master/LICENSE) for the full license text.

## Security disclosure

We take security very seriously. If you come across any issue regarding
security, please disclose the information by sending an email to
[security@mender.io](security@mender.io). Please do not create a new public
issue. We thank you in advance for your cooperation.

## Connect with us

* Join the [Mender Hub discussion forum](https://hub.mender.io)
* Follow us on [Twitter](https://twitter.com/mender_io). Please
  feel free to tweet us questions.
* Fork us on [Github](https://github.com/mendersoftware)
* Create an issue in the [bugtracker](https://tracker.mender.io/projects/MEN)
* Email us at [contact@mender.io](mailto:contact@mender.io)
* Connect to the [#mender IRC channel on Freenode](http://webchat.freenode.net/?channels=mender)


## Authors

Mender was created by the team at [Northern.tech AS](https://northern.tech), with many contributions from
the community. Thanks [everyone](https://github.com/mendersoftware/mender/graphs/contributors)!

[Mender](https://mender.io) is sponsored by [Northern.tech AS](https://northern.tech).
