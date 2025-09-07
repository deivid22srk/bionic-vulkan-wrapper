#!/bin/bash
# Mesa Mobile GPU Drivers Build Script
# Supports Linux native and Android cross-compilation with mobile optimizations

set -e  # Exit on error

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Default configuration
PLATFORM="linux"
BUILD_TYPE="mobile"
DRIVERS="freedreno,panfrost"
CLEAN_BUILD=false
INSTALL_DEPS=false
ANDROID_NDK_PATH=""
ANDROID_API="28"
BUILD_TOOLS=true
PARALLEL_JOBS=$(nproc)
OUTPUT_DIR="./build"

# Show help
show_help() {
    cat << EOF
Mesa Mobile GPU Drivers Build Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -p, --platform PLATFORM    Target platform (linux, android-arm64, android-arm32)
                               Default: linux
    
    -t, --type TYPE            Build type (mobile, performance, debug, minimal)
                               Default: mobile
    
    -d, --drivers DRIVERS      Comma-separated list of drivers to build
                               Options: freedreno, panfrost, llvmpipe
                               Default: freedreno,panfrost
    
    -c, --clean                Clean build directory before building
    
    -i, --install-deps         Install required dependencies (requires sudo)
    
    -n, --ndk-path PATH        Android NDK path (required for Android builds)
    
    -a, --android-api LEVEL    Android API level (default: 28)
    
    --no-tools                 Don't build debugging tools
    
    -j, --jobs JOBS            Number of parallel jobs (default: $(nproc))
    
    -o, --output DIR           Build output directory (default: ./build)
    
    -h, --help                 Show this help message

BUILD TYPES:
    mobile       - Mobile optimized build with power efficiency focus
    performance  - Maximum performance build with LTO
    debug        - Debug build with symbols and sanitizers
    minimal      - Minimal build with only Freedreno driver

PLATFORMS:
    linux        - Native Linux build (x86_64)
    android-arm64- Android ARM64 (aarch64) cross-compilation
    android-arm32- Android ARM32 (armv7) cross-compilation

EXAMPLES:
    # Linux native mobile-optimized build
    $0 --platform linux --type mobile

    # Android ARM64 performance build
    $0 --platform android-arm64 --type performance --ndk-path ~/Android/ndk/25.2.9519653

    # Debug build with only Freedreno driver
    $0 --type debug --drivers freedreno

    # Install dependencies and build
    $0 --install-deps --clean

ENVIRONMENT VARIABLES:
    The script will set these for mobile optimization builds:
    - TU_ENABLE_MOBILE_OPTIMIZATIONS=1
    - TU_PREFER_GMEM_RENDERING=1
    - TU_ENABLE_LRZ_OPTIMIZATION=1
    - PANFROST_FORCE_AFBC=1
    - PANFROST_ENABLE_TILE_OPTIMIZATION=1

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--platform)
            PLATFORM="$2"
            shift 2
            ;;
        -t|--type)
            BUILD_TYPE="$2"
            shift 2
            ;;
        -d|--drivers)
            DRIVERS="$2"
            shift 2
            ;;
        -c|--clean)
            CLEAN_BUILD=true
            shift
            ;;
        -i|--install-deps)
            INSTALL_DEPS=true
            shift
            ;;
        -n|--ndk-path)
            ANDROID_NDK_PATH="$2"
            shift 2
            ;;
        -a|--android-api)
            ANDROID_API="$2"
            shift 2
            ;;
        --no-tools)
            BUILD_TOOLS=false
            shift
            ;;
        -j|--jobs)
            PARALLEL_JOBS="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Validate platform
case "$PLATFORM" in
    linux|android-arm64|android-arm32)
        ;;
    *)
        log_error "Invalid platform: $PLATFORM"
        log_error "Valid platforms: linux, android-arm64, android-arm32"
        exit 1
        ;;
esac

# Validate build type
case "$BUILD_TYPE" in
    mobile|performance|debug|minimal)
        ;;
    *)
        log_error "Invalid build type: $BUILD_TYPE"
        log_error "Valid types: mobile, performance, debug, minimal"
        exit 1
        ;;
esac

# Check Android NDK for Android builds
if [[ "$PLATFORM" =~ android ]] && [[ -z "$ANDROID_NDK_PATH" ]]; then
    log_error "Android NDK path is required for Android builds"
    log_error "Use --ndk-path option or set ANDROID_NDK_ROOT environment variable"
    exit 1
fi

# Use environment variable if set
if [[ -z "$ANDROID_NDK_PATH" ]] && [[ -n "$ANDROID_NDK_ROOT" ]]; then
    ANDROID_NDK_PATH="$ANDROID_NDK_ROOT"
fi

# Verify NDK path
if [[ "$PLATFORM" =~ android ]] && [[ ! -d "$ANDROID_NDK_PATH" ]]; then
    log_error "Android NDK not found at: $ANDROID_NDK_PATH"
    exit 1
fi

log_info "Mesa Mobile GPU Drivers Build Configuration:"
log_info "  Platform: $PLATFORM"
log_info "  Build Type: $BUILD_TYPE"
log_info "  Drivers: $DRIVERS"
log_info "  Output: $OUTPUT_DIR"
log_info "  Parallel Jobs: $PARALLEL_JOBS"
if [[ "$PLATFORM" =~ android ]]; then
    log_info "  Android NDK: $ANDROID_NDK_PATH"
    log_info "  Android API: $ANDROID_API"
fi

# Install dependencies
install_linux_dependencies() {
    log_info "Installing Linux build dependencies..."
    
    # Check if running as root or with sudo
    if [[ $EUID -eq 0 ]]; then
        APT_CMD="apt-get"
    else
        APT_CMD="sudo apt-get"
    fi
    
    $APT_CMD update -qq
    $APT_CMD install -y \
        build-essential \
        meson \
        ninja-build \
        pkg-config \
        python3-mako \
        python3-packaging \
        python3-ply \
        python3-yaml \
        bison \
        flex \
        ccache \
        libdrm-dev \
        libelf-dev \
        libepoxy-dev \
        libexpat1-dev \
        libffi-dev \
        libpciaccess-dev \
        libudev-dev \
        libvulkan-dev \
        libwayland-dev \
        libx11-dev \
        libx11-xcb-dev \
        libxcb-dri2-0-dev \
        libxcb-dri3-dev \
        libxcb-glx0-dev \
        libxcb-present-dev \
        libxcb-randr0-dev \
        libxcb-shm0-dev \
        libxcb-sync-dev \
        libxcb-xfixes0-dev \
        libxdamage-dev \
        libxext-dev \
        libxfixes-dev \
        libxml2-utils \
        libxrandr-dev \
        libxshmfence-dev \
        libxxf86vm-dev \
        wayland-protocols \
        zlib1g-dev
    
    log_success "Dependencies installed successfully"
}

if [[ "$INSTALL_DEPS" == true ]]; then
    if [[ "$PLATFORM" == "linux" ]]; then
        install_linux_dependencies
    else
        log_warning "Dependency installation only supported for Linux platform"
    fi
fi

# Clean build directory
if [[ "$CLEAN_BUILD" == true ]] && [[ -d "$OUTPUT_DIR" ]]; then
    log_info "Cleaning build directory: $OUTPUT_DIR"
    rm -rf "$OUTPUT_DIR"
fi

# Create build directory
mkdir -p "$OUTPUT_DIR"

# Set up mobile optimization environment variables
if [[ "$BUILD_TYPE" == "mobile" ]]; then
    log_info "Enabling mobile optimization environment variables"
    export TU_ENABLE_MOBILE_OPTIMIZATIONS=1
    export TU_PREFER_GMEM_RENDERING=1
    export TU_ENABLE_LRZ_OPTIMIZATION=1
    export PANFROST_FORCE_AFBC=1
    export PANFROST_ENABLE_TILE_OPTIMIZATION=1
fi

# Create cross-compilation file for Android
create_android_cross_file() {
    local target="$1"
    local abi="$2"
    local cross_file="android-cross-${abi}.txt"
    
    log_info "Creating Android cross-compilation file: $cross_file"
    
    local cpu_family
    local cpu
    case "$abi" in
        "arm64-v8a")
            cpu_family="aarch64"
            cpu="armv8"
            ;;
        "armeabi-v7a")
            cpu_family="arm"
            cpu="armv7"
            ;;
        *)
            log_error "Unsupported Android ABI: $abi"
            exit 1
            ;;
    esac
    
    cat > "$cross_file" << EOF
[binaries]
c = '${ANDROID_NDK_PATH}/toolchains/llvm/prebuilt/linux-x86_64/bin/${target}${ANDROID_API}-clang'
cpp = '${ANDROID_NDK_PATH}/toolchains/llvm/prebuilt/linux-x86_64/bin/${target}${ANDROID_API}-clang++'
ar = '${ANDROID_NDK_PATH}/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-ar'
strip = '${ANDROID_NDK_PATH}/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip'
pkgconfig = 'pkg-config'

[host_machine]
system = 'android'
cpu_family = '$cpu_family'
cpu = '$cpu'
endian = 'little'

[properties]
c_args = ['-fPIC', '-fstack-protector-strong', '-ffunction-sections', '-fdata-sections']
cpp_args = ['-fPIC', '-fstack-protector-strong', '-ffunction-sections', '-fdata-sections']
c_link_args = ['-Wl,--gc-sections', '-Wl,--as-needed']
cpp_link_args = ['-Wl,--gc-sections', '-Wl,--as-needed']
EOF
    
    echo "$cross_file"
}

# Configure meson build
configure_build() {
    log_info "Configuring Mesa build..."
    
    local build_args=()
    
    # Platform-specific configuration
    case "$PLATFORM" in
        "linux")
            build_args+=(
                "-Dplatforms=x11,wayland"
                "-Dgbm=enabled"
                "-Dglx=dri"
                "-Ddri3=enabled"
                "-Dopengl=true"
            )
            ;;
        "android-arm64")
            local cross_file
            cross_file=$(create_android_cross_file "aarch64-linux-android" "arm64-v8a")
            build_args+=(
                "--cross-file=$cross_file"
                "-Dplatforms=android"
                "-Dandroid-stub=true"
                "-Dgbm=disabled"
                "-Dglx=disabled"
                "-Ddri3=disabled"
                "-Dosmesa=false"
                "-Dxmlconfig=disabled"
                "-Dlibunwind=disabled"
            )
            ;;
        "android-arm32")
            local cross_file
            cross_file=$(create_android_cross_file "arm-linux-androideabi" "armeabi-v7a")
            build_args+=(
                "--cross-file=$cross_file"
                "-Dplatforms=android"
                "-Dandroid-stub=true"
                "-Dgbm=disabled"
                "-Dglx=disabled"
                "-Ddri3=disabled"
                "-Dosmesa=false"
                "-Dxmlconfig=disabled"
                "-Dlibunwind=disabled"
            )
            ;;
    esac
    
    # Build type configuration
    case "$BUILD_TYPE" in
        "mobile")
            build_args+=(
                "--buildtype=debugoptimized"
                "-Db_lto=true"
                "-Db_ndebug=if-release"
                "-Doptimization=2"
            )
            ;;
        "performance")
            build_args+=(
                "--buildtype=release"
                "-Db_lto=true"
                "-Db_ndebug=true"
                "-Doptimization=3"
            )
            ;;
        "debug")
            build_args+=(
                "--buildtype=debug"
                "-Doptimization=g"
            )
            ;;
        "minimal")
            build_args+=(
                "--buildtype=release"
                "-Doptimization=s"
                "-Db_lto=false"
            )
            DRIVERS="freedreno"  # Override for minimal build
            ;;
    esac
    
    # Driver configuration
    build_args+=(
        "-Dgallium-drivers=$DRIVERS"
        "-Dvulkan-drivers=$DRIVERS"
    )
    
    # Common configuration
    build_args+=(
        "-Degl=enabled"
        "-Dgles1=enabled"
        "-Dgles2=enabled"
        "-Dshared-glapi=enabled"
        "-Dshader-cache=enabled"
        "-Dvulkan-layers=device-select,overlay"
    )
    
    # Tools configuration
    if [[ "$BUILD_TOOLS" == true ]] && [[ "$BUILD_TYPE" != "minimal" ]]; then
        build_args+=("-Dtools=freedreno,panfrost")
    fi
    
    # LLVM configuration (disable for Android and minimal builds)
    if [[ "$PLATFORM" =~ android ]] || [[ "$BUILD_TYPE" == "minimal" ]]; then
        build_args+=("-Dllvm=disabled")
    fi
    
    log_info "Meson configuration:"
    printf '  %s\n' "${build_args[@]}"
    
    # Run meson setup
    meson setup "$OUTPUT_DIR" "${build_args[@]}"
}

# Build the project
build_project() {
    log_info "Building Mesa with $PARALLEL_JOBS parallel jobs..."
    
    # Use time command to measure build time
    if command -v time &> /dev/null; then
        time ninja -C "$OUTPUT_DIR" -j"$PARALLEL_JOBS"
    else
        ninja -C "$OUTPUT_DIR" -j"$PARALLEL_JOBS"
    fi
    
    log_success "Build completed successfully!"
}

# Validate build results
validate_build() {
    log_info "Validating build results..."
    
    local lib_count
    lib_count=$(find "$OUTPUT_DIR" -name "*.so" -type f | wc -l)
    log_info "Built $lib_count shared libraries"
    
    # Check for specific drivers
    if [[ "$DRIVERS" == *"freedreno"* ]]; then
        local freedreno_files
        freedreno_files=$(find "$OUTPUT_DIR" -name "*freedreno*" -o -name "*turnip*" | wc -l)
        if [[ $freedreno_files -gt 0 ]]; then
            log_success "Freedreno/Turnip driver built successfully ($freedreno_files files)"
        else
            log_warning "Freedreno/Turnip driver files not found"
        fi
    fi
    
    if [[ "$DRIVERS" == *"panfrost"* ]]; then
        local panfrost_files
        panfrost_files=$(find "$OUTPUT_DIR" -name "*panfrost*" -o -name "*panvk*" | wc -l)
        if [[ $panfrost_files -gt 0 ]]; then
            log_success "Panfrost driver built successfully ($panfrost_files files)"
        else
            log_warning "Panfrost driver files not found"
        fi
    fi
    
    # Show build directory size
    local build_size
    build_size=$(du -sh "$OUTPUT_DIR" | cut -f1)
    log_info "Total build size: $build_size"
}

# Generate installation instructions
generate_install_instructions() {
    local install_file="$OUTPUT_DIR/INSTALL_INSTRUCTIONS.txt"
    
    log_info "Generating installation instructions: $install_file"
    
    cat > "$install_file" << EOF
Mesa Mobile GPU Drivers - Installation Instructions
Generated on: $(date)

Build Configuration:
- Platform: $PLATFORM
- Build Type: $BUILD_TYPE
- Drivers: $DRIVERS
- Tools: $BUILD_TOOLS

Installation:

EOF

    case "$PLATFORM" in
        "linux")
            cat >> "$install_file" << 'EOF'
Linux Installation:

1. System-wide installation (requires root):
   sudo cp build/src/**/*.so /usr/lib/x86_64-linux-gnu/
   sudo ldconfig

2. Local installation (recommended):
   export LD_LIBRARY_PATH="$(pwd)/build/src/gallium/targets/dri:$LD_LIBRARY_PATH"
   export LD_LIBRARY_PATH="$(pwd)/build/src/egl:$LD_LIBRARY_PATH"
   
3. Add to shell profile:
   echo 'export LD_LIBRARY_PATH="'$(pwd)'/build/src/gallium/targets/dri:$LD_LIBRARY_PATH"' >> ~/.bashrc

EOF
            ;;
        "android-"*)
            cat >> "$install_file" << 'EOF'
Android Installation:

1. Push libraries to device:
   find build -name "*.so" -exec adb push {} /data/local/tmp/ \;

2. Install to system (requires root):
   adb shell "su -c 'mount -o rw,remount /vendor'"
   adb shell "su -c 'cp /data/local/tmp/*.so /vendor/lib64/hw/'"
   adb shell "su -c 'chmod 644 /vendor/lib64/hw/*.so'"

3. Reboot device:
   adb reboot

EOF
            ;;
    esac
    
    if [[ "$BUILD_TYPE" == "mobile" ]]; then
        cat >> "$install_file" << 'EOF'

Mobile Optimization Environment Variables:
export TU_ENABLE_MOBILE_OPTIMIZATIONS=1
export TU_PREFER_GMEM_RENDERING=1
export TU_ENABLE_LRZ_OPTIMIZATION=1
export PANFROST_FORCE_AFBC=1
export PANFROST_ENABLE_TILE_OPTIMIZATION=1

EOF
    fi
    
    cat >> "$install_file" << 'EOF'
Testing:
- Linux: glxinfo | grep "OpenGL renderer"
- Android: adb shell getprop | grep egl

For more details, see the project documentation.
EOF
}

# Main execution
main() {
    log_info "Starting Mesa Mobile GPU Drivers build..."
    
    # Check required tools
    local required_tools=("meson" "ninja" "pkg-config")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "Required tool not found: $tool"
            if [[ "$tool" == "meson" ]] || [[ "$tool" == "ninja" ]]; then
                log_error "Install with: sudo apt-get install meson ninja-build"
            fi
            exit 1
        fi
    done
    
    # Check ccache
    if command -v ccache &> /dev/null; then
        log_info "Using ccache for faster rebuilds"
        export CC="ccache gcc"
        export CXX="ccache g++"
    fi
    
    configure_build
    build_project
    validate_build
    generate_install_instructions
    
    log_success "Build completed successfully!"
    log_info "Build output: $OUTPUT_DIR"
    log_info "Installation instructions: $OUTPUT_DIR/INSTALL_INSTRUCTIONS.txt"
    
    if [[ "$BUILD_TYPE" == "mobile" ]]; then
        log_info ""
        log_info "Mobile optimizations have been enabled. For best results, set these"
        log_info "environment variables before running applications:"
        log_info "  export TU_ENABLE_MOBILE_OPTIMIZATIONS=1"
        log_info "  export TU_PREFER_GMEM_RENDERING=1"
        log_info "  export TU_ENABLE_LRZ_OPTIMIZATION=1"
        log_info "  export PANFROST_FORCE_AFBC=1"
        log_info "  export PANFROST_ENABLE_TILE_OPTIMIZATION=1"
    fi
}

# Run main function
main "$@"