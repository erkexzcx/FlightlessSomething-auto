#!/bin/bash

# Exit immediately on error
set -e

# Check if yq is installed
if ! command -v yq &> /dev/null; then
    echo "yq could not be found. Please install yq."
    exit 1
fi

# Path to the benchmark yml file
BENCHMARK_FILE=$1

if [ -z "$BENCHMARK_FILE" ]; then
    echo "Usage: $0 <path_to_benchmark.yml>"
    exit 1
fi

# Extract some root variables from the benchmark yml file
# camera_snaps_time_between: 0.1 # seconds
# camera_snaps_count: 300        # time_between_camera_snaps * camera_snaps_count = total time of the benchmark
# camera_rotation_pixels: 1000   # pixels (find out with trial and error)
SNAP_TIME=$(yq -r '.camera_snaps_time_between' "$BENCHMARK_FILE")
SNAP_COUNT=$(yq -r '.camera_snaps_count' "$BENCHMARK_FILE")
MOUSE_MOVE=$(yq -r '.camera_rotation_pixels' "$BENCHMARK_FILE")

# Clone the repository
git clone https://github.com/sched-ext/scx.git /tmp/scx || true

# Create scx build target dir
# This means target is shared between builds (different schedulers, different branches)
# so dependencies are not built multiple times and time is saved...
export CARGO_TARGET_DIR=/tmp/scx_cargo_build_target
mkdir -p "$CARGO_TARGET_DIR"

# Device could "sleep", so wake it up
echo mousemove 1000 0 | dotoolc
sleep 5

# Read the benchmark.yml file and process each entry
yq -c '.jobs[]' "$BENCHMARK_FILE" | while read -r benchmark; do
    # Extract branch, build directory, and build command
    branch=$(echo "$benchmark" | yq -r '.branch')
    build_dir=$(echo "$benchmark" | yq -r '.build.dir')
    build_cmd=$(echo "$benchmark" | yq -r '.build.cmd')

    # Change to the temporary directory
    cd "/tmp/scx"

    # Fetch the latest changes
    git fetch origin

    # Checkout the branch
    git reset --hard "origin/$branch"

    # Enter the build directory
    cd "$build_dir"

    # Execute the build command
    eval "$build_cmd"

    # Iterate over each run
    echo "$benchmark" | yq -c '.runs[]' | while read -r run; do
        run_filename=$(echo "$run" | yq -r '.filename')
        run_scheduler=$(echo "$run" | yq -r '.scheduler')
        run_load_cmd=$(echo "$run" | yq -r '.load_cmd')

        # Execute scheduler in the background
        if [ -n "$run_scheduler" ] && [ "$run_scheduler" != "null" ]; then
            eval "sudo $CARGO_TARGET_DIR/$run_scheduler" &
        fi

        # Execute background load command in the background
        if [ -n "$run_load_cmd" ] && [ "$run_load_cmd" != "null" ]; then
            eval "$run_load_cmd" &
        fi

        ######################################################
        # Record benchmark data
        sudo kill -CONT $(pgrep -f 'Cyberpunk2077.exe') # Resume the game
        sleep 1

        echo keydown shift+f2 | dotoolc && sleep 0.2 && echo keyup shift+f2 | dotoolc                # Start recording
        for i in {1..$SNAP_COUNT}; do echo mousemove $MOUSE_MOVE 0 | dotoolc; sleep $SNAP_TIME; done # Snap mouse to the right, by 1000px, for 120 seconds
        echo keydown shift+f2 | dotoolc && sleep 0.2 && echo keyup shift+f2 | dotoolc                # Stop recording

        sleep 1
        sudo kill -STOP $(pgrep -f 'Cyberpunk2077.exe') # Pause the game

        sudo chmod -R 777 /tmp/mangohud_logs/
        rm -rf /tmp/mangohud_logs/*summary.csv
        mv /tmp/mangohud_logs/Cyberpunk2077_*.csv /tmp/mangohud_logs/$run_filename
        ######################################################

        # Kill background load command
        if [ -n "$run_load_cmd" ] && [ "$run_load_cmd" != "null" ]; then
            sudo pkill -f "$run_load_cmd" || true
        fi

        # Kill the scheduler that was running in the background
        if [ -n "$run_scheduler" ] && [ "$run_scheduler" != "null" ]; then
            sudo pkill -f "$run_scheduler" || true
            sleep 5 # Wait for scheduler to fully unregister
        fi
    done
done
