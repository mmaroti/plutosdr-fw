
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

all: kernel rootfs fpga boot

clean:
	make -C kernel clean
	make -C rootfs clean
	make -C fpga clean
	make -C boot clean

.PHONY: all clean

kernel:
	make -C kernel all

rootfs:
	make -C rootfs all

fpga:
	make -C fpga all

pluto:
	make -C boot build/pluto.dfu

boot: | kernel rootfs fpga pluto
	make -C boot all

.PHONY: kernel rootfs fpga pluto boot

dfu-pluto: | pluto
	dfu-util -D boot/build/pluto.dfu -a firmware.dfu
	dfu-util -e

dfu-sf-uboot: | boot
	echo "Erasing u-boot be careful - Press Return to continue... " && read key  && \
		dfu-util -D build/boot.dfu -a boot.dfu && \
		dfu-util -D build/uboot-env.dfu -a uboot-env.dfu
	dfu-util -e

dfu-ram: | pluto
	sshpass -p analog ssh root@pluto '/usr/sbin/device_reboot ram;'
	sleep 7
	dfu-util -D boot/build/pluto.dfu -a firmware.dfu
	dfu-util -e

.PHONY: dfu-pluto dfu-sf-boot dfu-ram
