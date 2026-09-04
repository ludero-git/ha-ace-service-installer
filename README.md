# <img width="50" height="50" align="absmiddle" alt="Logo" src="https://raw.githubusercontent.com/ludero-git/ha-ace-service-installer/main/ace_service_installer/icon.png" /> HA ACE Service Installer

[![Latest Version][version-shield]][repository]
[![Supports aarch64 Architecture][aarch64-shield]][repository]
[![Supports amd64 Architecture][amd64-shield]][repository]

Install and run the Alfen ACE Service Installer in Home Assistant.

## Installation

### 1. Open and add the repository

[![Open app][app-badge]][app-open]

**Or manually:**

1. In the Home Assistant App Store, open **Repositories**.
2. Add `https://github.com/ludero-git/ha-ace-service-installer`.
3. Refresh the App Store and open **ACE Service Installer**.

### 2. Install the app

Click **Install**.

### 3. Configure and start

Configure the app, then click **Start**. Access it through its web interface.

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
[app-badge]: https://my.home-assistant.io/badges/supervisor_addon.svg
[app-open]: https://my.home-assistant.io/redirect/supervisor_addon/?addon=a805add3_ace_service_installer&repository_url=https%3A%2F%2Fgithub.com%2Fludero-git%2Fha-ace-service-installer
[version-shield]: https://img.shields.io/github/v/tag/ludero-git/ha-ace-service-installer?sort=semver
[aarch64-shield]: https://img.shields.io/badge/aarch64-yes-green.svg
[amd64-shield]: https://img.shields.io/badge/amd64-yes-green.svg
