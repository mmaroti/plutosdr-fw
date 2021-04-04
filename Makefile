
VIVADO_SETTINGS ?= /opt/Xilinx/Vivado/2019.1/settings64.sh
CROSS_COMPILE ?= arm-linux-gnueabihf-

ifeq (, $(shell which $(CROSS_COMPILE)gcc))
$(error Could not find $(CROSS_COMPILE)gcc in PATH)
endif

ifeq (, $(shell which $(VIVADO_SETTINGS)))
$(error Could not find $(VIVADO_SETTINGS))
endif

ifeq (, $(shell which dfu-suffix))
$(error Could not find dfu-utils in PATH")
endif

UBOOT_VERSION=$(shell echo -n "PlutoSDR " && cd u-boot-xlnx && git describe --abbrev=0 --dirty --always --tags)

ZIP_ARCHIVE_PREFIX:=plutosdr
DEVICE_VID:=0x0456
DEVICE_PID:=0xb673

TARGETS = build/pluto.dfu build/pluto.frm
TARGETS += build/boot.dfu build/boot.frm 
TARGETS += build/uboot-env.dfu

all: clean-build $(TARGETS)

.NOTPARALLEL: all

build:
	mkdir -p $@

%: build/%
	cp $< $@

### u-boot ###

u-boot-xlnx/u-boot u-boot-xlnx/tools/mkimage:
	make -C u-boot-xlnx ARCH=arm zynq_pluto_defconfig
	make -C u-boot-xlnx ARCH=arm CROSS_COMPILE=$(CROSS_COMPILE) UBOOTVERSION="$(UBOOT_VERSION)"

.PHONY: u-boot-xlnx/u-boot

build/u-boot.elf: u-boot-xlnx/u-boot | build
	cp $< $@

build/uboot-env.txt: u-boot-xlnx/u-boot | build
	CROSS_COMPILE=$(CROSS_COMPILE) scripts/get_default_envs.sh > $@

build/uboot-env.bin: build/uboot-env.txt
	u-boot-xlnx/tools/mkenvimage -s 0x20000 -o $@ $<

kernel/build:
	make -C kernel CROSS_COMPILE=$(CROSS_COMPILE) all

rootfs/build:
	make -C rootfs CROSS_COMPILE=$(CROSS_COMPILE) all

fpga/build:
	make -C fpga VIVADO_SETTINGS=$(VIVADO_SETTINGS) all

build/pluto.itb: u-boot-xlnx/tools/mkimage kernel/build rootfs/build build/system_top.bit
	u-boot-xlnx/tools/mkimage -f scripts/pluto.its $@

build/sdk/fsbl/Release/fsbl.elf build/sdk/hw_0/system_top.bit: fpga/build
	rm -Rf build/sdk
	bash -c "source $(VIVADO_SETTINGS) && xsdk -batch -source scripts/create_fsbl_project.tcl"

build/system_top.bit: build/sdk/hw_0/system_top.bit
	cp $< $@

build/boot.bin: build/sdk/fsbl/Release/fsbl.elf build/u-boot.elf
	@echo img:{[bootloader] $^ } > build/boot.bif
	bash -c "source $(VIVADO_SETTINGS) && bootgen -image build/boot.bif -w -o $@"

### MSD update firmware file ###

build/pluto.frm: build/pluto.itb
	md5sum $< | cut -d ' ' -f 1 > $@.md5
	cat $< $@.md5 > $@

build/boot.frm: build/boot.bin build/uboot-env.bin scripts/target_mtd_info.key
	cat $^ | tee $@ | md5sum | cut -d ' ' -f1 | tee -a $@

### DFU update firmware file ###

build/%.dfu: build/%.bin
	cp $< $<.tmp
	dfu-suffix -a $<.tmp -v $(DEVICE_VID) -p $(DEVICE_PID)
	mv $<.tmp $@

build/pluto.dfu: build/pluto.itb
	cp $< $<.tmp
	dfu-suffix -a $<.tmp -v $(DEVICE_VID) -p $(DEVICE_PID)
	mv $<.tmp $@

clean-build:
	rm -f $(notdir $(wildcard build/*))
	rm -rf build/*

clean:
	make -C u-boot-xlnx clean
	make -C kernel clean
	make -C rootfs clean
	make -C hdl clean
	rm -f $(notdir $(wildcard build/*))
	rm -rf build/*

dfu-pluto: build/pluto.dfu
	dfu-util -D build/pluto.dfu -a firmware.dfu
	dfu-util -e

dfu-sf-uboot: build/boot.dfu build/uboot-env.dfu
	echo "Erasing u-boot be careful - Press Return to continue... " && read key  && \
		dfu-util -D build/boot.dfu -a boot.dfu && \
		dfu-util -D build/uboot-env.dfu -a uboot-env.dfu
	dfu-util -e

dfu-all: build/pluto.dfu build/boot.dfu build/uboot-env.dfu
	echo "Erasing u-boot be careful - Press Return to continue... " && read key && \
		dfu-util -D build/pluto.dfu -a firmware.dfu && \
		dfu-util -D build/boot.dfu -a boot.dfu  && \
		dfu-util -D build/uboot-env.dfu -a uboot-env.dfu
	dfu-util -e

dfu-ram: build/pluto.dfu
	sshpass -p analog ssh root@pluto '/usr/sbin/device_reboot ram;'
	sleep 7
	dfu-util -D build/pluto.dfu -a firmware.dfu
	dfu-util -e

git-update-all:
	git submodule update --recursive --remote

git-pull:
	git pull --recurse-submodules
