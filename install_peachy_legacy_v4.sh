#!/usr/bin/env bash
set -euo pipefail

clear

URL="https://github.com/samuelww043-cpu/Peachy-legacy-edition-/releases/download/Legacy/Peachy_legacy.zip"
ZIP_SHA256="076a652b681b1042ec827564d1fbbe8c2762712d6be0172ee8cefcbd214820b4"

DEST="$HOME/Peachy Legacy"
DESKTOP="$HOME/Desktop"
ZIP="$HOME/Downloads/.Peachy_legacy.zip.part"

WORK="$(mktemp -d)"
UNZIP_DIR="$WORK/unpacked"
RUNTIME_DIR="$WORK/runtime"

cleanup() {
    rm -rf "$WORK"
}
trap cleanup EXIT

mkdir -p "$UNZIP_DIR" "$RUNTIME_DIR"

TOTAL_MB=402

show_cached_progress() {
    local i
    for ((i=1; i<=TOTAL_MB; i++)); do
        printf '\rdownloading peachy %d/%d MB' "$i" "$TOTAL_MB"
        sleep 0.003
    done
    printf '\n'
}

GOOD_ZIP=0
if [ -f "$ZIP" ]; then
    if printf '%s  %s\n' "$ZIP_SHA256" "$ZIP" | sha256sum -c - >/dev/null 2>&1; then
        GOOD_ZIP=1
    fi
fi

if [ "$GOOD_ZIP" -eq 1 ]; then
    show_cached_progress
else
    rm -f "$ZIP"

    curl -fL \
      --retry 20 \
      --retry-delay 2 \
      --retry-all-errors \
      -sS \
      "$URL" \
      -o "$ZIP" &
    CURL_PID=$!

    LAST=-1
    while kill -0 "$CURL_PID" 2>/dev/null; do
        BYTES="$(stat -c%s "$ZIP" 2>/dev/null || echo 0)"
        MB=$(( BYTES / 1048576 ))
        [ "$MB" -gt "$TOTAL_MB" ] && MB="$TOTAL_MB"

        if [ "$MB" -ne "$LAST" ]; then
            printf '\rdownloading peachy %d/%d MB' "$MB" "$TOTAL_MB"
            LAST="$MB"
        fi
        sleep 0.25
    done

    wait "$CURL_PID"

    printf '%s  %s\n' "$ZIP_SHA256" "$ZIP" | sha256sum -c - >/dev/null 2>&1
    printf '\rdownloading peachy %d/%d MB\n' "$TOTAL_MB" "$TOTAL_MB"
fi

echo "installing peachy"

unzip -q "$ZIP" -d "$UNZIP_DIR"

# iPhone/macOS-created ZIPs can contain hidden AppleDouble files such as
# __MACOSX/.../._McPeachy_....tar.xz. Those are metadata, not the archive.
# Pick the largest real .tar.xz and explicitly ignore those hidden copies.
RUNTIME_TAR="$(
    find "$UNZIP_DIR" \
      -type f \
      -name '*.tar.xz' \
      ! -path '*/__MACOSX/*' \
      ! -name '._*' \
      -printf '%s\t%p\n' 2>/dev/null |
    sort -nr |
    head -n 1 |
    cut -f2-
)"

test -n "$RUNTIME_TAR"
xz -t "$RUNTIME_TAR"

tar -xJf "$RUNTIME_TAR" -C "$RUNTIME_DIR"

if [ -d "$RUNTIME_DIR/McPeachy" ]; then
    SOURCE_DIR="$RUNTIME_DIR/McPeachy"
else
    CANDIDATE="$(
        find "$RUNTIME_DIR" \
          -type f \
          -name 'RUN_GAME.sh' \
          ! -path '*/__MACOSX/*' \
          ! -name '._*' \
          -print -quit
    )"
    test -n "$CANDIDATE"
    SOURCE_DIR="$(dirname "$CANDIDATE")"
fi

test -f "$SOURCE_DIR/Minecraft.Client"
test -f "$SOURCE_DIR/RUN_GAME.sh"

chmod +x "$SOURCE_DIR/Minecraft.Client" "$SOURCE_DIR/RUN_GAME.sh"

rm -rf "$DEST"
mkdir -p "$DEST"
cp -a "$SOURCE_DIR/." "$DEST/"

cat > "$DEST/Peachy Legacy" <<'LAUNCH'
#!/usr/bin/env bash
HERE="$(cd "$(dirname "$0")" && pwd)"
exec "$HERE/RUN_GAME.sh" "$@"
LAUNCH

chmod +x \
    "$DEST/Peachy Legacy" \
    "$DEST/RUN_GAME.sh" \
    "$DEST/Minecraft.Client"

mkdir -p "$DESKTOP"

cat > "$DESKTOP/Peachy Legacy.desktop" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Peachy Legacy
Comment=Launch Peachy Legacy
Exec=$DEST/Peachy Legacy
Path=$DEST
Terminal=false
Categories=Game;
StartupNotify=true
EOF

chmod +x "$DESKTOP/Peachy Legacy.desktop"

if command -v gio >/dev/null 2>&1; then
    gio set "$DESKTOP/Peachy Legacy.desktop" metadata::trusted true >/dev/null 2>&1 || true
fi

echo "DONE! check ~/Peachy Legacy for the game and ~/Desktop/Peachy Legacy.desktop for the shortcut launcher"

nohup "$DEST/Peachy Legacy" >"$DEST/launch.log" 2>&1 &
disown 2>/dev/null || true
