# dreamscape-pass — the house FreeRDP, the Mac's RDP client for Mage M. Law: AGENTS.md.

prefix := env_var('HOME') / ".local/opt/dreamscape-pass"

# Configure and build the SDL3 client and the libraries it needs (Apple clang, Homebrew's dependencies).
build:
    CC=/usr/bin/clang CXX=/usr/bin/clang++ cmake -S . -B build -G Ninja \
      -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="{{prefix}}" -DCMAKE_INSTALL_RPATH=@loader_path/../lib \
      -DCMAKE_PREFIX_PATH="/opt/homebrew;/opt/homebrew/opt/openssl@3" -DOPENSSL_ROOT_DIR=/opt/homebrew/opt/openssl@3 \
      -DBUILD_SHARED_LIBS=ON -DBUILD_TESTING=OFF -DWITH_X11=OFF -DWITH_CLIENT_MAC=OFF -DWITH_JPEG=ON \
      -DWITH_MANPAGES=OFF -DWITH_WEBVIEW=OFF -DWITH_CLIENT_SDL=ON -DWITH_CLIENT_SDL2=OFF -DWITH_CLIENT_SDL3=ON \
      -DCHANNEL_RDPEWA=ON -DWITH_SERVER=OFF -DWITH_SAMPLE=OFF -DWITH_PROXY=OFF -DWITH_SHADOW=OFF
    cmake --build build

# Install into the prefix m-desktop prefers, then prove the installed client runs.
install: build
    cmake --install build
    "{{prefix}}/bin/sdl-freerdp" /version

# Start-up probe of the installed client: windows and Space changes against a closed local port (`--spaces 0` for the other mode).
probe *args:
    swift -swift-version 5 house/startup-probe.swift "{{prefix}}/bin/sdl-freerdp" {{args}}

# The same probe for any client binary, e.g. Homebrew's /opt/homebrew/bin/sdl-freerdp (an unpatched client flashes the screen).
probe-binary binary *args:
    swift -swift-version 5 house/startup-probe.swift "{{binary}}" {{args}}

# Where upstream stands: the PR, and the newest release tags.
upstream:
    git fetch -q upstream master --tags
    gh pr view 13564 --repo FreeRDP/FreeRDP --json state,mergedAt,url --jq '"PR #13564 \(.state) merged=\(.mergedAt // "-") \(.url)"'
    git tag --sort=-v:refname --list '3.*' | head -3
