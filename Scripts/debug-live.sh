#!/bin/bash

# Debug script to monitor Gnau logs in real-time

echo "🔍 Monitoring Gnau application logs..."
echo "================================"
echo ""
echo "Looking for:"
echo "  - Application initialization"
echo "  - Permission status"
echo "  - Analysis coordinator setup"
echo "  - Application switching"
echo "  - Text monitoring"
echo ""
echo "Press Ctrl+C to stop"
echo ""

# Stream logs from Gnau process
log stream --predicate 'process == "Gnau"' --level debug --style compact 2>&1 | while read line; do
    # Filter for relevant messages
    if echo "$line" | grep -qE "(Application launched|Menu bar|Analysis coordinator|Application changed|Text changed|Permission|monitoring|TextMonitor|AnalysisCoordinator)"; then
        echo "$line"
    fi
done
