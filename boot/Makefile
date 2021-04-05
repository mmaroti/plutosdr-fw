
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
DEVICE_VID:=0x0456
DEVICE_PID:=0xb673

all: build/pluto.dfu build/pluto.frm build/boot.dfu build/boot.frm build/uboot-env.dfu

clean:
	make -C u-boot-xlnx clean
	rm -Rf build

.NOTPARALLEL: all

build:
	mkdir -p $@

### copy files ###

build/system_top.hdf: ../fpga/build/system_top.hdf | build
	cp -a ../fpga/build/system_top.hdf build
	cp -a ../fpga/build/ps7_init* build

build/zImage: ../kernel/build/zImage | build
	cp -a ../kernel/build/zImage build
	cp -a ../kernel/build/*.dtb build

build/rootfs.cpio.gz: ../rootfs/build/rootfs.cpio.gz | build
	cp -a ../rootfs/build/rootfs.cpio.gz build

### pluto image ###

u-boot-xlnx/tools/mkimage:
	make -C u-boot-xlnx ARCH=arm zynq_pluto_defconfig
	make -C u-boot-xlnx ARCH=arm CROSS_COMPILE=$(CROSS_COMPILE) UBOOTVERSION="$(UBOOT_VERSION)"

build/system_top.bit: build/system_top.hdf
	unzip -o $< system_top.bit -d build
	touch $@

build/pluto.itb: u-boot-xlnx/tools/mkimage build/system_top.bit build/zImage build/rootfs.cpio.gz
	u-boot-xlnx/tools/mkimage -f scripts/pluto.its $@

build/pluto.frm: build/pluto.itb
	md5sum $< | cut -d ' ' -f 1 > $@.md5
	cat $< $@.md5 > $@

build/pluto.dfu: build/pluto.itb
	cp $< $<.tmp
	dfu-suffix -a $<.tmp -v $(DEVICE_VID) -p $(DEVICE_PID)
	mv $<.tmp $@

### uboot-env ###

build/uboot-env.txt: u-boot-xlnx/tools/mkimage | build
	CROSS_COMPILE=$(CROSS_COMPILE) scripts/get_default_envs.sh > $@

build/uboot-env.bin: build/uboot-env.txt
	u-boot-xlnx/tools/mkenvimage -s 0x20000 -o $@ $<

### boot ###

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

build/%.dfu: build/%.bin
	cp $< $<.tmp
	dfu-suffix -a $<.tmp -v $(DEVICE_VID) -p $(DEVICE_PID)
	mv $<.tmp $@
