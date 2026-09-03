#!/usr/bin/env python3
"""Create an Openbox configuration with disabled features like desktop switching and minimizing."""

import os
from pathlib import Path
import xml.etree.ElementTree as ET

SOURCE = Path(os.environ.get("ACE_OPENBOX_SOURCE", "/etc/xdg/openbox/rc.xml"))
DEST = Path(os.environ.get("ACE_OPENBOX_DEST", "/data/home/ace/.config/openbox/rc.xml"))
SHOW_DESKTOP = os.environ.get("SHOW_DESKTOP", "false").strip().lower() == "true"


def name(node):
    """Return an XML tag name without its namespace."""
    return node.tag.rsplit("}", 1)[-1]


def child(parent, child_name):
    """Return the first direct child with the requested tag name."""
    return next((item for item in parent if name(item) == child_name), None)


def has_action(node, names):
    names = {item.lower() for item in names}
    return any(
        action.attrib.get("name", "").strip().lower() in names
        for action in node.iter()
        if name(action) == "action"
    )


def has_desktop_action(node):
    return has_action(node, {
        "desktopnext",
        "desktopprevious",
        "gotodesktop",
        "sendtodesktop",
        "sendtodesktopdirectional",
    })


def has_minimize_action(node):
    return has_action(node, {"iconify"})


def shows_client_menu(node):
    for action in node.iter():
        if name(action) != "action":
            continue
        if action.attrib.get("name", "").strip().lower() != "showmenu":
            continue

        menu = child(action, "menu")
        if menu is not None and (menu.text or "").strip().lower() == "client-menu":
            return True

    return False


tree = ET.parse(SOURCE)
root = tree.getroot()

# Preserve the namespace used by the source configuration.
if root.tag.startswith("{"):
    ET.register_namespace("", root.tag[1:].split("}", 1)[0])

# Configure a fixed four-workspace layout without the desktop popup.
desktops = child(root, "desktops")
if desktops is not None:
    for key, value in (("number", "4"), ("firstdesk", "1"), ("popupTime", "0")):
        item = child(desktops, key)
        if item is not None:
            item.text = value

if not SHOW_DESKTOP:
    # Remove the minimize button from window title bars.
    theme = child(root, "theme")
    if theme is not None:
        title_layout = child(theme, "titleLayout")
        if title_layout is not None and title_layout.text:
            title_layout.text = title_layout.text.replace("I", "")

mouse = child(root, "mouse")
if mouse is not None:
    for context in list(mouse):
        if name(context) != "context":
            continue

        context_name = context.attrib.get("name", "").strip().lower()

        for binding in list(context):
            if name(binding) != "mousebind":
                continue

            button = binding.attrib.get("button", "").strip().lower()

            # Disable workspace switching via the desktop mouse wheel.
            if context_name in {"desktop", "root"} and button in {
                "up", "down", "button4", "button5", "4", "5"
            }:
                context.remove(binding)
                continue

            if not SHOW_DESKTOP and (
                has_minimize_action(binding)
                or (
                    context_name in {"frame", "titlebar", "title"}
                    and shows_client_menu(binding)
                )
            ):
                context.remove(binding)

keyboard = child(root, "keyboard")
if keyboard is not None:
    for binding in list(keyboard):
        if name(binding) != "keybind":
            continue

        # Remove workspace shortcuts and hidden-desktop actions.
        if has_desktop_action(binding) or (
            not SHOW_DESKTOP
            and (has_minimize_action(binding) or shows_client_menu(binding))
        ):
            keyboard.remove(binding)

DEST.parent.mkdir(parents=True, exist_ok=True)
tree.write(DEST, encoding="utf-8", xml_declaration=True)