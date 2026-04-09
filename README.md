# Move2Play — Claude Code Plugin Marketplace

Shared Claude Code skills for the Move2Play team.

## Setup (one-time)

Paste the following into Claude Code:

```
Set up the Move2Play plugin marketplace. Read my ~/.claude/settings.json file. If it doesn't exist, create it. Add the following to the "extraKnownMarketplaces" key (merge with any existing marketplaces, don't overwrite them):

"m2p-marketplace": {
  "source": {
    "source": "github",
    "repo": "SkwrlDesign/claude-plugins"
  }
}

Then verify the file is valid JSON and confirm it worked.
```

That's it! Claude will handle the rest. Restart Claude Code after setup.

## What's included

- **Operations Assistant** — Business context, data sources, inventory concepts, advertising query patterns, and response guidelines
- **Project Knowledge** — Product catalog, warehouse network, Google Sheets references, BigQuery table schemas, and currency conversion rates

## Updating

When the team knowledge changes, an admin pushes updates to this repo. Team members get updates automatically on session start.
