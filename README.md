# plutosdr-fw
PlutoSDR Firmware for the [ADALM-PLUTO](https://wiki.analog.com/university/tools/pluto "PlutoSDR Wiki Page") Active Learning Module.

Firmware License : [![Many Licenses](https://img.shields.io/badge/license-LGPL2+-blue.svg)](https://github.com/analogdevicesinc/plutosdr-fw/blob/master/LICENSE.md)  [![Many License](https://img.shields.io/badge/license-GPL2+-blue.svg)](https://github.com/analogdevicesinc/plutosdr-fw/blob/master/LICENSE.md)  [![Many License](https://img.shields.io/badge/license-BSD-blue.svg)](https://github.com/analogdevicesinc/plutosdr-fw/blob/master/LICENSE.md)  [![Many License](https://img.shields.io/badge/license-apache-blue.svg)](https://github.com/analogdevicesinc/plutosdr-fw/blob/master/LICENSE.md) and many others.

This is an updated version of the original [plutosdr-fw](https://github.com/analogdevicesinc/plutosdr-fw)
repository with many tweaks to the build system. This allows faster compilation times and easier way to
modify the FPGA code, the linux kernel settings, the root file system and built in utilities,
and the boot loader settings.

* Build Instructions:
Please install Vivado 2019.1 first, then run these commands:

```bash
 sudo apt-get install git build-essential fakeroot libncurses5-dev libssl-dev ccache
 sudo apt-get install dfu-util u-boot-tools device-tree-compiler libssl1.0-dev mtools
 sudo apt-get install bc python cpio zip unzip rsync file wget
 git clone --recursive https://github.com/mmaroti/plutosdr-fw
 cd plutosdr-fw
 make
```

 * Updating your local repository: `git pull --recurse-submodules`.

 * Programming the ADALM Pluto: Make sure that you copy the `src/scripts/53-adi-plutosdr-usb.rules`
 file to `/etc/udev/rules.d` to have user access to the pluto (otherwise you need run the following
 commands as root). You can upload the new image with the `make dfu-ram` or `make dfu-pluto`
 commands.

 * Main targets

     | File  | Comment |
     | ----- | ------- |
     | pluto.frm | Main PlutoSDR firmware file used with the USB Mass Storage Device |
     | pluto.dfu | Main PlutoSDR firmware file used in DFU mode |
     | boot.frm | First and Second Stage Bootloader (u-boot + fsbl + uEnv) used with the USB Mass Storage Device |
     | boot.dfu | First and Second Stage Bootloader (u-boot + fsbl) used in DFU mode |
     | uboot-env.dfu | u-boot default environment used in DFU mode |

