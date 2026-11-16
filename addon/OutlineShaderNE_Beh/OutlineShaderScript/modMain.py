# -*- coding: utf-8 -*-
"""
Outline Shader NE - ModSDK entry point.

Only the client matters for rendering/settings, but an empty InitServer is kept
so that every NetEase SDK build recognises the mod as a normal two-sided Mod.
"""

# Printed before any SDK import: if this line is missing from the log, the engine
# never imported modMain.py, i.e. the behavior pack itself is not loaded.
print("[OutlineShaderNE] modMain.py executing")

try:
    from mod.common.mod import Mod
except ImportError:  # very old SDK layout
    from common.mod import Mod

try:
    import mod.client.extraClientApi as clientApi
except ImportError:  # very old SDK layout
    import client.extraClientApi as clientApi

MOD_NAME = "OutlineShaderNE"
MOD_VERSION = "1.0.0"
SCRIPT_ROOT = "OutlineShaderScript"

print("[OutlineShaderNE] modMain.py imported")


@Mod.Binding(name=MOD_NAME, version=MOD_VERSION)
class OutlineShaderNEMod(object):

    @Mod.InitServer()
    def init_server(self):
        # Nothing is needed on the server side.
        pass

    @Mod.InitClient()
    def init_client(self):
        clientApi.RegisterSystem(
            MOD_NAME,
            "OutlineShaderNEClient",
            SCRIPT_ROOT + ".OutlineShaderNEClient.OutlineShaderNEClient"
        )
        print("[OutlineShaderNE] mod init (client)")

    @Mod.DestroyServer()
    def destroy_server(self):
        pass

    @Mod.DestroyClient()
    def destroy_client(self):
        pass
