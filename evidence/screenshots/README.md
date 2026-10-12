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

## Phase 2: Kali Linux baseline

| File | Shows | What it proves |
|---|---|---|
| `phase2-kali-snapshot-phase1-verified.png` | `VBoxManage snapshot ... take` and `list` | A rollback point existed before any Phase 2 change |
| `phase2-kali-credential-status.png` | Kali: `passwd -S kali` | Default password replaced on 2026-10-12, without showing the password |
| `phase2-kali-tool-versions.png` | Kali: Nmap, Wireshark and TShark versions, `id`, `getcap` and `ls -l` on `dumpcap` | Tool versions; capture allowed for the `wireshark` group without root |
| `phase2-kali-nonroot-capture.png` | Kali: `tshark -r` read-back of the test capture | Non-root capture works; also the "before" view of the DHCP Discovers |
| `phase2-kali-dhcp-source-mac.png` | Kali: `tshark ... -e eth.src` and `ip -br link` | The DHCP Discovers come from LNX-TGT's MAC, not from Kali |
| `phase2-lnx-tgt-dhclient-running.png` | Metasploitable: `ps aux \| grep dhclient`, `/etc/network/interfaces` | A stale DHCP client was running despite a correct static configuration |
| `phase2-lnx-tgt-dhclient-removed.png` | Metasploitable after reboot: `ps aux \| grep dhclient`, `ifconfig eth0` | DHCP client gone; static address survives a reboot |
| `phase2-kali-no-dhcp-traffic.png` | Kali: 30-second `tshark -Y dhcp` | No DHCP traffic remains after the fix (`0 packets captured`) |
| `phase2-kali-target-reachable.png` | Kali: `ping -c 2 10.10.10.30` after the target's reboot | Target still reachable at its static address |
| `phase2-kali-preflight-fail.png` | Kali: `preflight.sh` with the NAT cable connected | The check detects broken isolation (3 FAIL, exit code 1) |
| `phase2-kali-preflight-pass.png` | Kali: `preflight.sh` with the NAT cable disconnected | Isolation restored (5 PASS, exit code 0) |
| `phase2-kali-target-down-ping.png` | Kali: ping to 10.10.10.30 while LNX-TGT was still in a saved state | `Destination Host Unreachable`: the ARP-level failure described in the write-up |
| `phase2-snapshots.png` | `VBoxManage snapshot ... list` for both VMs | Baseline snapshots exist for KALI and LNX-TGT |
