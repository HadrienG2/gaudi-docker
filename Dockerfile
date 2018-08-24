# === DOCKER-SPECIFIC HACKERY ===

FROM hgrasland/root-tests:latest-cxx17
LABEL Description="openSUSE Tumbleweed environment for Gaudi" Version="0.1"
CMD bash


# === SYSTEM SETUP ===

# List of Gaudi's build requirements, as a Spack spec
#
# NOTE: We cannot test with Intel VTune in Docker because that is proprietary.
#
# FIXME: Add pocl-based OpenCL tests once the pocl spack package is fixed.
#
ENV GAUDI_SPACK_CDEPS="boost@1.67.0+python cmake cppunit doxygen+graphviz gdb  \
                       gperftools gsl heppdt@2 intel-tbb jemalloc libpng       \
                       libunwind libuuid ninja python xerces-c zlib"
ENV GAUDI_SPACK_PYDEPS="py-nose py-networkx py-setuptools"

# Install Gaudi build requirements using spack
RUN spack install ${GAUDI_SPACK_CDEPS} ${GAUDI_SPACK_PYDEPS}

# Bring Gaudi's build dependencies into the global scope
#
# TODO: Try out Spack environments once they have matured, do not forget ROOT.
#
RUN for spec in ${GAUDI_SPACK_PYDEPS}; do spack activate ${spec}; done         \
    && for spec in ${GAUDI_SPACK_CDEPS}; do                                    \
           echo "spack load ${spec}" >> "${SETUP_ENV}";                        \
       done


# TODO: Port the rest to Spack

# === INSTALL C++ GUIDELINE SUPPORT LIBRARY ===

# Download the GSL
RUN git clone --depth=1 https://github.com/Microsoft/GSL.git

# Build the GSL
RUN cd GSL && mkdir build && cd build                                          \
    && cmake -GNinja -DCMAKE_BUILD_TYPE=RelWithDebInfo                         \
             -DGSL_CXX_STANDARD=17 ..                                          \
    && ninja

# Check that the GSL build is working properly
RUN cd GSL/build && ctest -j8

# Install the GSL
RUN cd GSL/build && ninja install

# Get rid of the GSL build directory
RUN rm -rf GSL


# === INSTALL RANGE-V3

# Download the range-v3 library (v0.3.5)
RUN git clone --branch=0.3.6 --depth=1                                         \
              https://github.com/ericniebler/range-v3.git

# Build range-v3
RUN cd range-v3 && mkdir build && cd build                                     \
    && cmake -GNinja -DRANGES_CXX_STD=17 .. && ninja

# Check that the range-v3 build is working properly
RUN cd range-v3/build && ctest -j8

# Install range-v3
RUN cd range-v3/build && ninja install

# Get rid of the range-v3 build directory
RUN rm -rf range-v3


# === INSTALL AIDA ===

# Download, extract and delete the AIDA package
RUN mkdir AIDA && cd AIDA                                                      \
    && curl --output aida-3.2.1.zip                                            \
       ftp://ftp.slac.stanford.edu/software/freehep/AIDA/v3.2.1/aida-3.2.1.zip \
    && unzip -q aida-3.2.1.zip                                                 \
    && rm aida-3.2.1.zip

# Install the AIDA headers
RUN cp -r AIDA/src/cpp/AIDA /usr/include/

# Get rid of the rest of the package, we do not need it
RUN rm -rf AIDA


# === INSTALL CLHEP ===

# Download CLHEP
RUN git clone --branch=CLHEP_2_4_1_0 --depth=1                                 \
              https://gitlab.cern.ch/CLHEP/CLHEP.git

# Build CLHEP
RUN cd CLHEP && mkdir build && cd build                                        \
    && cmake -GNinja .. && ninja

# Test our CLHEP build
RUN cd CLHEP/build && ctest -j8

# Install CLHEP
RUN cd CLHEP/build && ninja install

# Get rid of the CLHEP build directory
RUN rm -rf CLHEP


# === INSTALL HEPMC v3 ===

# Download HepMC v3
RUN git clone --depth=1 https://gitlab.cern.ch/hepmc/HepMC3.git

# Build and install HepMC
RUN cd HepMC3 && mkdir build && cd build                                       \
    && cmake -DCMAKE_BUILD_TYPE=RelWithDebInfo ..                              \
    && make -j8 && make install

# Get rid of the HepMC build directory
RUN rm -rf HepMC3


# === INSTALL HEPMC v2 ===

# NOTE: Why are we overwriting our HepMC3 install with a HepMC2 one, you may
#       wonder? The answer has to do with RELAX being hopelessly broken, and
#       expecting the CMake files of HepMC3 together with the headers of HepMC2

# Dowload HepMC v2
RUN git clone --depth=1 https://gitlab.cern.ch/hepmc/HepMC.git

# Build HepMC
RUN cd HepMC && mkdir build && cd build                                        \
    && cmake -Dmomentum=GEV -Dlength=MM .. && make -j8

# Test our build of HepMC
RUN cd HepMC/build && make test -j8

# Install HepMC and remove bits of HepMC3 (ugh...)
RUN cd HepMC/build && make install                                             \
    && rm /usr/local/lib64/libHepMC.so /usr/local/lib64/libHepMC.a

# Get rid of the HepMC build directory
RUN rm -rf HepMC


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

# Configure the run-time linker
#
# NOTE: I am not sure why this is needed for this build specifically, but the
#       Gaudi build will fail to find CLHEP if we don't do it.
#
RUN ldconfig

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