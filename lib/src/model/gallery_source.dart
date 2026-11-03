/// Identifies which site a gallery belongs to.
///
/// Acervo H&C was written for E-Hentai only. This enum lets external sources
/// (8muses, Xlecx) reuse the same models, database tables and reader without
/// touching the E-H code paths.
///
/// The source is encoded in [GalleryUrl.gid] itself instead of adding a column
/// to the database: E-Hentai gids are currently around 4.6M, so any gid at or
/// above [eightMusesGidOffset] is unambiguously an external gallery. Each
/// external source gets its own offset block, so the ranges never overlap.
/// That keeps the drift schema (and every migration) untouched.
enum GallerySource { eh, eightMuses, xlecx }

/// First gid handed out to 8muses galleries.
const int eightMusesGidOffset = 2000000000;

/// First gid handed out to Xlecx galleries (kept above the 8muses block).
const int xlecxGidOffset = 2100000000;

/// Encode an 8muses gallery id as an Acervo H&C gid.
int eightMusesGid(int externalId) => eightMusesGidOffset + externalId;

/// Decode an 8muses gallery id from an Acervo H&C gid, or null for other galleries.
int? eightMusesExternalId(int? gid) {
  if (gid == null || gid < eightMusesGidOffset || gid >= xlecxGidOffset) {
    return null;
  }
  return gid - eightMusesGidOffset;
}

/// Encode a Xlecx gallery id as an Acervo H&C gid.
int xlecxGid(int externalId) => xlecxGidOffset + externalId;

/// Decode a Xlecx gallery id from an Acervo H&C gid, or null for other galleries.
int? xlecxExternalId(int? gid) {
  if (gid == null || gid < xlecxGidOffset) {
    return null;
  }
  return gid - xlecxGidOffset;
}

/// Which source produced [gid].
GallerySource sourceOfGid(int? gid) {
  if (gid == null) {
    return GallerySource.eh;
  }
  if (gid >= xlecxGidOffset) {
    return GallerySource.xlecx;
  }
  if (gid >= eightMusesGidOffset) {
    return GallerySource.eightMuses;
  }
  return GallerySource.eh;
}
