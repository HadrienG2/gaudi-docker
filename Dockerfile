# === DOCKER-SPECIFIC HACKERY ===

FROM hgrasland/root-tests:latest-cxx17
LABEL Description="openSUSE Tumbleweed environment for Gaudi" Version="0.1"
CMD bash


# === SYSTEM SETUP ===

# Use my RELAX package development branch
#
# TODO: Remove this once it's integrated in Spack
#
RUN cd /opt/spack && git fetch HadrienG2 && git checkout relax-package

# List of Gaudi's build requirements, as a Spack spec
#
# NOTE: We are using tabs to allow ourselves to separate the packages later on
#       without disturbing Spack along the way.
#
# NOTE: We cannot test with Intel VTune in Docker because that is proprietary.
#
# TODO: Investigate if pocl can be used without making ROOT's interpreter angry.
#
RUN export TAB=$'\t'                                                           \
    && echo "export GAUDI_SPACK_CDEPS=\"                                       \
                aida $TAB boost@1.67.0+python $TAB clhep $TAB cmake $TAB       \
                cppgsl cxxstd=17 $TAB cppunit $TAB doxygen+graphviz $TAB       \
                gdb $TAB gperftools $TAB gsl $TAB hepmc@2.06.09 $TAB           \
                heppdt@2.06.01 $TAB intel-tbb $TAB jemalloc $TAB libpng $TAB   \
                libunwind $TAB libuuid $TAB ninja $TAB python $TAB             \
                range-v3 cxxstd=17 $TAB relax ^ ${ROOT_SPACK_SPEC} $TAB        \
                xerces-c $TAB zlib                                             \
            \"" >> ${SETUP_ENV}                                                \
    && echo "export GAUDI_SPACK_PYDEPS=\"                                      \
                py-nose $TAB py-networkx $TAB py-setuptools                    \
            \"" >> ${SETUP_ENV}

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

# Use my fork of xenv
#
# FIXME: Remove once the argparse situation is resolved
#
COPY use-xenv-fork.diff /root/
RUN patch -p1 <use-xenv-fork.diff && rm use-xenv-fork.diff

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