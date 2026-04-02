---
description: "Use when writing or editing PowerShell scripts (.ps1/.psm1/.psd1). Enforces readable, maintainable script style for teams: clear naming, small functions, safe defaults, and predictable formatting."
name: "PowerShell Readability Standards"
applyTo: "**/*.{ps1,psm1,psd1}"
---
# PowerShell Readability Standards

Write PowerShell for long-term maintainability by humans first.

## Structure

- Keep functions focused on one responsibility.
- Prefer small functions over large procedural blocks.
- Put helper functions above the main execution flow.
- Keep nesting shallow. Use early returns and guard clauses.

## Naming

- Use approved Verb-Noun function names.
- Use descriptive parameter and variable names. Avoid abbreviations unless they are domain-standard.
- Use singular names for single values and plural names for collections.

## Parameters and Types

- Use parameter attributes for validation where practical.
- Add explicit types for parameters and function return values when they clarify intent.
- Prefer named parameters in internal calls when readability improves.

## Output and Logging

- Return objects, not formatted text, from reusable functions.
- Use Write-Verbose for diagnostic flow details.
- Use Write-Host only for intentional user-facing status lines.

## Error Handling and Safety

- Fail fast with clear error messages.
- Use try/finally when state or location must be restored.
- Prefer -LiteralPath for filesystem operations.
- Avoid destructive operations without explicit intent and context checks.

## Formatting

- Use consistent indentation and spacing.
- Keep lines reasonably short for side-by-side review.
- Use blank lines to separate logical blocks.
- Keep hashtables and PSCustomObject definitions vertically aligned when practical.

## Comments

- Explain why, not what.
- Add comments for non-obvious decisions, edge cases, and safety constraints.
- Remove stale comments when code changes.

## Suggested Pattern

```powershell
function Get-ExampleResult {
   [CmdletBinding()]
   param(
      [Parameter(Mandatory)]
      [ValidateNotNullOrEmpty()]
      [string]$Path
   )

   if (-not (Test-Path -LiteralPath $Path)) {
      throw "Path not found: $Path"
   }

   return [PSCustomObject]@{
      Path = $Path
   }
}
```
