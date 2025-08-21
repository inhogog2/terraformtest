#!/bin/bash
source ../common.sh
echo ACTIVE-ACTIVE

# Debug: Check if containers are running
echo "=== Checking container status ==="
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "(llb1|llb2|ep1|ep2|ep3|r1|r2|user)"

function tcp_validate() { 
  # Start iperf servers on endpoints
  echo "Starting iperf servers..." >&2
  $hexec ep1 iperf -s -p 8080 >> /dev/null 2>&1 &
  $hexec ep2 iperf -s -p 8080 >> /dev/null 2>&1 &
  $hexec ep3 iperf -s -p 8080 >> /dev/null 2>&1 &

  sleep 5
  
  echo "Running iperf client test..." >&2
  # Run iperf client and capture output
  iperf_output=$($hexec user iperf -c 20.20.20.1 -p 2020 -P 10 -t 100 -i 1 2>&1)
  iperf_exit_code=$?
  
  echo "Iperf output:" >&2
  echo "$iperf_output" >&2
  echo "Iperf exit code: $iperf_exit_code" >&2
  
  # Clean up iperf processes
  sudo pkill iperf 2>/dev/null
  
  # Check if iperf completed successfully
  if [[ $iperf_exit_code -eq 0 ]]; then
    # Additional check: look for successful data transfer in output
    if echo "$iperf_output" | grep -q "Mbits/sec\|Kbits/sec\|Gbits/sec"; then
      echo "TCP validation successful - data transfer detected" >&2
      echo 0
      return 0
    else
      echo "TCP validation failed - no data transfer detected" >&2
      echo 1
      return 1
    fi
  else
    echo "TCP validation failed - iperf command failed with exit code $iperf_exit_code" >&2
    echo 1
    return 1
  fi
}

function ecmp_validate() {
  # Check if all 3 loxilb instances are advertising the route
  echo "Checking ECMP routes..." >&2
  routes=$($hexec r1 ip route list match 20.20.20.1)
  echo "Routes: $routes" >&2
  
  # Count number of nexthops in ECMP
  nexthop_count=$(echo "$routes" | grep -o "nexthop" | wc -l)
  if [[ $nexthop_count -eq 0 ]]; then
    # Single route case - check if it contains multiple via
    via_count=$(echo "$routes" | grep -o "via" | wc -l)
    if [[ $via_count -ge 2 ]]; then
      echo "ECMP with 2 paths detected [OK]" >&2
    else
      echo "ECMP validation failed - only $via_count paths found" >&2
      return 1
    fi
  else
    if [[ $nexthop_count -ge 2 ]]; then
      echo "ECMP with $nexthop_count nexthops detected [OK]" >&2
      echo 0
    else
      echo "ECMP validation failed - only $nexthop_count nexthops found" >&2
      echo 1
    fi
  fi
}

echo "=== Starting BGP connection checks ==="

count=0
while : ; do
  echo "Checking llb1 BGP connection... (attempt $count)"
  echo "Running: $dexec llb1 gobgp neigh -p 50052"
  
  # Check if llb1 container is running first
  if ! docker ps | grep -q "llb1"; then
    echo "ERROR: llb1 container is not running!"
    exit 1
  fi
  
  bgp_output=$($dexec llb1 gobgp neigh -p 50052 2>&1)
  echo "BGP output: $bgp_output"
  
  echo "$bgp_output" | grep "Estab" 2>&1 >> /dev/null
  if [[ $? -eq 0 ]]; then
    echo "llb1 BGP connection [OK]"
    break;
  fi
  sleep 0.2
  count=$(( $count + 1 ))
  if [[ $count -ge 2000 ]]; then
    echo "llb1 BGP connection [NOK]"
    exit 1;
  fi
done

count=0
while : ; do
  echo "Checking llb2 BGP connection... (attempt $count)"
  $dexec llb2 gobgp neigh -p 50052 | grep "Estab" >> /dev/null
  if [[ $? -eq 0 ]]; then
    echo "llb2 BGP connection [OK]"
    break;
  fi
  sleep 0.2
  count=$(( $count + 1 ))
  if [[ $count -ge 2000 ]]; then
    echo "$backup BGP connection [NOK]"
    exit 1;
  fi
done

# First, test ECMP with all loxilb instances
echo "ACTIVE-ACTIVE ECMP Test Start"
code=0
code=$(ecmp_validate)
if [[ $code == 0 ]]
then
    echo ACTIVE-ACTIVE ECMP [OK]
else
    echo ACTIVE-ACTIVE ECMP [FAILED]
    exit 1
fi

echo "ACTIVE-ACTIVE TCP Start"
code=0
code=$(tcp_validate)
if [[ $code == 0 ]]
then
    echo ACTIVE-ACTIVE TCP [OK]
else
    echo ACTIVE-ACTIVE TCP [FAILED]
    exit 1
fi

exit $code
