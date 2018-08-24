# === DOCKER-SPECIFIC HACKERY ===

FROM hgrasland/root-tests:latest-cxx17
LABEL Description="openSUSE Tumbleweed environment for Gaudi" Version="0.1"
CMD bash


# === SYSTEM SETUP ===

# Switch to a development branch of Spack where all required packages are in
#
# FIXME: Remove this once everything is integrated.
#
RUN cd /opt/spack && git fetch HadrienG2 && git checkout gaudi-deps

# List of Gaudi's build requirements, as a Spack spec
#
# NOTE: We are using tabs to allow ourselves to separate the packages later on
#       without disturbing Spack along the way.
#
# NOTE: We cannot test with Intel VTune in Docker because that is proprietary.
#
# TODO: Try adding pocl later on to see if it can make the OpenCL example work.
#
ENV GAUDI_SPACK_CDEPS="aida \t boost@1.67.0+python \t clhep \t cmake \t        \
                       cppgsl cxxstd=17 \t cppunit \t doxygen+graphviz \t      \
                       gdb \t gperftools \t gsl \t hepmc@3 \t heppdt@2 \t      \
                       intel-tbb \t jemalloc \t libpng \t libunwind \t         \
                       libuuid \t ninja \t python \t range-v3 cxxstd=17 \t     \
                       xerces-c \t zlib"
ENV GAUDI_SPACK_PYDEPS="py-nose \t py-networkx \t py-setuptools"

# Install Gaudi build requirements using spack
RUN spack install ${GAUDI_SPACK_CDEPS} ${GAUDI_SPACK_PYDEPS}

# Bring Gaudi's build dependencies into the global scope
#
# TODO: Try out Spack environments once they have matured, do not forget ROOT.
#
RUN export IFS=$'\t'                                                           \
    && for spec in ${GAUDI_SPACK_PYDEPS}; do spack activate ${spec}; done      \
    && for spec in ${GAUDI_SPACK_CDEPS}; do                                    \
           echo "spack load ${spec}" >> "${SETUP_ENV}";                        \
       done


# TODO: Port the rest to Spack


# === INSTALL RELAX ===

# Downlad and extract RELAX (yes, this file is not actually gzipped)
RUN curl http://lcgpackages.web.cern.ch/lcgpackages/tarFiles/sources/RELAX-root6.tar.gz \
      | tar -x

# Build and install RELAX
RUN cd RELAX && mkdir build && cd build                                        \
    && cmake .. -DROOT_BINARY_PATH=`spack location -i root`/bin                \
                -DCMAKE_CXX_FLAGS="-std=c++17"                                 \
                -DCMAKE_BUILD_TYPE=RelWithDebInfo                              \
    && make -j8 && make install

# Get rid of the RELAX build directory
RUN rm -rf RELAX


# === ATTEMPT A GAUDI TEST BUILD ===

# Clone the Gaudi repository
RUN git clone --origin upstream https://gitlab.cern.ch/gaudi/Gaudi.git

# Patch Gaudi for Boost 1.67 support
#
# FIXME: To be submitted upstream after REQUIRED support is merged.
#
COPY boost-1_67.diff /root/
RUN patch -p1 <boost-1_67.diff && rm boost-1_67.diff

# Patch Gaudi to support versioned ROOT library names
#
# FIXME: Submitted upstream and awaiting integration.
#
COPY support_versioned_root.diff /root/
RUN patch -p1 <support_versioned_root.diff && rm support_versioned_root.diff

# Configure Gaudi
RUN cd Gaudi && mkdir build && cd build                                        \
    && cmake -DGAUDI_DIAGNOSTICS_COLOR=ON -GNinja ..

# Build Gaudi
RUN cd Gaudi/build && ninja

# Test the Gaudi build
#
# NOTE: Some Gaudi tests do ptrace system calls, which are not allowed in
#       unprivileged docker containers because they leak too much information
#       about the host. You can allow the container to run these tests
#       by passing the "--security-opt=seccomp:unconfined" flag to docker run,
#       but for some strange reason this flag cannot be passed to docker build.
#       Therefore, we disable these tests during the docker image build.
#
RUN cd Gaudi/build                                                             \
    && ctest -j8 -E "(google_auditors\.heapchecker|event_timeout_abort)"

# Remove build byproducts to keep image light
RUN cd Gaudi/build && ninja clean