HOWTO: Building Mender binaries
===============================

This document is specific to Ubuntu on generic 64-bit PCs.

Note that the steps show here for creating the mender and
mender-artifact binaries are not required for converting exsting
images; precompiled versions of these are provided with this
repository.  The instructions here are for reference. Consult the file
README.md for simple instructions to convert images.

## Fetching sources and building

There are two different repositories that are needed:

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

### Mender Client

Now that we have golang setup we can fetch and build the Mender client.

    $ export GOPATH=${UBUNTU_MENDER_DIR}/golang
    $ mkdir ${GOPATH}
    $ cd ${GOPATH}
    $ git clone git@github.com:mendersoftware/mender.git src/github.com/mendersoftware/mender
    $ cd ${GOPATH}/src/github.com/mendersoftware/mender
    $ git checkout 1.5.0
    $ make clean
    $ make get-tools
    $ CC=gcc \
      GOOS=linux \
      GOARCH=amd64 make build
    $ strip mender
    $ make install

A pre-built binary for 64-bit PC architecture systems running Ubuntu
is provided with this repository under bin/ubuntu/

### Mender Artifact tool

We need a version of the mender-artifact tool to run on your build
system (note that this does _not_ run on the target).

    $ export GOPATH=${UBUNTU_MENDER_DIR}/golang
    $ mkdir ${GOPATH}
    $ cd ${GOPATH}
    $ git clone git@github.com:mendersoftware/mender-artifact.git src/github.com/mendersoftware/mender-artifact
    $ cd ${GOPATH}/src/github.com/mendersoftware/mender-artifact
    $ make qgit checkout 2.2.0
    $ make clean
    $ make get-tools
    $ make
    $ make install

A pre-built binary for 64-bit PC architecture systems running Ubuntu
is provided with this repository under bin/

For more details please see the Mender documentation online:
* https://docs.mender.io/1.5/artifacts/modifying-a-mender-artifact#compiling-mender-artifact
