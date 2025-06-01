#!/bin/bash

# Benchmark specific variables
export GAME_EXEC="FactoryGameSteam-Win64-Shipping.exe" # Game.exe (ps aux | grep 'steamapps\\common')
export SCX_DIR="/var/lib/github-actions/scx" # Persistent, to re-use compiled deps (cache)
export CARGO_TARGET_DIR="/var/lib/github-actions/scx-cargo-target" # Persistent, to re-use compiled deps (cache)
export BENCHMARKS_DIR="/tmp/mangohud_logs" # Temporary dir to store benchmark results
export GAME_USER="deck" # User that runs game

# Used for upload
export GAME_NAME="Satisfactory"
export BASE_URL="https://flightlesssomething-auto.ambrosia.one"
#export MYSESSION  # Taken from environment variables
#export JOB_URL    # Taken from environment variables
