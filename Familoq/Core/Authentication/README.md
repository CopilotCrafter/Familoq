# Authentication (Phase 3)

Planned contents:

- `SignInWithAppleService.swift` - Sign in with Apple (AuthenticationServices).
- `InvitationGateView.swift` - first screen: *Enter Invitation Code* / *Request an Invitation* / *About*.
  No "Sign up", "Create account" or "Continue as guest".
- `AppInvitationClient.swift` - redeems an App Invitation (Level 1) against the
  invitation service (see `docs/04-families-invitations-cloudkit.md`).
- `FamilyInvitationService.swift` - Level 2 invitations (CloudKit share per family).

The code format (`MBF7-K92X-4QPL`, check character, typo detection) is already
implemented and tested in `FamiloqCore/Family/InvitationCode.swift`.
