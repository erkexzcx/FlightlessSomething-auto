#!/bin/bash

# Exit immediately on error
set -e

# Check if yq is installed
if ! command -v yq &> /dev/null; then
    echo "yq could not be found. Please install yq."
    exit 1
fi

# Check if dotoolc command exists
if ! command -v dotoolc &> /dev/null; then
    echo "dotool could not be found. Please install dotool."
    exit 1
fi

# Path to the benchmark yml file
BENCHMARK_FILE=$1

if [ -z "$BENCHMARK_FILE" ]; then
    echo "Usage: $0 <path_to_benchmark.yml>"
    exit 1
fi

# Ensure we have needed permissions
sudo chown $USER /tmp/dotool-pipe

# Ensure cleanup is done
sudo rm -rf /tmp/mangohud_logs
sudo mkdir -p /tmp/mangohud_logs
sudo chmod -R 777 /tmp/mangohud_logs/

# Ensure game is running
pgrep -f 'ForzaHorizon5.exe' > /dev/null

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

# Zoom out max + it wakes device if it's kind of asleep
echo keydown pagedown | dotoolc && sleep 5 && echo keyup pagedown | dotoolc

# Read the benchmark.yml file and process each entry
yq -c '.jobs[]' "$BENCHMARK_FILE" | while read -r benchmark; do
    # Extract reset_to, build directory, and build command
    resetto=$(echo "$benchmark" | yq -r '.reset_to')
    build_dir=$(echo "$benchmark" | yq -r '.build.dir')
    build_cmd=$(echo "$benchmark" | yq -r '.build.cmd')

    # Change to the temporary directory
    cd "/tmp/scx"

    # Fix git behavior?
    git config --global --add safe.directory /tmp/scx

    # Handle PRs differently
    if [[ "$resetto" =~ ^pr/[0-9]+$ ]]; then
        PR_NUMBER=${resetto#pr/}
        git fetch origin pull/$PR_NUMBER/head:pr-$PR_NUMBER
        git reset --hard pr-$PR_NUMBER
    else
        git fetch origin
        git reset --hard "$resetto"
    fi

    # Extract Short Commit Hash
    SCH=$(git --no-pager log -1 --pretty=format:"%h" --abbrev-commit)

    # Enter the build directory
    cd "$build_dir"

    # Execute the build command
    eval "$build_cmd"

    # Iterate over each run
    echo "$benchmark" | yq -c '.runs[]' | while read -r run; do
        run_filename=$(echo "$run" | yq -r '.filename')
        run_scheduler=$(echo "$run" | yq -r '.scheduler')

        # Print information:
        echo -e "\n>> Reset to: $resetto\n>> Scheduler: $run_scheduler\n>> background_load: $BACKGROUND_LOAD"
        git --no-pager log -1 --pretty=format:">> Full commit hash: %H%n>> Short commit hash: %h%n>> Commit message: %s%n" --abbrev-commit

        # Template out filename
        run_filename=$(echo "$run_filename" | sed "s/__SCH__/$SCH/g")

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
        #sudo kill -CONT $(pgrep -f 'ForzaHorizon5.exe') # Resume the game
        sleep 1

        start_time=$(date +%s)

        echo keydown shift+f2 | dotoolc && sleep 0.2 && echo keyup shift+f2 | dotoolc        # Start recording

        # Rotate camera in all directions for $SPIN_DURATION duration
        while (( $(date +%s) - start_time < SPIN_DURATION )); do
            for direction in left down right; do
                echo keydown $direction | dotoolc && sleep 0.1 && echo keyup $direction | dotoolc
                sleep 0.1
            done
        done

        echo keydown shift+f2 | dotoolc && sleep 0.2 && echo keyup shift+f2 | dotoolc        # Stop recording

        sleep 1
        #sudo kill -STOP $(pgrep -f 'ForzaHorizon5.exe') # Pause the game

        sudo chmod -R 777 /tmp/mangohud_logs/
        rm -rf /tmp/mangohud_logs/*summary.csv
        mv /tmp/mangohud_logs/ForzaHorizon5_*.csv /tmp/mangohud_logs/$run_filename
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
