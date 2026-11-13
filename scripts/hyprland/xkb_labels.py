#!/usr/bin/env python3
# What each key of the on-screen keyboard types in the compositor's layout, read from the keymap by libxkbcommon (which
# Hyprland and Qt use), for a layout the keyboard has no labels of its own for (layouts.js). Its keys send scancodes, so
# a French keymap types "a" on the key that a US label calls "q".
#   xkb_labels.py <layouts> <variants> <active name> [keycode...]
# The layouts and variants as Hyprland has them ("us,fr", ",azerty"), the active one by the name Hyprland gives it
# ("French (AZERTY)"). Prints {"<evdev keycode>": [label, label with Shift], ...}; exits 1 when the name is not one of the
# layouts or the keymap cannot be made.
import ctypes
import json
import sys
import unicodedata

# a dead key types nothing by itself: shown as the accent it adds
DEAD = {"grave": "`", "acute": "´", "circumflex": "^", "tilde": "~", "macron": "¯", "breve": "˘", "abovedot": "˙",
        "diaeresis": "¨", "abovering": "°", "doubleacute": "˝", "caron": "ˇ", "cedilla": "¸", "ogonek": "˛"}
ALTGR = {"ISO_Level3_Shift": "AltGr", "Mode_switch": "AltGr"}


class RuleNames(ctypes.Structure):
    _fields_ = [(f, ctypes.c_char_p) for f in ("rules", "model", "layout", "variant", "options")]


def labels(layouts, variants, name, keycodes):
    xkb = ctypes.CDLL("libxkbcommon.so.0")
    xkb.xkb_context_new.restype = xkb.xkb_keymap_new_from_names.restype = xkb.xkb_state_new.restype = ctypes.c_void_p
    xkb.xkb_keymap_new_from_names.argtypes = [ctypes.c_void_p, ctypes.POINTER(RuleNames), ctypes.c_int]
    xkb.xkb_keymap_layout_get_name.restype = ctypes.c_char_p
    xkb.xkb_keymap_layout_get_name.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
    xkb.xkb_keymap_num_layouts.argtypes = [ctypes.c_void_p]
    xkb.xkb_keymap_mod_get_index.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
    xkb.xkb_state_new.argtypes = [ctypes.c_void_p]
    xkb.xkb_state_update_mask.argtypes = [ctypes.c_void_p] + [ctypes.c_uint32] * 6
    xkb.xkb_state_key_get_utf8.argtypes = [ctypes.c_void_p, ctypes.c_uint32, ctypes.c_char_p, ctypes.c_size_t]
    xkb.xkb_state_key_get_one_sym.restype = ctypes.c_uint32
    xkb.xkb_state_key_get_one_sym.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
    xkb.xkb_keysym_get_name.argtypes = [ctypes.c_uint32, ctypes.c_char_p, ctypes.c_size_t]

    ctx = xkb.xkb_context_new(0)
    names = RuleNames(None, None, layouts.encode(), variants.encode(), None)
    keymap = ctx and xkb.xkb_keymap_new_from_names(ctx, ctypes.byref(names), 0)
    if not keymap:
        return None
    group = next((g for g in range(xkb.xkb_keymap_num_layouts(keymap))
                  if (xkb.xkb_keymap_layout_get_name(keymap, g) or b"").decode() == name), None)
    if group is None:
        return None
    state = xkb.xkb_state_new(keymap)
    shift = 1 << xkb.xkb_keymap_mod_get_index(keymap, b"Shift")
    buf = ctypes.create_string_buffer(64)

    def label(code, mods):
        xkb.xkb_state_update_mask(state, mods, 0, 0, 0, 0, group)
        xkb.xkb_state_key_get_utf8(state, code + 8, buf, len(buf))     # xkb's keycodes are evdev's plus 8
        text = buf.value.decode(errors="replace")
        if text and not any(unicodedata.category(c).startswith(("C", "Z")) for c in text):
            return text
        xkb.xkb_keysym_get_name(xkb.xkb_state_key_get_one_sym(state, code + 8), buf, len(buf))
        sym = buf.value.decode()
        return DEAD.get(sym.removeprefix("dead_"), "") if sym.startswith("dead_") else ALTGR.get(sym, "")

    return {str(code): [label(code, 0), label(code, shift)] for code in keycodes}


if __name__ == "__main__":
    if len(sys.argv) < 4:
        sys.exit("usage: xkb_labels.py <layouts> <variants> <active name> [keycode...]")
    out = labels(sys.argv[1], sys.argv[2], sys.argv[3], [int(k) for k in sys.argv[4:]] or range(1, 249))
    if not out:
        sys.exit(1)
    print(json.dumps(out, ensure_ascii=False))
