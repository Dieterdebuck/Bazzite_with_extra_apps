# Allow build scripts to be referenced without being copied into the final image
# This is a special "scratch" stage often used in Universal Blue's image-template.
# It serves as a temporary place to copy build helper scripts (like `build.sh`)
# that are then mounted into later stages, but are not part of the final image.
FROM scratch AS ctx
COPY build_files /

# --- Stage 1: Builder ---
# This stage is dedicated to COMPILING the 'huenicorn' application.
# It uses a full Fedora image because compilation requires various development tools,
# compilers (gcc-c++), and header files (-devel packages).
# IMPORTANT: This stage's image and tools are TEMPORARY and will NOT be part of your final bootc system.
FROM registry.fedoraproject.org/fedora:latest AS builder

# Ensure .gnupg directory exists and has correct permissions for dnf/gpg operations
# This might help with the "can't create directory '/root/.gnupg'" error
RUN mkdir -p /root/.gnupg && chmod 700 /root/.gnupg

# Add RPM Fusion repositories.
RUN dnf install -y \
    https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
    https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm \
    && dnf update -y

# Copy any necessary custom files into the builder stage.
COPY files/ /

# Install ALL necessary build dependencies for huenicorn.
# Check for 'asio-devel' package as it's the one that causes issues, but it should be correct for build.
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
# Clone the huenicorn source code from its Git repository.
RUN git clone https://gitlab.com/openjowelsofts/huenicorn.git .
# Create a 'build' directory, navigate into it, configure the build with CMake, and then compile the project with Make.
RUN mkdir build && cd build && cmake .. && make


# --- Stage 2: Final Bootc Image ---
FROM ghcr.io/ublue-os/bazzite-deck:latest

# Add RPM Fusion repositories to the final image for runtime libraries.
RUN dnf install -y \
    https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
    https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm \
    && dnf update -y

# Install ONLY runtime dependencies for huenicorn.
# We're removing the packages that were already reported as "installed".
# For 'asio', the runtime library is often part of 'asio-devel' itself,
# or it might be called 'boost-asio' if it's part of Boost.
# Given 'nlohmann-json-devel' is header-only and has no runtime, 'asio' might be similar,
# or its runtime is simply not packaged separately as 'asio'.
# Let's remove 'asio' from the runtime install list, as the build error "No match for argument: asio"
# suggests a dedicated runtime package 'asio' does not exist.
# The 'asio-devel' package *does* provide the necessary headers and static libs for linking.
RUN dnf install -y --skip-unavailable \
    ffmpeg \             # Likely needed
    gstreamer1-plugins-base \ # Likely needed
    libva \              # Likely needed
    libvdpau \           # Likely needed
    mesa-libGL \         # Likely needed
    libdrm \             # Likely needed
    libXext \            # Likely needed
    libXrandr \          # Likely needed
    && \
    dnf clean all

# Copy the compiled huenicorn executable from the 'builder' stage to the final image.
COPY --from=builder /app/huenicorn/build/huenicorn /usr/local/bin/huenicorn

# Set up the systemd service for huenicorn.
RUN mkdir -p /etc/systemd/system/
COPY systemd/huenicorn.service /etc/systemd/system/huenicorn.service
RUN systemctl enable huenicorn.service

# Validate the bootc image.
RUN bootc container lint

# --- Universal Blue Template Boilerplate ---
# Commented out as before, unless you are actively using the build.sh script.
# RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
#     --mount=type=cache,dst=/var/cache \
#     --mount=type=cache,dst=/var/log \
#     --mount=type=tmpfs,dst=/tmp \
#     /ctx/build.sh && \
#     ostree container commit
