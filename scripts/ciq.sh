#!/bin/bash
set -euo pipefail

action="${1:-run}"
case "$action" in
    build|run|test) ;;
    *) echo "Usage: $0 [build|run|test]" >&2; exit 1 ;;
esac

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
ciq_dir="$HOME/Library/Application Support/Garmin/ConnectIQ"
sdk_path="${CIQ_SDK_PATH:-}"
if [ -z "$sdk_path" ] && [ -f "$ciq_dir/current-sdk.cfg" ]; then
    sdk_path="$(tr -d '\r\n' < "$ciq_dir/current-sdk.cfg")"
fi
if [ -z "$sdk_path" ] || [ ! -x "$sdk_path/bin/monkeyc" ]; then
    echo "Connect IQ SDK not found. Select an SDK in Garmin SDK Manager or set CIQ_SDK_PATH." >&2
    exit 1
fi
if [ ! -d "$ciq_dir/Devices/fenix7pro" ]; then
    echo "Install the fēnix 7 Pro (fenix7pro) profile in Garmin SDK Manager." >&2
    exit 1
fi

developer_key="${CIQ_DEVELOPER_KEY:-}"
if [ -z "$developer_key" ]; then
    if [ -f "$HOME/Documents/developer_key" ]; then
        developer_key="$HOME/Documents/developer_key"
    else
        developer_key="$project_dir/.local/developer_key.der"
        if [ ! -f "$developer_key" ]; then
            mkdir -p "$project_dir/.local"
            (
                umask 077
                openssl genrsa 4096 2>/dev/null | openssl pkcs8 -topk8 -inform PEM -outform DER -nocrypt -out "$developer_key"
            )
            echo "Created a local development signing key in .local/."
        fi
    fi
fi
if [ ! -f "$developer_key" ]; then
    echo "Developer key not found: $developer_key" >&2
    exit 1
fi

cd "$project_dir"
mkdir -p bin
output="bin/Momo.prg"
compiler_args=(-f monkey.jungle -d fenix7pro -y "$developer_key" -w)
if [ "$action" = "test" ]; then
    output="bin/Momo-tests.prg"
    compiler_args+=(-t)
fi

echo "Building Momo for fēnix 7 Pro..."
"$sdk_path/bin/monkeyc" "${compiler_args[@]}" -o "$output"
if [ "$action" = "build" ]; then
    exit 0
fi

"$sdk_path/bin/connectiq"
ready=false
for attempt in {1..60}; do
    for port in {1234..1238}; do
        if /usr/bin/nc -z -w 1 127.0.0.1 "$port" 2>/dev/null; then
            ready=true
            break
        fi
    done
    if [ "$ready" = true ]; then break; fi
    sleep 0.25
done
if [ "$ready" != true ]; then
    echo "The Connect IQ simulator did not become ready. Open it and retry." >&2
    exit 1
fi

if [ "$action" = "test" ]; then
    test_log="$project_dir/bin/test-results.log"
    set +e
    "$sdk_path/bin/monkeydo" "$project_dir/$output" fenix7pro -t 2>&1 | tee "$test_log"
    set -e
    # SDK 9.1.0 can return 1 even when the test runner reports success.
    if grep -Eq '^PASSED \(passed=[1-9][0-9]*, failed=0, errors=0\)' "$test_log"; then
        exit 0
    fi
    echo "Tests did not report a passing result. See bin/test-results.log." >&2
    exit 1
fi

echo "Launching Momo in the fēnix 7 Pro simulator."
exec "$sdk_path/bin/monkeydo" "$project_dir/$output" fenix7pro
