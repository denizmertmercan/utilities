<#
.SYNOPSIS
  Exports user prompts and Claude's final text reply per turn from a Claude Code
  session transcript (.jsonl) to a markdown file, or to the pipeline as objects.

.DESCRIPTION
  A transcript is a .jsonl file (one JSON object per line), stored under
  ~\.claude\projects\<project>\<session-id>.jsonl.

  Each user prompt starts a turn. Only the LAST assistant text block of a turn is
  kept, which is the final reply shown to the user. Four things recorded inside tool
  calls are kept too, because they hold the plan or the user's own words: plan
  proposals (ExitPlanMode), the user's plan feedback, the opening sentence of the
  recorded approval, and the user's AskUserQuestion answers. A further user message in
  the same turn, which is how Claude Code records an interruption, is attached to that
  turn. All of these appear in time order within the turn. They are found from the
  transcript's own structure (turn ids, tool names, error flags, structured tool
  results), not from the wording of messages. With -Full a turn also lists the
  assistant's earlier messages and one line per tool call (never the tool's output).
  Everything else is skipped: other tool calls and results, thinking, subagent
  (sidechain) messages, meta messages, harness-injected text (system reminders,
  command output) and IDE context tags.

  Markdown layout: a metadata header (title, source, model, started, exported,
  turns), then one "## User prompt [timestamp]" and one "## AI response [timestamp]"
  section per turn (plus "AI plan", "User plan feedback", "Plan approval", "User
  answer" and "User interruption" sections where they occurred, and with -Full "AI
  progress" and "Tool calls").
  Free-form bodies sit in fenced blocks (the fence is one backtick longer than any run
  inside), so headings in the text cannot be mistaken for section headings. Timestamps are ISO 8601 UTC. "Started" is the
  time of the session's first prompt, even when -Last keeps only later turns. The file
  is UTF-8 without a BOM, with the platform's line endings (CRLF on Windows).

  Output location (-OutFile and -ToProject/-ProjectRoot are mutually exclusive):
    -OutFile                       exactly that file
    -ToProject / -ProjectRoot      <root>\transcripts\<session-id>.md
    (default)                      <session-id>.md next to the transcript

  Inputs and the output path are checked before the transcript is read. Success exits
  with 0 and prints one status line naming the file written. A problem, including a
  transcript with no conversation turns, is reported as one line ("error: ...") with
  exit code 1 and nothing is written; -Verbose adds the full error details. A plan or
  question result that cannot be extracted gives a warning with a count.
  With -AsObject no file is written; turn objects go to the pipeline instead.

.PARAMETER Path
  Transcript .jsonl file to read. Required; may be given positionally.

.PARAMETER OutFile
  Markdown file to write; missing folders in the path are created. Default:
  <session-id>.md next to the transcript.
  Cannot be combined with -ToProject or -ProjectRoot. Ignored with -AsObject.

.PARAMETER ToProject
  Write to <root>\transcripts\<session-id>.md instead of next to the transcript.
  The root is -ProjectRoot, or the current directory exactly as given (no git-root
  detection, so running from a subfolder uses that subfolder). The transcripts
  folder is created if missing.

.PARAMETER ProjectRoot
  Project folder to use as the root for -ToProject. Must exist. Passing it implies
  -ToProject. Default: the current directory.

.PARAMETER Force
  Overwrite the output file if it already exists, using the exact name with no numbering.
  Without it, an existing -OutFile is an error, and a derived path (default or
  -ToProject) gets the first free "<name> (n).md" instead.

.PARAMETER Last
  Keep only the last N turns. Default 0 = all turns.

.PARAMETER Full
  Also keep the assistant's earlier messages within a turn ("AI progress") and one
  line per tool call ("Tool calls": the tool's name and its main target, such as a
  path or command). Tool output is never included. Default: only the final reply.

.PARAMETER AsObject
  Emit objects (User, UserAt, AI, AIAt, Events) to the pipeline instead of writing a
  file, e.g. for Where-Object. Events lists the plan and answer items (Kind, At, Text).

.EXAMPLE
  .\extract-claude-transcript.ps1 C:\Users\me\.claude\projects\proj\abc.jsonl
  Writes all turns to C:\Users\me\.claude\projects\proj\abc.md (abc (1).md if that exists).

.EXAMPLE
  .\extract-claude-transcript.ps1 .\abc.jsonl -OutFile .\out\abc.md -Last 30 -Force
  Writes the last 30 turns to .\out\abc.md, overwriting it if present.

.EXAMPLE
  .\extract-claude-transcript.ps1 .\abc.jsonl -ToProject
  From C:\projects\wegweiser, writes C:\projects\wegweiser\transcripts\abc.md.

.EXAMPLE
  .\extract-claude-transcript.ps1 .\abc.jsonl -ProjectRoot C:\projects\wegweiser
  Same, from any directory; -ProjectRoot implies -ToProject.

.EXAMPLE
  .\extract-claude-transcript.ps1 .\abc.jsonl -AsObject | Where-Object AI -match 'script'
  Filters turns in the pipeline; no file is written.

.EXAMPLE
  .\extract-claude-transcript.ps1 .\abc.jsonl -Full
  Also includes the assistant's progress messages and a list of tool calls per turn.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory, Position = 0)]
  [string]$Path,

  [string]$OutFile,

  [switch]$ToProject,

  [string]$ProjectRoot,

  [switch]$Force,

  [ValidateRange(0, [int]::MaxValue)]
  [int]$Last = 0,

  [switch]$Full,

  [switch]$AsObject
)

# Any error ends the script and lands in the catch block at the bottom, so no step can
# fail quietly and still reach the "Wrote" line.
$ErrorActionPreference = 'Stop'

# User text starting with one of these is injected by the harness, not typed by the user.
$noise = '^<(system-reminder|command-|local-command)'
# IDE context blocks (<ide_opened_file>, <ide_selection>, ...) the extension prepends to prompts.
$ide = '(?s)<ide_[a-z_]+>.*?</ide_[a-z_]+>'

# Plain text of a message: content is either a string or an array of typed blocks.
function Get-MessageText($content) {
  if ($content -is [string]) { return $content }
  ($content | Where-Object type -eq 'text' | ForEach-Object text) -join "`n"
}

# ISO 8601 UTC; ConvertFrom-Json may already have turned the value into a DateTime.
function Get-Stamp($value) {
  ([datetime]$value).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
}

# Wraps free-form text in a fenced block, so headings or fences inside it stay inert. The fence is
# one backtick longer than the longest run inside the text, so nothing in it can close the fence early.
function Format-Fence($text) {
  $longest = ([regex]::Matches($text, '`+') | ForEach-Object { $_.Length } | Measure-Object -Maximum).Maximum
  $fence = '`' * [Math]::Max(3, $longest + 1)
  "$fence`n$text`n$fence"
}

# The only tool results worth keeping. Returns @(section kind, verbatim text), or $null when the
# result is not one of them. It relies on the transcript's own structure (the tool's name, the
# is_error flag and the structured toolUseResult on the entry), not on the wording of the result.
function Get-ToolEvent($name, $block, $entry) {
  $text = Get-MessageText $block.content
  switch ($name) {
    'ExitPlanMode' {
      if ($block.is_error) {
        # Plan refused: the user's comments follow this marker. Without it, keep the whole result.
        $comments = if ($text -match '(?s)Comments on the plan:\s*(.+)$') { $Matches[1] } else { $text }
        return @('User plan feedback', $comments.Trim())
      }
      if ($entry.toolUseResult.plan) {
        # Plan approved: quote only the opening sentence of the recorded result; the rest repeats the plan.
        $first = (($text -split '\r?\n', 2)[0] -split '(?<=[.!?])\s', 2)[0]
        return @('Plan approval', $first.Trim())
      }
    }
    'AskUserQuestion' {
      # The user's answers as structured data: each question text mapped to the answer.
      $answers = $entry.toolUseResult.answers
      if ($answers) {
        $pairs = foreach ($p in $answers.psobject.Properties) { '"{0}"="{1}"' -f $p.Name, (@($p.Value) -join ', ') }
        return @('User answer', ($pairs -join "`n"))
      }
    }
  }
}

# One line describing a tool call: its name and the most telling input (path, command, pattern, ...).
function Get-ToolSummary($name, $in) {
  $target = if ($in.questions) { $in.questions[0].question } else {
    foreach ($k in 'file_path', 'path', 'command', 'pattern', 'query', 'url', 'description') { if ($in.$k) { $in.$k; break } }
  }
  $target = ("$target" -replace '\s+', ' ').Trim()
  if ($target.Length -gt 200) { $target = $target.Substring(0, 200) + '...' }
  if ($target) { "${name}: $target" } else { $name }
}

try {
  # ---- Preflight: check inputs and the output path before any work is done. ----
  # Each failed check throws a plain message; the catch block at the bottom prints it.

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "Transcript not found: $Path. Give the path of a Claude Code session .jsonl file."
  }
  # Absolute path, so the Source line in the header is unambiguous.
  $Path = (Resolve-Path -LiteralPath $Path).Path

  # Output checks only matter when a file will actually be written.
  if (-not $AsObject) {
    # Passing -ProjectRoot alone implies -ToProject.
    if ($PSBoundParameters.ContainsKey('ProjectRoot')) { $ToProject = $true }

    # Two destinations is ambiguous, so refuse instead of letting one silently win.
    if ($ToProject -and $OutFile) {
      throw '-OutFile cannot be combined with -ToProject or -ProjectRoot. Choose one destination.'
    }

    # True when the script chooses the path (default or -ToProject), false for an explicit -OutFile.
    $derived = -not $OutFile

    if ($ToProject) {
      if ($ProjectRoot -and -not (Test-Path -LiteralPath $ProjectRoot -PathType Container)) {
        throw "Project root not found: $ProjectRoot"
      }
      # Root is -ProjectRoot, else the cwd exactly as given (no git-root detection).
      $root = if ($ProjectRoot) { (Resolve-Path -LiteralPath $ProjectRoot).Path } else { $PWD.ProviderPath }
      $OutFile = Join-Path $root "transcripts\$([IO.Path]::GetFileNameWithoutExtension($Path)).md"
    }
    # Default: same folder and base name as the transcript, .md extension.
    elseif (-not $OutFile) { $OutFile = [IO.Path]::ChangeExtension($Path, '.md') }

    # Absolute form of the target (it may not exist yet): every message shows the full path,
    # and a bare file name still has a parent folder to create.
    $OutFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutFile)
    if (Test-Path -LiteralPath $OutFile -PathType Container) {
      throw "Output path is a folder, not a file: $OutFile. Give a file name."
    }

    # Target taken: a derived path gets the first free "<name> (n).md" (n from 1), like Windows copies;
    # an explicit -OutFile is refused. -Force skips both.
    if ($derived -and -not $Force) {
      $dir = Split-Path $OutFile
      $name = [IO.Path]::GetFileNameWithoutExtension($OutFile)
      for ($n = 1; Test-Path -LiteralPath $OutFile; $n++) { $OutFile = Join-Path $dir "$name ($n).md" }
    }
    elseif ((Test-Path -LiteralPath $OutFile) -and -not $Force) {
      throw "Output exists: $OutFile. Use -Force to overwrite."
    }
  }

  # ---- Parse: collect one turn per real user prompt. ----

  $title = $null; $model = $null; $started = $null
  $turns = [System.Collections.Generic.List[object]]::new()
  $cur = $null   # the turn currently being filled (set by a user prompt)
  $tool = @{}    # tool_use id -> tool name, to know which tool a result belongs to
  $seq = 0       # running order, to keep items in file order when timestamps tie
  $unrecognized = 0   # plan or question items that could not be extracted (layout change)
  $toolGroup = $null  # -Full: the open "Tool calls" item, while tool calls follow each other directly

  foreach ($line in Get-Content -LiteralPath $Path -Encoding UTF8) {
    # Skip blank or truncated lines (e.g. a session still being written).
    try { $o = $line | ConvertFrom-Json -ErrorAction Stop } catch { continue }

    # Session title entry; the last one in the file wins.
    if ($o.type -eq 'ai-title') { $title = $o.aiTitle; continue }

    # Only real conversation messages: no subagent, meta, or bookkeeping entries.
    if ($o.isSidechain -or $o.isMeta -or $o.type -notin 'user', 'assistant') { continue }

    # Tool blocks: remember each call's name, and keep the few that carry the plan or the user's words.
    if ($o.message.content -isnot [string]) {
      foreach ($b in $o.message.content) {
        $ev = $null
        if ($b.type -eq 'tool_use') {
          $tool[$b.id] = $b.name
          if ($b.name -eq 'ExitPlanMode') {
            if ($b.input.plan) { $ev = @('AI plan', $b.input.plan.Trim()) } else { $unrecognized++ }
          }
          elseif ($Full -and $cur) {
            # Consecutive tool calls share one "Tool calls" item; anything else in between closes it.
            $line = '- ' + (Get-ToolSummary $b.name $b.input)
            if ($toolGroup) { $toolGroup.Text += "`n$line" }
            else {
              $toolGroup = [pscustomobject]@{ Kind = 'Tool calls'; At = Get-Stamp $o.timestamp; Seq = $seq++; Text = $line }
              $cur.Events.Add($toolGroup)
            }
          }
        }
        elseif ($b.type -eq 'tool_result') {
          $name = $tool[$b.tool_use_id]
          $ev = Get-ToolEvent -name $name -block $b -entry $o
          # A plan or question result that yields nothing means the transcript layout changed.
          # A declined question (is_error) is dropped on purpose, so it is not counted.
          if (-not $ev -and $name -in 'ExitPlanMode', 'AskUserQuestion' -and -not ($name -eq 'AskUserQuestion' -and $b.is_error)) {
            $unrecognized++
          }
        }
        if ($ev -and $cur) {
          $toolGroup = $null
          $cur.Events.Add([pscustomobject]@{ Kind = $ev[0]; At = Get-Stamp $o.timestamp; Seq = $seq++; Text = $ev[1] })
        }
      }
    }

    $text = Get-MessageText $o.message.content
    if ($o.type -eq 'user') { $text = $text -replace $ide, '' }   # drop IDE tags, keep the typed prompt
    $text = $text.Trim()
    if (-not $text) { continue }   # tool_use / tool_result / thinking carry no text

    if ($o.type -eq 'user') {
      if ($text -match $noise) { continue }
      # Every entry of a turn carries the same promptId. A further user message under the current
      # turn's id (how Claude Code files an interruption) belongs to that turn, not to a new one.
      if ($cur -and $o.promptId -and $o.promptId -eq $cur.PromptId) {
        $toolGroup = $null
        $cur.Events.Add([pscustomobject]@{ Kind = 'User interruption'; At = Get-Stamp $o.timestamp; Seq = $seq++; Text = $text })
        continue
      }
      if (-not $started) { $started = Get-Stamp $o.timestamp }   # first real prompt
      $cur = [pscustomobject]@{
        PromptId = $o.promptId
        User = $text; UserAt = Get-Stamp $o.timestamp; AI = ''; AIAt = ''; AISeq = 0
        Events = [System.Collections.Generic.List[object]]::new()
      }
      $turns.Add($cur)
      $toolGroup = $null
    }
    elseif ($cur) {
      # A later reply replaces the earlier one, so the last one wins. With -Full the earlier one
      # is kept as a progress message.
      if ($Full -and $cur.AI) {
        $cur.Events.Add([pscustomobject]@{ Kind = 'AI progress'; At = $cur.AIAt; Seq = $cur.AISeq; Text = $cur.AI })
      }
      $toolGroup = $null
      $cur.AI = $text; $cur.AIAt = Get-Stamp $o.timestamp; $cur.AISeq = $seq++
      if ($o.message.model) { $model = $o.message.model }
    }
  }

  # Safety net: say so when plan or question items were present but could not be read.
  if ($unrecognized) {
    Write-Warning "$unrecognized plan or question item(s) in the transcript could not be extracted; its layout may have changed."
  }

  # Nothing to export: most likely the wrong file or an empty session. Write nothing.
  if ($turns.Count -eq 0) {
    throw "No conversation turns found in $Path. Is it a Claude Code session transcript?"
  }

  # 0 means all turns; otherwise keep the most recent N.
  if ($Last -gt 0) { $turns = @($turns | Select-Object -Last $Last) }

  # Pipeline mode: hand back the turn objects and stop; no file is touched.
  if ($AsObject) { $turns; return }

  # ---- Output: build the markdown and write it. ----

  # Title falls back to the file name when no ai-title exists.
  $header = @(
    "# $(if ($title) { $title } else { [IO.Path]::GetFileNameWithoutExtension($Path) })"
    ''
    "- **Source:** $Path"
    "- **Model:** $model"
    "- **Started:** $started"
    "- **Exported:** $(Get-Stamp (Get-Date)) (via local jsonl)"
    "- **Turns:** $($turns.Count)"
  ) -join "`n"
  # Each section is one "## <Kind> [timestamp]" heading and its body, with a blank line before it.
  $sections = foreach ($t in $turns) {
    "`n## User prompt [$($t.UserAt)]`n`n$(Format-Fence $t.User)"
    # Plan, answer and interruption items plus the final reply, in file order. No reply yet means no empty section.
    $items = @($t.Events)
    if ($t.AI) { $items += [pscustomobject]@{ Kind = 'AI response'; At = $t.AIAt; Seq = $t.AISeq; Text = $t.AI } }
    foreach ($i in ($items | Sort-Object Seq)) {
      # Recorded one-liners and the tool call list stay plain; every free-form body is fenced.
      $body = if ($i.Kind -in 'Plan approval', 'User interruption', 'Tool calls') { $i.Text } else { Format-Fence $i.Text }
      "`n## $($i.Kind) [$($i.At)]`n`n$body"
    }
  }
  # Built with LF; replies carry LF too. Convert every line break to the platform's own
  # (CRLF on Windows) so the file never mixes the two.
  $md = (((@($header) + $sections) -join "`n") + "`n") -replace "`r?`n", [Environment]::NewLine

  # Create the parent folder(s) on demand, only now that parsing succeeded.
  New-Item -ItemType Directory -Force -Path (Split-Path $OutFile) | Out-Null
  # UTF-8 without a BOM (Set-Content -Encoding UTF8 adds one on Windows PowerShell 5.1).
  # Throws on any failure, so the status line below only follows a successful write.
  [IO.File]::WriteAllText($OutFile, $md,[Text.UTF8Encoding]::new($false))

  # The information stream keeps the status line out of the success stream, so captured output
  # stays clean; -InformationAction Continue makes it visible in the terminal.
  Write-Information "Wrote $($turns.Count) turns to $OutFile" -InformationAction Continue
}
catch {
  # One plain line for the user; the full details only with -Verbose.
  # .NET method failures arrive wrapped ('Exception calling "X" with "n" argument(s): ...'); show the cause.
  $msg = $_.Exception.Message
  if ($_.Exception -is [System.Management.Automation.MethodInvocationException] -and $_.Exception.InnerException) {
    $msg = $_.Exception.InnerException.Message
  }
  $Host.UI.WriteErrorLine("error: $msg")
  Write-Verbose ($_ | Out-String)
  Write-Verbose $_.ScriptStackTrace
  exit 1
}
