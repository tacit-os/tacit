#!/usr/bin/env python3
"""gnome-keyring's own wording of its unlock ask, in English and in every language it is installed with, as JSON:
{"named": [...], "login": [...]}. "named" is the description that names the keyring, with %s where the name goes ('An
application wants access to the keyring “%s”, but it is locked'); "login" is the login keyring's own sentence.

gnome-keyring translates its prompts, so Keyring.qml tells its unlock ask from gpg's or an ssh key's (which come
through the same prompter, and on a German login also name a key in »...«) by these words, in whichever language the
person's gnome-keyring speaks. Reads the catalogues only; asks the keyring nothing."""
import glob, gettext, json, re

NAMED = "An application wants access to the keyring “%s”, but it is locked"
LOGIN = "The login keyring did not get unlocked when you logged into your computer."

named, login = {NAMED}, {LOGIN}
for mo in glob.glob("/usr/share/locale/*/LC_MESSAGES/gnome-keyring.mo"):
    try:
        with open(mo, "rb") as f:
            t = gettext.GNUTranslations(f)
    except Exception:
        continue  # an unreadable catalogue is one language fewer
    n = re.sub(r"%1\$s", "%s", t.gettext(NAMED))
    if n.count("%s") == 1:
        named.add(n)
    login.add(t.gettext(LOGIN))
print(json.dumps({"named": sorted(named), "login": sorted(login)}, ensure_ascii=False))
