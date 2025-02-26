name: Build

on:
  push:
    branches:
      - 'master'
      - 'releases/**'
      - 'tests/**'
      - 'feature/**'
  pull_request:
  workflow_dispatch:

env:
  BUILD_TYPE: RelWithDebInfo

jobs:

  # Windows MINGW build
  win_mingw:
    runs-on: windows-2022
    name: 🪟 Windows MINGW64

    defaults:
      run:
        shell: msys2 {0}

    env:
      CCACHE_DIR:      "${{ github.workspace }}/.ccache"

    permissions:
      id-token: write
      attestations: write

    steps:
    - name: 🧰 Checkout
      uses: actions/checkout@v4
      with:
        submodules: recursive

    - name: 📜 Setup ccache
      uses:  hendrikmuhs/ccache-action@v1
      id:    cache-ccache
      with:
        key: ${{ runner.os }}-mingw-ccache-${{ github.run_id }}
        restore-keys: ${{ runner.os }}-mingw-ccache
        max-size: 1G

    - name: 🟦 Install msys2
      uses: msys2/setup-msys2@v2
      with:
        msystem: mingw64

    - name: ⬇️ Install dependencies
      run: |
        set -x
        dist/get_deps_msys2.sh

    - name: ⬇️ Install .NET
      uses: actions/setup-dotnet@v4
      with:
        dotnet-version: '8.0.100'

    - name: 📜 Set version variable
      run: |
        echo "IMHEX_VERSION=`cat VERSION`" >> $GITHUB_ENV

    # Windows cmake build
    - name: 🛠️ Configure CMake
      run: |
        set -x
        mkdir -p build
        cd build

        cmake -G "Ninja"                                            \
          -DCMAKE_BUILD_TYPE=${{ env.BUILD_TYPE }}                  \
          -DCMAKE_INSTALL_PREFIX="$PWD/install"                     \
          -DIMHEX_GENERATE_PACKAGE=ON                               \
          -DIMHEX_USE_DEFAULT_BUILD_SETTINGS=ON                     \
          -DIMHEX_PATTERNS_PULL_MASTER=ON                           \
          -DIMHEX_COMMIT_HASH_LONG="${GITHUB_SHA}"                  \
          -DIMHEX_COMMIT_BRANCH="${GITHUB_REF##*/}"                 \
          -DUSE_SYSTEM_CAPSTONE=ON                                  \
          -DIMHEX_GENERATE_PDBS=ON                                  \
          -DIMHEX_REPLACE_DWARF_WITH_PDB=ON                         \
          -DDOTNET_EXECUTABLE="C:/Program Files/dotnet/dotnet.exe"  \
          ..

    - name: 🛠️ Build
      run: |
        cd build
        ninja install

    - name: 🪲 Create PDBs for MSI
      run: |
        cd build
        
        mkdir cv2pdb
        cd cv2pdb
        wget https://github.com/rainers/cv2pdb/releases/download/v0.52/cv2pdb-0.52.zip
        unzip cv2pdb-0.52.zip
        cd ..
        
        cv2pdb/cv2pdb.exe imhex.exe
        cv2pdb/cv2pdb.exe imhex-gui.exe
        cv2pdb/cv2pdb.exe libimhex.dll
        
        for plugin in plugins/*.hexplug; do
          cv2pdb/cv2pdb.exe $plugin
        done
        
        rm -rf cv2pdb

    - name: 📦 Bundle MSI
      run: |
        cd build
        cpack
        mv ImHex-*.msi ../imhex-${{ env.IMHEX_VERSION }}-Windows-x86_64.msi

        echo "ImHex checks for the existence of this file to determine if it is running in portable mode. You should not delete this file" > $PWD/install/PORTABLE

    - name: 🪲 Create PDBs for ZIP
      run: |
        cd build/install

        mkdir cv2pdb
        cd cv2pdb
        wget https://github.com/rainers/cv2pdb/releases/download/v0.52/cv2pdb-0.52.zip
        unzip cv2pdb-0.52.zip
        cd ..
        
        cv2pdb/cv2pdb.exe imhex.exe
        cv2pdb/cv2pdb.exe imhex-gui.exe
        cv2pdb/cv2pdb.exe libimhex.dll
        
        for plugin in plugins/*.hexplug; do
          cv2pdb/cv2pdb.exe $plugin
        done
        
        rm -rf cv2pdb

    - name: 🗝️ Generate build provenance attestations
      uses: actions/attest-build-provenance@v2
      if: ${{ github.event.repository.fork == false && github.event_name != 'pull_request' }}
      with:
        subject-path: |
          imhex-*.msi

    - name: ⬆️ Upload Windows Installer
      uses: actions/upload-artifact@v4
      with:
        if-no-files-found: error
        name: Windows Installer x86_64
        path: |
          imhex-*.msi

    - name: ⬆️ Upload Portable ZIP
      uses: actions/upload-artifact@v4
      with:
        if-no-files-found: error
        name: Windows Portable x86_64
        path: |
          build/install/*

    - name: ⬇️ Download Mesa3D for NoGPU version
      shell: bash
      run: |
        set -x
        echo "NoGPU version Powered by Mesa 3D : https://fdossena.com/?p=mesa%2Findex.frag" > build/install/MESA.md
        curl https://downloads.fdossena.com/geth.php?r=mesa64-latest -L -o mesa.7z
        7z e mesa.7z
        mv opengl32.dll build/install

    - name: ⬆️ Upload NoGPU Portable ZIP
      uses: actions/upload-artifact@v4
      with:
        if-no-files-found: error
        name: Windows Portable NoGPU x86_64
        path: |
          build/install/*

  win_msvc:
    runs-on: windows-2022
    name: 🪟 Windows MSVC

    env:
      CCACHE_DIR:      "${{ github.workspace }}/.ccache"

    permissions:
      id-token: write
      attestations: write

    steps:
      - name: 🧰 Checkout
        uses: actions/checkout@v4
        with:
          submodules: recursive

      - name: 🫧 Setup Visual Studio Dev Environment
        uses: ilammy/msvc-dev-cmd@v1
        with:
          arch: amd64

      - name: 📜 Setup ccache
        uses:  hendrikmuhs/ccache-action@v1
        id:    cache-ccache
        with:
          key: ${{ runner.os }}-msvc-ccache-${{ github.run_id }}
          restore-keys: ${{ runner.os }}-msvc-ccache
          max-size: 1G

      - name: 📦 Install vcpkg
        uses: friendlyanon/setup-vcpkg@v1
        with: { committish: 7e21420f775f72ae938bdeb5e6068f722088f06a }

      - name: ⬇️ Install dependencies
        run: |
          cp dist/vcpkg.json vcpkg.json

      - name: ⬇️ Install CMake and Ninja
        uses: lukka/get-cmake@latest

      - name: ⬇️ Install .NET
        uses: actions/setup-dotnet@v4
        with:
          dotnet-version: '8.0.100'

      - name: 📜 Set version variable
        run: |
          "IMHEX_VERSION=$(Get-Content VERSION -Raw)" | Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append

      # Windows cmake build
      - name: 🛠️ Configure CMake
        run: |
          mkdir -p build
                    
          cmake -G "Ninja" -B build                                                   `
            --preset vs2022                                                           `
            -DCMAKE_TOOLCHAIN_FILE="$env:VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake" `
            -DCMAKE_C_COMPILER="$($(Get-Command cl.exe).Path)"                         `
            -DCMAKE_CXX_COMPILER="$($(Get-Command cl.exe).Path)"                       `
            -DCMAKE_C_COMPILER_LAUNCHER=ccache                                        `
            -DCMAKE_CXX_COMPILER_LAUNCHER=ccache                                      `
            -DCMAKE_BUILD_TYPE="$env:BUILD_TYPE"                                      `
            -DIMHEX_PATTERNS_PULL_MASTER=ON                                           `
            -DIMHEX_COMMIT_HASH_LONG="$env:GITHUB_SHA"                                `
            -DIMHEX_COMMIT_BRANCH="$($env:GITHUB_REF -replace '.*/', '')"             `
            -DDOTNET_EXECUTABLE="C:/Program Files/dotnet/dotnet.exe"                  `
            .

      - name: 🛠️ Build
        run: |
          cd build
          ninja

  win-plugin-template-test:
    runs-on: windows-2022
    name: 🧪 Plugin Template Test

    defaults:
      run:
        shell: msys2 {0}

    needs: win_mingw

    env:
      IMHEX_SDK_PATH: "${{ github.workspace }}/out/sdk"

    steps:
      - name: 🧰 Checkout ImHex
        uses: actions/checkout@v4
        with:
          path: imhex

      - name: 🟦 Install msys2
        uses: msys2/setup-msys2@v2
        with:
          msystem: mingw64

      - name: ⬇️ Install dependencies
        run: |
          set -x
          imhex/dist/get_deps_msys2.sh

      - name: 🧰 Checkout ImHex-Plugin-Template
        uses: actions/checkout@v4
        with:
          repository: WerWolv/ImHex-Plugin-Template
          submodules: recursive
          path: template

      - name: ⬇️ Download artifact
        uses: actions/download-artifact@v4
        with:
          name: Windows Portable x86_64
          path: out

      - name: 🛠️ Build
        run: |
          set -x
          cd template
          mkdir -p build
          cd build
  
          cmake -G "Ninja"                                          \
          -DCMAKE_BUILD_TYPE=${{ env.BUILD_TYPE }}                  \
          -DIMHEX_USE_DEFAULT_BUILD_SETTINGS=ON                     \
          -DUSE_SYSTEM_CAPSTONE=ON                                  \
          ..
          
          ninja

  # MacOS build
  macos-x86:
    runs-on: macos-13

    permissions:
      id-token: write
      attestations: write

    strategy:
      fail-fast: false
      matrix:
        include:
          - suffix: "-NoGPU"
            custom_glfw: true
          - suffix: ""
            custom_glfw: false

    name: 🍎 macOS 13${{ matrix.suffix }}

    steps:
    - name: 🧰 Checkout
      uses: actions/checkout@v4
      with:
        submodules: recursive

    - name: 📜 Set version variable
      run: |
        echo "IMHEX_VERSION=`cat VERSION`" >> $GITHUB_ENV

    - name: 📜 Setup ccache
      uses: hendrikmuhs/ccache-action@v1
      with:
        key: ${{ runner.os }}${{ matrix.suffix }}-ccache-${{ github.run_id }}
        restore-keys: ${{ runner.os }}${{ matrix.suffix }}-ccache
        max-size: 1G

    - name: ⬇️ Install dependencies
      env:
        # Make brew not display useless errors
        HOMEBREW_TESTS: 1
      run: |
        brew reinstall python --quiet || true
        brew link --overwrite --quiet python 2>/dev/null || true
        brew bundle --no-lock --quiet --file dist/macOS/Brewfile || true
        rm -rf /usr/local/Cellar/capstone

    - name: ⬇️ Install classic glfw
      if: ${{! matrix.custom_glfw }}
      run: |
        brew install --quiet glfw || true

    - name: ⬇️ Install .NET
      uses: actions/setup-dotnet@v4
      with:
        dotnet-version: '8.0.100'

    - name: 🧰 Checkout glfw
      if: ${{ matrix.custom_glfw }}
      uses: actions/checkout@v4
      with:
        repository: glfw/glfw
        path: glfw

    # GLFW custom build (to allow software rendering)
    - name: ⬇️ Patch and install custom glfw
      if: ${{ matrix.custom_glfw }}
      run: |
        set -x
        cd glfw
        git apply ../dist/macOS/0001-glfw-SW.patch

        mkdir build
        cd build

        cmake -G "Ninja"                                \
          -DCMAKE_BUILD_TYPE=${{ env.BUILD_TYPE }}      \
          -DBUILD_SHARED_LIBS=ON                        \
          -DCMAKE_C_COMPILER_LAUNCHER=ccache            \
          -DCMAKE_CXX_COMPILER_LAUNCHER=ccache          \
          -DCMAKE_OBJC_COMPILER_LAUNCHER=ccache         \
          -DCMAKE_OBJCXX_COMPILER_LAUNCHER=ccache       \
        ..
        ninja install

    # MacOS cmake build
    - name: 🛠️ Configure CMake
      run: |
        set -x
        mkdir -p build
        cd build
        CC=$(brew --prefix llvm)/bin/clang                                                          \
        CXX=$(brew --prefix llvm)/bin/clang++                                                       \
        OBJC=$(brew --prefix llvm)/bin/clang                                                        \
        OBJCXX=$(brew --prefix llvm)/bin/clang++                                                    \
        PKG_CONFIG_PATH="$(brew --prefix openssl)/lib/pkgconfig":"$(brew --prefix)/lib/pkgconfig"   \
        cmake -G "Ninja"                                                                            \
          -DCMAKE_BUILD_TYPE=${{ env.BUILD_TYPE }}                                                  \
          -DIMHEX_GENERATE_PACKAGE=ON                                                               \
          -DIMHEX_SYSTEM_LIBRARY_PATH="$(brew --prefix llvm)/lib;$(brew --prefix llvm)/lib/unwind;$(brew --prefix llvm)/lib/c++;$(brew --prefix)/lib" \
          -DCMAKE_C_COMPILER_LAUNCHER=ccache                                                        \
          -DCMAKE_CXX_COMPILER_LAUNCHER=ccache                                                      \
          -DCMAKE_OBJC_COMPILER_LAUNCHER=ccache                                                     \
          -DCMAKE_OBJCXX_COMPILER_LAUNCHER=ccache                                                   \
          -DCMAKE_INSTALL_PREFIX="./install"                                                        \
          -DIMHEX_PATTERNS_PULL_MASTER=ON                                                           \
          -DIMHEX_COMMIT_HASH_LONG="${GITHUB_SHA}"                                                  \
          -DIMHEX_COMMIT_BRANCH="${GITHUB_REF##*/}"                                                 \
          ..

    - name: 🛠️ Build
      run: cd build && ninja install

    - name: ✒️ Fix Signature
      run: |
        set -x
        cd build/install
        mv imhex.app ImHex.app
        codesign --remove-signature ImHex.app
        codesign --force --deep --sign - ImHex.app

    - name: 📁 Fix permissions
      run: |
        set -x
        cd build/install
        chmod -R 755 ImHex.app/

    - name: 🔫 Kill XProtect
      run: |
        # See https://github.com/actions/runner-images/issues/7522
        echo Killing XProtect...; sudo pkill -9 XProtect >/dev/null || true;
        echo Waiting for XProtect process...; while pgrep XProtect; do sleep 3; done;

    - name: 📦 Create DMG
      run: |
        brew install graphicsmagick imagemagick
        git clone https://github.com/sindresorhus/create-dmg
        cd create-dmg
        npm i && npm -g i
        cd ../build/install
        for i in $(seq 1 10); do
          create-dmg ImHex.app || true
          if ls -d *.dmg 1>/dev/null 2>/dev/null; then
            break;
          fi
        done
        mv *.dmg ../../imhex-${{ env.IMHEX_VERSION }}-macOS${{ matrix.suffix }}-x86_64.dmg

    - name: 🗝️ Generate build provenance attestations
      uses: actions/attest-build-provenance@v2
      if: ${{ github.event.repository.fork == false && github.event_name != 'pull_request' }}
      with:
        subject-path: |
          ./*.dmg

    - name: ⬆️ Upload DMG
      uses: actions/upload-artifact@v4
      with:
        if-no-files-found: error
        name: macOS DMG${{ matrix.suffix }} x86_64
        path: ./*.dmg

  macos-arm64:
    runs-on: ubuntu-24.04
    name: 🍎 macOS 13 arm64

    outputs:
      IMHEX_VERSION: ${{ steps.build.outputs.IMHEX_VERSION }}

    steps:
    - name: 🧰 Checkout
      uses: actions/checkout@v4
      with:
        submodules: recursive

    - name: 📁 Restore docker /cache
      uses: actions/cache@v4
      with:
        path: cache
        key: build-macos-arm64-cache

    - name: 🐳 Inject /cache into docker
      uses: reproducible-containers/buildkit-cache-dance@v2
      with:
        cache-source: cache
        cache-target: /cache

    - name: 🛠️ Build using docker
      id: build
      run: |
        echo "IMHEX_VERSION=`cat VERSION`" >> $GITHUB_OUTPUT
        docker buildx build . -f dist/macOS/arm64.Dockerfile --progress=plain --build-arg 'JOBS=4' --build-arg "BUILD_TYPE=$(BUILD_TYPE)" --build-context imhex=$(pwd) --output out
        cp resources/dist/macos/Entitlements.plist out/Entitlements.plist

    - name: ⬆️ Upload artifacts
      uses: actions/upload-artifact@v4
      with:
        name: macos_arm64_intermediate
        path: out/

      # See https://github.com/actions/cache/issues/342#issuecomment-1711054115
    - name: 🗑️ Delete old cache
      continue-on-error: true
      env:
        GH_TOKEN: ${{ github.token }}
      run: |
          gh extension install actions/gh-actions-cache
          gh actions-cache delete "build-macos-arm64-cache" --confirm || true

  macos-arm64-package:
    runs-on: macos-13
    name: 🍎 macOS 13 arm64 Packaging
    needs: macos-arm64

    env:
      IMHEX_VERSION: ${{ needs.macos-arm64.outputs.IMHEX_VERSION }}

    permissions:
      id-token: write
      attestations: write

    steps:
      - name: ⬇️ Download artifact
        uses: actions/download-artifact@v4
        with:
          name: macos_arm64_intermediate
          path: out

      - name: 🗑️ Delete artifact
        uses: geekyeggo/delete-artifact@v5
        with:
          name: macos_arm64_intermediate

      - name: ✒️ Fix Signature
        run: |
          set -x
          cd out
          mv imhex.app ImHex.app
          codesign --remove-signature ImHex.app
          codesign --force --deep --entitlements Entitlements.plist --sign - ImHex.app

      - name: 📁 Fix permissions
        run: |
          set -x
          cd out
          chmod -R 755 ImHex.app/

      - name: 🔫 Kill XProtect
        run: |
          # See https://github.com/actions/runner-images/issues/7522
          echo Killing XProtect...; sudo pkill -9 XProtect >/dev/null || true;
          echo Waiting for XProtect process...; while pgrep XProtect; do sleep 3; done;

      - name: 📦 Create DMG
        run: |
          brew install graphicsmagick imagemagick
          git clone https://github.com/sindresorhus/create-dmg
          cd create-dmg
          npm i && npm -g i
          cd ../out
          for i in $(seq 1 10); do
            create-dmg ImHex.app || true
            if ls -d *.dmg 1>/dev/null 2>/dev/null; then
              break;
            fi
          done
          mv *.dmg ../imhex-${{ env.IMHEX_VERSION }}-macOS${{ matrix.suffix }}-arm64.dmg

      - name: 🗝️ Generate build provenance attestations
        uses: actions/attest-build-provenance@v2
        if: ${{ github.event.repository.fork == false && github.event_name != 'pull_request' }}
        with:
          subject-path: |
            ./*.dmg

      - name: ⬆️ Upload DMG
        uses: actions/upload-artifact@v4
        with:
          if-no-files-found: error
          name: macOS DMG arm64
          path: ./*.dmg

  # Ubuntu build
  ubuntu:
    strategy:
      fail-fast: false
      matrix:
        include:
          - release_num: "24.04"
          - release_num: "24.10"

    name: 🐧 Ubuntu ${{ matrix.release_num }}
    runs-on: ubuntu-24.04

    container:
      image: "ubuntu:${{ matrix.release_num }}"
      options: --privileged

    permissions:
      id-token: write
      attestations: write

    steps:
      - name: ⬇️ Install setup dependencies
        run: apt update && apt install -y git curl

      - name: 🧰 Checkout
        uses: actions/checkout@v4
        with:
          submodules: recursive

      - name: 📜 Setup ccache
        uses: hendrikmuhs/ccache-action@v1
        with:
          key: Ubuntu-${{ matrix.release_num }}-ccache-${{ github.run_id }}
          restore-keys: Ubuntu-${{ matrix.release_num }}-ccache
          max-size: 1G

      - name: ⬇️ Install dependencies
        run: |
          apt update
          bash dist/get_deps_debian.sh

      - name: ⬇️ Install .NET
        uses: actions/setup-dotnet@v4
        with:
          dotnet-version: '8.0.100'

      # Ubuntu cmake build
      - name: 🛠️ Configure CMake
        shell: bash
        run: |
          set -x
          git config --global --add safe.directory '*'
          mkdir -p build
          cd build
          CC=gcc-14 CXX=g++-14 cmake -G "Ninja"                       \
            -DCMAKE_BUILD_TYPE=${{ env.BUILD_TYPE }}                  \
            -DCMAKE_INSTALL_PREFIX="/usr"                             \
            -DCMAKE_C_COMPILER_LAUNCHER=ccache                        \
            -DCMAKE_CXX_COMPILER_LAUNCHER=ccache                      \
            -DIMHEX_PATTERNS_PULL_MASTER=ON                           \
            -DIMHEX_COMMIT_HASH_LONG="${GITHUB_SHA}"                  \
            -DIMHEX_COMMIT_BRANCH="${GITHUB_REF##*/}"                 \
            -DIMHEX_ENABLE_LTO=ON                                     \
            -DIMHEX_USE_GTK_FILE_PICKER=ON                            \
            -DDOTNET_EXECUTABLE="dotnet"                              \
            ..

      - name: 🛠️ Build
        run: cd build && DESTDIR=DebDir ninja install

      - name: 📜 Set version variable
        run: |
          echo "IMHEX_VERSION=`cat VERSION`" >> $GITHUB_ENV

      - name: 📦 Bundle DEB
        run: |
          cp -r build/DEBIAN build/DebDir
          dpkg-deb -Zzstd --build build/DebDir
          mv build/DebDir.deb imhex-${{ env.IMHEX_VERSION }}-Ubuntu-${{ matrix.release_num }}-x86_64.deb

      - name: 🗝️ Generate build provenance attestations
        uses: actions/attest-build-provenance@v2
        if: ${{ github.event.repository.fork == false && github.event_name != 'pull_request' }}
        with:
          subject-path: |
            ./*.deb

      - name: ⬆️ Upload DEB
        uses: actions/upload-artifact@v4
        with:
          if-no-files-found: error
          name: Ubuntu ${{ matrix.release_num }} DEB x86_64
          path: '*.deb'

  # AppImage build
  appimage:
    strategy:
      fail-fast: false
      matrix:
        include:
          - architecture: "x86_64"
            architecture_package: "amd64"
            architecture_appimage_builder: "x86_64"
            image: ubuntu-24.04
          - architecture: "arm64"
            architecture_package: "arm64"
            architecture_appimage_builder: "aarch64"
            image: ubuntu-24.04-arm

    runs-on: ${{ matrix.image }}
    name: ⬇️ AppImage ${{ matrix.architecture }}

    permissions:
      id-token: write
      attestations: write

    steps:
      - name: 🧰 Checkout
        uses: actions/checkout@v4
        with:
          submodules: recursive

      - name: 📁 Restore docker /cache
        uses: actions/cache@v4
        with:
          path: cache
          key: appimage-ccache-${{ matrix.architecture }}-${{ github.run_id }}
          restore-keys: appimage-ccache-${{ matrix.architecture }}

      - name: 🐳 Inject /cache into docker
        uses: reproducible-containers/buildkit-cache-dance@v2
        with:
          cache-source: cache
          cache-target: /cache

      - name: 🛠️ Build using docker
        run: |
          docker buildx build . -f dist/AppImage/Dockerfile --progress=plain --build-arg "BUILD_TYPE=$BUILD_TYPE" \
          --build-arg "GIT_COMMIT_HASH=$GITHUB_SHA" --build-arg "GIT_BRANCH=${GITHUB_REF##*/}" \
          --build-arg "ARCHITECTURE_PACKAGE=${{ matrix.architecture_package }}" --build-arg "ARCHITECTURE_FILE_NAME=${{ matrix.architecture }}" --build-arg "ARCHITECTURE_APPIMAGE_BUILDER=${{ matrix.architecture_appimage_builder }}" \
          --output out

      - name: 🗝️ Generate build provenance attestations
        uses: actions/attest-build-provenance@v2
        if: ${{ github.event.repository.fork == false && github.event_name != 'pull_request' }}
        with:
          subject-path: |
            out/*.AppImage
            out/*.AppImage.zsync

      - name: ⬆️ Upload AppImage
        uses: actions/upload-artifact@v4
        with:
          if-no-files-found: error
          name: Linux AppImage ${{ matrix.architecture }}
          path: 'out/*.AppImage'

      - name: ⬆️ Upload AppImage zsync
        uses: actions/upload-artifact@v4
        with:
          if-no-files-found: error
          name: Linux AppImage zsync ${{ matrix.architecture }}
          path: 'out/*.AppImage.zsync'

  # ArchLinux build
  archlinux-build:
    name: 🐧 ArchLinux
    runs-on: ubuntu-24.04

    container:
      image: archlinux:base-devel

    permissions:
      id-token: write
      attestations: write

    steps:
      - name: ⬇️ Update all packages
        run: |
          pacman -Syyu --noconfirm

      - name: ⬇️ Install setup dependencies
        run: |
          pacman -Syu git ccache --noconfirm

      - name: 🧰 Checkout
        uses: actions/checkout@v4
        with:
          submodules: recursive

      - name: ⬇️ Install ImHex dependencies
        run: |
          dist/get_deps_archlinux.sh --noconfirm

      - name: ⬇️ Install .NET
        uses: actions/setup-dotnet@v4
        with:
          dotnet-version: '8.0.100'

      - name: 📜 Setup ccache
        uses: hendrikmuhs/ccache-action@v1
        with:
          key: archlinux-ccache-${{ github.run_id }}
          restore-keys: archlinux-ccache
          max-size: 1G

      # ArchLinux cmake build
      - name: 🛠️ Configure CMake
        run: |
          set -x
          mkdir -p build
          cd build
          CC=gcc CXX=g++ cmake -G "Ninja"               \
          -DCMAKE_BUILD_TYPE=${{ env.BUILD_TYPE }}      \
          -DCMAKE_INSTALL_PREFIX="/usr"                 \
          -DCMAKE_C_COMPILER_LAUNCHER=ccache            \
          -DCMAKE_CXX_COMPILER_LAUNCHER=ccache          \
          -DUSE_SYSTEM_FMT=ON                           \
          -DUSE_SYSTEM_YARA=ON                          \
          -DUSE_SYSTEM_NLOHMANN_JSON=ON                 \
          -DUSE_SYSTEM_CAPSTONE=OFF                     \
          -DIMHEX_PATTERNS_PULL_MASTER=ON               \
          -DIMHEX_COMMIT_HASH_LONG="${GITHUB_SHA}"      \
          -DIMHEX_COMMIT_BRANCH="${GITHUB_REF##*/}"     \
          -DIMHEX_ENABLE_LTO=ON                         \
          -DIMHEX_USE_GTK_FILE_PICKER=ON                \
          ..

      - name: 🛠️ Build
        run: cd build && DESTDIR=installDir ninja install

      - name: 📜 Set version variable
        run: |
          echo "IMHEX_VERSION=`cat VERSION`" >> $GITHUB_ENV

      - name: ✒️ Prepare PKGBUILD
        run: |
          cp dist/Arch/PKGBUILD build
          sed -i 's/%version%/${{ env.IMHEX_VERSION }}/g' build/PKGBUILD

    # makepkg doesn't want to run as root, so I had to chmod 777 all over
      - name: 📦 Package ArchLinux .pkg.tar.zst
        run: |
          set -x
          cd build

          # the name is a small trick to make makepkg recognize it as the source
          # else, it would try to download the file from the release
          tar -cvf imhex-${{ env.IMHEX_VERSION }}-ArchLinux-x86_64.pkg.tar.zst -C installDir .

          chmod -R 777 .

          sudo -u nobody makepkg

          # Replace the old file
          rm imhex-${{ env.IMHEX_VERSION }}-ArchLinux-x86_64.pkg.tar.zst
          rm *imhex-bin-debug* # rm debug package which is created for some reason
          mv *.pkg.tar.zst imhex-${{ env.IMHEX_VERSION }}-ArchLinux-x86_64.pkg.tar.zst

      - name: 🗝️ Generate build provenance attestations
        uses: actions/attest-build-provenance@v2
        if: ${{ github.event.repository.fork == false && github.event_name != 'pull_request' }}
        with:
          subject-path: |
            build/imhex-${{ env.IMHEX_VERSION }}-ArchLinux-x86_64.pkg.tar.zst

      - name: ⬆️ Upload imhex-archlinux.pkg.tar.zst
        uses: actions/upload-artifact@v4
        with:
          if-no-files-found: error
          name: ArchLinux .pkg.tar.zst x86_64
          path: |
            build/imhex-${{ env.IMHEX_VERSION }}-ArchLinux-x86_64.pkg.tar.zst

  # RPM distro builds
  rpm-build:
    strategy:
      fail-fast: false
      matrix:
        include:
          - name: Fedora
            mock_release: rawhide
            release_num: rawhide
            mock_config: fedora-rawhide
          - name: Fedora
            mock_release: f41
            release_num: 41
            mock_config: fedora-41
          - name: Fedora
            mock_release: f40
            release_num: 40
            mock_config: fedora-40
          - name: RHEL-AlmaLinux
            mock_release: epel9
            release_num: 9
            mock_config: "alma+epel-9"

    name: 🐧 ${{ matrix.name }} ${{ matrix.release_num }}
    runs-on: ubuntu-24.04

    container:
      image: "almalinux:9"
      options: --privileged --pid=host --security-opt apparmor=unconfined

    permissions:
      id-token: write
      attestations: write

    steps:
      # This, together with the `--pid=host --security-opt apparmor=unconfined` docker options is required to allow
      # fedpkg to work inside a Docker container running on Ubuntu again.
      # GitHub seems to have enabled AppArmor on their Ubuntu CI runners which limits Docker in ways that cause
      # programs inside it to fail.
      # Without this, fedpkg will throw the unhelpful error message 'Insufficient Rights'
      # This step uses nsenter to execute commands on the host that disable AppArmor entirely.
      - name: 🛡️ Disable AppArmor on Host
        run: |
          nsenter -t 1 -m -u -n -i sudo systemctl disable --now apparmor.service
          nsenter -t 1 -m -u -n -i sudo aa-teardown || true
          nsenter -t 1 -m -u -n -i sudo sysctl --write kernel.apparmor_restrict_unprivileged_unconfined=0
          nsenter -t 1 -m -u -n -i sudo sysctl --write kernel.apparmor_restrict_unprivileged_userns=0

      - name: ⬇️ Install git-core and EPEL repo
        run: dnf install git-core epel-release -y

      - name: 🧰 Checkout
        uses: actions/checkout@v4
        with:
          path: ImHex
          submodules: recursive

      - name: 📜 Setup DNF Cache
        uses: actions/cache@v4
        with:
          path: /var/cache/dnf
          key: ${{ matrix.mock_release }}-dnf-${{ github.run_id }}
          restore-keys: |
            ${{ matrix.mock_release }}-dnf

      - name: ⬇️ Update all packages and install dependencies
        run: |
          set -x
          dnf upgrade -y
          dnf install -y \
          fedpkg         \
          ccache

      - name: ⬇️ Install .NET
        uses: actions/setup-dotnet@v4
        with:
          dotnet-version: '8.0.100'

      - name: 📜 Setup ccache
        uses: hendrikmuhs/ccache-action@v1
        with:
          key: ${{ matrix.mock_release }}-rpm-${{ github.run_id }}
          restore-keys: ${{ matrix.mock_release }}-rpm
          max-size: 1G

      - name: 📜 Set version variable
        run: |
          echo "IMHEX_VERSION=`cat ImHex/VERSION`" >> $GITHUB_ENV

      - name: 🗜️ Create tarball from sources with dependencies
        run: tar --exclude-vcs -czf $GITHUB_WORKSPACE/imhex-$IMHEX_VERSION.tar.gz ImHex

      - name: ✒️ Modify spec file
        run: |
          sed -i \
          -e 's/Version:        VERSION$/Version:        ${{ env.IMHEX_VERSION }}/g'  \
          -e 's/IMHEX_OFFLINE_BUILD=ON/IMHEX_OFFLINE_BUILD=OFF/g'                     \
          -e '/IMHEX_OFFLINE_BUILD=OFF/a -D IMHEX_PATTERNS_PULL_MASTER=ON \\'         \
          -e '/BuildRequires:  cmake/a BuildRequires:  git-core'                      \
          -e '/%files/a %{_datadir}/%{name}/'                                         \
          $GITHUB_WORKSPACE/ImHex/dist/rpm/imhex.spec

      - name: 📜 Fix ccache on EL9
        if: matrix.mock_release == 'epel9'
        run: sed -i '/\. \/opt\/rh\/gcc-toolset-14\/enable/a PATH=/usr/lib64/ccache:$PATH' $GITHUB_WORKSPACE/ImHex/dist/rpm/imhex.spec

      - name: 🟩 Copy spec file to build root
        run: mv $GITHUB_WORKSPACE/ImHex/dist/rpm/imhex.spec $GITHUB_WORKSPACE/imhex.spec

      - name: 📜 Enable ccache for mock
        run: |
          cat <<EOT > $GITHUB_WORKSPACE/mock.cfg
          include('${{ matrix.mock_config }}-x86_64.cfg')
          config_opts['plugin_conf']['ccache_enable'] = True
          config_opts['plugin_conf']['ccache_opts']['max_cache_size'] = '1G'
          config_opts['plugin_conf']['ccache_opts']['compress'] = True
          config_opts['plugin_conf']['ccache_opts']['dir'] = "$GITHUB_WORKSPACE/.ccache"
          EOT

      # Fedora cmake build (in imhex.spec)
      - name: 📦 Build RPM
        run: |
          fedpkg --path $GITHUB_WORKSPACE --release ${{ matrix.mock_release }} mockbuild --enable-network -N --root $GITHUB_WORKSPACE/mock.cfg extra_args -- -v

      - name: 🟩 Move and rename finished RPM
        run: |
          mv $GITHUB_WORKSPACE/results_imhex/${{ env.IMHEX_VERSION }}/*/imhex-${{ env.IMHEX_VERSION }}-0.*.x86_64.rpm \
          $GITHUB_WORKSPACE/imhex-${{ env.IMHEX_VERSION }}-${{ matrix.name }}-${{ matrix.release_num }}-x86_64.rpm

      - name: 🗝️ Generate build provenance attestations
        uses: actions/attest-build-provenance@v2
        if: ${{ github.event.repository.fork == false && github.event_name != 'pull_request' }}
        with:
          subject-path: |
            imhex-${{ env.IMHEX_VERSION }}-${{ matrix.name }}-${{ matrix.release_num }}-x86_64.rpm

      - name: ⬆️ Upload RPM
        uses: actions/upload-artifact@v4
        with:
          if-no-files-found: error
          name: ${{ matrix.name }} ${{ matrix.release_num }} RPM x86_64
          path: |
            imhex-${{ env.IMHEX_VERSION }}-${{ matrix.name }}-${{ matrix.release_num }}-x86_64.rpm

  webassembly-build:
    runs-on: ubuntu-24.04
    name: 🌍 Web
    permissions:
      pages: write
      id-token: write
      actions: write
    steps:
      - name: 🧰 Checkout
        uses: actions/checkout@v4
        with:
          submodules: recursive

      - name: 📁 Restore docker /cache
        uses: actions/cache@v4
        with:
          path: cache
          key: web-cache-${{ hashFiles('**/CMakeLists.txt') }}

      - name: 🐳 Inject /cache into docker
        uses: reproducible-containers/buildkit-cache-dance@v2
        with:
          cache-source: cache
          cache-target: /cache

      - name: 🛠️ Build using docker
        run: |
          docker buildx build . -f dist/web/Dockerfile --progress=plain --build-arg 'JOBS=4' --output out --target raw

      - name: 🔨 Fix permissions
        run: |
          chmod -c -R +rX "out/"

      - name: ⬆️ Upload artifacts
        uses: actions/upload-pages-artifact@v3
        with:
          path: out/

      - name: 🔨 Copy necessary files
        run: |
          cp dist/web/serve.py out/start_imhex_web.py

      - name: ⬆️ Upload package
        uses: actions/upload-artifact@v4
        with:
          if-no-files-found: error
          name: ImHex Web
          path: out/*

        # See https://github.com/actions/cache/issues/342#issuecomment-1711054115
      - name: 🗑️ Delete old cache
        continue-on-error: true
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          gh extension install actions/gh-actions-cache || true
          gh actions-cache delete "build-web-cache" --confirm || true

  webassembly-deploy:
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    permissions:
      pages: write
      id-token: write
      actions: write
    name: 📃 Deploy to GitHub Pages
    runs-on: ubuntu-24.04

    if: ${{ github.ref == 'refs/heads/master' && github.event.repository.fork == false }}
    needs: webassembly-build

    steps:
      - name: 🌍 Deploy WebAssembly Build to GitHub Pages
        id: deployment
        uses: actions/deploy-pages@v4

      - name: 🗑️ Delete artifact
        uses: geekyeggo/delete-artifact@v5
        with:
          name: github-pages
