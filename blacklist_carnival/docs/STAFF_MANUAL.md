# Event staff operating manual

**Players run every attraction themselves** by targeting the attraction ped: the gallery game, wheel and fortune teller are instant; the theatre, Hall of Deception and House of Horrors start themselves when a player (or the arriving group) triggers them. Staff are ambient actors: perform, scare, lead fortune readings, and use the panel to monitor and fix problems. An attraction set to *staff* mode in the configurator uses the staff-run flow described below.

Open the staff panel with `/carnivalstaff`. You only see the tools your role allows. **Minimise** lets you move around without closing it; **Report problem** sends a report to the monitoring log (and Discord, if configured).

## Before doors open

1. Walk to your attraction NPC and choose **Staff: check in here** (or *Check in* on the Overview's attraction tiles). Attractions marked *requires performer* are only "ready" when someone is checked in; the round holds those groups until then (or skips them if the server is set to skip).
2. Hall of Deception performers: the operator assigns you a performer profile; your brief (truth/lie, statements to keep consistent, private notes) appears at the top of the Hall of Deception tab. Keep it to yourself.

## Overview tab

* **Event** — state, round, timer, overtime flag. Pause / Resume (with optional reason).
* **Rotation** — the six-round grid and the current round per colour:
  * *Open* — start a held (pending) group manually.
  * *Complete* — finish the group's visit (operators can complete their own attraction).
  * *Delay* — hold a group for N seconds (not while a run/heat is in progress).
  * *Skip* — skip the attraction for that group (reason required, audited).
  * *Extend round* / *Force-advance round* / *Start next round now*.
* When the round timer runs out, automated attractions complete automatically but the **Puppet Master's Theatre and Hall of Deception wait for you** ("overtime"). Judge, then press *Complete*.

## Attraction consoles

### Shooting Gallery
Self-service: players target the gallery ped and play the aim game (one game per visit by default). The console shows who is playing, their live score, rejected shots, and results. *Allow replay* gives someone another go (reason required, audited).

### Wheel of Misfortune
Players spin by themselves. Special prizes that need approval appear under *Awaiting approval* — approve (delivers immediately) or reject (reason). You can see every spin and each member's remaining spins.

### Fortune Teller
Automated readings run on their own. To lead a reading: select a player, *Present* a question (you see the answer), *Reveal* a fortune to one player or the whole group, and award roleplay points (capped; each click is a separate, de-duplicated award).

### Puppet Master's Theatre
1. Choose a scenario (filter, *Random*, or *Create a custom scenario* if allowed).
2. Tick performers from the group and type their roles; optional duration.
3. *Prepare* → *Show cards* (performers see their role; the group sees the scene) → *Start* → (*Pause*/*Resume*) → *End performance*.
4. Tick winners, enter points (clamped to the scenario maximum), choose the participation bonus, add a note, **Preview**, then **Commit results**. A performance can only be committed once. *Cancel* abandons it without points.
Previous performances (with results and notes) are listed below.

### Hall of Deception
1. *Prepare for this group* (choose a mystery).
2. Assign performer profiles to online staff (they get their brief).
3. *Start questioning* (timer starts; investigators can use the accusation terminal at the hall).
4. *Release* clues when earned. Use *Record an answer for a player* for verbal accusations.
5. *End questioning* → judge reasoning (optional bonus per player) → *Preview scores* → *Commit scores* (requires the answer-key permission; once only). *Reveal solution* shows the liars to the group (also done on commit).

### House of Horrors
*Start run* (allowlisted controllers only) spawns the tokens for the group and starts the server countdown. Watch runners (tokens, points, inside boundary, escaped). Send a manual *warning*, *Pause*/*Resume*, *Stop* (escapes keep their bonus) or *Reset* (abandon; optionally reverse the run's points — reason required). Performers trigger **Scares** for runners near a scare point. When the run ends the group is completed automatically.

## Participants tab
Search players, open their record, transfer colours (issues a new ticket), replace lost tickets, retry ticket delivery, remove/reinstate, adjust scores (reason required). All actions are audited.

## Good practice
* Always give a clear reason — it is stored permanently in the audit trail.
* If something breaks, **Pause** the event first, then report the problem.
* Never award points by verbal promise; use the console so the ledger stays correct.
