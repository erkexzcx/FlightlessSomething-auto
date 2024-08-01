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

# Cleanup from previous jobs
sudo rm -rf /tmp/scx*

# Clone the repository
git clone https://github.com/sched-ext/scx.git /tmp/scx

# Read the benchmark.yml file and process each entry
yq -c '.[]' "$BENCHMARK_FILE" | while read -r benchmark; do
    # Extract branch, build directory, and build command
    branch=$(echo "$benchmark" | yq -r '.branch')
    build_dir=$(echo "$benchmark" | yq -r '.build.dir')
    build_cmd=$(echo "$benchmark" | yq -r '.build.cmd')

    # Change to the temporary directory
    cd "/tmp/scx"

    # Checkout the branch
    git reset --hard "$branch"

    # Enter the build directory
    cd "$build_dir"

    # Execute the build command
    eval "$build_cmd"

    # Iterate over each run
    echo "$benchmark" | yq -c '.runs[]' | while read -r run; do
        run_filename=$(echo "$run" | yq -r '.filename')
        run_cmd=$(echo "$run" | yq -r '.cmd')

        # Execute scheduler in the background
        eval "sudo /tmp/scx-$branch/$run_cmd" &

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

        # Kill the background scheduler processes
        sudo pkill -f 'scx_' || true
    done
done
