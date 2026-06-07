# Visual Style Options

DF asked what visual styles are available. Homepage supports several looks through `settings.yaml` before touching custom CSS. These options are safe starting points.

## Option A — Obsidian Glass, recommended

Dark slate / zinc theme, subtle blur, boxed widgets, clean tabs. This fits a homelab operations cockpit: elegant, readable, not visually noisy.

```yaml
theme: dark
color: slate
headerStyle: boxedWidgets
statusStyle: dot
iconStyle: theme
cardBlur: true
fullWidth: true
```

Optional CSS: subtle translucent cards and slightly stronger card borders.

Best for: daily operations, many services, long-term maintainability.

## Option B — Cyber Console

Dark indigo/cyan accent, stronger contrast, more “NOC dashboard” feeling.

```yaml
theme: dark
color: indigo
headerStyle: boxedWidgets
statusStyle: dot
iconStyle: theme
fullWidth: true
```

Best for: techy dashboard vibe, monitoring-heavy layout.

Tradeoff: easier to become visually loud if too many icons/widgets are present.

## Option C — Minimal Pro

Very clean dark or light theme, less decoration, maximum readability.

```yaml
theme: dark
color: zinc
headerStyle: clean
statusStyle: dot
iconStyle: theme
fullWidth: false
```

Best for: fast loading, low visual noise, documentation-like dashboard.

Tradeoff: less personality.

## Option D — Glass Mansion

Background image or gradient, card blur, elegant “home portal” style.

```yaml
theme: dark
color: blue
headerStyle: boxedWidgets
statusStyle: dot
iconStyle: theme
cardBlur: true
background:
  image: /images/background.webp
  blur: sm
  saturate: 50
  brightness: 50
  opacity: 50
```

Best for: beautiful personal homepage.

Tradeoff: background image needs asset management and can reduce readability if overdone.

## Option E — Service Catalog Classic

Compact grid, many groups, utilitarian operations view.

```yaml
theme: dark
color: neutral
headerStyle: clean
statusStyle: basic
iconStyle: theme
fullWidth: true
maxGroupColumns: 5
```

Best for: very large service count.

Tradeoff: less visually polished.

## Recommended choice for Phase 2

Start with **Option A — Obsidian Glass**. It is the safest default for a large service catalog: polished enough to feel good, restrained enough to stay readable, and does not require custom assets.

If DF later wants stronger atmosphere, move from Option A to Option D by adding a background image and a slightly more decorative `custom.css`.
