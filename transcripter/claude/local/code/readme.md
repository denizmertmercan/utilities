# extract-claude-transcript

Exports a Claude Code session transcript (`.jsonl`) to a markdown file.

Sessions are stored in `~\.claude\projects\<project>\<session-id>.jsonl`.

## Use

cli

Dropping a `.jsonl` onto `extract-claude-transcript.cmd` does the default export and keeps the window open.

Runs on PowerShell 7 and Windows PowerShell 5.1. `Get-Help .\extract-claude-transcript.ps1 -Full` has the details.

| Parameter | Meaning |
| --- | --- |
| `Path` | Transcript to read. Required, positional. |
| `OutFile` | Exact output file. Not combinable with `-ToProject` or `-ProjectRoot`. |
| `ToProject` | Write to `<root>\transcripts\<session-id>.md`. |
| `ProjectRoot` | Root for `-ToProject`. Default: current directory. Implies `-ToProject`. |
| `Force` | Overwrite instead of numbering or failing. |
| `Last` | Keep the last N turns. Default 0 = all. |
| `Full` | Also keep earlier assistant messages and one line per tool call. Never tool output. |
| `AsObject` | Emit turn objects to the pipeline, write no file. |
| `Verbose` | Full error details. |

- Kept per turn: the user prompt, the final reply, plan proposals, plan feedback, the opening sentence of a plan approval, answers to questions, and interruptions.
- Section kinds: `User prompt`, `AI response`, `AI plan`, `User plan feedback`, `Plan approval`, `User answer`, `User interruption`, and with `-Full` also `AI progress` and `Tool calls`.
- Free-form bodies are fenced, so headings inside them cannot be mistaken for sections. The fence is one backtick longer than the longest run inside.
- Left out: tool output, thinking, subagent and meta entries, harness-injected text, and the IDE context tags.
- UTF-8 without BOM, platform line endings.
