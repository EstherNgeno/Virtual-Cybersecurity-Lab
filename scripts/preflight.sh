#!/usr/bin/env bash
# Pre-flight isolation check for KALI (control 5 in architecture/network-plan.md).
# Run before every scan or simulation.
# Exit code 0 = isolated, safe to proceed. Exit code 1 = stop and investigate.

LAB_IF="eth0"
LAB_IP="10.10.10.50/24"
NAT_IF="eth1"
fail=0

# Runs a test function and prints PASS or FAIL next to its description.
check() {
    local desc="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        echo "[PASS] $desc"
    else
        echo "[FAIL] $desc"
        fail=1
    fi
}

no_default_route()     { [ -z "$(ip -4 route show default)" ] && [ -z "$(ip -6 route show default)" ]; }
lab_ip_set()           { ip -br -4 addr show dev "$LAB_IF" | grep -qF "$LAB_IP"; }
nat_has_no_address()   { [ -z "$(ip -br -4 addr show dev "$NAT_IF" | awk '{print $3}')" ]; }
forwarding_disabled()  { [ "$(sysctl -n net.ipv4.ip_forward)" = "0" ]; }
internet_unreachable() { ! ping -c 1 -W 2 8.8.8.8; }

echo "Pre-flight isolation check: $(hostname), $(date '+%Y-%m-%d %H:%M:%S')"
check "No default route (IPv4 or IPv6)"       no_default_route
check "$LAB_IF has lab address $LAB_IP"       lab_ip_set
check "$NAT_IF (NAT) has no IPv4 address"     nat_has_no_address
check "IP forwarding is disabled"             forwarding_disabled
check "Internet (8.8.8.8) is unreachable"     internet_unreachable

if [ "$fail" -eq 0 ]; then
    echo "RESULT: ISOLATED. Safe to proceed."
else
    echo "RESULT: NOT ISOLATED. Do not run scans or simulations."
fi
exit "$fail"
