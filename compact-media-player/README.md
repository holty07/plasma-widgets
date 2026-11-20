# Compact Media Player

Compact MPRIS media controller with a cava audio visualiser. Plugin ID: `io.github.holty07.compactmediaplayer`.

## Install

```bash
ln -s "$PWD" ~/.local/share/plasma/plasmoids/io.github.holty07.compactmediaplayer
systemctl --user restart plasma-plasmashell.service
```

### Visualiser (optional)

Needs `cava`. The bridge keeps the newest frame at `$XDG_RUNTIME_DIR/cava-plasmoid.raw` for the widget to read.

```bash
install -Dm755 support/cava-plasmoid-bridge ~/.local/bin/cava-plasmoid-bridge
install -Dm644 support/plasmoid.conf ~/.config/cava/plasmoid.conf
install -Dm644 support/cava-plasmoid.service ~/.config/systemd/user/cava-plasmoid.service
systemctl --user daemon-reload
```

With "auto-manage cava" on (the default), the widget starts and stops the service itself.

## Choosing a player

By default the widget follows whichever MPRIS player started most recently. To follow one app only, open the widget settings, go to **Player**, tick "Only ever follow one player", and pick it from the detected list. Matching uses the player's desktop entry first, then its identity. For example, limusic has no desktop entry, so it matches on its identity, `Limusic`.
