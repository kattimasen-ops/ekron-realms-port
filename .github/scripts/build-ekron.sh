#!/bin/bash
# ============================================================
# Ekron Realms FPS - Cross-Compile fuer ARM64 / RK3326
# MAXIMALE Performance-Version
# GLIBC 2.31 (ArkOS / R36S / M9 Pro)
# KORRIGIERT: -Fl statt -Fd fuer Library-Suchpfad
# ============================================================
set -e

export DEBIAN_FRONTEND=noninteractive
echo "==> Host arch: $(uname -m)"

# ------------------------------------------------------------
# 1. Multiarch + apt-Quellen
# ------------------------------------------------------------
dpkg --add-architecture arm64

rm -f /etc/apt/sources.list
printf '%s\n' \
  'deb [arch=amd64] http://archive.ubuntu.com/ubuntu focal main restricted universe multiverse' \
  'deb [arch=amd64] http://archive.ubuntu.com/ubuntu focal-updates main restricted universe multiverse' \
  'deb [arch=amd64] http://security.ubuntu.com/ubuntu focal-security main restricted universe multiverse' \
  > /etc/apt/sources.list

mkdir -p /etc/apt/sources.list.d
printf '%s\n' \
  'deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports focal main restricted universe multiverse' \
  'deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports focal-updates main restricted universe multiverse' \
  'deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports focal-security main restricted universe multiverse' \
  > /etc/apt/sources.list.d/arm64.list

apt-get update

# ------------------------------------------------------------
# 2. Cross-Toolchain + ARM64-Bibliotheken
#    HINWEIS: libdecor-0-dev:arm64 existiert NICHT in Focal
# ------------------------------------------------------------
echo "==> Installing cross-toolchain and ARM64 libs"
apt-get install -y --no-install-recommends \
  build-essential git pkg-config pkg-config-aarch64-linux-gnu ca-certificates wget file zip python3 ccache \
  crossbuild-essential-arm64 \
  libsdl2-dev:arm64 libsdl2-image-dev:arm64 libsdl2-mixer-dev:arm64 \
  libsdl2-ttf-dev:arm64 libsdl2-net-dev:arm64 \
  libdbus-1-dev:arm64 libsystemd-dev:arm64 \
  libglib2.0-dev:arm64 \
  libibus-1.0-dev:arm64 \
  libdrm-dev:arm64 libgbm-dev:arm64 libegl1-mesa-dev:arm64 libgles2-mesa-dev:arm64 \
  libgl1-mesa-dev:arm64 libglu1-mesa-dev:arm64 \
  linux-libc-dev:arm64 \
  libfreetype6-dev:arm64 libjpeg-dev:arm64 libpng-dev:arm64 zlib1g-dev:arm64 \
  libogg-dev:arm64 libvorbis-dev:arm64 libopus-dev:arm64 libopusfile-dev:arm64 \
  libopenal-dev:arm64 libspeex-dev:arm64 \
  libx11-dev:arm64 libxext-dev:arm64 libxrender-dev:arm64 libxrandr-dev:arm64 \
  libxcursor-dev:arm64 libxi-dev:arm64 libxfixes-dev:arm64 libxss-dev:arm64 \
  libxxf86vm-dev:arm64 libxtst-dev:arm64 \
  libudev-dev:arm64 libasound2-dev:arm64 libpulse-dev:arm64 \
  libwayland-dev:arm64 \
  libunwind-dev:arm64 liblzma-dev:arm64 libbz2-dev:arm64 \
  libvulkan-dev:arm64

which aarch64-linux-gnu-gcc
aarch64-linux-gnu-gcc --version | head -1

# ------------------------------------------------------------
# 3. pkg-config fuer ARM64 konfigurieren
# ------------------------------------------------------------
export PKG_CONFIG_LIBDIR="/usr/lib/aarch64-linux-gnu/pkgconfig:/usr/share/pkgconfig"
unset PKG_CONFIG_PATH
unset PKG_CONFIG_SYSROOT_DIR

echo "==> pkg-config ARM64 check:"
pkg-config --libs libdrm gbm egl dbus-1 ibus-1.0 2>&1 || echo "WARN: pkg-config check failed"

echo "==> Critical header check:"
for h in /usr/include/libdrm/drm.h \
         /usr/include/xf86drm.h \
         /usr/include/dbus-1.0/dbus/dbus.h \
         /usr/lib/aarch64-linux-gnu/dbus-1.0/include/dbus/dbus-arch-deps.h \
         /usr/include/EGL/egl.h \
         /usr/include/GLES2/gl2.h \
         /usr/include/ibus-1.0/ibus.h \
         /usr/include/ibus-1.0/ibusversion.h; do
  if [ -f "$h" ]; then
    echo "  OK: $h"
  else
    echo "  MISSING: $h"
  fi
done

# ------------------------------------------------------------
# 4. FPC aarch64 Cross-Compiler
#    ppca64 ist ARM64-Binary -> QEMU-binfmt muss aktiv sein!
# ------------------------------------------------------------
echo "==> Setting up FPC aarch64 cross-compiler"

FPC_VERSION="3.2.2"
FPC_AARCH64_URL="https://downloads.freepascal.org/fpc/dist/${FPC_VERSION}/aarch64-linux/fpc-${FPC_VERSION}.aarch64-linux.tar"

wget -q "${FPC_AARCH64_URL}" -O /tmp/fpc-aarch64-wrapper.tar
mkdir -p /opt/fpc-aarch64
tar -xf /tmp/fpc-aarch64-wrapper.tar -C /opt/fpc-aarch64

FPC_CROSS_DIR="/opt/fpc-aarch64/fpc-${FPC_VERSION}.aarch64-linux"

# --- Wrapper-Tarball entpacken ---
BINARY_TAR="${FPC_CROSS_DIR}/binary.aarch64-linux.tar"
if [ ! -f "${BINARY_TAR}" ]; then
  echo "[ERROR] ${BINARY_TAR} nicht gefunden!"
  ls -la "${FPC_CROSS_DIR}/"
  exit 1
fi
tar -xf "${BINARY_TAR}" -C "${FPC_CROSS_DIR}/"

# --- base.aarch64-linux.tar.gz entpacken (enthaelt ppca64 + Units) ---
BASE_TAR="${FPC_CROSS_DIR}/base.aarch64-linux.tar.gz"
if [ ! -f "${BASE_TAR}" ]; then
  echo "[ERROR] ${BASE_TAR} nicht gefunden!"
  ls -la "${FPC_CROSS_DIR}/"
  exit 1
fi
tar -xzf "${BASE_TAR}" -C "${FPC_CROSS_DIR}/"

# --- ppca64-Backend suchen ---
PPCA64_PATH=""
for p in "${FPC_CROSS_DIR}/lib/fpc/${FPC_VERSION}/ppca64" \
         "${FPC_CROSS_DIR}/bin/ppca64" \
         "${FPC_CROSS_DIR}/ppca64" ; do
  if [ -x "$p" ] && [ -f "$p" ]; then
    PPCA64_PATH="$p"
    break
  fi
done

if [ -z "${PPCA64_PATH}" ]; then
  echo "[ERROR] ppca64-Backend nicht gefunden."
  find "${FPC_CROSS_DIR}" -name "ppca64" -type f 2>/dev/null
  exit 1
fi
echo "==> ppca64 gefunden: ${PPCA64_PATH}"

# --- aarch64-Units suchen ---
FPC_UNITS_AARCH64=""
for p in "${FPC_CROSS_DIR}/lib/fpc/${FPC_VERSION}/units/aarch64-linux" \
         "${FPC_CROSS_DIR}/units/aarch64-linux" ; do
  if [ -d "$p" ]; then
    FPC_UNITS_AARCH64="$p"
    break
  fi
done

if [ -z "${FPC_UNITS_AARCH64}" ]; then
  echo "[ERROR] aarch64-Units nicht gefunden."
  find "${FPC_CROSS_DIR}" -type d -name "aarch64-linux" 2>/dev/null
  exit 1
fi
echo "==> aarch64-Units: ${FPC_UNITS_AARCH64}"

# --- ppca64 nach /usr/local/bin kopieren UND Wrapper-Skript erstellen ---
cp "${PPCA64_PATH}" /usr/local/bin/ppca64
chmod +x /usr/local/bin/ppca64

# Wrapper-Skript: ruft fpc mit den richtigen Flags auf
cat > /usr/local/bin/fpc-aarch64 <<'WRAPPER_EOF'
#!/bin/bash
exec fpc -Paarch64 -Tlinux -XP/usr/local/bin/ppca64 "$@"
WRAPPER_EOF
chmod +x /usr/local/bin/fpc-aarch64

export PATH="/usr/local/bin:/usr/local/sbin:${PATH}"

# Verifikation: QEMU-binfmt muss ppca64 ausfuehren koennen
echo "==> Native fpc gefunden: $(command -v fpc)"
fpc -iV

echo "==> ppca64 gefunden: $(command -v ppca64)"
if command -v ppca64 &>/dev/null; then
  if ppca64 -i 2>&1 | head -1; then
    echo "==> ppca64 ist ausfuehrbar (QEMU-binfmt aktiv)"
  else
    echo "[WARN] ppca64 konnte nicht ausgefuehrt werden - QEMU-binfmt fehlt?"
  fi
fi

echo "==> fpc-aarch64 Wrapper: $(command -v fpc-aarch64)"

# ------------------------------------------------------------
# 5. Verzeichnisse
# ------------------------------------------------------------
export SRC_DIR="/work/src"
export OUT_LIBS="/work/out/libs.aarch64"
export PORT_OUT="/work/out/ekron-realms"
mkdir -p "${SRC_DIR}" "${OUT_LIBS}" "${PORT_OUT}"

# ------------------------------------------------------------
# 6. CMake 3.28.3
# ------------------------------------------------------------
echo "==> Installing CMake 3.28.3"
CMAKE_VERSION=3.28.3
wget -q "https://cmake.org/files/v3.28/cmake-${CMAKE_VERSION}-linux-x86_64.tar.gz" -O /tmp/cmake.tar.gz
mkdir -p /opt/cmake
tar -xzf /tmp/cmake.tar.gz -C /opt/cmake --strip-components=1
export PATH=/opt/cmake/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
cmake --version

# ------------------------------------------------------------
# 7. Toolchain-File
# ------------------------------------------------------------
cat > /tmp/aarch64-toolchain.cmake <<'EOF'
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)
set(CMAKE_C_COMPILER aarch64-linux-gnu-gcc)
set(CMAKE_CXX_COMPILER aarch64-linux-gnu-g++)
set(CMAKE_FIND_ROOT_PATH /usr/aarch64-linux-gnu /usr)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
set(ENV{PKG_CONFIG_LIBDIR} "/usr/lib/aarch64-linux-gnu/pkgconfig:/usr/share/pkgconfig")
set(ENV{PKG_CONFIG_SYSROOT_DIR} "/usr/aarch64-linux-gnu")
EOF
export TOOLCHAIN=/tmp/aarch64-toolchain.cmake

# ------------------------------------------------------------
# 8. gl4es
# ------------------------------------------------------------
echo "==> Building gl4es"
cd "${SRC_DIR}"
git clone --depth=1 https://github.com/ptitSeb/gl4es.git
cd gl4es
mkdir -p build && cd build
cmake .. \
  -DCMAKE_TOOLCHAIN_FILE="${TOOLCHAIN}" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_FLAGS="-O3 -mcpu=cortex-a35 -mtune=cortex-a35 -fomit-frame-pointer -ffast-math -ftree-vectorize -fno-plt -I/usr/include/libdrm -I/usr/include/drm" \
  -DNOX11=ON -DGBM=ON -DEGL_WRAPPER=ON \
  -DDEFAULT_ES=2 -DSTATICLIB=OFF
make -j$(nproc)
GL4ES_LIB=$(find "${SRC_DIR}/gl4es" -name libGL.so.1 -print -quit)
EGL_LIB=$(find "${SRC_DIR}/gl4es" -name libEGL.so.1 -print -quit)
cp "${GL4ES_LIB}" "${OUT_LIBS}/libGL.so.1"
cp "${EGL_LIB}"   "${OUT_LIBS}/libEGL.so.1"

# ------------------------------------------------------------
# 9. SDL2
# ------------------------------------------------------------
echo "==> Building SDL2"
cd "${SRC_DIR}"
git clone --depth=1 -b release-2.30.2 https://github.com/libsdl-org/SDL.git
cd SDL
mkdir -p build && cd build
cmake .. \
  -DCMAKE_TOOLCHAIN_FILE="${TOOLCHAIN}" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=/opt/sdl2-aarch64 \
  -DSDL_STATIC=OFF -DSDL_SHARED=ON \
  -DSDL_KMSDRM=ON -DSDL_WAYLAND=OFF \
  -DSDL_X11=ON -DSDL_ALSA=ON -DSDL_PULSEAUDIO=ON \
  -DCMAKE_C_FLAGS="-O3 -mcpu=cortex-a35 -mtune=cortex-a35 -fomit-frame-pointer -ffast-math -ftree-vectorize -fno-plt \
-I/usr/include/libdrm \
-I/usr/include/dbus-1.0 \
-I/usr/lib/aarch64-linux-gnu/dbus-1.0/include \
-I/usr/include/ibus-1.0 \
-I/usr/include/glib-2.0 \
-I/usr/lib/aarch64-linux-gnu/glib-2.0/include"
make -j$(nproc)
make install
SDL2_LIB=$(find /opt/sdl2-aarch64 -name libSDL2-2.0.so.0 -print -quit)
cp "${SDL2_LIB}" "${OUT_LIBS}/libSDL2-2.0.so.0"
cp /usr/lib/aarch64-linux-gnu/libSDL2_ttf-2.0.so.0 "${OUT_LIBS}/" 2>/dev/null || true
cp /usr/lib/aarch64-linux-gnu/libSDL2_image-2.0.so.0 "${OUT_LIBS}/" 2>/dev/null || true
cp /usr/lib/aarch64-linux-gnu/libSDL2_mixer-2.0.so.0 "${OUT_LIBS}/" 2>/dev/null || true

# ------------------------------------------------------------
# 10. Ekron Realms (FPC Cross-Compile) - KORRIGIERT
#     -Fl statt -Fd fuer Library-Suchpfad
# ------------------------------------------------------------
echo "==> Building Ekron Realms FPS (maximized)"
cd "${SRC_DIR}"
git clone --depth=1 https://github.com/ringsce/ekron-realms.git
cd ekron-realms

# --- Submodul-Fix ---
echo "==> Fixing broken submodule tools/SDL2-for-Pascal"
if [ -e "tools/SDL2-for-Pascal" ]; then
  rm -rf "tools/SDL2-for-Pascal"
fi
mkdir -p tools
git clone --depth=1 https://github.com/PascalGameDevelopment/SDL2-for-Pascal.git \
  tools/SDL2-for-Pascal

if [ ! -f "tools/SDL2-for-Pascal/units/sdl2.pas" ]; then
  echo "[ERROR] SDL2-for-Pascal Units nicht gefunden!"
  ls -la tools/SDL2-for-Pascal/
  exit 1
fi

# --- Hauptprogramm EXPLIZIT setzen ---
MAIN_LPR="Projects/realms.lpr"
if [ ! -f "${MAIN_LPR}" ]; then
  echo "[ERROR] ${MAIN_LPR} nicht gefunden!"
  find . -name "*.lpr"
  exit 1
fi
echo "==> Hauptprogramm: ${MAIN_LPR}"

# --- FPC-Aufruf mit Wrapper-Skript ---
fpc-aarch64 \
  -Fu"${FPC_UNITS_AARCH64}" \
  -Fu"${FPC_UNITS_AARCH64}/rtl" \
  -Fu"${FPC_UNITS_AARCH64}/rtl-extra" \
  -Fu"${FPC_UNITS_AARCH64}/rtl-generics" \
  -Fu"${FPC_UNITS_AARCH64}/rtl-objpas" \
  -Fu"${FPC_UNITS_AARCH64}/rtl-unicode" \
  -Fu"${FPC_UNITS_AARCH64}/packages" \
  -Fu"${FPC_UNITS_AARCH64}/packages/base" \
  -Fu"${FPC_UNITS_AARCH64}/packages/fcl-base" \
  -Fu"${FPC_UNITS_AARCH64}/packages/fcl-process" \
  -Fu"${FPC_UNITS_AARCH64}/packages/rtl-extra" \
  -Fu"${FPC_UNITS_AARCH64}/packages/rtl-generics" \
  -Fu"${FPC_UNITS_AARCH64}/packages/rtl-objpas" \
  -Fu"${FPC_UNITS_AARCH64}/packages/rtl-unicode" \
  -Fu"$(pwd)/tools/SDL2-for-Pascal/units" \
  -FuProjects/units -Fuengine -Fugame -Fuqcommon -Fuserver \
  -Furef_gl -Furef_soft -Fuctf -Fuui -Fuclient \
  -Fl/usr/lib/aarch64-linux-gnu \
  -Mdelphi -Scgi \
  -O4 \
  -OoREGVAR,UNCERTAIN,STACKFRAME,PEEPHOLE,LOOPUNROLL,TAILREC,CSE,DFA,STRENGTH,FASTMATH,REMOVEEMPTYPROCS,ORDERFIELDS,CONSTPROP,DEADSTORE,FORCENOSTACKFRAME \
  -CpARMV8 -CfNEON \
  -XX -CX -Xs \
  -OW \
  -k--gc-sections -k-O1 -k--as-needed \
  -o"${PORT_OUT}/ekron" \
  "${MAIN_LPR}"

# --- Build-Output kopieren ---
cp -r * "${PORT_OUT}/" 2>/dev/null || true
find "${PORT_OUT}" -name "*.o" -delete
find "${PORT_OUT}" -name "*.ppu" -delete
find "${PORT_OUT}" -name "*.a" -delete
find "${PORT_OUT}" -name "*.lpi" -delete
find "${PORT_OUT}" -name "*.lpr" -delete
rm -rf "${PORT_OUT}/tools/SDL2-for-Pascal/.git" 2>/dev/null || true

# ------------------------------------------------------------
# 11. Bibliotheken kopieren
# ------------------------------------------------------------
mkdir -p "${PORT_OUT}/libs.aarch64"
cp "${OUT_LIBS}"/*.so* "${PORT_OUT}/libs.aarch64/" 2>/dev/null || true

# ============================================================
# 12. PORTMASTER-DATEIEN GENERIEREN
# ============================================================
echo "==> Generating PortMaster files"

cat > "${PORT_OUT}/Ekron Realms FPS.sh" <<'STARTSCRIPT'
#!/bin/bash
XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}
GAMEDIR="$(cd "$(dirname "$0")" && pwd)"
CUR_DIR="$(pwd)"

if [ -d "/opt/system/Tools/PortMaster" ]; then
  controlfolder="/opt/system/Tools/PortMaster"
elif [ -d "/opt/tools/PortMaster" ]; then
  controlfolder="/opt/tools/PortMaster"
elif [ -d "$XDG_DATA_HOME/PortMaster" ]; then
  controlfolder="$XDG_DATA_HOME/PortMaster"
else
  controlfolder="/roms/ports/PortMaster"
fi

source "$controlfolder/control.txt" 2>/dev/null || true
[ -f "$controlfolder/device_info.txt" ] && source "$controlfolder/device_info.txt"

export SDL_VIDEODRIVER=kmsdrm
export SDL_AUDIODRIVER=alsa
export SDL_HINT_RENDER_DRIVER=opengles2
export SDL_HINT_RENDER_VSYNC=0
export SDL_HINT_KMSDRM_REQUIRE_DRM_MASTER=1
export SDL_HINT_VIDEO_DOUBLE_BUFFER=1
export SDL_VIDEO_GL_DRIVER=libGL.so.1
export SDL_VIDEO_EGL_DRIVER=libEGL.so.1

export LIBGL_FB=1
export LIBGL_ES=2
export LIBGL_GL=21
export LIBGL_SHRINK=4
export LIBGL_MIPMAP=1
export LIBGL_RECYCLEFBO=1
export LIBGL_VSYNC=0
export LIBGL_NOBANNER=1
export LIBGL_NOTEST=1
export LIBGL_NODOWNSAMPLE=1
export LIBGL_XREFRESH=1
export LIBGL_STREAM=0

export MESA_GL_VERSION_OVERRIDE=2.1
export MESA_GLSL_VERSION_OVERRIDE=120
export MESA_EGL_NO_X11=1

for gov in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
  [ -f "$gov" ] && echo performance > "$gov" 2>/dev/null || true
done
for gpu_gov in /sys/class/devfreq/*gpu/governor /sys/class/devfreq/ff400000.gpu/governor; do
  [ -f "$gpu_gov" ] && echo performance > "$gpu_gov" 2>/dev/null || true
done

export LD_LIBRARY_PATH="$GAMEDIR/libs.aarch64:$GAMEDIR:$LD_LIBRARY_PATH"
cd "$GAMEDIR"
> "$GAMEDIR/log.txt" && exec > >(tee "$GAMEDIR/log.txt") 2>&1

echo "=== Ekron Realms FPS (Max Performance) ==="
echo "GAMEDIR: $GAMEDIR"
echo "LD_LIBRARY_PATH: $LD_LIBRARY_PATH"

if [ -f "$GAMEDIR/ekron" ]; then
  "$GAMEDIR/ekron" "$@"
elif [ -f "$GAMEDIR/realms" ]; then
  "$GAMEDIR/realms" "$@"
else
  EXEC=$(find "$GAMEDIR" -maxdepth 1 -type f -executable ! -name "*.sh" ! -name "*.so*" -print -quit)
  if [ -n "$EXEC" ]; then
    "$EXEC" "$@"
  else
    echo "ERROR: Keine ausfuehrbare Datei gefunden!"
    exit 1
  fi
fi
cd "$CUR_DIR"
STARTSCRIPT
chmod +x "${PORT_OUT}/Ekron Realms FPS.sh"

cat > "${PORT_OUT}/port.json" <<'PORTJSON'
{
  "version": 3,
  "name": "ekron-realms.zip",
  "items": [
    "Ekron Realms FPS.sh",
    "ekron",
    "libs.aarch64/",
    "config.cfg",
    "gl4es.cfg",
    "sdl2.cfg"
  ],
  "items_opt": [],
  "attr": {
    "title": "Ekron Realms FPS",
    "porter": "DeinName",
    "desc": "Open-Source Ego-Shooter (Quake-2-Engine, Object Pascal). Maximale ARM64-Performance mit NEON, gl4es und Smart Linking.",
    "desc_md": null,
    "inst": "Alle Dateien enthalten. Einfach starten.",
    "inst_md": null,
    "genres": ["fps"],
    "image": {},
    "rtr": true,
    "exp": false,
    "runtime": null,
    "reqs": [],
    "arch": ["aarch64"],
    "min_glibc": "2.31"
  }
}
PORTJSON

cat > "${PORT_OUT}/gameinfo.xml" <<'GAMEINFO'
<?xml version="1.0"?>
<gameList>
  <game>
    <path>./Ekron Realms FPS.sh</path>
    <name>Ekron Realms FPS</name>
    <desc>Open-Source Ego-Shooter (Quake-2-Engine, Object Pascal). Maximale ARM64-Performance mit NEON, gl4es und Smart Linking.</desc>
    <releasedate>20240101T000000</releasedate>
    <developer>RingsCE</developer>
    <publisher>RingsCE</publisher>
    <genre>FPS</genre>
    <players>1</players>
  </game>
</gameList>
GAMEINFO

cat > "${PORT_OUT}/config.cfg" <<'CONFIGCFG'
# Ekron Realms FPS - Konfiguration fuer RK3326 / ArkOS
[Video]
Width=640
Height=480
Fullscreen=1
VSync=0
FPSLimit=30
Renderer=OpenGL
GLESVersion=2
TextureQuality=High
ShadowQuality=Low
ParticleEffects=High
AntiAliasing=0
AnisotropicFiltering=2
Bloom=On
MotionBlur=Off
DepthOfField=Off
ViewDistance=80
FOV=75

[Audio]
Enabled=1
Volume=80
MusicVolume=60

[Controls]
GamepadEnabled=1
Deadzone=0.15
Sensitivity=1.5
MoveForward=DPAD_UP
MoveBackward=DPAD_DOWN
StrafeLeft=DPAD_LEFT
StrafeRight=DPAD_RIGHT
Fire=BUTTON_A
Jump=BUTTON_B
Crouch=BUTTON_X
Use=BUTTON_Y
Reload=BUTTON_L1
WeaponNext=BUTTON_R1
WeaponPrev=BUTTON_L2
Menu=BUTTON_START

[Performance]
ThreadedRendering=1
Multithreaded=1
CacheSize=64
PreloadAssets=1
CONFIGCFG

cat > "${PORT_OUT}/gl4es.cfg" <<'GL4ESCFG'
# gl4es configuration for RK3326 (Mali-G31 MP2)
LIBGL_FB=1
LIBGL_ES=2
LIBGL_GL=21
LIBGL_SHRINK=4
LIBGL_MIPMAP=1
LIBGL_RECYCLEFBO=1
LIBGL_VSYNC=0
LIBGL_NOBANNER=1
LIBGL_NOTEST=1
LIBGL_NODOWNSAMPLE=1
LIBGL_XREFRESH=1
LIBGL_STREAM=0
GL4ESCFG

cat > "${PORT_OUT}/sdl2.cfg" <<'SDL2CFG'
# SDL2 configuration for RK3326
SDL_VIDEODRIVER=kmsdrm
SDL_AUDIODRIVER=alsa
SDL_HINT_RENDER_DRIVER=opengles2
SDL_HINT_RENDER_OPENGL_SHADERS=1
SDL_HINT_RENDER_VSYNC=0
SDL_HINT_KMSDRM_REQUIRE_DRM_MASTER=1
SDL_HINT_VIDEO_DOUBLE_BUFFER=1
SDL2CFG

# ------------------------------------------------------------
# 13. Finale Ausgabe + Verifikation
# ------------------------------------------------------------
echo "=== Final PortMaster output ==="
ls -la "${PORT_OUT}/"
echo ""
echo "=== libs.aarch64 ==="
ls -la "${PORT_OUT}/libs.aarch64/" 2>/dev/null || true

if [ -f "${PORT_OUT}/ekron" ]; then
  echo ""
  echo "=== Binary verification ==="
  file "${PORT_OUT}/ekron"
  aarch64-linux-gnu-readelf -h "${PORT_OUT}/ekron" | head -20 || true
fi

echo "==> Cross-Compile + PortMaster-Paketierung erfolgreich."
