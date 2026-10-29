# Phase 4: Wazuh Server and Agent

| | |
|---|---|
| **Status** | Complete: server built and verified, WIN-TGT enrolled, Sysmon events reaching the SIEM, first endpoint alerts triaged |
| **Date** | 2026-10-15 to 2026-10-29 |
| **Hosts in scope** | WAZUH-SRV, WIN-TGT |

## Objective

Build WAZUH-SRV, the lab's SIEM: Ubuntu Server with the Wazuh all-in-one stack (indexer, manager, dashboard), on the isolated lab network at 10.10.10.10, reachable from the host only through localhost port-forwards. Prove it is stable and healthy, verify the dashboard's certificate before trusting it, and leave a clean snapshot before the first agent is enrolled. Then enrol WIN-TGT as the first agent without giving it internet access, forward its Sysmon telemetry, and explain every alert it produces.

## Environment

| Component | Detail |
|---|---|
| WAZUH-SRV | Ubuntu Server 24.04.5 LTS, kernel 6.8.0-147, 4 GB RAM, **1 vCPU** (planned 2, see Finding 4.1), 50 GB disk, legacy BIOS firmware |
| Wazuh | 4.14.9 all-in-one: wazuh-indexer (OpenSearch 2.19.6), wazuh-manager, Filebeat 7.10.2, wazuh-dashboard |
| WIN-TGT | Windows 11 Enterprise Evaluation 10.0.26300, Wazuh agent 4.14.9 (agent ID `001`), Sysmon (Phase 3), **2 GB RAM** during this phase (Finding 4.6), 2 vCPU, 10.10.10.20, no internet |
| Hypervisor | VirtualBox 7.2.8 on the Windows hypervisor ("NEM" mode), because Virtualization-Based Security stays enabled on the host |
| Network | Adapter 1 `soc-lab` 10.10.10.10/24, no gateway; adapter 2 VirtualBox NAT (10.0.3.15) for updates and two localhost-only port-forwards |

Wazuh's documentation recommends 4 vCPU and 8 GB RAM for an all-in-one server. This lab runs it on 4 GB as a documented trade-off for a 16 GB laptop; it is enough for one or two agents.

## 1. Installation media

```powershell
Get-FileHash .\ubuntu-24.04.5-live-server-amd64.iso -Algorithm SHA256
# 97F3D7FFB032C3EB3B23D2C8BE9CC76E60C2C1F2C0146BA5BA9FE01CAFAE0FD8
```

The value matches the official `SHA256SUMS` published by Ubuntu, so the image is the one Canonical released. An older Ubuntu 22.04 desktop ISO already on the host was deliberately not used.

## 2. Virtual machine

Equivalent `VBoxManage` settings:

```powershell
VBoxManage createvm --name WAZUH-SRV --ostype Ubuntu_64 --register
VBoxManage modifyvm WAZUH-SRV --firmware bios --memory 4096 --cpus 2 --graphicscontroller vmsvga `
  --nic1 intnet --intnet1 soc-lab --nic-promisc1 deny `
  --nic2 nat --cable-connected2 on `
  --natpf2 "dashboard,tcp,127.0.0.1,8443,,443" --natpf2 "ssh,tcp,127.0.0.1,2222,,22"
# 50 GB dynamically allocated VDI on SATA port 0, ISO on port 1
# later (Finding 4.1):
VBoxManage modifyvm WAZUH-SRV --cpus 1
```

| Setting | Value | Reason |
|---|---|---|
| Firmware | Legacy BIOS from the start | Avoids the UEFI multi-CPU hang found in Phase 3 ([Finding 3.1](03-windows-target.md#finding-31-uefi-firmware-hangs-with-more-than-one-virtual-cpu-on-this-host)) |
| Adapter 1 | Internal `soc-lab`, promiscuous deny, MAC `08:00:27:FF:41:EE` | Receives agent traffic on TCP 1514/1515 |
| Adapter 2 | NAT, cable connected | Package and vulnerability-feed updates |
| Port-forward `dashboard` | `127.0.0.1:8443` → guest 443 | Dashboard from the host browser only; bound to localhost so no other device on the home Wi-Fi can reach it |
| Port-forward `ssh` | `127.0.0.1:2222` → guest 22 | Administration from a host terminal, with copy and paste |

## 3. Ubuntu installation

- **Network:** `enp0s3` (soc-lab) first showed `autoconfiguration failed`, because the lab has no DHCP server by design. It was set manually to `10.10.10.10/24` with no gateway and no DNS. `enp0s8` (NAT) received `10.0.3.15/24` by DHCP, with gateway `10.0.3.2`. VirtualBox gives a VM's second NAT adapter the 10.0.3.0/24 range, not the familiar 10.0.2.0/24.
- **Storage:** whole disk, plain ext4 at `/` (about 50 GB) plus the 1 MB BIOS boot partition. No LVM, to keep the lab simple.
- **Profile:** hostname `wazuh-srv`, user `labadmin` with a lab-only password, OpenSSH server installed, no extra snaps.

First boot confirmed one default route only, via `10.0.3.2` on the NAT adapter, so the lab segment has no path out.

## 4. Remote access and updates

The first SSH connection from the host showed an ED25519 host-key fingerprint, which was compared with the key on the server's console before being accepted:

```
SHA256:UlrIRzdu+1zz21NxrnSqQ3mXKMY60b2QhO+PBCr/o5s
```

The first login attempt ended with `Connection closed by 127.0.0.1 port 2222` without a `Permission denied` message. The login grace timer had expired while the password was typed (Linux shows nothing as you type). The second attempt succeeded.

`sudo apt update && sudo apt full-upgrade` brought the system to kernel 6.8.0-147 with 0 upgradable packages. The login banner offered `do-release-upgrade` to Ubuntu 26.04; this was declined, because Wazuh 4.14 is supported on 24.04 and a release upgrade would change the platform underneath it.

A snapshot, `phase4-ubuntu-base`, was taken with the VM powered off and the ISO ejected.

## 5. Wazuh installation

```bash
curl -sO https://packages.wazuh.com/4.14/wazuh-install.sh
head wazuh-install.sh                    # confirms 4.14.9 and the Wazuh GPG key URL
tmux new -s wazuh                        # the install survives a dropped SSH session
sudo bash wazuh-install.sh -a            # -a = all-in-one
```

It took four attempts to get a working install:

| Attempt | Date | Outcome | Cause |
|---|---|---|---|
| 1 | 2026-10-19 | `ERROR: wazuh-indexer could not be started`; the installer rolled itself back | Indexer start exceeded systemd's 180 s limit (Finding 4.2) |
| 2 | 2026-10-19 | Guest hung during indexer start; console showed soft lockups | 2 vCPUs under NEM (Finding 4.1) |
| 3 | 2026-10-21 | **Succeeded**, then lost by an unintended snapshot restore | Process error (Finding 4.3) |
| 4 | 2026-10-21 | **Succeeded** and kept | `Installation finished.` at 11:09:55 in `/var/log/wazuh-install.log`, no `ERROR` lines |

The installer prints the admin password at the end and stores all generated passwords in `~/wazuh-install-files.tar`. No screenshot in this repository shows a password.

### Health check

```bash
systemctl is-active wazuh-indexer wazuh-manager filebeat wazuh-dashboard   # 4 x active
sudo filebeat test output     # TLSv1.2 handshake to the indexer, certificate chain verification enabled
free -h                       # 2.2 Gi used, 1.6 Gi available, swap almost unused
df -h /                       # 22 G used of 49 G
```

Disk use jumped from 6.6 GB to 22 GB during installation. `du` showed most of it in `/var/ossec/queue/vd` (9.4 GB), the vulnerability-detection content database, which Wazuh downloads and maintains itself. This is expected and was kept, because vulnerability detection is useful against the deliberately unpatched WIN-TGT (Finding 3.4). `sudo apt clean` recovered 1.6 GB of cached packages, leaving 21 GB used (45%).

## 6. Dashboard

### Certificate verification before login

Chrome reported `NET::ERR_CERT_AUTHORITY_INVALID`, because the installer generates its own certificate authority. Rather than click through the warning, the certificate was compared through a second channel. On the server, over SSH:

```bash
sudo grep 'server.ssl.certificate' /etc/wazuh-dashboard/opensearch_dashboards.yml
# server.ssl.certificate: "/etc/wazuh-dashboard/certs/wazuh-dashboard.pem"
sudo openssl x509 -in /etc/wazuh-dashboard/certs/wazuh-dashboard.pem -noout -fingerprint -sha256 -subject -enddate
# sha256 Fingerprint=96:E2:B8:A8:4B:07:64:61:8B:12:7A:61:C2:61:6C:F7:28:EF:85:06:6D:66:5D:01:B7:67:0D:B6:0F:0B:AF:CE
# subject=C = US, L = California, O = Wazuh, OU = Wazuh, CN = wazuh-dashboard
# notAfter=Oct 18 10:37:28 2036 GMT
```

The SHA-256 fingerprint in Chrome's certificate viewer for `https://127.0.0.1:8443` was identical. Only then was the warning accepted and the `admin` login used.

### First look

The Overview page reported **no agents registered**, as expected before enrolment, and no API or indexer errors. It also showed **54 alerts in the last 24 hours** (28 medium, 26 low) from the server monitoring itself (agent `000`). They were triaged as the first exercise of the lab:

| Alerts | Rule IDs | Source | Verdict |
|---|---|---|---|
| 26 low (level 3) | 5402 `Successful sudo to ROOT executed`, 5501/5502 `PAM: Login session opened/closed` | Every `sudo` produces this triplet at the same millisecond. Timestamps matched the commands run during this phase. | Expected administrator activity |
| 28 medium (level 7) | 2902 `New dpkg (Debian Package) installed`, 2904 `Dpkg (Debian Package) half configured` | Package changes from 09:37 to 09:41 UTC on 2026-10-28 | Expected maintenance (below) |

Installing software on a SIEM server deserves an explanation, so the package alerts were traced to their source in three independent logs:

| Question | Answer | Source |
|---|---|---|
| Who? | `unattended-upgrades`, Ubuntu's automatic security updater, started by its systemd timer | `/var/log/unattended-upgrades/unattended-upgrades.log`: `Starting unattended upgrades script` at 09:36:35 |
| What? | `ca-certificates git git-man liblzma5 python3-jwt xz-utils` | Same log, `Packages that will be upgraded`, matching `/var/log/dpkg.log` line for line |
| From where? | Ubuntu `noble`, `noble-security` and ESM only. The Wazuh repository is not an allowed origin, so Wazuh is never upgraded automatically. | `Allowed origins are:` line |
| Why then? | The daily run was missed while the VM was in a saved state for five days, and caught up 18 seconds after it resumed | Timing |

`half configured` is a normal, momentary state that every Debian package passes through during installation (unpacked → half-configured → installed). It would only indicate a problem if a package stayed there. One of the upgraded packages, `xz-utils 5.6.1+really5.4.5`, is Ubuntu's reverted build following the 2024 xz backdoor (CVE-2024-3094), a reminder of why package-install alerts are worth reading.

## 7. Stability testing

After Finding 4.1 the server was reduced to 1 vCPU, and a soak test was run to show the guest stays healthy over several hours. The test ran in two sessions on the same boot:

- **2026-10-22:** booted 15:49 UTC; all four services active at boot; checkpoint after 18 minutes clean. The VM was saved at 18:52 UTC before the final check.
- **2026-10-28:** resumed (uptime 3:13, confirming the same boot), then checked `dmesg`/`journalctl` and service state, and re-checked after a further hour.

The kernel log contained six soft lockups and one RCU stall, in five clusters. Every cluster coincided with the **host laptop** entering Modern Standby (Finding 4.4). None occurred while the host was awake (about 59 minutes on 22 October and 77 minutes on 28 October), and all services stayed active throughout. **Result: pass.** The 1-vCPU configuration is stable; the remaining reports are an artefact of the host sleeping.

## 8. Agent enrolment on WIN-TGT

**Time zones:** WAZUH-SRV logs in UTC; WIN-TGT and the dashboard display East Africa Time (EAT, UTC+3). Times below say which they are.

### Preparation

With WAZUH-SRV running, only about 2.7 GB of host memory was free, so WIN-TGT was reduced from 4 GB to 2 GB for this phase (Finding 4.6). Before any install, both ends were checked: four Wazuh services `active` on the server ([server ready](../evidence/screenshots/phase4-agent-server-ready.png), [WIN-TGT 2048 MB](../evidence/screenshots/phase4-agent-win-tgt-2048mb.png)), and WIN-TGT reaching `10.10.10.10` over `soc-lab` with Sysmon running ([ping](../evidence/screenshots/phase4-agent-win-tgt-to-server-ping.png)).

### Getting the installer to an offline endpoint

WIN-TGT has no internet access by design (Phase 3), so the installer was downloaded on the server, which has a NAT adapter, and served to WIN-TGT across the lab network:

```bash
sudo /var/ossec/bin/wazuh-control info          # manager v4.14.9: agent version must not be newer
curl -fSLO https://packages.wazuh.com/4.x/windows/wazuh-agent-4.14.9-1.msi
sha256sum wazuh-agent-4.14.9-1.msi
# e3f18109d36c98c2f861f210fc6661226d99251b79321c5d7ff27821b906ea49
python3 -m http.server 8000 --bind 10.10.10.10   # lab interface only; stopped with Ctrl+C after one download
# 10.10.10.20 - - [28/Oct/2026 15:23:15] "GET /wazuh-agent-4.14.9-1.msi HTTP/1.1" 200 -
```

([download](../evidence/screenshots/phase4-agent-msi-download.png), [transfer](../evidence/screenshots/phase4-agent-msi-transfer-server-log.png)). Binding to `10.10.10.10` kept the temporary web server off the NAT adapter, and the log shows exactly one request, from WIN-TGT.

On WIN-TGT, the file was checked twice before it was run ([hash and signature](../evidence/screenshots/phase4-agent-msi-hash-signature.png)):

| Check | Result | What it proves |
|---|---|---|
| `Get-FileHash` | `E3F18109…B906EA49`, identical to the server's `sha256sum` | The file was not altered in transit |
| `Get-AuthenticodeSignature` | `Valid`, signer `CN="Wazuh, Inc"`, issuer `Microsoft ID Verified CS AOC CA 04` | Wazuh built it |

The signing certificate was valid for only three days (7 to 10 October 2026) and had already expired, yet the signature is `Valid`. Short-lived certificates are normal for Microsoft's Trusted Signing service; the signature carries a trusted timestamp proving it was made while the certificate was valid.

### Installation

```powershell
$p = Start-Process msiexec.exe -Wait -PassThru -ArgumentList '/i wazuh-agent-4.14.9-1.msi /qn /L*V C:\Users\labadmin\Downloads\wazuh-agent-install.log WAZUH_MANAGER="10.10.10.10" WAZUH_AGENT_NAME="WIN-TGT"'
$p.ExitCode        # 0
NET START Wazuh
```

The first attempt returned exit code 1639 (invalid command line), because the logging switch was typed `/1*v` with the digit one instead of the letter L ([1639](../evidence/screenshots/phase4-agent-msiexec-1639.png)). Checking the exit code caught this; a silent install (`/qn`) shows no error dialog.

The agent connected at 18:49:13 EAT, then ran its first rootcheck, file-integrity scan and CIS Windows 11 configuration assessment (SCA, 40 seconds) ([install and connection](../evidence/screenshots/phase4-agent-install-connected.png)).

### Verification from the server

| Source | Result |
|---|---|
| `agent_control -l` | `ID: 001, Name: WIN-TGT, IP: any, Active` ([list](../evidence/screenshots/phase4-agent-control-list.png)) |
| Dashboard, Endpoints | 1 active agent: `001 WIN-TGT 10.10.10.20`, group `default`, Windows 11 Enterprise Evaluation 10.0.26300.9457, v4.14.9 ([dashboard](../evidence/screenshots/phase4-agent-dashboard-active.png)) |

Both VMs were then shut down and snapshotted together as `phase4-agent-enrolled`. Snapshots of the two must stay in step: the agent's key in `client.keys` has to match the manager's copy.

## 9. Sysmon collection and first endpoint alerts

### Adding the Sysmon channel

After a fresh boot from the snapshot, the agent reconnected on its own ([reconnect](../evidence/screenshots/phase4-agent-reconnect-after-boot.png)). However, the agent's default `ossec.conf` only collects the `Application`, `Security` and `System` event logs. Sysmon writes to its own channel, which had to be added. The file was backed up first ([backup and current channels](../evidence/screenshots/phase4-sysmon-ossec-conf-backup.png)):

```powershell
cd 'C:\Program Files (x86)\ossec-agent'
Copy-Item .\ossec.conf .\ossec.conf.bak-pre-sysmon
Add-Content -Path .\ossec.conf -Value "`r`n<ossec_config>`r`n <localfile>`r`n <location>Microsoft-Windows-Sysmon/Operational</location>`r`n <log_format>eventchannel</log_format>`r`n </localfile>`r`n</ossec_config>"
Restart-Service WazuhSvc
```

The first attempt contained a typo and stopped the agent (Finding 4.7). It was rolled back from the backup and re-applied. After the restart, the agent log confirmed the new channel ([collected](../evidence/screenshots/phase4-sysmon-channel-collected.png)):

```
2026/10/29 13:51:32 wazuh-agent: INFO: (1951): Analyzing event log: 'Microsoft-Windows-Sysmon/Operational'.
2026/10/29 13:51:32 wazuh-agent: INFO: (4102): Connected to the server ([10.10.10.10]:1514/tcp).
```

### End-to-end check

Threat Hunting, filtered to agent `WIN-TGT` and `data.win.system.channel: Microsoft-Windows-Sysmon/Operational`, showed **31 alerts** in 24 hours ([dashboard](../evidence/screenshots/phase4-sysmon-alerts-dashboard.png)). On the server, `grep -c` on `alerts.json` also gave 31. Displaying the "latest" of those matches returned a `sudo` alert instead of a Sysmon one: the analyst's own `sudo grep 'Microsoft-Windows-Sysmon' …` command line had been logged into `alerts.json` and matched its own search ([observer effect](../evidence/screenshots/phase4-sysmon-alerts-grep-observer-effect.png)). Searching structured fields (`data.win.system.channel`) instead of raw text avoids this.

The Sysmon timestamps (`utcTime` 10:52 UTC) and the dashboard (13:52 EAT) agree, which confirms that the host clock problem in Finding 4.5 no longer affects WIN-TGT's events.

### Triage

Each rule that appeared was explained before moving on:

| Rule | Level | What happened | Verdict |
|---|---|---|---|
| 92205 `Powershell process created an executable file in Windows root folder` | 9 | 32-bit PowerShell, as SYSTEM, created `C:\Windows\SystemTemp\__PSScriptPolicyTest_*.ps1`, the file PowerShell writes to test whether AppLocker/WDAC policy allows scripts ([92205](../evidence/screenshots/phase4-alert-92205-pspolicytest.png)) | Benign, self-generated (Finding 4.8) |
| 92066 `SecEdit.exe binary in a suspicious location` | 4 | `C:\Windows\SysWOW64\SecEdit.exe /export`, parent `powershell secedit /export … Select-String "ResetLockoutCount"; Remove-Item …`, working directory `C:\Program Files (x86)\ossec-agent\` ([92066](../evidence/screenshots/phase4-alert-92066-secedit-sca.png)) | Benign, self-generated (Finding 4.8) |
| 92031 `Discovery activity executed` | 3 | Same SCA burst | Benign, self-generated |
| 92021 `Powershell was used to delete files or directories` | 3 | `Remove-Item` of the temporary `secpol.cfg` in the same SCA command | Benign, self-generated |
| 92058 `Application Compatibility Database launched` | **12** | `sdbinst.exe -m -bg`, parent `svchost.exe -k LocalSystemNetworkRestricted -p`, SYSTEM ([92058](../evidence/screenshots/phase4-alert-92058-sdbinst.png)) | Benign, Windows maintenance (Finding 4.9) |

The burst of 92205, 92066, 92031 and 92021 alerts ran from 13:52:04 to 13:52:12 EAT, about 30 seconds after the agent restarted. It is the agent's own CIS benchmark scan: SCA checks security policy by running `secedit` through PowerShell. The agent is 32-bit, so its child processes are the 32-bit copies in `SysWOW64`, which is what made rule 92066 call the location suspicious.

## 10. Snapshots

## 10. Snapshots

```powershell
VBoxManage snapshot WAZUH-SRV take phase4-dashboard-verified --description "1 vCPU, manager start-timeout drop-in, soak passed, dashboard cert verified, unattended-upgrades 2026-10-28 applied"
```

| Snapshot | State it holds |
|---|---|
| `phase4-ubuntu-base` | Ubuntu installed and fully patched, static lab address, SSH via 127.0.0.1:2222. Before Wazuh. |
| `phase4-wazuh-installed` | Wazuh 4.14.9 installed (attempt 4), indexer start-timeout drop-in, 2 vCPU |
| `phase4-1vcpu-manager-dropin` | 1 vCPU, manager start-timeout drop-in |
| `phase4-dashboard-verified` | Soak passed, dashboard certificate verified, packages updated on 2026-10-28 |

From agent enrolment onwards, both VMs are snapshotted together under the same name, because the agent key on WIN-TGT must match the manager's copy:

| Snapshot (both VMs) | State it holds |
|---|---|
| `phase4-agent-enrolled` | Agent 001 WIN-TGT enrolled and active; WIN-TGT at 2 GB |
| `phase4-sysmon-collection` | Sysmon/Operational channel added to the agent; backup `ossec.conf.bak-pre-sysmon` kept on WIN-TGT |
| `phase4-complete` (current) | Alerts triaged; end of Phase 4 ([snapshots](../evidence/screenshots/phase4-complete-snapshots.png)) |

Every snapshot was taken with the VM **powered off** (confirmed with `VBoxManage list runningvms` returning nothing), so none contains a saved memory state. WIN-TGT's Phase 3 snapshots still hold its original 4 GB configuration.

## 11. Verification

| # | Test | Expected | Result | Evidence |
|---|---|---|---|---|
| 1 | ISO integrity | Matches Ubuntu `SHA256SUMS` | **Pass** | [ISO hash](../evidence/screenshots/phase4-iso-hash.png) |
| 2 | VM configuration | BIOS, 4 GB, soc-lab + NAT, two localhost forwards | **Pass** | [VM config](../evidence/screenshots/phase4-wazuh-srv-vm-config.png) |
| 3 | Lab address, single default route via NAT | `10.10.10.10/24`, default via `10.0.3.2` only | **Pass** | [Installer before](../evidence/screenshots/phase4-ubuntu-network-before.png), [after](../evidence/screenshots/phase4-ubuntu-network-static.png), [storage](../evidence/screenshots/phase4-ubuntu-storage.png), [first boot](../evidence/screenshots/phase4-wazuh-srv-first-boot.png) |
| 4 | SSH host key verified | Fingerprint matches console | **Pass** | [DNS and host key](../evidence/screenshots/phase4-dns-and-hostkey.png), [SSH from host](../evidence/screenshots/phase4-ssh-from-host.png) |
| 5 | Fully patched before install | 0 upgradable | **Pass** | [Post-update](../evidence/screenshots/phase4-post-update.png), [base snapshot](../evidence/screenshots/phase4-wazuh-srv-snapshot-base.png) |
| 6 | Wazuh installed | `Installation finished.`, no `ERROR` | **Pass** | [Install log](../evidence/screenshots/phase4-install-finished-log.png) |
| 7 | Services healthy | 4 × `active`, Filebeat → indexer TLS OK | **Pass** | [Health](../evidence/screenshots/phase4-wazuh-health.png) |
| 8 | Disk usage explained and reduced | VD database identified; `apt clean` | **Pass**: 45% used | [du](../evidence/screenshots/phase4-disk-usage.png), [apt clean](../evidence/screenshots/phase4-apt-clean.png) |
| 9 | Stable on 1 vCPU | No lockups while host awake; services stay active | **Pass** | [Resume](../evidence/screenshots/phase4-soak-resume-uptime.png), [final check](../evidence/screenshots/phase4-soak-final.png), [journal times](../evidence/screenshots/phase4-soak-lockups-host-standby.png), [awake re-check](../evidence/screenshots/phase4-awake-recheck.png) |
| 10 | Dashboard certificate | Server fingerprint = browser fingerprint | **Pass** | [Server side](../evidence/screenshots/phase4-dashboard-cert-fingerprint-server.png) (browser side compared live, not captured) |
| 11 | Dashboard login and overview | Logged in; no agents; no errors | **Pass** | [Overview](../evidence/screenshots/phase4-dashboard-overview.png) |
| 12 | Self-alerts triaged | Every alert explained | **Pass** | [Low alerts](../evidence/screenshots/phase4-manager-self-alerts.png), [medium alerts](../evidence/screenshots/phase4-manager-self-alerts-medium.png), [dpkg and clock](../evidence/screenshots/phase4-unattended-upgrades-dpkg-timedatectl.png), [unattended-upgrades log](../evidence/screenshots/phase4-unattended-upgrades-log.png) |
| 13 | Clean server snapshot before enrolment | `phase4-dashboard-verified` current, VM powered off | **Pass** | [Snapshots](../evidence/screenshots/phase4-wazuh-srv-snapshot-dashboard-verified.png) |
| 14 | Agent installer authentic | Hash matches on both ends; Authenticode `Valid`, signer Wazuh, Inc | **Pass** | [Download](../evidence/screenshots/phase4-agent-msi-download.png), [transfer](../evidence/screenshots/phase4-agent-msi-transfer-server-log.png), [hash and signature](../evidence/screenshots/phase4-agent-msi-hash-signature.png) |
| 15 | WIN-TGT agent enrolled and reporting | Agent `active` in `agent_control` and the dashboard | **Pass** | [Install](../evidence/screenshots/phase4-agent-install-connected.png), [agent_control](../evidence/screenshots/phase4-agent-control-list.png), [dashboard](../evidence/screenshots/phase4-agent-dashboard-active.png) |
| 16 | Agent survives a reboot | Reconnects without intervention | **Pass** | [After boot](../evidence/screenshots/phase4-agent-reconnect-after-boot.png), [after restore](../evidence/screenshots/phase4-sysmon-after-restore.png) |
| 17 | Sysmon channel collected | `(1951) Analyzing event log: 'Microsoft-Windows-Sysmon/Operational'` | **Pass** | [Agent log](../evidence/screenshots/phase4-sysmon-channel-collected.png) |
| 18 | Sysmon events reach the SIEM | Sysmon alerts for WIN-TGT in Threat Hunting and `alerts.json` | **Pass**: 31 = 31 | [Dashboard](../evidence/screenshots/phase4-sysmon-alerts-dashboard.png), [CLI](../evidence/screenshots/phase4-sysmon-alerts-grep-observer-effect.png) |
| 19 | Endpoint alerts triaged | Every rule explained | **Pass** | [92205](../evidence/screenshots/phase4-alert-92205-pspolicytest.png), [92066](../evidence/screenshots/phase4-alert-92066-secedit-sca.png), [92058](../evidence/screenshots/phase4-alert-92058-sdbinst.png), [sdbinst signature](../evidence/screenshots/phase4-sdbinst-signature.png), [shim folder and InstalledSDB](../evidence/screenshots/phase4-shim-folder-installedsdb.png), [Custom](../evidence/screenshots/phase4-shim-custom-registry.png) |
| 20 | Paired snapshots | `phase4-complete` current on both VMs, taken powered off | **Pass** | [Snapshots](../evidence/screenshots/phase4-complete-snapshots.png) |

## 12. Findings

### Finding 4.1: guest instability with 2 vCPUs on the Windows hypervisor

**Observation:** With 2 vCPUs, WAZUH-SRV intermittently hung at boot, logged soft lockups under load, and twice froze completely.

**Evidence:**

- Boot hangs in the initramfs at `Begin: Loading essential drivers`, one with a kernel call trace in `init_module` after 710 s ([hang](../evidence/screenshots/phase4-boot-hang-initramfs.png), [call trace](../evidence/screenshots/phase4-boot-hang-calltrace.png), [second hang](../evidence/screenshots/phase4-boot-hang-2-initramfs.png)). A plain retry booted normally ([retry](../evidence/screenshots/phase4-boot-retry-ssh-ok.png)).
- During install attempt 2: `watchdog: BUG: soft lockup - CPU#1 stuck for 121s! [G1 Refine]` (a Java garbage-collector thread), then a full freeze ([console](../evidence/screenshots/phase4-soft-lockup-console.png), [SSH dropped](../evidence/screenshots/phase4-attempt2-ssh-dropped.png)).
- On 2026-10-22, about an hour after boot: `rcu_preempt self-detected stall`, `Possible timer handling issue on cpu=1`, a kernel thread starved for 222577 jiffies, and soft lockups on both CPUs, after which the guest stopped responding ([console](../evidence/screenshots/phase4-rcu-stall-soft-lockups.png)). VirtualBox's per-vCPU counters had stopped advancing.

**Analysis:** The symptoms point to the same root as Finding 3.1: VirtualBox running on the Windows hypervisor fails to schedule or deliver timer interrupts to a second virtual CPU reliably. The failure is intermittent rather than deterministic (the same configuration installed successfully on attempts 3 and 4), which made it hard to pin down. The host fix, disabling Virtualization-Based Security or adding a separate boot entry without the hypervisor, was considered and **declined by the owner**: the laptop's own protections (Memory Integrity, Secure Launch, BitLocker with TPM) take priority over lab performance. With 1 vCPU there is no second processor to fall out of step, and the soak test (section 7) showed no lockups while the host was awake.

**Risk:** Low to medium. One vCPU makes the server slower, especially at boot (Finding 4.2), and may struggle with many agents or heavy searches. It is adequate for this lab's one or two agents.

**Recommendation and status:** Run WAZUH-SRV on 1 vCPU and keep host security features on. Revisit if the host configuration changes or a later VirtualBox release fixes SMP under NEM. **Mitigated.**

### Finding 4.2: Wazuh services time out during start on a slow virtual CPU

**Observation:** On install attempt 1 the installer reported `wazuh-indexer could not be started` and removed everything. After the move to 1 vCPU, `wazuh-manager` failed at boot with `Result: timeout`.

**Evidence:** `journalctl -u wazuh-indexer`: started 14:30:13, `start operation timed out` at 14:33:13 (exactly 180 s), with 3 min 35 s of CPU consumed; no out-of-memory messages in `dmesg`, 3.4 GiB available ([diagnosis](../evidence/screenshots/phase4-indexer-diag.png)). For the manager, the journal showed the start killed while the boot was still loading every other service; the same `wazuh-control start` completed in 27 s once the boot settled.

**Analysis:** Both services are healthy but start slowly when CPU is scarce. OpenSearch (a Java application) is CPU-bound while it starts, and on one vCPU the manager competes with the indexer and dashboard at boot. systemd treats a service that has not reported "started" within its time limit as failed and kills it. Memory was ruled out first, because it is the more common cause of indexer failures.

**Risk:** Medium if not fixed: the SIEM would come up without its manager after a reboot and silently stop processing events.

**Recommendation and status:** Systemd drop-ins raise the start limit without editing the vendor's unit files, so package upgrades do not overwrite them:

```bash
# /etc/systemd/system/wazuh-indexer.service.d/override.conf
# /etc/systemd/system/wazuh-manager.service.d/override.conf
[Service]
TimeoutStartSec=600
```

After `systemctl daemon-reload`, `systemctl show -p TimeoutStartUSec` reports `10min`, and all four services have come up on their own at every boot since ([indexer drop-in and attempt 2](../evidence/screenshots/phase4-indexer-timeout-fix-and-attempt2.png)). **Remediated.**

### Finding 4.3: a working install lost to snapshot handling

**Observation:** After install attempt 3 succeeded, the next boot showed all Wazuh services `inactive` and `filebeat: command not found`. Later, a snapshot was taken while the VM was still shutting down.

**Evidence:** The login banner showed `Last login: Mon Oct 19 11:26:06`, a session from before the base snapshot, and VirtualBox's service log recorded a snapshot restore at 10:18:23 UTC immediately before the VM was started ([lost install](../evidence/screenshots/phase4-wazuh-lost-after-restore.png)). On attempt 4, `snapshot take` ran while `list runningvms` still listed the VM, producing a snapshot with 1.5 GB of saved memory; the guest only reached its power-off state four minutes later ([snapshot during shutdown](../evidence/screenshots/phase4-snapshot-taken-during-shutdown.png)).

**Analysis:** Two process errors, not technical faults. The restore came either from re-running a command block that contained `snapshot restorecurrent`, or from the "Restore current snapshot" option in VirtualBox's power-off dialog. The live snapshot happened because `poweroff` inside the guest returns immediately while shutdown continues in the background. A snapshot taken mid-shutdown captures a half-stopped system and would restore into that state.

**Risk:** Lost work (about an hour here). In a real environment, the same mistake while restoring a server could also silently roll back security patches or logs.

**Recommendation and status:** Take a snapshot immediately after any success, with the VM confirmed off (`list runningvms` empty). Never re-run a command block that contains a restore. Leave "Restore current snapshot" unticked when closing a VM window. The live snapshot was deleted and replaced with an offline one. **Process corrected.**

### Finding 4.4: false soft-lockup alarms caused by the host going to sleep

**Observation:** The soak test logged five soft lockups (285 s to 3045 s) and an RCU stall on 22 October, and one more soft lockup (267 s) during the re-check on 28 October.

**Evidence:** Real write times from `journalctl -k`, compared with Windows `Kernel-Power` events 506/507 (entering and exiting Modern Standby), all in UTC with the host's clock offset removed (Finding 4.5):

| Host asleep | Guest reported | Delay after wake |
|---|---|---|
| 16:45:43 → 16:58:13 (22 Oct) | 16:58:54, stuck 698 s | 41 s |
| 16:59:54 → 17:31:15 | 17:31:41, stuck 442 s, plus RCU stall | 26 s |
| 17:32:54 → 18:32:28 | 18:32:55, stuck 285 s and 3045 s | 27 s |
| 18:34:48 → 18:47:53 | 18:48:20, stuck 732 s | 27 s |
| 10:41:32 → 10:46:19 (28 Oct) | 10:46:23, stuck 267 s | 4 s |

([journal times](../evidence/screenshots/phase4-soak-lockups-host-standby.png), [re-check](../evidence/screenshots/phase4-awake-recheck.png)). Several of the stuck tasks were `swapper/0:0`, the kernel's idle task.

**Analysis:** In Modern Standby, Windows stops scheduling the VM's virtual CPU. When the host wakes, the guest's watchdog sees that minutes passed without progress and reports a lockup. An idle task cannot genuinely lock a CPU, which is a strong hint that the guest was simply not running. Unlike the real hangs in Finding 4.1, the guest recovered every time, with services still active. The first comparison, built on `dmesg -T`, paired the events slightly wrong, because that option estimates times from the boot time; the journal's recorded times gave the exact match.

**Risk:** Low for the lab, but misleading: a stability test can fail for reasons that have nothing to do with the system under test. Event times inside the guest also lag after the host wakes.

**Recommendation and status:** Keep the host plugged in and set "sleep when plugged in" to Never during lab sessions and soak tests. When a guest reports a lockup, check the host's power events before blaming the guest. Host sleep was set to Never on 2026-10-28. **Remediated.**

### Finding 4.5: the host clock is about 2 minutes 48 seconds fast

**Observation:** Alerts on WAZUH-SRV appeared to start two minutes before VirtualBox logged the VM's resume, and every event in Finding 4.4 was offset by a similar amount.

**Evidence:** The guest reports `System clock synchronized: yes` with NTP active. On the host, `w32tm /stripchart /computer:time.windows.com` measured −167.58 s and, 40 minutes later, −167.62 s. The Windows Time service is configured with `Type = NoSync`, meaning automatic synchronisation is off.

**Analysis:** The guest's clock is correct; the host's clock has drifted, and VirtualBox's log uses host time. WIN-TGT has no internet access and takes its time from the host, so once it is enrolled its events would arrive about three minutes "in the future" compared with the server's. Correlating events across hosts is the core of an investigation, and a few minutes of skew is enough to put cause and effect in the wrong order.

**Risk:** Medium for later phases: incorrect timelines in attack simulations.

**Recommendation and status:** Turn on "Set time automatically" on the host and sync, before WIN-TGT is enrolled. Record the offset at the start of each investigation regardless.

Automatic time was turned on and the host synchronised on 2026-10-28, before enrolment. On 2026-10-29 `w32tm /stripchart` measured −0.03 s to +0.17 s against `time.windows.com`, and WIN-TGT's Sysmon `utcTime` values agree with the server's alert times. `w32tm /query /status` still reports `Source: Local CMOS Clock`, so the host is not syncing continuously and may drift again. **Remediated; offset to be re-checked at the start of each investigation.**

### Finding 4.6: host memory is insufficient for two 4 GB VMs

**Observation:** With no VMs running, the host had 4.4 GB of available memory. Agent enrolment needs WAZUH-SRV and WIN-TGT (4 GB each) running together.

**Evidence:** `\Memory\Available MBytes` = 4440. Largest consumers: Edge WebView2 (25 processes, 1.2 GB), VS Code and its helpers (2.3 GB), Chrome (0.8 GB), Snipping Tool (0.7 GB), NordVPN and OneDrive (0.4 GB).

**Analysis:** Running both VMs as configured would force Windows to page VM memory to disk, which stalls guests in exactly the way this phase spent days ruling out. The original plan of three VMs at once assumed more free memory than the host actually has with everyday applications open.

**Risk:** Medium: unreliable results in Step 7 and later multi-VM exercises.

**Recommendation and status:** Reboot the host and close non-essential applications before multi-VM sessions; measure available memory with WAZUH-SRV running before starting WIN-TGT; if needed, run WIN-TGT at 3 GB for agent work (reversible, the Phase 3 snapshot keeps 4 GB).

After a host restart with applications closed, 2677 MB was free with WAZUH-SRV running, not enough for 3 GB. WIN-TGT was set to **2 GB** for this phase. With both VMs running, free host memory ranged from about 860 MB to 2 GB, with short bursts of paging (up to 59 pages/s). Windows 11 ran on 2 GB but is below Microsoft's 4 GB minimum, so heavier work on WIN-TGT (attack simulations, large Sysmon volumes) will feel the limit, and Finding 4.10 may be a symptom. **Mitigated: WIN-TGT at 2 GB; check free host memory before every multi-VM session.**

### Finding 4.7: a one-character configuration typo stopped the endpoint agent

**Observation:** After the Sysmon channel was first added to `ossec.conf`, `Restart-Service WazuhSvc` left the agent `Stopped`.

**Evidence:** The appended block read `<log_format>eventchannel<log_format/>`, a self-closing tag where a closing tag `</log_format>` belonged ([typo](../evidence/screenshots/phase4-sysmon-ossec-conf-typo-stopped.png)). The agent log recorded `ERROR: (1226): Error reading XML file 'ossec.conf': (line 0)` at 13:03:03 and again at 13:21:03 EAT, each followed by `Exit completed`. Restoring `ossec.conf.bak-pre-sysmon` brought the agent back to `Running`; the corrected block, pasted rather than retyped, started cleanly ([rollback and fix](../evidence/screenshots/phase4-sysmon-ossec-conf-rollback-fix.png)).

**Analysis:** The agent refuses to start with invalid configuration rather than running with part of it. That is safe for the agent but leaves the endpoint unmonitored, and nothing on the endpoint warns the user. The backup taken beforehand turned the recovery into a single command. The line number in the error (`line 0`) was no help in locating the fault; comparing the file with the backup was.

**Risk:** Medium in a real environment. A broken agent is a blind spot, and an attacker who can edit `ossec.conf` can create the same blind spot on purpose.

**Recommendation and status:** Back up before every change; paste rather than retype configuration; after a restart, check the service state and the agent log for `ERROR` before moving on. For more than one endpoint, manage agent configuration centrally (agent groups and `agent.conf` on the manager, checked with `verify-agent-conf`) and alert on agent disconnection. **Fixed; process adopted. Disconnection alerting to be reviewed in Phase 5.**

### Finding 4.8: the agent's own compliance scan raises suspicious-looking alerts

**Observation:** About 30 seconds after the agent restarted, WIN-TGT raised a burst of Sysmon-based alerts within 8 seconds, including level 9 "Powershell process created an executable file in Windows root folder" and level 4 "SecEdit.exe binary in a suspicious location".

**Evidence:** The 92066 alert's parent command line is `powershell secedit /export /cfg $env:TEMP\secpol.cfg; Get-Content … | Select-String "ResetLockoutCount"; Remove-Item …`, run as SYSTEM from `C:\Program Files (x86)\ossec-agent\` ([92066](../evidence/screenshots/phase4-alert-92066-secedit-sca.png)). That matches a CIS Windows 11 check on the account lockout policy. The 92205 alerts are PowerShell's own `__PSScriptPolicyTest_*.ps1` files in `C:\Windows\SystemTemp`, created by the same 32-bit PowerShell ([92205](../evidence/screenshots/phase4-alert-92205-pspolicytest.png)). The burst lines up with the SCA scan that runs at agent start ([install log](../evidence/screenshots/phase4-agent-install-connected.png)).

**Analysis:** These are true detections of real behaviour (PowerShell exporting security policy, a binary run from `SysWOW64`), but the actor is the monitoring tool itself. The 32-bit agent starts 32-bit PowerShell and `secedit` from `SysWOW64`, which is exactly what rule 92066 treats as unusual. The same behaviour from any other parent would deserve attention, because attackers also export security policy to plan their next step.

**Risk:** Low directly, but noisy: each agent restart produces a level-9 alert. Analysts who learn to ignore this pattern could miss the real thing.

**Recommendation and status:** Do not suppress the rules. In Phase 5, add narrow exceptions that match this parent command line and working directory exactly, and keep alerting on `secedit /export` from anywhere else. Expect this burst after every agent restart until then. **Explained; tuning planned for Phase 5.**

### Finding 4.9: a level 12 alert from routine Windows maintenance

**Observation:** Rule 92058 "Application Compatibility Database launched", level 12 (the highest seen so far), fired on WIN-TGT more than once.

**Evidence:** Sysmon recorded `C:\Windows\System32\sdbinst.exe -m -bg`, parent `svchost.exe -k LocalSystemNetworkRestricted -p`, user `NT AUTHORITY\SYSTEM`, Microsoft metadata ([92058](../evidence/screenshots/phase4-alert-92058-sdbinst.png)). The checks below were made on the endpoint:

| Check | Result |
|---|---|
| `Get-AuthenticodeSignature sdbinst.exe` | `Valid`, signer `Microsoft Windows`, issuer `Microsoft Windows Production PCA 2011`; certificate expired 17 Oct 2026 but timestamped ([signature](../evidence/screenshots/phase4-sdbinst-signature.png)) |
| `C:\Windows\apppatch\Custom` | Exists, empty ([folder and registry](../evidence/screenshots/phase4-shim-folder-installedsdb.png)) |
| `HKLM\…\AppCompatFlags\InstalledSDB` | No entries |
| `HKLM\…\AppCompatFlags\Custom` | No entries ([Custom](../evidence/screenshots/phase4-shim-custom-registry.png)) |

**Analysis:** The rule exists for application shimming (MITRE ATT&CK T1546.011), in which an attacker installs a custom shim database (`sdbinst <file>.sdb`) so that their code runs whenever a chosen program starts. Every installed shim is registered under `InstalledSDB` and `Custom`, wherever its file is kept. Here the binary is genuine, the command line installs no file (`-m -bg` is Windows' own background maintenance of the built-in databases), the parent is a Windows service host, and no custom shim is registered. **Verdict: benign; no evidence of T1546.011.**

**Risk:** Low. The severity reflects what the rule *could* catch, not what happened.

**Recommendation and status:** Keep the rule. In Phase 5, consider an exception for exactly `sdbinst.exe -m -bg` with this parent, so that any other use of `sdbinst` still raises a level 12 alert. When this alert fires, check the registry keys above, not just the folder. **Closed: false positive.**

### Finding 4.10: a one-second agent disconnect with no manager-side trace

**Observation:** On 2026-10-29 the agent logged a second `(4102) Connected` 13 minutes after its startup connection.

**Evidence:** WIN-TGT's `ossec.log` ([agent log](../evidence/screenshots/phase4-agent-reconnect-log.png)):

```
18:34:18 wazuh-agent: WARNING: Server unavailable. Setting lock.
18:34:19 wazuh-agent: INFO: Trying to connect to server ([10.10.10.10]:1514/tcp).
18:34:19 wazuh-agent: WARNING: Process locked due to agent is offline. Waiting for connection...
18:34:19 wazuh-agent: INFO: (4102): Connected to the server ([10.10.10.10]:1514/tcp).
```

The manager's `ossec.log` for 15:33 to 15:35 UTC (the same minutes) contains one unrelated line, a journald rotation notice at 15:34:12 ([manager log](../evidence/screenshots/phase4-manager-log-reconnect-window.png)). A few minutes later, the host had 1158 MB free and was paging at 59 pages/s.

**Analysis:** The agent stopped receiving replies, held its events in its buffer ("Setting lock"), and reconnected within a second, so no events should have been lost. The gap was too short for the manager to mark the agent disconnected. The cause is not proven. The most likely explanation is a brief stall of the single-vCPU server while the host was short of memory (Finding 4.6), but this rests on timing alone.

**Risk:** Low as a single event. Repeated or longer gaps would mean delayed or missing alerts.

**Recommendation and status:** Note any further `Server unavailable` warnings together with the host's free memory at the time. If they recur, compare them with the manager's `wazuh-remoted` statistics before changing anything. **Open: monitoring.**

## 13. Issues encountered

| Issue | Cause | Resolution |
|---|---|---|
| `autoconfiguration failed` on the lab adapter in the installer | No DHCP on `soc-lab`, by design | Static `10.10.10.10/24`, no gateway |
| NAT address `10.0.3.15`, not `10.0.2.15` | VirtualBox numbers NAT ranges by adapter slot | Documented; no change needed |
| DHCP pushed a route and DNS server for `192.168.0.1` | The same stale host network setting seen in Phase 3 | DNS worked after unplugging and replugging the NAT cable |
| First SSH login closed without an error ([screenshot](../evidence/screenshots/phase4-ssh-first-attempt-closed.png)) | Login grace time expired while typing an invisible password | Retried |
| `hostnamect1: command not found` | Digit `1` typed instead of letter `l` | Retyped |
| Linux commands in a Windows PowerShell window (`Sudo is disabled on this machine`) | Host and guest terminals look alike | Check the prompt: `labadmin@wazuh-srv` is the server |
| `do-release-upgrade` offered at login | Ubuntu 26.04 is available | Declined; Wazuh 4.14 targets 24.04 |
| Install attempt 1 failed and rolled back ([screenshot](../evidence/screenshots/phase4-wazuh-install-attempt1-indexer-failed.png)) | Indexer start timeout | Finding 4.2 |
| `wazuh-install-files.tar` from a failed attempt left behind | The installer refuses to reuse it | Removed before re-running ([attempt 3 prep](../evidence/screenshots/phase4-attempt3-restore-and-dropin.png)) |
| Host screen unresponsive while installing | 4 GB guest plus host apps on 16 GB | Finding 4.6 |
| `NMI watchdog: Perf NMI watchdog permanently disabled` | Normal in a VM without a performance-monitoring unit; the soft-lockup detector still works | No action |
| `e1000_watchdog hogged CPU` warnings | The emulated Intel NIC is slow to access under NEM; a performance warning, not a stall | Possible later change to a `virtio-net` adapter |
| Chrome screenshot showed personal bookmarks and profile photo | Browser chrome in the frame | Bookmarks bar hidden (Ctrl+Shift+B) and profile area redacted |
| `msiexec` exit code 1639 ([screenshot](../evidence/screenshots/phase4-agent-msiexec-1639.png)) | `/1*v` (digit one) typed for the logging switch `/l*v` | Re-run with `/L*V`; always check `$p.ExitCode` after a silent install |
| Searching the agent log for `key\|enroll` returned only registry paths | `HKEY_…` and `PortKeywords` contain the search text | Search for exact message text, such as `Connected to the server` |
| `grep` "latest Sysmon alert" printed a `sudo` alert | The search command itself was logged in `alerts.json` (section 9) | Filter on structured fields, not raw text |
| `Access to the path … ossec.log is denied` | PowerShell window not elevated; the agent folder is readable only by Administrators and SYSTEM | Re-ran in an elevated window. A `C:\Windows\system32` prompt does not prove elevation; the window title or an `IsInRole(Administrator)` check does |
| `Missing argument in parameter list` | `Select` and the property name typed together | Retyped with a space |
| Agent and manager times did not line up at first glance | WIN-TGT logs in EAT, the manager in UTC | Convert to one time zone before correlating |

## 14. Lessons learned

- Rule out the cheap explanation first. Memory is the usual cause of indexer failures; the journal showed a timeout instead, which changed the fix entirely.
- Look at the host before blaming the guest. Every "lockup" in the soak test turned out to be the laptop going to sleep.
- Clocks are evidence. A three-minute drift on one machine was visible only by comparing three logs, and it would have corrupted every later timeline.
- Treat a certificate warning as a question, not an obstacle. A fingerprint compared over a second channel turns "Proceed anyway" into a verified decision.
- Every alert gets an explanation, even on a server with no agents. The first 54 alerts were the analyst's own commands and automatic updates, and proving that took three independent logs.
- Snapshots are only as good as the moment they are taken: powered off, immediately after success, and never undone by a stray restore command.
- A security trade-off is a decision, not a default. Keeping host protections on cost a CPU core, and that cost is written down.
- Trust a file because of evidence, not because of where it came from: a matching hash proves it arrived intact, and a valid signature proves who built it. Neither needs the endpoint to go online.
- Back up configuration before changing it. One wrong character silenced the endpoint, and the backup made recovery a single command.
- The monitoring tool is also a source of alerts. The first suspicious-looking burst from the endpoint was the agent's own compliance scan, identified from its parent process and working directory.
- Severity describes what a rule could catch, not what happened. The level 12 alert was closed by checking for the artefact the attack technique needs (a registered shim), not by its score.
- Searching for text can find the search itself. Filter on structured fields when the data has them.

## Next steps

Phase 5: Sysmon configuration and tuning. Review which Sysmon events reach Wazuh and at what volume, add narrow exceptions for the self-generated alerts in Findings 4.8 and 4.9, check that an agent disconnection raises an alert (Findings 4.7 and 4.10), and measure the host clock offset at the start of the session (Finding 4.5).
