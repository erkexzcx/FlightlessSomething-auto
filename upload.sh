#!/bin/bash
set -e

# Check if required environment variables are set
for var in BENCHMARKS_DIR GAME_NAME JOB_URL MYSESSION; do
    if [ -z "${!var}" ]; then
        echo "Environment variable $var is not set. Please set it before running the script."
        exit 1
    fi
done

# Check if there are any CSV files in the directory
csv_files=("${BENCHMARKS_DIR}"/*.csv)
if [ ! -e "${csv_files[0]}" ]; then
  echo "Error: No CSV files found in directory ${BENCHMARKS_DIR}."
  exit 1
fi

# Build vars for request

title="Automated ${GAME_NAME} benchmark"
description="Details: $JOB_URL"

# Start constructing the curl command
curl_command=(
  curl -i "$BASE_URL/benchmark"
  -X POST
  -H "Cookie: mysession=$MYSESSION"
  -F "title=$title"
  -F "description=$description"
)

# Loop over all CSV files in the specified directory
for file in "${BENCHMARKS_DIR}"/*.csv; do
  curl_command+=(-F "files=@$file")
done

# Execute the constructed curl command and capture the response
response=$("${curl_command[@]}")
echo $response

# Check if the response contains a 303 status code and a Location header
if echo "$response" | grep -q "HTTP/2 303" && echo "$response" | grep -q "location:"; then
  location=$(echo "$response" | grep "location:" | awk '{print $2}' | tr -d '\r')
  echo "$BASE_URL$location"
else
  echo "Error: The request did not return a 303 status code or a Location header."
  exit 1
fi
