# Utilities

This repository contains various tools and utilities.

## Directory structure

```text
.
├── README.md
├── auditor/                                        # transcript auditing
│   └── intent.md
├── file-tools/                                     # file analysis tools
│   ├── README.md
│   ├── scripts/
│   │   ├── file_hash.py                            # streaming file hashes
│   │   └── line_count.py                           # UTF-8 line counts
│   └── tests/
└── transcripter/                                   # transcript exporting
    ├── claude/                                     # Claude transcript tools
    │   ├── web-browser/
    │   │   └── google-chrome/                      # console exporter
    │   ├── local/                                  # local environment
    │   │   ├── code/                               # Code-specific exporter
    │   │   │   ├── extract-claude-transcript.ps1
    │   │   │   └── readme.md
    │   │   └── design/                             # Design-specific exporter
    │   └── cloud/                                  # cloud environment
    │       ├── code/                               # Code-specific exporter
    │       └── design/                             # Design-specific exporter
    └── outputs/                                    # generated transcript files
```

## Projects

### File tools

Dependency-free Python utilities for hashing files and counting lines.

### Transcripter

Claude Code transcript export tools and related files.

### Auditor

Intent and workflow notes for quote-based transcript briefings.
