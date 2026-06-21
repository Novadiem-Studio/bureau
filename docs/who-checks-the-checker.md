# Who Checks the Checker?

I designed an AI to take the human out of a multi-agent review loop. Then I asked six AIs to review the design. Five said it was good. The sixth had read the code.

That difference is the whole story.

I build with a multi-agent framework I wrote called the Bureau. It isn't a demo or a wrapper around a chat window; it's how most of my work gets from idea to scoped build.

A run starts with the Conductor, the orchestrator. It routes work through isolated specialists: Analizer 2000 for requirements, the Architect for system design, the Challenger as a cold critic, the Spellwright for build prompts. Yes, those are the names. If you're going to live inside a thing, you may as well name it.

Under the names, the machinery is plain. Each specialist runs in a fresh context. Parallel build agents work in separate git worktrees so they don't collide. Models are routed by role through a provider-neutral layer instead of treated like competing chatbots. The shape is planner, generator, evaluator: plan the work, generate the artifact, review it cold, move to the next gate.

The gates are the point. The Challenger is useful because it didn't watch the argument happen. It reads what exists, not what I meant.

The problem was me.

At every checkpoint the run stopped and waited for a human. Read the spec. Approve the plan. Check the review. Decide whether to continue. On a complex feature that can mean a dozen interruptions across hours. A few of those decisions genuinely need me. Most don't.

So I designed a delegate: an agent above the Conductor that could take the routine approvals, escalate the real product calls, and keep the run moving without me pasting one agent's output into another all day.

Then I tried to break the design.

## The diagnosis I was sure of

I'd already tested the rough version by hand. I started a run, then used Codex to play the checkpoint reviewer. It worked. It caught real problems. It also burned through tokens fast enough that I used two full sessions on one run.

I thought I knew why. The cost, I figured, came from resuming the Conductor's live session over and over: the transcript kept growing, and every checkpoint dragged more history back through the model. The fix looked obvious. Don't drive a live session. Make the delegate a short-lived process that wakes on an event, reads the run files from disk, writes a verdict, and exits. A file mailbox in the run directory, with the waiting handled by a shell loop instead of billed model turns.

It was a clean diagnosis with a clean fix. It was also wrong, and no amount of thinking harder was going to show me that.

## Five reviews and a false sense of signal

I ran the design past five general-purpose models: Claude, Grok, ChatGPT, DeepSeek, Mistral.

They gave useful feedback. One caught that I'd fused two roles that should stay separate. Another sharpened the audit trail. A third found a contradiction I'd left sitting in my own document.

By the fifth review the returns had collapsed. Each model mostly confirmed the others. It all hung together, and the agreement was starting to feel earned.

> Consensus feels like correctness. It isn't.

Every one of those reviewers had read my design document. None had read the repo. None had seen the logs from the hand-run relay. None could check the central claim. They could tell me whether the design was plausible; they couldn't tell me whether it was true. All five were working from the same blind spot.

## The sixth reviewer had receipts

The sixth review came from Codex, running in the actual repository with the real telemetry in front of it. Instead of confirming the diagnosis, it took the diagnosis apart.

The token sink was never the growing transcript. The relay's own numbers showed 52M input tokens, 50.2M of them cached, about 96%. The cost was the mechanism: 126 terminal round-trips, redraw noise, the same artifacts re-verified over and over, four context compactions, and one resumed session that spun for eight minutes producing nothing. The transcript played a part, but it wasn't the thing that compounded.

Then Codex kept going.

I'd claimed the delegate persona would have to clear the framework's battle-test gate. Codex checked the rules: that gate applies to workflows, not personas. I'd claimed the delegate could intercept the review step as a checkpoint, but Codex traced the workflows and found that step runs straight through. Intercepting it would mean adding a new gate to every workflow, not the small change I'd assumed. And the document I'd named as the canonical home for the escalation rules? It only governs its own tool's sessions, so it can't own a shared contract.

Every correction was checkable against the real system. None of the five chat reviewers could have caught them, because none of them could see the system.

That's a rule now in how I route models: route to ground truth, not to a vote. The one reviewer that could read the code and the telemetry was worth more than the five that agreed without seeing it.

## I'd made this mistake before

This wasn't the first time a paper design had lied to me.

When I built Rheo, an assistant with persistent memory, the cold critic found dozens of structural problems and missed the behavioral one that mattered: it assumed the model would actually use the retrieval tools I'd given it. In production it often didn't. It answered from whatever was already in front of it and never went looking.

The retrieval system was sound on paper. None of that mattered if nothing reached for it.

The delegate review was the same failure in a different coat. Five reviewers with the document in hand converged on a confident, wrong story. The one reviewer with the running system found what was actually broken.

## Then the role proved itself anyway

The diagnosis was wrong. The role wasn't.

I had a real, hard run sitting in the output directory: a 109 KB spec, a 94 KB prompt set, a shell-and-`jq` feature with an ugly validation contract. The Challenger passed the prompts. A focused verification pass reported zero blockers.

Then the delegate kept going and caught twenty build-breaking defects across three rounds: a function called before it was defined, a script that aborted on a missing file, a boolean silently handled as a string, an atomic write that wasn't atomic across filesystems, a schema key that had drifted.

The Challenger had passed every one of them.

That settled the part I'd been unsure of. A second reviewer earns its place when it checks how the first reviewer's findings were handled. Nobody else in the pipeline was asking whether "fixed" was fixed.

It also narrowed the cost story. My first version oversold a slicing trick. A real review still has to read the 94 KB prompt file against the 109 KB contract; you don't make that cheap by pretending the bug lives on the first page. The honest win is smaller and more useful: kill the live-terminal overhead, kill the cross-round accumulation, and run the same review in a fresh process that reads files and exits. That's where the ~10x comes from. Not magic, just less machinery left running.

## The expensive loops were upstream

Once I stopped blaming the wrong thing, another pattern showed up. The expensive loops weren't mainly the Challenger being picky. They were Analizer 2000 and the Architect drifting apart.

The analyst writes the requirements and hands off. The Architect designs against them, sometimes reading them differently, sometimes barred from editing them, so it bolts on an addendum, and now the second half of the document quietly contradicts the first. The Challenger catches it, but too late: by then it costs a full loop. Route back, rewrite requirements, reconcile architecture, review again.

The fix is almost embarrassingly small: one cheap pass where Analizer 2000 re-reads the architecture before the expensive review. It owns the requirements, so it can fix the drift in place. The contradiction never reaches the Challenger.

The delegate makes review loops cheaper; the analyst re-check makes them fewer. Those are different jobs, and fusing them would produce a worse version of both.

## A real gate lives outside the thing it gates

The delegate checks the Conductor because the Conductor wants to ship, and whoever wants to ship shouldn't grade their own work.

But the same question just moves up a level.

Who checks the delegate?

A delegate writes its own verdict and flags its own uncertainty. It's the one deciding how far to trust itself. That leaves the dangerous case untouched: a confident, wrong "proceed" that never flags itself.

> A gate is only real if something outside the gated party can check it.

That outside check can be a script, CI, or a cold reviewer holding the actual artifacts. What it can't be is the gated party's confidence, or a consensus of reviewers who all lack access to the system. Same reason green tests matter at merge time: the builder's say-so isn't the gate, the external check is.

So the delegate doesn't run unwatched. In the Bureau that role is the Notary, a cold external attestor. It gets a sealed packet, samples the delegate's "proceed" decisions blind, and checks them against the real artifacts. Its job isn't to be smarter than the delegate; it's to be outside it.

I started out trying to take the human out of the loop. What I ended up with was a sharper sense of what the human was for. Not the routine approval; a delegate can take most of that. The job that's hard to hand off is grounding: checking whether the confident answer is actually true.

You can move that job around. You can't delete it.

## What I'm building next

The delegate isn't shipped yet, and neither is the upstream drift pass. They're designs hardened by review, not trophies. The open build questions are concrete:

1. Can a file-mailbox delegate actually beat the live relay on cost, on a real run?
2. Can its "proceed" decisions be trusted without the Notary sampling them?
3. Where should CI become the mechanical enforcement gate, instead of one more advisory voice?

The Bureau underneath all this already runs every day. The next version just has to earn the right to interrupt me less.

The delegate is the next thing I'm probably wrong about, until the receipts say otherwise.
