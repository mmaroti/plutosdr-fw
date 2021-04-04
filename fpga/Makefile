
VIVADO_SETTINGS ?= /opt/Xilinx/Vivado/2019.1/settings64.sh

ifeq (, $(shell which $(VIVADO_SETTINGS)))
$(error Could not find $(VIVADO_SETTINGS))
endif

all: build/system_top.hdf

clean:
	make -C hdl clean
	rm -Rf build

.PHONY: all clean

build:
	mkdir -p $@

build/system_top.hdf: | build
	bash -c "source $(VIVADO_SETTINGS) && make -C hdl/projects/pluto"
	cp hdl/projects/pluto/pluto.sdk/system_top.hdf $@
	cp hdl/projects/pluto/pluto.srcs/sources_1/bd/system/ip/system_sys_ps7_0/ps7_init* build/
