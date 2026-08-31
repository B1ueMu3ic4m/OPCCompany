<!-- Translated from MULTI_PRODUCT_WORKSPACES.md; the Chinese original remains authoritative for internal history. -->

# Multi-Product Workspace Design

Last updated: 2026-05-07

Current status: Multi-product workspaces have reached the formal-use baseline. Product switching, the current product team, product-scoped task/message/memory/terminal-log filtering, legacy task ownership migration, and product isolation health checks are all in place; this document keeps the model design and future evolution boundaries.

## Core principles

OPC Company should not hold only one project. The correct structure is:

```text
OPC Company
├── Product Workspace A
│   ├── Independent repo/directory
│   ├── Independent task board
│   ├── Independent terminal logs
│   ├── Independent docs and decision records
│   └── Can bind a set of agent employees
├── Product Workspace B
└── Product Workspace C
```

## Product–employee relationship

- The CTO is a company-level role and can see all products.
- UI, engineering, test, and review employees can be assigned to one or more products.
- Each product has its own current stage: research, design, implementation, testing, release, maintenance.
- Each product has its own root directory, Git branch, environment variables, and CLI working directory.

## Data model

The current core models are already in place:

- `ProductWorkspace`
  - id
  - name
  - shortName
  - rootDirectory
  - status
  - stage
  - assignedAgentIDs
  - createdAt
  - updatedAt
- `ProductTask`
  - productID
  - ownerID
  - status
  - successCriteria
- `ProductTerminalSession`
  - productID
  - agentID
  - command
  - output
  - exitCode

Items still under evaluation based on real usage:

- A graphical git worktree manager.
- A multi-product disk usage/archival policy panel.
- Cross-product resource quotas and employee scheduling conflict warnings.

## UI changes

The left sidebar should be upgraded from an "employee list" to two layers:

1. Product switcher
   - Current product
   - Add product
   - Pause/archive product
2. Employees and tasks under the current product

The center main view switches with the product:

- Company overview: progress of all products
- Single-product office: the current product team's workspace
- Terminal Hall: employee terminals filtered by product

The right panel changes with the selected object:

- Product selected: product Command Center
- Boss selected: company Command Center
- CTO selected: cross-product scheduling console
- Employee selected: employee chat/archive/terminal

## Parallel development rules

- Each product defaults to its own Git worktree or independent directory.
- The same engineering agent can write to only one product at a time, avoiding context contamination.
- The CTO can view status across products, but must specify a product when dispatching tasks.
- Terminal commands must use the product root directory as the working directory.
- Each product's memory, logs, tasks, and acceptance conclusions are saved independently.
