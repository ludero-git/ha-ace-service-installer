# <img width="50" height="50" align="absmiddle" alt="Logo" src="https://raw.githubusercontent.com/ludero-git/ha-ace-service-installer/main/ace_service_installer/icon.png" /> HA ACE Service Installer

[![Supports aarch64 Architecture][aarch64-shield]][repository]
[![Supports amd64 Architecture][amd64-shield]][repository]

Run the Alfen ACE Service Installer through a browser in Home Assistant.

## Installation

### 1. Add the repository

[![Add repository][repository-badge]][repository-add]

**Manually:**

1. From the Home Assistant App Store, navigate to the overflow menu in the top right corner and select "Repositories".
2. Add the following URL: `https://github.com/ludero-git/ha-ace-service-installer`.
3. Refresh the App store and you should see the ACE Service Installer app appear.

### 2. Install the app

[![Install app][app-badge]][app-install]

**Manually:**

1. From the Home Assistant App Store, navigate to ACE Service Installer.
2. Press "Install".

### 3. Configure and start

Configure the app from Home Assistant and start it. The application can then be accessed through its web interface.

## Technical

### Building

The container is built for both `amd64` and `aarch64`.

On AMD64 it uses Wine directly. On ARM64 it uses Hangover to provide Windows x86-64 compatibility.

During the image build, a Wine prefix is prepared with:

- .NET Framework 4.8
- Microsoft Core Fonts
- RGB font smoothing

### Patching

Several files require compatibility patches.

`Xwt.dll` is patched so `Xwt.StockIcons.GetIcon(string)` returns `null`. This prevents crashes when stock icons cannot be resolved, at the cost of some missing icons.

`Tmdns.MDns.dll` is patched for network discovery. `NetworkInterfaceHandler.CreateIpv4Socket(int)` is changed to use interface index `0`, and the associated `IPAddress.HostToNetworkOrder` conversion is removed.

`ACEServiceInstaller.exe.config` is modified to require .NET framework `v4.8` instead of `v4.8.1`. Required for Hangover, otherwise the program won't start up.

## License

[MIT](./LICENSE)

[repository]: https://github.com/ludero-git/ha-ace-service-installer
[repository-badge]: https://my.home-assistant.io/badges/supervisor_add_addon_repository.svg
[repository-add]: https://my.home-assistant.io/redirect/supervisor_add_addon_repository/?repository_url=https%3A%2F%2Fgithub.com%2Fludero-git%2Fha-ace-service-installer
[app-badge]: https://my.home-assistant.io/badges/supervisor_addon.svg
[app-install]: https://my.home-assistant.io/redirect/supervisor_addon/?addon=ace_service_installer&repository_url=https%3A%2F%2Fgithub.com%2Fludero-git%2Fha-ace-service-installer
[aarch64-shield]: https://img.shields.io/badge/aarch64-yes-green.svg
[amd64-shield]: https://img.shields.io/badge/amd64-yes-green.svg
