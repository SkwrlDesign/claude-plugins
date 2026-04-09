# Move2Play — Claude Code Plugin Marketplace

Shared Claude Code skills for the Move2Play team.

## Setup (one-time)

### 1. Install GitHub CLI
```bash
brew install gh
```

### 2. Log into GitHub
```bash
gh auth login
```
Follow the prompts — pick "GitHub.com", "HTTPS", and "Login with a web browser".

### 3. Add the marketplace (in Claude Code)
```
/plugin marketplace add SkwrlDesign/claude-plugins
```

### 4. Install the plugin (in Claude Code)
```
/plugin install m2p-operations@m2p-marketplace
```

Done! Claude now has Move2Play operations context automatically.

## What's included

- **Operations Assistant** — Business context, data sources, inventory concepts, advertising query patterns, and response guidelines
- **Project Knowledge** — Product catalog, warehouse network, Google Sheets references, BigQuery table schemas, and currency conversion rates

## Updating

When the team knowledge changes, an admin pushes updates to this repo. Team members get updates automatically, or can run `/plugin update` in Claude Code.
