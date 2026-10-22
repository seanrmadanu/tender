# Design review: Tender original banknote style restored

October 21, 2026. Native SwiftUI, iPhone 17 Pro simulator / iOS 26.2.

## Summary

Restored our pre-import design from Git `354b234` and saved screenshots, while
retaining the requested wallet swiping, bottom Add actions, and new navigation.
The visual identity remains ivory paper, dark engraved green cards, serif
headings, fine inset borders and quiet green controls. The separate Merged copy
was not used as the visual baseline or modified.

## Fixed findings

- **Critical, resolved — dark-mode contrast.** The imported card and Add button
  used white over Ink.green, which becomes pale in dark appearance: approximately
  1.26:1. Restored the original fixed green/cream banknote surface (11.30:1 base
  colors) and paired adaptive foreground/background for Add buttons (10.50:1
  light, 12.73:1 dark). These are calculated base-color WCAG ratios, excluding
  decorative engraving, shadows and antialiasing.
  `accessibility.md > Vision`: “Strive to meet color contrast minimum standards.”
- **High, resolved — original brand details lost.** Restored YOUR EVERYDAY LEDGER,
  A little more intentional., original card color, fading engraving, fine inset
  border, original serif amount weight and rounded-rectangle primary actions.
  The color/typography/card design system itself already matched the baseline;
  the imported wallet surface and heading were the main regressions.
- **High, resolved — Add action obscured content at maximum Dynamic Type.**
  A compact 56-point plus action now appears at accessibility sizes; VoiceOver
  retains the full action label. Normal sizes keep the visible text action.
  `layout.md > Adaptability`: “Be prepared for text-size changes.”
  `accessibility.md > Mobility`: “Offer sufficiently sized controls.”

## Preserved behavior

Home still has separate account cards; Settings remains a main tab with Accounts
inside it, Reports remains inside Activity, and primary Add actions remain at
the lower right. Field focus targets stay at least 48 points tall. Saved cash,
grocery plans, receipt details, transaction sync and privacy work were retained.

`tab-bars.md > Best practices`: “Use a tab bar to support navigation, not to
provide actions.” `text-fields.md > Best practices`: “Evenly space multiple text
fields.” New controls use the existing typography and color system.

## Evidence and limits

Compared with `build/oct21-empty-final.png` and source at `354b234`. Reviewed
Home in light/dark mode, account details, Activity and Reports in Device Hub;
checked the maximum accessibility text size and the empty Home state. Core
navigation/input/grocery flows are covered by the UI tests in verification.md.

Final screenshots include `build/ui-restored-empty-final.png`,
`build/ui-restored-home-light.png`, `build/ui-restored-home-dark.png`, and
`build/ui-restored-large-text-final.png`. The earlier
`ui-restored-home-large-text.png` records the pre-fix button for comparison.
Images in `build/ui-restored-*` are simulator evidence. Populated screenshots
use isolated sample fixtures, clearly labeled, with networking disabled. They
are not real bank data. Personal app defaults remain empty.

This is not a complete VoiceOver, iPad, landscape or physical-device audit.
Microphone, camera, real bank results and notification delivery need device
verification. The line engraving is decorative and excluded from accessibility.

References read from the Apple Design skill: accessibility, layout, typography,
color, designing-for-ios, buttons, text-fields and tab-bars. HIG source pages:
https://developer.apple.com/design/human-interface-guidelines/accessibility
https://developer.apple.com/design/human-interface-guidelines/layout
https://developer.apple.com/design/human-interface-guidelines/tab-bars
https://developer.apple.com/design/human-interface-guidelines/text-fields
