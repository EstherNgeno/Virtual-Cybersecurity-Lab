# Phase 7: Nmap Reconnaissance

| | |
|---|---|
| **Status** | Complete |
| **Date** | 2026-11-11 |
| **Hosts in scope** | KALI (scanner and capture point), LNX-TGT, WIN-TGT |
| **Tools** | Nmap 7.99, TShark 4.6.6, Windows `auditpol` and `Get-WinEvent` |
| **ATT&CK** | T1018 Remote System Discovery, T1046 Network Service Discovery |
| **Output** | 8 scans in [evidence/scans/](../evidence/scans/), 3 packet captures in [evidence/packet-captures/](../evidence/packet-captures/) with SHA-256 hashes |

## Objective

Scan the lab targets from KALI, and at the same time observe each scan from the defender's side: on the wire (pcap), in the target's own logs, and in what would reach the SIEM. The question for every scan is what the attacker learned and what the defender could have seen.

## Plan

Free host memory allowed two VMs plus KALI at most ([Finding 4.6](04-wazuh-server.md#finding-46-host-memory-is-insufficient-for-two-4-gb-vms)), so the phase ran in two stages.

| Stage | VMs | Topic |
|---|---|---|
| A | KALI + LNX-TGT (512 MB) | Host discovery, SYN vs connect scan, full-port service and OS detection, safe NSE scripts |
| B | KALI + WIN-TGT | Scanning through a host firewall; endpoint visibility of the scan; testing a logging fix |

WAZUH-SRV stayed off. Wazuh can only receive what the endpoint logs, so the endpoint's own logs answered the SIEM question (see B2).

All times are UTC. LNX-TGT logs in EST (UTC−5); its times below are converted. WIN-TGT's clock was checked against the host before scanning and was correct (Finding 6.5 only appears under load).

## Stage A: KALI and LNX-TGT

### A1. Host discovery: `nmap -sn 10.10.10.0/24`

09:23:14, 6.14 s. Two hosts up: LNX-TGT (MAC `08:00:27:4B:14:1A`, labelled *Oracle VirtualBox virtual NIC* from its vendor prefix) and KALI itself. WAZUH-SRV and WIN-TGT were off.

The capture (`phase7-discovery.pcapng`) holds 516 frames, **all ARP**, with no ICMP or other IP traffic. As root on its own subnet, Nmap discovers hosts with ARP, which a host cannot ignore and which never reaches the IP layer.

| ARP requests | Count |
|---|---|
| 254 addresses that never replied | 2 each (one retry) = 508 |
| 10.10.10.30 | 4, all broadcast, each answered in under 1 ms |
| Replies | 4 |

All four requests to 10.10.10.30 were broadcast, so they came from Nmap, not from the kernel re-validating a cache entry. Why Nmap re-asked a host that had already answered is not proven; the likely reason is its timing probes during a sweep.

**Signature:** about 510 broadcast ARP requests from one MAC to 255 sequential addresses in 1.4 s. Firewalls, IP-based IDS rules and endpoint agents do not see it; only layer-2 monitoring does.

### A2. SYN scan vs connect scan

Same four ports, two methods, captured together (`phase7-syn-vs-connect.pcapng`, 25 packets, exactly the predicted 11 + 14). Both reported 21, 22 and 80 **open** and 8888 **closed**.

| | `-sS` (09:56:13) | `-sT` (09:56:33) |
|---|---|---|
| Open port 22 | SYN → SYN/ACK → **RST** (3 packets; the RST comes from KALI's kernel, which never opened the connection) | SYN → SYN/ACK → **ACK** → RST/ACK (4 packets; handshake completed, zero bytes sent) |
| Closed port 8888 | SYN → RST/ACK | SYN → RST/ACK |
| Source port | **61580 for every probe** (crafted packets) | New random port per probe, like normal traffic |

`-sT` was run without `sudo`. A connect scan needs no privileges, so an attacker on a compromised low-privilege account can still map ports. (Kali's Nmap still recorded `--privileged` in the saved command line; the scan type was set explicitly, so the result is unaffected.)

### A3. What LNX-TGT logged

Searching LNX-TGT's `auth.log`, `syslog` and `vsftpd.log` for `10.10.10.50` returned nothing for either scan. Logging was working (CRON and console-login entries present). Searching by **time** found one line:

```
Nov 11 04:56:33 metasploitable xinetd[4806]: warning: can't get client address: Connection reset by peer
```

04:56:33 EST is 09:56:33 UTC, the second of the connect scan. A service run by `xinetd` accepted the connection and was reset before it could read the client's address. The SYN scan never completed a handshake and left nothing. See Finding 7.1.

### A4. Full-port service and OS detection: `nmap -p- -sV -O`

10:20:27 to 10:22:54, 147.68 s. **30 open TCP ports**, 65,505 closed.

| Group | Ports and versions |
|---|---|
| Backdoor already present | 1524 `bindshell` ("Metasploitable root shell") |
| Versions with known critical flaws | 21 vsftpd 2.3.4 (CVE-2011-2523 backdoor), 3632 distccd v1 (CVE-2004-2687), 139/445 Samba (exact version in A5), 6667/6697 UnrealIRCd (version not identified), 2121 ProFTPD 1.3.1 |
| Cleartext or trust-based logins | 23 telnet, 512 rexec, 513 rlogin, 514 rsh |
| Databases and admin interfaces | 3306 MySQL 5.0.51a, 5432 PostgreSQL 8.3, 5900 VNC 3.3, 8180 Tomcat, 8009 AJP, 1099 and 35980 Java RMI, 8787 Ruby DRb |
| RPC and file sharing | 111 rpcbind, 2049 NFS, mountd, nlockmgr, status (the last three on high ports assigned at boot, missed by a top-1000 scan) |
| Other | 22 OpenSSH 4.7p1, 25 Postfix, 53 BIND 9.4.2, 80 Apache 2.2.8, 6000 X11 (access denied) |

OS: `Linux 2.6.9 – 2.6.33`, 1 hop (actual kernel 2.6.24). A version string is a lead, not a confirmed vulnerability: banners can be wrong, and distributions backport fixes without changing them.

This scan was not quiet. Between 10:20:46 and 10:20:56, LNX-TGT logged 55 lines (some duplicated across log files), many naming the scanner: `in.telnetd`, `in.rshd` and `in.rlogind` each logged `connect from 10.10.10.50`, Postfix logged `connect from unknown[10.10.10.50]` and its `anvil` rate statistics, and Tomcat logged `SEVERE` AJP protocol errors. See Finding 7.2.

### A5. Safe NSE scripts: `nmap -sV -sC` on six ports

10:36:18, 11.84 s. The `default` scripts gather information only.

| Port | Result |
|---|---|
| 21 | `ftp-anon: Anonymous FTP login allowed (FTP code 230)`; server status: control and data connections in plain text |
| 22 | Host keys DSA 1024 (deprecated) and RSA 2048 |
| 445 | **Samba 3.0.20-Debian**, an exact version where `-sV` had only "3.X – 4.X". 3.0.20 is in the range affected by CVE-2007-2447 (not tested) |
| 445 | As `guest`: computer name, FQDN `metasploitable.localdomain`, system time; `message_signing: disabled` (NTLM relay risk) |
| 3306 | `mysql-info`: version, capabilities, authentication salt, without logging in |
| 5900 | VNC protocol 3.3, VNC Authentication only (password, no user name) |

`clock-skew: mean 2h29m58s, deviation 3h32m07s, median -1s` is two samples: one correct, one 5 hours out. Five hours is LNX-TGT's EST offset, so one service most likely reported local time without a zone and was read as UTC. Which service is not shown. Timestamps without a time zone produce false skew.

## Stage B: KALI and WIN-TGT

LNX-TGT was shut down first. Its kernel ignores the ACPI power button; `sudo poweroff` on the console works.

### B1. Ground truth, then the scan

Before scanning, WIN-TGT (elevated PowerShell) showed:

| Check | Result |
|---|---|
| Firewall, all profiles | Enabled; default inbound action not configured (Windows default: block); `LogBlocked` **False**, `LogAllowed` False |
| Listening TCP ports | 135, 139, 445, 5040, 49664–49669 (10 ports) |
| Sysmon64, WazuhSvc | Running |

| Scan | Time | Result |
|---|---|---|
| `-sS` on the 10 listening ports + 8888 (not listening) | 11:01:31, 1.51 s | **All 11 filtered** |
| `-sS` top 1000 | 11:01:58, 21.38 s | All 1000 filtered (no-response) |

The capture (`phase7-wintgt-scan.pcapng`, 2,116 frames) has 94 ARP frames and 2,022 TCP packets, **all from KALI**. WIN-TGT sent no IP packet at all: no SYN/ACK, no RST, no ICMP. 1,003 ports received 2 SYNs (probe and one retry) and 4 ports received 4 (scanned twice): 1,003 × 2 + 4 × 4 = 2,022. The host still showed as "up" because ARP crosses the firewall. See Finding 7.4.

### B2. What WIN-TGT logged

Checked for the 10 minutes covering both scans:

| Source | Result |
|---|---|
| Sysmon | Active (boot activity: 137 × ID 1, 106 × ID 10, 120 × ID 13), but **0** ID 3 events involving 10.10.10.50 |
| Security events 5152, 5156, 5157 | **0** |
| Audit policy: Filtering Platform Packet Drop / Connection | No Auditing |

A 1,007-port scan left no trace on the endpoint, so nothing could reach Wazuh. Stage B with WAZUH-SRV was therefore not needed.

### B3. Testing the fix

| Time | Action |
|---|---|
| 11:08:13 | `auditpol /set /subcategory:"Filtering Platform Packet Drop" /failure:enable` |
| 11:08:30 | Same 11 ports rescanned (`-sT`): all filtered again; the attacker's view did not change |
| 11:09 | Auditing disabled again and verified (`No Auditing`) |

Result: **28 × event 5152**, all from 10.10.10.50, covering **all 11 ports** (2–3 each, one per blocked SYN including retries). No other source appeared in the one-minute window. First event:

```
11:08:28.319 UTC  Security 5152  Direction %%14592 (Inbound)
10.10.10.50:59332 -> 10.10.10.20:139  Protocol 6 (TCP)  Layer %%14610 (Receive/Accept)  FilterRTID 67173
```

## Verification

| # | Test | Result |
|---|---|---|
| 1 | Pre-flight isolation check before scanning | **Pass**: `RESULT: ISOLATED`; LNX-TGT ping 2/2; KALI time zone UTC |
| 2 | Discovery method identified from the capture | **Pass**: 516/516 frames ARP; request counts explained |
| 3 | SYN and connect scans told apart on the wire | **Pass**: 3 vs 4 packets per open port; fixed vs random source port |
| 4 | Target log visibility measured for each scan type | **Pass**: `-sS` 0 lines, `-sT` 1 line without IP, `-sV` 55 lines with IP |
| 5 | Full attack surface of LNX-TGT enumerated | **Pass**: 30 ports, versions, OS |
| 6 | NSE results recorded | **Pass**: anonymous FTP, exact Samba version, SMB signing off |
| 7 | Scan result compared with WIN-TGT's real listening ports | **Pass**: 10 listening, all reported filtered, same as a non-listening port |
| 8 | Endpoint visibility of a filtered scan measured | **Pass**: 0 events by default |
| 9 | Logging fix tested and reverted | **Pass**: 28 × 5152 with source IP and port; auditing off again |
| 10 | Evidence exported with integrity hashes | **Pass**: 8 scans, 3 captures, [SHA256SUMS](../evidence/packet-captures/SHA256SUMS) checked on arrival |
| 11 | KALI snapshot | **Pass**: `phase7-complete`, taken powered off |

## Findings

### Finding 7.1: port scans barely register in a Linux target's logs

**Observation:** A SYN scan and a connect scan of LNX-TGT's open services left almost nothing in its logs.

**Evidence:** Section A3. Search by scanner IP: 0 results. Search by time: one `xinetd` line at the second of the connect scan, without a client address ([screenshot](../evidence/screenshots/phase7-lnx-tgt-xinetd-only-trace.png)). SSH and Apache logged nothing.

**Analysis:** A SYN scan never completes a handshake, so no application ever handles it. A connect scan does complete it, but most services only log once a client sends data or authenticates. The one trace that exists cannot be found by the usual first step, searching for the attacker's IP.

**Risk:** Medium. Reconnaissance, usually the first sign of an attack, goes unseen if host logs are the only source.

**Recommendation and status:** Detect scanning on the network (IDS, flow logs, or firewall drop logs; see 7.5). When an IP search returns nothing, pivot on time. **Informational; network detection is part of Phase 10.**

### Finding 7.2: service-version detection is noisy and leaves a correlatable pattern

**Observation:** `-sV` caused 55 log lines across several services in about 10 seconds.

**Evidence:** Section A4: `in.telnetd`, `in.rshd`, `in.rlogind` and Postfix each logged `connect from 10.10.10.50`; Tomcat logged AJP protocol errors.

**Analysis:** Each line alone looks routine. The pattern is the indicator: one source touching many different services within seconds, with protocol errors.

**Risk:** Low as a finding; useful as a detection opportunity.

**Recommendation and status:** Forward LNX-TGT's syslog to the SIEM (a syslog source, since Metasploitable 2 cannot run the Wazuh agent) and alert when one source connects to several distinct services within a minute. **Open: candidate rule for Phase 10.**

### Finding 7.3: LNX-TGT exposes 30 services, including an unauthenticated root shell

**Observation:** Full-port scanning found 30 open TCP ports.

**Evidence:** [`p7-04-full.nmap`](../evidence/scans/p7-04-full.nmap) and [`p7-05-nse.nmap`](../evidence/scans/p7-05-nse.nmap): bindshell on 1524, vsftpd 2.3.4, distccd v1, Samba 3.0.20, anonymous FTP, telnet and r-services, databases and VNC open to the network, SMB signing disabled.

**Analysis:** Port 1524 gives a root shell to anyone who connects, with no exploit needed. Several other versions have public remote-code-execution flaws. The OS and most services are years past end of support.

**Risk:** Critical on any real network.

**Recommendation and status:** On a real host: remove the bindshell and unused services, patch or replace end-of-life software, restrict databases and admin interfaces to management addresses, require SMB signing, disable anonymous FTP. LNX-TGT is vulnerable by design. **Accepted (lab target); vulnerabilities assessed in Phase 8.**

### Finding 7.4: WIN-TGT's default-deny firewall hides every listening port

**Observation:** All 10 listening ports, and a port with nothing listening, were reported identically as filtered.

**Evidence:** Section B1; [`p7-06-wintgt-known.nmap`](../evidence/scans/p7-06-wintgt-known.nmap); `phase7-wintgt-scan.pcapng` shows no IP packet from WIN-TGT.

**Analysis:** A silent drop gives the scanner nothing to measure: a listening port and an empty one look the same. Only ARP revealed that the host exists.

**Risk:** Low. This is the control working.

**Recommendation and status:** Keep default-deny inbound on endpoints and open only what is needed, to named sources. **Effective control.**

### Finding 7.5: a blocked scan is invisible to the endpoint and the SIEM by default

**Observation:** A 1,007-port scan of WIN-TGT left no event on the host.

**Evidence:** Section B2: firewall drop logging off, packet-drop auditing off, Sysmon ID 3 only records connections that succeed ([screenshot](../evidence/screenshots/phase7-wintgt-no-scan-trace.png)). After enabling *Filtering Platform Packet Drop* auditing, the same scan produced 28 × event 5152 with source IP, destination port and time ([screenshot](../evidence/screenshots/phase7-wintgt-5152-by-port.png)).

**Analysis:** The firewall stopped the scan but kept no record of it, so the SIEM had nothing to alert on. This is the same pattern as Findings 6.6 and 6.7: activity that matters, but leaves no central trace. One audit setting closes the gap at the source.

**Risk:** Medium. Internal reconnaissance against Windows endpoints goes unnoticed.

**Recommendation and status:** Enable packet-drop auditing (or firewall drop logging), forward event 5152 to Wazuh, and alert on the number of **distinct destination ports per source** in a short window rather than on each event (T1046). Measure the noise first: the one-minute test was too short to judge it. Auditing was turned off again to keep WIN-TGT at its baseline. **Open: fix tested; Wazuh rule in Phase 10.**

## Issues encountered

| Issue | Cause | Resolution |
|---|---|---|
| Results "missing" after a scan | Output was in a terminal on another Kali workspace, or the capture was still running | Stop the capture first; read results from the saved `-oA` files rather than the screen |
| Long output scrolled off the window | Small terminal window | Print fields only (`tshark -T fields`, `cut`, `sed -n`) and `clear` first |
| `grep` for the scanner's IP found nothing | The only log line had no client address | Searched by time window instead |
| `vsftpd.log: Permission denied` | File is root-only (`600`) | File time showed no writes since 6 Nov, so no `sudo` was needed |
| LNX-TGT ignored `acpipowerbutton` | Ubuntu 8.04 without `acpid` | `sudo poweroff` on the console |
| `sudo nmap` not possible when typing remotely | KALI password not shared | Used `-sT`, which needs no privileges and is dropped by the firewall in the same way |
| `guestcontrol copyfrom` failed twice | Long command wrapped on paste; single files need a full destination file name, not a folder | One short command per file in a loop |

## Lessons learned

- Every scan type has a defender's view; measure it, don't assume it. Here: ARP-only discovery, a scan that left one IP-less log line, and a blocked scan that left nothing.
- *Filtered* means the scanner learned nothing about the port. A silent drop is better than a reject.
- Version detection trades stealth for information, and that trade is what makes it detectable.
- A detected version is a hypothesis. Confirm it with a second method before calling it a vulnerability (here: `-sV` "3.X – 4.X", NSE "3.0.20").
- When the IP search is empty, search by time.
- A missing time zone looks like clock skew.
- A recommendation is stronger once tested: one audit setting turned an invisible scan into 28 attributable events.

## Evidence

**Scans** ([evidence/scans/](../evidence/scans/)): each in `.nmap` (readable), `.gnmap` (grep) and `.xml`.

| File | Target | Command | Section |
|---|---|---|---|
| `p7-01-discovery` | 10.10.10.0/24 | `-sn` | A1 |
| `p7-02-syn` | LNX-TGT | `-sS -p 21,22,80,8888` | A2 |
| `p7-03-connect` | LNX-TGT | `-sT -p 21,22,80,8888` | A2 |
| `p7-04-full` | LNX-TGT | `-p- -sV -O` | A4 |
| `p7-05-nse` | LNX-TGT | `-sV -sC -p 21,22,139,445,3306,5900` | A5 |
| `p7-06-wintgt-known` | WIN-TGT | `-sS` on 10 listening ports + 8888 | B1 |
| `p7-07-wintgt-top1000` | WIN-TGT | `-sS` top 1000 | B1 |
| `p7-08-wintgt-audit` | WIN-TGT | `-sT` on the same 11 ports, auditing on | B3 |

**Packet captures** ([evidence/packet-captures/](../evidence/packet-captures/), hashes in [SHA256SUMS](../evidence/packet-captures/SHA256SUMS)), all captured on KALI:

| File | Packets | Section |
|---|---|---|
| `phase7-discovery.pcapng` | 516 | A1 |
| `phase7-syn-vs-connect.pcapng` | 25 | A2 |
| `phase7-wintgt-scan.pcapng` | 2,116 | B1 |

Transfer path: KALI → host with `VBoxManage guestcontrol copyfrom` (no network involved) → repository, hashes checked on arrival.

**Screenshots**

- [phase7-lnx-tgt-xinetd-only-trace.png](../evidence/screenshots/phase7-lnx-tgt-xinetd-only-trace.png)
- [phase7-wintgt-no-scan-trace.png](../evidence/screenshots/phase7-wintgt-no-scan-trace.png)
- [phase7-wintgt-5152-by-port.png](../evidence/screenshots/phase7-wintgt-5152-by-port.png)

## Snapshots

| VM | Snapshot | Note |
|---|---|---|
| KALI | `phase7-complete` (current) | Scan results in `~/scans`, captures in `~/captures` |
| WIN-TGT | `phase5-complete` (unchanged) | Packet-drop auditing enabled and reverted during B3 |
| LNX-TGT | `phase2-clean-baseline` (unchanged) | No configuration changes |
| WAZUH-SRV | `phase5-complete` (unchanged) | Not used in this phase |

## Next steps

Phase 8: vulnerability assessment of the services found here, confirming or ruling out the version-based leads in Finding 7.3. For Phase 10: detection rules for Findings 7.2 and 7.5, alongside 6.6 and 6.7.
