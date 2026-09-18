## Purpose

Ensures that user-supplied list/identifier input reaching phonebook, contact, SMS-campaign, and survey queries — and internally-built bulk-import SQL — is validated and parameterized, so it cannot be used to inject arbitrary SQL.

## Requirements

### Requirement: Multi-delete and count endpoints validate list input before querying
Any request handler that accepts a list of record identifiers from `request.GET` or `request.POST` (contact count, phonebook delete, contact delete, SMS campaign delete/stop, survey delete) SHALL reject or discard values that are not valid integer identifiers before they are used in a database query, and SHALL query using parameterized ORM lookups rather than string-built raw SQL fragments.

#### Scenario: Valid numeric identifiers are submitted
- **WHEN** a user submits a list of numeric record IDs to a multi-delete or count endpoint they are authorized to act on
- **THEN** the system deletes/counts exactly the records matching those IDs, scoped to the requesting user, with identical results to the current behavior

#### Scenario: Non-numeric or malicious input is submitted
- **WHEN** a submitted "identifier" list contains a non-numeric value (including a SQL-injection payload such as `1) OR 1=1 --`)
- **THEN** the system does not execute that value as part of a SQL fragment; it either ignores the invalid entries and processes only the valid numeric ones, or rejects the request, and in no case alters the query's intended scope

### Requirement: Raw SQL execution uses parameterized queries
Any code path that executes raw SQL (via `cursor.execute` or `Model.objects.raw`) with values derived from application state (e.g. campaign ID, phonebook ID) SHALL pass those values as query parameters rather than interpolating them into the SQL string.

#### Scenario: Bulk subscriber import runs
- **WHEN** the contact-to-subscriber or contact-to-SMS-campaign-subscriber bulk import task executes its `INSERT ... SELECT` statement for a given campaign and phonebook
- **THEN** the campaign ID and phonebook ID are bound as query parameters, not string-formatted into the SQL text, and the import produces the same rows as before

#### Scenario: SMS campaign subscriber raw query runs
- **WHEN** `SMSCampaign` builds its raw query to enumerate contacts not yet subscribed
- **THEN** the campaign ID values are bound as query parameters, not string-formatted into the SQL text
