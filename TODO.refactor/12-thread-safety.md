# 12 — Thread safety

Priority: covered by track 01.
Status: n/a.

The `Registry` base class introduced in track 01 includes `Mutex`-based
synchronization around mutations (`register`, `reset!`). All migrated
registries inherit this for free. No standalone work.
