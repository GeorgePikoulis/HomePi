# Manual Import of Legacy Media into the *-arr Ecosystem

This document describes the **safe, repeatable procedure** for importing existing / legacy movies, TV series, and music into the *-arr* family (Radarr, Sonarr, Lidarr).

The goal is to **preserve files**, allow correct identification, and let the *-arr* applications take ownership of naming, structure, and metadata.

---

## 1. Core Principles

* *-arr tools **do not watch arbitrary folders***
* Media must be **imported**, not copied blindly
* Root folders are **owned** by the *-arr app
* Imports should be **interactive** when filenames are uncertain

---

## 2. Recommended Folder Layout

### Managed media roots

```
/media
├── movies        # Radarr root
├── series        # Sonarr root
└── music         # Lidarr root
```

These folders are **managed exclusively** by the respective *-arr* application.

---

### Temporary import location (legacy media)

```
/import
├── old_movies
├── old_series
└── old_music
```

Reasons for a separate import folder:

* Prevent accidental deletion
* Allow preview & correction of matches
* Enable hardlinks if supported

---

## 3. Pre‑Import Settings Checklist

### Media Management (all apps)

* Enable **Hardlinks instead of Copy** (same filesystem)
* Disable **Delete Empty Folders** (initial import)
* Disable **Automatic Upgrades** (initial import)

### Quality Profiles

Create a temporary **Legacy Import** profile:

* Accept all qualities
* No upgrades

Tighten profiles **after** import is complete.

---

## 4. Import Procedures

---

## 4.1 Radarr — Movies

**Path:**

```
Radarr → Movies → Library Import
```

Steps:

1. Select `/import/old_movies`
2. Enable **Interactive Import**
3. Choose **Copy** (safest) or **Move**
4. Verify movie matches (TMDB)
5. Confirm import

Result:

* Files renamed
* Correct folder structure created
* Metadata fetched

---

## 4.2 Sonarr — TV Series

**Path:**

```
Sonarr → Series → Import Existing Series on Disk
```

Expected structure (ideal):

```
Show Name/
  Season 01/
    S01E01.ext
```

Notes:

* Sonarr is **strict** about naming
* For messy collections:

  * Use **Manual Import**
  * Import one series at a time

---

## 4.3 Lidarr — Music

**Path:**

```
Lidarr → Artist → Import Existing Music
```

Recommended options:

* Enable **Prefer Accurate Track Data**
* Enable **Fix Track Numbers**
* Enable **MusicBrainz Sync**

Lidarr will:

* Identify artists & albums
* Re-tag files
* Normalize album structures

---

## 5. Jellyfin / Plex Integration

After imports complete:

1. Trigger **Scan All Libraries** in Jellyfin / Plex
2. Libraries should point only to:

```
/media/movies
/media/series
/media/music
```

Never point Jellyfin/Plex to `/import`.

---

## 6. Common Mistakes (Avoid)

* Dropping files directly into managed root folders
* Letting *-arr* monitor random directories
* Enabling upgrades during initial import
* Mixing multiple movies in one folder
* Expecting filenames alone to be sufficient (especially for music)

---

## 7. Recommended Import Order

1. **Music (Lidarr)** — safest, fully reversible
2. **Movies (Radarr)** — forgiving matching
3. **TV Series (Sonarr)** — strictest rules

---

## 8. Post‑Import Cleanup

After everything is verified:

* Enable upgrades
* Tighten quality profiles
* Remove `/import` directory
* Enable automatic organization

---

## 9. Notes

This workflow mirrors professional media archive migrations and minimizes risk of data loss while ensuring clean, standardized libraries.

---

**Last reviewed:** 2025‑12‑17 11:00 (EET)
