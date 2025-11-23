#!/bin/bash

# Debug script to monitor TextWarden logs in real-time

echo "🔍 Monitoring TextWarden application logs..."
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

# Stream logs from TextWarden process
log stream --predicate 'process == "TextWarden"' --level debug --style compact 2>&1 | while read line; do
    # Filter for relevant messages
    if echo "$line" | grep -qE "(Application launched|Menu bar|Analysis coordinator|Application changed|Text changed|Permission|monitoring|TextMonitor|AnalysisCoordinator)"; then
        echo "$line"
    fi
done
