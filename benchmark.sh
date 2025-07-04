#!/bin/bash
set -e

# Check if required packages are installed
for cmd in yq ydotool git mangohud; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "$cmd could not be found. Please install $cmd."
        exit 1
    fi
done

# Check if required environment variables are set
for var in GAME_EXEC SCX_DIR CARGO_TARGET_DIR BENCHMARKS_DIR GAME_USER; do
    if [ -z "${!var}" ]; then
        echo "Environment variable $var is not set. Please set it before running the script."
        exit 1
    fi
done

# Exit if ${GAME_USER} is root
if [ "$GAME_USER" = "root" ]; then
    echo "Game cannot be executed under root user."
    exit 1
fi

# Path to the benchmark yml file
BENCHMARK_FILE=$1
if [ -z "$BENCHMARK_FILE" ]; then
    echo "Usage: $0 <path_to_benchmark.yml>"
    exit 1
fi

# Ensure game is running
pgrep -f "${GAME_EXEC}" > /dev/null

# Setup ydotool socket
export YDOTOOL_SOCKET="/tmp/ydotool_socket"
sudo pkill -f "ydotoold" || true
sudo rm -f $YDOTOOL_SOCKET
sudo -u "${GAME_USER}" XDG_RUNTIME_DIR="/run/user/$(id -u ${GAME_USER})" ydotoold -p $YDOTOOL_SOCKET &
sleep 1 # Give ydotoold some time to start
sudo chown $USER $YDOTOOL_SOCKET

# Ensure configuration of Mangohud is correct
MANGOHUD_CONF="/home/${GAME_USER}/.config/MangoHud/MangoHud.conf"
sudo -u "${GAME_USER}" sed -i "s|^output_folder=.*|output_folder=${BENCHMARKS_DIR}|" "$MANGOHUD_CONF"
sudo -u "${GAME_USER}" sed -i "s/^log_duration=.*/log_duration=9999/" "$MANGOHUD_CONF"
sudo -u "${GAME_USER}" sed -i "s/^autostart_log=.*/autostart_log=0/" "$MANGOHUD_CONF"
sudo -u "${GAME_USER}" sed -i "s/^log_interval=.*/log_interval=0/" "$MANGOHUD_CONF"
sudo -u "${GAME_USER}" sed -i "s/^toggle_logging=.*/toggle_logging=Shift_L+F2/" "$MANGOHUD_CONF"

# Cleanup if any previous logs exist
sudo mkdir -p ${BENCHMARKS_DIR}
sudo rm -rf ${BENCHMARKS_DIR}/*
sudo chmod -R 777 ${BENCHMARKS_DIR}

# Remove/Disable any scx scheduler in case it's still running
sudo systemctl disable --now scx.service || true
sudo pkill -f "scx" || true

# Clone the repository
git config --global --add safe.directory "${SCX_DIR}"
git clone https://github.com/sched-ext/scx.git "${SCX_DIR}" || true

# Ensure scx build target dir exists
mkdir -p "$CARGO_TARGET_DIR"

# Extract some root variables from the benchmark yml file
SPIN_DURATION=$(yq -r '.camera_spin_duration' "$BENCHMARK_FILE")

# Background load var
BACKGROUND_LOAD=$(yq -r '.background_load' "$BENCHMARK_FILE")

# Read the benchmark.yml file and process each entry
yq -c '.jobs[]' "$BENCHMARK_FILE" | while read -r benchmark; do
    # Extract reset_to, build directory, and build command
    resetto=$(echo "$benchmark" | yq -r '.reset_to')
    build_dir=$(echo "$benchmark" | yq -r '.build.dir')
    build_cmd=$(echo "$benchmark" | yq -r '.build.cmd')

    # Change to the temporary directory
    cd "${SCX_DIR}"

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

    # Above build command might have been long, or for whatever reason the device has gone to sleep.
    # Without waking it up first, mangohud record shortcut might not get picked up.
    # This command acts as a wake-up call.
    #
    ydotool mousemove -x 1 -y 0

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
        sudo kill -CONT $(pgrep -f "${GAME_EXEC}") # Resume the game

        sleep 1
        ydotool key --key-delay=200 42:1 60:1 60:0 42:0 # Start recording

        # Rotate camera in all directions for $SPIN_DURATION duration
        for ((i = 0; i < SPIN_DURATION; i++)); do
            for ((j = 0; j < 1000; j++)); do
                ydotool mousemove -x 1 -y 0
                sleep 0.001
            done
        done

        ydotool key --key-delay=200 42:1 60:1 60:0 42:0 # Stop recording
        sleep 1

        sudo kill -STOP $(pgrep -f "${GAME_EXEC}") # Pause the game

        # Mangohud changes permissions of the dir, which causes sequential benchmark not to
        # generate a CSV file, therefore script fails. This is needed after each run.
        sudo chmod -R 777 "${BENCHMARKS_DIR}"

        sudo rm -rf ${BENCHMARKS_DIR}/*summary.csv
        sudo mv ${BENCHMARKS_DIR}/${GAME_EXEC%.exe}_*.csv ${BENCHMARKS_DIR}/$run_filename
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
