# Screenshots

Naming: `phaseN-<what-it-shows>.png`. Each screenshot should prove one claim made in the write-ups.

Before committing, check that no screenshot shows passwords, personal email, browser tabs or anything outside the lab.

## Phase 1: Virtualization and network isolation

| File | What to capture | What it proves |
|---|---|---|
| `phase1-kali-network-settings.png` | Kali → Settings → Network, Adapter 1 tab, with Advanced expanded | Assessment host is on the isolated `soc-lab` network with promiscuous mode for capture |
| `phase1-kali-nat-disconnected.png` | Kali → Settings → Network, Adapter 2 tab, with Advanced expanded | Internet adapter exists but its cable is disconnected |
| `phase1-lnx-tgt-network-settings.png` | Metasploitable → Settings → Network, Adapter 1 tab | Vulnerable host is on `soc-lab` only |
| `phase1-kali-ip-addr.png` | Kali terminal: `ip -br addr` | Static lab address 10.10.10.50 |
| `phase1-kali-ip-route.png` | Kali terminal: `ip route` | No default route, so no way out of the lab |
| `phase1-lnx-tgt-ifconfig.png` | Metasploitable console: `ifconfig eth0` | Static lab address 10.10.10.30 |
| `phase1-ping-lab-success.png` | Kali terminal: `ping -c 4 10.10.10.30` | Lab hosts can communicate |
| `phase1-ping-internet-blocked.png` | Kali terminal: `ping -c 2 8.8.8.8` | Lab cannot reach the internet. The key isolation proof. |
