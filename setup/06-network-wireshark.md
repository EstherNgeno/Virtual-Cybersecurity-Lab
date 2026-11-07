# Phase 6: Network Fundamentals and Wireshark

| | |
|---|---|
| **Status** | In progress: Stage A complete, Stage B in progress |
| **Date** | 2026-11-06 to |
| **Hosts in scope** | KALI (capture point), LNX-TGT, WIN-TGT, WAZUH-SRV |
| **Tools** | Wireshark 4.6.6, `nc`, `curl` |

## Objective

Learn to read traffic on the lab network well enough to confirm or disprove what endpoint logs claim. KALI is the capture point: its soc-lab adapter is the only one in promiscuous mode (*allow VMs*), so it can record traffic between other VMs, like a SPAN port on a physical switch.

## Plan

Running all three of KALI, WAZUH-SRV and WIN-TGT needs about 8 GB, but the host had only about 7 GB free with no VMs running ([Finding 4.6](04-wazuh-server.md#finding-46-host-memory-is-insufficient-for-two-4-gb-vms)). The phase is therefore split into stages that each run two VMs.

| Stage | VMs | Topic |
|---|---|---|
| A | KALI + LNX-TGT | ARP, ICMP, the TCP handshake, filters, cleartext protocols |
| B1 | KALI + WIN-TGT | Windows background traffic, name-resolution fallback (LLMNR / NBT-NS), endpoint log to packet correlation |
| B2 | WAZUH-SRV + WIN-TGT | The Wazuh agent channel (TCP 1514), captured on the server |

LNX-TGT was reduced from 2 GB to **512 MB** RAM for this phase, which is enough for Metasploitable 2 and matches the network plan.

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

Each connection opens with SYN → SYN/ACK → ACK. After `QUIT`, the **server** (10.10.10.30) sent the first FIN. Protocol Hierarchy labels 32.6% of the packets (14 of 43) as FTP. The rest are TCP control packets without payload (handshakes, ACKs, FINs).

### A3. HTTP Basic authentication

One request was sent with invented credentials: `curl -u labuser:NotARealPass1 http://10.10.10.30/`. The web server returned 200 and ignored the credentials, but the header still crossed the network.

## Verification

| # | Test | Result |
|---|---|---|
| 1 | Pre-flight isolation check before every capture | **Pass**: 5/5 on 6 and 7 Nov |
| 2 | ARP and ICMP read correctly | **Pass**: broadcast request, unicast reply, types 8/0, TTL 64 |
| 3 | TCP handshake and connection close identified | **Pass**: SYN, SYN/ACK, ACK; server-side FIN |
| 4 | Cleartext FTP credentials visible | **Pass**: [Follow TCP Stream](../evidence/screenshots/phase6-ftp-cleartext-credentials.png) |
| 5 | Basic auth credentials recovered from the capture | **Pass**: Wireshark decode and `base64 -d` |
| 6 | Clocks of all capture and log sources checked | **Pass**: host −2.7 s from `time.windows.com`; WIN-TGT and KALI correct in UTC (see Finding 6.3) |

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

**Recommendation and status:** Use HTTPS (TLS) for any authenticated web traffic, and prefer token or single sign-on logins with MFA. TLS also hides content from the analyst: only addresses, timing and volume remain visible. **Informational (lab).**

### Finding 6.3: the capture sensor displays a different time zone from the rest of the lab

**Observation:** KALI showed 04:38 when the time in Nairobi was about 12:38.

**Evidence:** `timedatectl`: time zone `America/New_York (EST, -0500)`, universal time 09:39:01 UTC, which matches the host. WIN-TGT displays EAT (UTC+3). Sysmon records `UtcTime` and Wazuh works in UTC. NTP is inactive on all lab VMs, which is expected without internet.

**Analysis:** The clock itself is correct, and pcap files store timestamps in UTC, so no data is wrong. However, Wireshark, file times and the shell display New York time. Matching a Kali time against a WIN-TGT time means shifting by 8 hours, which is an easy way to build a wrong timeline.

**Risk:** Low. It affects correlation accuracy, not security.

**Recommendation and status:** Set KALI to UTC (`timedatectl set-timezone UTC`), the usual choice for sensors, and write all incident times in UTC. **In progress (Stage B).**

## Issues encountered

| Issue | Cause | Resolution |
|---|---|---|
| Filter bar turned red: "10.10.10.30 was unexpected in this context" | `host 10.10.10.30` is capture-filter (BPF) syntax, typed into the display-filter bar | Display filter is `ip.addr == 10.10.10.30`. Captures are now started with `wireshark -i eth0 -f "<filter>" -k`, so the capture filter really applies |
| First capture recorded everything on eth0 | Started without a capture filter (Capture File Properties: none) | Harmless with two VMs; display filters used instead |
| FTP login failed with `503 Login with USER first.` | The `USER` line never reached the server; it ended up in the shell (`USER: command not found`) | Typed one line at a time after each reply. The capture, not the screen, showed what was actually sent |
| `base64: invalid input` | Copied Wireshark's `\r\n` line ending along with the string | Decode only the text between `Basic ` and `\r\n` |

## Lessons learned

- A capture filter decides what is recorded and loses the rest for good. A display filter only hides. Capture broadly, narrow down later.
- A pcap shows what crossed the wire, not what someone typed or saw. The terminal showed `USER msfadmin`; the network shows it was never sent.
- When the evidence disagrees with the hypothesis, change the hypothesis. The first explanation of the failed login (server ignored an early command) was wrong.
- Summaries first: Conversations and Protocol Hierarchy show where to look. A connection that lasts far longer than its siblings stands out.
- Record a MAC address with all six bytes, and report hosts by IP and role, not by MAC.

## Evidence

- Screenshot: [phase6-ftp-cleartext-credentials.png](../evidence/screenshots/phase6-ftp-cleartext-credentials.png)
- Packet captures: `phase6-arp-icmp.pcapng`, `phase6-ftp-cleartext.pcapng`, `phase6-http-basic-auth.pcapng`. They are on KALI and will be copied to [evidence/packet-captures/](../evidence/packet-captures/) at the end of the phase, when KALI and WAZUH-SRV can run together for the transfer. They contain only lab traffic and lab or invented credentials.

## Next steps

Stage B1: set KALI to UTC, capture WIN-TGT's background traffic and the LLMNR / NBT-NS fallback, then match a Sysmon network event to its packets.
