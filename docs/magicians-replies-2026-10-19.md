# Magicians thread 29998 — replies to posts #2, #3 and #4 (revision 2)

Status: drafts for the author's approval; each is posted as a reply to the post it answers. Revision 2 of the draft (`ERCS/erc-8447.md`, reference v0.3) implements everything the replies commit to and is on the PR branch and in this repository before the replies go out.

Revision 2 in one paragraph, for the PR description: *addresses Magicians #2–#4. The pack's economic terms (`commitment`) carry their own hash, committed at formation and compared at amendment, so a changed objective or commitment is material by construction and the `material` flag is one-way; `challenge` treats a `false` returned with less than one eighth of the pre-call gas as unevaluable and reinstates a suspended member whose module answers `true` again; `expel` re-evaluates the module before acting; `isAuthorized` reports nobody once a swarm is dissolved, and the account profile states its post-dissolution rule on-chain (`recoveryAddress()`). Interface identifiers: `ISwarmRegistry` `0x085203a4`, `ISwarmAccount` `0x25e98353`. 91 tests.*

---

## Reply to #2 (SergeevDmitry)

@SergeevDmitry Nothing prevents it today, and you have put the finger on exactly the dependency behind question 2 of the opening post: the exit window guards members against the amendment authority, but the authority alone classified the amendment, and the allocation rule it could quietly change lived in the pack where the registry cannot see it.

Committing the economic fields separately is the right fix, and it generalizes the `objectiveHash` case. Revision 2 of the draft, now on the PR branch and in the repository, does this: the Swarm Pack gets a `commitment` member — the allocation rule per phase, costs, liabilities, data access, and the actions taken in the members' name — and `commitmentHash` (SHA-256 over its canonical form) is committed at formation next to `objectiveHash`. `amend` takes both hashes; any change to either makes the amendment material by construction, with the commitment version incremented and the exit window opened. The `material` flag survives only as a one-way override: an authority can declare a textual change material, and can never declare a change of objective or commitment minor. The registry still never reads charter text; what it protects is a structural fact that anyone verifies with one hash. The schema moves `allocation` out of the phase objects into `commitment` for that reason, and a charter that keeps economic terms in its prose instead has visibly put them outside the rule.

That also settles question 2: yes, stricter, and for more than the objective.

## Reply to #3 (Zealynx)

@Zealynx Thank you for reading the challenge path this closely. Both points stand, and both belong to the registry rather than to module authors.

On gas: the reference composite forwards inner reverts, so the registry already reported those as unevaluable; but the specification said nothing about a module that catches its own reads and answers `false`, which is the common way to write one, and the caller controls the gas. Revision 2 adds the remainder rule to `challenge`: a `false` returned with less than one eighth of the pre-call gas remaining is unevaluable and changes nothing. One eighth rather than one sixty-fourth because a catching layer keeps one sixty-fourth of its own budget, so a single catch returns to the registry with about two sixty-fourths of the pre-call gas, and nested catches add one sixty-fourth each; one eighth covers several layers, and an honest `false` that arrives with less simply asks the challenger to try again with more gas. A `true` needs no guard. The test suite now carries the attack: a module whose inner read costs a few million gas; without the rule, a sweep of gas limits from about 1.0M upward suspends an honest member, and with it every such call is unevaluable and the member stays active.

On `expel`: agreed that reading the clock alone contradicts "reinstate on recovery" whenever the `REINSTATE` holder is not watching. `expel` now re-evaluates the module: `false` expels as before, `true` reinstates the member instead and the call returns without exiting, an unevaluable answer leaves the suspension in place and reverts so the caller knows nothing was decided. `challenge` is symmetric for the same reason: anyone's challenge of a member suspended for ineligibility reinstates it when the module answers `true` again, so the member itself, or anyone, can reinstate on evidence without an authority. The `REINSTATE` authority keeps its role for reinstatement on judgment.

On the escalation: the chain you describe is real, with one qualification that the text now makes explicit: `enforceRoster` suspends the swarm with `ROSTER_LOST`, and `resume` is permissionless once the roster holds again, so the effect is a pause rather than a termination. The pause still stops contributions and does not stop the inactivity clock, which is why the two paths above matter: they are what make it short.

## Reply to #4 (Revinand)

@Revinand You are right on every point, and the sentence you quote was wrong as written. `isAuthorized` read membership only for `ROLE` and `ANY_MEMBER`; an `ADDRESS` or `INITIATOR` representative was authorized independently of the roster and kept acting through the account after dissolution, while a roster-based representative was lazily exited. Two swarms on the same account code therefore differed in recovery behaviour for no reason a counterparty could read — a defect of the profile, not a feature of the authority model.

Revision 2 fixes it at both levels. In the registry, `isAuthorized` returns `false` for every decision point and every kind of authority once the swarm is `DISSOLVED`: a representative's power ends with the swarm, whatever kind it was. In the account profile, a conforming account must state its post-dissolution rule on-chain: `recoveryAddress()` returns the one account that may act through it once the swarm is dissolved, or zero when nobody may and whatever is left stays; the rule cannot depend on membership state or on the `REPRESENT` kind, can be changed only by a representative while the swarm lives, and is frozen with the swarm. The reference account takes the recovery address at deployment, lets a representative change it before dissolution, and afterwards accepts calls from that address alone. Dissolution stays independent of settlement — the permissionless exit is not negotiable — and distribution by representation happens in `CONCLUDING`, where the settlement window guarantees the time.

Thank you for the catch; both kinds of swarm now give the same answer to "who can recover what is left", and a counterparty can read it before funding.

## Reply to #8 (Zealynx, second round)

@Zealynx Agreed, and the admission path has had the same exposure since revision 1: the registry reads a module at the instant of a transition and acts on that instant, so any module whose `true` can be rented for one transaction can be rented at admission, at a `SELECT` advance and now at reinstatement. The registry cannot tell a borrowed balance from an owned one; the module can, by not looking at the present.

Revision 2.1 (on the PR branch and in the repository) does two things. Section 6.4 now binds every module with one rule: a module MUST NOT answer from a quantity the evaluated account can change within the same transaction; a module that gates on a token holding reads a checkpointed balance at an earlier block (ERC-5805 `getPastVotes`), a time-weighted holding or a holding that has lasted a declared period, never the live balance. And the Security Considerations gain the mirror image of the griefed `false`: the bought `true`, with the flash-loan sequence you describe, the note that admission and selection share it, and the advice to bind no module whose `true` can be rented and to prefer identity and assertion registries, where a `true` is a record that someone else issued. The reference modules read identity states, assertion levels, agent ownership and allowlists — none of them a balance — so they are unaffected, but the text had listed token balances as an ordinary input without the qualification, and that is fixed.

Thank you for the second look; the symmetric evidence path is worth keeping, and this is the condition under which it is safe.

