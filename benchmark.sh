#!/bin/bash

# Exit immediately on error
set -e

# Check if yq is installed
if ! command -v yq &> /dev/null; then
    echo "yq could not be found. Please install yq."
    exit 1
fi

# Path to the benchmark.yml file
BENCHMARK_FILE=$1

if [ -z "$BENCHMARK_FILE" ]; then
    echo "Usage: $0 <path_to_benchmark.yml>"
    exit 1
fi

# Clone the repository
git clone https://github.com/sched-ext/scx.git /tmp/scx || true

# Create scx build target dir
# This means target is shared between builds (different schedulers, different branches)
# so dependencies are not built multiple times and time is saved...
export CARGO_TARGET_DIR=/tmp/scx_cargo_build_target
mkdir -p "$CARGO_TARGET_DIR"

# Read the benchmark.yml file and process each entry
yq -c '.[]' "$BENCHMARK_FILE" | while read -r benchmark; do
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
        run_cmd=$(echo "$run" | yq -r '.cmd')

        # Execute scheduler in the background
        if [ -n "$run_cmd" ]; then
            eval "sudo $CARGO_TARGET_DIR/$run_cmd" &
        fi

        ######################################################
        # Record benchmark data
        sudo kill -CONT $(pgrep -f 'Cyberpunk2077.exe') # Resume the game
        sleep 1

        echo keydown shift+f2 | dotoolc && sleep 0.2 && echo keyup shift+f2 | dotoolc # Start recording
        for i in {1..300}; do echo mousemove 1000 0 | dotoolc; sleep 0.1; done        # Move mouse (camera) to the right, by 1000px
        echo keydown shift+f2 | dotoolc && sleep 0.2 && echo keyup shift+f2 | dotoolc # Stop recording

        sleep 1
        sudo kill -STOP $(pgrep -f 'Cyberpunk2077.exe') # Pause the game

        sudo chmod -R 777 /tmp/mangohud_logs/
        rm -rf /tmp/mangohud_logs/*summary.csv
        mv /tmp/mangohud_logs/Cyberpunk2077_*.csv /tmp/mangohud_logs/$run_filename
        ######################################################

        # Kill the scheduler that was running in the background
        if [ -n "$run_cmd" ]; then
            sudo pkill -f "$run_cmd" || true
            sleep 5 # Wait for scheduler to fully unregister
        fi
    done
done
