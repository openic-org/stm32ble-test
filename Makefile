CUBE_DRV_ROOT ?= /home/manuel/STM32Cube/Repository/STM32Cube_FW_WB0_V1.4.0
CUBE_MW_ROOT  ?= /home/manuel/STM32Cube/Repository/STM32Cube_FW_WB0_V1.4.1
DEBUG         ?= 0

MAKE_FLAGS := CUBE_DRV_ROOT=$(CUBE_DRV_ROOT) CUBE_MW_ROOT=$(CUBE_MW_ROOT) DEBUG=$(DEBUG)

.PHONY: all server client clean flash-server flash-client

all: server client

server:
	$(MAKE) -C server $(MAKE_FLAGS)

client:
	$(MAKE) -C client $(MAKE_FLAGS)

clean:
	$(MAKE) -C server clean
	$(MAKE) -C client clean

flash-server:
	$(MAKE) -C server $(MAKE_FLAGS) flash

flash-client:
	$(MAKE) -C client $(MAKE_FLAGS) flash
