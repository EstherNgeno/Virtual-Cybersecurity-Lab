# Phase 2: Kali Linux Baseline

| | |
|---|---|
| **Status** | Complete |
| **Date** | 2026-10-12 |
| **Hosts in scope** | KALI, LNX-TGT |

## Objective

Turn the Kali VM into a trusted, documented assessment and capture host: no default credentials, known tool versions, packet capture without root, a repeatable isolation check and a snapshot to return to.

## Environment

| Component | Detail |
|---|---|
| KALI | Kali Linux 2026.1 prebuilt VirtualBox image, 10.10.10.50/24, 2 GB RAM / 2 vCPU |
| LNX-TGT | Metasploitable 2, 10.10.10.30/24 |
| Network | VirtualBox Internal Network `soc-lab`, no gateway ([network plan](../architecture/network-plan.md)) |

## 1. Rollback snapshot

A snapshot was taken before any change, so a failed step could be undone with one restore.

```powershell
VBoxManage snapshot "kali-linux-2026.1-virtualbox-amd64" take "phase1-verified" --description "Isolated on soc-lab, static 10.10.10.50, no gateway. Before Phase 2 updates."
```

## 2. Default credentials

The prebuilt image ships with the published credentials `kali` / `kali`, and that account has full `sudo` rights. The password was changed with `passwd` to one used only in this lab, and the change was confirmed without exposing it:

```bash
passwd -S kali
# kali P 2026-10-12 0 99999 7 -1
```

`P` means a usable password is set; the date is the day of the last change. See Finding 2.1.

## 3. System update: deferred

A controlled update (connect NAT, `apt full-upgrade`, disconnect, re-verify) was planned and then deferred. Kali remains on the package versions shipped with the 2026.1 image. See Finding 2.3.

## 4. Tool inventory and capture privileges

```bash
nmap --version | head -1          # Nmap version 7.99
wireshark --version | head -1     # Wireshark 4.6.6
tshark --version | head -1        # TShark (Wireshark) 4.6.6
id                                # groups include 27(sudo), 122(wireshark)
getcap /usr/bin/dumpcap           # cap_net_admin,cap_net_raw=eip
ls -l /usr/bin/dumpcap            # -rwxr-xr-- 1 root wireshark
```

| Item | Value | Why it matters |
|---|---|---|
| Nmap | 7.99 | Version behind every scan result in later phases |
| Wireshark / TShark | 4.6.6 | Version behind every capture and decode |
| `dumpcap` capabilities | `cap_net_admin`, `cap_net_raw` | The capture helper holds only the two privileges needed to open a network card, not full root |
| `dumpcap` permissions | `root:wireshark`, mode `754` | Only root and members of `wireshark` can execute it |
| `kali` group membership | `wireshark` | The analyst account can capture without `sudo` |

Wireshark and TShark parse untrusted traffic with hundreds of protocol decoders. Running them as an ordinary user, with capture delegated to `dumpcap`, limits the damage a decoder bug could do.

## 5. Capture test as a non-root user

```bash
mkdir -p ~/captures
tshark -i eth0 -a duration:20 -w ~/captures/phase2-capture-test.pcapng   # terminal 1, no sudo
ping -c 4 10.10.10.30                                                    # terminal 2
tshark -r ~/captures/phase2-capture-test.pcapng
```

Result: 6 packets captured and read back with no permission error.

| Frame | Time (s) | Packet |
|---|---|---|
| 1, 2 | 0.000, 8.869 | `0.0.0.0 → 255.255.255.255` DHCP Discover (unexpected; see Finding 2.2) |
| 3 | 18.540 | ARP: who has 10.10.10.30? Tell 10.10.10.50 |
| 4 | 18.541 | ARP: 10.10.10.30 is at `08:00:27:4b:14:1a` |
| 5 | 18.541 | ICMP echo request, 10.10.10.50 → 10.10.10.30 |
| 6 | 18.542 | ICMP echo reply, 10.10.10.30 → 10.10.10.50 |

The ping returned 4/4. Only the first request and reply are in the file because the ping began 18.5 seconds into a 20-second capture window.

## 6. Pre-flight isolation check

Control 5 of the network plan requires an isolation check on KALI before every exercise. It is implemented as [scripts/preflight.sh](../scripts/preflight.sh), which runs five tests and exits `0` if the host is isolated and `1` if not.

| Test | Method |
|---|---|
| No default route | `ip -4 route show default` and `ip -6 route show default` return nothing |
| `eth0` has the lab address | `ip -br -4 addr show dev eth0` contains `10.10.10.50/24` |
| `eth1` (NAT) has no IPv4 address | `ip -br -4 addr show dev eth1` shows no address |
| IP forwarding disabled | `sysctl -n net.ipv4.ip_forward` equals `0` |
| Internet unreachable | `ping -c 1 -W 2 8.8.8.8` fails |

The first four tests check configuration; the fifth checks the outcome directly.

The script was tested in both directions. With the NAT cable deliberately connected (`VBoxManage controlvm ... setlinkstate2 on`) it failed exactly the three tests that depend on the cable, and after disconnecting it returned to all passes.

| Test | NAT cable connected | NAT cable disconnected |
|---|---|---|
| No default route | FAIL | PASS |
| `eth0` has lab address | PASS | PASS |
| `eth1` has no IPv4 address | FAIL | PASS |
| IP forwarding disabled | PASS | PASS |
| Internet unreachable | FAIL | PASS |
| Exit code | 1 | 0 |

No tools other than the script were run while the cable was connected.

## 7. Baseline snapshots

```powershell
VBoxManage snapshot "kali-linux-2026.1-virtualbox-amd64" take "phase2-baseline" --description "Password changed, Nmap 7.99 and Wireshark 4.6.6 verified, non-root capture working, preflight.sh tested. Not updated (deferred)."
VBoxManage snapshot "Metasoploitable-2" take "phase2-clean-baseline" --description "Clean boot, static 10.10.10.30, no dhclient, no NAT. Unmodified target before any scanning."
```

| VM | Snapshot | State it holds |
|---|---|---|
| KALI | `phase1-verified` | Isolated and addressed, before Phase 2 changes |
| KALI | `phase2-baseline` (current) | Hardened and verified assessment host |
| LNX-TGT | `phase2-clean-baseline` (current) | Unmodified target, before any scanning or exploitation |

## 8. Verification

| # | Test | Expected | Result | Evidence |
|---|---|---|---|---|
| 1 | Rollback snapshot exists | `phase1-verified` listed | **Pass** | [Snapshot](../evidence/screenshots/phase2-kali-snapshot-phase1-verified.png) |
| 2 | Default password replaced | `passwd -S kali` shows `P` and today's date | **Pass**: `P 2026-10-12` | [Credential status](../evidence/screenshots/phase2-kali-credential-status.png) |
| 3 | Tools present | Nmap, Wireshark and TShark report a version | **Pass**: 7.99, 4.6.6, 4.6.6 | [Tool versions](../evidence/screenshots/phase2-kali-tool-versions.png) |
| 4 | Capture privileges | `kali` in `wireshark`; `dumpcap` has `cap_net_raw` | **Pass** | same screenshot |
| 5 | Non-root capture | Packets written and read back without `sudo` | **Pass**: 6 packets | [Non-root capture](../evidence/screenshots/phase2-kali-nonroot-capture.png) |
| 6 | LNX-TGT address survives a reboot | 10.10.10.30 after `sudo reboot`; ping from KALI succeeds | **Pass**: 2/2 received | [dhclient removed](../evidence/screenshots/phase2-lnx-tgt-dhclient-removed.png), [target reachable](../evidence/screenshots/phase2-kali-target-reachable.png) |
| 7 | No DHCP traffic on the segment | 0 DHCP packets in 30 s | **Pass**: `0 packets captured` | [No DHCP traffic](../evidence/screenshots/phase2-kali-no-dhcp-traffic.png) |
| 8 | Pre-flight detects broken isolation | 3 FAIL, exit code 1 with NAT connected | **Pass** | [Pre-flight fail](../evidence/screenshots/phase2-kali-preflight-fail.png) |
| 9 | Pre-flight confirms isolation | 5 PASS, exit code 0 | **Pass** | [Pre-flight pass](../evidence/screenshots/phase2-kali-preflight-pass.png) |
| 10 | Baseline snapshots exist | `phase2-baseline`, `phase2-clean-baseline` | **Pass** | [Snapshots](../evidence/screenshots/phase2-snapshots.png) |

## 9. Findings

### Finding 2.1: default credentials on the assessment host

**Observation:** The Kali image was in use with its published default credentials, `kali` / `kali`, on an account with unrestricted `sudo`.

**Evidence:** Vendor documentation for the prebuilt image. After remediation, `passwd -S kali` reports `kali P 2026-10-12 0 99999 7 -1`.

**Analysis:** Default credentials are among the first things an attacker tries (MITRE ATT&CK T1078.001, Valid Accounts: Default Accounts). Because the account has full `sudo`, its password is equivalent to the root password. The assessment host holds scan results, packet captures and attack tooling.

**Risk:** Low in this lab, because the host is reachable only from the isolated segment. It would be high on any shared or routed network.

**Recommendation and status:** Replace default credentials before first use and keep lab passwords unique to the lab. **Remediated.**

### Finding 2.2: unexpected DHCP traffic from a statically addressed host

**Observation:** A test capture on KALI contained two DHCP Discover broadcasts from `0.0.0.0`, 8.9 seconds apart, on a network designed with static addressing and no DHCP server.

**Evidence:**

```bash
tshark -r ~/captures/phase2-capture-test.pcapng -Y dhcp -T fields -e frame.number -e eth.src -e dhcp.option.hostname
# 1   08:00:27:4b:14:1a
# 2   08:00:27:4b:14:1a
```

([screenshot](../evidence/screenshots/phase2-kali-dhcp-source-mac.png)) The source MAC matches neither KALI interface (`08:00:27:8a:35:d2`, `08:00:27:40:03:30`). It matches the ARP reply in frame 4 of the same capture, "10.10.10.30 is at 08:00:27:4b:14:1a", which identifies LNX-TGT. On LNX-TGT:

```bash
ps aux | grep dhclient
# dhcp  4715 ... 05:56  dhclient3 -e IF_METRIC=100 -pf /var/run/dhclient.eth0.pid ... eth0
cat /etc/network/interfaces
# iface eth0 inet static
# address 10.10.10.30
# netmask 255.255.255.0
```

([screenshot](../evidence/screenshots/phase2-lnx-tgt-dhclient-running.png))

**Analysis:** The source IP of a DHCP Discover is always `0.0.0.0`, so the sender had to be identified at layer 2 and tied to a host through another packet in the capture. The configuration file was correct, but a DHCP client was still running on `eth0`. Its start time was about three hours before the check on the VM's clock, which is consistent with it having started at boot under the image's original DHCP configuration and never having been stopped when the static address was applied in Phase 1. The VM had since only been saved and resumed, which preserves running processes.

**Risk:** Low. With no DHCP server on the segment the requests go unanswered. The costs are noise in every capture and a running state that did not match the documented configuration. On a network where an attacker could run a rogue DHCP server, a host soliciting addresses could be handed an attacker-chosen gateway and DNS server.

**Recommendation and status:** After changing network configuration, reboot or restart the affected service and confirm the running state, not only the file. LNX-TGT was rebooted; `dhclient3` is no longer running, 10.10.10.30 persisted across the boot, and a 30-second capture filtered on DHCP recorded 0 packets. **Remediated.**

### Finding 2.3: assessment host not updated

**Observation:** KALI runs the package versions shipped with the 2026.1 image. No `apt` update has been applied.

**Evidence:** Nmap 7.99 and Wireshark 4.6.6 as shipped. TShark prints `Couldn't load plugin 'falco-events.so' ... undefined symbol` on every run, a library version mismatch within the image.

**Analysis:** Kali is a rolling distribution, so a prebuilt image falls behind on fixes from the day it is published. The plugin warning does not affect capture or decoding; the plugin handles Falco system-call events, which this lab does not use.

**Risk:** Low. The host has no internet path and is reachable only by lab VMs. Unpatched packet decoders matter more than usual on a host that parses traffic from deliberately hostile targets, which is partly mitigated by capturing as a non-root user.

**Recommendation and status:** Apply a controlled update (connect NAT, `apt update && apt full-upgrade`, disconnect, run `preflight.sh`) before the attack simulation phases, or sooner if a tool misbehaves. **Accepted for now; deferred.**

## 10. Issues encountered

| Issue | Cause | Resolution |
|---|---|---|
| `ping 10.10.10.30` returned `Destination Host Unreachable` ([screenshot](../evidence/screenshots/phase2-kali-target-down-ping.png)) | LNX-TGT was still in a saved state, so nothing answered ARP | Started the VM; ping 4/4 |
| First capture file was empty | No traffic on the segment during the capture window | Repeated with the target running |
| TShark prints a `falco-events.so` plugin error | Library mismatch in the 2026.1 image | Harmless; recorded under Finding 2.3 |
| `dumpcap` mode was `-rwxr-xr--`, not the expected `-rwxr-x---` | Packaging default: others may read the file but not execute it | No change needed; execution is still limited to root and `wireshark` |

## 11. Lessons learned

- The wording of a ping failure locates the fault. `Network is unreachable` means no route existed and nothing was sent. `Destination Host Unreachable` from the host's own address means a route existed but ARP went unanswered.
- When the IP address identifies nobody, identify the host by MAC and tie that MAC to a known host using other packets in the same capture.
- A configuration file describes the next boot, not the running system. Verify both.
- A check that has only ever passed is unproven. The pre-flight script was trusted only after it was seen to fail for the right reasons.
- Unexplained traffic in a baseline is worth an hour now. Left alone, it becomes noise in every later investigation.

## Next phase

Phase 3: Windows target. Build WIN-TGT (Windows 11 Enterprise evaluation) on `soc-lab` at 10.10.10.20.
