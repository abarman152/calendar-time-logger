# Categories

A **category** names the kind of work a session belongs to, such as *Development*, *Education*, or *Research*. Where a template says *how* work is recorded, a category groups work across templates, so you can see how much of your time went to each area in Work Logs, Analytics, and your exports.

Every template and every session has exactly one category. There is no blank or "uncategorized" state.

## Built-in categories

Six categories are built in:

| Category | Used by default for |
| --- | --- |
| **Development** | Software Engineering |
| **Education** | Study |
| **Research** | Research |
| **Content** | Writing |
| **Design** | Design |
| **General** | New quick tasks, and everything recorded before categories existed |

The Category menus offer the stored category list: these six to begin with, plus every category you add. Add one in **Categories** or by choosing **New Category…** in any Category menu; either way it stays in the list until you delete it.

## A template's category

![The template editor with Category set to Development under Basic Information, beside the Task Priority and Menu Bar settings](../Design/Screenshots/04-template-editor.png)

Choose it in **Templates**, under **Basic Information › Category**. The menu lists the available categories; **New Category…** at the bottom lets you type a new one in place, then **Add** (or Return) selects it and **Cancel** (or Escape) goes back to the menu.

- A category name can be up to 40 characters. Extra spaces are removed.
- Names that differ only in capitalization are the same category. Typing `research` selects the existing **Research**.
- A template can't be saved without a category; the footer says so if you try.

The template list shows each template's category under its name, and the template search field matches categories as well as names and tags.

### Managing categories

![The Categories sheet over the Templates screen: each category with the templates and work logs that use it, a Default badge on General, an actions menu on each row, and Add Category](../Design/Screenshots/03-templates.png)

The folder button beside **+** at the top of the template list opens **Categories**. Each row shows the category, which templates use it (or the number of templates), and how many work logs were recorded in it. A green record symbol marks the category of the session in progress. Every change shows immediately in every Category menu in the app, including the menu bar.

| Action | How | What happens |
| --- | --- | --- |
| **Add Category** | The button at the top right | Type a name and press **Add** (or <kbd>Return</kbd>). The category is saved straight away, even before a template uses it. |
| **Rename…** | The row's **⋯** menu, or right-click the row | Renames the category and every template that uses it. The category stays the same category; its name changes. Renaming onto a name that already exists merges the two. |
| **Move Templates…** | The row's **⋯** menu | Moves every template in this category to the one you choose. The category itself stays. |
| **Delete…** | The row's **⋯** menu | Deletes the category. See below. |

**Names.** Up to 40 characters; extra spaces are removed. Names are compared without regard to capitalization, so **Add Category** refuses `research` when **Research** exists, and says so under the field.

**General** is marked **Default**. It is where quick tasks start and where templates go when you have nothing better, so it can't be renamed or deleted. Every other category, including the built-in ones, can be.

### Deleting a category

- **No template uses it:** a confirmation asks first. **Delete Category** removes it; **Cancel** keeps it.
- **Templates use it:** the templates must go somewhere first. The **Delete** sheet lists the templates, the work logs recorded in the category, and the session in progress if it uses it. Choose **Move templates to**, then **Move and Delete**. The templates move and the category is deleted together, so a template never ends up in a category that no longer exists. If anything fails, nothing changes.

### What category changes never touch

| | Rename | Move Templates | Delete |
| --- | --- | --- | --- |
| **Templates in the category** | Take the new name | Move to the category you chose | Move to the category you chose |
| **Sessions you start afterwards** | Use the new name | Use the templates' new category | Use the templates' new category |
| **The session in progress** | Keeps its category | Keeps its category | Keeps its category |
| **Work logs already recorded** | Keep their category | Keep their category | Keep their category |

Work logs are never rewritten. A work log recorded in **Work** still says **Work** in Work Logs, Analytics, and exports after **Work** is renamed or deleted, and the Edit Entry menu shows it as **Work (deleted)**. To change one work log's category, use **Edit Entry**.

## A session's category

When a session starts, it takes its template's category. From then on the category belongs to the **session**, exactly like its task priority:

| You do this | What happens |
| --- | --- |
| Start from the **Start Work** sheet, or **Start with Category and Priority…** in the menu bar | The template's category is preselected; change it for this session only |
| Start a template directly (template menu, Recent Templates, menu bar row, <kbd>⌃</kbd><kbd>⌘</kbd><kbd>1</kbd>–<kbd>9</kbd>, Shortcuts) | The session uses the template's category |
| Start a **Quick New Task** | Choose a category in the sheet or the popover form; it starts as **General** |
| Choose **Change Category and Priority** while working (Dashboard, Session menu, menu bar popover) | Only the open session changes |
| **Change Template** while working, or on a completed work log | An inherited category follows the new template; one you chose for the session is kept |
| **Edit Entry** on a completed work log | Corrects that work log's category only |

![The Start Work sheet with Template, Category, Urgent, and Important](../Design/Screenshots/start-work.png)

**Changing a template never rewrites history.** If *Software Engineering* was in **Development** when you recorded a session on Monday and you move the template to **Professional Work** on Friday, Monday's work log still says **Development**; sessions started after Friday say **Professional Work**.

## Where categories appear

| Place | What you see |
| --- | --- |
| **Dashboard** | The running session's category beside its start time; each row of Today's Work names its category |
| **Menu bar** | The running session's category under the template name |
| **Work Completed** | A **Category** row |
| **Work Logs** | The category under the template name in each row, a **Category** row in the inspector, a **Category** filter, and search that matches category names. See [Work Logs](Work%20Logs.md). |
| **Analytics** | **Work by Category**: time, sessions, and share per category for the selected range, with the templates and priority combinations inside each. See [Analytics](Analytics.md). |
| **Calendar events** | A `Category:` line in the event notes |
| **Excel export** | A **Category** column, the **Category Analysis** preset, and a **Work by Category** block on the Summary sheet. See [Exporting Data](Exporting%20Data.md). |

![Work by Category in Analytics for the last 30 days](../Design/Screenshots/10-analytics-category.png)

## Upgrading from 1.3 to 1.4

Calendar Time Logger now keeps a list of categories instead of deriving it from your templates. On first launch after upgrading, the list is filled with the six built-in categories plus every category your templates use. No template or work log is changed.

## Upgrading from 1.2

Categories arrived in Calendar Time Logger 1.3.0. On the first launch of 1.3.0, every existing template and every existing work log is given the category **General**. Nothing else about them changes: names, icons, colors, priorities, tags, notes, times, and Calendar events are all kept. Set your templates' categories afterwards; new sessions will use them, and you can correct individual older work logs with **Edit Entry**.

---

[Back to User Guide](README.md) · [Previous: Task Priority](Task%20Priority.md) · [Next: Dashboard](Dashboard.md)
