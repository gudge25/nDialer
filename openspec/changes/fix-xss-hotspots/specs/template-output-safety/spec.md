## Purpose

Ensures user-authored free-text content (survey questions/scripts, form input, and similar) is HTML-escaped before being rendered into a template with autoescaping disabled, so one user's authored content cannot execute as HTML/JavaScript in another user's browser.

## ADDED Requirements

### Requirement: Free-text content is escaped before unescaped rendering
Any template output that marks its value safe/unescaped (e.g. via the `safe` filter) SHALL NOT embed free-text content originating from user or admin input without first HTML-escaping it. Values that are always integers, fixed choice codes, or deployment-configuration strings (never free text) are exempt.

#### Scenario: Survey section text contains HTML-special characters
- **WHEN** a survey section's `question` or `script` field contains characters like `<`, `>`, or `&` (including a deliberate `<script>` payload)
- **THEN** the branching "goto" dropdown renders that text as literal, visible text in the option label, not as executable HTML/script

#### Scenario: Survey section text contains only plain text
- **WHEN** a survey section's `question` or `script` field contains ordinary text with no HTML-special characters
- **THEN** the branching "goto" dropdown displays it exactly as before this change
