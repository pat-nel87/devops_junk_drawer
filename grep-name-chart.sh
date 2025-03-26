#!/bin/bash

CHART_DIR="mychart"
NEW_NAME="custom-chart"

# Update the name field in Chart.yaml
sed -i "s/^name:.*/name: ${NEW_NAME}/" ${CHART_DIR}/Chart.yaml

# Extract the version after modifying the name
VERSION=$(grep '^version:' ${CHART_DIR}/Chart.yaml | awk '{print $2}')

# Package the chart
helm package ${CHART_DIR}

echo "Packaged as ${NEW_NAME}-${VERSION}.tgz"
