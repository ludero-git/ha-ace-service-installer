#!/usr/bin/env bash

ACE_INSTALLER_URL="$(jq -r '.installer.url' "$ACE_OPTIONS")"
ACE_INSTALLER_MODE="$(jq -r '.installer.mode' "$ACE_OPTIONS")"
ACE_AUTO_INSTALL="$(jq -r '.startup.install' "$ACE_OPTIONS")"
ACE_AUTO_LAUNCH="$(jq -r '.startup.launch' "$ACE_OPTIONS")"
ACE_DISPLAY_MODE="$(jq -r '.display.mode' "$ACE_OPTIONS")"
ACE_AUTO_MAXIMIZE="$(jq -r '.display.maximize' "$ACE_OPTIONS")"
ACE_LOG_LEVEL="$(jq -r '.logging.level' "$ACE_OPTIONS")"