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

## Phase 4: Wazuh server

| File | Shows | What it proves |
|---|---|---|
| `phase4-iso-hash.png` | `Get-FileHash` on the Ubuntu Server ISO | Matches Ubuntu's official `SHA256SUMS` |
| `phase4-wazuh-srv-vm-config.png` | `VBoxManage showvminfo` for WAZUH-SRV | BIOS, 4 GB, `soc-lab` + NAT, localhost-only forwards 8443 and 2222 |
| `phase4-ubuntu-network-before.png` | Installer network screen | `autoconfiguration failed` on the lab adapter: no DHCP on `soc-lab` |
| `phase4-ubuntu-network-static.png` | Installer network screen after editing | Static 10.10.10.10/24 on `enp0s3`; NAT DHCP 10.0.3.15 on `enp0s8` |
| `phase4-ubuntu-storage.png` | Installer storage summary | Plain ext4 root plus BIOS boot partition |
| `phase4-wazuh-srv-first-boot.png` | `hostnamectl`, `ip -br addr`, `ip route`, ping | Hostname, both addresses, single default route via NAT |
| `phase4-dns-and-hostkey.png` | DNS lookup and first SSH prompt | Name resolution works; host-key fingerprint shown for comparison |
| `phase4-ssh-first-attempt-closed.png` | Host: `ssh -p 2222` | Connection closed by grace-time expiry, not a wrong password |
| `phase4-ssh-from-host.png` | Host: successful SSH login | Administration over 127.0.0.1:2222 |
| `phase4-post-update.png` | `apt full-upgrade` end, `uname -r` | Fully patched, kernel 6.8.0-147, 0 upgradable |
| `phase4-wazuh-srv-snapshot-base.png` | `snapshot take` and `list` | `phase4-ubuntu-base` taken offline with ISO ejected |
| `phase4-boot-hang-initramfs.png` | VM console | Finding 4.1: boot stuck at `Loading essential drivers` |
| `phase4-boot-hang-calltrace.png` | VM console | Kernel call trace in module loading during the hang |
| `phase4-boot-retry-ssh-ok.png` | Retry boot and SSH | The same configuration booted normally on retry: intermittent |
| `phase4-preflight.png` | `nproc`, `df -h`, installer size | Resources and installer download checked before install |
| `phase4-preflight-script-header.png` | `head wazuh-install.sh` | Installer version 4.14.9 and Wazuh GPG key |
| `phase4-wazuh-install-attempt1-indexer-failed.png` | Installer output, attempt 1 | `wazuh-indexer could not be started`; automatic rollback |
| `phase4-indexer-diag.png` | `journalctl -u wazuh-indexer`, `free -h`, `dmesg` | Finding 4.2: 180 s start timeout; no out-of-memory |
| `phase4-indexer-timeout-fix-and-attempt2.png` | Drop-in creation and attempt 2 start | `TimeoutStartSec=600` for the indexer |
| `phase4-attempt2-ssh-dropped.png` | Host terminal | SSH dropped as the guest froze during attempt 2 |
| `phase4-soft-lockup-console.png` | VM console | Finding 4.1: `soft lockup ... [G1 Refine]` on CPU#1 |
| `phase4-attempt3-restore-and-dropin.png` | Login banner, drop-in, `ls` | Clean base restored before attempt 3 |
| `phase4-wazuh-install-summary.png` | Installer output, attempt 3 (cropped above the password) | All components installed and started |
| `phase4-boot-hang-2-initramfs.png` | VM console | Second boot hang at the same point |
| `phase4-wazuh-lost-after-restore.png` | `is-active`, `filebeat`, `free -h` | Finding 4.3: install lost to a snapshot restore |
| `phase4-snapshot-taken-during-shutdown.png` | `list runningvms`, `snapshot take` | Finding 4.3: snapshot taken while the VM was still shutting down |
| `phase4-install-finished-log.png` | `wazuh-install.log`, `is-active`, `filebeat test output`, `free`, `df` | Attempt 4 finished without errors; services healthy |
| `phase4-wazuh-health.png` | Health checks | 4 × active; Filebeat to indexer over TLS |
| `phase4-disk-usage.png` | `du` on `/var` | 15 GB explained: vulnerability-detection database |
| `phase4-apt-clean.png` | `apt clean`, `df -h` | 1.6 GB recovered; 45% used |
| `phase4-rcu-stall-soft-lockups.png` | VM console, 2026-10-22 | Finding 4.1: RCU stall and soft lockups on both CPUs before a freeze |
| `phase4-soak-resume-uptime.png` | `uptime` after resuming | Same boot as the soak (3 h 13 min) |
| `phase4-soak-final.png` | `is-active`, `dmesg` grep, `free -h` | Services healthy; lockup reports present (Finding 4.4) |
| `phase4-soak-lockups-host-standby.png` | `journalctl -k` lockup lines with real times | Finding 4.4: times that match host standby periods |
| `phase4-dashboard-cert-fingerprint-server.png` | `openssl x509 -fingerprint -sha256` | Server-side certificate fingerprint, subject and expiry |
| `phase4-dashboard-overview.png` | Dashboard Overview (profile area redacted) | Login works; no agents; 54 self-alerts; no errors |
| `phase4-manager-self-alerts.png` | Threat Hunting events | Low alerts are `sudo`/PAM triplets from the analyst's commands |
| `phase4-manager-self-alerts-medium.png` | Threat Hunting, `rule.level >= 7` | Medium alerts are dpkg package changes |
| `phase4-unattended-upgrades-dpkg-timedatectl.png` | `timedatectl`, `dpkg.log` | Guest clock synchronised; which packages changed and when |
| `phase4-unattended-upgrades-log.png` | `unattended-upgrades.log` | Who installed them, from which sources |
| `phase4-awake-recheck.png` | Re-check after one hour | One lockup, matching a host standby; services healthy |
| `phase4-wazuh-srv-snapshot-dashboard-verified.png` | `poweroff`, `snapshot take`, `snapshot list` | `phase4-dashboard-verified` taken offline and current |
| `phase4-agent-server-ready.png` | `is-active`, `free -h` on WAZUH-SRV | Server healthy before enrolment |
| `phase4-agent-win-tgt-2048mb.png` | `showvminfo WIN-TGT` | Finding 4.6: WIN-TGT reduced to 2048 MB |
| `phase4-agent-win-tgt-to-server-ping.png` | `ping 10.10.10.10`, `Get-Service Sysmon64` | WIN-TGT reaches the server over `soc-lab`; Sysmon running |
| `phase4-agent-msi-download.png` | `wazuh-control info`, `curl`, `ls -l` on WAZUH-SRV | Manager v4.14.9; matching agent MSI downloaded on the server |
| `phase4-agent-msi-transfer-server-log.png` | `sha256sum`, `http.server` log | MSI hash; one download, by 10.10.10.20, then the server stopped |
| `phase4-agent-msi-hash-signature.png` | `Get-FileHash`, `Get-AuthenticodeSignature` on WIN-TGT | Same hash as on the server; signed by Wazuh, Inc |
| `phase4-agent-msiexec-1639.png` | First `msiexec` run | Exit code 1639 from a mistyped switch |
| `phase4-agent-install-connected.png` | Exit code, `NET START`, `ossec.log` | Agent installed, connected, SCA scan finished |
| `phase4-agent-control-list.png` | `agent_control -l` | Agent 001 WIN-TGT active on the manager |
| `phase4-agent-dashboard-active.png` | Dashboard Endpoints (profile area redacted) | WIN-TGT active, Windows 11, v4.14.9 |
| `phase4-agent-reconnect-after-boot.png` | Services, `ossec.log`, Sysmon events | Agent reconnects after a fresh boot |
| `phase4-sysmon-ossec-conf-backup.png` | `Copy-Item`, `<location>` entries | Backup taken; default config lacks the Sysmon channel |
| `phase4-sysmon-ossec-conf-typo-stopped.png` | Appended block, `Get-Service` | Finding 4.7: `<log_format/>` typo; agent stopped |
| `phase4-sysmon-ossec-conf-rollback-fix.png` | `ossec.log` errors, rollback, re-append | Finding 4.7: XML error 1226; restored from backup; corrected block |
| `phase4-sysmon-channel-collected.png` | Restart, `ossec.log` | `(1951) Analyzing event log: 'Microsoft-Windows-Sysmon/Operational'` |
| `phase4-sysmon-alerts-dashboard.png` | Threat Hunting, WIN-TGT Sysmon channel (profile area redacted) | 31 alerts reached the SIEM; SCA burst and 92058 |
| `phase4-sysmon-alerts-grep-observer-effect.png` | `grep -c`, last match | 31 in `alerts.json`; the search command matched itself |
| `phase4-alert-92058-sdbinst.png` | Alert 92058 event data | Finding 4.9: `sdbinst.exe -m -bg` from `svchost.exe` as SYSTEM |
| `phase4-alert-92205-pspolicytest.png` | Alert 92205 event data | Finding 4.8: PowerShell policy-test file in `SystemTemp` |
| `phase4-alert-92066-secedit-sca.png` | Alert 92066 event data | Finding 4.8: `secedit /export` started from the agent folder |
| `phase4-sysmon-after-restore.png` | Services, `ossec.log` after restoring `phase4-sysmon-collection` | Sysmon channel and connection survive restore and reboot |
| `phase4-sdbinst-signature.png` | `Get-AuthenticodeSignature sdbinst.exe` | Finding 4.9: genuine Microsoft binary |
| `phase4-shim-folder-installedsdb.png` | `Test-Path`, `InstalledSDB` query | Finding 4.9: no custom shim databases registered |
| `phase4-shim-custom-registry.png` | `AppCompatFlags\Custom` query | Finding 4.9: no shim mappings |
| `phase4-agent-reconnect-log.png` | Agent `ossec.log` 18:21 to 18:34 EAT | Finding 4.10: one-second disconnect and reconnect |
| `phase4-manager-log-reconnect-window.png` | Manager `ossec.log` 15:33 to 15:35 UTC | Finding 4.10: no disconnect recorded on the server |
| `phase4-complete-snapshots.png` | `list runningvms`, `snapshot take` on both VMs | `phase4-complete` taken with both VMs off |
