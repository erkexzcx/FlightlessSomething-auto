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
SPIN_DURATION=$(yq -r '.camera_spin_duration' "$BENCHMARK_FILE")

# Background load var
BACKGROUND_LOAD=$(yq -r '.background_load' "$BENCHMARK_FILE")

# Clone the repository
git clone https://github.com/sched-ext/scx.git /tmp/scx || true

# Create scx build target dir
# This means target is shared between builds (different schedulers, different branches)
# so dependencies are not built multiple times and time is saved...
export CARGO_TARGET_DIR=/tmp/scx_cargo_build_target
mkdir -p "$CARGO_TARGET_DIR"

# Zoom out max + it wakes device if it's kind of sleep
echo keydown pagedown | dotoolc && sleep 5 && echo keyup pagedown | dotoolc

# Read the benchmark.yml file and process each entry
yq -c '.jobs[]' "$BENCHMARK_FILE" | while read -r benchmark; do
    # Extract reset_to, build directory, and build command
    resetto=$(echo "$benchmark" | yq -r '.reset_to')
    build_dir=$(echo "$benchmark" | yq -r '.build.dir')
    build_cmd=$(echo "$benchmark" | yq -r '.build.cmd')

    # Change to the temporary directory
    cd "/tmp/scx"

    # Fetch the latest changes
    git fetch origin

    # Checkout the resetto
    git reset --hard "$resetto"

    # Enter the build directory
    cd "$build_dir"

    # Execute the build command
    eval "$build_cmd"

    # Iterate over each run
    echo "$benchmark" | yq -c '.runs[]' | while read -r run; do
        run_filename=$(echo "$run" | yq -r '.filename')
        run_scheduler=$(echo "$run" | yq -r '.scheduler')

        # Execute scheduler in the background
        if [ -n "$run_scheduler" ] && [ "$run_scheduler" != "null" ]; then
            eval "sudo $CARGO_TARGET_DIR/$run_scheduler" &
        fi

        # Execute background load command in the background
        if [ -n "$BACKGROUND_LOAD" ] && [ "$BACKGROUND_LOAD" != "null" ]; then
            eval "$BACKGROUND_LOAD" &
        fi

        ######################################################
        # Record benchmark data
        sudo kill -CONT $(pgrep -f 'bg3.exe') # Resume the game
        sleep 1

        echo keydown shift+f2 | dotoolc && sleep 0.2 && echo keyup shift+f2 | dotoolc        # Start recording
        echo keydown delete | dotoolc && sleep $SPIN_DURATION && echo keyup delete | dotoolc # Rotate camera
        echo keydown shift+f2 | dotoolc && sleep 0.2 && echo keyup shift+f2 | dotoolc        # Stop recording

        sleep 1
        sudo kill -STOP $(pgrep -f 'bg3.exe') # Pause the game

        sudo chmod -R 777 /tmp/mangohud_logs/
        rm -rf /tmp/mangohud_logs/*summary.csv
        mv /tmp/mangohud_logs/bg3_*.csv /tmp/mangohud_logs/$run_filename
        ######################################################

        # Kill background load command
        if [ -n "$BACKGROUND_LOAD" ] && [ "$BACKGROUND_LOAD" != "null" ]; then
            sudo pkill -f "$BACKGROUND_LOAD" || true
        fi

        # Kill the scheduler that was running in the background
        if [ -n "$run_scheduler" ] && [ "$run_scheduler" != "null" ]; then
            sudo pkill -f "$run_scheduler" || true
            sleep 5 # Wait for scheduler to fully unregister
        fi
    done
done
