# Documentation

All Calendar Time Logger documentation lives here. Only `README.md` and `CLAUDE.md` (and the non-Markdown `LICENSE`) stay at the repository root. Calendar Time Logger is released under the [MIT License](../LICENSE) by Abir Barman ([abirbarman.com](https://abirbarman.com)).

```
Documentation/
├── README.md                  this index
├── Architecture/              how the app is built
├── Decisions/                 Architecture Decision Records
├── Design/                    branding, icon, menu bar, installer artwork, screenshots
├── Development/               setup, conventions, documentation rules
├── Product/                   requirements and privacy
├── Releases/                  release process, changelog, versioning
├── Testing/                   test strategy, coverage, manual QA
└── User Guide/                how to use the app
```

## For people using the app

Start at the [User Guide](User%20Guide/README.md).

| Page | Purpose |
| --- | --- |
| [Getting Started](User%20Guide/Getting%20Started.md) | Install, grant permissions, record a first session |
| [App Overview](User%20Guide/App%20Overview.md) | The main window, menu bar, menus, and Shortcuts actions |
| [Sessions](User%20Guide/Sessions.md) | Start Work, Pause, Resume, Finish Work, Cancel Session, recovery |
| [Task Priority](User%20Guide/Task%20Priority.md) | Urgent and Important, template defaults, per-session values, Quick New Task |
| [Categories](User%20Guide/Categories.md) | Template and session categories, managing them, and how history is kept |
| [Dashboard](User%20Guide/Dashboard.md) | Current session, Today's Progress, Quick Actions, Today's Work |
| [Templates](User%20Guide/Templates.md) | Names, SF Symbol icons, categories, colors, calendars, tags, menu bar, notifications |
| [Menu Bar](User%20Guide/Menu%20Bar.md) | The CTL item, its popover, and per-template appearance |
| [Work Logs](User%20Guide/Work%20Logs.md) | Reviewing, searching, filtering, editing, deleting completed sessions |
| [Calendar](User%20Guide/Calendar.md) | Permission, calendar choice, event contents, sync problems |
| [Analytics](User%20Guide/Analytics.md) | Date ranges, work summary, categories, task priority, per-template and daily totals |
| [Notifications](User%20Guide/Notifications.md) | The four notifications and how to control them |
| [Exporting Data](User%20Guide/Exporting%20Data.md) | Excel export: scopes, choosing and ordering columns, Summary sheet |
| [Settings](User%20Guide/Settings.md) | Every setting, pane by pane |
| [Troubleshooting](User%20Guide/Troubleshooting.md) | Symptoms, causes, and fixes |
| [FAQ](User%20Guide/FAQ.md) | Short answers to common questions |

## For people working on the app

| Document | Purpose |
| --- | --- |
| [Architecture/ARCHITECTURE.md](Architecture/ARCHITECTURE.md) | Layers, domain, services, app composition, error handling |
| [Decisions/README.md](Decisions/README.md) | Index of ADRs, and when an ADR is required |
| [Design/BRANDING.md](Design/BRANDING.md) | App icon, CTL mark, menu bar presentation, DMG artwork |
| [Development/DEVELOPMENT.md](Development/DEVELOPMENT.md) | Requirements, project layout, demo mode, scripts, conventions |
| [Development/DOCUMENTATION_RULES.md](Development/DOCUMENTATION_RULES.md) | Where documentation belongs and how it stays accurate |
| [Product/PRODUCT_REQUIREMENTS.md](Product/PRODUCT_REQUIREMENTS.md) | Product rules, requirements, and their status |
| [Product/PRIVACY.md](Product/PRIVACY.md) | What is stored, what is sent to Calendar, permissions |
| [Releases/RELEASE.md](Releases/RELEASE.md) | Release checklist, packaging, signing, notarization |
| [Releases/CHANGELOG.md](Releases/CHANGELOG.md) | What changed in each version |
| [Releases/VERSION.md](Releases/VERSION.md) | Current version and the versioning policy |
| [Testing/TESTING.md](Testing/TESTING.md) | Automated coverage, manual QA checklist, verification logs |
| [Testing/30-Day Regression.md](Testing/30-Day%20Regression.md) | The simulated 30-day regression: data strategy, scenarios, and results |

Assets used by the documentation are in [Design/Assets](Design/Assets) (artwork) and [Design/Screenshots](Design/Screenshots) (captured from the DEBUG demo build).
