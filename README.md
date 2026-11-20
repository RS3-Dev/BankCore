# Bank Core

Bank Core lets RuneScape bank plugins share one sidebar and display their own
arrangements of your bank items. Bank Tags, Bank Cleaner, Advanced Bank Search
and War Chest provide the features; Core supplies the bank window space and
handles the real items behind their pages.

## Install

Enable **PrettyUI**, **Bank Core**, and the bank feature plugins you want in your
client's plugin manager. Core by itself provides no tags, categories or searches.

For a manual installation, create a `bankcore` folder in your client's development
plugins directory. Copy `main.lua`, `plugin.json` and `lib/` from this
repository into it, or extract the contents of a runtime release ZIP into it:

```text
plugins/
  bankcore/
    main.lua
    plugin.json
    lib/
```

Install PrettyUI separately. No build step is needed. The docs and examples are
for reference and do not need to go in your Core plugin folder.

## Use it

1. Open your bank and select **All Items**.
2. Click a plugin's icon on the rail. Hover an icon to see its name.
3. Choose a tag, category or search result in that plugin's sidebar.
4. Use the displayed items with the bank's normal clicks and menus.
5. Click a native bank tab to return to the normal bank view.

The **Return to Bank** button above the sidebar also closes any plugin page or
custom view. It is disabled while the normal bank is displayed, and returning
keeps the selected plugin's sidebar open.

A plugin with no sidebar column can open its page directly from its rail icon.
Drag an icon up or down the rail to change the order; Core remembers it, and
dragging does not switch the plugin or page you are using.

These pages rearrange the view of your items; they do not create items or add
bank storage. Repeated item pictures do not duplicate an item in your bank. When
a page lists an item that stacks in the bank more than once, every picture shows
your one stack of it and works with it. Items that never stack, such as augmented
gear, are separate stacks: each picture uses the next one, and a picture with no
stack left shows zero.

## Settings and troubleshooting

The fixed **Settings** cog at the bottom of the bank's icon rail opens
Core's settings in the bank item area. It stays below the scrolling plugin icons
and is not a registered plugin. Click it again, or **Return to Bank**, to close
the settings page. The **X** in the page header also returns to the bank.
The plugin manager also offers settings, so you can recover from a fully hidden sidebar without a shortcut.
Selecting Settings clears the plugin selection. The content column stays visible
in Expanded mode and collapses in Rail only or Fully collapsed mode;
the cog is highlighted while its page is open. Select a plugin icon to reopen
that plugin's sidebar. Plugins that provide only a page also highlight their
icon without opening a sidebar, and clicking their icon again closes the page.

Settings include **Enable debug**, which writes diagnostics to
the client log, and **Reset geometry**, which clears Core's saved bank window
adjustments. After resetting, close and reopen the bank to measure a fresh layout.
General settings start with **Sidebar expansion**, followed by **Sidebar position**.
Position chooses Left (Rail / Sidebar / Bank) or Right (Bank / Sidebar / Rail),
in either interface mode. Expansion controls modern-mode resizing: **Expand to the side** (the default) keeps
the native bank stationary and grows toward the chosen side; **Evenly** grows
around the window's center. Existing Left preferences migrate to Expand to the side + Left.

**Sidebar on bank open** offers **Expanded**, **Rail only** (the default), and
**Fully collapsed**. The latter two clear the selection when the bank closes.
Click the selected plugin icon again to collapse its column.

**Expand Sidebar** defaults to **Ctrl** and selects the first icon in your saved rail order. Press it again
to collapse back to your configured state. It is available in Rail only and Fully
collapsed modes; the keybind is disabled when the sidebar starts Expanded.

**Enable rail peeking** is available only in Fully collapsed mode. Hold its separate
**Peek Rail** keybind (default **Shift**) to reveal the rail and release to retract it. Selecting a
plugin or opening settings keeps that selection visible after you release the key.
The two keybind fields sit side by side and retain their values when disabled.
They must use different shortcuts. PrettyUI input capture and blocked keyboard
input suppress these shortcuts.

Debug logging and geometry recovery are under **Developer settings**, with
instructions for repositioning and resetting the bank.
Leave debug off during normal play. Feature plugins have their own settings.
Banking Tweaks supplies modifier-click options.

- **No sidebar:** check that PrettyUI and Core are enabled, then reopen the bank.
- **No feature icons:** check that the feature plugins and their dependencies loaded.
- **A page will not open:** select the bank's native All Items tab and try again.
- **A problem after reloading:** Core retains registered feature plugins across
  session replacement while those plugins remain running. The client's `prl`
  command disables and re-enables Core; required dependents can be disabled as
  part of that operation. Check `plist` and re-enable those feature plugins
  with `pon <plugin folder>`. Core cannot restore plugins the client has disabled.
  Keep your saved plugin data while investigating.

Closing the bank or disabling Core removes its controls and restores the bank
window. A client component that no longer accepts changes can delay restoration;
the [known limitations](docs/API.md#known-limitations) describe that case.

## Develop a bank plugin

The mod.io implementation of Bank Core has ID **6464293**. To depend on it, add
this entry to your plugin manifest:

```json
"requiredDependencies": {
  "bankcore": 6464293
}
```

Core 1.1.0 adds `GetBankState()` and `onBankStateChanged(state)` for native
All Items selection, search, filters and presets. Search and filters use the
shared cancel label's English text to distinguish their modes. The API also
supports optional page titles, native drag settings, sidebar sprites and native
bank-tab/slot reads. See the API reference for field formats and callbacks.

Use [`bankcore.SanitizeString(text)`](docs/API.md#sanitize-player-text) before
saving or displaying player text from sharecodes or manual entry. It strips
game text tags, including inline images and sprites that can crash the client
when their IDs are invalid. Sanitize existing stored text on display as well.

- [API reference](docs/API.md): register a sidebar, supply an item page or draw a custom
  view, and read menus.
- [Examples](examples/README.md): a standard page, sidebar controls and a custom page.
- [Contributing](CONTRIBUTING.md): guidelines for changes and pull requests.

Core requires no HTTP permission and sends no network requests. Check input and
appearance in RuneScape when changing those parts.

## License

Copyright (C) 2026 Bank Core contributors. Core and its examples are licensed
under the [BSD 2-Clause License](LICENSE)
(`BSD-2-Clause`). Include the license when redistributing them.

## Runtime releases

Download a runtime ZIP from [GitHub Releases](https://github.com/RS3-Dev/bank-utils-core/releases).
Each ZIP contains `main.lua`, `plugin.json` and `lib/` at its root and is ready
to install without a build step. The BSD license is embedded in `main.lua`;
repository docs, examples and the standalone license file are excluded.
