# Phase 6: Network Fundamentals and Wireshark

| | |
|---|---|
| **Status** | Complete |
| **Date** | 2026-11-06 to 2026-11-09 |
| **Hosts in scope** | KALI (capture point), LNX-TGT, WIN-TGT, WAZUH-SRV |
| **Tools** | Wireshark 4.6.6, `tcpdump`, `nc`, `curl`, `Test-NetConnection` |
| **Output** | Six packet captures in [evidence/packet-captures/](../evidence/packet-captures/) with SHA-256 hashes |

## Objective

Learn to read traffic on the lab network well enough to confirm or disprove what endpoint logs claim. KALI is the capture point: its soc-lab adapter is the only one in promiscuous mode (*allow VMs*), so it can record traffic between other VMs, like a SPAN port on a physical switch.

## Plan

Running all three of KALI, WAZUH-SRV and WIN-TGT needs about 8 GB, but the host had at most 8 GB free with no VMs running ([Finding 4.6](04-wazuh-server.md#finding-46-host-memory-is-insufficient-for-two-4-gb-vms)). The phase was therefore split into stages that each run two VMs.

| Stage | VMs | Topic |
|---|---|---|
| A | KALI + LNX-TGT | ARP, ICMP, the TCP handshake, filters, cleartext protocols |
| B1 | KALI + WIN-TGT | Windows background traffic, name-resolution fallback, endpoint log to packet correlation |
| B2 | WAZUH-SRV + WIN-TGT | The Wazuh agent channel (TCP 1514), captured on the server |

LNX-TGT was reduced from 2 GB to **512 MB** RAM for this phase, which is enough for Metasploitable 2 and matches the network plan. Closing VS Code and background apps on the host raised free memory from about 7.1 GB to 8 GB.

## Stage A: KALI and LNX-TGT (2026-11-06)

All logins used Metasploitable's public lab account (`msfadmin`) or invented credentials. Nothing real was exposed.

### A1. ARP and ICMP

Kali's ARP cache was flushed, then one ping was sent to LNX-TGT.

| Packet | Observed | Meaning |
|---|---|---|
| ARP request | Destination `ff:ff:ff:ff:ff:ff`, "Who has 10.10.10.30? Tell 10.10.10.50" | Broadcast: Kali does not yet know the MAC address, so it asks every host |
| ARP reply | "10.10.10.30 is at `08:00:27:4b:14:1a`", sent unicast to Kali `08:00:27:8a:35:d2` | The request carried Kali's MAC, so the reply goes straight back |
| ICMP | Echo request type **8**, echo reply type **0** | Same type 8 allowed by the WIN-TGT firewall rule in Phase 3 |
| Reply TTL | **64** | Linux default, not decremented: same layer-2 segment, no router |

Any host can answer an ARP request and the answer is not verified. That is the basis of ARP spoofing (T1557.002).

### A2. TCP handshake and FTP

An FTP login was typed by hand with `nc 10.10.10.30 21`. The capture holds three TCP connections.

| Stream | Client port | Duration | Content |
|---|---|---|---|
| 0 | 45056 | 299.9 s | Banner `220 (vsFTPd 2.3.4)`, then no client data; server closed with `421 Timeout.` (vsftpd's 300 s idle limit) |
| 1 | 43748 | 41.5 s | `PASS` sent without `USER` → `503 Login with USER first.` |
| 2 | 49096 | 64.6 s | Complete login: `USER` → `331`, `PASS` → `230 Login successful.` |

Each connection opens with SYN → SYN/ACK → ACK. After `QUIT`, the **server** (10.10.10.30) sent the first FIN. Protocol Hierarchy labels 32.6% of the packets (14 of 43) as FTP. The rest are TCP control packets without payload.

### A3. HTTP Basic authentication

One request was sent with invented credentials: `curl -u labuser:NotARealPass1 http://10.10.10.30/`. The web server returned 200 and ignored the credentials, but the header still crossed the network.

## Stage B1: KALI and WIN-TGT (2026-11-09)

KALI was set to UTC first (Finding 6.3). WAZUH-SRV was powered off during B1.

### B1.1 Background traffic of an idle Windows host

Capture filter `host 10.10.10.20`, about 80 s idle, then one lookup of an invented name (`ping -n 1 fileserver01`). 84 packets:

| Protocol | Packets | Destination | What it is |
|---|---|---|---|
| ARP | 71 | Broadcast | "Who has 10.10.10.10?": the Wazuh agent looking for its powered-off server. Bursts of about three requests 1 s apart, roughly every 15 s. Never answered |
| mDNS | 6 | `224.0.0.251` (multicast) | `fileserver01.local` |
| LLMNR | 4 | `224.0.0.252` (multicast) | `fileserver01` |
| NBNS | 3 | `10.10.10.255` (broadcast) | `FILESERVER01<00>` |
| TCP | **0** | | No SYN to 10.10.10.10:1514 was ever sent: without an ARP answer there is no MAC address, so no frame can be built |

How a connection fails tells you why: unanswered ARP means the host is off or not on the segment; SYN with no reply means traffic is dropped; SYN → RST means nothing listens on the port. Nmap's *open / closed / filtered* (Phase 7) rests on the same responses.

The capture filter only matched IPv4, so the IPv6 copies of the LLMNR and mDNS queries (`ff02::1:3`, `ff02::fb`) were not recorded.

### B1.2 Endpoint log to packet correlation

KALI listened with `nc -lvnp 4444`, and WIN-TGT ran `Test-NetConnection 10.10.10.50 -Port 4444` twice. Port 4444 is Metasploit's default reverse-shell port; only a plain TCP connection was made.

| Source | Connection 1 | Connection 2 |
|---|---|---|
| `nc` on KALI | `connect to [10.10.10.50] from [10.10.10.20] 49792` | `… 49816` |
| Capture on KALI | Handshake from 10.10.10.20:49792 to :4444 | Same for :49816 |
| Sysmon ID 3 on WIN-TGT | `powershell.exe`, `WIN-TGT\labadmin`, tcp, initiated, 10.10.10.20:**49792** → 10.10.10.50:4444, UtcTime 09:24:42.342 | Source port **49816**, UtcTime 09:35:52.864 |

The client's random **source port** at the same time on both sides proves it is the same connection ([Sysmon event](../evidence/screenshots/phase6-sysmon-id3-powershell-4444.png)). Each source adds what the other cannot see: Sysmon names the **process and user**; the capture shows **what crossed the network**, including WIN-TGT's reverse lookups of 10.10.10.50 (PTR queries over mDNS and LLMNR, a NetBIOS status query), each answered by KALI with ICMP port unreachable.

### B1.3 Clock test

WIN-TGT's system clock fell behind during the session. Three measurements against the host clock, which was within 2.7 s of `time.windows.com`:

| Event on WIN-TGT | Recorded UTC | Real UTC (host) | Error |
|---|---|---|---|
| Sysmon ID 1, `PING.EXE -n 1 fileserver01` | 08:33:52.059 | 08:33:53 | about 0 |
| Sysmon ID 3, PowerShell → 4444 (connection 2) | 09:35:52.864 | 09:35:52.6 | about 0 |
| `Get-Date`, same moment | 09:32:41 | 09:35:52.6 | **−3 min 11 s** |
| Sysmon ID 1, `cmd.exe /c echo clocktest` | 09:33:58.421 | 09:37:09.6 | **−3 min 11 s** |
| `Get-Date` during B2 | 10:23:54 | 10:30:11 | **−6 min 17 s** |

Screenshots: [ID 3 in real time](../evidence/screenshots/phase6-clock-test-id3-real-time.png), [ID 1 on the slow clock](../evidence/screenshots/phase6-clock-test-id1-slow-clock.png). See Finding 6.5.

## Stage B2: WAZUH-SRV and WIN-TGT (2026-11-09)

`tcpdump` ran on WAZUH-SRV for 120 s with filter `host 10.10.10.20 and tcp port 1514`, while the agent on WIN-TGT was restarted.

| Observation | Detail |
|---|---|
| Volume | 556 packets in 2 minutes, during agent shutdown (the agent flushes its queue) |
| Payload | `!001!#AES:` followed by unreadable bytes, in both directions. The **agent ID** and the cipher label are cleartext; the events are encrypted |
| End of session | `10.10.10.20.49897 > 10.10.10.10.1514: Flags [R.]` at 10:31:12, **61 s** after the stop request. A reset, not a FIN: the process was terminated with its socket open |
| Restart | `Restart-Service` hit its stop timeout ("cannot be stopped"), so the start half never ran. The agent was started by hand at 10:31:42 |
| Reconnection | Not captured: it happened after the 120 s capture ended |

On the SIEM side, `alerts.json` held only two **503 "agent started"** alerts (10:17:18 after the server booted, 10:31:47 after the manual start). There was no 100302 (agent stopped) and no 100301 (disconnected). See Finding 6.6.

A search for the two PowerShell → 4444 connections found no alert. Both raw-text matches for `4444` were the analyst's own `sudo grep` commands, logged by Wazuh. Archiving is off, so whether the events arrived at all cannot be checked. See Finding 6.7.

## Verification

| # | Test | Result |
|---|---|---|
| 1 | Pre-flight isolation check before every capture | **Pass**: 5/5 on 6, 7 and 9 Nov |
| 2 | ARP and ICMP read correctly | **Pass**: broadcast request, unicast reply, types 8/0, TTL 64 |
| 3 | TCP handshake and connection close identified | **Pass**: SYN, SYN/ACK, ACK; server-side FIN |
| 4 | Cleartext FTP credentials visible | **Pass**: [Follow TCP Stream](../evidence/screenshots/phase6-ftp-cleartext-credentials.png) |
| 5 | Basic auth credentials recovered from the capture | **Pass**: Wireshark decode and `base64 -d` |
| 6 | Windows name-resolution fallback observed | **Pass**: LLMNR, NBNS, mDNS for `fileserver01` |
| 7 | Sysmon network event matched to packets | **Pass**: 2 of 2, by source port |
| 8 | Clock offset of each log source measured | **Pass**: KALI and host correct; WIN-TGT system clock −3:11, later −6:17 |
| 9 | Agent channel identified and its encryption confirmed | **Pass**: TCP 1514, `#AES:` payload |
| 10 | Captures exported with integrity hashes | **Pass**: 6 files, [SHA256SUMS](../evidence/packet-captures/SHA256SUMS) |
| 11 | KALI snapshot | **Pass**: `phase6-complete`, taken powered off |

## Findings

### Finding 6.1: FTP sends credentials in cleartext

**Observation:** The login to LNX-TGT's FTP service is readable in the capture.

**Evidence:** [Follow TCP Stream](../evidence/screenshots/phase6-ftp-cleartext-credentials.png) of stream 2 shows `USER msfadmin`, `PASS msfadmin` and `230 Login successful.` The banner also reveals the exact version, `vsFTPd 2.3.4`.

**Analysis:** FTP has no encryption. Anyone who can see the traffic, such as a compromised host on the same segment or an ARP-spoofing attacker, can collect working credentials (T1040). vsFTPd 2.3.4 is the release with a known backdoor (CVE-2011-2523), and the banner hands that to any scanner.

**Risk:** High on a real network.

**Recommendation and status:** Replace FTP with SFTP or FTPS, and suppress version banners. In this lab the host is vulnerable by design. **Accepted (lab target); the version is assessed in Phase 8.**

### Finding 6.2: HTTP Basic authentication is encoding, not encryption

**Observation:** The request carried `Authorization: Basic bGFidXNlcjpOb3RBUmVhbFBhc3Mx`.

**Evidence:** Wireshark shows it decoded as `labuser:NotARealPass1`. `base64 -d` returns the same, with no key needed.

**Analysis:** Base64 is a reversible format for transport, not a protection. Over plain HTTP, Basic auth is as exposed as FTP.

**Risk:** High wherever Basic auth is used without TLS.

**Recommendation and status:** Use HTTPS (TLS) for any authenticated web traffic, and prefer token or single sign-on logins with MFA. Encryption also hides content from the analyst, as the Wazuh agent channel in Stage B2 shows: only addresses, timing and volume remain. **Informational (lab).**

### Finding 6.3: the capture sensor displayed a different time zone from the rest of the lab

**Observation:** KALI showed 04:38 when the time in Nairobi was about 12:38.

**Evidence:** `timedatectl`: time zone `America/New_York (EST, -0500)`, universal time 09:39:01 UTC, matching the host.

**Analysis:** The clock was correct and pcap files store timestamps in UTC, so no data was wrong. However, Wireshark, file times and the shell displayed New York time. Matching a Kali time against a WIN-TGT time (EAT, UTC+3) meant shifting by 8 hours.

**Risk:** Low. It affects correlation accuracy, not security.

**Recommendation and status:** KALI set to UTC with `timedatectl set-timezone UTC` and kept in snapshot `phase6-complete`. Incident times are written in UTC. **Remediated.**

### Finding 6.4: WIN-TGT broadcasts unresolved names to the whole network

**Observation:** One failed lookup of `fileserver01` produced LLMNR, NBNS and mDNS queries to multicast and broadcast addresses.

**Evidence:** `phase6-wintgt-chatter.pcapng`: 4 LLMNR to `224.0.0.252`, 3 NBNS to `10.10.10.255`, 6 mDNS to `224.0.0.251`. No host answered.

**Analysis:** Windows accepts the first answer to these queries without verifying it. An attacker on the segment can answer "that is me", receive the connection and capture the user's NTLMv2 hash for offline cracking or relay (LLMNR/NBT-NS poisoning, T1557.001). A single mistyped share name is enough to trigger it.

**Risk:** High on a real internal network.

**Recommendation and status:** Disable LLMNR (Group Policy *Turn off multicast name resolution*), disable NetBIOS over TCP/IP, and restrict mDNS. Detect any host answering these queries that is not a name server. Kept enabled for now as the precondition for a Phase 10 scenario. **Open: carried into Phase 10.**

### Finding 6.5: endpoint events from the same Sysmon log disagree by minutes

**Observation:** WIN-TGT's system clock lost 3 min 11 s during the session, later 6 min 17 s. Process events (ID 1) carried the slow time; network events (ID 3) carried the correct time.

**Evidence:** Section B1.3. The first ID 1 event of the day was correct, so the clock slipped afterwards. Both slips happened while WIN-TGT or the host was under heavy load: a recursive file search on WIN-TGT (09:18 to 09:25 UTC) and WAZUH-SRV booting (10:16 UTC). WIN-TGT has no Guest Additions and no NTP source, so nothing corrects the clock.

**Analysis:** The VM most likely missed timer ticks while starved of CPU. Sysmon network events are timestamped by a different Windows mechanism (Event Tracing for Windows), which kept the right time. This explanation fits the measurements but was not proven. As a result, a process can appear to start minutes **after** the network connection it made, and a timeline built from endpoint time alone puts events in the wrong order.

**Risk:** Medium for the lab. Phase 10 investigations depend on correct ordering.

**Recommendation and status:** Before each investigation, measure WIN-TGT's offset against a known-good clock and record it. Provide a lab time source, for example WAZUH-SRV as an NTP server for WIN-TGT. Treat the capture and the manager's receive time as the reference. **Open: fix before Phase 10.**

### Finding 6.6: killing the Wazuh agent leaves no tamper alert

**Observation:** The agent was terminated and restarted, and Wazuh raised only a routine "agent started" alert.

**Evidence:** The capture shows the session ending with a **RST** from WIN-TGT at 10:31:12. `alerts.json` shows no rule 100302 (agent stopped) and no 100301 (disconnected), only 503 at 10:31:47.

**Analysis:** Rule 100302 depends on the agent sending a "stopped" message, which a terminated process never sends. Rule 100301 needs 2 minutes of silence; the real gap was 35 s. An attacker who kills the sensor and restarts it quickly (T1562.001) leaves a level-3 alert that looks like normal maintenance. The network capture shows what the SIEM did not: an abrupt reset instead of a clean close.

**Risk:** Medium. It defeats the tamper detection built in Phase 5.

**Recommendation and status:** Alert on a 503 that is not preceded by a 506 within a few minutes, and collect Windows System events 7031 and 7034 (service terminated unexpectedly). **Open: Phase 10 detection work.**

### Finding 6.7: a PowerShell connection to port 4444 raises no SIEM alert

**Observation:** PowerShell on WIN-TGT connected to KALI on TCP 4444, Metasploit's default port. Sysmon logged it; Wazuh raised nothing.

**Evidence:** Two Sysmon ID 3 events (B1.2). No matching alert in `alerts.json`; the only raw-text hits were the analyst's own commands. Archiving is off, so Wazuh keeps no other record.

**Analysis:** The Wazuh base rule for Sysmon network events is level 0. A reverse shell would leave the same trace: one local Sysmon event and nothing in the SIEM.

**Risk:** High. Command-and-control over a common attack port goes unnoticed centrally.

**Recommendation and status:** Add a rule for Sysmon ID 3 from script interpreters (`powershell.exe`, `pwsh.exe`, `cmd.exe`, `wscript.exe`, `mshta.exe`) to non-standard ports, with a higher level for known attack ports (T1059.001, T1571). **Open: Phase 10 detection work.**

## Issues encountered

| Issue | Cause | Resolution |
|---|---|---|
| Filter bar turned red: "10.10.10.30 was unexpected in this context" | `host 10.10.10.30` is capture-filter (BPF) syntax, typed into the display-filter bar | Display filter is `ip.addr == 10.10.10.30`. Captures were then started with `wireshark -i eth0 -f "<filter>" -k` |
| FTP login failed with `503 Login with USER first.` | The `USER` line went to the shell, not to `nc` | Typed one line at a time after each reply. The capture, not the screen, showed what was sent |
| `base64: invalid input` | Copied Wireshark's `\r\n` along with the string | Decode only the text between `Basic ` and `\r\n` |
| Sysmon queries returned nothing | PowerShell was not elevated; `-ErrorAction SilentlyContinue` hid "unauthorized operation", and `Get-WinEvent` reported access denied as "No events were found" | Checked elevation with `IsInRole('Administrators')` first; reran in an elevated window |
| Search for the Sysmon config file ran for minutes | Recursive search of `C:\Users` on a 2 GB VM | Stopped; tested behaviour directly instead. The load probably triggered the clock slip in Finding 6.5 |
| `startvm WAZUH-SRV` did nothing | Command failed in the PowerShell window (likely `$vb` not set there) | Started from a working session; confirm with `list runningvms` |
| `Restart-Service WazuhSvc` failed, agent left stopped | Stop took 61 s, longer than the cmdlet waits | `Start-Service` by hand; agent back within 90 s |
| Raw-text search for `4444` returned two "hits" | The search commands themselves were logged by Wazuh's sudo monitoring | Search structured fields, not raw text |
| First `scp` from KALI closed before the password prompt | Host-key check took longer than the server's login grace time | Repeated the command; the key was already trusted |

## Lessons learned

- A capture filter loses what it does not match, for good: here it hid the IPv6 copies of the name queries. Capture broadly, narrow down later.
- A pcap shows what crossed the wire, not what someone typed or saw.
- An empty result is not evidence of absence until you have confirmed you were allowed to look. Never suppress errors in an evidence query.
- The source port links a network flow to an endpoint event. The two sources answer different questions: who and which process, versus what was actually sent.
- Measure every clock against a reference before building a timeline, and expect one host's events to disagree with each other.
- A RST from a security agent followed by silence is what sensor tampering looks like on the wire.
- When the evidence disagrees with the hypothesis, change the hypothesis. Two working explanations in this phase were wrong and were corrected by the data: the early FTP command and the boot-time clock catch-up.

## Evidence

**Screenshots**

- [phase6-ftp-cleartext-credentials.png](../evidence/screenshots/phase6-ftp-cleartext-credentials.png)
- [phase6-sysmon-id3-powershell-4444.png](../evidence/screenshots/phase6-sysmon-id3-powershell-4444.png)
- [phase6-clock-test-id3-real-time.png](../evidence/screenshots/phase6-clock-test-id3-real-time.png)
- [phase6-clock-test-id1-slow-clock.png](../evidence/screenshots/phase6-clock-test-id1-slow-clock.png)

**Packet captures** ([evidence/packet-captures/](../evidence/packet-captures/), hashes in [SHA256SUMS](../evidence/packet-captures/SHA256SUMS)). They contain only lab traffic and lab or invented credentials.

| File | Packets | Captured on | Content |
|---|---|---|---|
| `phase6-arp-icmp.pcapng` | 10 | KALI | A1 |
| `phase6-ftp-cleartext.pcapng` | 43 | KALI | A2, Finding 6.1 |
| `phase6-http-basic-auth.pcapng` | 17 | KALI | A3, Finding 6.2 |
| `phase6-wintgt-chatter.pcapng` | 84 | KALI | B1.1, Finding 6.4 |
| `phase6-wintgt-correlation.pcapng` | 953 | KALI | B1.2 (filter `host 10.10.10.20`) |
| `phase6-agent-1514.pcap` | 556 | WAZUH-SRV | B2, Finding 6.6 |

Transfer path: KALI → WAZUH-SRV (`scp`, host key verified in full) → host (`scp -P 2222`) → repository, with the hashes checked on arrival.

## Snapshots

| VM | Snapshot | Note |
|---|---|---|
| KALI | `phase6-complete` (current) | UTC time zone; trusts WAZUH-SRV's host key |
| WAZUH-SRV, WIN-TGT | `phase5-complete` (unchanged) | No configuration changes in this phase |
| LNX-TGT | `phase2-clean-baseline` (unchanged) | Stores 2048 MB; after a restore, set 512 MB again |

## Next steps

Phase 7: Nmap reconnaissance against LNX-TGT and WIN-TGT. Before Phase 10: a lab time source for WIN-TGT (Finding 6.5) and detection rules for Findings 6.6 and 6.7.
