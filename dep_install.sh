#!/usr/bin/env bash

sudo apt install -y build-essential clang lld llvm autoconf automake libtool libc6-dev git \
python3 python3-pip gawk libgoogle-perftools-dev aptitude needrestart mc curl rsync htop \
iotop iftop tuned net-tools sysstat zstd jq members vnstat cmake ninja-build libglib2.0-dev help2man \
perl libfl2 libfl-dev zlib1g zlib1g-dev bison libbison-dev libgmp-dev libmpfr-dev libmpc-dev \
libyaml-dev pkg-config autotools-dev libusb-1.0-0-dev libcanberra-gtk-module libexpat-dev \
libcanberra-gtk3-module flex texinfo gperf patchutils bc libusb-1.0-0-dev:i386 libftdi-dev \
libftdi1 doxygen libsdl2-dev scons gtkwave libsndfile1-dev libsdl2-ttf-dev libxft2 libxft2:i386 \
lib32ncurses6 libxext6 libxext6:i386 libghc-terminfo-dev python3-dev swig

sudo pip3 install --upgrade pip  
sudo pip3 install --use-pep517 --upgrade pyelftools numpy setuptools setuptools_scm

exit 0
