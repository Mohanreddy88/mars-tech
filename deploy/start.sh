#!/bin/bash
set -e
echo "=== HRMS starting (VPS) ==="

nginx -g "daemon off;" &
cd /app/api
dotnet HrmsApi.dll &

# If either process exits, stop the container so Docker restarts it
wait -n
echo "A process exited — stopping container"
exit 1
