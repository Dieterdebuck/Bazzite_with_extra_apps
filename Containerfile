# Allow build scripts to be referenced without being copied into the final image
# This is a special "scratch" stage often used in Universal Blue's image-template.
# It serves as a temporary place to copy build helper scripts (like `build.sh`)
# that are then mounted into later stages, but are not part of the final image.
FROM scratch AS ctx
COPY build_files /

# --- Stage 1: Builder ---
# This stage is dedicated to COMPILING the 'huenicorn' application.
# It uses a full Fedora image because compilation requires various development tools,
# compilers (gcc-c++) and header files (-devel packages).
# IMPORTANT: This stage's image and tools are TEMPORARY and will NOT be part of your final bootc system.
FROM registry.fedoraproject.org/fedora:latest AS builder

# Ensure .gnupg directory exists and has correct permissions for dnf/gpg operations
# This might help with the "can't create directory '/root/.gnupg'" error in the builder stage.
RUN mkdir -p /root/.gnupg && chmod 700 /root/.gnupg

# Add RPM Fusion repositories for the builder stage.
RUN dnf install -y \
    https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
    https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm \
    && dnf update -y

# Copy any necessary custom files into the builder stage.
COPY files/ /

# Install ALL necessary build dependencies for huenicorn.
RUN dnf update -y && \
    dnf install -y \
        git \
        cmake \
        gcc-c++ \
        make \
        pkgconfig \
        curl-devel \
        json-c-devel \
        libusbx-devel \
        opencv-devel \
        asio-devel \
        nlohmann-json-devel \
        mbedtls-devel \
        libX11-devel \
        glib2-devel \
        pipewire-devel \
        ffmpeg-devel \
        gstreamer1-plugins-base-devel \
        libva-devel \
        libvdpau-devel \
        mesa-libGL-devel \
        libdrm-devel \
        libXext-devel \
        libXrandr-devel \
        glm-devel \
    && \
    dnf clean all

# Set the working directory inside the builder container for huenicorn's source code.
WORKDIR /app/huenicorn

# Set environment variables for more verbose git output and to prevent interactive prompts
ENV GIT_TERMINAL_PROMPT=0
ENV GIT_CURL_VERBOSE=1
# Clone the huenicorn source code from its Git repository.
RUN git clone https://gitlab.com/openjowelsofts/huenicorn.git /app/huenicorn

# Create a 'build' directory, navigate into it, configure the build with CMake, and then compile the project with Make.
WORKDIR /app/huenicorn
RUN mkdir build && cd build && cmake .. && make
RUN ls -l /app/huenicorn/build/


# --- Stage 2: Final Bootc Image ---
# Start from your desired Bazzite base image.
FROM ghcr.io/ublue-os/bazzite-deck:latest

# IMPORTANT: DO NOT use 'dnf install' here for layering packages.
# The Universal Blue template uses a 'packages' file and the 'build.sh' script with 'rpm-ostree'.
# The previous problematic 'RUN dnf install' blocks have been removed from here.

# Copy the compiled huenicorn executable from the 'builder' stage to the final image.
COPY --from=builder /app/huenicorn/build/huenicorn /usr/local/bin/huenicorn

# Copy the webroot directory to a shared location where the service can find it.
COPY --from=builder /app/huenicorn/webroot /usr/local/share/huenicorn/webroot

# Set up the systemd service for huenicorn.
RUN mkdir -p /etc/systemd/system/ # Only needed if /etc/systemd/system/ doesn't exist, but safe to keep.
COPY systemd/huenicorn.service /etc/systemd/system/huenicorn.service
RUN systemctl enable huenicorn.service

# Validate the bootc image.
RUN bootc container lint

# --- Universal Blue Template Boilerplate ---
# THIS SECTION MUST BE UNCOMMENTED AND USED FOR PACKAGE LAYERING
# It uses the 'packages' file (see below for 'packages' file content).
# This is how packages are properly layered onto an immutable OS like Bazzite.
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build.sh && \
    ostree container commit
