# Phase 5: Sysmon Configuration and Tuning

| | |
|---|---|
| **Status** | Complete |
| **Date** | 2026-10-30 to 2026-11-05 |
| **Hosts in scope** | WIN-TGT, WAZUH-SRV |
| **Output** | [detections/wazuh/local_rules.xml](../detections/wazuh/local_rules.xml) |

## Objective

Measure what the endpoint telemetry actually contains, close the most important gaps in the Sysmon configuration and the Wazuh ruleset, and remove proven false positives without hiding the attacks they resemble. This phase also covers log baselining, which was planned as a separate Phase 9 and merged here.

## 1. Baseline

| Source | Measurement |
|---|---|
| Sysmon log on WIN-TGT (13 to 30 Oct) | 2,927 events, 4.26 of 64 MB, circular. Top IDs: 1 process create (1,711), 13 registry value set (764), 11 file create (255). **Zero** ID 3 network, ID 7 image load, ID 10 process access |
| Wazuh alerts for WIN-TGT (28 Oct to 4 Nov) | 1,244 alerts. About 40% are agent compliance-scan (SCA) results, 13% are SCA side effects, and 118 are vulnerability detections (kept) |

## 2. Configuration review

The running configuration is the SwiftOnSecurity `sysmonconfig-export.xml` (SHA256 `055FEBC6…87162`, schema 4.50).

| Event | State | Decision |
|---|---|---|
| ProcessAccess (10) | Off | **Enable for `lsass.exe` only**: credential dumping, low volume |
| PipeEvent (17/18) | List of known-bad pipe names; `PSEXESVC` missing | **Add `\PSEXESVC`**: lateral movement with PsExec |
| ImageLoad (7), RawAccessRead (9), FileDelete (23/26) | Off | Accepted gap; too much volume for a 2 GB endpoint |
| NetworkConnect (3) | Selective include list | Unchanged |

The change was made into a new file, `sysmonconfig-v2-lsass-psexec.xml` (SHA256 `48C1D0BF…F1C8`), and loaded with `Sysmon64 -c`. The original is kept beside it for rollback.

## 3. Detection rules

Sysmon now logged the events, but Wazuh raised **no alert** for them: the base rules for ID 10, 16 and 17 are level 0. Four child rules were added:

| Rule | Level | Fires on | ATT&CK |
|---|---|---|---|
| 100100 | 10 | Sysmon configuration changed (ID 16) | T1562.006 |
| 100110 | 12 | LSASS opened with the memory-read right (`GrantedAccess` with bit `0x10`) | T1003.001 |
| 100120 | 10 | Pipe named `PSEXESVC` created | T1021.002, T1569.002 |
| 100121 | 12 | Same, by any process other than `PSEXESVC.exe` | T1021.002, T1036 |

**Test:** reloading the config raised 100100. A `PSEXESVC` pipe created from PowerShell raised 100121, and the parent 100120 was correctly superseded by its child. 100110 stayed silent: the only LSASS access in the period was `svchost.exe` with `0x1000`, which carries no read right (about 12 events an hour). See Finding 5.3 for why a real test could not trigger it.

## 4. Noise exceptions

Eight level-0 child rules (100200 to 100207) silence sources proven benign in Phase 4 and Step 1. Each one matches the **process path, the exact command line or file pattern, and the user**. They do not match on the parent process, which is not reliable (Finding 5.1).

| Rule | Silences | Still alerts on |
|---|---|---|
| 100200 to 100202 | The agent's SCA scan: `secedit /export`, `net user`, run as SYSTEM from the agent folder | The same commands from any other user, folder or with any extra argument |
| 100203, 100204 | PowerShell's `__PSScriptPolicyTest_<8>.<3>.ps1` startup files | Any other name, including look-alikes |
| 100205 | Defender `MpCmdRun.exe` unpacking `mpam-*.exe` / `UpdatePlatform.exe` in its `MpCommU` folder | A file written anywhere else |
| 100206 | `sdbinst.exe -m -bg` (compatibility database maintenance) | `sdbinst` installing any `.sdb` file (T1546.011) |
| 100207 | Per-user service instances (`Name_<hex>`) pointing at System32 `svchost -k` | Any other service image path |

**Testing.** `wazuh-logtest` cannot replay Windows event-channel events, so the rules were tested in two layers:

1. **Offline.** A script applied the deployed regexes to every historical alert: **471 alerts → 2**. The two left are a single CompatTelRunner and a single troubleshooting-tool event, kept on purpose because their sources are not verified. Eight mutated "attacker" variants all kept their original alert. The test also caught a bug (the `9` in `P9RdrService`), which was fixed.
2. **Live.** After an agent restart the SCA scan ran (69 s, 12 SYSTEM processes) and produced none of the silenced alerts. A look-alike `__PSScriptPolicyTest_evil.ps1` raised 92213 (level 15), and `net user` as labadmin raised 92031 and 92033.

## 5. Crash and outage alerts

| Rule | Level | Change | Live test |
|---|---|---|---|
| 100300 | 12 | Bugcheck reboot (System 1001), previously only generic 61102 at level 5 | Verified against both real crash alerts |
| 100301 | 10 | Agent disconnected (504, level 3) | Network cable pulled 10:59:25 UTC → alert 11:01:11 |
| 100302 | 10 | Agent stopped (506, level 3); possible sensor tampering, T1562.001 | Agent restart → alert 11:03:37 |

`agents_disconnection_time` was lowered from **15 min to 2 min** in the manager's `ossec.conf`. Before this, a crash and reboot of 1 to 2 minutes never produced a disconnect alert. Trade-off: brief network blips will now alert; with one agent on an isolated network that is acceptable.

## 6. Verification

| # | Test | Result |
|---|---|---|
| 1 | Sysmon v2 loaded and hash recorded | **Pass**: ID 16 logged |
| 2 | LSASS access logged (ID 10) | **Pass**: [ID 10](../evidence/screenshots/phase5-sysmon-id10-lsass-access.png) |
| 3 | `PSEXESVC` pipe logged (ID 17) | **Pass**: [ID 17](../evidence/screenshots/phase5-sysmon-id17-psexesvc-pipe-test.png) |
| 4 | Detections fire on the manager | **Pass**: 100100, 100121 ([test](../evidence/screenshots/phase5-detection-tests-config-reload-pipe.png)) |
| 5 | Exceptions silence verified noise | **Pass**: 471 → 2 offline; 0 live |
| 6 | Exceptions do not hide look-alikes | **Pass**: 8/8 offline, 2/2 live |
| 7 | Outage alerts | **Pass**: 100301, 100302 live |
| 8 | Crash cause identified | **Pass**: [WinDbg excerpt](../evidence/logs/phase5-bsod-windbg-analyze.txt) |
| 9 | Paired snapshots | **Pass**: `phase5-complete` on both, taken powered off |

## 7. Findings

### Finding 5.1: Sysmon loses events at every boot

**Observation:** Sysmon ID 255 "events dropped from driver queue" appears about 40 s after each boot.

**Evidence:** 4 Nov 09:14:39 UTC: RegistryEvent 7,983, ImageLoad 102, ProcessCreate 50, FileCreate 31 and PipeEvent 20 dropped (queue size 50,000). Alerts from processes started in that window carry an all-zero `parentProcessGuid` and no parent image.

**Analysis:** The VM boots slowly (2 GB, Windows hypervisor) and the driver's queue overflows before the Sysmon service drains it. Boot is also when persistence mechanisms run.

**Risk:** Medium. There is a blind spot exactly where boot persistence would execute, and missing parent fields weaken any rule that relies on them.

**Recommendation and status:** Rules should not depend on parent fields alone (applied in the exceptions). A larger driver queue or more guest memory would help. **Open: accepted for the lab.**

### Finding 5.2: high-value attacker activity produced no alert

**Observation:** LSASS access, a `PSEXESVC` pipe and a Sysmon configuration change were all invisible in the SIEM.

**Analysis:** The first two were not logged by the configuration at all. The third was logged but mapped to a level-0 rule. A stock configuration and a stock ruleset can each be "on" and still miss credential theft, lateral movement and sensor tampering.

**Recommendation and status:** Sections 2 and 3. **Remediated.**

### Finding 5.3: LSA protection blocks LSASS access and hides the attempt

**Observation:** With LSA protection on (`RunAsPPL = 2`), a test that opened LSASS was refused, and **no ID 10 was logged** ([blocked](../evidence/screenshots/phase5-lsass-test-blocked-by-ppl.png), [setting](../evidence/screenshots/phase5-lsa-runasppl-enabled.png)).

**Analysis:** Protection works, but a *failed* dumping attempt can leave no ProcessAccess event. Rule 100110 only catches successful access.

**Recommendation and status:** Keep LSA protection on. Detect dumping attempts through process creation (dump tools, `comsvcs.dll MiniDump` command lines) in the simulation phase. **Open: carried into Phase 10.**

### Finding 5.4: WIN-TGT crashes with stop code 0xA

**Observation:** Two crashes, 30 Oct and 4 Nov, both `IRQL_NOT_LESS_OR_EQUAL`. The user did not notice the second, because Windows restarts by itself.

**Evidence:** System events 41, 6008 and 1001. Two minidumps analysed with WinDbg ([excerpt](../evidence/logs/phase5-bsod-windbg-analyze.txt)): both fault at the **first instruction of the kernel's interrupt handler** (`nt!KiDpcInterrupt+0`) at IRQL `0xFF`. The interrupted code was different each time (`conhost` drawing text, `svchost` waiting for work), and only built-in Microsoft drivers plus SysmonDrv were loaded.

**Analysis:** The only thing the two crashes share is "an interrupt arrived". That points at interrupt delivery by VirtualBox on the Windows hypervisor with 2 vCPUs, the same weakness as Findings 3.1 and 4.1. No driver or malicious cause was found. WinDbg's automatic summary blamed a different module each time (`win32kbase`, then `nt`), because it reports the interrupted code, not the cause.

**Risk:** Medium for the lab. A crash during a simulation would interrupt telemetry.

**Recommendation and status:** 1 vCPU would likely fix it, as it did on WAZUH-SRV. The owner chose to keep 2 vCPUs, with rule 100300 alerting on any crash and a snapshot before each simulation. **Accepted risk.**

### Finding 5.5: crashes and outages were silent in the SIEM

**Observation:** Each crash produced one generic level-5 alert. Unclean-shutdown events 41 and 6008 produced none. Disconnects under 15 minutes never alerted.

**Recommendation and status:** Section 5. **Remediated.**

### Finding 5.6: closing the laptop lid froze the lab and skewed the endpoint clock

**Observation:** On 4 Nov the host slept for 2 h 48 min. Afterwards WIN-TGT's clock was **3 h 54 min behind**.

**Evidence:** VirtualBox log `HostSuspend` / `HostResume` and repeated "TM: Giving up catch-up". The manager stamped the 100121 test alert at 17:29 UTC for an event WIN-TGT dated about 13:35 UTC.

**Analysis:** "Sleep: never" covers idle time only. Closing the lid is a separate setting, which is still Sleep on battery and Hibernate on mains power. VirtualBox only partly catches up a guest clock after a long pause. A fresh power-on resets it.

**Risk:** An analyst correlating by endpoint time would have been four hours off.

**Recommendation and status:** Do not close the lid with VMs running. After any pause, compare the endpoint clock before correlating. **Open: owner's choice.**

### Finding 5.7: most endpoint alerts were proven noise

**Observation:** 471 alerts from eight rules came from the agent's own scan, PowerShell, Defender updates and Windows maintenance.

**Recommendation and status:** Section 4. Two unverified sources still alert. **Remediated.**

## 8. Issues encountered

| Issue | Cause | Resolution |
|---|---|---|
| `wazuh-logtest` decoded replayed Windows events as plain JSON | The Windows event-channel decoder is built into the engine and only applies to events from an agent | Tested the regexes offline in Python, then live |
| First v2 config had `lssas.exe` and a duplicated block | Re-running `-replace` on an already edited file | Content check caught it; rebuilt from the original |
| `Sysmon64 -c \| Select-String` matched nothing | Sysmon writes UTF-16 to the pipe | Run without the pipe |
| Alert counts doubled or missed | `alerts.json` is a hard link to the day's file; most archives are not gzipped | Read only `ossec-alerts-*.json`, uncompressed |
| `EvtSubscribe` error 5023 in the agent log | Windows was shutting down | Benign; matches events 1074 and 6006 |

## 9. Lessons learned

- "Enabled" is not "detected". Check each link: is it logged, collected, and does a rule above level 0 fire?
- An exception is a promise that the source is verified. Anchor it on what the attacker cannot easily fake, and test it with look-alikes.
- If the test tool cannot test something, change the test, not the conclusion.
- Unnoticed is not the same as did not happen. The event log and dump showed a crash the user had not seen.
- Read the stack, not the summary line, of a crash dump.

## 10. Open items

- Agent disconnect at 4 Nov 09:54 UTC, 40 minutes after boot: cause unknown.
- Why the offline Defender keeps unpacking update packages.
- Four Sysmon ID 8 (CreateRemoteThread) events not yet reviewed.

## Next steps

Phase 6: network fundamentals and Wireshark.
