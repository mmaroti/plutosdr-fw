
CROSS_COMPILE ?= arm-linux-gnueabihf-

ifeq (, $(shell which $(CROSS_COMPILE)gcc))
$(error Could not find $(CROSS_COMPILE)gcc in PATH)
endif

NCORES = $(shell grep -c ^processor /proc/cpuinfo)
TOOLCHAIN_PATH = $(shell dirname $(shell dirname $(shell which $(CROSS_COMPILE)gcc)))

all: build/VERSIONS build/LICENSE.html build/rootfs.cpio.gz

clean:
	make -C buildroot clean
	rm -rf build

.PHONY: all clean

build:
	mkdir -p $@

build/VERSIONS: build
	echo plutosdr-fw $(shell cd .. && git describe --abbrev=4 --dirty --always --tags) > $@
	echo hdl $(shell cd ../hdl && git describe --abbrev=4 --dirty --always --tags) >> $@
	echo buildroot $(shell cd buildroot && git describe --abbrev=4 --dirty --always --tags) >> $@
	echo linux $(shell cd ../kernel/linux && git describe --abbrev=4 --dirty --always --tags) >> $@
	echo u-boot-xlnx $(shell cd ../u-boot-xlnx && git describe --abbrev=4 --dirty --always --tags) >> $@

build/LICENSE.html: build/VERSIONS
	make -C buildroot ARCH=arm zynq_pluto_defconfig
	make -C buildroot -j $(NCORES) legal-info
	scripts/legal_info_html.sh "PlutoSDR" "build/VERSIONS"

buildroot/output/images/rootfs.cpio.gz: build/VERSIONS build/LICENSE.html
	cp build/VERSIONS buildroot/board/pluto/VERSIONS
	cp build/LICENSE.html buildroot/board/pluto/msd/LICENSE.html
	make -C buildroot -j $(NCORES) TOOLCHAIN_EXTERNAL_INSTALL_DIR=$(TOOLCHAIN_PATH) ARCH=arm CROSS_COMPILE=$(CROSS_COMPILE) BUSYBOX_CONFIG_FILE=$(CURDIR)/buildroot/board/pluto/busybox-1.25.0.config all

build/rootfs.cpio.gz: buildroot/output/images/rootfs.cpio.gz build
	cp $< $@
