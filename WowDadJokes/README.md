# WowDadJokes

In-game World of Warcraft dad joke collection with a scrollable UI, individual **Joke** and **Punchline** chat buttons, an in-game joke editor, a chat channel selector, and a two-step **Random Joke** keybind.

## Features
- **Starter Collection**: Comes pre-loaded with 28 classic Warcraft dad jokes saved in `WowDadJokesDB`.
- **Joke & Punchline Buttons**: Every joke row displays both the setup and punchline with dedicated **Joke** and **Punchline** buttons to send them individually to chat.
- **Two-Step Random Joke Keybind (No Repeats)**:
  - **1st press**: Picks a random dad joke and says the **setup** in your chosen channel. Never repeats a joke until you've cycled through your entire collection!
  - **2nd press**: Says the matching **punchline**!
  - Bind a key right inside the `/joke` window (click the **Keybind** button at the top, or Right-Click it to unbind), or in WoW's **Options -> Keybindings -> AddOns -> WoW Dad Jokes**.
- **Channel Selector & Quick Toggle**:
  - Choose between **Say (`/s`)**, **General (`/1`)**, **Party (`/p`)**, **Raid (`/ra`)**, **Instance (`/i`)**, **Guild (`/g`)**, and **Yell (`/y`)**.
  - **In the UI**: **Left-Click** the Channel button to open the dropdown list, or **Right-Click** it to quickly toggle/cycle to the next channel.
  - **Keybind**: Bind **Cycle Joke Chat Channel** in WoW's **Keybindings -> AddOns -> WoW Dad Jokes** to toggle channels on the fly.
  - **Slash Commands**: Type `/joke channel` to cycle channels, or `/joke general` (or `/joke 1`), `/joke party`, `/joke raid`, `/joke guild`, `/joke say`, `/joke instance`, `/joke yell` to switch directly.
  - Automatically falls back safely if you aren't currently in the selected group/channel.
- **Add, Edit & Delete**: Add new jokes, edit existing setups/punchlines, delete jokes, or click **Restore Defaults** to bring back any deleted starter jokes.

## Commands
- `/joke` (or `/jokes`, `/dadjoke`, `/wdj`) — Open/close the WoW Dad Jokes window
- `/joke random` — Say a random joke setup (or deliver the queued punchline)
- `/joke channel` — Cycle to the next chat channel
- `/joke <say|general|party|raid|instance|guild|yell>` — Switch directly to that chat channel
- `/joke add` — Open the window directly to the Add New Joke editor
