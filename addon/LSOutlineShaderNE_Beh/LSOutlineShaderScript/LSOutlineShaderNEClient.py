# -*- coding: utf-8 -*-
"""
Outline Shader NE - client system.

Responsibilities
    1. Register the universal settings page (official Python API) and list every
       option of the original shader pack.
    2. Push the selected values into two NetEase post-process effects as
       EXTRA_VECTOR uniforms (see addon/LSOutlineShaderNE_Res/shaders/glsl/*.fragment).
    3. Persist the values in the local config API so they survive a restart.

Nothing here touches the shader maths: the outline algorithm lives in
ls_outline_shader_ne.fragment and is a line-by-line port of the original final.fsh.
"""

try:
    import mod.client.extraClientApi as clientApi
except ImportError:  # very old SDK layout
    import client.extraClientApi as clientApi

from LSOutlineShaderScript import ShaderSettings as S
from LSOutlineShaderScript.LSPrefs import LSPrefs

ClientSystem = clientApi.GetClientSystemCls()

# The settings page callbacks are module-level so that they keep working after
# a ClientSystem instance is recreated (save exit -> re-enter world).
_ACTIVE = None


def _on_control(*args):
    if _ACTIVE is None:
        return
    if len(args) >= 2:
        key, value = args[0], args[1]
    elif len(args) == 1:
        key, value = None, args[0]
    else:
        return
    if key is None:
        return
    try:
        _ACTIVE.OnControlChanged(key, value)
    except Exception as exc:
        print("[LSOutlineShaderNE] settings callback error: %s" % exc)


def _on_open(*args):
    print("[LSOutlineShaderNE] open settings button clicked")
    if _ACTIVE is None:
        return
    try:
        _ACTIVE.OpenCustomUI()
    except Exception as exc:
        print("[LSOutlineShaderNE] open custom UI failed: %s" % exc)


class LSOutlineShaderNEClient(ClientSystem):

    def __init__(self, namespace, systemName):
        ClientSystem.__init__(self, namespace, systemName)

        global _ACTIVE
        _ACTIVE = self

        self._values = S.default_values()
        self._prefs = LSPrefs()
        self._post_comp = None
        self._setting_inst = None
        self._ui_ready = False
        self._ui_tries = 0
        self._processes_ready = False
        self._ticks = 0
        self._warned = False
        self._dirty = False
        self._ui_logged = False
        self._post_logged = False
        self._add_logged = set()
        self._params_logged = False
        self._ui_registered = False
        self._pending_push_check = False
        self._push_check_tick = 0
        self._push_retried = False
        self._custom_ui_open = False

        self._load_config()

        self.ListenForEvent(
            clientApi.GetEngineNamespace(),
            clientApi.GetEngineSystemName(),
            "UiInitFinished",
            self,
            self.OnUiInitFinished
        )
        self.ListenForEvent(
            clientApi.GetEngineNamespace(),
            clientApi.GetEngineSystemName(),
            "OnScriptTickClient",
            self,
            self.OnScriptTickClient
        )
        self.ListenForEvent(
            clientApi.GetEngineNamespace(),
            clientApi.GetEngineSystemName(),
            "OnKeyPressInGame",
            self,
            self.OnKeyPressInGame
        )
        self.ListenForEvent(
            clientApi.GetEngineNamespace(),
            clientApi.GetEngineSystemName(),
            "DimensionChangeFinishClientEvent",
            self,
            self.DimensionChangeFinishClientEvent
        )
        print("[LSOutlineShaderNE] client system ready")

    # ------------------------------------------------------------------ events
    def RegisterCustomUI(self):
        if self._ui_registered:
            return
        try:
            ok = clientApi.RegisterUI(
                S.MOD_NAMESPACE,
                S.UI_KEY,
                "LSOutlineShaderScript.LSOutlineShaderUIScreen.LSOutlineShaderUIScreen",
                S.UI_JSON_DEF
            )
            print("[LSOutlineShaderNE] RegisterUI -> %s" % (ok,))
            if ok is False or ok == 0:
                print("[LSOutlineShaderNE] RegisterUI returned failure")
            else:
                self._ui_registered = True
        except Exception as exc:
            print("[LSOutlineShaderNE] RegisterUI failed: %s" % exc)

    def OnUiInitFinished(self, args):
        # The config component can be unavailable during __init__; try again now.
        print("[LSOutlineShaderNE] UI init finished")
        self._load_config()
        self.RegisterCustomUI()
        self._ui_ready = False
        self.RegisterSettings()
        self.Apply()

    def DimensionChangeFinishClientEvent(self, args):
        print("[LSOutlineShaderNE] dimension change finished")
        self.CloseCustomUI() #这里是解决跨纬度打不开UI的bug的核心，看来在比特萝卜上班的经验还是很有用的哈

    def OnKeyPressInGame(self, args):
        if str(args.get("key", "")) != "27" or not args.get("isDown"): #key 27 是 ESC
            return
        if not self._custom_ui_open:
            return
        print("[LSOutlineShaderNE] ESC pressed, closing custom UI")
        self.CloseCustomUI()

    def CloseCustomUI(self):
        self._save_config()
        self._custom_ui_open = False
        
        try:
            ui = clientApi.GetUI(S.MOD_NAMESPACE, S.UI_KEY)
            if ui is not None:
                print("[LSOutlineShaderNE] remove custom UI")
                ui.SetRemove()
                return
        except Exception as exc:
            print("[LSOutlineShaderNE] GetUI close failed: %s" % exc)

        try:
            top = str(clientApi.GetTopUI())
            print("[LSOutlineShaderNE] top UI: %s" % top)
            if S.UI_NAMESPACE in top:
                print("[LSOutlineShaderNE] pop custom UI")
                clientApi.PopTopUI()
                return
        except Exception as exc:
            print("[LSOutlineShaderNE] GetTopUI close failed: %s" % exc)

        # PushScreen may report the screen without its namespace; the flag is
        # only set after PushScreen, so popping is safe here.
        try:
            clientApi.PopTopUI()
        except Exception:
            pass

    def OnScriptTickClient(self): #只能说这里面写的东西都很冗余啊，而且会引发很多bug，而且原本传参错了还一直报错
        self._ticks += 1

    # ------------------------------------------------------------------ config
    def _load_config(self):
        data = self._prefs.load()
        if not isinstance(data, dict):
            return
        for key, value in data.items():
            if key not in self._values:
                continue
            spec = S.CONTROL_MAP.get(key)
            if spec is None:
                continue
            if spec.get("hidden") and key != "OUTLINE_MODE":
                # Hidden options are fixed at their defaults; do not restore an
                # old saved value (e.g. texture outlines from a previous build).
                # OUTLINE_MODE is hidden from the UI but still the real value
                # behind the 内侧/外侧 option toggles, so it is restored.
                continue
            if spec["kind"] == "toggle":
                self._values[key] = S.bool_value(value)
            elif spec["kind"] == "slider":
                try:
                    self._values[key] = int(value)
                except (TypeError, ValueError):
                    pass
            elif spec["kind"] == "dropdown":
                self._values[key] = S.dropdown_index(spec, value)

        self._sync_outline_toggles()

    def _sync_outline_toggles(self):
        try:
            mode = int(self._values.get("OUTLINE_MODE", 0))
        except (TypeError, ValueError):
            mode = 0
        mode = 1 if mode == 1 else 0
        self._values["OUTLINE_MODE"] = mode
        self._values["OUTLINE_MODE_INSIDE"] = (mode == 0)
        self._values["OUTLINE_MODE_OUTSIDE"] = (mode == 1)

    def _save_config(self):
        ok = self._prefs.save(self._values)
        if ok:
            self._dirty = False
        return ok

    # -------------------------------------------------------------------- post
    def _get_post_comp(self):
        if self._post_comp is None:
            try:
                self._post_comp = clientApi.GetEngineCompFactory().CreatePostProcess(
                    clientApi.GetLevelId()
                )
            except Exception as exc:
                print("[LSOutlineShaderNE] CreatePostProcess failed: %s" % exc)
        return self._post_comp

    def _ensure_processes(self, post):
        if self._processes_ready:
            return True
        try:
            order = post.GetPostProcessOrder()
        except Exception as exc:
            order = None
            print("[LSOutlineShaderNE] GetPostProcessOrder failed: %s" % exc)
        if not order:
            order = []

        if not self._post_logged:
            self._post_logged = True
            print("[LSOutlineShaderNE] post-process order: %s" % (order,))

        if S.PROCESS_SHADOW not in order:
            ok = False
            try:
                ok = post.AddPostProcess(S.build_shadow_process(self._values), -1)
            except Exception as exc:
                print("[LSOutlineShaderNE] AddPostProcess(shadow) failed: %s" % exc)
            if S.PROCESS_SHADOW not in self._add_logged:
                self._add_logged.add(S.PROCESS_SHADOW)
                print("[LSOutlineShaderNE] AddPostProcess(shadow) -> %s" % ok)

        if S.PROCESS_OUTLINE not in order:
            ok = False
            try:
                ok = post.AddPostProcess(S.build_outline_process(self._values), -1)
            except Exception as exc:
                print("[LSOutlineShaderNE] AddPostProcess(outline) failed: %s" % exc)
            if S.PROCESS_OUTLINE not in self._add_logged:
                self._add_logged.add(S.PROCESS_OUTLINE)
                print("[LSOutlineShaderNE] AddPostProcess(outline) -> %s" % ok)

        self._processes_ready = True
        return True

    def Apply(self):
        post = self._get_post_comp()
        if post is None:
            return

        self._ensure_processes(post)

        values = self._values
        outline_a, outline_b, outline_c = S.outline_params(values)
        shadow_a, shadow_b = S.shadow_params(values)

        # Make sure both effects are enabled while writing parameters: some
        # builds reject SetParameter on a switched-off custom post-process.
        try:
            post.SetEnableByName(S.PROCESS_OUTLINE, True)
            post.SetEnableByName(S.PROCESS_SHADOW, True)
        except Exception:
            pass

        ok = True
        try:
            ok = post.SetParameter(S.PROCESS_OUTLINE, "p_outline_a", outline_a) and ok
            ok = post.SetParameter(S.PROCESS_OUTLINE, "p_outline_b", outline_b) and ok
            ok = post.SetParameter(S.PROCESS_OUTLINE, "p_outline_c", outline_c) and ok
            ok = post.SetParameter(S.PROCESS_SHADOW, "p_shadow_a", shadow_a) and ok
            ok = post.SetParameter(S.PROCESS_SHADOW, "p_shadow_b", shadow_b) and ok
        except Exception as exc:
            print("[LSOutlineShaderNE] SetParameter failed: %s" % exc)
            ok = False

        if not ok:
            # The effects may not exist yet (or were reset); retry next tick.
            self._processes_ready = False
            if not self._warned:
                self._warned = True
                print("[LSOutlineShaderNE] post-process not ready yet; retrying")
        elif not self._params_logged:
            self._params_logged = True
            print("[LSOutlineShaderNE] post-process parameters applied")

        master = S.bool_value(values.get("MASTER", True))
        shadow_wanted = master and (
            S.bool_value(values.get("ENABLE_SHADOWS", False)) or
            S.option_value(S.CONTROL_MAP["Shininess"], values.get("Shininess", 0)) > 0.0
        )
        try:
            post.SetEnableByName(S.PROCESS_OUTLINE, master)
            post.SetEnableByName(S.PROCESS_SHADOW, shadow_wanted)
        except Exception as exc:
            print("[LSOutlineShaderNE] SetEnableByName failed: %s" % exc)

    # ------------------------------------------------------------- custom ui
    def get_ui_values(self):
        return self._values

    def set_ui_value(self, key, value):
        self._values[key] = value
        self._dirty = True
        self.Apply()
        self._save_config()

    def set_ui_mode(self, outside):
        self._values["OUTLINE_MODE"] = 1 if outside else 0
        self._values["OUTLINE_MODE_INSIDE"] = not outside
        self._values["OUTLINE_MODE_OUTSIDE"] = outside
        self._dirty = True
        self.Apply()
        self._save_config()

    def OpenCustomUI(self):
        print("[LSOutlineShaderNE] OpenCustomUI (%s)" % S.UI_JSON_DEF)
        import LSOutlineShaderScript.LSOutlineShaderUIScreen as UI
        UI.HOST = self
        self.RegisterCustomUI()
        print("[LSOutlineShaderNE] custom UI registered=%s" % self._ui_registered)

        # Close the universal settings page first, otherwise it would still be
        # behind the custom overlay instead of the game.
        try:
            window_comp = clientApi.GetEngineCompFactory().CreateNeteaseWindow(
                clientApi.GetLevelId()
            )
            result = window_comp.CloseSettingUI()
            print("[LSOutlineShaderNE] CloseSettingUI -> %s" % (result,))
        except Exception as exc:
            print("[LSOutlineShaderNE] CloseSettingUI failed: %s" % exc)

        # If the pause menu is still on the stack, close it so the game (not the
        # pause background) is what the custom overlay is drawn over.
        try:
            clientApi.PopTopUI()
        except Exception:
            pass

        try:
            clientApi.PushScreen(S.MOD_NAMESPACE, S.UI_KEY)
            print("[LSOutlineShaderNE] PushScreen called")
            self._custom_ui_open = True
            self._push_retried = False
            self._pending_push_check = True
            self._push_check_tick = self._ticks
        except Exception as exc:
            print("[LSOutlineShaderNE] PushScreen failed: %s" % exc)

    # ---------------------------------------------------------------------- ui
    def RegisterSettings(self):
        factory = clientApi.GetEngineCompFactory()

        # Different SDK builds accept the level id or the local player id here.
        comp_ids = []
        try:
            comp_ids.append(clientApi.GetLevelId())
        except Exception:
            pass
        try:
            comp_ids.append(clientApi.GetLocalPlayerId())
        except Exception:
            pass

        inst = None
        for comp_id in comp_ids:
            try:
                window_comp = factory.CreateNeteaseWindow(comp_id)
                inst = window_comp.RegisterSettingInst(
                    S.MOD_NAMESPACE, S.api_text(S.MOD_DISPLAY_NAME), S.MOD_ICON
                )
            except Exception as exc:
                print("[LSOutlineShaderNE] RegisterSettingInst(%s) failed: %s" % (comp_id, exc))
                inst = None
            if inst:
                break

        if not inst:
            if not self._ui_logged:
                self._ui_logged = True
                print("[LSOutlineShaderNE] RegisterSettingInst returned None "
                      "(settings page unavailable: check namespace/itemId)")
            return

        self._setting_inst = inst
        self._ui_ready = True

        try:
            inst.Clear()
        except Exception:
            pass

        try:
            inst.AddButton("open_settings", S.api_text(u"----"),
                           S.api_text(u"打开设置"), _on_open, 0)
            inst.AddText("entry_brand", S.api_text(u"LoongLy Software 2026"), 1)
        except Exception as exc:
            print("[LSOutlineShaderNE] add entry controls failed: %s" % exc)

        print("[LSOutlineShaderNE] entry page registered")

    def _set_outline_mode(self, outside, enabled):
        """内侧/外侧 option toggles: exactly one of them is always selected."""
        if not S.bool_value(enabled):
            # Re-select the active option instead of allowing "none".
            if self._setting_inst is not None:
                try:
                    self._setting_inst.SetToggleValue(
                        "OUTLINE_MODE_OUTSIDE" if outside else "OUTLINE_MODE_INSIDE",
                        True
                    )
                except Exception:
                    pass
            return

        self._values["OUTLINE_MODE"] = 1 if outside else 0
        self._values["OUTLINE_MODE_INSIDE"] = not outside
        self._values["OUTLINE_MODE_OUTSIDE"] = outside

        if self._setting_inst is not None:
            try:
                self._setting_inst.SetToggleValue("OUTLINE_MODE_INSIDE", not outside)
                self._setting_inst.SetToggleValue("OUTLINE_MODE_OUTSIDE", outside)
            except Exception:
                pass

        self._dirty = True
        self.Apply()
        self._save_config()

    def OnControlChanged(self, key, value):
        spec = S.CONTROL_MAP.get(key)
        if spec is None or spec["kind"] == "text" or spec.get("hidden"):
            return

        if key in ("OUTLINE_MODE_INSIDE", "OUTLINE_MODE_OUTSIDE"):
            self._set_outline_mode(key == "OUTLINE_MODE_OUTSIDE", value)
            return

        if spec["kind"] == "toggle":
            self._values[key] = S.bool_value(value)
        elif spec["kind"] == "slider":
            try:
                index = int(value)
            except (TypeError, ValueError):
                return
            self._values[key] = index
        elif spec["kind"] == "dropdown":
            self._values[key] = S.dropdown_index(spec, value)
        else:
            return

        # Mark dirty and write immediately; the tick flush is only a fallback.
        self._dirty = True
        self.Apply()
        self._save_config()
