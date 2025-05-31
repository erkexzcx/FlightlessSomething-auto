#!/bin/bash

# Check if the correct number of arguments is provided
if [ "$#" -ne 3 ]; then
  echo "Usage: $0 <mysession_value> <runjob_url> <additional_description>"
  exit 1
fi

# Assign argument to variable
MYSESSION=$1
JOBURL=$2
DESCRIPTION=$3

# Some hardcoded variables
DIRECTORY="/tmp/mangohud_logs"
BASE_URL="https://flightlesssomething-auto.ambrosia.one"

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
TIMESTAMP=$(date -u +"%Y-%m-%d %H:%M:%S UTC")

# Debug information
echo "title: Automated FH5 benchmark"
echo "description: Automated Forza Horizon 5 benchmark, on Steam Deck LCD 512GB, at $TIMESTAMP. For more information, see $JOBURL. $DESCRIPTION"

# Start constructing the curl command
curl_command=(
  curl -i "$BASE_URL/benchmark"
  -X POST
  -H "Cookie: mysession=$MYSESSION"
  -F "title=Automated FH5 benchmark"
  -F "description=Automated Forza Horizon 5 benchmark, on Steam Deck LCD 512GB, at $TIMESTAMP. For more information, see $JOBURL. $DESCRIPTION"
)

# Loop over all CSV files in the specified directory
for file in "$DIRECTORY"/*.csv; do
  curl_command+=(-F "files=@$file")
  echo "Adding file: $file"
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
