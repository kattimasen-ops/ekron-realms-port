name: Build Ekron Realms FPS (RK3326 / ARM64 - Max Performance)

on:
  push:
    branches: [ main, master ]
  workflow_dispatch:

jobs:
  build-aarch64:
    runs-on: ubuntu-22.04
    steps:
      - name: Repository auschecken (ohne Submodule)
        uses: actions/checkout@v4
        with:
          submodules: false

      - name: Cross-Compile im FPC 3.2.2 Container
        run: |
          docker run --rm \
            -v "${{ github.workspace }}:/work" \
            -w /work \
            freepascal/fpc:3.2.2-focal-full \
            bash /work/.github/scripts/build-ekron.sh

      - name: Build-Artefakte hochladen
        uses: actions/upload-artifact@v4
        with:
          name: ekron-realms-rk3326-aarch64
          path: out/ekron-realms/
          if-no-files-found: error
