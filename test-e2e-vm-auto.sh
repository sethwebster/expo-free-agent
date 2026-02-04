#!/bin/bash
# Modified E2E test that uses non-interactive certificate selection
# This allows the test to run fully automated

set -e

# Copy the original test script
cp test-e2e-vm.sh test-e2e-vm-auto-temp.sh

# Replace the cert finder with our automated version
sed -i '' 's|test/find-dev-certs.sh|test/find-dev-certs-auto.sh|' test-e2e-vm-auto-temp.sh

# Run the modified test
./test-e2e-vm-auto-temp.sh

# Clean up
rm -f test-e2e-vm-auto-temp.sh