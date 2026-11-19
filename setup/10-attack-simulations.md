# Phase 10: Attack Simulations

| | |
|---|---|
| **Status** | Complete |
| **Date** | 2026-11-17 to 2026-11-19 |
| **Hosts in scope** | KALI (attacker, 10.10.10.50), WIN-TGT (target, 10.10.10.20), WAZUH-SRV (SIEM, 10.10.10.10) |
| **Tools** | Nmap 7.99, Windows PowerShell, netcat, Responder 3.2.2.0, Wazuh 4.14, Sysmon 15.22 |
| **ATT&CK** | T1046 Network Service Discovery, T1571 Non-Standard Port, T1059.001 PowerShell, T1562.001 Impair Defenses: Disable or Modify Tools, T1557.001 LLMNR/NBT-NS Poisoning |
| **Detections** | Rules 100303, 100500, 100501, 100510 in [detections/wazuh/local_rules.xml](../detections/wazuh/local_rules.xml) |
| **Closes** | Findings 7.5, 6.7, 6.6, 6.4 |

## Objective

Run four attacker techniques against WIN-TGT and detect each one from the defender's side. Every simulation starts from a question left open by an earlier phase ("this activity left no alert"), reproduces the gap, closes it, and proves the fix from the actual Wazuh alert, not from the fact that a command was run.

## Method

The same evidence-first loop was used for each simulation, refined across the three sessions:

1. **Reproduce the gap.** Run the attack and confirm from `alerts.json` that nothing useful fires. This is the "before" picture.
2. **Capture the real event.** Turn on raw archiving (`<logall_json>yes`) so every received event lands in `archives.json`, matched by a rule or not. This separates a *collection* problem (the event never arrived) from a *detection* problem (it arrived but no rule matched).
3. **Find the anchor.** A custom Wazuh rule only fires if it chains (`if_sid`) off the **deepest** built-in rule that already claims the event. The deepest claimer was identified from the alert's own content or by searching the ruleset, never assumed.
4. **Write and test the rule.** Validate syntax (`wazuh-analysisd -t`) before restarting the manager, then re-run the attack and confirm the new alert in `alerts.json`.
5. **Clean up.** Archiving off, rule committed to the repo.

**Verification is from `alerts.json` on the manager**, treated as the source of truth. Two scoping rules avoided false results that cost hours early on:

- **Scope every search by agent.** A bare `grep 5152` or `grep 4444` also matches the analyst's own `sudo` commands, which Wazuh logs (rule 5402). All checks use `grep '"name":"WIN-TGT"' <file>` with the real pattern on the far side of the pipe.
- **Run checks on the manager.** `alerts.json` and `archives.json` exist only on WAZUH-SRV; the same grep in a KALI shell returns nothing and looks like a negative result.

All times are UTC.

---

## Simulation 1: Port scan (T1046)

**Closes [Finding 7.5](07-nmap-recon.md#finding-75-a-blocked-scan-is-invisible-to-the-endpoint-and-the-siem-by-default).** Phase 7 showed that a scan blocked by the Windows firewall left no trace: the firewall dropped the packets but logged nothing, so the SIEM had nothing to alert on.

**Attack.** `nmap -sS` from KALI (10.10.10.50) against WIN-TGT (10.10.10.20).

**The gap, and the fix at the source.** Two things had to change before any rule could work:

1. **Audit the drops.** WIN-TGT's *Filtering Platform Packet Drop* auditing was enabled (`auditpol`), so the firewall writes **Event 5152** for each blocked packet, with source IP, destination port and time. Without this the event does not exist.
2. **Let the agent forward it.** The Wazuh Windows agent's default `ossec.conf` **excludes** Event 5152 from the Security channel (`and EventID != 5152`, a noise-reduction default). That clause was removed so the agent forwards the event. *Enabling the audit is not enough; the agent must be allowed to send it.*

**Detection.** Two rules, because one 5152 is noise but many from one source in a short window is a scan:

| Rule | Logic | Level |
|---|---|---|
| 100500 | `if_sid 60104` + `win.system.eventID = 5152` | 5 |
| 100501 | `if_matched_sid 100500`, `same_field win.eventdata.sourceAddress`, `frequency=12 timeframe=20` | 10 |

Rule 100500 chains off the built-in **60104** (not a standalone `decoded_as`, which never fires). Rule 100501 correlates: twelve blocked packets from the same source address within twenty seconds.

**Verified.** The `-sS` scan produced ~200 × Event 5152. Rule 100500 fired 184 times; **rule 100501 "Port scan detected from 10.10.10.50" (level 10, T1046) fired 16 times.** Confirmed from the alert JSON: the correlated alert carried twelve 5152 drops from source 10.10.10.50 to many destination ports.

---

## Simulation 2: PowerShell C2 beacon (T1571, T1059.001)

**Closes [Finding 6.7](06-network-wireshark.md#finding-67-a-powershell-connection-to-port-4444-raises-no-siem-alert).** A PowerShell connection from WIN-TGT to KALI on TCP 4444 (Metasploit's default port) was logged by Sysmon but raised no SIEM alert.

**Attack.** `nc -lvnp 4444` listener on KALI; on WIN-TGT, `Test-NetConnection 10.10.10.50 -Port 4444`. This generates **Sysmon Event ID 3** (network connection: `powershell.exe` → 10.10.10.50:4444).

**The gap — a detection problem, not collection.** The EID 3 event *did* reach the manager (confirmed in `archives.json`), but no custom rule fired. The cause was the **anchor**. Wazuh assigns each event to the single deepest rule that claims it, and a custom rule must chain off exactly that rule. The EID 3 chain is:

```
60000 → 60004 (Sysmon/Operational) → 61600 (INFORMATION) → 61605 (eventID 3) → 92101 (PowerShell over TCP)
```

**92101** ("Powershell process communicating over TCP", image `powershell.exe` + protocol tcp) was the deepest claimer. Chaining off anything shallower (`sysmon_event3`, `decoded_as`, 61605) failed because 92101 won. The anchor was found by **anchor-isolation**: adding a test rule under each candidate parent plus the port field, and seeing which single one fired.

**Detection.**

| Rule | Logic | Level |
|---|---|---|
| 100510 | `if_sid 92101` + `win.eventdata.destinationPort = 4444` | 12 |

**Verified.** A fresh beacon produced **alert 100510 "Possible C2 beacon: PowerShell connected to 10.10.10.50:4444" (level 12, T1571 + T1059.001)**, confirmed in `alerts.json`.

---

## Simulation 3A: Sensor kill (T1562.001)

**Closes [Finding 6.6](06-network-wireshark.md#finding-66-killing-the-wazuh-agent-leaves-no-tamper-alert).** Killing the Wazuh agent left no tamper alert. Rule 100302 ("agent stopped") needs the agent to send a goodbye message, which a killed process never sends; rule 100301 ("disconnected") needs two minutes of silence, which a quick restart avoids.

**Attack.** On WIN-TGT: `taskkill /F /IM wazuh-agent.exe`, then `Start-Service WazuhSvc` about 30 seconds later. A forced kill followed by a quick restart.

**Baseline (the gap reproduced).** After the kill at 10:18:02, the only WIN-TGT alert near the attack was **503 "Wazuh agent started" (level 3)** at 10:21:41. No 100301, no 100302. The kill looked like routine maintenance.

**The collection gap.** Windows *did* record the kill: Service Control Manager **Event 7034** ("The Wazuh service terminated unexpectedly") in the System log, with `param1 = Wazuh`. (7034 because the service had no recovery action; 7031 if it had.) But 7034 was **not** in `archives.json`. The reason is the agent setting **`only-future-events`**, which defaults to `yes`: on restart the agent reads only events logged from that moment on, and skips everything logged while it was down — which is exactly the window the attacker cares about. Setting it to `no` on WIN-TGT's System subscription makes the restarted agent catch up and deliver the record of its own death.

After the fix, 7034 arrived and was claimed by the built-in **61102** ("Windows System error event", level 5, groups `windows`, `windows_system`, `system_error`) — the deepest claimer, confirmed from the alert's content (`eventID 7034`, `param1 Wazuh`).

**Detection.**

| Rule | Logic | Level |
|---|---|---|
| 100303 | `if_sid 61102` + `win.system.eventID = 7034\|7031` + `win.eventdata.param1 = wazuh` | 12 |

7034 **or** 7031 so the attacker cannot dodge the rule by changing the service's recovery setting; `param1 = Wazuh` so only the security sensor dying is critical, not every crashing service.

**Verified.** A kill at 11:47:56 produced **alert 100303 "Wazuh agent service terminated unexpectedly: possible sensor kill" (level 12, T1562.001)** at 11:48:19, confirmed in `alerts.json`.

---

## Simulation 3B: LLMNR/NBT-NS poisoning (T1557.001)

**Closes [Finding 6.4](06-network-wireshark.md#finding-64-win-tgt-broadcasts-unresolved-names-to-the-whole-network).** When WIN-TGT fails to resolve a name, it broadcasts the query over LLMNR, NBT-NS and mDNS and trusts the first answer. An attacker on the segment can answer "that is me" and capture the user's NTLMv2 hash.

**Attack.** `responder -I eth0 -w -v` on KALI. On WIN-TGT, a failed lookup of a non-existent share (`dir \\fileserver01\share`) triggered the broadcasts; Responder returned poisoned LLMNR, NBT-NS and mDNS answers pointing WIN-TGT at KALI. A forced SMB login (`net use`) then sent the NTLMv2 authentication to KALI, which Responder captured.

> **Safety:** the login used an explicit throwaway credential, so the captured hash is of that throwaway, **not** the account's real password — `net use` computes the NTLMv2 response from the credential supplied on the command line. No real credential was exposed. The captured material was deleted. The dangerous real-world variant (silent single-sign-on, which sends the logged-in user's real hash) was deliberately not used.

**The finding: this is where host-based detection runs out, and the control is prevention.** The poisoning happens on the wire between the two hosts; a host-based SIEM never sees the rogue reply. The *consequence* — WIN-TGT's outbound SMB login to the attacker — is the only host-visible signal, and the most diagnostic form of it was **not collected**:

- The actual SMB authentication to KALI is made by the Windows **System** process (kernel SMB client). A built-in rule exists for exactly this (**92106**, "System process over SMB"), but it never fired, because the SwiftOnSecurity Sysmon config **excludes System-process network connections** to reduce noise. A third collection gap, matching Sim 1 and Sim 3A.
- What *did* reach the SIEM were weak, indirect signals: rule 92037 (`net.exe` to a remote share, level 3), rule 60122 (a logon failure, level 5), and — usefully — the Sim 1 rule **100500**, which flagged Responder's own inbound packets being blocked by WFP. None of them says "credential theft".

Because the detectable signal is weak and partly uncollected, the correct control is **prevention**, which is also what Finding 6.4 recommended.

**Remediation (on WIN-TGT, persistent, applied at reboot):**

| Protocol | Setting |
|---|---|
| LLMNR | `HKLM\...\Windows NT\DNSClient` → `EnableMulticast = 0` |
| mDNS | `HKLM\...\Dnscache\Parameters` → `EnableMDNS = 0` |
| NBT-NS | `NetBT\Parameters\Interfaces\*` → `NetbiosOptions = 2` |

**Verified.** The attack was re-run after the reboot. Responder returned **zero** poisoned answers — WIN-TGT no longer broadcasts the query, so there is nothing to answer and no hash to capture. The attack is dead at the source.

---

## The recurring lesson: an alert needs both collection and a rule

Across the four simulations, the first failure was a *collection* gap three times out of four — the event never reached the SIEM — and a *detection* (anchoring) gap once. A rule cannot match an event that does not arrive, so looking only at rules hides half the problem.

| Simulation | First failure | Fix |
|---|---|---|
| 1 Port scan | Collection: audit off **and** agent filtered 5152 | Enable audit + un-filter agent, then rules 100500/100501 |
| 2 C2 beacon | Detection: wrong anchor | Chain 100510 off the deepest claimer (92101) |
| 3A Sensor kill | Collection: agent skipped downtime events | `only-future-events = no`, then rule 100303 |
| 3B LLMNR poisoning | Collection: System-process SMB filtered | Prevention (disable LLMNR/mDNS/NBT-NS) |

## Detection rules summary

| Rule | Level | Trigger | ATT&CK | Simulation |
|---|---|---|---|---|
| 100500 | 5 | WFP-blocked inbound packet (Event 5152) | T1046 | 1 |
| 100501 | 10 | ≥12 blocked packets from one source in 20 s | T1046 | 1 |
| 100510 | 12 | PowerShell → TCP 4444 | T1571, T1059.001 | 2 |
| 100303 | 12 | Wazuh service SCM 7034/7031 | T1562.001 | 3A |

All four are in [detections/wazuh/local_rules.xml](../detections/wazuh/local_rules.xml), synced verbatim with the running manager.

## Findings

### Finding 10.1: killing the sensor is now detected, but only because the agent is told to catch up

**Observation:** Rule 100303 raises a level-12 alert when the Wazuh service is terminated, but it depends on the agent delivering the Event 7034 that is written while the agent is dead.

**Evidence:** Simulation 3A. With `only-future-events = yes` (the default), the baseline kill produced only a 503. With `only-future-events = no`, the same kill produced 7034 → 61102 → rule 100303.

**Analysis:** The detection works because the restarted agent re-reads the events it missed. An attacker who prevents the restart, or who disables the event source first, still defeats it. The alert fires *after* the sensor comes back, so there is a gap during the outage.

**Risk:** Medium. The common "kill and quickly restart" pattern is now caught; a more careful attacker who keeps the sensor down is not.

**Recommendation and status:** Keep `only-future-events = no` on the System channel. Consider a complementary rule on a 503 not preceded by a 506, and forward-shipping of critical events in near real time. **Closed for the quick-restart case; residual gap noted.**

### Finding 10.2: LLMNR poisoning is a prevention problem, not a detection problem, for a host-based SIEM

**Observation:** A successful credential-theft attack produced no high-severity alert, and its most diagnostic event was never collected.

**Evidence:** Simulation 3B. The System-process SMB authentication to the attacker (built-in rule 92106) was filtered by the Sysmon config; only weak signals (92037 level 3, 60122 level 5) reached the SIEM.

**Analysis:** The poisoning is a layer-2/3 event the host agent cannot see, and the one host event that would betray it is suppressed as noise. Tuning the Sysmon config to log System-process SMB connections would surface the symptom but at high volume. Disabling the vulnerable protocols removes the attack entirely.

**Risk:** High if unaddressed (NTLMv2 capture enables offline cracking or relay); low after remediation.

**Recommendation and status:** LLMNR, mDNS and NBT-NS disabled on WIN-TGT and verified. For broader coverage, detect any host answering these queries that is not a name server (network-side). **Closed by prevention.**

## Verification

| # | Test | Result |
|---|---|---|
| 1 | Port scan raises a correlated alert | **Pass**: 100501 level 10, 16× |
| 2 | PowerShell → 4444 raises a C2 alert | **Pass**: 100510 level 12 |
| 3 | Sensor kill raises a tamper alert | **Pass**: 100303 level 12 |
| 4 | Windows 7034 reaches the SIEM after restart | **Pass**: in `archives.json` after `only-future-events = no` |
| 5 | LLMNR poisoning after hardening | **Pass**: zero poisoned answers from Responder |
| 6 | Repo ruleset matches the running manager | **Pass**: committed verbatim |
