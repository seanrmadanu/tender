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

## October 22: Shopping Mode quick cart

Removed the mandatory Shopping Item sheet from Shopping Mode → Add to Cart.
The existing paper/green/serif design is preserved. The former decorative bag
header was removed to make room for useful controls. Price is explicitly per
item; normal text sizes place a minus/count/plus control to its right. Larger
accessibility sizes stack those controls. Scan uses text.viewfinder at the top
right; quantity and scan icons have 44-point targets and VoiceOver labels.
Primary cart/purchase actions retain text to distinguish saving an intention
from recording money spent.

`entering-data.md > Best practices`: “Be clear about the data you need.”
`buttons.md > Content`: “Try to associate familiar actions with familiar icons.”
The icon-only quantity/scanner controls and optional cart metadata apply those
guidelines to the requested compact flow. Cart default date is today, reminders
are off, store is blank, and a missing name with a known price becomes Shopping
item. Planning details remain editable from Groceries. A new scan clears the
previous name/price so ambiguous OCR cannot silently reuse an old price.

Camera/OCR on physical hardware remains a device check; simulator results are
recorded in verification.md.

## October 22: quantity wheel follow-up

Replaced Shopping Mode's minus/count/plus controls with the native SwiftUI wheel
picker requested from the iOS Timer reference. It stays inline to the right of
unit price at normal text sizes (108 × 116 points), with a highlighted selected
row and vertically scrolling values 1–99. Accessibility sizes retain the existing
stacked layout. Quantity has a VoiceOver label; cart and purchase totals continue
to derive from the same selection.

`pickers.md > Best practices`: “Avoid switching views to show a picker.” The
quantity wheel stays on the current screen instead of opening another sheet.
