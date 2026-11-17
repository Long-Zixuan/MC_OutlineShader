# -*- coding: utf-8 -*-
"""
Outline Shader NE - client system.

Responsibilities
    1. Register the universal settings page (official Python API) and list every
       option of the original shader pack.
    2. Push the selected values into two NetEase post-process effects as
       EXTRA_VECTOR uniforms (see addon/OutlineShaderNE_Res/shaders/glsl/*.fragment).
    3. Persist the values in the local config API so they survive a restart.

Nothing here touches the shader maths: the outline algorithm lives in
outline_shader_ne.fragment and is a line-by-line port of the original final.fsh.
"""

try:
    import mod.client.extraClientApi as clientApi
except ImportError:  # very old SDK layout
    import client.extraClientApi as clientApi

from OutlineShaderScript import ShaderSettings as S

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
        print("[OutlineShaderNE] settings callback error: %s" % exc)


class OutlineShaderNEClient(ClientSystem):

    def __init__(self, namespace, systemName):
        ClientSystem.__init__(self, namespace, systemName)

        global _ACTIVE
        _ACTIVE = self

        self._values = S.default_values()
        self._config_comp = None
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
        print("[OutlineShaderNE] client system ready")

    # ------------------------------------------------------------------ events
    def OnUiInitFinished(self, args):
        # The config component can be unavailable during __init__; try again now.
        self._load_config()
        self._ui_ready = False
        self.RegisterSettings()
        self.Apply()

    def OnScriptTickClient(self, args):
        self._ticks += 1

        # UiInitFinished can be missed on some builds; retry gently.
        if not self._ui_ready and self._ticks % 20 == 0 and self._ui_tries < 60:
            self._ui_tries += 1
            self.RegisterSettings()

        # AddPostProcess may fail while the world is still loading; retry.
        if not self._processes_ready and self._ticks % 40 == 0:
            self.Apply()

        # Re-assert values now and then (world reload / dimension change).
        if self._processes_ready and self._ticks % 150 == 0:
            self.Apply()

        # Slider callbacks can fire every frame; write the config on a timer.
        if self._dirty and self._ticks % 20 == 0:
            self._save_config()
            self._dirty = False

    # ------------------------------------------------------------------ config
    def _get_config_comp(self):
        if self._config_comp is None:
            try:
                self._config_comp = clientApi.GetEngineCompFactory().CreateConfigClient(
                    clientApi.GetLevelId()
                )
            except Exception as exc:
                print("[OutlineShaderNE] CreateConfigClient failed: %s" % exc)
        return self._config_comp

    def _load_config(self):
        comp = self._get_config_comp()
        if comp is None:
            return
        try:
            data = comp.GetConfigData(S.CFG_NAME, True)
        except Exception as exc:
            print("[OutlineShaderNE] GetConfigData failed: %s" % exc)
            return
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
        comp = self._get_config_comp()
        if comp is None:
            return
        try:
            comp.SetConfigData(S.CFG_NAME, dict(self._values), True)
        except Exception as exc:
            print("[OutlineShaderNE] SetConfigData failed: %s" % exc)

    # -------------------------------------------------------------------- post
    def _get_post_comp(self):
        if self._post_comp is None:
            try:
                self._post_comp = clientApi.GetEngineCompFactory().CreatePostProcess(
                    clientApi.GetLevelId()
                )
            except Exception as exc:
                print("[OutlineShaderNE] CreatePostProcess failed: %s" % exc)
        return self._post_comp

    def _ensure_processes(self, post):
        if self._processes_ready:
            return True
        try:
            order = post.GetPostProcessOrder()
        except Exception as exc:
            order = None
            print("[OutlineShaderNE] GetPostProcessOrder failed: %s" % exc)
        if not order:
            order = []

        if not self._post_logged:
            self._post_logged = True
            print("[OutlineShaderNE] post-process order: %s" % (order,))

        if S.PROCESS_SHADOW not in order:
            ok = False
            try:
                ok = post.AddPostProcess(S.build_shadow_process(self._values), -1)
            except Exception as exc:
                print("[OutlineShaderNE] AddPostProcess(shadow) failed: %s" % exc)
            if S.PROCESS_SHADOW not in self._add_logged:
                self._add_logged.add(S.PROCESS_SHADOW)
                print("[OutlineShaderNE] AddPostProcess(shadow) -> %s" % ok)

        if S.PROCESS_OUTLINE not in order:
            ok = False
            try:
                ok = post.AddPostProcess(S.build_outline_process(self._values), -1)
            except Exception as exc:
                print("[OutlineShaderNE] AddPostProcess(outline) failed: %s" % exc)
            if S.PROCESS_OUTLINE not in self._add_logged:
                self._add_logged.add(S.PROCESS_OUTLINE)
                print("[OutlineShaderNE] AddPostProcess(outline) -> %s" % ok)

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
            print("[OutlineShaderNE] SetParameter failed: %s" % exc)
            ok = False

        if not ok:
            # The effects may not exist yet (or were reset); retry next tick.
            self._processes_ready = False
            if not self._warned:
                self._warned = True
                print("[OutlineShaderNE] post-process not ready yet; retrying")
        elif not self._params_logged:
            self._params_logged = True
            print("[OutlineShaderNE] post-process parameters applied")

        master = S.bool_value(values.get("MASTER", True))
        shadow_wanted = master and (
            S.bool_value(values.get("ENABLE_SHADOWS", False)) or
            S.option_value(S.CONTROL_MAP["Shininess"], values.get("Shininess", 0)) > 0.0
        )
        try:
            post.SetEnableByName(S.PROCESS_OUTLINE, master)
            post.SetEnableByName(S.PROCESS_SHADOW, shadow_wanted)
        except Exception as exc:
            print("[OutlineShaderNE] SetEnableByName failed: %s" % exc)

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
                print("[OutlineShaderNE] RegisterSettingInst(%s) failed: %s" % (comp_id, exc))
                inst = None
            if inst:
                break

        if not inst:
            if not self._ui_logged:
                self._ui_logged = True
                print("[OutlineShaderNE] RegisterSettingInst returned None "
                      "(settings page unavailable: check namespace/itemId)")
            return

        self._setting_inst = inst
        self._ui_ready = True

        try:
            inst.Clear()
        except Exception:
            pass

        ui_priority = 0
        for spec in S.CONTROLS:
            if spec.get("hidden"):
                continue
            key = spec["key"]
            label = S.api_text(spec["label"])
            kind = spec["kind"]
            try:
                if kind == "text":
                    inst.AddText(key, label, ui_priority)
                elif kind == "toggle":
                    default = S.bool_value(self._values.get(key, spec["default"]))
                    inst.AddToggle(key, label, _on_control, ui_priority, default)
                elif kind == "slider":
                    options = spec["options"]
                    step = max(1, len(options) - 1)
                    default = int(self._values.get(key, spec["default"]))
                    if default < 0:
                        default = 0
                    if default > step:
                        default = step
                    inst.AddSlider(key, label, step, _on_control, ui_priority, default)
                elif kind == "dropdown":
                    labels = [S.api_text(item) for item in spec["labels"]]
                    default = int(self._values.get(key, spec["default"]))
                    if default < 0:
                        default = 0
                    if default >= len(labels):
                        default = len(labels) - 1
                    inst.AddDropDown(key, label, labels, _on_control, ui_priority,
                                     labels[default])
                else:
                    print("[OutlineShaderNE] unknown control kind: %s" % kind)
            except Exception as exc:
                print("[OutlineShaderNE] Add control %s failed: %s" % (key, exc))
            ui_priority += 1

        print("[OutlineShaderNE] settings page registered (%d controls)" % ui_priority)

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

        # Mark dirty; OnScriptTickClient flushes to disk every 20 ticks so a
        # dragged slider does not write the config file every frame.
        self._dirty = True
        self.Apply()
