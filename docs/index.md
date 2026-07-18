---
hide:
  - navigation
  - toc
---

<div class="saf-hero" markdown>

# saf

<p class="tagline">One class for the Android Storage Access Framework — pickers, persisted permissions, file management, streaming read/write, recursive walk, and progress.</p>

<div class="saf-badges">
  <span>Flutter ≥ 3.10</span>
  <span>Dart ≥ 3.0</span>
  <span>minSdk 21</span>
  <span>pana 150/150</span>
  <span>MIT</span>
</div>

</div>

```dart
final saf = Saf();

final dir = await saf.pickDirectory();          // one prompt, persists across restarts
if (dir == null) return;

for (final f in await saf.list(dir.uri)) {
  print('${f.name} · ${f.length} B · ${f.mimeType}');
}

final doc = await saf.writeFileBytes(
    dir.uri, 'hello.txt', 'text/plain', utf8.encode('hi') as Uint8List);
final bytes = await saf.readFileBytes(doc.uri);
```

<div class="saf-features" markdown>

<div class="card" markdown>
### 📂 One package
Everything SAF in a single `Saf` class — no pairing two libraries.
</div>

<div class="card" markdown>
### 🔒 Persisted permissions
Grant once, reuse across app restarts. List grants with `persistedPermissions()`.
</div>

<div class="card" markdown>
### 🌊 Streaming I/O
`readFileStream` and one-call `writeFileStream` for large files — no session bookkeeping.
</div>

<div class="card" markdown>
### 🚶 Recursive walk
`walk()` streams a whole directory tree; `copyTo`/`moveTo` recurse with progress.
</div>

<div class="card" markdown>
### 🎯 Typed errors
`SafPermissionException`, `SafNotFoundException`, … instead of raw `PlatformException`.
</div>

<div class="card" markdown>
### 📱 Broad support
Dart ≥ 3.0, Flutter ≥ 3.10, Android minSdk 21 — wider than the alternatives.
</div>

</div>

## Where to next

- **[Install & first run](getting-started.md)** — add the dependency and grant your first directory.
- **[Recipes](guide.md)** — copy-paste snippets for every operation.
- **[Migrate](migration.md)** — from saf 1.x.
- **[Architecture](architecture.md)** — how the Dart facade talks to the Kotlin SAF layer.
- **[API reference](https://jvoltci.github.io/saf/api/)** — the full generated dartdoc.
