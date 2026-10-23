## Adding repo

```ini
[turann-s-place]
Server = https://turannul.github.io/KaiT2en-Arch/$arch
SigLevel = Never
```
The repo signature is entirely optional.
```bash
# Import key
curl -fsSL https://turannul.github.io/KaiT2en-Arch/key.asc | sudo pacman-key --add -
sudo pacman-key --lsign-key turannul
```
If key is added can change Never to Required
```ini
SigLevel = Required
```
