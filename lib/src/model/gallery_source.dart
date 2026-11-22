/// Identifies which site a gallery belongs to.
///
/// Acervo H&C was written for E-Hentai only. This enum lets the external
/// source (Xlecx) reuse the same models, database tables and reader without
/// touching the E-H code paths.
///
/// The source is encoded in [GalleryUrl.gid] itself instead of adding a column
/// to the database: E-Hentai gids are currently around 4.6M, so any gid at or
/// above [nhentaiGidOffset] is unambiguously an external gallery.
enum GallerySource { eh, xlecx, nhentai }

/// First gid handed out to nhentai galleries (`[2_000_000_000, 2_100_000_000)`).
const int nhentaiGidOffset = 2000000000;

/// First gid handed out to Xlecx galleries (`>= 2_100_000_000`).
const int xlecxGidOffset = 2100000000;

/// Encode a Xlecx gallery id as an Acervo H&C gid.
int xlecxGid(int externalId) => xlecxGidOffset + externalId;

/// Encode an nhentai gallery id as an Acervo H&C gid.
int nhentaiGid(int externalId) => nhentaiGidOffset + externalId;

/// Which source produced [gid].
GallerySource sourceOfGid(int? gid) {
  if (gid == null) {
    return GallerySource.eh;
  }
  if (gid >= xlecxGidOffset) {
    return GallerySource.xlecx;
  }
  if (gid >= nhentaiGidOffset) {
    return GallerySource.nhentai;
  }
  return GallerySource.eh;
}
