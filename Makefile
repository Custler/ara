# Copyright 2020 ETH Zurich and University of Bologna.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Author: Matheus Cavalcante, ETH Zurich

SHELL = /usr/bin/env bash
ROOT_DIR := $(patsubst %/,%, $(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
ARA_DIR := $(shell git rev-parse --show-toplevel 2>/dev/null || echo $$MEMPOOL_DIR)

INSTALL_PREFIX          ?= install
INSTALL_DIR             ?= ${ROOT_DIR}/${INSTALL_PREFIX}
GCC_INSTALL_DIR         ?= ${INSTALL_DIR}/riscv-gcc
LLVM_INSTALL_DIR        ?= ${INSTALL_DIR}/riscv-llvm
ISA_SIM_INSTALL_DIR     ?= ${INSTALL_DIR}/riscv-isa-sim
ISA_SIM_MOD_INSTALL_DIR ?= ${INSTALL_DIR}/riscv-isa-sim-mod
VERIL_INSTALL_DIR       ?= ${INSTALL_DIR}/verilator

#===============================================================================
# Toolchain versions

# Newlib tags: https://sourceware.org/git/?p=newlib-cygwin.git;a=tags
NEWLIB_TAG              ?= newlib-4.4.0

# riscv-gnu-toolchain tags: https://github.com/riscv-collab/riscv-gnu-toolchain/tags
RISCV_GNU_TOOLCHAIN_TAG ?= 2024.02.02

# LLVM version:
LLVM_VER                ?= release/17.x

# VERILATOR tags: https://github.com/verilator/verilator/tags
VERIL_VERSION           ?= v5.020

DTC_COMMIT              ?= v1.6.1
# DTC tags: https://github.com/dgibson/dtc/tags
# DTC_COMMIT              ?= v1.7.0

#===============================================================================

CMAKE ?= cmake

# CC and CXX are Makefile default variables that are always defined in a Makefile. Hence, overwrite
# the variable if it is only defined by the Makefile (its origin in the Makefile's default).
ifeq ($(origin CC),default)
CC     = gcc
endif
ifeq ($(origin CXX),default)
CXX    = g++
endif

# We need a recent LLVM to compile Verilator
CLANG_CC  ?= clang
CLANG_CXX ?= clang++
ifneq (${CLANG_PATH},)
	CLANG_CXXFLAGS := "-nostdinc++ -isystem $(CLANG_PATH)/include/c++/v1"
	CLANG_LDFLAGS  := "-L $(CLANG_PATH)/lib -Wl,-rpath,$(CLANG_PATH)/lib -lc++ -nostdlib++"
else
	CLANG_CXXFLAGS := ""
	CLANG_LDFLAGS  := ""
endif

# Default target
all: toolchains riscv-isa-sim verilator

# GCC and LLVM Toolchains
.PHONY: toolchains toolchain-gcc toolchain-llvm toolchain-llvm-main toolchain-llvm-newlib toolchain-llvm-rt
toolchains: toolchain-gcc toolchain-llvm

toolchain-llvm: REBUILD_LLVM=1
toolchain-llvm: toolchain-llvm-main toolchain-llvm-newlib toolchain-llvm-rt

# GCC ================================================
toolchain-gcc: 
	rm -rf $(ROOT_DIR)/toolchain/riscv-gnu-toolchain
	cd $(ROOT_DIR)/toolchain && \
	git clone --depth 1 --branch $(RISCV_GNU_TOOLCHAIN_TAG) --recursive https://github.com/riscv-collab/riscv-gnu-toolchain.git && \
	cd $(ROOT_DIR)/toolchain/riscv-gnu-toolchain && \
	mkdir -p $(GCC_INSTALL_DIR)
	cd $(ROOT_DIR)/toolchain/riscv-gnu-toolchain && rm -rf build && mkdir -p build && cd build && \
	CC=$(CC) CXX=$(CXX) ../configure --prefix=$(GCC_INSTALL_DIR) --with-arch=rv64gcv --with-cmodel=medlow --enable-multilib && \
	$(MAKE) MAKEINFO=true -j$(shell nproc)

# LLVM ================================================
toolchain-llvm-main:
	if [ "$(REBUILD_LLVM)" = "1" ]; then \
		rm -rf $(ROOT_DIR)/toolchain/riscv-llvm; \
	fi
	if [ ! -d "$(ROOT_DIR)/toolchain/riscv-llvm" ]; then \
		cd $(ROOT_DIR)/toolchain && \
		git clone --depth 1 --recursive --branch $(LLVM_VER) https://github.com/llvm/llvm-project.git riscv-llvm && \
		cd $(ROOT_DIR)/toolchain/riscv-llvm && mkdir -p build && cd build && \
		$(CMAKE) -G Ninja  \
		-DCMAKE_INSTALL_PREFIX=$(LLVM_INSTALL_DIR) \
		-DLLVM_ENABLE_PROJECTS="clang;lld" \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_C_COMPILER=$(CC) \
		-DCMAKE_CXX_COMPILER=$(CXX) \
		-DLLVM_DEFAULT_TARGET_TRIPLE=riscv64-unknown-elf \
		-DLLVM_TARGETS_TO_BUILD="RISCV" \
		../llvm && \
		cd $(ROOT_DIR)/toolchain/riscv-llvm && \
		$(CMAKE) --build build --target install; \
	fi

# Newlib ================================================
toolchain-llvm-newlib: toolchain-llvm-main toolchain-llvm-rt
	rm -rf $(ROOT_DIR)/toolchain/newlib
	cd ${ROOT_DIR}/toolchain && \
	git clone --depth 1 --branch $(NEWLIB_TAG) --recursive https://sourceware.org/git/newlib-cygwin.git newlib
	cd ${ROOT_DIR}/toolchain/newlib && mkdir -p build && cd build && \
	../configure --prefix=${LLVM_INSTALL_DIR} \
	--target=riscv64-unknown-elf \
	CC_FOR_TARGET="${LLVM_INSTALL_DIR}/bin/clang -march=rv64gc -mabi=lp64d -mno-relax -mcmodel=medany -Wno-error-implicit-function-declaration -Wno-error=int-conversion" \
	AS_FOR_TARGET=${LLVM_INSTALL_DIR}/bin/llvm-as \
	AR_FOR_TARGET=${LLVM_INSTALL_DIR}/bin/llvm-ar \
	LD_FOR_TARGET=${LLVM_INSTALL_DIR}/bin/llvm-ld \
	RANLIB_FOR_TARGET=${LLVM_INSTALL_DIR}/bin/llvm-ranlib && \
	make -j$(shell nproc) && \
	make install

# Compiler-RT ================================================
toolchain-llvm-rt: toolchain-llvm-main
	cd $(ROOT_DIR)/toolchain/riscv-llvm/compiler-rt && mkdir -p build && cd build && \
	$(CMAKE) $(ROOT_DIR)/toolchain/riscv-llvm/compiler-rt -G Ninja \
	-DCMAKE_INSTALL_PREFIX=$(LLVM_INSTALL_DIR) \
	-DCMAKE_C_COMPILER_TARGET="riscv64-unknown-elf" \
	-DCMAKE_ASM_COMPILER_TARGET="riscv64-unknown-elf" \
	-DCOMPILER_RT_DEFAULT_TARGET_ONLY=ON \
	-DCOMPILER_RT_BAREMETAL_BUILD=ON \
	-DCOMPILER_RT_BUILD_BUILTINS=ON \
	-DCOMPILER_RT_BUILD_LIBFUZZER=OFF \
	-DCOMPILER_RT_BUILD_MEMPROF=OFF \
	-DCOMPILER_RT_BUILD_PROFILE=OFF \
	-DCOMPILER_RT_BUILD_SANITIZERS=OFF \
	-DCOMPILER_RT_BUILD_XRAY=OFF \
	-DCMAKE_C_COMPILER_WORKS=1 \
	-DCMAKE_CXX_COMPILER_WORKS=1 \
	-DCMAKE_SIZEOF_VOID_P=4 \
	-DCMAKE_C_COMPILER="$(LLVM_INSTALL_DIR)/bin/clang" \
	-DCMAKE_C_FLAGS="-march=rv64gc -mabi=lp64d -mno-relax -mcmodel=medany" \
	-DCMAKE_ASM_FLAGS="-march=rv64gc -mabi=lp64d -mno-relax -mcmodel=medany" \
	-DCMAKE_AR=$(LLVM_INSTALL_DIR)/bin/llvm-ar \
	-DCMAKE_NM=$(LLVM_INSTALL_DIR)/bin/llvm-nm \
	-DCMAKE_RANLIB=$(LLVM_INSTALL_DIR)/bin/llvm-ranlib \
	-DLLVM_CMAKE_DIR=$(LLVM_INSTALL_DIR)/bin/llvm-config
	cd $(ROOT_DIR)/toolchain/riscv-llvm/compiler-rt && \
	$(CMAKE) --build build --target install && \
	ln -s $(LLVM_INSTALL_DIR)/lib/linux $(LLVM_INSTALL_DIR)/lib/clang/$(shell $(LLVM_INSTALL_DIR)/bin/llvm-config --version | cut -d. -f1)/lib | true

# Spike (riscv-isa-sim)
.PHONY: riscv-isa-sim riscv-isa-sim-mod
riscv-isa-sim: ${ISA_SIM_INSTALL_DIR} ${ISA_SIM_MOD_INSTALL_DIR}
riscv-isa-sim-mod: ${ISA_SIM_MOD_INSTALL_DIR}

${ISA_SIM_MOD_INSTALL_DIR}: Makefile patches/0003-riscv-isa-sim-patch ${ISA_SIM_INSTALL_DIR}
	# There are linking issues with the standard libraries when using newer CC/CXX versions to compile Spike.
	# Therefore, here we resort to older versions of the compilers.
	# If there are problems with dynamic linking, use:
	# make riscv-isa-sim LDFLAGS="-static-libstdc++"
	# Spike was compiled successfully using gcc and g++ version 7.2.0.
	cd toolchain/riscv-isa-sim && git stash && git apply ../../patches/0003-riscv-isa-sim-patch && \
	rm -rf build && mkdir -p build && cd build; \
	[ -d dtc ] || git clone https://git.kernel.org/pub/scm/utils/dtc/dtc.git && cd dtc && git checkout $(DTC_COMMIT); \
	make -j$(shell nproc) install SETUP_PREFIX=$(ISA_SIM_MOD_INSTALL_DIR) PREFIX=$(ISA_SIM_MOD_INSTALL_DIR) && \
	PATH=$(ISA_SIM_MOD_INSTALL_DIR)/bin:$$PATH; cd ..; \
	../configure --prefix=$(ISA_SIM_MOD_INSTALL_DIR) \
	--without-boost --without-boost-asio --without-boost-regex && \
	make -j$(shell nproc) && make install; \
	git stash

${ISA_SIM_INSTALL_DIR}: Makefile
	# There are linking issues with the standard libraries when using newer CC/CXX versions to compile Spike.
	# Therefore, here we resort to older versions of the compilers.
	# If there are problems with dynamic linking, use:
	# make riscv-isa-sim LDFLAGS="-static-libstdc++"
	# Spike was compiled successfully using gcc and g++ version 7.2.0.
	cd toolchain/riscv-isa-sim && rm -rf build && mkdir -p build && cd build; \
	[ -d dtc ] || git clone https://git.kernel.org/pub/scm/utils/dtc/dtc.git && cd dtc && git checkout $(DTC_COMMIT); \
	make -j$(shell nproc) install SETUP_PREFIX=$(ISA_SIM_INSTALL_DIR) PREFIX=$(ISA_SIM_INSTALL_DIR) && \
	PATH=$(ISA_SIM_INSTALL_DIR)/bin:$$PATH; cd ..; \
	../configure --prefix=$(ISA_SIM_INSTALL_DIR) \
	--without-boost --without-boost-asio --without-boost-regex && \
	make -j$(shell nproc) && make install

# Verilator
.PHONY: verilator
verilator: ${VERIL_INSTALL_DIR}

${VERIL_INSTALL_DIR}: Makefile
	rm -rf $(ROOT_DIR)/toolchain/verilator
	cd $(ROOT_DIR)/toolchain && \
	git clone --depth 1 --branch ${VERIL_VERSION} https://github.com/verilator/verilator.git
	cd $(ROOT_DIR)/toolchain/verilator && autoconf && \
	CC=$(CLANG_CC) CXX=$(CLANG_CXX) CXXFLAGS=$(CLANG_CXXFLAGS) LDFLAGS=$(CLANG_LDFLAGS) \
		./configure --prefix=$(VERIL_INSTALL_DIR) && make -j$(shell nproc) && make install

# RISC-V Tests
riscv_tests:
	make -C apps j$(shell nproc) riscv_tests && \
	make -C hardware riscv_tests_simc

# Helper targets
.PHONY: clean

clean:
	rm -rf $(INSTALL_DIR)
