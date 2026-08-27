# Where this comes from

`src/`, `native/` and `resources/` are a verbatim copy of the shim in the
**firefox-atl** repository (`jvm-run/shim/`), which is where it is developed and
where `audit.sh` and `NOTES.md` explain what belongs in it and why. Refresh with
`scripts/sync-shim.sh FIREFOX_ATL_DIR`.

`build.sh` here is not that tree's: it drops the two gates that need to *run*
what they check (`tools/JdkRefCheck.java`, `tools/ShimCheck.java`), because this
is a cross build and the `.so` it produces is aarch64. It keeps the two that are
pure inspection — the package allowlist and the exported-symbol list. Run the
upstream `jvm-run/shim/build.sh` when changing a source file; this one only has
to reproduce the same jar.
