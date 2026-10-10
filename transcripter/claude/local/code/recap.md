# claude recap

## 1. Why it exists

- Trigger: the user (Deniz) wanted to continue work from a previous Claude Code session that had grown too long. They asked whether the old transcript could be read and whether it would help.
- Findings: sessions are JSONL files in `C:\Users\deniz\.claude\projects\c--projects-wegweiser\`, one per session id. The old session, `8b4c7d90-…jsonl`, is 4.7 MB, too big to read whole, so targeted extraction was the answer.
- Sessions in play:
  - `8b4c7d90`: the old session, titled "Copilot-extracts review", with 98 turns.
  - `d96dbaa1`: a small 8-turn session about a git pathspec error.
  - `bbcf4879`: the session that built the script, which this recap came from.
- Recaps: recap 1 is the original session AI's own recap (20:53:20Z). Recap 2 is a later session's recap from the transcript, which said it couldn't find plan-mode detail or the "project's model" and "variant" corrections. Both are in `claude\transcripts\claude-extracts.md` in the wegweiser repo. Entries there are immutable but may be amended.
- Core purpose: produce a faithful, readable record of a session for a successor AI or human.

## 2. Current state

The script was developed at the root of the wegweiser repo, untracked there. It has since moved to `C:\projects\utilities\transcripter\claude\local\code\`, in the utilities repo (its own git repo), which the user commits:

- `extract-claude-transcript.ps1`, about 290 lines, with detailed help and inline comments, and a clean PSScriptAnalyzer run (user-verified).
- `extract-claude-transcript.cmd`: the drag-and-drop launcher. It runs `powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0…ps1" %*` and then `pause`. The user confirmed it works.
- Added there afterwards: `readme.md` and this file as `recap.md`.

Parameters

- `Path`: mandatory and positional, with no default.
- `OutFile`: writes exactly that file. It cannot be combined with `-ToProject` or `-ProjectRoot`.
- `ToProject` and `ProjectRoot`: write to `<root>\transcripts\<session-id>.md`. The root defaults to the cwd exactly as given, with no git-root detection. Passing `-ProjectRoot` implies `-ToProject`.
- `Force`: overwrites.
- `Last`: keeps the last N turns, default 0 (all). The user changed it from 10 to 1 to 0.
- `Full`: described in section 4.
- `AsObject`: emits turn objects to the pipeline instead of writing a file.
- `Verbose`: shows full error details.

Behavior

- Output path: the default is `<session-id>.md` next to the transcript. For derived paths (default and `-ToProject`) an existing file gives the first free `<name> (n).md`. An existing explicit `-OutFile` is an error unless `-Force` is passed. Missing folders are created.
- Errors: every failure is one line, `error: …`, with exit code 1 and nothing written. The preflight checks cover a missing transcript, a missing project root, the destination conflict, an output path that is a folder, and an existing output. Anything else is caught by the single top-level `try/catch`. Zero turns is also an error.
- Status line: `Write-Information … -InformationAction Continue`, so it stays out of the success stream and the analyzer is happy.
- Encoding: UTF-8 without a BOM, written with `[IO.File]::WriteAllText`. A BOM appeared with `Set-Content -Encoding UTF8` on Windows PowerShell 5.1. All line breaks are normalized to the platform's own (CRLF on Windows).
- Both PowerShell versions must work. `pwsh` 7.6.6 is the primary shell, and the `.cmd` uses 5.1. Outputs are byte-identical across both.

Export format

- A header: `# <last ai-title>`, then Source, Model (the last reply's), Started (the session's first prompt, even with `-Last`), Exported and Turns.
- Then one section per item: `## <Kind> [ISO-8601 UTC with milliseconds]`, in time order within the turn.
- Kinds are `User prompt`, `AI response`, `AI plan`, `User plan feedback`, `Plan approval`, `User answer` and `User interruption`. With `-Full`, `AI progress` and `Tool calls` are added.
- Fences: every free-form body is in a fenced block, with a fence one backtick longer than the longest backtick run inside. Plain, unfenced bodies are the approval sentence, the interruption marker and the `Tool calls` list.
- No `---` separators: the user dropped them once fencing existed.
- No empty `AI response` section when a turn has no reply.

## 3. What is exported, and what isn't

Kept

- User prompts: IDE context tags stripped, harness-injected text filtered. `<pasted_content>` wrappers are kept verbatim.
- The final assistant text per turn.
- Plan text, from `ExitPlanMode` `input.plan`.
- Plan feedback, from the refused result's text after "Comments on the plan:". If that marker is missing, the whole result is kept.
- The approval, as the first sentence only: "User has approved your plan." The user chose a verbatim quote over an invented label, and the sentence was cut to its opening one when detection became structural.
- `AskUserQuestion` answers, rendered from `toolUseResult.answers` as `"question"="answer"`.
- Interruptions, attached to the turn they interrupted.

With `-Full`

- Earlier assistant messages in a turn become `AI progress`.
- Consecutive tool calls form one `Tool calls` list: `- Name: target`. The target is the first of `file_path`, `path`, `command`, `pattern`, `query`, `url` or `description`, or `questions[0].question`. Whitespace is collapsed, and targets over 200 characters are cut with `...`.
- Tool output is never included.

Dropped, by decision or by nature

- Tool results and, in default mode, tool calls.
- Progress messages in default mode.
- Thinking, because those blocks are empty (0 characters) in these transcripts.
- Tool rejections and declined questions, which the user didn't want.
- Sidechain and meta entries.
- The IDE context the user had open or selected.
- `Edit` diffs. `toolUseResult` carries `structuredPatch`, which we don't use.

## 4. How the transcript is identified (no phrase matching where avoidable)

- Turns: `promptId` is the turn id. All user-side entries of a turn share it. The old session has 98 distinct ids, equal to the 98 turns. A further user text under the same id is an interruption. In 5 cases its text was `[Request interrupted by user]` or `… for tool use]`, but the code does not depend on the wording. If `promptId` disappears, interruptions degrade into separate turns and no data is lost.
- Plan flow: a refused `ExitPlanMode` result has `is_error: true`. An approved one has `toolUseResult` as an object with `plan`, and a refusal has a string. `toolDenialKind` values (`permission-rule`, `user-rejected`) are not reliable here, because `permission-rule` appears on both plan feedback and an `Edit` rejection. Don't branch on them.
- Questions: `toolUseResult.questions` and `answers`.
- Other fields: `isSidechain`, `isMeta`, the last `ai-title` entry, `message.model`, and ISO timestamps. `ConvertFrom-Json` turns timestamps into `DateTime`, so `Get-Stamp` formats them back to UTC with milliseconds.
- Safety net: a counter, `$unrecognized`, raises a `Write-Warning` with a count when plan or question items exist but can't be extracted. A declined question is deliberately not counted. A tested perturbation: renaming `toolUseResult` gave a warning for 2 items, renaming `is_error` gave 3, rewording the feedback marker gave none and kept the whole text, and renaming `promptId` gave 103 turns with no warning.
- Still wording-dependent: the "Comments on the plan:" split, which has a fallback, the first-sentence cut, and the harness-noise regex `^<(system-reminder|command-|local-command)`. A failure of the regex adds noise and loses nothing.

## 5. Evolution and the reasoning behind it

1. Start: a pwsh script printing only user prompts and each turn's final reply, skipping tool results, thinking and progress. The user asked for it as a file in the workspace, then renamed it. They wanted the path as a mandatory argument, no default, reusable, with comments.
2. File output: the format was modeled on the user's browser exporter outputs in `C:\projects\utilities\transcripter\` (`claude-transcript-export.js` and its `outputs\`). That drove the header and the `## User prompt [ts]` and `## AI response [ts]` layout. The default location next to the transcript was chosen for reusability. `-ToProject` was added because the user consumes exports in their repo, with `root/transcripts/` agreed, and `root/transcripts/claude/` for multiple agents deferred.
3. Hardening:
   - `$ErrorActionPreference = 'Stop'` and one top-level handler.
   - The false "Wrote ..." message bug (a `Set-Content` error that didn't stop the script) led to the rule that the status line must only appear when it is true.
   - The 5.1 BOM led to `WriteAllText`.
   - The `(n)` numbering and the `-Force` semantics.
4. Trimming: the user pressed for simplicity. These were removed or simplified: the output-file verification (redundant once the write throws), the file-in-the-way and `-IsValid` preflights, the extension warning, the `StringBuilder`, and the `---` lines. The zero-turn warning became a `throw`.
5. Content fidelity: recap 2 reported missing plan detail. Investigation showed the data was in the JSONL, in tool calls and results the script ignored, so it added plan, feedback, approval and answer extraction. Plan text collided with our `##` headings. The user chose to fence all free-form bodies (not only plans) over demoting headings or just documenting the heading pattern, and kept content verbatim. The switch to structural detection (section 4) followed when the user asked for something sturdier than English phrases.
6. `-Full`: added at the user's request, with progress text and tool one-liners and no tool output.

Rejected on purpose:

- Git-root detection.
- An atomic write.
- Looking for `pwsh` in the `.cmd`.
- Replacing `ValidateRange` with a manual check.
- A second text-based detector as a belt-and-braces fallback. It would bring back phrase matching, so add one only after a real format change.
- Putting tool output in `-Full`.
- Altering text inside bodies.

## 6. Verification state

- Analyzer: PSScriptAnalyzer is clean, via the VS Code PowerShell extension module (1.24.0). The user ran it each time.
- Independent verifier: a Python script, `verify_export.py`, written from the transcript and not from the PowerShell code. It lived only in my temporary scratch folder (`…\scratchpad\`). It ran on the user's `(3).md` and on fresh default and `-Full` exports of three sessions. It makes 26 checks per default export and 27 per `-Full`, with 0 failures except one expected case. In the live session's default export, 6 progress messages are left out, so replies plus progress don't equal assistant text entries. With `-Full` it passes, 105 + 6 = 111.
- Recap check: 40 keyword probes from recap 1 against the export, using only sections written before the recap. 38 had evidence. `sceptical` is not a miss: the user's first prompt says "scepticism". `rotate 180` appears only in `Read` results and an `Edit` call. 13 terms had only assistant evidence, because the facts came from tool output.
- Earlier diffs: the three exports were compared in sequence, and all differences matched the script changes: added plan and answer sections, the 10 empty `## AI response []` sections removed, the interruptions and fences, and a byte total that reconciles exactly (+596).
- Speed: about 0.15 to 0.36 s on warm runs for the 4.7 MB session. The user doesn't care about it.

## 7. Since the recap

All of this happened after sections 1 to 6 were written.

- Where the script should live: the user asked for it to be integrated into their utilities repo, either under `C:\projects\utilities\transcripter\` or directly in `utilities`. I inspected the repo: its own git repo, a two-line `README.md`, and `transcripter\` with `claude-transcript-export.js`, `outputs\` (gitignored through `.gitignore`) and, at that time, an empty `local-claude-code-extractor\` folder. The user wanted a name that exposes the platform without being too long, and follows the convention that paths expose their meaning.
- Naming discussion: I first proposed `transcripter\claude-code\` with `extract-transcript.ps1` and `.cmd`, then `transcripter\claude\code\local\`. The JS exporter, `claude-transcript-export.js`, works on Claude Code on the web as well as on claude.ai chat, which differ slightly. The user chose `C:\projects\utilities\transcripter\claude\local\code\`, kept the file names `extract-claude-transcript.ps1` and `.cmd` (so no renames and no launcher edits were needed), and copied both there themselves. I verified by hash that both copies are identical to the wegweiser versions, and that `local-claude-code-extractor\` no longer exists.
- Files I created there: `readme.md`, concise by the user's instruction (usage, parameter table, output format, what is kept and left out, errors; no mention of the web exporter), and this file, `recap.md`: the recap above, kept as it was, with the facts that changed since put in past tense and related to the present, plus this section.
- Help examples: the user objected to `C:\projects\wegweiser` in two help examples (`-ToProject` and `-ProjectRoot`). Unchanged until asked.
- Not done by the assistant: deleting the originals in the wegweiser repo, and committing in the utilities repo. Both are the user's.
