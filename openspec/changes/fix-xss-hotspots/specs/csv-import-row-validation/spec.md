## Purpose

Ensures CSV bulk-import handlers correctly recognize and skip a row whose first column is a blank/zero placeholder, consistent with how they already skip an entirely empty row.

## ADDED Requirements

### Requirement: A leading-zero-marker CSV row is skipped like an empty row
Any CSV bulk-import handler (contact import, DNC import, phonebook contact import, survey section/branching import) that already skips an entirely empty row SHALL also skip a row whose first column, after stripping, is the string `"0"`, treating it the same as an empty row rather than processing it as data.

#### Scenario: A row's first column is the string "0"
- **WHEN** a CSV import handler reads a row whose first column value is `"0"`
- **THEN** the handler skips that row without attempting to process it as import data, the same as it would for an entirely empty row

#### Scenario: A row's first column is a normal data value
- **WHEN** a CSV import handler reads a row whose first column is any value other than empty or `"0"`
- **THEN** the handler processes that row as before this change
