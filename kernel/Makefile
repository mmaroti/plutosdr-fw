
CROSS_COMPILE ?= arm-linux-gnueabihf-

ifeq (, $(shell which $(CROSS_COMPILE)gcc))
$(error Could not find $(CROSS_COMPILE)gcc in PATH)
endif

NCORES = $(shell grep -c ^processor /proc/cpuinfo)

all: build/zImage build/zynq-pluto-sdr.dtb build/zynq-pluto-sdr-revb.dtb build/zynq-pluto-sdr-revc.dtb

clean:
	make -C linux clean
	rm -Rf build

.PHONY: all clean

linux/arch/arm/boot/zImage:
	make -C linux ARCH=arm zynq_pluto_defconfig
	make -C linux -j $(NCORES) ARCH=arm CROSS_COMPILE=$(CROSS_COMPILE) zImage UIMAGE_LOADADDR=0x8000

linux/arch/arm/boot/dts/%.dtb: linux/arch/arm/boot/dts/%.dts linux/arch/arm/boot/dts/zynq-pluto-sdr.dtsi
	make -C linux -j ARCH=arm CROSS_COMPILE=$(CROSS_COMPILE) $(notdir $@)

build:
	mkdir -p $@

build/zImage: linux/arch/arm/boot/zImage | build
	cp $< $@

build/%.dtb: linux/arch/arm/boot/dts/%.dtb | build
	cp $< $@
