###
###  *** Makefile for mapping a project in HDL to GDS ***
###
###  Make gds through openlane, info (stats), png, interactive docker shell...
###  docs below and within
###  
###
###  Copyright (C) 2023 Pat Deegan, https://psychogenic.com
###  
###  This program is free software; you can redistribute it and/or modify
###  it under the terms of the GNU General Public License as published by
###  the Free Software Foundation; either version 2 of the License, or
###  (at your option) any later version.
###  
###  This program is distributed in the hope that it will be useful,
###  but WITHOUT ANY WARRANTY; without even the implied warranty of
###  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
###  GNU General Public License for more details.
###
###
###
###  This is basically the same function as the TinyTapeout
###  github actions, but packaged so you can run them 
###  locally and with some extra goodies.
###
###  The various settings are below, with comments.  In short
###  if you set
###		OPENLANE_ROOT
###		PDK_ROOT and
###		PDK
###  here, or in your environment, then you can
###
###	 make gds # go through the whole flow
###	 make info # gather some stats
###  make png  # generate some images
###
###  make interactive
###
###  brings you straight into the openlane docker shell, with the 
###  project mounted and available.
###
###


PYTHON_BIN ?= python3
CWD = $(shell pwd)


# OPENLANE_ROOT set this to full path of openlane install
OPENLANE_ROOT ?= $(shell cd ../../; pwd)

# PDK_ROOT set this to full path of sky130 pdk
PDK_ROOT ?= $(OPENLANE_ROOT)/pdks

OPENLANE_IMAGE_NAME ?= efabless/openlane

#OPENLANE_DIR = $(shell pwd)

DOCKER_OPTIONS = $(shell $(PYTHON_BIN) $(OPENLANE_ROOT)/env.py docker-config)

DOCKER_ARCH ?= $(shell $(PYTHON_BIN) $(OPENLANE_ROOT)/docker/current_platform.py)



PDK ?= sky130A

# FLOW_RUN_TAG current run tag
# e.g. 
#      FLOW_RUN_TAG=trialXYZ make gds
# will gen all its output under runs/trialXYZ
FLOW_RUN_TAG ?= run$(shell date +"%m%d")

# WORKDIR parent dir with src etc, defaults to pwd
WORKDIR ?= $(shell pwd)

# INFOFILE -- result of make info, some stats output by 
# tt into summary-info-$(FLOW_RUN_TAG).txt
INFOFILE ?= $(WORKDIR)/summary-info-$(FLOW_RUN_TAG).txt


# x windows stuff for interactive
XSOCK :=/tmp/.X11-unix
XAUTH :=/tmp/.docker.xauth

# OPENLANE_SRC_WORKDIR -- the project dir is mapped into openlane docker at
# this location 
OPENLANE_SRC_WORKDIR ?= /work

# CURRENTRUN_OUTPUT_DIR -- where the output of the flow winds up
CURRENTRUN_OUTPUT_DIR := runs/$(FLOW_RUN_TAG)

# FLOW_RUNNER_COMMAND -- the actual call to flow.tcl, inside openlane docker
FLOW_RUNNER_COMMAND := ./flow.tcl -overwrite -design $(OPENLANE_SRC_WORKDIR)/src -run_path $(OPENLANE_SRC_WORKDIR)/runs -tag $(FLOW_RUN_TAG)

# basic openlane docker args, mounting for source files, setting up X forwarding
# (for interactive, e.g. openroad -gui), and a $FLOWRUNNER env var just as a reminder
OPENLANE_DOCKER_ARGS := -v $(OPENLANE_ROOT):/openlane \
		-v $(PDK_ROOT):$(PDK_ROOT) -v $(WORKDIR):$(OPENLANE_SRC_WORKDIR) \
		-e PDK_ROOT=$(PDK_ROOT)  -e PDK=$(PDK) \
		-u $(shell id -u $(USER)):$(shell id -g $(USER)) \
		--net=host --env="DISPLAY"  \
		-v $(XSOCK) -v $(XAUTH) -e XAUTHORITY=$(XAUTH) \
		-e FLOWRUNNER="$(FLOW_RUNNER_COMMAND)" \
		$(OPENLANE_IMAGE_NAME)


# some output file that shows gds was already run
GDS_RUN_OUTFILE := $(CURRENTRUN_OUTPUT_DIR)/reports/signoff/drc.rpt
# get the TinyTapeout tools and install reqs
tt: 
	git clone https://github.com/TinyTapeout/tt-support-tools.git tt
	pip install -r tt/requirements.txt


# generated user config, using tt
src/user_config.tcl: tt
	./tt/tt_tool.py --create-user-config
	

# make userconfig will gen this file
userconfig: src/user_config.tcl


yo: 
	echo "$(DOCKER_ARCH)"
	echo "$(DOCKER_OPTIONS)"
# make the GDS, ie. go through entire flow
gds: src/user_config.tcl $(GDS_RUN_OUTFILE)
	

# a stats file post run
$(INFOFILE): 
	./tt/tt_tool.py --print-warnings > $(INFOFILE)
	./tt/tt_tool.py --print-stats >> $(INFOFILE)
	./tt/tt_tool.py --print-cell-category >> $(INFOFILE)

# make info to generate stats file, after going through flow
info: gds $(INFOFILE)
	cat $(INFOFILE)
	echo "Stored in $(INFOFILE)"

# the PNG of all the magic
gds_render.png: 
	./tt/tt_tool.py --run-dir $(CURRENTRUN_OUTPUT_DIR)  --create-png

# make png, to get image
png: gds gds_render.png
	echo $(shell ls -1 gds_render*)

# make interactive, to launch openlane docker in interactive mode 
interactive: tt
	xauth nlist $(DISPLAY) | sed -e 's/^..../ffff/' | xauth -f $(XAUTH) nmerge -
	chmod 755 $(XAUTH)
	docker run -it  $(OPENLANE_DOCKER_ARGS)

# not the best way to do this, but simple way of detecting GDS has
# been done
$(GDS_RUN_OUTFILE):
	echo running synth
	docker run $(OPENLANE_DOCKER_ARGS) \
		/bin/bash -c "$(FLOW_RUNNER_COMMAND)"
	
.PHONY: klayout_cells show_latestdb
klayout_cells: 
	docker run $(OPENLANE_DOCKER_ARGS) \
		/bin/bash -c "klayout -l $(OPENLANE_SRC_WORKDIR)/klayout-cellfocused.lyp $(OPENLANE_SRC_WORKDIR)/$(CURRENTRUN_OUTPUT_DIR)/results/final/gds/freqcount.gds"


show_latestdb:
	echo read_db $(OPENLANE_SRC_WORKDIR)/`find $(CURRENTRUN_OUTPUT_DIR) -name "*.odb" | xargs ls -1t | head -1` > $(CURRENTRUN_OUTPUT_DIR)/viewlatestdb.tcl
	echo gui::show >> $(CURRENTRUN_OUTPUT_DIR)/viewlatestdb.tcl
	docker run $(OPENLANE_DOCKER_ARGS) \
		/bin/bash -c "openroad $(OPENLANE_SRC_WORKDIR)/$(CURRENTRUN_OUTPUT_DIR)/viewlatestdb.tcl"


# delete that GDS outfile and 
.PHONY: clean veryclean
clean:
	rm $(WORKDIR)/$(GDS_RUN_OUTFILE)

veryclean:
	rm -r $(CURRENTRUN_OUTPUT_DIR)

