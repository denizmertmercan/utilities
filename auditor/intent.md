# project's intent

## propositions from an ai assistant in a previous session

"It splits the expensive job, reading everything once, from the collaborative work. The worker never sees the full history, so its attention stays on the project."

"The auditor's report is still a summary. A report that paraphrases the conversation will lose nuance and can change its meaning, the way compaction does." ; "The fix is to have the auditor record decisions as verbatim quotes with line references, not as its own wording." ; "Then the worker reads your exact words, and checks the transcript when it needs context."

"Errors compound. The auditor is an AI with the same tendencies: it may pad, misread, or call something settled when it isn't." ; "The briefing should mark every item as confirmed, provisional, or pending, with the quote behind it, so the worker can tell settled from unsettled. A wrong status is worse than a missing item."

"Auditor, one pass over the full transcript. It writes a briefing with five sections:
Approved decisions, quoted verbatim with line numbers.
Open items, in your words.
Rejected proposals, so they aren't raised again.
Standing rules from your corrections, quoted.
Known mistakes to avoid, such as the README misreading and the "pending" confusion."

"The auditor should only extract and check, not write a recap of the work. A "review of the work" would bring back the padding and paraphrase you want to avoid. Keep its output short and quote-based."

"Worker, reads the briefing only. When a decision matters, it reads the cited lines, not the whole transcript."

"You, read the briefing once (or spot-check a few quotes)."

## workflow

1. user and agent (worker-1) have a conversation (1) and work collaboratively on certain subject matter. that conversation's transcript is saved locally.
2. user starts a new separate fresh conversation session (2), tasks the new agent (auditor) with creating the "briefing".
3. auditor read the first conversation's transcript in full, and creates the report "briefing".
4. user reviews the briefing and make corrections or improvements if necessary.
5. user starts another new separate fresh conversation session (3), tasks the new agent (worker-2) with reading the briefing.
6. new agent (worker-2) reads the briefing in full, as well as any related project documentation, in order to develop a genuine understanding of the project, its history as well current state, and the context awareness needed to continue the collaboration seamlessly.
7. user and new agent (worker-2) continue working collaboratively on the subject matter. new agent (worker-2) uses the briefing as reference routing when needs arise, consulting the original transcript only with targeted reads.
