# Taxi

Two independent Flutter applications:

- `taxi-customers` — customer application (`taxi_customers`).
- `taxi-driver` — driver application (`taxi_driver`).

Both projects include Android, iOS, web, Windows, macOS, and Linux scaffolding.

## Run

From either application directory:

```sh
flutter pub get
flutter run
```

For a browser preview in a dev container:

```sh
flutter run -d web-server --web-hostname 0.0.0.0 --web-port 8080
```

Forward port 8080 in VS Code to open the preview.

## Development container

Open the repository in VS Code and select **Dev Containers: Reopen in Container**.
The `.devcontainer/devcontainer.json` configuration is copied from
[`vensar7/mobile`](https://github.com/vensar7/mobile/tree/main/.devcontainer).
It installs Flutter stable and the Dart/Flutter extensions.

Each app manages its dependencies separately. Run `flutter pub get` in both
directories after the container starts. Native builds require the corresponding
platform toolchains; iOS and macOS require macOS with Xcode.
