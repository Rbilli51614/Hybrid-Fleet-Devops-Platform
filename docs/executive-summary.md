# Hybrid Fleet Platform — Project Summary

*A plain-language overview for non-technical stakeholders.*

## What this project is

Many companies run their applications in two places at once: partly in the cloud (rented computing power from a provider like Amazon), and partly on their own physical servers, often for cost, compliance, or historical reasons. Managing both environments usually means duplicating effort — separate security rules, separate cost tracking, separate monitoring, separate processes for deploying updates.

This project builds a single, unified system for managing both environments together. One set of security policies applies to both. One dashboard shows the health of both. One process deploys updates to both. The goal is to prove that a "hybrid" setup like this can be run as reliably and efficiently as a single-environment one — without doubling the operational effort.

## What we did

We didn't just design this on paper. We built the entire system for real, turned it on in a live cloud environment, and put every part of it through genuine, hands-on testing — not just a checklist review. That included:

- Standing up both environments (cloud and on-site) with matching security and monitoring rules
- Setting up automated systems that add or remove computing capacity on demand, so the company only pays for what it's using
- Connecting the two environments with a secure, private network link
- Building automated cost-tracking so spending can be broken down by team or project
- Setting up automated software delivery, so code changes are tested automatically before they reach production
- Verifying every single piece actually works by running real tests against it — not assuming it would work because the paperwork looked right

Once everything was proven to work end-to-end, we shut the live environment down to stop it from costing money while it's not needed, while keeping every blueprint and setting saved so it can be rebuilt in minutes whenever it's needed again.

## Key challenges we ran into, and how we solved them

Building something for real, rather than just on paper, is exactly what surfaces the problems that would otherwise only show up after go-live. Here are the most important ones we found — and fixed — before they could cause a real incident.

### 1. Auto-scaling looked correct on paper, but failed five different ways in practice

One of the system's key features is automatically bringing on extra computing capacity when demand spikes, then removing it again once it's no longer needed — so the company never pays for idle capacity, but never runs short either. When we actually tested this live, the very first attempt failed. So did the second, third, fourth, and fifth — each for a different reason: a missing permission, a second missing permission one step deeper, a first-time-use restriction on the account, a mismatch between our security rules and the tool's default settings, and a missing connection step between the new capacity and the rest of the system.

We treated each failure as real information, not a nuisance, and fixed the root cause each time rather than working around it. The fifth fix was the charm: we confirmed with a live test that the system could request new capacity, bring it online, put it to work, and automatically retire it again once it was no longer needed — the complete cycle, proven, not assumed.

**Why this matters:** this is exactly the kind of issue that, if left undiscovered, surfaces for the first time during a real traffic spike — the worst possible moment. Finding and fixing all five causes ahead of time turns a potential outage into a non-event.

### 2. Automated software testing was correctly blocked by our own security rules

We set up a system so that whenever someone makes a code change, it's automatically tested before it's allowed to go live — reducing the risk of human error reaching production. Getting this fully connected required one manual, one-time step (granting the tool permission to access the company's code, a deliberate security checkpoint that only a person can approve). Once that was done, our own security policy did its job and blocked two things that didn't meet the bar: a test run that hadn't been given proper resource boundaries, and a piece of default software that wasn't a specific, verified version.

Rather than loosen the security policy to make the errors go away, we fixed the actual configuration to meet the existing bar, then re-ran the test for real and confirmed the whole process — from code change to automated testing to a passing result — worked correctly.

**Why this matters:** the security policy did exactly what it was supposed to do. This shows the guardrails are working, not just present.

### 3. A routine update would have silently cut a private network connection

During a final health check — after the system had already been live and working for some time — we discovered that the next routine update to the network settings would have accidentally deleted the private connection linking the cloud and on-site environments, with no warning or error message. It would have looked like a normal, successful update right up until the connection quietly stopped working.

We caught this during a planned check, not during an actual outage, traced it to a configuration conflict between two separate pieces of the system that were both trying to manage the same network route, and fixed the underlying setup so this class of mistake can't happen again — confirmed by checking the real, live network afterward to make sure the connection was still intact.

**Why this matters:** this is the difference between an incident report and a line item in a routine status update. The problem was found and fixed before it ever affected anyone.

### 4. A cost-tracking feature turned out to be easier to deliver than expected

Part of the plan was to let the company see cloud spending broken down by team, so each group can be held accountable for its own usage. One piece of this — tracing costs down to the level of individual application components — was initially believed to require an ongoing manual setup step through Amazon's own billing console. On closer investigation, we found this wasn't true: it could be fully automated instead.

We automated it, turned it on, and confirmed it was actually working by checking the real billing data — removing a piece of manual, recurring work that had been planned into the ongoing operating cost of the system.

**Why this matters:** a small piece of research turned a recurring manual chore into a one-time automated setup, saving time on every future use of this system going forward.

### 5. A false alarm in our automated testing pipeline

Our automated testing pipeline was reporting a failure on every single change — which, left unexplained, could easily be mistaken for a sign of ongoing quality problems, or ignored as "probably nothing" (which is its own risk). We treated it as worth understanding properly rather than dismissing it, and traced it to one incorrect line in the pipeline's own configuration, unrelated to the quality of any actual code change.

We fixed the configuration and confirmed the pipeline now runs cleanly. The false alarm is gone, and — just as important — we now know for certain it really was a false alarm, not something masking a real problem.

**Why this matters:** teams that get used to ignoring "probably fine" red flags eventually miss the one that isn't. Running this down cost a small amount of time and bought real confidence.

## Where things stand now

The system has been fully built, turned on, and verified end-to-end against real, live infrastructure — every major capability has been proven to actually work, not just assumed to work from a design document. All of the issues above were found and permanently fixed, not worked around. The live environment has since been shut down to avoid unnecessary ongoing cost, but everything needed to bring it back — fully configured, with every fix already included — is saved and ready to go.
