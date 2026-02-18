# discourse-tag-gating

A Discourse plugin that gates access to topics based on tags and user field values.

## Overview

This plugin allows you to restrict access to topics with a specific tag to only users who meet a configurable user field criteria. Topics that are gated will be hidden from unauthorized users across all Discourse surfaces — topic lists, search, category pages, and direct links.

## Features

- **Topic list filtering** — Gated topics are hidden from latest, new, unread, and category feeds
- **Search filtering** — Gated topics do not appear in search results
- **Category featured topics filtering** — Gated topics are hidden from the category page featured topic list
- **Direct link protection** — Users who access a gated topic directly via link receive a clear error message explaining why access was denied
- **Owner bypass** — Topic owners can always see their own topics regardless of access settings
- **Staff bypass** — Staff members always have full access
- **Runtime configurable** — All settings can be changed from the admin panel without a restart

## Installation

Follow the standard Discourse plugin installation process:

1. Add the plugin to your `app.yml`:
   ```yaml
   hooks:
     after_code:
       - exec:
           cd: $home/plugins
           cmd:
             - git clone https://github.com/SizeStation/discourse-tag-gating.git
   ```
2. Rebuild your Discourse container:
   ```bash
   ./launcher rebuild app
   ```

## Configuration

All settings are available under **Admin → Plugins**.

| Setting | Type | Default | Description |
|---|---|---|---|
| `tag_gating_enabled` | Boolean | `false` | Enable or disable the plugin entirely |
| `tag_gating_tag_name` | String | `nsfw` | The tag name used to gate topic access |
| `tag_gating_user_field_id` | Integer | `7` | The user field ID checked for access |
| `tag_gating_user_field_logic` | Boolean | `false` | When `true`, field must be checked for access. When `false`, field must be unchecked |

## How It Works

When enabled, the plugin checks whether a topic has the configured tag. If it does, access is granted only to users whose specified user field matches the configured logic value. Staff and topic owners always bypass the gate.

The plugin enforces this at five layers:

1. **Guardian** — blocks direct topic access and delivers a user-facing error message
2. **Post scope** — filters posts from bookmarks, activity feeds, and API queries
3. **TopicQuery** — filters topics from all list views
4. **Search** — filters topics from search results
5. **CategoryList** — filters topics from category featured topic lists

## User Field Setup

1. Go to **Admin → Community → User Fields**
2. Create a checkbox field for users to opt into gated content
3. Note the field ID (shown in the URL when editing)
4. Set `tag_gating_user_field_id` to that ID in plugin settings

## Limitations

- Currently supports a single tag and a single user field
- Multiple tag support and group-based access may be added in future versions

## Author

SkyDev125 — [https://github.com/SizeStation/discourse-tag-gating](https://github.com/SizeStation/discourse-tag-gating)