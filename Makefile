# Edit these to match your installation

VIVADO_SETTINGS ?= /opt/Xilinx/Vivado/2019.1/settings64.sh
CROSS_COMPILE ?= arm-linux-gnueabihf-

# Set up variables

ifeq (, $(shell which $(VIVADO_SETTINGS)))
$(error Could not find $(VIVADO_SETTINGS))
endif

TOOLCHAIN_GCC = $(shell bash -c "source $(VIVADO_SETTINGS) && which $(CROSS_COMPILE)gcc")
ifeq (, $(TOOLCHAIN_GCC))
$(error Could not find $(CROSS_COMPILE)gcc in PATH)
endif

ifeq (, $(shell which dfu-suffix))
$(error Could not find dfu-utils in PATH")
endif

NCORES = $(shell grep -c ^processor /proc/cpuinfo)
TOOLCHAIN_PATH = $(abspath $(TOOLCHAIN_GCC)/../../)
UBOOT_VERSION=$(shell echo -n "PlutoSDR " && cd u-boot-xlnx && git describe --abbrev=0 --dirty --always --tags)
DEVICE_VID:=0x0456
DEVICE_PID:=0xb673

$(info VIVADO_SETTINGS is $(VIVADO_SETTINGS))
$(info TOOLCHAIN_PATH is $(TOOLCHAIN_PATH))

# Main targets

all: build/pluto.dfu build/pluto.frm build/boot.dfu build/boot.frm build/uboot-env.dfu

clean:
	make -C linux clean
	make -C buildroot clean
	make -C hdl clean
	make -C u-boot-xlnx clean
	rm -Rf build

dfu-pluto: build/pluto.dfu
	dfu-util -D build/pluto.dfu -a firmware.dfu
	dfu-util -e

dfu-sf-uboot: build/boot.dfu build/uboot-env.dfu
	echo "Erasing u-boot be careful - Press Return to continue... " && read key  && \
		dfu-util -D build/boot.dfu -a boot.dfu && \
		dfu-util -D build/uboot-env.dfu -a uboot-env.dfu
	dfu-util -e

dfu-ram: build/pluto.dfu
	sshpass -p analog ssh root@pluto '/usr/sbin/device_reboot ram;'
	sleep 7
	dfu-util -D build/pluto.dfu -a firmware.dfu
	dfu-util -e

.PHONY: all clean dfu-pluto dfu-sf-boot dfu-ram

build:
	mkdir -p $@

### fpga ###

build/system_top.hdf: | build
	bash -c "source $(VIVADO_SETTINGS) && make -C hdl/projects/pluto -j $(NCORES)"
	cp hdl/projects/pluto/pluto.sdk/system_top.hdf $@
	cp hdl/projects/pluto/pluto.srcs/sources_1/bd/system/ip/system_sys_ps7_0/ps7_init* build/

### kernel ###

linux/arch/arm/boot/zImage:
	make -C linux ARCH=arm zynq_pluto_defconfig
	bash -c "source $(VIVADO_SETTINGS) && make -C linux -j $(NCORES) ARCH=arm CROSS_COMPILE=$(CROSS_COMPILE) zImage UIMAGE_LOADADDR=0x8000"

linux/arch/arm/boot/dts/%.dtb: linux/arch/arm/boot/dts/%.dts linux/arch/arm/boot/dts/zynq-pluto-sdr.dtsi
	bash -c "source $(VIVADO_SETTINGS) && make -C linux -j ARCH=arm CROSS_COMPILE=$(CROSS_COMPILE) $(notdir $@)"

build/zImage: linux/arch/arm/boot/zImage | build
	cp $< $@

build/%.dtb: linux/arch/arm/boot/dts/%.dtb | build
	cp $< $@

### rootfs ###

VERSION_OLD = $(shell test -f build/VERSIONS && head -n 1 build/VERSIONS)
VERSION_NEW = plutosdr-fw $(shell git describe --abbrev=4 --dirty --always --tags)

build-versions: | build
ifneq ($(VERSION_OLD),$(VERSION_NEW))
	echo $(VERSION_NEW) > build/VERSIONS
	echo hdl $(shell cd hdl && git describe --abbrev=4 --dirty --always --tags) >> build/VERSIONS
	echo buildroot $(shell cd buildroot && git describe --abbrev=4 --dirty --always --tags) >> build/VERSIONS
	echo linux $(shell cd linux && git describe --abbrev=4 --dirty --always --tags) >> build/VERSIONS
	echo u-boot-xlnx $(shell cd u-boot-xlnx && git describe --abbrev=4 --dirty --always --tags) >> build/VERSIONS
endif

.phony: build-versions

build/VERSIONS: | build-versions

build/LICENSE.html: scripts/legal_info_html.sh build/VERSIONS
	make -C buildroot ARCH=arm zynq_pluto_defconfig
	make -C buildroot legal-info
	scripts/legal_info_html.sh "PlutoSDR" "build/VERSIONS"

buildroot/output/images/rootfs.cpio.gz: build/VERSIONS build/LICENSE.html
	cp build/VERSIONS buildroot/board/pluto/VERSIONS
	cp build/LICENSE.html buildroot/board/pluto/msd/LICENSE.html
	bash -c "source $(VIVADO_SETTINGS) && make -C buildroot -j $(NCORES) ARCH=arm CROSS_COMPILE=$(CROSS_COMPILE) BUSYBOX_CONFIG_FILE=$(CURDIR)/buildroot/board/pluto/busybox-1.25.0.config all"

build/rootfs.cpio.gz: buildroot/output/images/rootfs.cpio.gz | build
	cp $< $@

### pluto.dfu ###

u-boot-xlnx/tools/mkimage:
	make -C u-boot-xlnx ARCH=arm zynq_pluto_defconfig
	bash -c "source $(VIVADO_SETTINGS) && make -C u-boot-xlnx -j $(NCORES) ARCH=arm CROSS_COMPILE=$(CROSS_COMPILE) UBOOTVERSION=\"$(UBOOT_VERSION)\""

build/system_top.bit: build/system_top.hdf
	unzip -o $< system_top.bit -d build
	touch $@

build/pluto.itb: u-boot-xlnx/tools/mkimage build/system_top.bit build/zImage build/zynq-pluto-sdr.dtb build/zynq-pluto-sdr-revb.dtb build/zynq-pluto-sdr-revc.dtb build/rootfs.cpio.gz
	u-boot-xlnx/tools/mkimage -f scripts/pluto.its $@

build/pluto.frm: build/pluto.itb
	md5sum $< | cut -d ' ' -f 1 > $@.md5
	cat $< $@.md5 > $@

build/pluto.dfu: build/pluto.itb
	cp $< $<.tmp
	dfu-suffix -a $<.tmp -v $(DEVICE_VID) -p $(DEVICE_PID)
	mv $<.tmp $@

### uboot-env.dfu ###

build/uboot-env.txt: u-boot-xlnx/tools/mkimage | build
	CROSS_COMPILE=$(CROSS_COMPILE) scripts/get_default_envs.sh > $@

build/uboot-env.bin: build/uboot-env.txt
	u-boot-xlnx/tools/mkenvimage -s 0x20000 -o $@ $<

build/%.dfu: build/%.bin
	cp $< $<.tmp
	dfu-suffix -a $<.tmp -v $(DEVICE_VID) -p $(DEVICE_PID)
	mv $<.tmp $@

### boot.dfu ###

build/u-boot.elf: u-boot-xlnx/tools/mkimage | build
	cp u-boot-xlnx/u-boot $@

build/sdk/fsbl/Release/fsbl.elf: build/system_top.hdf build/system_top.bit
	mv build/system_top.bit build/system_top.bit.orig
	rm -Rf build/sdk
	bash -c "source $(VIVADO_SETTINGS) && xsdk -batch -source scripts/create_fsbl_project.tcl"
	mv build/system_top.bit.orig build/system_top.bit

build/boot.bin: build/sdk/fsbl/Release/fsbl.elf build/u-boot.elf
	@echo img:{[bootloader] $^ } > build/boot.bif
	bash -c "source $(VIVADO_SETTINGS) && bootgen -image build/boot.bif -w -o $@"

build/boot.frm: build/boot.bin build/uboot-env.bin scripts/target_mtd_info.key
	cat $^ | tee $@ | md5sum | cut -d ' ' -f1 | tee -a $@
