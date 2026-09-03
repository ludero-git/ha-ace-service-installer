# ACE Service Installer

Install and run the Alfen ACE Service Installer in Home Assistant.

## Installation

1. Install the app.
2. Review the configuration.
3. Start the app.
4. Open **ACE Service Installer** from the Home Assistant sidebar.

## Architectures

Supported architectures:

- `amd64` using Wine
- `aarch64` using Hangover

ARM64 systems require a compatible 4 KiB page-size environment.

## Network

The app uses host networking and requires `NET_ADMIN` and `NET_RAW` for local device discovery.

Network isolation, VLANs, or firewall rules may interfere with discovery.

## Troubleshooting

If the installer or application does not start:

```yaml
show_desktop: true
debug_wine: true
```

If automatic installation or launch is not working, verify:

```yaml
auto_install: true
auto_launch: true
```

If maximization causes issues:

```yaml
auto_maximize: false
```

## Support

Source code and issue tracking:

https://github.com/ludero-git/ha-ace-service-installer

## License

This project is licensed under the MIT License.

Third-party components remain subject to their own licenses and terms.
