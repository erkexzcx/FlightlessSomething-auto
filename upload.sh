#!/bin/bash

# Check if the correct number of arguments is provided
if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <mysession_value>"
  exit 1
fi

# Assign argument to variable
MYSESSION=$1

# Some hardcoded variables
DIRECTORY="/home/deck/mangohud_logs"
BASE_URL="https://flightlesssomething-auto.duckdns.org"
REPO_URL="https://github.com/erkexzcx/FlightlessSomething-auto"

# Check if the directory exists
if [ ! -d "$DIRECTORY" ]; then
  echo "Error: Directory $DIRECTORY does not exist."
  exit 1
fi

# Check if there are any CSV files in the directory
csv_files=("$DIRECTORY"/*.csv)
if [ ! -e "${csv_files[0]}" ]; then
  echo "Error: No CSV files found in directory $DIRECTORY."
  exit 1
fi

# Generate a Unix timestamp
TIMESTAMP=$(date +%s)

# Start constructing the curl command
curl_command=(
  curl -i "$BASE_URL/benchmark"
  -X POST
  -H "Cookie: mysession=$MYSESSION"
  -F "title=Automated benchmark at $TIMESTAMP"
  -F "description=Automated benchmark at $TIMESTAMP. See $REPO_URL"
)

# Loop over all CSV files in the specified directory
for file in "$DIRECTORY"/*.csv; do
  curl_command+=(-F "files=@$file")
done

# Execute the constructed curl command and capture the response
response=$("${curl_command[@]}")

# Check if the response contains a 303 status code and a Location header
if echo "$response" | grep -q "HTTP/1.1 303 See Other" && echo "$response" | grep -q "Location:"; then
  location=$(echo "$response" | grep "Location:" | awk '{print $2}' | tr -d '\r')
  echo "Success! Redirected to: $BASE_URL$location"
else
  echo "Error: The request did not return a 303 status code or a Location header."
  exit 1
fi
