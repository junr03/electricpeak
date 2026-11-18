{ lib }:
let
  enabled = profile: entries:
    lib.filter (entry: !(entry ? profiles) || lib.elem profile entry.profiles) entries;
in
{
  # Package values for the entries enabled for the profile.
  select =
    {
      profile,
      entries,
    }:
    map (entry: entry.name) (enabled profile entries);

  # Names of enabled entries marked `unfree = true`, for allowUnfreePredicate.
  unfreeNames =
    {
      profile,
      entries,
    }:
    map (entry: lib.getName entry.name) (
      lib.filter (entry: entry.unfree or false) (enabled profile entries)
    );
}
