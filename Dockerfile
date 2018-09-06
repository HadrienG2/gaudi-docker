# === DOCKER-SPECIFIC HACKERY ===

FROM hgrasland/root-tests:latest-cxx17
LABEL Description="openSUSE Tumbleweed environment for Gaudi" Version="0.1"
CMD bash


# Use my Gaudi package development branch
#
# TODO: Remove this once it's integrated in Spack
#
RUN cd /opt/spack && git fetch HadrienG2 && git checkout gaudi-package

# Build a spack spec for Gaudi
RUN echo "export GAUDI_SPACK_SPEC=gaudi@develop +tests +optional               \
                                      ^ ${ROOT_SPACK_SPEC}" >> ${SETUP_ENV}

# Build Gaudi and its dependencies using Spack
RUN spack build ${GAUDI_SPACK_SPEC}

# Test the Gaudi build
#
# NOTE: Some Gaudi tests do ptrace system calls, which are not allowed in
#       unprivileged docker containers because they leak too much information
#       about the host. You can allow the container to run these tests
#       by passing the "--security-opt=seccomp:unconfined" flag to docker run,
#       but for some strange reason this flag cannot be passed to docker build.
#       Therefore, we disable these tests during the docker image build.
#
# FIXME: Ask the Spack team if the manual env setup can be avoided
#
RUN spack cd --build-dir ${GAUDI_SPACK_SPEC}                                   \
    && cd spack-build                                                          \
    && spack activate py-networkx                                              \
    && spack activate py-nose                                                  \
    && spack load gdb                                                          \
    && spack env gaudi                                                         \
           ctest -j8 -E "(google_auditors\.heapchecker|event_timeout_abort)"

# Install Gaudi
RUN spack install ${GAUDI_SPACK_SPEC}