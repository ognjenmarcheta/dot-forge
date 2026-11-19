# Banner

`media/project-banner.png` (1730 × 909) is the README banner. The anvil in the
terminal is `config/hello/byteforge.logo`, the logo the startup card draws.

- `banner.html`: the page, with `@@ART@@` where the anvil goes.
- `render-banner.py`: fills in the anvil from the logo file.

## Re-render

Run from the repo root (needs Python 3 and Google Chrome):

```sh
python3 media/brand/render-banner.py config/hello/byteforge.logo media/brand/banner.html /tmp/banner.html
google-chrome --headless=new --hide-scrollbars --window-size=1730,909 \
  --virtual-time-budget=4000 --screenshot=media/project-banner.png file:///tmp/banner.html
```
