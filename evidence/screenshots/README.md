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

## Phase 3: Windows target

| File | Shows | What it proves |
|---|---|---|
| `phase3-win-tgt-vm-config.png` | `VBoxManage showvminfo` for WIN-TGT | 4 GB, 2 vCPU, `soc-lab` on adapter 1 with promiscuous mode deny, NAT cable off, clipboard and drag-and-drop disabled |
| `phase3-win-tgt-storage.png` | `showvminfo` storage lines | 80 GB SSD-flagged disk on port 0, evaluation ISO on port 1 |
| `phase3-win-tgt-labconfig-verified.png` | Installer prompt: `reg query HKLM\SYSTEM\Setup\LabConfig` | `BypassCPUCheck = 0x1` was correctly set |
| `phase3-win-tgt-setup-cores-check-failed.png` | Windows 11 Setup requirements screen | Setup still refused 1 core with the key set |
| `phase3-win-tgt-legacy-setup-refused.png` | Previous version of Setup | The older installer refused too |
| `phase3-win-tgt-installing.png` | "Installing Windows 11" | Install proceeding on legacy BIOS with 2 vCPUs |
| `phase3-win-tgt-oobe-region.png` | First-run setup, region screen | Installation completed |
| `phase3-win-tgt-desktop-local-account.png` | Start menu account panel | `labadmin` is a local account; no Microsoft account |
| `phase3-win-tgt-licence-before.png` | `Get-CimInstance SoftwareLicensingProduct` | Evaluation not activated: status 5, grace 0 |
| `phase3-win-tgt-licence-after.png` | Same query after `slmgr /ato` | Activated: status 1, 129600 minutes |
| `phase3-win-tgt-dns-resolve-failure.png` | DNS server list, failed `curl`, revocation error | The stale DNS server (`192.168.0.1`) behind the download failures |
| `phase3-win-tgt-sysmon-download.png` | `curl.exe` progress table | Sysmon.zip downloaded after the DNS fix |
| `phase3-win-tgt-sysmon-signature.png` | `Get-AuthenticodeSignature` on Sysmon64.exe | Binary signed by Microsoft, signature valid |
| `phase3-win-tgt-stale-default-route.png` | `ipconfig`, `Get-NetRoute`, `ping 8.8.8.8` | Finding 3.2: default route via the unplugged NAT adapter; "0% loss" made of local errors |
| `phase3-win-tgt-nat-adapter-disabled.png` | `Disable-NetAdapter`, adapter list, ping | NAT adapter disabled; internet ping fails with `General failure` |
| `phase3-win-tgt-no-default-route.png` | `Get-NetRoute -DestinationPrefix 0.0.0.0/0` | No default route |
| `phase3-kali-ping-win-tgt-blocked.png` | KALI: `ping -c 4 10.10.10.20` | Inbound ping blocked by default (Finding 3.3) |
| `phase3-win-tgt-ping-kali.png` | WIN-TGT: `ping 10.10.10.50` | Outbound lab connectivity; `TTL=64` from Linux |
| `phase3-win-tgt-firewall-icmp-rule.png` | Network profile and `New-NetFirewallRule` | Public profile; scoped ICMP rule created |
| `phase3-kali-ping-win-tgt-allowed.png` | KALI: `ping -c 4 10.10.10.20` | Ping allowed after the rule; `ttl=128` from Windows |
| `phase3-win-tgt-sysmon-not-elevated.png` | Sysmon install in a normal terminal | Installation requires elevation |
| `phase3-win-tgt-sysmon-install.png` | Sysmon install output and `Get-Service` | Sysmon 15.22 installed with a validated config; service running |
| `phase3-win-tgt-sysmon-events.png` | `Get-WinEvent` on the Sysmon log | Event ID 1 (Process Create) being recorded |
| `phase3-win-tgt-sysmon-event1-notepad.png` | Event ID 1 for Notepad | Full process telemetry: image, command line, user, integrity level, hashes |
| `phase3-win-tgt-post-reboot-baseline.png` | Hostname, Sysmon, IP, adapters, firewall, rule, route after reboot | The whole baseline persists across a restart |
| `phase3-win-tgt-snapshots.png` | `VBoxManage snapshot WIN-TGT list` | `phase3-fresh-install` and `phase3-baseline` exist; baseline is current |
