# Allow build scripts to be referenced without being copied into the final image
FROM scratch AS ctx
COPY build_files /

# Base Image
FROM ghcr.io/ublue-os/bazzite-deck:latest
# --- Stage 1: Builder ---
# Use a standard Fedora image for building. This stage will contain all build tools.
# This image will NOT be part of your final bootc system.
FROM registry.fedoraproject.org/fedora:latest AS builder

# Install build dependencies for huenicorn
# We use 'dnf' as Fedora is the base for Bazzite.
# 'gcc-c++' for the C++ compiler, 'git' for cloning, 'cmake' for configuration, 'make' for building.
# '-devel' packages provide the necessary header files and static libraries for compilation.

# Set the working directory for the build
WORKDIR /app/huenicorn

# Clone the huenicorn repository
RUN git clone https://gitlab.com/openjowelsofts/huenicorn.git .

# Create a build directory and navigate into it
RUN mkdir build && cd build

# Configure the build with CMake
RUN cd build && cmake ..

# Compile the project
RUN cd build && make

# --- Stage 2: Final Bootc Image ---
# Start from your desired Bazzite base image.
# This is the image that will become your bootable OS.
# Choose the specific Bazzite variant you are using (e.g., bazzite-gnome, bazzite-nvidia).
FROM ghcr.io/ublue-os/bazzite-deck:latest

# Install runtime dependencies for huenicorn in the final image.
# These are the shared libraries that huenicorn needs to run.
# Use 'rpm-ostree install' for layering packages on immutable systems like Bazzite.
# Note: rpm-ostree commands are typically run by the build system, not directly as `RUN` instructions
# in a standard Dockerfile/Containerfile for a bootc image.
# However, for simple additions like this, a `RUN` command works during the image build.
# For more complex layering, Universal Blue's image-template often handles this via a `packages` file.
# Since we are directly building the Containerfile, we'll use `dnf` for simplicity in the build context.
# In a true Universal Blue template, you'd add these to a `packages` file or similar mechanism.
# For a direct Containerfile build, we need to ensure these are present.
# Let's assume the base Bazzite image *might* have some, but we'll explicitly install.
RUN dnf install -y curl json-c libusb && \
    dnf clean all

# Copy the compiled huenicorn executable from the 'builder' stage to the final image.
# We'll place it in /usr/local/bin, a common location for custom binaries.
# The 'huenicorn' executable is typically found in the 'build' directory after 'make'.
COPY --from=builder /app/huenicorn/build/huenicorn /usr/local/bin/huenicorn

# (Optional) Add a systemd service if you want huenicorn to run automatically at boot
# For a command-line tool, this might not be necessary, but it shows how to enable services.
# If you want it to run at boot, create 'my_bazzite_huenicorn/systemd/huenicorn.service'
# and add:
# COPY systemd/huenicorn.service /etc/systemd/system/huenicorn.service
# RUN systemctl enable huenicorn.service

# Validate the bootc image (highly recommended for bootc images)
# This command checks for common issues that might prevent the image from booting correctly.
# Bazzite images usually have 'bootc' installed.
RUN bootc container lint
## Other possible base images include:
# FROM ghcr.io/ublue-os/bazzite:latest
# FROM ghcr.io/ublue-os/bluefin-nvidia:stable
# 
# ... and so on, here are more base images
# Universal Blue Images: https://github.com/orgs/ublue-os/packages
# Fedora base image: quay.io/fedora/fedora-bootc:41
# CentOS base images: quay.io/centos-bootc/centos-bootc:stream10

### MODIFICATIONS
## make modifications desired in your image and install packages by modifying the build.sh script
## the following RUN directive does all the things required to run "build.sh" as recommended.


# This will copy everything from your local 'files' directory
# into the root '/' of the image. Since 'files' contains 'usr/local/include',
# it will correctly place your files there.
COPY files/ /

# Add any other customizations here, like installing additional packages
# Example:
# RUN rpm-ostree install my-dev-package && rpm-ostree cleanup -m
# RUN rpm-ostree override replace https://example.com/my-custom-package.rpm



RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build.sh && \
    ostree container commit
    
### LINTING
## Verify final image and contents are correct.
RUN bootc container lint
