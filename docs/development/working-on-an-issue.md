# Working on an issue

How to take an issue from the board to a merged PR. This assumes your laptop
is set up ([getting-started.md](getting-started.md)). Branch, commit and PR
rules are in [CONTRIBUTING.md](../../CONTRIBUTING.md); this page shows where
issues fit into them.

## Where issues live

- **Every issue is in [Nova-Collected](https://github.com/UTATRocketry/Nova-Collected/issues)**,
  even when the code goes in another repo. Don't open issues in novaOps-back,
  novaOPS-front or novaGround.
- **The board is the [Nova Software project](https://github.com/orgs/UTATRocketry/projects/3).**
  It has two views: **Status Board** (cards in a column per status) and
  **Task List** (a table). Each card's **Code repo** field says which repo the
  change goes in, and **Status** says where it is:

  | Status | Means | Moved by |
  |---|---|---|
  | Backlog | Not ready: open questions or a blocking issue | the board, when a new issue is added |
  | Ready | Questions answered; anyone can pick it up | leads |
  | In progress | Someone is assigned and working on it | you |
  | In review | A PR is open | you |
  | Done | Merged, issue closed | the board, when the issue closes |

- **Milestones** are test campaigns (e.g. Destiny Hotfire Testing). An issue
  with a milestone is needed by that date.
- **Labels** you'll meet first: `good first issue` (suitable for a new
  member), `needs-hardware` (needs the bench or test stand to build or check),
  `needs-design` (agree the design in the issue before writing code). All
  labels and what they mean are on the
  [labels page](https://github.com/UTATRocketry/Nova-Collected/labels).

## 1. Pick an issue

1. Open the **Status Board** view and look in the **Ready** column. For your
   first issue, filter by `label:"good first issue"`.
2. Open the issue and check that:
   - nobody is assigned;
   - **Relationships** in the sidebar shows no open "Blocked by" issue;
   - its **Open questions** are ticked or answered in the comments.
3. Read the whole issue: Summary, Details, Acceptance criteria and any
   linked issues.

> [!TIP]
> Not sure if an issue is right for you? Ask in `#software` on Slack before
> starting. A lead can suggest one.

## 2. Claim it

1. In the issue's sidebar, **Assignees → assign yourself**.
2. On the board, move the card to **In progress**.
3. Leave a comment saying you've started. If something in the issue is
   unclear, ask in the same comment.

> [!IMPORTANT]
> Discuss the issue **in the issue's comments**, not only on Slack. Decisions
> made on Slack are lost when the thread scrolls away. If you agree something
> on Slack, write it into the issue.

## 3. Make a branch in the right clone

The **Code repo** field tells you which `dev/` clone to work in:

| Code repo | Clone | Branch from | PR into |
|---|---|---|---|
| backend | `dev/backend` (novaOps-back) | `dev` | `dev` |
| frontend | `dev/frontend` (novaOPS-front) | `dev` | `dev` |
| novaGround | `dev/novaGround` | `dev` | `dev` |
| ops | your Nova-Collected clone itself | `main` | `main` |

Name the branch after the change, following
[CONTRIBUTING.md §3](../../CONTRIBUTING.md#supporting-branches). For issue
#23 in the backend:

```bash
cd dev/backend
git switch dev
git pull
git switch -c bugfix/actuator-state-on-config-switch
```

> [!NOTE]
> An issue's **Suggested branch** is a starting point. Check its prefix is
> `feature/`, `bugfix/` or `chore/`: CI rejects other prefixes.

## 4. Do the work

- **Stay inside the issue.** If you find another bug or idea, open a new
  issue for it (**New issue** in Nova-Collected, then pick a form) and keep
  going.
- **Tick the Acceptance criteria** in the issue as you meet them (edit the
  issue, or click the checkboxes).
- **Test it** to the level [CONTRIBUTING.md §7](../../CONTRIBUTING.md#7-testing)
  asks for. Most changes can be tested with the simulator
  ([getting-started.md](getting-started.md#run-each-part-without-hardware)).
- **`needs-hardware` issues:** ask a lead to put your branch on the bench.
- **Write down what you learn.** Investigation issues end with the findings
  written in the issue, and follow-up issues opened.

> [!CAUTION]
> If your change affects how actuators are commanded, safety rules,
> interlocks or timing, add the `hardware-risk` label to your PR. It needs a
> lead's approval ([CONTRIBUTING.md §4](../../CONTRIBUTING.md#4-making-a-change-everyone)).

## 5. Open the PR

Push your branch and open the PR as in
[CONTRIBUTING.md §4](../../CONTRIBUTING.md#4-making-a-change-everyone). In
the PR description, link the issue so that merging the PR closes it:

| PR is in | Write in the PR description |
|---|---|
| novaOps-back, novaOPS-front or novaGround | `Closes UTATRocketry/Nova-Collected#23` |
| Nova-Collected | `Closes #23` |

In a code repo, a plain `#23` means issue 23 of *that* repo, so it must name
Nova-Collected in full.

- **The PR only does part of the issue?** Write
  `Part of UTATRocketry/Nova-Collected#23` instead, so the issue stays open.
- Then move the card to **In review**.

## 6. After it merges

1. The issue closes when the PR is merged into `dev` (or `main` in
   Nova-Collected), and the board moves its card to **Done**. Check that it
   did; if you wrote `Part of`, the issue stays open on purpose.
2. Switch back to `dev` and pull, ready for the next one.

## When an issue spans two repos

A change that needs both the backend and the frontend is split into two issues,
one per repo. The backend one **blocks** the frontend one: do it first, or
work on both together and test them together on the simulator
([CONTRIBUTING.md §7](../../CONTRIBUTING.md#how-far-a-change-must-go)).

## When you can't finish

That's fine. Say so early:

1. Comment on the issue with what you did, what's left, and a link to your
   branch.
2. Unassign yourself and move the card back to **Ready**.

## Opening a new issue

Use **New issue** in Nova-Collected and pick the form that fits: Bug,
Feature, Investigation, Task or Test anomaly. The form adds the right labels
and `needs-triage`, and the issue lands on the board in **Backlog**. A lead
then triages it and sets its fields. Something seen during a test is a
**Test anomaly**: file it the same day, with the recording link.
