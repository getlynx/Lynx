#!/bin/bash

# journalctl -t lynx

# Set strict error handling
set -euo pipefail

# Configuration
CAP=400                    # Maximum number of suitable inputs
AMOUNT=20                  # Amount to send per transaction
DELAY=5                    # Delay between transactions in seconds

# Validate command line arguments
if [ $# -ne 1 ]; then
  logger -p user.error -t lynx -s "Missing argument"
  logger -p user.error -t lynx -s "Usage: $0 <suitable inputs>"
  exit 1
fi

# Validate input is a number
if ! [[ $1 =~ ^[0-9]+$ ]]; then
  logger -p user.error -t lynx -s "Argument must be a number"
  exit 1
fi

START_NUM=$1

# Check if start number is less than cap
if [ "$START_NUM" -lt "$CAP" ]; then

  # Check wallet balance
  BALANCE=$(lynx-cli getbalance)
  if ! [[ "$BALANCE" =~ ^[0-9]+\.?[0-9]*$ ]]; then
    logger -p user.error -t lynx -s "Invalid balance format received"
    logger -p user.error -t lynx -s "Current balance: $BALANCE"
    exit 1
  fi

  # Calculate required amount
  REQUIRED_AMOUNT=$(((CAP - START_NUM + 1) * AMOUNT))

  logger -p user.info -t lynx -s "Total balance required: $REQUIRED_AMOUNT"

  # Verify sufficient balance
  if [ "${BALANCE%.*}" -lt "$REQUIRED_AMOUNT" ]; then
    logger -p user.error -t lynx -s "Insufficient balance. Required: $REQUIRED_AMOUNT, Current: $BALANCE"
    exit 1
  fi

  # Get new address for transactions
  ADDRESS=$(lynx-cli getnewaddress)

  if [ -z "$ADDRESS" ]; then
    logger -p user.error -t lynx -s "Failed to generate new address"
    exit 1
  fi

  logger -p user.info -t lynx -s "Starting transactions from $START_NUM to $CAP"
  logger -p user.info -t lynx -s "Sending to address: $ADDRESS"

# Loop through and send transactions
for i in $(seq "$START_NUM" "$CAP"); do
  logger -p user.info -t lynx -s "Processing transaction $i of $CAP"
  if TXHASH=$(lynx-cli sendtoaddress "$ADDRESS" "$AMOUNT"); then
    logger -p user.info -t lynx -s "Transaction $i hash: $TXHASH"
  else
    logger -p user.error -t lynx -s "Transaction failed at iteration $i"
    exit 1
  fi
  sleep "$DELAY"
done

  logger -p user.info -t lynx -s "Completed all transactions successfully"
else
  logger -p user.info -t lynx -s "Start number ($START_NUM) is not less than cap ($CAP)"
  exit 0
fi