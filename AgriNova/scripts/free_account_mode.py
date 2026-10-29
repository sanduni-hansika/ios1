#!/usr/bin/env python3
"""Strips capabilities that need a PAID Apple Developer account (iCloud/CloudKit, Sign in with Apple, App Groups, Push Notifications)
so the app builds with a free Apple ID. Run once, then ./scripts/bootstrap.sh.
Trade-offs: no iCloud sync, no Sign in with Apple, and the widget cannot read live app data
(it shows placeholder data) because App Groups are removed."""
import re, pathlib
p = pathlib.Path(__file__).resolve().parent.parent / "project.yml"
s = p.read_text()
for key in ["com.apple.security.application-groups", "com.apple.developer.icloud-container-identifiers",
            "com.apple.developer.icloud-services", "com.apple.developer.applesignin", "aps-environment"]:
    s = re.sub(r"^\s*%s:.*\n" % re.escape(key), "", s, flags=re.M)
p.write_text(s)
print("Done. Capabilities removed from project.yml – now run ./scripts/bootstrap.sh")
