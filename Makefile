# Edit these to match your installation

VIVADO_SETTINGS ?= /opt/Xilinx/Vivado/2019.1/settings64.sh
CROSS_COMPILE ?= arm-linux-gnueabihf-
FPGA_DIR ?= src/fpga0

# Set up variables

ifeq (, $(shell which $(VIVADO_SETTINGS)))
$(error Could not find $(VIVADO_SETTINGS))
endif

TOOLCHAIN = $(shell bash -c "source $(VIVADO_SETTINGS) && which $(CROSS_COMPILE)gcc")

ifeq (, $(TOOLCHAIN))
$(error Could not find $(CROSS_COMPILE)gcc in PATH)
endif

ifeq (, $(shell which dfu-suffix))
$(error Could not find dfu-utils in PATH")
endif

NCORES = $(shell nproc)
DEVICE_VID := 0x0456
DEVICE_PID := 0xb673

$(info VIVADO_SETTINGS is $(VIVADO_SETTINGS))
$(info TOOLCHAIN is $(TOOLCHAIN))
$(info FPGA_DIR is $(FPGA_DIR))

# Main targets

pluto: build/pluto.dfu build/pluto.frm

all: pluto build/boot.dfu build/boot.frm build/uboot-env.dfu

clean:
	make -C linux clean
	make -C buildroot clean
	make -C $(FPGA_DIR) clean
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

.PHONY: pluto all clean dfu-pluto dfu-sf-boot dfu-ram

# helper targets

build:
	mkdir -p $@

FORCE:

.PHONY: FORCE

### fpga ###

build/system_top.hdf: FORCE | build
	bash -c "source $(VIVADO_SETTINGS) && make -C $(FPGA_DIR) -j $(NCORES)"
	cp -a $(FPGA_DIR)/build/system_top.hdf $@
	cp -a $(FPGA_DIR)/build/ps7_init* build/

### kernel ###

linux/arch/arm/boot/zImage:
	make -C linux ARCH=arm zynq_pluto_defconfig
	bash -c "source $(VIVADO_SETTINGS) && make -C linux -j $(NCORES) ARCH=arm CROSS_COMPILE=$(CROSS_COMPILE) zImage UIMAGE_LOADADDR=0x8000"

build/zImage: linux/arch/arm/boot/zImage | build
	cp $< $@

copydtsi:
	cp -a $(FPGA_DIR)/*.dtsi linux/arch/arm/boot/dts/

.PHONY: copydtsi

build/%.dtb: $(FPGA_DIR)/%.dts $(wildcard $(FPGA_DIR)/*.dtsi) | copydtsi build
	cp -a $< linux/arch/arm/boot/dts/
	bash -c "source $(VIVADO_SETTINGS) && make -C linux ARCH=arm CROSS_COMPILE=$(CROSS_COMPILE) $(notdir $@)"
	cp -a linux/arch/arm/boot/dts/$(notdir $@) $@

### rootfs ###

VERSION_OLD = $(shell test -f build/VERSIONS && head -n 1 build/VERSIONS)
VERSION_NEW = plutosdr-fw $(shell git describe --dirty --always --tags)

build/VERSIONS: FORCE | build
ifneq ($(VERSION_OLD), $(VERSION_NEW))
	echo $(VERSION_NEW) > $@
	echo hdl $(shell cd hdl && git describe --dirty --always --tags) >> $@
	echo buildroot $(shell cd buildroot && git describe --dirty --always --tags) >> $@
	echo linux $(shell cd linux && git describe --dirty --always --tags) >> $@
	echo u-boot-xlnx $(shell cd u-boot-xlnx && git describe --dirty --always --tags) >> $@
endif

build/LICENSE.html: src/scripts/legal_info_html.sh build/VERSIONS
	make -C buildroot ARCH=arm zynq_pluto_defconfig
	make -C buildroot legal-info
	src/scripts/legal_info_html.sh "PlutoSDR" "build/VERSIONS"

buildroot/output/images/rootfs.cpio.gz: build/VERSIONS build/LICENSE.html
	cp build/VERSIONS buildroot/board/pluto/VERSIONS
	cp build/LICENSE.html buildroot/board/pluto/msd/LICENSE.html
	bash -c "source $(VIVADO_SETTINGS) && make -C buildroot -j $(NCORES) ARCH=arm CROSS_COMPILE=$(CROSS_COMPILE) BUSYBOX_CONFIG_FILE=$(CURDIR)/buildroot/board/pluto/busybox-1.25.0.config all"

build/rootfs.cpio.gz: buildroot/output/images/rootfs.cpio.gz | build
	cp $< $@

### pluto.dfu ###

UBOOT_VERSION = $(shell echo -n "PlutoSDR " && cd u-boot-xlnx && git describe --dirty --always --tags)

u-boot-xlnx/tools/mkimage:
	make -C u-boot-xlnx ARCH=arm zynq_pluto_defconfig
	bash -c "source $(VIVADO_SETTINGS) && make -C u-boot-xlnx -j $(NCORES) ARCH=arm CROSS_COMPILE=$(CROSS_COMPILE) UBOOTVERSION=\"$(UBOOT_VERSION)\""

build/system_top.bit: build/system_top.hdf
	unzip -o $< system_top.bit -d build
	touch $@

build/pluto.itb: src/scripts/pluto.its u-boot-xlnx/tools/mkimage build/system_top.bit build/zImage build/zynq-pluto-sdr.dtb build/zynq-pluto-sdr-revb.dtb build/zynq-pluto-sdr-revc.dtb build/rootfs.cpio.gz
	u-boot-xlnx/tools/mkimage -f src/scripts/pluto.its $@

build/pluto.frm: build/pluto.itb
	md5sum $< | cut -d ' ' -f 1 > $@.md5
	cat $< $@.md5 > $@

build/pluto.dfu: build/pluto.itb
	cp $< $<.tmp
	dfu-suffix -a $<.tmp -v $(DEVICE_VID) -p $(DEVICE_PID)
	mv $<.tmp $@

### uboot-env.dfu ###

build/uboot-env.txt: src/scripts/get_default_envs.sh u-boot-xlnx/tools/mkimage | build
	CROSS_COMPILE=$(CROSS_COMPILE) src/scripts/get_default_envs.sh > $@

build/uboot-env.bin: build/uboot-env.txt
	u-boot-xlnx/tools/mkenvimage -s 0x20000 -o $@ $<

build/%.dfu: build/%.bin
	cp $< $<.tmp
	dfu-suffix -a $<.tmp -v $(DEVICE_VID) -p $(DEVICE_PID)
	mv $<.tmp $@

### boot.dfu ###

build/u-boot.elf: u-boot-xlnx/tools/mkimage | build
	cp u-boot-xlnx/u-boot $@

build/sdk/fsbl/Release/fsbl.elf: src/scripts/create_fsbl_project.tcl build/system_top.hdf build/system_top.bit
	mv build/system_top.bit build/system_top.bit.orig
	rm -Rf build/sdk
	bash -c "source $(VIVADO_SETTINGS) && xsdk -batch -source src/scripts/create_fsbl_project.tcl"
	mv build/system_top.bit.orig build/system_top.bit

build/boot.bin: build/sdk/fsbl/Release/fsbl.elf build/u-boot.elf
	@echo img:{[bootloader] $^ } > build/boot.bif
	bash -c "source $(VIVADO_SETTINGS) && bootgen -image build/boot.bif -w -o $@"

build/boot.frm: build/boot.bin build/uboot-env.bin src/scripts/target_mtd_info.key
	cat $^ | tee $@ | md5sum | cut -d ' ' -f1 | tee -a $@
