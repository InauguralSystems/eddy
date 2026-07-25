# Self-contained dev/CI image for eddy.
#
# eddy is a *consumer* of EigenScript that also carries an EXTERNAL oracle: the
# store and DST are .eigs programs run against the pinned runtime, and their
# histories are graded by a small Go program built over anishathalye/porcupine.
# So this image needs BOTH the EigenScript runtime (pinned) and a Go toolchain.
# The same image backs Codespaces and CI (devcontainers/ci), so local-green and
# CI-green can't drift. The tag below IS the version pin — bump EIGS_REF to move
# the runtime under the suite.
FROM debian:stable-slim

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        curl \
        default-jre-headless \
        git \
        unzip \
 && rm -rf /var/lib/apt/lists/*

# Elle (transactional-isolation oracle) via the elle-cli standalone uberjar —
# grades the multi-key milestone-2 histories. JRE installed above.
ARG ELLE_CLI_VERSION=0.1.9
RUN curl -fsSL "https://github.com/ligurio/elle-cli/releases/download/${ELLE_CLI_VERSION}/elle-cli-bin-${ELLE_CLI_VERSION}.zip" \
        -o /tmp/elle.zip \
 && unzip -o /tmp/elle.zip -d /tmp/elle >/dev/null \
 && mkdir -p /opt \
 && cp /tmp/elle/target/elle-cli-*-standalone.jar /opt/elle-cli.jar \
 && rm -rf /tmp/elle /tmp/elle.zip
ENV ELLE_JAR=/opt/elle-cli.jar

# Go toolchain (for the Porcupine oracle harness). Pinned tarball rather than
# distro golang so the checker builds against a known-good version.
ARG GO_VERSION=1.23.4
RUN curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" \
        -o /tmp/go.tgz \
 && tar -C /usr/local -xzf /tmp/go.tgz \
 && rm /tmp/go.tgz
ENV PATH="/usr/local/go/bin:${PATH}"

# Build + install EigenScript at the pinned tag (binary on PATH, stdlib under
# /usr/local/lib/eigenscript found relative to the binary).
ARG EIGS_REF=v0.33.0
RUN git clone --depth 1 --branch "${EIGS_REF}" \
        https://github.com/InauguralSystems/EigenScript.git /tmp/eigs \
 && make -C /tmp/eigs install PREFIX=/usr/local CC=gcc \
 && rm -rf /tmp/eigs

WORKDIR /workspaces/eddy
