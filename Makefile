
VIVADO_SETTINGS ?= /opt/Xilinx/Vivado/2019.1/settings64.sh
CROSS_COMPILE ?= arm-linux-gnueabihf-

ifeq (, $(shell which $(CROSS_COMPILE)gcc))
$(error Could not find $(CROSS_COMPILE)gcc in PATH)
endif

ifeq (, $(shell which $(VIVADO_SETTINGS)))
$(error Could not find $(VIVADO_SETTINGS))
endif

ifeq (, $(shell which dfu-suffix))
$(error Could dfu-utils in PATH")
endif

TOOLCHAIN_PATH = $(shell dirname $(shell dirname $(shell which $(CROSS_COMPILE)gcc)))
# $(info TOOLCHAIN_PATH is $(TOOLCHAIN_PATH))

NCORES = $(shell grep -c ^processor /proc/cpuinfo)
VSUBDIRS = hdl buildroot linux u-boot-xlnx

VERSION=$(shell git describe --abbrev=4 --dirty --always --tags)
UBOOT_VERSION=$(shell echo -n "PlutoSDR " && cd u-boot-xlnx && git describe --abbrev=0 --dirty --always --tags)

TARGET_DTS_FILES:= zynq-pluto-sdr.dtb zynq-pluto-sdr-revb.dtb zynq-pluto-sdr-revc.dtb
COMPLETE_NAME:=PlutoSDR
ZIP_ARCHIVE_PREFIX:=plutosdr
DEVICE_VID:=0x0456
DEVICE_PID:=0xb673

TARGETS = build/pluto.dfu build/pluto.frm
TARGETS += build/boot.dfu build/boot.frm 
TARGETS += build/uboot-env.dfu jtag-bootstrap

all: clean-build $(TARGETS) zip-all legal-info

.NOTPARALLEL: all

TARGET_DTS_FILES:=$(foreach dts,$(TARGET_DTS_FILES),build/$(dts))
# $(info TARGET_DTS_FILES is $(TARGET_DTS_FILES))

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

### Linux ###

linux/arch/arm/boot/zImage:
	make -C linux ARCH=arm zynq_pluto_defconfig
	make -C linux -j $(NCORES) ARCH=arm CROSS_COMPILE=$(CROSS_COMPILE) zImage UIMAGE_LOADADDR=0x8000

.PHONY: linux/arch/arm/boot/zImage


build/zImage: linux/arch/arm/boot/zImage  | build
	cp $< $@

### Device Tree ###

linux/arch/arm/boot/dts/%.dtb: linux/arch/arm/boot/dts/%.dts  linux/arch/arm/boot/dts/zynq-pluto-sdr.dtsi
	make -C linux -j $(NCORES) ARCH=arm CROSS_COMPILE=$(CROSS_COMPILE) $(notdir $@)

build/%.dtb: linux/arch/arm/boot/dts/%.dtb | build
	cp $< $@

### Buildroot ###

buildroot/output/images/rootfs.cpio.gz:
	@echo device-fw $(VERSION)> $(CURDIR)/buildroot/board/pluto/VERSIONS
	@$(foreach dir,$(VSUBDIRS),echo $(dir) $(shell cd $(dir) && git describe --abbrev=4 --dirty --always --tags) >> $(CURDIR)/buildroot/board/pluto/VERSIONS;)
	make -C buildroot ARCH=arm zynq_pluto_defconfig
	make -C buildroot legal-info
	scripts/legal_info_html.sh "$(COMPLETE_NAME)" "$(CURDIR)/buildroot/board/pluto/VERSIONS"
	cp build/LICENSE.html buildroot/board/pluto/msd/LICENSE.html
	make -C buildroot TOOLCHAIN_EXTERNAL_INSTALL_DIR=$(TOOLCHAIN_PATH) ARCH=arm CROSS_COMPILE=$(CROSS_COMPILE) BUSYBOX_CONFIG_FILE=$(CURDIR)/buildroot/board/pluto/busybox-1.25.0.config all

.PHONY: buildroot/output/images/rootfs.cpio.gz

build/rootfs.cpio.gz: buildroot/output/images/rootfs.cpio.gz | build
	cp $< $@

build/pluto.itb: u-boot-xlnx/tools/mkimage build/zImage build/rootfs.cpio.gz $(TARGET_DTS_FILES) build/system_top.bit
	u-boot-xlnx/tools/mkimage -f scripts/pluto.its $@

build/system_top.hdf:  | build
	bash -c "source $(VIVADO_SETTINGS) && make -C hdl/projects/pluto && cp hdl/projects/pluto/pluto.sdk/system_top.hdf $@"
	unzip -l $@ | grep -q ps7_init || cp hdl/projects/pluto/pluto.srcs/sources_1/bd/system/ip/system_sys_ps7_0/ps7_init* build/

### TODO: Build system_top.hdf from src if dl fails - need 2016.2 for that ...

build/sdk/fsbl/Release/fsbl.elf build/sdk/hw_0/system_top.bit : build/system_top.hdf
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
	make -C linux clean
	make -C buildroot clean
	make -C hdl clean
	rm -f $(notdir $(wildcard build/*))
	rm -rf build/*

zip-all: $(TARGETS)
	zip -j build/$(ZIP_ARCHIVE_PREFIX)-fw-$(VERSION).zip $^

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

jtag-bootstrap: build/u-boot.elf build/sdk/hw_0/ps7_init.tcl build/sdk/hw_0/system_top.bit scripts/run.tcl
	$(CROSS_COMPILE)strip build/u-boot.elf
	zip -j build/$(ZIP_ARCHIVE_PREFIX)-$@-$(VERSION).zip $^

sysroot: buildroot/output/images/rootfs.cpio.gz
	tar czfh build/sysroot-$(VERSION).tar.gz --hard-dereference --exclude=usr/share/man -C buildroot/output staging

legal-info: buildroot/output/images/rootfs.cpio.gz
	tar czvf build/legal-info-$(VERSION).tar.gz -C buildroot/output legal-info

git-update-all:
	git submodule update --recursive --remote

git-pull:
	git pull --recurse-submodules
