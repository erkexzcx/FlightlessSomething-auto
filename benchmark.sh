#!/bin/bash

# Exit immediately on error
set -e

# Path to the benchmark.yml file
BENCHMARK_FILE=$1

# cleanup from previous jobs
sudo rm -rf /tmp/scx*

# Clone the repository
git clone https://github.com/sched-ext/scx.git /tmp/scx

# Read the benchmark.yml file and process each entry
yq e -o=json '.' "$BENCHMARK_FILE" | yq e -c '.[]' - | while read -r benchmark; do
    # Extract branch, build directory, and build command
    branch=$(echo "$benchmark" | yq e -r '.branch' -)
    build_dir=$(echo "$benchmark" | yq e -r '.build.dir' -)
    build_cmd=$(echo "$benchmark" | yq e -r '.build.cmd' -)

    # Create a temporary directory for the branch
    cp -r /tmp/scx "/tmp/scx-$branch"

    # Change to the temporary directory
    cd "/tmp/scx-$branch" || exit

    # Checkout the branch
    git checkout "$branch"

    # Execute the build command
    eval "$build_cmd"

    # Iterate over each run
    echo "$benchmark" | yq e -c '.runs[]' - | while read -r run; do
        run_filename=$(echo "$run" | yq e -r '.filename' -)
        run_cmd=$(echo "$run" | yq e -r '.cmd' -)

        # Execute the run command in the background
        eval "$run_cmd" &

        # Store the PID of the background process
        run_cmd_pid=$!

        ######################################################
        # Record benchmark data
        sleep 1

        echo keydown shift+f2 | dotoolc && sleep 0.2 && echo keyup shift+f2 | dotoolc # Start recording
        for i in {1..300}; do echo mousemove 1000 0 | dotoolc; sleep 0.1; done        # Move mouse (camera) to the right, by 1000px
        echo keydown shift+f2 | dotoolc && sleep 0.2 && echo keyup shift+f2 | dotoolc # Stop recording

        sleep 1

        sudo chmod -R 777 /tmp/mangohud_logs/
        rm -f /tmp/mangohud_logs/*summary.csv
        mv /tmp/mangohud_logs/Cyberpunk2077_*.csv /tmp/mangohud_logs/$run_filename
        ######################################################

        # Kill the background process
        kill $run_cmd_pid || true
    done
done