# Screenshots

Naming: `phaseN-<what-it-shows>.png`. Each screenshot should prove one claim made in the write-ups.

Before committing, check that no screenshot shows passwords, personal email, browser tabs or anything outside the lab.

## Phase 1: Virtualization and network isolation

| File | Shows | What it proves |
|---|---|---|
| `phase1-kali-adapter-verification.png` | `VBoxManage showvminfo` for Kali | Kali on internal `soc-lab`; NAT cable disconnected; clipboard host-to-guest; drag-and-drop off |
| `phase1-lnx-tgt-reconfigure.png` | `discardstate` and `modifyvm` commands | How the vulnerable host was moved off the NAT Network |
| `phase1-lnx-tgt-adapter-verification.png` | `VBoxManage showvminfo` for Metasploitable | Vulnerable host on `soc-lab` only; NIC 2–4 disabled |
| `phase1-lnx-tgt-ifconfig.png` | Metasploitable: `ifconfig eth0` | Static lab address 10.10.10.30 |
| `phase1-kali-connectivity-and-isolation.png` | Kali: `ip -br addr`, `ip route`, ping to 10.10.10.30, ping to 8.8.8.8 | Lab address, no default route, lab connectivity, internet unreachable. The key isolation proof. |

Optional, nice for non-technical readers: `phase1-kali-network-settings.png`, the VirtualBox Settings → Network window for Kali's Adapter 1.
