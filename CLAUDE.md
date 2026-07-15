# Project Guidelines

## Commits

- No AI attribution (no Co-Authored-By, no Claude/Anthropic mentions)

## Code

- Perl v5.22+, strict, warnings
- Shell commands are output to stdout, not executed
- Support local and remote (SSH) for source or destination (not both)
- Use `shell_quote()` for all interpolated values in generated commands
