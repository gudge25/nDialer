# account-self-service Specification

## Purpose

Defines what an unauthenticated visitor can do under `/accounts/` — login, logout, in-session password change, and self-registration eligibility — and states explicitly that self-service password reset is not exposed.

## Requirements

### Requirement: No self-service password reset
The system SHALL NOT expose any route, link, or view that lets an unauthenticated visitor request a password-reset email for an account.

#### Scenario: Password reset route does not resolve
- **WHEN** any client requests a password-reset URL under `/accounts/` (request, done, confirm, or complete step)
- **THEN** the system returns a 404 rather than serving a password-reset view

#### Scenario: Login page carries no reset link
- **WHEN** an unauthenticated visitor views the login page
- **THEN** the page shows no "forgot password" link or control that leads to a password-reset flow

### Requirement: Locked-out visitor is directed to support
The system SHALL tell an unauthenticated visitor on the login page how to get unblocked without offering a self-service path.

#### Scenario: Login page shows support instruction
- **WHEN** an unauthenticated visitor views the login page
- **THEN** the page displays static text instructing them to contact support, with no link to an automated reset or registration flow

### Requirement: In-session password change remains available
An authenticated user who knows their current password SHALL be able to change it without staff assistance.

#### Scenario: Authenticated user changes their password
- **WHEN** an authenticated user submits their current password and a new password to the password-change form
- **THEN** the system updates the password and the user can log in with the new password afterward

### Requirement: Self-registration is opt-in and off by default
The system SHALL only expose a self-registration route when explicitly enabled by deployment configuration; it SHALL be disabled unless turned on.

#### Scenario: Registration route absent when not enabled
- **WHEN** the deployment configuration does not explicitly enable self-registration
- **THEN** requests to the self-registration URL return a 404

#### Scenario: Registration route present when enabled
- **WHEN** the deployment configuration explicitly enables self-registration
- **THEN** an unauthenticated visitor can reach the self-registration form and create a new account

#### Scenario: Enabling registration does not restore password reset
- **WHEN** the deployment configuration explicitly enables self-registration
- **THEN** password-reset routes still return a 404, unaffected by the registration setting

### Requirement: Staff-mediated password reset remains available
A staff member or superuser SHALL be able to set a new password for any account visible to them in the administration interface, independent of the account owner's ability to self-serve.

#### Scenario: Staff resets a user's password via admin
- **WHEN** a staff member with access to the administration interface opens a user's record and submits a new password
- **THEN** the system updates that user's password and the user can log in with the new password afterward
