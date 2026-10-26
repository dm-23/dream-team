# Interface card: generic

The method the Designer applies and `/generate-knowledge` maps onto a project's pages. It names no framework, no library and no style class: it speaks of what every interface has, and the project's `FRONTEND-ARCHITECTURE.md → Design language` says what each of those is here. Sections and order are mandatory for every interface card.

## Detect

- Applies to every project whose `FRONTEND-ARCHITECTURE.md` describes a user interface. A project without one has no design language and the Designer never runs.

## Vocabulary

The terms every brief, audit and design-language topic is written in. The design language binds each to the project's element and its path.

| Term | Meaning |
|------|---------|
| primary action | the one thing a page or a dialog exists to let a person do; one per view |
| secondary action | anything else a person may do there |
| destructive action | removes, overwrites or applies something that cannot be taken back by one more click |
| list view | rows of things a person scans, filters and picks from |
| detail view | one thing, whole, with what can be done to it |
| form | fields a person fills before an action |
| feedback | what the interface shows after an action: what happened, to how many, and whether it worked |
| confirmation | what the interface asks before a destructive or bulk action: the count and the consequence |
| preview-then-apply | a dry run shown before the real one, with the choice of what to apply |
| navigation | how a person moves between views and knows where they are |
| state | what a view shows when its data is empty, loading, failed, partial, complete, or forbidden |
| interface language | the language the copy is written in |

## Heuristics

Each one is a check: what to look at, what a violation looks like, what the brief writes instead. A finding cites the heuristic number.

- **H1 Status is visible.** Look at every action that takes time or changes data. Violation: nothing changes on screen between the action and its result, or the result is shown nowhere a person is looking. Instead: feedback in place, naming what happened and how many; a loading state while it takes time.
- **H2 The user's words.** Look at labels, headings, menu entries, column titles, error text. Violation: identifiers, codes, column names or system terms where the person has a word. Instead: the domain's word from `PROJECT-OVERVIEW.md`, an identifier only beside a name.
- **H3 A way back.** Look at every destructive and every bulk action. Violation: it runs on one click, or its confirmation names neither the count nor the consequence, or there is no preview and no undo. Instead: confirmation with count and consequence, or preview-then-apply, whichever the project already does.
- **H4 One way to do one thing.** Look at the same action across pages: its word, its place, its control. Violation: two words, two places or two controls for one action. Instead: the inventory line; a change to the recorded way is a `[convention]` decision, never a silent choice.
- **H5 Errors prevented before they are made.** Look at forms and filters. Violation: an invalid choice is offered (a range that can be reversed, a required field unmarked, a format unshown). Instead: constrain the choice, mark the field, show the format beside it.
- **H6 Recognise, do not recall.** Look at every place a person picks or types a reference to something elsewhere. Violation: a code or an identifier must be remembered from another page. Instead: the name with the identifier, the context kept in view.
- **H7 The frequent task is short.** For each user task count the steps and the clicks as they are. Violation: a daily task repeats a confirmation, re-enters a filter, or needs more steps than its data requires. Instead: a default, a remembered filter, one action for many rows.
- **H8 The eye lands where the task is.** Look at list views and dashboards. Violation: the primary action is not the most visible control, the key column is not where a person looks first, figures that are compared do not line up. Instead: one visible primary action, the key column first, comparable figures aligned.
- **H9 An error says what to do.** Look at every error path. Violation: a code, a system name or "something went wrong" with no next step. Instead: what happened, what the person can do, where.
- **H10 Help where the hand is.** Look at every field that needs a format, a unit or a convention. Violation: the requirement is discovered after the error. Instead: the example or the unit beside the field.
- **H11 Reachable without a pointer.** Look at dialogs, inline edits and icon-only controls. Violation: an action reachable only by pointer, focus lost when a dialog closes, an icon-only control with no accessible name. Instead: keyboard order through the task, focus returned to the control that opened the dialog, a name and a title on every icon-only control.
- **H12 Readable.** Look at text on backgrounds and at target sizes. Violation: contrast a person strains at, a target smaller than a fingertip, a meaning carried by colour alone. Instead: contrast the project's own styles already give, targets of the project's standard size, a word or an icon beside the colour.

## States

Every view and every action is described in six states. A brief writes each as what the person sees, or `n/a — <reason>`. An audit writes `missing` where the interface shows nothing.

| State | What must be shown |
|-------|--------------------|
| empty | that there is nothing yet, and the one action that changes that |
| loading | that data is on its way, in place of where it will appear |
| error | H9: what happened, what to do |
| partial | which part succeeded, which did not, and why (bulk actions, uploads) |
| success | H1: what happened and how many |
| no permission | that the action exists, that this person cannot do it, and who can |

## User tasks

Three to five per surface, from the project's domains and the task text. For each: the steps as they are, the clicks, where a wrong turn is possible, whether it can be undone, the state matrix along the way. A finding or a change that no user task reaches is cut.

## Severity

| Severity | Meaning |
|----------|---------|
| blocking | a user task cannot be completed, or completes with a wrong result the person does not see |
| slowing | the task completes, with avoidable steps, errors, doubt or a wrong turn that can be undone |
| cosmetic | the task is unaffected; the defect is in appearance or wording |

The order of work follows severity, then pages: blocking first, one batch per page.

## Copy

- In the interface language, every sentence exact; never a placeholder.
- Actions are verbs that name the result ("Apply to 12 rows", not "OK"); the destructive verb names what is lost.
- An error is H9; a confirmation is H3; feedback is H1, with the count.
- Terms come from `PROJECT-OVERVIEW.md → Core Domains`; one term per thing across every page.

## Accessibility floor

Not a preference: a brief that drops below it is wrong. Every control reachable by keyboard in task order; focus visible and returned after a dialog; a name on every icon-only control; a label on every field; meaning never carried by colour alone; contrast and target size the project's own styles already provide.

## Out of scope

Palette, typeface, iconography, brand and visual style, unless the task asks for them. A brief or an audit names them under `## Out of scope` and leaves them.

## Review checks

Written into `REVIEW-CHECKLIST.md` by `/generate-knowledge`, each rewritten with the project's element and path from `FRONTEND-ARCHITECTURE.md → Design language`, only when that section exists.

1. Every new list view or detail view has an empty state with text, never a blank area, and a loading state where its data arrives after the page.
2. Every new action that changes data gives feedback through the project's feedback element, naming what changed and how many.
3. Every new destructive or bulk action confirms with the count and the consequence, or shows a preview before applying, through the project's confirmation or preview-then-apply pattern.
4. Every new error path shows text that says what happened and what to do, in the interface language; never a code or an identifier alone.
5. Every new control has a visible label or, when icon-only, an accessible name and a title; every new field that needs a format shows it beside the field.
6. A new page puts its primary action where the project's pages put theirs and uses the project's word for it.
7. New interface copy is in the interface language `FRONTEND-ARCHITECTURE.md` records, exact, with no placeholder; when the run has a brief, it matches the brief's `Copy:` lines.

## Sources

- Nielsen, "10 Usability Heuristics for User Interface Design" (H1–H10, reworded as checks).
- WCAG 2.2, level AA, for the accessibility floor (H11, H12).
- Project conventions, through `FRONTEND-ARCHITECTURE.md → Design language`, which win where they disagree with this card; the disagreement is written down there.
