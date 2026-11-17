# -*- coding: utf-8 -*-
"""
LSOutlineShaderNE - global player preferences.

NetEase ModSDK does not expose a component literally named PlayerPrefs on the
client.  Its documented global key/value store is ConfigClient with
isGlobal=True: True = global (shared by all saves), False = per-save.

This wrapper keeps the mod's settings in one global dict and migrates the old
pre-LS config key on first run.
"""

import mod.client.extraClientApi as clientApi

PREF_NAME = "ls_outline_shader_ne_settings_v1"
LEGACY_NAMES = (
    "outline_shader_ne_settings_v1",  # key used before the LS rename
)


class LSPrefs(object):

    def __init__(self):
        self._comp = None

    def _get_comp(self):
        if self._comp is None:
            try:
                self._comp = clientApi.GetEngineCompFactory().CreateConfigClient(
                    clientApi.GetLevelId()
                )
            except Exception as exc:
                print("[LSOutlineShaderNE] CreateConfigClient failed: %s" % exc)
        return self._comp

    def load(self):
        comp = self._get_comp()
        if comp is None:
            return {}

        data = None
        try:
            data = comp.GetConfigData(PREF_NAME, True)
        except Exception as exc:
            print("[LSOutlineShaderNE] PlayerPrefs GetConfigData failed: %s" % exc)

        if isinstance(data, dict) and data:
            return data

        for legacy in LEGACY_NAMES:
            old = None
            try:
                old = comp.GetConfigData(legacy, True)
            except Exception:
                old = None
            if isinstance(old, dict) and old:
                print("[LSOutlineShaderNE] migrating global settings from %s" % legacy)
                self.save(old)
                return old
        return {}

    def save(self, values):
        comp = self._get_comp()
        if comp is None:
            return False
        try:
            ok = comp.SetConfigData(PREF_NAME, dict(values), True)
        except Exception as exc:
            print("[LSOutlineShaderNE] PlayerPrefs SetConfigData failed: %s" % exc)
            return False
        if ok is False:
            print("[LSOutlineShaderNE] PlayerPrefs SetConfigData returned False")
        return ok is not False

    def clear(self):
        return self.save({})
