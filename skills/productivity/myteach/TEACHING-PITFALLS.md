# Teaching pitfalls (case studies)

Every rule in `SKILL.md` → **Hard Rules** was paid for in a real session. This file keeps the evidence, so the rules don't look like arbitrary style preferences.

Context: a 15-lesson course on Traefik / TLS / certificate lifecycle, taught against live production hosts (`mint`, `ali`, `tencent`, `racknerd`), with the source tree of the tool being taught available locally.

---

## 1. Never ship an unverified command

**What happened.** A lesson's emergency drill told the learner to run:

```bash
docker exec traefik traefik reload 2>/dev/null || docker restart traefik
```

`reload` is not a Traefik subcommand (`grep` over `cmd/traefik/` returns nothing). The learner pushed back bluntly: *"前半部分直接报错，没有 reload 的子参数，瞎编乱造"* — and they were right.

The same lesson referenced `python3 edit-drill.py`. No such script was ever created; it was an artifact of writing the procedure as prose instead of building it.

**Rule.** *Execute first, then write.* If a lesson needs a script, create it and `ls` it. A learner copies what you write, so an invented command becomes an invented failure on their machine — and it burns their trust in everything else in the lesson.

**Why it's specifically a teaching failure.** In normal engineering prose an untested snippet is a minor sin. In teaching material it is a *claim about the learner's environment* that you have not checked.

---

## 2. Never claim a change you did not make

**What happened.** After a correction, the reply said *"已同步改写 lesson 0014 那段表述"*. The file was untouched. The learner found the old text still on screen and said so: *"没改，还是旧文"*.

**Rule.** "Done" means: the edit ran **and** you verified it (grep the old string → zero hits; re-read the region). Otherwise say "not done".

**Why it's worse than an obvious gap.** An obvious gap invites a check. A false "done" **removes** the check.

---

## 3. No claim without a source (memory is not a source)

**What happened.** Several assertions were made from memory and later contradicted by the code:

| Claim (from memory) | Truth (from source) |
|---|---|
| "changing dynamic config requires a restart" | the file provider uses `fsnotify` (`pkg/provider/file/file.go:170`) → hot reload |
| "the default certificate is what a client sees when SNI doesn't match" | with `sniStrict: true`, unmatched SNI is *rejected* before the default cert is ever consulted (`pkg/tls/tlsmanager.go:272-292`) |
| "compensating config is overwritten immediately" | the write is *triggered* (new cert issued / account saved) and can lie dormant for up to 30 days (`pkg/provider/acme/provider.go:810-827`) |
| "field names must match exactly" | matching is case-insensitive (`paerser/parser/labels_decode.go:72` uses `strings.EqualFold`), so `entrypoints` is legal |

**Rule.** Source-code line, official-doc quote, or measured output. Anything else is a hypothesis to be checked, not a lesson to be taught. Teach the *mechanism* (with the line reference), not the conclusion — a learner who can re-derive it won't be misled by your next memory slip.

---

## 4. Every assertion needs a judge that can fail

**What happened.** A certificate check compared the certificate's **CN** against the requested hostname and flagged a mismatch. The real certificate was a *bundled* cert: `CN=auth.example.com`, with `SAN` covering both `auth.example.com` and `dls.example.com`. It was correct; the judge was wrong.

Same family of error, other days:

- `curl` returning `000` was treated as "the service is down" on a host whose domains have **no public DNS at all** — there `000` is the expected value and carries zero information.
- A local `curl` returning `200` was treated as "the network path works" — but loopback **bypasses the firewall chain**, so it says nothing about external reachability.
- `NXDOMAIN` was treated as "DNS is broken" — it means the name does not exist publicly, which can be entirely correct (LAN-only host, internal-only name).

**Rule.** Before writing a verification step, ask: *does this value actually change when the thing is broken?* Prefer, in increasing strength: **read state → read data → read externally observed result.** Today's rule of thumb: a state check proves "I didn't typo"; only an external observation proves "it took effect".

**Corollary — always add a control.** Any "can't find / won't connect / is empty" observation needs a *known-good* comparison before you attribute it. Query a domain that definitely has a record; test a host that definitely works.

---

## 5. Reverse-verify your own artifacts (mutation test)

**What happened.** A YAML validator gained a "field existence" check backed by a whitelist generated from source. Called directly it worked. Called through the learner's `~/bin/yamlcheck` symlink it printed **OK for invalid input** — `__file__` was the symlink path, so the whitelist file wasn't found, so the check silently returned "no problems".

**Rule.** Deliberately break an input and confirm the check reports failure. If it can't fail, it's decoration. Equally: **a check must never degrade silently** — if it cannot load what it needs, it must warn loudly.

This is also why a fixture-based self-test exists (`scripts/selftest.sh`): it turned the whole class of "input shape" bugs into repeatable assertions.

---

## 6. Classify before concluding

**What happened.** "Private key exposure" and "storage lost" were initially treated as one problem. They aren't: loss is not urgent (the tool re-registers and re-issues on restart); exposure may be a security incident, where **the certificate is not the urgent item** — but key rotation is a required part of the cleanup. The learner supplied this distinction; the lesson only got correct after adopting it.

**Rule.** Most wrong conclusions are **category errors**, not arithmetic errors. Teach the taxonomy first (increasingly: "which of these two situations are we in?"), then the procedure per branch. A procedure taught without its classification condition gets applied in the wrong branch — which is how a "verify public reachability" step ends up triggering a rollback on a LAN-only host.

---

## 7. Confirm the learner's environment before writing verification steps

**What happened.** An emergency-rotation script verified success by `curl`-ing each domain from the public internet. On the learner's main host, **no domain is publicly reachable** (LAN-only machine, one tunnel, DNS-01 issuers). Every domain would return `000` → the script would classify a *successful* rotation as a failure and auto-roll-back.

The learner's one-line correction — *"mint 属于局域网，公网不可达"* — invalidated a verification step in a tool that is used during incidents.

**Rule.** Before writing steps, establish: is this host public or private? are there tunnels? who owns the files? A step that is invalid in the learner's environment doesn't just fail — it teaches the wrong thing and can cause real damage.

---

## 8. When corrected, fix the artifact and prove it

**What happened (twice).** Corrections arrived as: *"那个 default 后跟个 & 什么意思"* (deduce that an anchor in the snippet is meaningless leftover), *"`crt.sh` 我推荐错了"* (a recommended tool was down: 502 direct and via proxy), *"你写的不好"* (a conditional was dropped from a statement), *"Notes 都要记录什么"* (the notes were full of self-narrative).

**Rule.** Apply the fix to the file, then **show the evidence** (grep the old string → zero hits; re-read the region). Record the resulting *rule* — not the incident — in `NOTES.md`. A correction left as a conversational claim will be re-broken later, and a notes file full of "I was wrong" entries crowds out the facts the next session actually needs.

---

## Meta-lesson

Over this course, the learner kept arriving at the right principle before the teacher did:

> *"带着源码，不去猜行为"* — bring the source, don't guess at behaviour.
> *"编造不存在的脚本和子命令错误不会发生在人身上，人类都会执行 ok 再写"* — a human wouldn't invent a script; they run it, then write it down.
> *"查不到说明没有公网解析，不能说明 DNS 有问题"* — "not found" is a result, not a fault.

All three are the same rule from different angles: **evidence before assertion**. The learner's instinct is the standard; the teacher's job is to meet it, verify before writing, and demonstrate the fix on the artifact rather than in prose.
