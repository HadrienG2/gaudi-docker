# === DOCKER-SPECIFIC HACKERY ===

FROM hgrasland/root-tests
LABEL Description="openSUSE Tumbleweed environment for Gaudi" Version="0.1"
CMD bash


# === SYSTEM SETUP ===

# Update the host system
RUN zypper ref && zypper dup -y

# TODO: These are Debian packages. Find the SUSE ones and add missing stuff.
RUN zypper in -y doxygen graphviz libboost-all-dev libcppunit-dev gdb unzip    \
                 libxerces-c-dev uuid-dev libunwind-dev google-perftools       \
                 libgoogle-perftools-dev libjemalloc-dev libncurses5-dev       \
                 ninja-build wget python-nose python-networkx


# === TODO: ADAPT REMAINDER OF GCC63 RECIPE ===


# === FINAL CLEAN UP ===

# Discard the system package cache to save up space
RUN zypper clean