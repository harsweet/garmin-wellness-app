#!/bin/bash
# macOS helper: always build with the hackathon's SDK, even if a newer one is selected.
set -euo pipefail

action="${1:-run}"
case "$action" in
    build|run|test) ;;
    *) echo "Usage: $0 [build|run|test]" >&2; exit 1 ;;
esac

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
ciq_dir="$HOME/Library/Application Support/Garmin/ConnectIQ"
sdk_path="${CIQ_SDK_PATH:-}"

if [ -z "$sdk_path" ]; then
    for candidate in "$ciq_dir"/Sdks/connectiq-sdk-mac-9.1.0-*; do
        if [ -x "$candidate/bin/monkeyc" ]; then
            sdk_path="$candidate"
            break
        fi
    done
fi

if [ -z "$sdk_path" ] || [ ! -x "$sdk_path/bin/monkeyc" ]; then
    echo "SDK 9.1.0 not found. Install it with Garmin SDK Manager or set CIQ_SDK_PATH." >&2
    exit 1
fi
sdk_version="$(tr -d '\r\n' < "$sdk_path/bin/version.txt")"
if [ "$sdk_version" != "9.1.0" ]; then
    echo "Expected SDK 9.1.0, found $sdk_version. Check CIQ_SDK_PATH." >&2
    exit 1
fi
if [ ! -d "$ciq_dir/Devices/fenix7pro" ]; then
    echo "Install Fenix 7 Pro (fenix7pro) in Garmin SDK Manager's Devices tab." >&2
    exit 1
fi

developer_key="${CIQ_DEVELOPER_KEY:-$HOME/Documents/developer_key}"
if [ ! -f "$developer_key" ]; then
    echo "Developer key not found. Set CIQ_DEVELOPER_KEY to your existing key file." >&2
    exit 1
fi

cd "$project_dir"
mkdir -p bin
output="bin/ChairHeist.prg"
compiler_args=(-f monkey.jungle -d fenix7pro -y "$developer_key" -w -l 3)
if [ "$action" = "test" ]; then
    output="bin/ChairHeist-tests.prg"
    compiler_args+=(-t)
fi
echo "Building Chair Heist for fenix7pro with SDK $sdk_version..."
"$sdk_path/bin/monkeyc" "${compiler_args[@]}" -o "$output"

if [ "$action" != "build" ]; then
    "$sdk_path/bin/connectiq"
    # Wait for Garmin's simulator service (the SDK uses ports 1234 through 1238).
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
        echo "Simulator did not become ready. Check the Connect IQ Simulator window and retry." >&2
        exit 1
    fi
    echo "Launching on the Fenix 7 Pro simulator."
    if [ "$action" = "test" ]; then
        # SDK 9.1.0 can return 1 even after Run No Evil reports all tests passed.
        # Require the runner's explicit success summary rather than its exit code.
        test_log="$project_dir/bin/test-results.log"
        set +e
        "$sdk_path/bin/monkeydo" "$project_dir/$output" fenix7pro -t 2>&1 | tee "$test_log"
        set -e
        if /usr/bin/grep -Eq '^PASSED \(passed=[1-9][0-9]*, failed=0, errors=0\)' "$test_log"; then
            exit 0
        fi
        echo "Heist tests did not report a passing result. See bin/test-results.log." >&2
        exit 1
    fi
    exec "$sdk_path/bin/monkeydo" "$project_dir/$output" fenix7pro
fi
