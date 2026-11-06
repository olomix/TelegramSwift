# Real UI for Instant View, TON, gift and bot verification fallbacks

## Overview

The telegram-ios core update
(`docs/plans/completed/20261011-update-telegram-ios-core.md`) kept the Mac
build working by giving new upstream features neutral fallbacks. Some of those
lose content or actions. This plan replaces the small, local ones with real UI:

- **Instant View:** inline buttons, TON addresses and compact tables, plus five
  block types the Mac layout drops entirely (`buttonRow`, `document`,
  `formula`, `heading`, `thinking`). The dropped blocks aren't in
  `nogit_todo.md`; they were found while planning.
- **Text entities:** TON addresses in chat messages.
- **Gifts:** unique gift notes, and hide-name and note options on resale.
- **Bots:** custom verification description entities, both editing and display.

**Out of scope, each getting its own plan later:** WEB proxies, and the features
with no Mac UI at all (rich-text messages and editor, ephemeral and welcome
messages, anchored message reporting).

**Dropped from the TODO:** `UpgradeStarGiftError.alreadyUpgraded`. The core
already recovers by refetching the gift
(`TelegramCore/.../Payments/StarGifts.swift:1739`), and iOS shows the same
generic error if that fails (`GiftViewScreen.swift:2552`). The Mac already
matches iOS.

## Context (from discovery)

All Mac paths are under `Telegram-Mac/`. iOS references are under
`submodules/telegram-ios/submodules/`.

| Area | Mac site | iOS reference |
| --- | --- | --- |
| Inline button | `InstantPageTextItem.swift:572` | `InstantPageUI/Sources/InstantPageInlineButton.swift`, `InstantPageV2ButtonViews.swift` |
| TON in IV | `InstantPageTextItem.swift:570` | `InstantPageUI/Sources/InstantPageTextItem.swift:1154` |
| Compact table | `InstantPageLayout.swift:627`, `InstantPageTableItem.swift:99` | `InstantPageMetrics.swift:133-136` (halved insets) |
| Dropped blocks | `default:` arm at the end of the block switch in `InstantPageLayout.swift` | `InstantPageV2Layout.swift:978, 1298, 1314, 1317, 1343` |
| TON in chat | `ChatMessageItem.swift:740, 912`, `CoreExtension.swift:4077, 4159` | `TextFormat/Sources/StringWithAppliedEntities.swift:421` |
| TON validation | new | length gate in `ChatMessageRichDataBubbleContentNode.swift:2007`; chat and IV rendering on iOS don't validate at all |
| Gift note | `ChatServiceItem.swift:1555, 1638`, `Star_Transaction.swift:1525`, `StarGift_Nft_Controller.swift:1316` | `GiftViewScreen.swift:3072, 3150, 3179` (unique note), `:4905` (original details); `:5267` is the non-unique branch, not a reference |
| Resale | `StarGift_Nft_Controller.swift:1544, 1565, 1574, 1581` | `GiftViewBuyGift.swift:52, 73-75`, `Payments/StarGifts.swift:1493, 1505-1512`, `TelegramEnginePayments.swift:187` |
| Verification | `UserInfoEntries.swift:252, 268`, `verifiedInfo` entries in `UserInfoEntries`, `ChannelInfoEntries`, `GroupInfoEntries` | `PeerInfoScreen.swift:3924`, `PeerInfoProfileItems.swift:24-37` (`peerVerificationDescriptionEntities`), `VerifyAlertController.swift:280` |

Upstream's design notes are in
`submodules/telegram-ios/docs/instantpage-richtext.md`, section "Inline buttons
& document blocks".

Patterns to reuse:

- `InstantPageUrlItem` plus `textItem.linkAt` is the click path
  (`InstantPageSelectText.swift:256`).
- `ChatInterfaceInteraction.swift:772` (`processBotKeyboard`) shows how Mac runs
  each button action, including `.copyText`.
- `ChatMessageItem.applyMessageEntities` plus `InlineStickerItem.apply` renders
  stored text with entities (`Star_Transaction.swift:1527`).
- `messageTextEntities` (`ChatInterfaceState.swift:802`) turns input state into
  entities.
- `InputTextDataRowItem` with `stargifts_message_length_max`
  (`PreviewStarGiftController.swift:832-836`) and the anonymous row (`:903`) are
  the gift note and hide-name UI. Don't use `SellNftInputItem`: it is private and
  accepts digits only.
- `showModalAlert` with footers (`UserInfoEntries.swift:258-260`) is the dialog
  that can hold inputs. `verifyAlert` can't.

## Development Approach

- **Testing approach:** package tests plus manual checks. Telegram-Mac has no
  unit test target and this plan doesn't add one.
- Pure logic goes in `packages/FoundationUtils` with tests written first
  (`swift test --package-path packages/FoundationUtils`).
- Every task must pass the Debug build from `INSTALL.md`:

  ```
  xcodebuild -workspace Telegram-Mac.xcworkspace -scheme Telegram \
    -configuration Debug -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath ~/build/TelegramSwift \
    -allowProvisioningUpdates -allowProvisioningDeviceRegistration build
  ```

- Views and layout are checked by hand; see Post-Completion. Instant View blocks
  that may not appear on real pages are checked on the DEBUG fixture page from
  Task 12.
- Complete each task before starting the next, and update this plan when scope
  changes.

## Progress Tracking

- Mark completed items with `[x]` immediately.
- Add newly discovered tasks with a ➕ prefix and blockers with a ⚠️ prefix.

## Solution Overview

**Clicks in text.** `InstantPageUrlItem` can only carry a URL, but buttons and
TON addresses need other actions. Add a new text attribute carrying an action
value, and extend the click path to check it before `linkAt`. Don't encode
actions in fake URLs.

**Button actions.** A page has no message behind it, so:

- `url`, `openUserProfile` and `copyText` run normally. `url` buttons use
  `inApp(..., confirm: true)`, like bot buttons, because the label hides the
  destination. The page's own `openUrl` uses `confirm: false`, so don't reuse it.
- `callback`, `switchInline`, `urlAuth`, `openWebApp`, `openWebView` and anything
  else still render as buttons, and a click shows a "not available here" toast.
  `openWebApp` and `openWebView` belong here because Mac takes the message ID or
  the bot from the message (`ChatInterfaceInteraction.swift:800, 879`).
- `.disabled` renders dimmed and a click does nothing, as on iOS.

**TON address click.** The Mac app has no wallet and no `sendgrams` handling, so
a click copies the address and shows the existing copied toast, in chats and in
Instant View. Addresses that fail the format check stay plain text. Suspicious
peers need no new code: adding `.TonAddress` to the `ignoreLinks` filter applies
the Mac's existing rule (`canHighlightLinks`, `ChatHistoryEntry.swift:1140`).
That rule checks `.canReport`, while iOS also checks `.canBlock`; this plan
leaves it alone because changing it would affect every link type.

**Resale.** `payResaleForm` fetches the form with the chosen options, stops if
the price rose above the confirmed price or the form is in another currency, and
pays that same form with the same source. It replaces `buyStarGift`, which
compares raw amounts, so a Stars form would pass a nanoton cap. Fetch the form at
open only for the price, keep the balance check, and treat an unknown balance as
unknown rather than zero. After a price rise the next confirmation uses the new
price, without a refetch; a currency mismatch at open or at purchase means the
listing is stale, so the button says OK, a click shows why and closes, and nothing
is sent; other errors reload the balance and the price. The note and hide-name
choice survive a retry. Other errors show the generic error, because server errors
carry a raw RPC code. Return in the note field doesn't confirm; only the OK button
pays.

**Who can buy.** One decision (`quickLookOkAction`) drives both the OK button's
label and its action. Someone who manages a saved gift toggles it on their
profile. Otherwise a listed gift can be bought only when the viewer is shown not
to manage it; a manager, or an owner the app can't resolve, gets OK, which closes.
So price buttons that used to only close now reach `buyResellGift`, with its
confirm alert and cap: `t.me/nft` links, chat bubbles, and saved gifts on someone
else's profile (gifts tab and header pins). Those purchases go to the viewer's own
account. A manager with no saved-gift reference used to get a working Buy button
and now gets OK.

**Still open in resale.** `payResaleForm` keeps what `buyStarGift` did here: it
applies `ignoreValues` and flattens errors. It now sees the form's result and
errors, so these no longer need a core change:

- A false success on `.externalVerificationRequired` remains possible. The result
  is discarded and the signal completes normally, so the app would play confetti,
  show the bought toast, remove the gift from the lists and close, though nothing
  was paid. Whether Stars and TON forms ever return it is unconfirmed.
- The specific errors (already paid, payment failed, precheckout failed, out of
  stock, user limit) are flattened, so they show the generic error.

## Technical Details

- **Compact table insets:** `compact` halves the existing Mac insets to
  `NSEdgeInsetsMake(7, 6, 7, 6)`. `tableCellInsets` is a private global used
  during layout and hit testing (`InstantPageTableItem.swift:280, 321, 524-537,
  587, 595`),
  so store the chosen insets on `InstantPageTableItem`. The height trim for
  non-text cell items is halved with them, from 10 to 5, or inline items overflow.
- **TON address validation:** exactly 48 characters, all from the base64 or all
  from the URL-safe base64 alphabet, so mixed alphabets and `=` padding fail. That
  is the iOS length gate plus a character check.
  No checksum: the action only copies, and iOS's real parser (`parseTonAddress`
  in `WalletEngineFFI`) has no source in this checkout, so a stricter rule could
  wrongly reject real addresses.
- **Resale prices:** the button, alert, toast, price-changed text, sale row and
  gift cards show TON in full through `CurrencyAmount.exactlyFormatted`, because
  the charge uses every nanoton. Other TON amounts keep `fullyFormatted`.
- **Row clicks over tiles:** text tiles are transparent sibling views that take
  clicks, so button rows and documents stay above them after each sort
  (`sortInstantPageSubviews`). `separatesTiles` would clip the text around them.
- **Verification entity offsets:** the Mac prefix is `"\(clown) "`, 3 UTF-16
  units (`UserInfoEntries.swift:2105`), so shift by 3. iOS uses a different prefix
  of 4 units, so don't copy its number. Merge with auto-detected links without
  overlaps, as `peerVerificationDescriptionEntities` does, and pass custom emoji
  through `InlineStickerItem.apply` with its `offset` parameter
  (`ChatMessageItem.swift:73`). Use one shared helper for all three info screens.
- **Verification input:** Task 11's input became `InputTextDataRowItem`, because
  `InputDataRowItem` reports a plain string and can't carry entities. The limit
  now blocks confirm instead of stopping input.
- **Pure helpers:** TON validation, the risky file check, resale price selection,
  button row packing and original-info slot filling live in
  `packages/FoundationUtils`, where they are tested.
- **Risky files:** documents open through `QuickLookPreview.showAfterWarningIfRisky`,
  which chat files share. It ignores case and also checks real MIME types, so it
  warns on more files than the old chat check, never on fewer.
- **New strings:** "not available here" and the resale price-changed message
  are Telex-only and missing from the server language pack. Add them as a local
  constant in the style of
  `packages/MacPasscode/Sources/MacPasscode/PasscodeTexts.swift`, without
  extending that passcode-only enum. Reuse existing `strings()` keys for
  everything else, such as `Share.Link.Copied`.
- **Item clicks:** button row and document items must set `isInteractive = false`.
  With `true`, the click handler force-unwraps `item.medias.first!`
  (`InstantPageSelectText.swift:318`), which crashes on empty `medias`. With
  `false` the click reaches the view (`:334-336`), which handles it itself.
- **New files:** `Telegram.xcodeproj` lists files explicitly, so every new Swift
  file must be registered in `project.pbxproj`.
- **Formula blocks:** show the LaTeX source as text, as the inline `.formula`
  case at `InstantPageTextItem.swift:575` already does. Rendering formulas is a
  separate feature.

## What Goes Where

- **Implementation Steps:** changes in this repository.
- **Post-Completion:** manual checks that need a real account and test content.

## Implementation Steps

### Task 1: Add TON address validation

**Files:**
- Create: `packages/FoundationUtils/Sources/FoundationUtils/TonAddress.swift`
- Create: `packages/FoundationUtils/Tests/FoundationUtilsTests/TonAddressTests.swift`

- [x] write failing tests: both alphabets, wrong length, bad characters, empty string
- [x] implement a `public` `isValidTonAddress(_:)` using the rule in Technical Details
- [x] run `swift test --package-path packages/FoundationUtils` - must pass before task 2

### Task 2: Make TON addresses clickable in chat messages

**Files:**
- Modify: `Telegram-Mac/ChatMessageItem.swift`

- [x] add a `.TonAddress` case next to `.BankCard` (line 912) with link colour and an `inAppLink.callback` that copies and shows the toast
- [x] add `.TonAddress` to the `ignoreLinks` filter (line 740)
- [x] leave the text plain when validation fails
- [x] run the Debug build - must pass before task 3

### Task 3: Add the Instant View click action and TON addresses

**Files:**
- Modify: `Telegram-Mac/InstantPageTextItem.swift`
- Modify: `Telegram-Mac/InstantPageSelectText.swift`
- Modify: `Telegram-Mac/InstantPageViewController.swift`

- [x] add the action attribute and an enum with `copyTonAddress` and `button` cases; `button` does nothing until task 4
- [x] add `actionAt(point:)` next to `linkAt` on the line and text item, and check it first in the click handler (`InstantPageSelectText.swift:256`)
- [x] check `actionAt` in the hover path too (`InstantPageSelectText.swift:424`), so the cursor becomes a hand
- [x] split `.textTonAddress` out of the shared case at line 570 and style it as a link with the copy action when valid
- [x] run the Debug build - must pass before task 4

### Task 4: Render inline page buttons and run their actions

**Files:**
- Create: `Telegram-Mac/InstantPageButtonAction.swift`
- Modify: `Telegram-Mac/InstantPageTextItem.swift`
- Modify: `Telegram-Mac/InstantPageItem.swift`
- Modify: `Telegram-Mac/InstantPageTextStyleStack.swift`
- Modify: `Telegram-Mac/InstantPageContentView.swift`
- Modify: `Telegram-Mac/InstantPageViewController.swift`
- Modify: `Telegram.xcodeproj/project.pbxproj`

- [x] replace the plain-text fallback at line 572 with accent-coloured medium-weight text, tinted by `color`; `isLink` buttons look like links. Inline pills like iOS's run-delegate version are left out to keep text layout unchanged
- [x] add a `performButtonAction` closure to `InstantPageItemArguments`, implement it in the controller, and forward it where arguments are rebuilt (`InstantPageContentView.swift:195`)
- [x] run `url` with `confirm: true`, `openUserProfile` and `copyText`
- [x] make `.disabled` a dimmed no-op, and show the "not available here" toast for every other action
- [x] run the Debug build - must pass before task 5

### Task 5: Support compact tables

**Files:**
- Modify: `Telegram-Mac/InstantPageLayout.swift`
- Modify: `Telegram-Mac/InstantPageTableItem.swift`

- [x] pass `compact` from `.table` (line 627) into `layoutTableItem`
- [x] replace every use of the global `tableCellInsets` with insets stored on the item, including hit testing
- [x] run the Debug build - must pass before task 6

### Task 6: Render the heading, thinking and formula blocks

**Files:**
- Modify: `Telegram-Mac/InstantPageLayout.swift`
- Modify: `Telegram-Mac/InstantPageLayoutSpacings.swift`
- Modify: `Telegram-Mac/InstantPageTheme.swift` (if new heading categories are needed)

- [x] add `.heading`, copying the `.header` arm at line 194 and mapping all six levels, following iOS V1 (`InstantPageUI/Sources/InstantPageLayout.swift:295`)
- [x] add `.thinking` as text in a secondary style, after reading the iOS V2 version
- [x] add `.formula` showing the LaTeX source as text, following iOS V1 (`:300`)
- [x] add spacing rules for all three
- [x] run the Debug build - must pass before task 7

### Task 7: Render the button row block

**Files:**
- Create: `Telegram-Mac/InstantPageButtonRowItem.swift`
- Modify: `Telegram-Mac/InstantPageLayout.swift`
- Modify: `Telegram-Mac/InstantPageLayoutSpacings.swift`
- Modify: `Telegram.xcodeproj/project.pbxproj`

- [x] add an `InstantPageItem` with `isInteractive = false` and a view that lays out buttons, honouring `alignment` and wrapping when narrow (read `InstantPageV2ButtonRowLayout.swift`)
- [x] run actions through `performButtonAction` from task 4
- [x] add the `.buttonRow` case and its spacing rule
- [x] run the Debug build - must pass before task 8

### Task 8: Render the document block

**Files:**
- Create: `Telegram-Mac/InstantPageDocumentItem.swift`
- Modify: `Telegram-Mac/InstantPageLayout.swift`
- Modify: `Telegram-Mac/InstantPageLayoutSpacings.swift`
- Modify: `Telegram-Mac/QuickLookPreview.swift`
- Modify: `Telegram-Mac/ChatFileContentView.swift`
- Modify: `Telegram.xcodeproj/project.pbxproj`

- [x] add an item with `isInteractive = false` and empty `medias`, and a view showing the file name and size. Don't follow `InstantPageAudioItem`: it is interactive and has no download code
- [x] on click, download with `freeMediaFileInteractiveFetched` using `FileMediaReference.webPage(...)`, so expired references can refresh, then open with `QuickLookPreview.current.showAfterWarningIfRisky`
- [x] add the `.document` case with its caption, and a spacing rule; render only the caption if `media[id]` is missing
- [x] run the Debug build - must pass before task 9

### Task 9: Show unique gift notes

**Files:**
- Modify: `Telegram-Mac/ChatServiceItem.swift`
- Modify: `Telegram-Mac/StarGift_Nft_Controller.swift`

- [x] bind `text` and `entities` in the `.starGiftUnique` pattern (line 1555) under names that don't clash with the local `text`
- [x] fix line 1638: it passes the local `text`, the service message sentence, as the gift note, with `entities: nil`; pass the real note and entities instead
- [x] show the note as a row in the NFT controller, rendered as in `Star_Transaction.swift:1527`, with the gating at `GiftViewScreen.swift:3150`
- [x] show the note on the gift bubble (the `info` area at `ChatServiceItem.swift:1650-1692`), following `ChatMessageGiftBubbleContentNode.swift:839`
- [x] load the peers `.originalInfo` refers to, since it carries only IDs
- [x] handle `.originalInfo` in the attribute switch (line 1316 area) using the `giftUniqueOriginalInfo*` strings, shifting the note's entities to its position in the formatted string, as at `GiftViewScreen.swift:4905-4925`
- [x] run the Debug build - must pass before task 10

### Task 10: Add resale hide-name and note options

**Files:**
- Modify: `Telegram-Mac/StarGift_Nft_Controller.swift`
- Modify: `Telegram-Mac/ModalAlertController.swift`

- [x] when buying for someone else, replace `verifyAlert` (line 1574) with `showModalAlert` holding an `InputTextDataRowItem` note and a hide-my-name option; check the footer refreshes on change, because `ModalAlertData.Footer` always compares equal (`ModalAlertController.swift:745`)
- [x] when buying for yourself, keep the plain alert and send `hideName: true` with no note, matching `GiftViewScreen.swift:503`
- [x] replace `sendStarsPaymentForm` with `buyStarGift`, passing the confirmed price, and keep the confetti, list updates and toast on completion
- [x] handle `.priceChanged` with the new string, and show the generic error for `.starGiftResellTooEarly`, `.serverProvided` and `.generic`; unlike `GiftViewBuyGift.swift:73`, `.serverProvided` isn't silent
- [x] replace the hard-coded `ton: false` at line 1544 with `gift.resellForTonOnly`, and build `price` in the matching currency
- [x] run the Debug build - must pass before task 11

### Task 11: Support entities in bot verification

**Files:**
- Modify: `Telegram-Mac/UserInfoEntries.swift`
- Modify: `Telegram-Mac/ChannelInfoEntries.swift`
- Modify: `Telegram-Mac/GroupInfoEntries.swift`
- Modify: `Telegram-Mac/ModalAlertController.swift`

- [x] add the shared rendering helper described in Technical Details, and use it in all three `verifiedInfo` entries (`UserInfoEntries.swift:2105`, `ChannelInfoEntries.swift:1226`, `GroupInfoEntries.swift:1861`)
- [x] keep the input at `UserInfoEntries.swift:252` without a format menu, as iOS does (`VerifyAlertController.swift:280`), under the `bot_verification_description_length_limit` limit
- [x] send entities at line 268 from `messageTextEntities`, choosing its detection argument deliberately; its default is `[.Hashtags]`
- [x] run the Debug build - must pass before task 12

### Task 12: Add a DEBUG Instant View fixture page

Real pages may not contain these blocks: iOS's older Instant View skips
`buttonRow`, `document` and `thinking`. The fixture doesn't prove the server sends
them to Mac; it only exercises the rendering.

**Files:**
- Create: `Telegram-Mac/InstantPageDebugFixture.swift`
- Modify: `Telegram-Mac/ApplicationContext.swift` (the existing `#if DEBUG` Command-T handler, the smallest entry point)
- Modify: `Telegram.xcodeproj/project.pbxproj`

- [x] wrap the whole file and its entry point in `#if DEBUG`, so nothing reaches release builds
- [x] build a page from `InstantPageBlock` values covering all five blocks, all six heading levels, compact and regular tables, a TON address, and one button for each action group: working, message-bound and `.disabled`
- [x] add a way to open it in a Debug build
- [x] run the Debug build, and confirm a Release build doesn't contain the fixture - must pass before task 13

### Task 13: Verify acceptance criteria

- [x] verify every Overview item is implemented
- [x] confirm `InstantPageLayout.swift`'s `default:` arm is reached only by `.unsupported`
- [x] run `swift test --package-path packages/FoundationUtils`
- [x] run the Debug build from a clean state

### Task 14: [Final] Update documentation

- [x] remove the finished items from `nogit_todo.md` and note the `alreadyUpgraded` decision; leave WEB proxies and the new features there
- [x] add the remaining Instant View gaps to `nogit_todo.md`: `textSpoiler` and image and video `spoiler` reveal hidden content; auto links, mentions, hashtags, cashtags, bot commands and bank cards aren't clickable; checklist `checked`, quote `collapsed` and non-image slideshow slides are ignored
- [x] add any new patterns to `CLAUDE.md` if needed; leave `README.md` as upstream wrote it
- [x] move this plan to docs/plans/completed/ (done by the orchestrator after reviews)

## Post-Completion

*Manual checks with a real account and test content; no checkboxes.*

**Instant View:**
- Open the DEBUG fixture page (Command-T in the main window of a Debug build;
  each press alternates LTR and RTL) in light and dark themes. Check each block,
  each working button action, the toast for a message-bound button, and the
  disabled buttons, including those with a link or address inside. Open the stored
  document. The fixture has no server-side file, so a real download can only be
  checked on a real page with a document block, if one turns up.
- The fixture still sends `messages.getWebPage` for its `telex.invalid` URLs.
  Confirm the blocks stay after that refresh returns.
- Click the link, address and button in table cells in both tables, and in details
  blocks. Check the hand cursor over addresses and inline buttons.
- In "Clicks across text tiles", click the bottom edge of every pill and document;
  each must respond. Repeat at another window width, since layout moves the edges.
- Click the unfetchable document twice: fetching, then cancel. Check button row
  alignments and wrapping at a narrow width.
- Also try real pages with tables, headings and formulas, and note any new block
  type seen on a real page.
- Check that text selection and existing links still work.
- Reopen a cached page, since cached pages already hold these blocks.

**Risky files:**
- Open a normal and a risky file from a chat, including an upper-case extension
  such as `.HTML`, and the risky documents on the fixture page. Each risky one
  warns first.

**TON addresses in chat:**
- Click a valid address, and confirm it's copied with a toast.
- Check that invalid addresses stay plain text and that an address from a
  suspicious peer isn't linked.

**Gifts (these spend real Stars, so use a low-priced gift):**
- Open a unique gift that has a note, and one with original details. Check the
  note on the chat bubble and in the gift screen.
- Buy a resale gift for another user with a note and a hidden name. Confirm what
  the recipient sees, and that the payment doesn't fail on a form mismatch.
- Buy a resale gift for yourself.
- A listed gift you don't own, from a `t.me/nft` link, a chat bubble and another
  user's profile (gifts tab and header pin): the button says Buy, and the confirm
  alert appears before any charge. Cancel, or buy a low-priced one.
- A listed gift you own, and one in a channel you manage, from the same places:
  no Buy button, and no route to the confirm alert.
- A TON listing with more than two decimals, if one turns up: every digit shows on
  the card, sale row, button, alert and toast.
- Press Return in the note field: it must not confirm or pay. Check what it does
  to the text, and that the OK button still works.
- Type a long multi-line note: the row and modal grow, the counter updates, the
  caret and focus survive the rebuild on each keystroke, and over the limit the
  row shakes and confirm is blocked.
- Non-success paths: a TON-only gift (card, sale row, button and alert all show
  TON), too low a balance in each currency, a balance not yet loaded, the
  price-changed alert (the button and next alert show the new price, the note
  and hide-name choice stay), and a failed purchase (generic error, nothing
  charged, balance reloaded).
- Watch for a false success: if a purchase ever shows the bought toast without a
  charge, it is the `.externalVerificationRequired` risk in Solution Overview.
- Gift bubbles: a refunded gift with a note (refund line first), a note with
  attributes and a badge, and a gift with no note. All rely on an offset change in
  the gift row. Profile notes with a hidden sender and an unknown sender (the
  second shows no note), opened from the gifts tab and from the pinned gifts in
  the profile header. Click a mention in a note in the gift screen.

**Bot verification (needs a bot with verifier rights):**
- Verify a peer with a formatted description, and check it in the user, group and
  channel info screens.
- There is no format menu, so enter formatting by paste and command shortcuts.
  Check a pasted custom emoji (its offset), a spoiler reveal, a text link, a typed
  link overlapping an auto-detected one, a hashtag click, and an empty description.
- The input row grows with long text, keeps caret and focus while typing, and over
  the limit shakes and blocks confirm.
- Check the official-badge fallback on all three screens.
