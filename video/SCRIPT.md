# GoalVault — Demo Video Script

**Track:** Reactive Omni Buildathon · "Set It and Forget It"
**Target length:** ~2.5 minutes (hard limit: under 5 minutes)
**Narration:** English, TTS (see narration/ segments — one file per scene)
**Captions:** burned in, large high-contrast, in all scenes

Word count: ~360 words.

---

## Scene 1 — Title / the problem (title slide)

> Every "automatic" payout in crypto has a catch: somebody still has to press
> the button. A savings goal fills up — and waits. An escrow is fully funded —
> and the freelancer still chases the release. GoalVault removes the button
> entirely.

## Scene 2 — The tool (dashboard hero + template picker)

> GoalVault is a no-code builder for Reactive automations, built for the
> Set It and Forget It track. You pick a template — a savings goal, or
> pay-when-funded escrow — and the vault you deploy finishes itself.
> No code, no server, no keeper.

## Scene 3 — The low-code form (builder form, filled)

> Creating one takes under a minute. Who should receive the money? What is
> the target? The dashboard turns plain answers into exact deployment
> parameters, and your wallet deploys the vault on Sepolia. Then you just
> fund it — whenever, in as many deposits as you like.

## Scene 4 — How Reactive works (flow diagram slide)

> Behind the scenes, every deposit emits an event carrying the running total
> and the target. A reactive contract on Lasna listens for those events and
> checks the condition on-chain, in about a second. Below target, it does
> nothing. The moment the total reaches the target, it requests a callback —
> once, and only once.

## Scene 5 — It finishes itself (My Automations + Reactive status panel)

> The callback lands back on Sepolia and releases the funds to the
> beneficiary automatically. Here is a real goal from the live deployment:
> fully funded, one hundred percent, completed and paid out — with nobody
> pressing anything. The Reactive panel shows both automations live and
> subscribed.

## Scene 6 — The live proof (evidence slide, Template #1 proof chain)

> And this is the proof, live on testnet. A deposit of 0.02 ether crossed
> the 0.03 target on Sepolia. The Lasna reactive transaction fired
> GoalTargetHit and requested the callback. One Sepolia block later, the
> callback transaction paid out the full amount. Both templates ran this
> exact loop, end to end.

## Scene 7 — Negative proof + safety (evidence slide)

> It is also safe to leave running. A below-target deposit was evaluated
> and correctly ignored — zero logs, no payout. Contract debt is zero on
> both sides. Creators can cancel and refund every contributor, the owner
> can pause or retry a callback, and 58 tests pass.

## Scene 8 — Closing (closing slide)

> Set it, and forget it — because Reactive remembers for you. GoalVault:
> templates anyone can use, and automations that finish themselves.
> Thank you.
